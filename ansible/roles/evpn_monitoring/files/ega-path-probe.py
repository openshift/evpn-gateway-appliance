"""Ping one overlay target and publish the result through node-exporter's textfile collector.

ping -c 3 -w 5 sends up to 5 requests and exits 1 unless 3 replies arrive within 5s, so success
means at most 2 of 5 lost. Any other failure (bad target, no socket, no route to the target) exits
without writing and lets the stale textfile report the probe as unavailable. The result is
published 5s after the start whatever the outcome: a success is known in about 2s and a failure
only at the deadline, so rule samples at fixed times would miss some failures.
"""

import os
import re
import signal
import subprocess
import sys
import tempfile
import time

PACE_SECONDS = 5.0
RESULT = """\
# HELP ega_path_probe_success 1 if 3 echo replies arrived within 5s (up to 5 requests), else 0.
# TYPE ega_path_probe_success gauge
ega_path_probe_success{{target="{target}"}} {success}
# HELP ega_path_probe_rtt_seconds Average round-trip time of the 3 echo replies in seconds, only on success.
# TYPE ega_path_probe_rtt_seconds gauge
"""
RTT = re.compile(r"^rtt [^=]*= [0-9.]+/([0-9.]+)/", re.MULTILINE)


def main(argv: list[str]) -> int:
    if len(argv) != 3 or not argv[1] or not argv[2]:
        print("usage: ega-path-probe.py TARGET OUTPUT", file=sys.stderr)
        return 2
    target, output = argv[1], argv[2]
    start = time.monotonic()
    reply = subprocess.run(
        ["ping", "-n", "-q", "-c", "3", "-w", "5", target],
        stdout=subprocess.PIPE, text=True, env={**os.environ, "LC_ALL": "C"}, check=False,
    )
    if reply.returncode not in (0, 1):
        return reply.returncode
    result = RESULT.format(target=target, success=int(reply.returncode == 0))
    rtt = RTT.search(reply.stdout) if reply.returncode == 0 else None
    if rtt:
        seconds = float(rtt.group(1)) / 1000
        result += f'ega_path_probe_rtt_seconds{{target="{target}"}} {seconds:.9f}\n'
    time.sleep(max(0.0, PACE_SECONDS - (time.monotonic() - start)))
    # The temporary file must share the output's filesystem for the rename to be atomic, and
    # must not end in .prom, which the collector would read.
    directory = os.path.dirname(output) or "."
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(output) + ".", dir=directory)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(result)
        os.chmod(tmp, 0o644)
        os.replace(tmp, output)
    except BaseException:
        os.unlink(tmp)
        raise
    return 0


if __name__ == "__main__":
    # Turn systemd's SIGTERM and a SIGHUP into SystemExit so a partly written file is removed.
    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, lambda *_: sys.exit(1))
    sys.exit(main(sys.argv))
