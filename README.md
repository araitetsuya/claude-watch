# claude-watch

複数プロジェクトの Claude Code セッションを **1か所で見て、状態変化で通知し、クリックで
IDE に飛ぶ**ためのデスク用ツール。`claude agents --json` を読むだけ（リポジトリには触れない）。

> 通知の役割分担：**席にいる時はこのツール（Mac デスクトップ）**、**離席中はスマホ/Apple Watch
> ＝ Claude Code 組み込み push（Remote Control 経由）** に任せる、という棲み分け。

## 構成

```
app/         ネイティブ macOS アプリ（Swift / SwiftUI MenuBarExtra）— 本命
prototype/   Python 版（検証済みプロトタイプ。仕様の参照・記録）
```

### app/ — ネイティブアプリ（ClaudeWatch）

メニューバー常駐。`claude agents --json` をポーリング → 一覧表示 → 状態が
`waiting`/`blocked`/`done`/`failed` に遷移したら native 通知 → クリックで PhpStorm。

- `app/ClaudeWatch/` … Xcode プロジェクト（本流。`app/XCODE.md` の手順で作成）
- `app/swiftc/` … Xcode 無しでビルドする最小版（学習の出発点・CI 用）
- `app/XCODE.md` … swiftc 版 → Xcode への移行手順

Xcode 無しで素早く動かす場合：

```bash
cd app/swiftc
bash build.sh          # build/ClaudeWatch.app を生成（Xcode 不要・ad-hoc 署名）
open build/ClaudeWatch.app
```

### prototype/ — Python 版（参照）

ロジックを最初に検証した版。常駐デーモン＋ターミナル表示＋通知。
（当時の名前 `claude-dash` のまま。`~/.claude-dash` に常設済み・内部名も据え置き。）

```bash
cd prototype
python3 daemon.py      # 本体（Ctrl+Cで停止）
python3 view.py        # 一覧（別タブ）
# 自動起動させる場合: bash install.sh  （launchd 登録）
```

> アプリ版と Python 版を**同時に常駐させない**こと（通知が二重になる）。
> アプリへ移行したら Python 版の launchd は解除：
> `launchctl unload ~/Library/LaunchAgents/com.claude-dash.daemon.plist`

## ステータス

- [x] Python プロトタイプ（検証済み・`~/.claude-dash` に常設）
- [x] ネイティブアプリ 第1マイルストーン：一覧＋native通知＋クリックでPhpStorm
- [ ] ログイン時自動起動（SMAppService）
- [ ] メニューバーアイコンの状態反映の作り込み・設定画面
- [ ] 配布（他Mac向けの署名）

## 既知の制限

- mac がスリープするとポーリングも止まる（復帰で再開）。
- ポーリング間隔より速く消えたセッションは取り逃すことがある。
- 通知は対象状態への「遷移時」に1回。