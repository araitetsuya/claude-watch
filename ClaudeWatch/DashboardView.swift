// DashboardView — 開いて状態確認するウィンドウの中身。
//
//   • SessionStore.shared を共有 → メニューと同じ状態を表示（自動同期）
//   • メニューより情報量を多めに（cwd も表示）
//   • ウィンドウを開くと Dock 表示＋前面化（.regular）、閉じたらメニューバー
//     常駐に戻す（.accessory）= Docker Desktop と同じ挙動

import SwiftUI
import AppKit

struct DashboardView: View {
    var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            legend
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            // メニューバーアプリ（.accessory）から、開いている間だけ通常アプリに昇格。
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// ステータス色の凡例。将来は設定画面へ移す予定（今はダッシュボード下部に仮置き）。
    private var legend: some View {
        let statuses = ["idle", "busy", "waiting", "working", "blocked", "done", "failed", "stopped"]
        return VStack(alignment: .leading, spacing: 6) {
            Text("ステータス凡例").font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(statuses, id: \.self) { st in
                    HStack(spacing: 6) {
                        Circle().fill(AgentSession.statusColor(for: st)).frame(width: 9, height: 9)
                        Text(st.uppercased()).font(.caption).bold()
                            .foregroundStyle(AgentSession.statusColor(for: st))
                    }
                }
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: store.needsAttention ? "bell.badge.fill" : "list.bullet.rectangle")
                .foregroundStyle(store.needsAttention ? .red : .secondary)
            Text("claude-watch").font(.title3).bold()
            Spacer()
            Text("\(store.sessions.count) セッション")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if let err = store.lastError {
            ContentUnavailableView {
                Label("エラー", systemImage: "exclamationmark.triangle")
            } description: {
                Text(err)
            }
        } else if store.sessions.isEmpty {
            ContentUnavailableView("アクティブなセッションはありません",
                                   systemImage: "moon.zzz")
        } else {
            List(store.sessions) { session in
                row(session)
            }
            .listStyle(.inset)
        }
    }

    private func row(_ s: AgentSession) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // 1行目：大文字・色付きステータス ＋ プロジェクト名（メニューと統一）
                HStack(spacing: 6) {
                    Text(s.state.uppercased()).font(.body).bold().foregroundStyle(s.statusColor)
                    Text(s.project).font(.body).bold()
                }
                if !s.subtitle.isEmpty {
                    Text(s.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                if !s.cwd.isEmpty {
                    Text(s.cwd).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("開く") { openInPhpStorm(s.cwd) }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
