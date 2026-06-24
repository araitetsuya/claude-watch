// ClaudeWatchApp — アプリのエントリポイント（@main）。
//
// ここには SwiftUI の Scene 定義だけを置く。中身は役割ごとに分割:
//   • Model.swift       … データ（AgentSession / SessionStore）
//   • Notifier.swift    … 通知と PhpStorm 起動
//   • AppDelegate.swift … 起動時の初期化・通知デリゲート
//   • MenuContent.swift … メニューバーに出す View
//   • DashboardView.swift … 開いて状態確認するウィンドウ

import SwiftUI

@main
struct ClaudeWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SessionStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(systemName: store.needsAttention ? "bell.badge.fill" : "list.bullet.rectangle")
        }
        .menuBarExtraStyle(.window)

        // 開いて状態確認するダッシュボード。メニューの「ダッシュボードを開く」や
        // openWindow(id:) で表示する。起動時に勝手に開かないよう .suppressed。
        Window("ClaudeWatch", id: DashboardWindow.id) {
            DashboardView(store: store)
        }
        .defaultSize(width: 480, height: 600)
        .defaultLaunchBehavior(.suppressed)
    }
}

/// openWindow(id:) で使うウィンドウ識別子。
enum DashboardWindow {
    static let id = "dashboard"
}
