"""claude-dash core: shared library (fetch / normalize / state IO / notify).

This is the reusable "core". The daemon (daemon.py) and any view (view.py now,
a menu-bar plugin later) all import this. Stdlib only. Python 3.8+.

State lives under CLAUDE_DASH_DIR (default ~/.claude-dash):
  state.json     -- current snapshot, written by the daemon, read by views
  laststate.json -- {id: state} from the previous tick, for transition detection
"""
import os
import json
import time
import shutil
import tempfile
import subprocess

DIR = os.environ.get("CLAUDE_DASH_DIR", os.path.expanduser("~/.claude-dash"))
STATE_FILE = os.path.join(DIR, "state.json")
LAST_FILE = os.path.join(DIR, "laststate.json")

# A session entering one of these states is worth a desktop notification.
# Note: interactive sessions report "waiting" (not "blocked") when they need you
# (e.g. a permission prompt) -- confirmed empirically -- so both are included.
NOTIFY_STATES = {"blocked", "waiting", "done", "failed"}


def ensure_dir():
    os.makedirs(DIR, exist_ok=True)


def fetch_agents():
    """Return the raw agent dicts from `claude agents --json` ([] on any error)."""
    try:
        p = subprocess.run(
            ["claude", "agents", "--json"],
            capture_output=True, text=True, timeout=15,
        )
        if p.returncode != 0 or not p.stdout.strip():
            return []
        return json.loads(p.stdout)
    except Exception:
        return []


def normalize(a):
    """Flatten one raw agent into the fields the dashboard needs.

    `claude agents --json` uses `state` (working/blocked/done/failed/stopped) for
    background agents and `status` (idle/busy) for interactive ones; we keep
    whichever is present.
    """
    cwd = (a.get("cwd") or "").rstrip("/")
    return {
        "id": a.get("id") or a.get("sessionId") or "",
        "project": os.path.basename(cwd) or cwd or "(unknown)",
        "cwd": cwd,
        "name": a.get("name") or "",
        "kind": a.get("kind") or "",
        "state": a.get("state") or a.get("status") or "unknown",
        "waitingFor": a.get("waitingFor") or "",
        "startedAt": a.get("startedAt") or 0,
    }


def _atomic_write(path, text):
    ensure_dir()
    fd, tmp = tempfile.mkstemp(dir=DIR)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def write_state(agents):
    _atomic_write(STATE_FILE, json.dumps(
        {"ts": time.time(), "agents": agents}, ensure_ascii=False, indent=2))


def read_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"ts": 0, "agents": []}


def load_last():
    """Previous {id: state}, or None on the very first run (=> seed, don't notify)."""
    try:
        with open(LAST_FILE) as f:
            return json.load(f)
    except Exception:
        return None


def save_last(state_map):
    _atomic_write(LAST_FILE, json.dumps(state_map, ensure_ascii=False))


def transitions(last, agents):
    """Pure logic: agents that just moved INTO a notify-worthy state.

    last  -- previous {id: state} (None on first run => no notifications)
    agents -- current normalized agents
    """
    if last is None:
        return []
    out = []
    for a in agents:
        if last.get(a["id"]) != a["state"] and a["state"] in NOTIFY_STATES:
            out.append(a)
    return out


def notify(title, message, cwd=None):
    """Fire one macOS notification.

    Uses terminal-notifier if installed (lets the banner be CLICKED to focus the
    project in PhpStorm); otherwise falls back to osascript (no click action).
    """
    tn = shutil.which("terminal-notifier")
    phpstorm = shutil.which("phpstorm")
    if tn:
        cmd = [tn, "-title", title, "-message", message,
               "-group", "claude-dash", "-sound", "Ping"]
        if cwd and phpstorm:
            cmd += ["-execute", 'phpstorm "%s"' % cwd]
        subprocess.run(cmd, capture_output=True)
    else:
        # argv form keeps quotes/unicode in the text from breaking the AppleScript
        script = ("on run argv\n"
                  "display notification (item 1 of argv) "
                  'with title (item 2 of argv) sound name "Ping"\n'
                  "end run")
        subprocess.run(["osascript", "-e", script, message, title],
                       capture_output=True)
