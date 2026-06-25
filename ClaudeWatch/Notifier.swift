// Notifier — 通知とエディタ起動。
//
//   • Notifier        : セッションの状態に応じてネイティブ通知を出す（enum で名前空間化）
//   • openInPhpStorm  : 指定したプロジェクトを PhpStorm で前面に開く

import AppKit
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
        case "idle":
            content.title = "💬 \(a.project) 応答完了"
            content.body = "入力待ち（あなたの番）"
        default:
            return
        }
        content.sound = .default
        content.userInfo = ["cwd": a.cwd]  // carried so a click can open the project
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

private let phpStormBundleID = "com.jetbrains.PhpStorm"

/// 起動済みアプリを前面化し、実際に前面化した瞬間に一度だけ `onReady` を呼ぶ。
/// AppKit の `didActivateApplicationNotification` を購読するイベント駆動。
/// 通知が来ない場合に備えて 1 秒でタイムアウト発火する。発火後は購読を解除し、
/// 自己保持（keepAlive）を解いて解放されるため、呼び出し側は保持しなくてよい。
@MainActor
private final class FrontmostActivation {
    private var observer: NSObjectProtocol?
    private var timeout: DispatchWorkItem?
    private var onReady: (() -> Void)?
    private var keepAlive: FrontmostActivation?

    static func activate(_ app: NSRunningApplication, then onReady: @escaping () -> Void) {
        let activation = FrontmostActivation()
        activation.onReady = onReady
        activation.keepAlive = activation                 // 発火まで自己保持
        let targetID = app.bundleIdentifier

        let center = NSWorkspace.shared.notificationCenter
        activation.observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak activation] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if activated?.bundleIdentifier == targetID {
                MainActor.assumeIsolated { activation?.fire() }
            }
        }
        let work = DispatchWorkItem { [weak activation] in
            MainActor.assumeIsolated { activation?.fire() }
        }
        activation.timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)

        app.activate()
    }

    private func fire() {
        guard let onReady else { return }                 // 二重発火防止
        self.onReady = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        timeout?.cancel()
        onReady()
        keepAlive = nil                                    // 自己保持を解放
    }
}

/// Focus (or open) the project in PhpStorm. JetBrains reuses one window per
/// project, so this brings the existing window forward.
///
/// Dock を跳ねさせないための要点：プロジェクト切替に使えるのは PhpStorm の
/// ネイティブランチャ（`…/Contents/MacOS/phpstorm <path>`、コマンドサーバ経由）
/// だけだが、これをバックグラウンドのアプリに対して叩くと「外部からの前面化」と
/// なり跳ねる。そこで先にプロセス内でアプリ自身をアクティベート（跳ねない）して
/// から、前面になった状態でランチャを実行する。
///
/// 動作は3分岐：
///   - すでに PhpStorm が前面 → そのまま切替（跳ねず、切替フラッシュもなし）
///   - 未起動 → ランチャで起動（初回のみ跳ねうるが許容）
///   - 起動済みだが背面 → `activate()` し、前面化した瞬間（AppKit の
///     didActivateApplication 通知）に切替。固定遅延のもたつきを避けるための
///     イベント駆動。通知が来ない場合に備え 1 秒でタイムアウト発火する。
///
/// （`open -b <bundleId> <folder>` は跳ねないが目的プロジェクトへ切り替わらず
/// 不採用。NSWorkspace.open([folderURL]) はフォルダをドキュメント扱いし
/// プロジェクトとして認識できないため不採用。PhpStorm は Java/Swing 製で
/// ウィンドウを Accessibility にまともに公開しないため、AX 経由で特定
/// プロジェクトの窓を選ぶ方法も採れない。）
@MainActor
func openInPhpStorm(_ cwd: String) {
    guard !cwd.isEmpty,
          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: phpStormBundleID),
          let launcher = Bundle(url: appURL)?.executableURL
    else { return }

    let switchProject = {
        let proc = Process()
        proc.executableURL = launcher
        proc.arguments = [cwd]
        try? proc.run()
    }

    // すでに前面なら跳ねないので即切替（フラッシュなし）。
    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == phpStormBundleID {
        switchProject()
        return
    }
    // 未起動ならランチャで起動。
    guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: phpStormBundleID).first else {
        switchProject()
        return
    }
    // 起動済みだが背面：アクティベート（跳ねない）→ 前面化通知を受けて切替。
    FrontmostActivation.activate(running, then: switchProject)
}