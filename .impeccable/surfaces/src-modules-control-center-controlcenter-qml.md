---
version: 1
slug: "src-modules-control-center-controlcenter-qml"
primary_target: "src/modules/control_center/ControlCenter.qml"
related_targets: ["src/modules/common/Theme.qml"]
---

# Control Center — Operate

Audience: desktop user adjusting devices and reviewing real notification history. Task: quick radio, brightness and audio changes; connected devices; safe display changes; actionable notifications. Preserve the existing native backends, layer-shell attachment, focus ownership, discovery lifetime and display recovery.

## Direction contract

THESIS: Implement the user-selected Unified option A: stable quick controls above independently scrolling history; detailed audio lives behind Sound.

OWN-WORLD: Use the shared Graphite Aurora palette and semantic theme roles. Use the shared UI font role consistently across all shell text while retaining the glyph font for icons. Extend the shared kit with glass task groups, authored vector symbols and native keyboard-capable controls. Keep theme overrides authoritative.

STORY: See current state immediately, adjust a level, enter a device page for details, then return to complete retained history. Real errors and pending actions stay visible.

FIRST VIEWPORT: A 436px right-attached, full-height panel beneath the bar. Header and close; grouped connectivity beside DND/Focus; Display and Sound groups; Notifications heading, count and Clear all; expanding scroll region. Compact controls on short displays preserve useful history space. The separate power menu owns Lock and Power; this panel has no duplicated footer actions.

FORM: User-selected option A, Unified, from the saved native QML prototype. Seed key: user-approved-Unified-A; no new concept round. Approved screenshot supplies composition; the user explicitly requires the unified desktop-shell theme.

CORRECTIONS: Full-shape hover feedback, vertically centered titles/chevrons and square icon targets; flat Wi-Fi/Bluetooth lists with separators; explicit keyboard-open focus and meaningful accessible names. Use existing surfaceGlassStrong/surfaceRaised/surfaceHover transparency with compositor-owned blur. Unmuted audio icons are info cyan; muted icons are danger rose, with distinct glyphs. Keep the Notifications heading row at 32px whether empty or populated.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
