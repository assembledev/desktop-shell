pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../common"

Scope {
  id: root

  Theme {
    id: theme
  }

  ShellConfig { id: shellConfig }
  MotionTransition {
    id: surfaceTransition
    requested: root.open
  }

  property string hotkeysPath: Quickshell.env("DESKTOP_SHELL_HOTKEYS_JSON")
  property bool open: false
  property var entries: []
  property var categories: []
  property string message: ""

  readonly property var categoryOrder: [
    "Shell",
    "Windows",
    "Workspaces",
    "Apps",
    "Utilities"
  ]
  readonly property var columnOrder: [
    ["Shell", "Utilities"],
    ["Windows"],
    ["Apps", "Workspaces"]
  ]

  function openSheet() {
    open = true;
  }

  function closeSheet() {
    open = false;
  }

  function toggleSheet() {
    if (open)
      closeSheet();
    else
      openSheet();
  }

  function loadHotkeys(raw) {
    try {
      const parsed = JSON.parse(raw);
      const hotkeys = Array.isArray(parsed)
        ? parsed
        : (parsed?.integrations?.hotkeys || []);
      entries = hotkeys.filter(function(item) {
        return item && !item.hidden && String(item.key || "").length > 0 && String(item.title || "").length > 0;
      });
      message = "";
    } catch (error) {
      entries = [];
      message = "Failed to read hotkeys";
      console.error("cheatsheet: JSON parse failed: " + error);
    }

    buildCategories();
  }

  function orderCategory(name) {
    const index = categoryOrder.indexOf(name);
    return index >= 0 ? index : categoryOrder.length + 1;
  }

  function buildCategories() {
    const groups = {};
    const merged = {};

    for (const entry of entries) {
      const category = String(entry.category || "Other");
      const mergeKey = category + "\u0000" + String(entry.title || "") + "\u0000" + String(entry.description || "");

      if (!merged[mergeKey]) {
        merged[mergeKey] = {
          category: category,
          title: entry.title,
          description: entry.description || "",
          keys: [],
          displayKeys: []
        };
      }

      merged[mergeKey].keys.push(entry.key);
    }

    for (const key in merged) {
      const entry = merged[key];
      const category = entry.category;
      entry.displayKeys = compactKeys(entry.keys);
      if (!groups[category])
        groups[category] = [];
      groups[category].push(entry);
    }

    categories = Object.keys(groups).sort(function(a, b) {
      const order = orderCategory(a) - orderCategory(b);
      return order !== 0 ? order : a.localeCompare(b);
    }).map(function(name) {
      return { name: name, entries: groups[name] };
    });
  }

  function categoryByName(name) {
    for (const category of categories) {
      if (category.name === name)
        return category;
    }
    return null;
  }

  function columnCategories(column) {
    const result = [];
    for (const name of columnOrder[column]) {
      const category = categoryByName(name);
      if (category)
        result.push(category);
    }
    if (column === 2) {
      for (const category of categories) {
        if (categoryOrder.indexOf(category.name) < 0)
          result.push(category);
      }
    }
    return result;
  }

  function keyPrefixAndTail(key) {
    const parts = String(key || "").split(" + ");
    if (parts.length === 0)
      return null;

    return {
      prefix: parts.slice(0, parts.length - 1).join(" + "),
      tail: parts[parts.length - 1]
    };
  }

  function numericTail(tail) {
    const value = String(tail || "");
    let match = value.match(/^F([0-9]+)$/);
    if (match)
      return { kind: "F", number: Number(match[1]), width: 0 };

    match = value.match(/^([0-9]+)$/);
    if (match)
      return { kind: "", number: Number(match[1]), width: value.length };

    return null;
  }

  function compactKeys(keys) {
    const byPrefixAndKind = {};
    const passthrough = [];

    for (const key of keys) {
      const parsed = keyPrefixAndTail(key);
      const tail = parsed ? numericTail(parsed.tail) : null;

      if (!parsed || !tail) {
        passthrough.push(key);
        continue;
      }

      const groupKey = parsed.prefix + "\u0000" + tail.kind + "\u0000" + tail.width;
      if (!byPrefixAndKind[groupKey]) {
        byPrefixAndKind[groupKey] = {
          prefix: parsed.prefix,
          kind: tail.kind,
          width: tail.width,
          numbers: []
        };
      }

      byPrefixAndKind[groupKey].numbers.push(tail.number);
    }

    const compacted = [];
    for (const groupKey in byPrefixAndKind) {
      const group = byPrefixAndKind[groupKey];
      const numbers = group.numbers.sort(function(a, b) { return a - b; });
      let start = numbers[0];
      let end = numbers[0];

      function pushRange(from, to) {
        const left = group.kind + String(from).padStart(group.width, "0");
        const right = group.kind + String(to).padStart(group.width, "0");
        const tail = from === to ? left : left + "-" + right;
        compacted.push(group.prefix.length > 0 ? group.prefix + " + " + tail : tail);
      }

      for (let i = 1; i < numbers.length; i++) {
        if (numbers[i] === end + 1) {
          end = numbers[i];
          continue;
        }

        pushRange(start, end);
        start = numbers[i];
        end = numbers[i];
      }

      pushRange(start, end);
    }

    return compacted.concat(passthrough);
  }

  function displayKeyToken(token) {
    const value = String(token || "");
    const map = {
      "SUPER": "Super",
      "ALT": "Alt",
      "ALT_L": "Left Alt",
      "ALT_R": "Right Alt",
      "CTRL": "Ctrl",
      "SHIFT": "Shift",
      "Slash": "/",
      "left": "Left",
      "right": "Right",
      "up": "Up",
      "down": "Down",
      "mouse:272": "LMB",
      "mouse:273": "RMB"
    };

    return map[value] || value;
  }

  function displayKey(key) {
    return String(key || "").split(" + ").map(displayKeyToken).join(" + ");
  }

  Component.onCompleted: {
    if (hotkeysPath.length === 0)
      message = "No hotkey source";
  }

  FileView {
    id: hotkeysFile
    path: root.hotkeysPath
    preload: true
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.loadHotkeys(text())
    onLoadFailed: function() {
      root.entries = [];
      root.message = "Failed to read hotkeys";
      root.buildCategories();
    }
  }

  function keys(entry) {
    const displayed = entry.displayKeys;
    const parts = displayed.map(function(key) { return root.keyPrefixAndTail(key); });
    const arrows = ["left", "up", "down", "right"];
    if (parts.length === 4 && parts.every(function(part) { return part.prefix === parts[0].prefix; })
        && arrows.every(function(arrow) { return parts.some(function(part) { return part.tail === arrow; }); }))
      return root.displayKey(parts[0].prefix) + " + ← ↑ ↓ →";
    return displayed.map(function(key) {
      const arrowNames = {left: "←", right: "→", up: "↑", down: "↓"};
      return String(key).split(" + ").map(function(token) {
        return arrowNames[token] || root.displayKeyToken(token);
      }).join(" + ").replace(/(F?\d+)-(F?\d+)/g, "$1–$2");
    }).join("\n");
  }
  component ReferenceText: Text {
    color: theme.textPrimary
    font.family: theme.uiFontFamily
    font.pixelSize: 13
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
  }
  function keyTokens(sequence) {
    const tokens = [];
    for (const key of String(sequence).split(" + ")) {
      if (tokens.length > 0) tokens.push("+");
      tokens.push(key === "SPACE" ? "Space" : key);
    }
    return tokens;
  }
  function keyTone(key) {
    if (key === "Super") return theme.accent;
    if (key === "Alt" || key === "Left Alt" || key === "Right Alt") return theme.info;
    if (key === "Shift") return theme.utility;
    return theme.textPrimary;
  }
  component ShortcutChord: Flow {
    id: chord
    required property string sequence
    spacing: 5
    Repeater {
      model: root.keyTokens(chord.sequence)
      delegate: Item {
        id: token
        required property string modelData
        width: keyLabel.implicitWidth
        height: 22
        ReferenceText {
          id: keyLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: token.modelData
          color: root.keyTone(token.modelData)
          font.pixelSize: 12
          font.weight: token.modelData === "+" ? Font.Normal : Font.DemiBold
          wrapMode: Text.NoWrap
        }
      }
    }
  }
  component KeyFirstAction: Item {
    id: action
    required property var entry
    implicitHeight: Math.max(36, Math.max(chord.implicitHeight, title.implicitHeight) + 12)
    Column {
      id: chord
      width: 151
      y: 6
      spacing: 6
      Repeater {
        model: root.keys(action.entry).split("\n")
        delegate: ShortcutChord {
          required property string modelData
          width: chord.width
          sequence: modelData
        }
      }
    }
    ReferenceText {
      id: title
      x: 163
      y: 8
      width: parent.width - x
      text: action.entry.title
      color: theme.textSecondary
    }
  }
  component SectionHeading: Item {
    id: heading
    required property string label
    implicitHeight: 44
    ReferenceText {
      width: parent.width
      text: heading.label
      font.pixelSize: 15
      font.weight: Font.DemiBold
    }
    Rectangle {
      y: 28
      width: parent.width
      height: 1
      color: theme.borderMuted
    }
  }
  component KeyFirstSection: Column {
    id: section
    required property var group
    SectionHeading { width: parent.width; label: section.group.name }
    Repeater {
      model: section.group.entries
      delegate: KeyFirstAction {
        required property var modelData
        width: section.width
        entry: modelData
      }
    }
  }

  PanelWindow {
    id: window
    screen: shellConfig.screen
    visible: surfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "quickshell:cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: theme.surfaceScrim
      opacity: surfaceTransition.progress
      MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.closeSheet()
      }
    }

    Rectangle {
      id: panel
      width: Math.min(1200, window.width - 56)
      height: Math.min(window.height - 56, Math.max(680, contentColumns.implicitHeight + 118))
      anchors.centerIn: parent
      radius: theme.groupRadius
      color: theme.surfaceGlassStrong
      border.width: 1
      border.color: theme.borderSubtle
      clip: true
      opacity: surfaceTransition.progress
      scale: 0.95 + surfaceTransition.progress * 0.05
      transform: Translate {
        y: (1 - surfaceTransition.progress) * 20
      }
      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { mouse.accepted = true; }
      }

      RowLayout {
        x: 24
        y: 20
        width: parent.width - 48
        spacing: 16
        ReferenceText {
          Layout.fillWidth: true
          text: "Shortcuts"
          font.pixelSize: 20
          font.bold: true
        }
        ShellButton {
          colors: theme
          glyph: "close"
          tooltip: "Close shortcuts"
          flatAction: true
          enabled: root.open
          onClicked: root.closeSheet()
        }
      }
      Rectangle {
        x: 24
        y: 64
        width: parent.width - 48
        height: 1
        color: theme.borderMuted
      }

      Row {
        id: contentColumns
        x: 24
        y: 88
        width: parent.width - 48
        spacing: 24
        visible: root.categories.length > 0 && root.message.length === 0
        Repeater {
          model: [0, 1, 2]
          delegate: Column {
            id: referenceColumn
            required property int modelData
            width: (contentColumns.width - 48) / 3
            spacing: 24
            Repeater {
              model: root.columnCategories(referenceColumn.modelData)
              delegate: KeyFirstSection {
                required property var modelData
                width: referenceColumn.width
                group: modelData
              }
            }
          }
        }
      }
      ReferenceText {
        anchors.centerIn: parent
        width: parent.width - 48
        visible: root.categories.length === 0 || root.message.length > 0
        text: root.message.length > 0 ? root.message : "No shortcuts"
        color: theme.textSecondary
        horizontalAlignment: Text.AlignHCenter
      }
    }
    Shortcut {
      sequence: "Esc"
      enabled: root.open
      onActivated: root.closeSheet()
    }
  }
}
