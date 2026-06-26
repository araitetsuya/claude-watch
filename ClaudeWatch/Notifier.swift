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
        // title はプロジェクト名（通知一覧で一番目立つ位置）。body は状態の文章 1 行に
        // まとめ、詳細（待ち理由 / セッション名）があるときだけ括弧で添える。
        // アプリ名は OS が自動表示する。
        content.title = a.project.isEmpty ? "Claude セッション" : a.project
        switch a.state {
        case "blocked", "waiting":
            content.body = withDetail("確認待ちです", a.waitingFor)
        case "done":
            content.body = withDetail("作業が完了しました", a.name)
        case "failed":
            content.body = withDetail("作業が失敗しました", a.name)
        case "idle":
            content.body = "応答が完了しました"
        default:
            return
        }
        content.sound = .default
        content.userInfo = ["cwd": a.cwd]  // carried so a click can open the project
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// 状態の文章に、詳細があれば「（詳細）」を添えて 1 行にまとめる。
    private static func withDetail(_ base: String, _ detail: String) -> String {
        detail.isEmpty ? base : "\(base)（\(detail)）"
    }
}

private let phpStormBundleID = "com.jetbrains.PhpStorm"

/// 指定バンドルIDのアプリが最前面か。
@MainActor private func isFrontmost(_ bundleID: String?) -> Bool {
    NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
}

/// `ready()` が真になるまで 25ms 間隔でポーリングする（最大 timeout）。
/// 毎回 `attempt()` を呼ぶ（activate などの副作用用。不要なら既定の空でよい）。
@MainActor private func poll(timeout: Duration, attempt: () -> Void = {}, until ready: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        attempt()
        if ready() { return }
        try? await Task.sleep(for: .milliseconds(25))
    }
}

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
/// なり跳ねる。そこで先にプロセス内でアプリ自身をアクティベートしてから、前面に
/// なった状態でランチャを実行する。
///
/// 呼び出し元（fromNotification）で経路を分ける：
///   通知クリック由来：クリックは直後（実測 ~25ms）に LSUIElement の ClaudeWatch を
///     前面化し居座る。先に PhpStorm を activate するとこの前面化に上書きされ、
///     ランチャの toFront と競合して跳ねる。そこで 2 段階にする：
///       Phase1: ClaudeWatch が前面になった（=click の onset 完了）のを実測で待つ。
///       Phase2: 後出しで PhpStorm を activate し、実際に frontmost になったことを
///               実測確認してからランチャを叩く。
///   メニュー/ダッシュボード由来（競合なし）：
///     - すでに PhpStorm が前面 → そのまま切替（跳ねず、フラッシュもなし）
///     - 未起動 → ランチャで起動（初回のみ跳ねうるが許容）
///     - 起動済みだが背面 → activate し、前面化した瞬間（didActivateApplication
///       通知）に切替。通知が来ない場合に備え 1 秒でタイムアウト発火する。
///
/// （`open -b <bundleId> <folder>` は跳ねないが目的プロジェクトへ切り替わらず
/// 不採用。NSWorkspace.open([folderURL]) はフォルダをドキュメント扱いし
/// プロジェクトとして認識できないため不採用。PhpStorm は Java/Swing 製で
/// ウィンドウを Accessibility にまともに公開しないため、AX 経由で特定
/// プロジェクトの窓を選ぶ方法も採れない。）
@MainActor
func openInPhpStorm(_ cwd: String, fromNotification: Bool = false) {
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

    // 通知クリック経路。クリックは直後（実測 ~25ms）に ClaudeWatch（LSUIElement）を
    // 前面化し居座る。先に PhpStorm を activate すると上書きされ、ランチャの toFront と
    // 競合して跳ねる。そこで「ClaudeWatch が前面になった（onset 完了）のを待ってから、
    // 後出しで PhpStorm を前面化」する。
    if fromNotification {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: phpStormBundleID).first else {
            switchProject()          // 未起動ならランチャで起動
            return
        }
        let selfID = Bundle.main.bundleIdentifier
        Task { @MainActor in
            // Phase1: クリックによる ClaudeWatch 前面化(onset)を待つ。
            await poll(timeout: .milliseconds(500)) { isFrontmost(selfID) }
            // Phase2: 後出しで PhpStorm を前面化し、実測確認してからランチャ。
            await poll(timeout: .milliseconds(1000), attempt: { running.activate() }) { isFrontmost(phpStormBundleID) }
            switchProject()
        }
        return
    }

    // メニュー/ダッシュボード経路（通知のような競合なし）。
    // すでに前面なら即切替（フラッシュなし）。
    if isFrontmost(phpStormBundleID) {
        switchProject()
        return
    }
    // 未起動ならランチャで起動。
    guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: phpStormBundleID).first else {
        switchProject()
        return
    }
    // 起動済みだが背面：アクティベート→前面化通知で切替。
    FrontmostActivation.activate(running, then: switchProject)
}