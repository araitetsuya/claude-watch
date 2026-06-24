// Model — データ層（このアプリの「単一の真実」）。
//
//   • AgentSession : `claude agents --json` の1要素を表す構造体（画面表示用）
//   • AgentDTO     : JSON をそのまま受けるデコード用の型（Codable）
//   • PollError    : 失敗を表す簡単なエラー型
//   • SessionStore : セッション一覧を保持し、2秒ごとにポーリングする本体。
//                    @Observable なので、画面はプロパティを読むだけで自動更新される。

import Foundation
import Observation

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

extension AgentSession {
    /// One-line detail: waitingFor > name > kind, falling back to the raw state.
    var detailText: String {
        let detail = !waitingFor.isEmpty ? waitingFor
                   : !name.isEmpty ? name : kind
        return detail.isEmpty ? state : "\(state) · \(detail)"
    }
}

/// Raw shape of one element in `claude agents --json`. Keys are optional because
/// the CLI uses a few aliases (id/sessionId, state/status) we normalise below.
private struct AgentDTO: Decodable {
    let id: String?
    let sessionId: String?
    let cwd: String?
    let name: String?
    let kind: String?
    let state: String?
    let status: String?
    let waitingFor: String?
}

/// A simple error wrapper — Result's failure type must conform to Error.
struct PollError: Error { let message: String }

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    private(set) var sessions: [AgentSession] = []
    private(set) var lastError: String?

    /// States worth a desktop notification when a session transitions INTO them.
    /// NB: interactive sessions report "waiting" (not "blocked") when they need
    /// you — discovered by testing the Python prototype.
    static let notifyStates: Set<String> = ["blocked", "waiting", "done", "failed"]
    static let attentionStates: Set<String> = ["blocked", "waiting"]

    private var lastStates: [String: String] = [:]
    private var seeded = false
    private var pollingTask: Task<Void, Never>?

    /// Any session currently needing the user — drives the menu-bar icon badge.
    var needsAttention: Bool {
        sessions.contains { Self.attentionStates.contains($0.state) }
    }

    /// Start the 2-second polling loop. The blocking CLI call runs off the main
    /// actor (`Task.detached`); results are applied back on the main actor.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let result = await Task.detached(priority: .utility) { Self.fetch() }.value
                self?.apply(result)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func apply(_ result: Result<[AgentSession], PollError>) {
        switch result {
        case .failure(let err):
            lastError = err.message
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

    /// Run `claude agents --json` and decode it. `nonisolated` so it can run on a
    /// background task. Uses a login shell so `claude` (in ~/.local/bin) is found.
    nonisolated private static func fetch() -> Result<[AgentSession], PollError> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "claude agents --json"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch {
            return .failure(PollError(message: "claude 起動失敗: \(error.localizedDescription)"))
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let dtos = try? JSONDecoder().decode([AgentDTO].self, from: data) else {
            return .success([])  // empty / unparseable -> no sessions
        }
        return .success(dtos.map { d in
            let cwd = (d.cwd ?? "").trimmedSlash
            let base = cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent
            return AgentSession(
                id: d.id ?? d.sessionId ?? UUID().uuidString,
                project: base.isEmpty ? cwd : base,
                cwd: cwd,
                name: d.name ?? "",
                kind: d.kind ?? "",
                state: d.state ?? d.status ?? "unknown",
                waitingFor: d.waitingFor ?? ""
            )
        })
    }
}

private extension String {
    nonisolated var trimmedSlash: String { hasSuffix("/") ? String(dropLast()) : self }
}
