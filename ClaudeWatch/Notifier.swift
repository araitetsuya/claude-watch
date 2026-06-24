// Notifier — 通知とエディタ起動。
//
//   • Notifier        : セッションの状態に応じてネイティブ通知を出す（enum で名前空間化）
//   • openInPhpStorm  : 指定したプロジェクトを PhpStorm で前面に開く

import Foundation
import UserNotifications

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