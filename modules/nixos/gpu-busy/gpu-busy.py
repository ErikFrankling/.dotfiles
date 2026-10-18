"""How busy each GPU really is, from the time the kernel bills to its clients.

amdgpu's own utilisation counter (`gpu_busy_percent`, and `average_gfx_activity`
in `gpu_metrics`, which nvtop's device total reads) is the power firmware's
activity monitor. With `power_dpm_force_performance_level=profile_peak` clock
gating is off and that monitor reads 100 whether the card is working or not.

The DRM fdinfo of every open GPU file does not depend on it: `drm-engine-gfx`
and friends are nanoseconds of engine time the scheduler has charged to that
client. Summing them over all clients of one card and dividing by wall time
gives the card's busy share per engine, which is what nvtop's per-process
column shows. The busiest engine is the card's figure.

Reading another user's fdinfo needs ptrace read access, and Hyprland is not
dumpable even to its own user, so this runs as a service with CAP_SYS_PTRACE
and CAP_DAC_READ_SEARCH.
Once a second it writes the percentage for each card to `<outdir>/<pci address>`,
which the shell reads instead of `gpu_busy_percent`.

Not counted: ROCm/KFD user queues, which bypass the DRM scheduler. Work that
goes through Vulkan, OpenGL or VA-API is all here.
"""

import os
import sys
import time

INTERVAL = 1.0

# Walking every fd of every process to find the GPU ones is most of the cost
# (16 ms on the desktop, against 1.4 ms for reading the 56 GPU ones), so the
# full walk runs every RESCAN samples. In between, only processes younger than
# YOUNG samples are walked: a new GPU client is nearly always a new process
# (llama-server, a browser's GPU process), and it opens the device a moment
# after it starts, so it is looked at for a few seconds rather than once.
RESCAN = 10
YOUNG = 3


def gpu_fds(pids):
    """Paths of the fdinfo files of every DRM device file the pids hold open."""
    found = []
    for pid in pids:
        fddir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fddir)
        except OSError:
            continue
        for fd in fds:
            try:
                if os.readlink(f"{fddir}/{fd}").startswith("/dev/dri/"):
                    found.append(f"/proc/{pid}/fdinfo/{fd}")
            except OSError:
                continue
    return found


def sample(paths):
    """{(pdev, client id): {engine: ns}} for every DRM client right now."""
    clients = {}
    for path in paths:
        try:
            with open(path) as f:
                text = f.read()
        except OSError:
            continue
        pdev = client = None
        engines = {}
        for line in text.splitlines():
            key, _, value = line.partition(":")
            if key == "drm-pdev":
                pdev = value.strip()
            elif key == "drm-client-id":
                client = value.strip()
            elif key.startswith("drm-engine-") and not key.startswith(
                "drm-engine-capacity-"
            ):
                engines[key[len("drm-engine-"):]] = int(value.split()[0])
        # A client shared between fds or processes (an fd passed over a
        # socket, a fork) has one id and must only be counted once.
        if pdev and client and engines:
            clients[(pdev, client)] = engines
    return clients


def write(outdir, pdev, percent):
    path = os.path.join(outdir, pdev)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"{percent}\n")
    os.replace(tmp, path)


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    tick = 0
    born = {pid: tick for pid in os.listdir("/proc") if pid.isdigit()}
    paths = set(gpu_fds(born))
    prev, prev_t = sample(paths), time.monotonic()
    while True:
        time.sleep(INTERVAL)
        tick += 1
        pids = [pid for pid in os.listdir("/proc") if pid.isdigit()]
        born = {pid: born.get(pid, tick) for pid in pids}
        if tick % RESCAN == 0:
            paths = set(gpu_fds(pids))
        else:
            paths = {p for p in paths if p.split("/")[2] in born}
            paths.update(gpu_fds(p for p in pids if tick - born[p] < YOUNG))
        cur, now = sample(paths), time.monotonic()
        dt_ns = (now - prev_t) * 1e9
        busy = {}
        for (pdev, client), engines in cur.items():
            per_engine = busy.setdefault(pdev, {})
            # A client that opened inside this interval has no baseline; one
            # that closed has taken its time with it. Both are under a second
            # of error on one sample, never a stuck reading.
            before = prev.get((pdev, client))
            if before is None:
                continue
            for engine, ns in engines.items():
                delta = ns - before.get(engine, ns)
                if delta > 0:
                    per_engine[engine] = per_engine.get(engine, 0) + delta
        for pdev in {p for p, _ in cur}:
            per_engine = busy.get(pdev, {})
            top = max(per_engine.values(), default=0)
            write(outdir, pdev, min(100, round(100 * top / dt_ns)))
        prev, prev_t = cur, now


if __name__ == "__main__":
    main()
