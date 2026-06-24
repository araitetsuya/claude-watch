// View — メニューバーのネイティブメニュー（NSMenu）の中身。
//
//   • MenuBarExtra のデフォルト（.menu）スタイルで使う想定。
//     なので VStack や frame で囲わず、メニュー項目を直接並べる。
//   • セッションは「色付きドット + プロジェクト名 · 状態」の1行項目（Docker の
//     "● ... is running" に寄せる）。クリックで IDE を開く。
//   • ドットは SF Symbol だとメニューで単色化されるため、色付きの丸を描いた
//     「非テンプレート画像」を使って色を乗せる。

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
                    Label {
                        Text("\(s.state.uppercased())  \(s.project)")
                    } icon: {
                        Image(nsImage: Self.dot(NSColor(s.statusColor)))
                    }
                }
            }
        }

        Divider()
        Button("開く") { openWindow(id: DashboardWindow.id) }
        Button("終了") { NSApplication.shared.terminate(nil) }
    }

    /// 色付きの丸を描いた非テンプレート画像（メニューで色が乗るように）。
    private static func dot(_ color: NSColor, diameter: CGFloat = 9) -> NSImage {
        // 行の縦中央に置く（ネイティブのメニューアイコンと同じ標準位置）。
        // 無理にテキストへ揃えるとホバーの四角に対して中央からズレて見えるため、
        // 中央のままにしておく。
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false   // テンプレートにすると単色化されるので false
        return image
    }
}

extension AgentSession {
    /// 状態を表すドットの色（メニュー・ダッシュボード共通）。
    var statusColor: Color {
        switch state {
        case "blocked", "waiting": return .red
        case "working", "busy":    return .blue
        case "failed":             return .red
        case "done":               return .green
        default:                   return .secondary
        }
    }
}
