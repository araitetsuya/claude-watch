# claude-dash (Stage 1)

複数プロジェクトの Claude Code セッションを**1か所で見て・状態変化で通知**する、
常駐デーモン＋表示の最小構成。`claude agents --json` を読むだけ（リポジトリには触れない）。

## 構成（コア分離・通知担当は1つ）

```
cdash.py    コア（取得・整形・状態IO・通知）。全部品が import する
daemon.py   常駐デーモン＝唯一の「本体」。ポーリング→ state.json 書き出し→遷移検知→通知
view.py     ターミナル表示＝state.json を読む「窓」。複数開いてOK・通知はしない
com.claude-dash.daemon.plist  launchd 用（自動起動）
install.sh  ~/.claude-dash へ配置し launchd 登録
```

- **通知を出すのは daemon だけ**＝窓を何枚開いても二重通知にならない。
- 状態は `~/.claude-dash/`（環境変数 `CLAUDE_DASH_DIR` で変更可）。

## 試す（常駐させずに）

```bash
# 1つのターミナルでデーモンを起動（Ctrl+Cで停止）
python3 daemon.py

# 別タブで表示
python3 view.py
```

`state` 別に色分け、`blocked`（=あなたの操作待ち）を最上段に表示。
どれかが blocked / done / failed になると mac 通知が出る。

## 常駐させる（自動起動）

```bash
bash install.sh            # ~/.claude-dash へ配置 + launchd 登録（ログイン時自動起動）
python3 ~/.claude-dash/view.py   # 一覧を見たいとき
bash install.sh uninstall  # 常駐解除
```

## クリックで PhpStorm にジャンプしたい場合

標準の osascript 通知はクリック動作に非対応。クリックで該当プロジェクトを
PhpStorm で前面化したいときは terminal-notifier を入れる（cdash.py が自動検出）:

```bash
brew install terminal-notifier
```

（phpstorm CLI は導入済みを確認済み。通知クリック→ `phpstorm <cwd>` で該当ウィンドウが前面化）

## Stage 2（後付け）：メニューバー表示

xbar / SwiftBar のプラグインとして「`state.json` を読んで行を print するだけ」の
薄い殻を1枚足せば、同じ state.json をメニューバーからも見られる。
daemon.py / view.py はそのまま（窓が増えるだけ）。

## 既知の制限

- mac がスリープするとデーモンも止まる（復帰で再開）＝ローカル常駐の宿命。
- ポーリング間隔より速く `done` になって消えたセッションは取り逃すことがある（通知のみ）。
- 通知は blocked / done / failed への「遷移時」に1回。idle/busy/working は通知しない。
