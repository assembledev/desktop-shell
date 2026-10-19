# Design notes

Desktop Shell is a compact, keyboard-first desktop control surface with cool
neutral text, semantic accents, and translucent surfaces.

Defaults live in [nix/theme.nix](nix/theme.nix). Runtime theme resolution and
shared shape tokens belong to [Theme.qml](src/modules/common/Theme.qml);
configured theme overrides take precedence over defaults. See
[Configuration](docs/configuration.md#theme) for the supported interface.
Keep values in their code owners rather than copying them into this document.

- Use text roles consistently across surfaces: `textPrimary` for emphasis,
  `textSecondary` for ordinary content, `textMuted` for supporting detail, and
  `textDisabled` only for unavailable controls. Empty states remain readable
  content. Avoid reducing text contrast with additional opacity.
- Use `accent` for navigation and focus, domain accents for compact wayfinding
  markers, and state colors for outcomes or problems. State takes precedence
  over domain identity; keep long text on the neutral hierarchy.
- Use semantic surface tokens and borders for depth. Surface tokens own
  opacity; the compositor owns backdrop blur. Check legibility against both
  light and dark wallpapers.
- Use `uiFontFamily` for UI text and `fontFamily` for existing font icons.
  Reuse shared controls and `ShellSymbol`; keep symbols centered and hover
  feedback aligned with the full actionable shape.
- Preserve visible keyboard focus, meaningful accessible names, and the
  backend's authoritative pending, error, and recovery states.
- Keep related controls compact and groups distinguishable. Components own
  their geometry; bar spacing belongs to
  [BarSpacing.qml](src/modules/bar/BarSpacing.qml), and animation roles belong
  to [Motion.qml](src/modules/common/Motion.qml).
