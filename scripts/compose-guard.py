#!/usr/bin/env python3
"""Run the local toolchain with a monitored 50 GB disk reserve."""
import os, signal, subprocess, sys

def available():
    return int(subprocess.check_output(['df', '-k', '/System/Volumes/Data'], text=True).splitlines()[1].split()[3]) * 1024
if available() < 55_000_000_000:
    sys.exit('Insufficient headroom for Compose build; preserve the 50 GB reserve.')
p = subprocess.Popen(sys.argv[1:], start_new_session=True)
try:
    while p.poll() is None:
        if available() <= 50_000_000_000:
            os.killpg(p.pid, signal.SIGTERM)
            sys.exit('50 GB disk reserve reached; stopped Compose operation.')
        try: p.wait(timeout=20)
        except subprocess.TimeoutExpired: pass
finally:
    if p.poll() is None:
        os.killpg(p.pid, signal.SIGTERM)
        try: p.wait(timeout=10)
        except subprocess.TimeoutExpired: os.killpg(p.pid, signal.SIGKILL)
if available() <= 50_000_000_000: sys.exit('50 GB disk reserve reached after Compose operation.')
sys.exit(p.returncode)
