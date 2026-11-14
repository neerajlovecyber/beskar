# Runtime and panel clearing

Current runtime: upstream `v0.8.0-exp.16` (`a6286bd8eabfbe4762698e32d9fd49ca6329653f`),
pinned by `shell/runtime.sh`. This was the latest tag checked on 2026-11-14.
The release build used `cargo build --release --locked`; no Rust source patches
were made. The previous exp.8 binary remains beside it for rollback.

## Residual notification and centre-panel content

The reported pale shadow was retained panel content, including readable notification
labels and calendar cells. The panel owner was closed and each scene's `seen` spring
was zero, so this was not an intentional shadow, still-open panel or extra surface
introduced by reusable controls.

The artifact reproduced with both exp.8 and exp.15 using pleamar's default own-frame,
partial-damage buffer path on the live niri/AMD session. Exp.15's upstream repaint
fixes did not fully eliminate it here. A transparent helper draw was tried and removed;
it did not consistently clear notifications. No such helper or permanently mapped
closed panels are part of the fix.

`supervise.sh` sets `PLEAMAR_SWAPCHAIN=1` in the child that runs `desktop.plm`.
That selects pleamar's driver-managed swapchain for the process that owns the frame,
Settings and panel scenes. It is applied at startup rather than relying on a
one-session environment override. Wallpaper, widgets and lock are not given this
flag by the supervisor. Their separate processes and layer ownership remain intact.

## Scope and cost

This adds no surface, process, service subscription, animation or polling callback.
Closed panels keep their normal lifecycle, empty input region and keyboard release.
The driver-managed path repaints changed surfaces as whole frames; it gives up the
own-buffer partial-repaint optimization. This is a correctness workaround, not a
claim of free or faster rendering. A controlled frame-time benchmark has not been
performed. Latest-runtime memory/expression improvements are upstream changes and
are not presented as measurements of this shell.

For diagnosis after an upstream buffer fix, launch the shell with
`BESKAR_DESKTOP_SWAPCHAIN=0` to leave the desktop on the default buffer path.
The default is 1; ordinary login and restart therefore retain the fix.

## Verification

All production scene compile checks passed under exp.16: combined desktop, widgets,
wallpaper, lock and capture. The lock was compiled, never activated for testing.

Notification, Today and music panels were opened and closed over a stable desktop
region. The test captured a baseline and compared the same pixels after closure.
The own-frame path visibly retained content; with the swapchain, all three tested
regions returned to the baseline with **zero changed pixels** (channel tolerance 6).
The panels reported closed, and captures confirmed that labels/calendar cells were
gone. The normal-startup path and both monitors are checked separately so that the
workaround does not depend on a temporary environment setting.

Exp.16 appeared during verification and replaced exp.15 before completion. It adds
opt-in deferred includes; its buffer path is unchanged, so the tested desktop
swapchain setting is retained. The normal-startup close checks were repeated on
the final runtime. HDMI's background video moves, so exact pixel comparison there
is inconclusive for the centre regions; visual inspection checks that no panel
content remains. Exact baseline equality was measured on the stable eDP regions.
