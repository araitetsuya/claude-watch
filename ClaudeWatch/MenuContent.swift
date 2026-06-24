// View — メニューバーアイコンをクリックすると出るポップオーバーの中身。
//
//   • store を observe してセッション一覧を表示
//   • 行をタップするとそのプロジェクトを PhpStorm で開く
//   • 「ダッシュボードを開く」でウィンドウ表示（openWindow）
//   • 状態絵文字・詳細は AgentSession の共有ヘルパー（Model.swift）を使う

import SwiftUI
import AppKit

struct MenuContent: View {
    var store: SessionStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

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
                            Text(s.stateEmoji).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.project).bold()
                                Text(s.detailText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            Button("ダッシュボードを開く") {
                openWindow(id: DashboardWindow.id)
                dismiss()   // ポップオーバーを閉じる（.window スタイルは自動で閉じない）
            }
            Button("終了") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
    }
}
