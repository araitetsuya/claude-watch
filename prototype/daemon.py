"""claude-dash daemon: the single resident process ("the brain").

Polls `claude agents --json`, writes the shared state file, and fires ONE
notification whenever a session transitions into blocked / done / failed.
Being the only thing that notifies is what prevents double-notifications when
several views are open.

  resident:   python3 daemon.py
  one tick:   python3 daemon.py --once     (for testing / cron)
"""
import time
import argparse

import cdash


def tick():
    agents = [cdash.normalize(a) for a in cdash.fetch_agents()]
    cdash.write_state(agents)

    fired = cdash.transitions(cdash.load_last(), agents)
    for a in fired:
        if a["state"] in ("blocked", "waiting"):
            cdash.notify("⚠️ %s が待っています" % a["project"],
                         a["waitingFor"] or "要対応（許可 / 入力）", a["cwd"])
        elif a["state"] == "done":
            cdash.notify("✅ %s 完了" % a["project"],
                         a["name"] or "セッション完了", a["cwd"])
        elif a["state"] == "failed":
            cdash.notify("❌ %s 失敗" % a["project"],
                         a["name"] or "セッション失敗", a["cwd"])

    cdash.save_last({a["id"]: a["state"] for a in agents})
    return len(agents), len(fired)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true",
                    help="run a single tick and exit")
    ap.add_argument("--interval", type=float, default=2.0,
                    help="seconds between polls (default 2.0)")
    args = ap.parse_args()

    if args.once:
        n, f = tick()
        print("[claude-dash] tick: %d sessions, %d notifications" % (n, f))
        return

    print("[claude-dash] daemon start (interval=%ss, dir=%s)"
          % (args.interval, cdash.DIR))
    while True:
        try:
            tick()
        except Exception as e:
            print("[claude-dash] tick error: %s" % e)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
