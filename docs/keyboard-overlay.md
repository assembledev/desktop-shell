# Glove80 overlay

`desktop-shell keyboard-overlay toggle` shows or hides a live Glove80 map.
Tap the desktop's shared F9 shortcut to toggle. Hold F9 for 250 ms to enable
moving, then drag anywhere on the overlay with the left mouse button. Release
F9 to restore click-through, even if the mouse button is still held. Holding F9
also opens a hidden overlay. Position is retained until the shell restarts and
clamped to the screen. F9 is consumed, so applications do not receive it.

The overlay shows both halves, staggered columns and angled thumbs using geometry
read from the keyboard. Labels come from its current bindings and active layers;
transparent keys inherit from the next active layer. Tap/hold keys show the hold
action beneath the tap action. Macros currently display their numeric identifier,
not their operation sequence. Combos are not drawn.

It uses translucent key fills and outlines without a panel background or footer.
It is a non-focusable Wayland overlay above fullscreen windows, click-through
except during the deliberate F9 hold.
It does not capture keystrokes, highlight pressed keys, reserve screen space,
or pause a game. Hide it when its contents obstruct something you need to see.
The compositor shortcut remains available through application shortcut inhibitors.

## Connection

Use an already connected Glove80 with compatible MoErgo RMK/Rynk firmware over
Bluetooth. No USB connection, pairing prompt, layout file, or firmware change is
required. The reader uses BlueZ and the pinned upstream Rynk protocol client.
It never writes keyboard configuration or changes layers.

Opening reads geometry, bindings and layer metadata, then listens for firmware
layer notifications. Each notification triggers an authoritative layer-state
snapshot; there is no periodic polling. Initial loading can take several seconds.
Closing terminates the reader and releases its GATT notification subscription,
without disconnecting the keyboard's normal Bluetooth input connection.

If disconnected, the map is dimmed and a connection message appears. Reconnection
uses backoff up to 30 seconds. If more than one compatible keyboard is connected,
the reader refuses to guess. USB-only operation is not supported by this reader.
Close the overlay while editing with another Rynk client; simultaneous configuration
sessions are not qualified. Reopen after editing to reload the bindings.

## Ownership and verification

`src/keyboard-overlay` owns the read-only device session and emits JSON lines.
`src/modules/keyboard_overlay` owns presentation and reader lifetime. Nix packages
the Rust helper with the shell. Firmware and personal-layout repositories are
not runtime dependencies. The hotkey belongs to desktop configuration.

The upstream protocol revision is pinned in Cargo.toml and Cargo.lock; update it
with a compatible firmware version and rerun the packaged build and device check.
`nix flake check` includes the helper's Rust tests through its package build.
Manual qualification must check physical layer transitions, reconnect, closing
while keys are held, and fullscreen focus on the target desktop. Host tests do not
establish end-to-end latency or battery cost; neither has been measured.
