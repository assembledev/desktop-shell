---
name: "Desktop Shell — Graphite Aurora"
description: "Compact native desktop controls with cool neutrals and semantic aurora accents."
colors:
  surfaceGlassStrong: "#151725ca"
  surfaceRaised: "#23283bb8"
  surfaceHover: "#303650bd"
  bgSolid: "#151725"
  bgRaised: "#23283b"
  bgMuted: "#1c2030"
  bgHover: "#303650"
  bgHoverAlt: "#2a3047"
  bgToast: "#191c2b"
  selectedBg: "#3a4060"
  textPrimary: "#eef0f8"
  textSecondary: "#c7ccdc"
  textMuted: "#929cb2"
  textDisabled: "#69748b"
  textOnAccent: "#151725"
  accent: "#a78bfa"
  accentHover: "#c4b5fd"
  info: "#67d4e8"
  special: "#d08cf3"
  resource: "#9ece6a"
  utility: "#f0c36e"
  success: "#9ece6a"
  warning: "#f0c36e"
  caution: "#f3a66e"
  danger: "#f283a2"
  dangerStrong: "#ff7898"
  border: "#424a68"
  borderMuted: "#343b55"
typography:
  headline:
    fontFamily: "sans-serif"
    fontSize: "20px"
    fontWeight: 700
  title:
    fontFamily: "sans-serif"
    fontSize: "14px"
    fontWeight: 700
  label:
    fontFamily: "sans-serif"
    fontSize: "12px"
    fontWeight: 700
  body:
    fontFamily: "sans-serif"
    fontSize: "12px"
    fontWeight: 400
  caption:
    fontFamily: "sans-serif"
    fontSize: "10px"
    fontWeight: 400
  legacy-icon:
    fontFamily: "FiraCode Nerd Font"
rounded:
  control: "6px"
  group: "14px"
spacing:
  control-padding: "6px"
  content-gap: "10px"
  group-inset: "12px"
components:
  button:
    backgroundColor: "{colors.bgMuted}"
    textColor: "{colors.textPrimary}"
    rounded: "{rounded.control}"
    height: "32px"
  button-hover:
    backgroundColor: "{colors.bgHover}"
  icon-button:
    rounded: "{rounded.control}"
    height: "32px"
    width: "32px"
  task-surface:
    backgroundColor: "{colors.surfaceRaised}"
    textColor: "{colors.textPrimary}"
    rounded: "{rounded.group}"
  group:
    backgroundColor: "{colors.surfaceRaised}"
    rounded: "{rounded.group}"
  slider:
    height: "28px"
  switch:
    height: "32px"
    width: "42px"
---

# Desktop Shell design system

## Overview

**Creative North Star: "Graphite Aurora"**

Desktop Shell uses the Graphite Aurora language: an ink-indigo canvas, cool
neutral content, and a coordinated band of iris, cyan, orchid, mint, amber,
coral, and rose. It is a desktop control surface, so color must provide
wayfinding even before interaction. Every major surface keeps one or two small
chromatic anchors—icons, markers, badges, rails, or borders—while long text
stays on the neutral hierarchy.

The shell is compact and keyboard-first. Density should make information quick
to scan without collapsing the gaps that separate controls, status groups, and
content regions.

## Colors

The frontmatter records defaults from `nix/theme.nix` and the matching QML
fallback. Its translucent colors use portable alpha-last notation; runtime
Qt tokens use the equivalent alpha-first form. Runtime overrides remain
authoritative. Opacity belongs to the semantic surface token, not a separate
component tint.

### Surfaces

| Token | Role |
| --- | --- |
| `bgSolid` | Opaque canvas and contrast anchor |
| `bgMuted` | Quiet controls and wells |
| `bgRaised` | Raised panels and cards |
| `bgHover` | Hovered interactive surfaces |
| `selectedBg` | Selected content behind neutral text |
| `border` | Default structural border |
| `borderMuted` | Low-emphasis control border |

Translucent `surface*` tokens derive from this ladder. Depth is expressed by a
surface step plus a hairline border, not by decorative shadows or unrelated
color tints.

### Text

| Token | Role |
| --- | --- |
| `textPrimary` | Active titles, selected content, important values |
| `textSecondary` | Default labels, body copy, ordinary status values |
| `textMuted` | Metadata, timestamps, shortcuts, section labels |
| `textDisabled` | Disabled controls only |
| `textOnAccent` | Content on a solid accent fill |

Use one role consistently across every surface. A section title does not gain a
different color because it belongs to audio, Bluetooth, calendars, or media.
Empty-state messages remain readable content and use `textSecondary` or
`textMuted`; they are not disabled controls.

Do not combine `textMuted` or `textDisabled` with arbitrary opacity. Opacity is
reserved for transitions, occlusion, and genuinely inactive spatial context.

### Navigation and domain accents

| Token | Role |
| --- | --- |
| `accent` | Primary navigation, generic focus, selection |
| `accentHover` | Strong primary-accent feedback |
| `info` | Connectivity, audio output, displays, data flow |
| `special` | Bluetooth, media, focus mode, move destinations |
| `resource` | Resource metrics and existing/open targets |
| `utility` | Keyboard, brightness, launch/profile affordances |

Domain accents are persistent wayfinding, not state. Their default values may
share a hue with a state token, but they remain separate configuration fields
so a theme can change one without changing the other.

### State

| Token | Role |
| --- | --- |
| `success` | Confirmed success, charging, connected status |
| `warning` | Warning and degraded thresholds |
| `caution` | Elevated but permitted values, such as audio boost |
| `danger` | Failure and destructive action |
| `dangerStrong` | Urgent danger feedback and recording indicator |

State always overrides domain. A low battery is warning or danger, not
resource; a failed Bluetooth action is danger, not special. Prefer a small
state dot, border, or icon over recoloring an entire label.

### Contrast and verification

On the default opaque raised surface, primary, secondary, and muted text have
contrast ratios of approximately 12.8:1, 9.1:1, and 5.3:1. Useful text must
remain at least 4.5:1 after the translucent surface is composited over both
light and dark wallpapers. Disabled controls may fall below that threshold,
but their labels must not carry information needed to recover.

Review every change in normal, focused, selected, warning, danger, and disabled
states. A grayscale view should preserve the information hierarchy.

## Typography

`Theme.uiFontFamily` is the UI text role across every shell surface. Its default
is the fontconfig alias `sans-serif`; named overrides apply to labels, content,
metadata and inputs together. `Theme.fontFamily` remains the family for existing
Nerd Font icons. New control symbols use authored vectors through `ShellSymbol`
and do not depend on font metrics.

The frontmatter type ramp describes the shared control kit, in QML logical
pixels. Individual surfaces choose their own sizes within their information
hierarchy: a lock clock, calendar date and compact bar label are different roles,
but share the UI family. Plain text must not accidentally inherit the icon font.

## Layout

Use measured content, explicit control dimensions and tight internal groups.
The control kit uses a 10px content gap and 12px group insets; the bar has its own
semantic spacing owner, `BarSpacing.qml`. Do not treat one surface's spacing
constants as a universal grid.

Attached panels use the available area beneath the bar. The Control Center has
a maximum width of 436px, with stable quick controls above independently
scrolling history. `QuickControls` selects its compact layout when the main
content area is below 600px high. Device lists are flat rows with hairline
separators rather than nested rounded containers.

## Elevation & Depth

Depth comes from the existing tonal surface ladder and hairline borders.
The Control Center canvas uses `surfaceGlassStrong`, groups and history cards
use `surfaceRaised`, and task hovers use `surfaceHover`. The compositor owns
backdrop blur; the shell supplies transparent native surfaces. Decorative
shadows and locally invented opacity constants are not part of the control kit.

## Shapes

`Theme.groupRadius` (14px) belongs to shared glass groups and standalone task
surfaces. `Theme.controlRadius` (6px) belongs to small action buttons. A grouped
row rounds only the outside corners it owns. Its hover background fills the
whole actionable rectangle and repeats those corners.

Authored symbols use one square 24-unit viewBox and a 1.8-unit rounded stroke.
`ShellSymbol` centers a fixed square image inside its assigned layout slot;
button backgrounds and symbol bounds do not depend on font ascent or descent.

## Components

- Panel title: `textPrimary`.
- Default row title or value: `textSecondary`; promote to `textPrimary` when it
  is the current focus or the main content of the surface.
- Section label, count, timestamp, shortcut, or supporting detail:
  `textMuted`.
- Selected or focused target: accent surface/border/icon; keep long text on the
  neutral text ladder.
- Section identity: neutral label plus a domain-colored marker, not a colored
  paragraph or heading.
- Error text and destructive actions: `danger`; warning text only when the user
  needs to notice a degraded or risky state.
- Links: `accent`, with non-color feedback for hover or focus.


### Native controls

- `ShellButton`: native button with a centered icon/label row, shared hover
  color and visible keyboard focus. Icon-only targets are 32px squares.
- `ShellTaskButton`: native task or disclosure button. Hide empty subtitles,
  center the title and chevron vertically, and match hover to the entire target.
- `ShellGroup`: glass tonal container with the shared group radius and border.
- `ShellSlider`: native keyboard-capable slider with an 8px rail, 18px handle,
  visible focus and a caution segment when boost is allowed.
- `ShellSwitch`: native switch with a 36×22px visual track inside its 42×32px
  target, an 18px thumb, authoritative state binding and visible focus.
- `ConnectivityRow`: separate native radio toggle and detail-navigation targets,
  with domain accents and the outside corners of its containing group.

Clipboard history uses the same native icon buttons, vector symbols and UI
font role. Its centered picker keeps search and list navigation together;
selection uses an accent outline on `surfaceRaised`, while row hover uses
`surfaceHover`.

Use the existing `Motion` roles. Hover feedback changes color over 120ms without
moving the glyph or shrinking the hit target. Audio mute icons use `info` cyan when unmuted and `danger` rose when muted,
with a distinct muted glyph. Each control needs a contextual accessible name; pending and error states remain tied to the owning backend.

## Do's and Don'ts

- Don't use long feature-colored headings or body text without an interaction/state
  reason.
- Don't create a shell where all domain accents collapse to one hue or disappear at rest.
- Don't use multiple equal-brightness whites with different color temperatures.
- Don't use blue, purple, yellow, or green only to make a module feel distinct.
- Don't reduce contrast by combining a muted token with opacity.
- Don't use pre-semantic palette aliases in shell components.
- Do use the UI font role consistently and keep glyph fonts on icon-only text.
- Do center symbol bounds inside their targets and cover every rounded edge on hover.
- Do keep device lists flat and preserve the backend's real states and recovery.
