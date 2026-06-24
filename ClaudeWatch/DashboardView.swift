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
        HStack(spacing: 10) {
            Text(s.stateEmoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.project).font(.body).bold()
                Text(s.detailText).font(.caption).foregroundStyle(.secondary)
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
