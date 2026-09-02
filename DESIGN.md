# Desktop Shell design system

## Direction

Desktop Shell uses the Graphite Aurora language: an ink-indigo canvas, cool
neutral content, and a coordinated band of iris, cyan, orchid, mint, amber,
coral, and rose. It is a desktop control surface, so color must provide
wayfinding even before interaction. Every major surface keeps one or two small
chromatic anchors—icons, markers, badges, rails, or borders—while long text
stays on the neutral hierarchy.

The shell is compact and keyboard-first. Density should make information quick
to scan without collapsing the gaps that separate controls, status groups, and
content regions.

## Color roles

### Surfaces

| Token | Default | Role |
| --- | --- | --- |
| `bgSolid` | `#151725` | Opaque canvas and contrast anchor |
| `bgMuted` | `#1c2030` | Quiet controls and wells |
| `bgRaised` | `#23283b` | Raised panels and cards |
| `bgHover` | `#303650` | Hovered interactive surfaces |
| `selectedBg` | `#3a4060` | Selected content behind neutral text |
| `border` | `#424a68` | Default structural border |
| `borderMuted` | `#343b55` | Low-emphasis control border |

Translucent `surface*` tokens derive from this ladder. Depth is expressed by a
surface step plus a hairline border, not by decorative shadows or unrelated
color tints.

### Text

| Token | Default | Role |
| --- | --- | --- |
| `textPrimary` | `#eef0f8` | Active titles, selected content, important values |
| `textSecondary` | `#c7ccdc` | Default labels, body copy, ordinary status values |
| `textMuted` | `#929cb2` | Metadata, timestamps, shortcuts, section labels |
| `textDisabled` | `#69748b` | Disabled controls only |
| `textOnAccent` | `#151725` | Content on a solid accent fill |

Use one role consistently across every surface. A section title does not gain a
different color because it belongs to audio, Bluetooth, calendars, or media.
Empty-state messages remain readable content and use `textSecondary` or
`textMuted`; they are not disabled controls.

Do not combine `textMuted` or `textDisabled` with arbitrary opacity. Opacity is
reserved for transitions, occlusion, and genuinely inactive spatial context.

### Navigation and domain accents

| Token | Default | Role |
| --- | --- | --- |
| `accent` | `#a78bfa` | Primary navigation, generic focus, selection |
| `accentHover` | `#c4b5fd` | Strong primary-accent feedback |
| `info` | `#67d4e8` | Connectivity, audio output, displays, data flow |
| `special` | `#d08cf3` | Bluetooth, media, focus mode, move destinations |
| `resource` | `#9ece6a` | Resource metrics and existing/open targets |
| `utility` | `#f0c36e` | Keyboard, brightness, launch/profile affordances |

Domain accents are persistent wayfinding, not state. Their default values may
share a hue with a state token, but they remain separate configuration fields
so a theme can change one without changing the other.

### State

| Token | Default | Role |
| --- | --- | --- |
| `success` | `#9ece6a` | Confirmed success, charging, connected status |
| `warning` | `#f0c36e` | Warning and degraded thresholds |
| `caution` | `#f3a66e` | Elevated but permitted values, such as audio boost |
| `danger` | `#f283a2` | Failure and destructive action |
| `dangerStrong` | `#ff7898` | Urgent danger feedback and recording indicator |

State always overrides domain. A low battery is warning or danger, not
resource; a failed Bluetooth action is danger, not special. Prefer a small
state dot, border, or icon over recoloring an entire label.

## Icons

Nerd Font glyphs are icons even when implemented with QML `Text`. Use
`iconPrimary`, `iconSecondary`, `iconMuted`, and `iconAccent` according to the
same hierarchy as content. A persistent domain-colored icon is encouraged when
it helps identify a dense control group; its adjacent value normally remains
`textSecondary`.

## Component contract

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

## Contrast and verification

On the default opaque raised surface, primary, secondary, and muted text have
contrast ratios of approximately 12.8:1, 9.1:1, and 5.3:1. Useful text must
remain at least 4.5:1 after the translucent surface is composited over both
light and dark wallpapers. Disabled controls may fall below that threshold,
but their labels must not carry information needed to recover.

Review every change in normal, focused, selected, warning, danger, and disabled
states. A grayscale view should preserve the information hierarchy.

## Avoid

- Long feature-colored headings or body text without an interaction/state
  reason.
- A shell where all domain accents collapse to one hue or disappear at rest.
- Multiple equal-brightness whites with different color temperatures.
- Blue, purple, yellow, or green used only to make a module feel distinct.
- Low-contrast content created by a muted token plus opacity.
- Direct use of pre-semantic palette aliases in shell components.
