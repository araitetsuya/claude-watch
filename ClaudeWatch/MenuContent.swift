// View — メニューバーアイコンをクリックすると出るポップオーバーの中身。
//
//   • store を observe してセッション一覧を表示
//   • 行をタップするとそのプロジェクトを PhpStorm で開く
//   • emoji / info は表示用のヘルパー

import SwiftUI
import AppKit

struct MenuContent: View {
    var store: SessionStore

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