# Xcode への移行手順

`swiftc` で作った最小版（`app/swiftc/`）を、標準の **Xcode プロジェクト**に移し、
これ以降は Xcode で開発する。所要 10〜15 分。Xcode 初めてでも追えるように細かく書く。

前提：Xcode 26+ / macOS 26（確認済み）。既存コード `app/swiftc/ClaudeWatchApp.swift`
をそのまま流用する。

---

## 1. 新規プロジェクトを作る

1. Xcode を起動 → メニュー **File > New > Project…**（⇧⌘N）
2. 上のタブ **macOS** → **App** を選んで **Next**
3. 入力：
   - **Product Name**: `ClaudeWatch`
   - **Team**: 自分の Apple ID（未設定なら空のままでOK。後述「署名」参照）
   - **Organization Identifier**: `com.tetsuyaarai`
     → Bundle Identifier が `com.tetsuyaarai.ClaudeWatch` になる
     （`com.tetsuyaarai.claude-watch` に揃えたいなら、後で Target > General で変更可）
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
   - **Storage**: None（チェック不要）／ **Include Tests**: 最初は外してよい
4. **Next** → 保存先に **`~/workspace/claude-watch/app/`** を選ぶ
   → `app/ClaudeWatch/` が作られる
   - ⚠️ **「Create Git repository on my Mac」のチェックは外す**
     （既にリポがある。二重に git init しない）

---

## 2. テンプレを自分のコードに差し替える

Xcode が `app/ClaudeWatch/ClaudeWatch/` に2つ生成する：
`ClaudeWatchApp.swift`（テンプレ）と `ContentView.swift`。

1. **`ContentView.swift` を削除**（右クリック → Move to Trash）
2. テンプレの **`ClaudeWatchApp.swift` を開き、中身を全削除**して、
   **`app/swiftc/ClaudeWatchApp.swift` の中身を丸ごと貼り付け**る
   - ポイント：`@main` は1ファイルにのみ存在させる。テンプレ側の中身を上書きするので
     `@main` が重複せず安全（うちのコードに `@main struct ClaudeWatchApp` が含まれる）

> これでモデル・通知・UI が1ファイルに入った状態になる。慣れてきたら
> Model / Notifier / Views をファイル分割すると良い練習になる。

---

## 3. メニューバーアプリにする（Dock アイコン無し）

1. 左ペイン最上部の青いプロジェクトアイコン → **TARGETS > ClaudeWatch** → **Info** タブ
2. リストの行にカーソル → **+** で行追加：
   - **Key**: `Application is agent (UIElement)`
   - **Value**: `YES`
   - （これが `LSUIElement`。Dock に出さずメニューバー常駐になる）

---

## 4. ビルド＆実行

1. **⌘R**（Run）
2. 初回：**通知の許可ダイアログ → 許可**
3. メニューバーにアイコン → クリックで一覧 → 行クリックで PhpStorm が前面化

---

## 5. Xcode ならではの利点（ここから学べる）

- **コンソール**：`print(...)` が下部に出る（デバッグの基本）
- **ブレークポイント**：行番号の左をクリック → ⌘R で停止し変数を確認
- **SwiftUI プレビュー**：`MenuContent` の下に下記を足すと右側で即確認できる
  ```swift
  #Preview { MenuContent(store: .shared) }
  ```
- **capability 追加**：TARGETS > Signing & Capabilities の **+ Capability**

---

## 6. git に載せる

```bash
cd ~/workspace/claude-watch
git add app/ClaudeWatch
git commit -m "feat(app): Xcode プロジェクト化（swiftc 版から移行）"
```

`xcuserdata` 等の個人設定は `.gitignore` 済み。`*.xcodeproj` 本体はコミットする。

---

## 7. この先（やりたくなったら）

- **ログイン時自動起動**：`SMAppService.mainApp.register()` をコードで呼ぶ（Login Items に登録）
- **アプリアイコン**：`Assets.xcassets > AppIcon` に画像を入れる
- **通知**：ローカル通知は特別な entitlement 不要。リモート push をやるなら
  Capability に **Push Notifications** を追加
- **他 Mac へ配布**：Signing で Team を設定（無料 Apple ID でも自分の Mac 向けは可。
  Gatekeeper を完全に黙らせるには Apple Developer Program 〔$99/年〕＋公証）

---

## swiftc 版（`app/swiftc/`）との関係

- `app/swiftc/` は「Xcode 無しでビルドする最小版」。**中身が分かる学習の出発点**・CI 用に残置。
- 今後の本流は **Xcode プロジェクト（`app/ClaudeWatch/`）**。ソースの正は Xcode 側。
- 両方を同期したい場合は、`app/swiftc/ClaudeWatchApp.swift` を Xcode 側へのシンボリックリンク
  にする手もある（最初は気にしなくてよい）。

---

## トラブルシュート

- **通知が出ない** → システム設定 > 通知 > ClaudeWatch を許可
- **`claude` が見つからない**（一覧が空＋エラー）→ アプリは `zsh -lc` で `claude` を呼ぶ。
  ログインシェルの PATH に `~/.local/bin` が含まれているか確認
- **署名で実行できない** → TARGETS > Signing & Capabilities で
  **Automatically manage signing** にチェック＋自分の Apple ID。
  Team が無くても Xcode が "Sign to Run Locally" でローカル実行はできる