# Browser tabs

Desktop Shell can include open tabs in the launcher's `Focus` results. The
integration is optional and consists of a Firefox-compatible WebExtension and
a native messaging host built by the same flake.

## Launcher behavior

Normal `Focus` search combines open Hyprland windows with inactive browser
tabs. Active tabs stay represented by their browser window, avoiding duplicate
results. Prefix a query with `!` to search tabs only; a bare `!` lists recent
tabs.

Selecting a tab asks the extension to activate the tab, then focuses the
associated browser toplevel through Hyprland. The launcher does not simulate
clicks or depend on a browser remote
debugging port.

Browser identity is configuration, not a built-in application choice. Set the
desktop-entry ID, display name, and icon to match the Firefox-derived browser
that receives the extension.

## Data contract

The extension publishes the following fields for each non-private tab:

- title;
- `host:port`, derived with the URL parser;
- tab-group title and color, when supported;
- tab and window navigation IDs;
- active, focused, pinned, audible, and muted state;
- the browser-provided last-access time.

It does not publish the full URL. Incognito tabs are excluded and the extension
is not allowed in private windows.

The native host writes a mode-`0600` snapshot and Unix socket below:

```text
$XDG_RUNTIME_DIR/desktop-shell/
├── browser-tabs.json
└── browser-tabs.sock
```

The directory is mode `0700`. The snapshot is removed when the browser-native
connection closes. Activation requests include a per-connection session ID so
stale launcher results cannot address a later browser session.

## Installation

Enable browser tabs in the Home Manager module and install both browser-side
artifacts into the same Firefox-derived browser. The flake exposes
`browser-native-host` for a Nix browser wrapper and
`browser-extension-unsigned` as a development XPI. Normal Firefox release
profiles require a signed extension; deploy it through a supported signing or
policy channel rather than disabling signature checks in the everyday profile.

See [Installation](installation.md#browser-tab-integration) for the Nix wrapper
example.

After installation, restart the browser and verify the bridge:

```console
$ desktop-shell browser-tabs state-path
```

The printed snapshot appears only while the extension is connected. If it does
not, run `desktop-shell doctor` and inspect the browser's extension diagnostics
for a native-host registration error.

## Compatibility

The extension requires Firefox 140 or a compatible Gecko-derived browser. It
uses Manifest V3 and Firefox `browser.*` APIs, including the optional tab-groups
API. Browsers that remove native messaging, change the extension manifest
contract, or do not provide Firefox-compatible APIs are not supported by this
integration. The native host accepts one connected browser profile at a time;
start a second profile after closing the first profile's bridge connection.
