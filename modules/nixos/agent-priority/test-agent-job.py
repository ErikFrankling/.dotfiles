"""Regression tests using an isolated state directory and fake systemctl."""
import os
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).with_name("agent-job.sh").resolve()
with tempfile.TemporaryDirectory(prefix="agent-job-test-", dir=Path.cwd()) as tmp:
    root = Path(tmp)
    state = root / "agent-job"
    state.mkdir()
    bindir = root / "bin"
    bindir.mkdir()
    for name, body in {
        "sleep": "exit 0\n",
        "systemctl": '''n=$(cat "$TEST_ROOT/count" 2>/dev/null || echo 0)
echo $((n+1)) > "$TEST_ROOT/count"
case "$TEST_MODE:$n" in
  recover:0|lost:*) exit 1 ;;
  followlost:0) echo active ;;
  followlost:*) exit 1 ;;
  empty:*) exit 0 ;;
  recover:1) echo active ;;
  finished:*|recover:*) echo 7 > "$XDG_STATE_HOME/agent-job/job.status"; echo inactive ;;
  active:*) echo active ;;
esac
''',
    }.items():
        path = bindir / name
        path.write_text("#!/usr/bin/env bash\n" + body)
        path.chmod(0o755)
    env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}",
               XDG_STATE_HOME=str(root), TEST_ROOT=str(root))
    for mode, action, expected in [
        ("recover", "attach", 7),
        ("finished", "attach", 7),
        ("lost", "attach", 75),
        ("lost", "run", 75),
        ("lost", "status", 75),
        ("followlost", "attach", 75),
        ("empty", "attach", 75),
        ("active", "status", 0),
    ]:
        (root / "count").unlink(missing_ok=True)
        (state / "job.status").unlink(missing_ok=True)
        (state / "job.log").write_text("preserved log\n")
        # Would trigger heavy's recovery path if unknown meant inactive.
        (state / "job.cmd").write_bytes(os.fsencode(root) + b"\0/heavy\0")
        original = (state / "job.cmd").read_bytes()
        result = subprocess.run(
            ["bash", str(source), action, "job", "--", "false"],
            env=dict(env, TEST_MODE=mode), capture_output=True, text=True, timeout=10)
        assert result.returncode == expected, (mode, action, result)
        assert (state / "job.log").read_text() == "preserved log\n"
        assert (state / "job.cmd").read_bytes() == original
        assert not (state / "job.env").exists()
        print(f"PASS {mode} {action}: exit {expected}, records preserved")
