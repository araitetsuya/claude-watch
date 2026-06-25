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
    /// 状態以外の補足（待ち理由 > 名前 > 種別）。状態は別に色付きで表示するため含めない。
    var subtitle: String {
        !waitingFor.isEmpty ? waitingFor : (!name.isEmpty ? name : kind)
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
    /// 「作業中」を表す状態。ここから idle へ遷移＝1ターン完了とみなして通知する。
    static let activeStates: Set<String> = ["working", "busy"]

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
        for a in agents {
            let prev = lastStates[a.id]
            guard prev != a.state else { continue }   // 状態が変わった瞬間だけ
            if Self.notifyStates.contains(a.state) {
                Notifier.fire(for: a)
            } else if a.state == "idle", let prev, Self.activeStates.contains(prev) {
                Notifier.fire(for: a)   // busy/working -> idle = 1ターン完了
            }
        }
    }

    /// ユーザーのログインシェルが組み立てる PATH。初回だけ実際にシェルを起動して解決し、
    /// 以降はキャッシュを返す（解決は背景タスク上の `fetch()` から呼ばれる）。
    ///
    ///   • `$SHELL -ilc` で対話ログインシェルを起動し `.zshrc`/`.bashrc` まで読ませる。
    ///     nvm・mise・volta・カスタム npm prefix など、PATH をそこで足す環境に追従できる。
    ///   • rc がバナーを stdout に吐いても拾わないよう、PATH を番兵で挟んで切り出す。
    ///   • 解決に失敗したら代表的なインストール先のフォールバックを使う。
    nonisolated(unsafe) private static var cachedPath: String?
    private static let pathLock = NSLock()

    nonisolated private static func loginShellPath() -> String {
        pathLock.lock(); defer { pathLock.unlock() }
        if let cachedPath { return cachedPath }

        let home = NSHomeDirectory()
        let fallback = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-ilc", #"printf '__CWPATH__%s__CWEND__' "$PATH""#]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()

        var resolved = fallback
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            if let lo = text.range(of: "__CWPATH__"),
               let hi = text.range(of: "__CWEND__"),
               lo.upperBound <= hi.lowerBound {
                let value = String(text[lo.upperBound..<hi.lowerBound])
                if !value.isEmpty { resolved = value }
            }
        } catch {
            NSLog("loginShellPath: \(shell) 起動失敗 \(error.localizedDescription) — fallback 使用")
        }

        cachedPath = resolved
        return resolved
    }

    /// Run `claude agents --json` and decode it. `nonisolated` so it can run on a
    /// background task.
    ///
    /// PATH: Finder/Xcode から起動した GUI アプリはターミナルの PATH を継承しないため、
    /// `claude`（nvm/mise/volta/`~/.local/bin` 等、人によって場所が違う）を素では見つけ
    /// られない。そこで起動時にユーザーのログインシェルから PATH を一度だけ解決して
    /// キャッシュし（VS Code などと同じ方式・`loginShellPath()`）、その PATH を環境に
    /// 渡して claude を起動する。ポーリング毎の対話シェル起動コストは無い。
    nonisolated private static func fetch() -> Result<[AgentSession], PollError> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = loginShellPath()
        proc.environment = env
        proc.arguments = ["-c", "claude agents --json"]
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
