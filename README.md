# claude-watch

複数プロジェクトの Claude Code セッションを **1か所で見て、状態変化で通知し、クリックで
IDE に飛ぶ**ための macOS メニューバーアプリ。`claude agents --json` を読むだけ（リポジトリには触れない）。

> 通知の役割分担：**席にいる時はこのアプリ（Mac デスクトップ）**、**離席中はスマホ/Apple Watch
> ＝ Claude Code 組み込み push（Remote Control 経由）** に任せる、という棲み分け。

## 動かす

Xcode で `ClaudeWatch.xcodeproj` を開いて **⌘R**。

- 初回起動時に通知の許可を求められる → 許可
- メニューバーにアイコンが出る → クリックで一覧 → 行クリックでプロジェクトを IDE で前面化
- Dock には出さずメニューバー常駐（`LSUIElement`）

`claude` をサブプロセス起動するため **App Sandbox は無効**にしている。

## 構成

```
ClaudeWatch.xcodeproj      Xcode プロジェクト
ClaudeWatch/               ソース
├── ClaudeWatchApp.swift   @main / Scene 定義
├── Model.swift            AgentSession / SessionStore（2秒ごとにポーリング・単一の真実）
├── Notifier.swift         native 通知 + IDE 起動
├── AppDelegate.swift      起動初期化・通知デリゲート
└── MenuContent.swift      メニューバーに出す View
```

メニューバー常駐で `claude agents --json` をポーリング → 一覧表示 → 状態が
`waiting`/`blocked`/`done`/`failed` に遷移したら native 通知 → クリックで IDE。
状態管理は `@Observable`、ポーリングは async ループ、JSON は `Codable`。

## ステータス

- [x] 第1マイルストーン：一覧＋native通知＋クリックで IDE
- [ ] ダッシュボードウィンドウ（開いて状態確認できる）
- [ ] ターミナルからの状態確認（CLI）
- [ ] ログイン時自動起動（SMAppService）
- [ ] メニューバーアイコンの状態反映の作り込み・設定画面
- [ ] 配布（他Mac向けの署名）

## 既知の制限

- mac がスリープするとポーリングも止まる（復帰で再開）。
- ポーリング間隔より速く消えたセッションは取り逃すことがある。
- 通知は対象状態への「遷移時」に1回。
