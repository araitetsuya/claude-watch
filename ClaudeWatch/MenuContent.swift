// View — メニューバーのネイティブメニュー（NSMenu）の中身。
//
//   • MenuBarExtra のデフォルト（.menu）スタイルで使う想定。
//     なので VStack や frame で囲わず、メニュー項目を直接並べる。
//   • セッションは「大文字ステータス + プロジェクト名」の1行項目。
//     状態色を文字色に適用（※ネイティブメニューが色を無視する可能性あり）。
//   • 項目を選ぶとメニューは自動でフェードして閉じる。

import SwiftUI
import AppKit

struct MenuContent: View {
    var store: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let err = store.lastError {
            Text("⚠️ \(err)")
        }

        if store.sessions.isEmpty {
            Text("アクティブなセッションはありません")
        } else {
            ForEach(store.sessions) { s in
                Button { openInPhpStorm(s.cwd) } label: {
                    Text(Self.title(for: s))
                }
            }
        }

        Divider()
        Button("開く") { openWindow(id: DashboardWindow.id) }

        // ログイン時に自動起動。状態は SMAppService から読むので、システム設定側で
        // 変えられても次に開いたとき正しく反映される。
        let loginOn = LoginItem.shared.isEnabled
        Toggle("ログイン時に起動", isOn: Binding(
            get: { loginOn },
            set: { LoginItem.shared.set($0) }
        ))

        Button("終了") { NSApplication.shared.terminate(nil) }
    }

    /// 「色付きの大文字ステータス」＋「通常色のプロジェクト名」を結合したタイトル。
    /// ステータス部分だけに色を付けるため AttributedString で組み立てる。
    private static func title(for s: AgentSession) -> AttributedString {
        var status = AttributedString(s.state.uppercased())
        status.foregroundColor = s.statusColor
        // メニューと同じサイズでボールド指定（inlinePresentationIntent は効かないため）
        status.font = .system(size: NSFont.menuFont(ofSize: 0).pointSize, weight: .bold)
        return status + AttributedString(" - \(s.project)")
    }
}

extension AgentSession {
    /// 状態を表す色（メニューの文字色・ダッシュボードのドット共通）。
    var statusColor: Color { Self.statusColor(for: state) }

    /// 状態文字列 → 色（セッションが無くても使えるよう static。凡例などで利用）。
    static func statusColor(for state: String) -> Color {
        switch state {
        case "blocked", "waiting": return .orange
        case "working", "busy":    return .blue
        case "failed":             return .red
        case "done":               return .green
        default:                   return .secondary
        }
    }
}
