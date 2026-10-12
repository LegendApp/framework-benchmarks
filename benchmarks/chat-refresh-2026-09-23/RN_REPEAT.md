# React Native repeat — September 24, 2026

Same built app and fixture hashes as the full-suite run; no rebuild or code change. Two discarded warmups, ten measured timing launches, and ten separate unrecorded memory launches. All ten videos, unlocked-session checks, content digests and bundle-hash checks passed; no failed attempts.

| Metric | Full-suite median | RN-only repeat median | Change |
| --- | ---: | ---: | ---: |
| Window | 258.9 ms | 244.6 ms | -14.3 ms |
| First content | 409.6 ms | 378.4 ms | -31.1 ms |
| Jump | 71.0 ms | 54.4 ms | -16.6 ms |
| Switch | 200.5 ms | 202.3 ms | +1.8 ms |
| Initial memory | 55.5 MiB | 54.6 MiB | -0.9 MiB |
| Top memory | 60.0 MiB | 59.1 MiB | -0.9 MiB |
| Switched memory | 66.2 MiB | 65.9 MiB | -0.3 MiB |

First-content p90 was 426.3 → 394.7 ms. Individual first-content values in the repeat: 377.9, 378.1, 394.8, 394.7, 394.5, 394.4, 377.7, 378.3, 378.5, 361.9 ms.

App-reported readiness shifted 324.0 → 316.1 ms, while video-visible first content shifted 409.6 → 378.4 ms. Thus only part of the visible difference appears in internal readiness; frame presentation/capture alignment and scheduling can contribute, but this run does not isolate their causes. Native initial document work was 35.5 → 29.9 ms; switching remained essentially unchanged.

This repeat ran RN consecutively, whereas the full suite rotated frameworks. It demonstrates session/order sensitivity with identical code, not a code optimization or a controlled baseline/candidate comparison. Keep the full-suite table intact and show this repeat separately rather than selecting the faster result as the sole framework ranking.

[Raw report and recordings](../../ChatHistory/benchmark/results/2026-09-24T07-22-52.021Z.md) · [Original full-suite report](RESULTS.md).
