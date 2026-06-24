// ClaudeWatchApp — a native macOS menu-bar app that mirrors `claude agents`.
//
// What it does (first milestone):
//   • polls `claude agents --json` every 2s (off the main thread)
//   • shows the cross-project session list in the menu bar
//   • posts a NATIVE notification when a session enters waiting/blocked/done/failed
//   • click a row (or the notification) -> opens that project in PhpStorm
//
// This is the Swift port of the validated Python prototype (~/.claude-dash).
// Single file on purpose so it is easy to read while learning; in Xcode you'd
// normally split Model / Notifier / Views into separate files.

import SwiftUI
import AppKit
import UserNotifications

// MARK: - Model

/// One Claude Code session, flattened from `claude agents --json`.
struct AgentSession: Identifiable, Sendable {
    let id: String
    let project: String
    let cwd: String
    let name: String
    let kind: String
    let state: String      // waiting/blocked/working/busy/idle/done/failed/stopped
    let waitingFor: String  // e.g. "permission prompt" when state == waiting
}

@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var lastError: String?

    /// States worth a desktop notification when a session transitions INTO them.
    /// NB: interactive sessions report "waiting" (not "blocked") when they need
    /// you — discovered by testing the Python prototype.
    static let notifyStates: Set<String> = ["blocked", "waiting", "done", "failed"]
    static let attentionStates: Set<String> = ["blocked", "waiting"]

    private var lastStates: [String: String] = [:]
    private var seeded = false
    private var timer: Timer?

    /// Any session currently needing the user — drives the menu-bar icon badge.
    var needsAttention: Bool {
        sessions.contains { Self.attentionStates.contains($0.state) }
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        // Run the CLI off the main actor so the UI never hitches, then hop back.
        Task.detached(priority: .utility) {
            let result = SessionStore.runClaudeAgents()
            await MainActor.run { SessionStore.shared.apply(result) }
        }
    }

    private func apply(_ result: Result<[AgentSession], String>) {
        switch result {
        case .failure(let msg):
            lastError = msg
        case .success(let agents):
            lastError = nil
            sessions = agents.sorted { Self.order($0.state) < Self.order($1.state) }
            detectTransitions(agents)
        }
    }

    private static func order(_ s: String) -> Int {
        switch s {
        case "blocked", "waiting": return 0   // needs you -> top
        case "working", "busy":    return 1
        case "failed":             return 2
        case "done":               return 3
        case "idle":               return 4
        default:                   return 5
        }
    }

    private func detectTransitions(_ agents: [AgentSession]) {
        defer {
            lastStates = Dictionary(agents.map { ($0.id, $0.state) }) { a, _ in a }
            seeded = true
        }
        guard seeded else { return }  // first run: seed only, no startup spam
        for a in agents where Self.notifyStates.contains(a.state) {
            if lastStates[a.id] != a.state { Notifier.fire(for: a) }
        }
    }

    /// Run `claude agents --json` and parse it. nonisolated so it can run on a
    /// background task. Uses a login shell so `claude` (in ~/.local/bin) is found.
    nonisolated static func runClaudeAgents() -> Result<[AgentSession], String> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "claude agents --json"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch {
            return .failure("claude 起動失敗: \(error.localizedDescription)")
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return .success([])  // empty / unparseable -> no sessions
        }
        return .success(arr.map { d in
            let cwd = (d["cwd"] as? String ?? "").trimmedSlash
            let base = (cwd as NSString).lastPathComponent
            return AgentSession(
                id: (d["id"] as? String) ?? (d["sessionId"] as? String) ?? UUID().uuidString,
                project: base.isEmpty ? cwd : base,
                cwd: cwd,
                name: d["name"] as? String ?? "",
                kind: d["kind"] as? String ?? "",
                state: (d["state"] as? String) ?? (d["status"] as? String) ?? "unknown",
                waitingFor: d["waitingFor"] as? String ?? ""
            )
        })
    }
}

private extension String {
    var trimmedSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}

// MARK: - Notifications

enum Notifier {
    static func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func fire(for a: AgentSession) {
        let content = UNMutableNotificationContent()
        switch a.state {
        case "blocked", "waiting":
            content.title = "⚠️ \(a.project) が待っています"
            content.body = a.waitingFor.isEmpty ? "要対応（許可 / 入力）" : a.waitingFor
        case "done":
            content.title = "✅ \(a.project) 完了"
            content.body = a.name.isEmpty ? "セッション完了" : a.name
        case "failed":
            content.title = "❌ \(a.project) 失敗"
            content.body = a.name.isEmpty ? "セッション失敗" : a.name
        default:
            return
        }
        content.sound = .default
        content.userInfo = ["cwd": a.cwd]  // carried so a click can open the project
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// Focus (or open) the project in PhpStorm. JetBrains reuses one window per
/// project, so this brings the existing window forward.
@MainActor
func openInPhpStorm(_ cwd: String) {
    guard !cwd.isEmpty else { return }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
    proc.arguments = ["-lc", "phpstorm \"\(cwd)\""]
    try? proc.run()
}

// MARK: - App lifecycle (notification delegate)

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestAuth()
        SessionStore.shared.start()
    }

    // show banners even while the app is frontmost
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    // clicking the banner opens the project
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let cwd = response.notification.request.content.userInfo["cwd"] as? String ?? ""
        await openInPhpStorm(cwd)
    }
}

// MARK: - UI

@main
struct ClaudeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = SessionStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(systemName: store.needsAttention ? "bell.badge.fill" : "list.bullet.rectangle")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("claude-watch").font(.headline)

            if let err = store.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            if store.sessions.isEmpty {
                Text("アクティブなセッションはありません")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(store.sessions) { s in
                    Button { openInPhpStorm(s.cwd) } label: {
                        HStack(spacing: 8) {
                            Text(emoji(s.state)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.project).bold()
                                Text(info(s)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func emoji(_ state: String) -> String {
        switch state {
        case "blocked", "waiting": return "🔴"
        case "working", "busy":    return "🔵"
        case "failed":             return "❌"
        case "done":               return "🟢"
        default:                   return "⚪️"
        }
    }

    private func info(_ s: AgentSession) -> String {
        let detail = !s.waitingFor.isEmpty ? s.waitingFor
                   : !s.name.isEmpty ? s.name : s.kind
        return detail.isEmpty ? s.state : "\(s.state) · \(detail)"
    }
}