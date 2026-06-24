"""claude-dash terminal view: a window onto the daemon's state file.

Pure display -- it does NOT poll Claude or send notifications (that is the
daemon's job). Open as many views as you like; they all read the same
state.json, so they always agree.

  live:   python3 view.py
  once:   python3 view.py --once
"""
import time
import argparse

import cdash

RESET = "\033[0m"
COLOR = {
    "blocked": "\033[1;97;41m",  # white on red  -> needs you
    "waiting": "\033[1;97;41m",  # interactive sessions use "waiting" for this
    "working": "\033[36m",       # cyan
    "busy":    "\033[36m",
    "failed":  "\033[1;31m",
    "done":    "\033[32m",       # green
    "idle":    "\033[2m",        # dim
    "stopped": "\033[2m",
}
# sort key: needs-attention first, finished/idle last
ORDER = {"blocked": 0, "waiting": 0, "working": 1, "busy": 1, "failed": 2,
         "done": 3, "idle": 4, "stopped": 5}

# states that mean "this session needs you right now"
ATTENTION = ("blocked", "waiting")


def fmt_age(started_ms):
    if not started_ms:
        return ""
    s = max(0, int(time.time() - started_ms / 1000))
    if s < 60:
        return "%ds" % s
    if s < 3600:
        return "%dm" % (s // 60)
    return "%dh%dm" % (s // 3600, (s % 3600) // 60)


def render():
    st = cdash.read_state()
    agents = st.get("agents", [])
    age = time.time() - st.get("ts", 0)

    out = ["\033[1m  claude-dash\033[0m  (複数プロジェクトのセッション一覧)"]
    if st.get("ts", 0) == 0:
        out.append("  \033[33m状態ファイルがありません。daemon.py を起動してください。\033[0m")
    elif age > 10:
        out.append("  \033[33m⚠ %ds 更新なし（デーモン停止中？）\033[0m" % int(age))
    else:
        out.append("  更新 %ds 前" % int(age))
    out.append("")

    if any(a["state"] in ATTENTION for a in agents):
        out.append("  \033[1;91m● 要対応のセッションがあります\033[0m")

    out.append("  %-9s %-26s %5s  %s" % ("STATE", "PROJECT", "AGE", "INFO"))
    out.append("  %s %s %s  %s" % ("-" * 9, "-" * 26, "-" * 5, "-" * 22))
    for a in sorted(agents, key=lambda a: (ORDER.get(a["state"], 9), a["project"])):
        c = COLOR.get(a["state"], "")
        state = "%s%-9s%s" % (c, a["state"], RESET)
        info = a["waitingFor"] or a["name"] or a["kind"]
        out.append("  %s %-26s %5s  %s"
                   % (state, a["project"], fmt_age(a["startedAt"]), info))
    if not agents:
        out.append("  （アクティブなセッションはありません）")

    out.append("")
    out.append("  \033[2mCtrl+C で終了\033[0m")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--interval", type=float, default=1.0)
    args = ap.parse_args()

    if args.once:
        print(render())
        return
    try:
        while True:
            print("\033[H\033[J" + render(), end="", flush=True)
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
