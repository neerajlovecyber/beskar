# Baseline (2026-11-11, branch feat/unified-surface at f6df51e, after phases 1 and 2)

2 monitors, current pleamar (`bin/pleamar`). GPU = `drm-memory-gtt` + `drm-memory-vram` summed from `/proc/<pid>/fdinfo`; PSS from `smaps_rollup`. Idle shell.

| Process | GPU MB | PSS MB | Threads |
| :--- | ---: | ---: | ---: |
| wallpaper | 125 | 32 | 17 |
| topbar | 120 | 47 | 38 |
| settings | 49 | 39 | 20 |
| lock | 0 | 38 | 16 |
| widgets | 136 | 64 | 25 |
| overlays | 195 | 75 | 73 |
| **Total** | **625** | **295** | **189** |

`pleamar --report topbar|overlays --seconds 8`: both "barely animated" (idle, nothing to judge).
Surfaces mapped by overlays at startup (log lines `surface … on …`): 32.

Reading: overlays (13 + 2 + 1 + banner surfaces, each x2 monitors) is the biggest GPU holder; the target of phase 3 is to
shrink it and topbar together. Compare against this table after each phase.

## After phases 3 and 4 (one process: desktop = wallpaper + topbar + overlays + settings; pleamar 0.8.0-exp.3)

| Process | GPU MB | PSS MB | Threads |
| :--- | ---: | ---: | ---: |
| desktop | 342 | 104 | 91 |
| widgets | 136 | 92 | 28 |
| lock | 0 | 44 | 16 |
| **Total** | **478** | **240** | **135** |

Before: 625 / 295 / 189. Mapped surfaces at startup: 8 (was 32).
