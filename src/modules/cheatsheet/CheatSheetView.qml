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
  readonly property var leftColumnOrder: [
    "Shell",
    "Apps",
    "Utilities"
  ]
  readonly property var rightColumnOrder: [
    "Windows",
    "Workspaces"
  ]

  function openSheet() {
    open = true;
    reloadHotkeys();
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

  function reloadHotkeys() {
    if (hotkeysPath.length === 0) {
      entries = [];
      message = "No hotkey source";
      buildCategories();
      return;
    }

    hotkeysFile.reload();
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
    const order = column === 0 ? leftColumnOrder : rightColumnOrder;
    const result = [];

    for (const name of order) {
      const category = categoryByName(name);
      if (category)
        result.push(category);
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

  Component.onCompleted: reloadHotkeys()

  FileView {
    id: hotkeysFile
    path: root.hotkeysPath
    preload: true
    watchChanges: false
    onLoaded: root.loadHotkeys(text())
    onTextChanged: root.loadHotkeys(text())
    onLoadFailed: function() {
      root.entries = [];
      root.message = "Failed to read hotkeys";
      root.buildCategories();
    }
  }

  PanelWindow {
    screen: shellConfig.screen
    id: window
    visible: surfaceTransition.presented
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open
      ? WlrKeyboardFocus.Exclusive
      : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

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

      width: Math.min(980, window.width - 44)
      height: Math.min(window.height - 96, Math.max(340, header.implicitHeight + body.spacing + contentColumns.implicitHeight + 48))
      anchors.centerIn: parent
      radius: 14
      color: theme.surfaceGlassStrong
      border.color: theme.borderSubtle
      border.width: 1
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

      ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12
        opacity: Math.max(0, Math.min(1, (surfaceTransition.progress - 0.16) / 0.84))
        transform: Translate {
          // Translate moves pixels without changing layout geometry.
          // qmllint disable Quick.layout-positioning
          y: (1 - body.opacity) * 8
          // qmllint enable Quick.layout-positioning
        }

        RowLayout {
          id: header

          Layout.fillWidth: true
          spacing: 10

          Text {
            Layout.fillWidth: true
            text: "Shortcuts"
            color: theme.textPrimary
            font.family: theme.fontFamily
            font.pixelSize: 20
            font.bold: true
            elide: Text.ElideRight
          }
        }

        RowLayout {
          id: contentColumns

          Layout.fillWidth: true
          spacing: 12

          Repeater {
            model: [0, 1]

            delegate: ColumnLayout {
              id: column

              required property int modelData

              Layout.fillWidth: true
              spacing: 10

              Repeater {
                model: root.columnCategories(column.modelData)

                delegate: Rectangle {
                  id: section

                  required property var modelData

                  Layout.fillWidth: true
                  Layout.preferredHeight: sectionContent.implicitHeight + 16
                  radius: 8
                  color: theme.surfaceSoft
                  border.width: 0
                  border.color: "transparent"

                  Column {
                    id: sectionContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 5

                    Text {
                      width: parent.width
                      text: section.modelData.name
                      color: theme.utility
                      font.family: theme.fontFamily
                      font.pixelSize: 12
                      font.bold: true
                    }

                    Repeater {
                      model: section.modelData.entries

                      delegate: Item {
                        id: row

                        required property var modelData

                        width: sectionContent.width
                        height: Math.max(26, Math.max(titleText.implicitHeight, keyFlow.implicitHeight) + 4)

                        RowLayout {
                          anchors.fill: parent
                          spacing: 8

                          Text {
                            id: titleText
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            topPadding: 3
                            text: row.modelData.title
                            color: theme.textPrimary
                            font.family: theme.fontFamily
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                          }

                          Flow {
                            id: keyFlow
                            Layout.preferredWidth: Math.min(230, Math.max(150, section.width * 0.44))
                            Layout.alignment: Qt.AlignTop
                            layoutDirection: Qt.RightToLeft
                            spacing: 4

                            Repeater {
                              model: row.modelData.displayKeys

                              delegate: Rectangle {
                                required property string modelData

                                height: 23
                                width: Math.max(44, Math.min(220, keyLabel.implicitWidth + 14))
                                radius: 6
                                color: theme.surfaceHover
                                border.width: 1
                                border.color: theme.borderSubtle

                                Text {
                                  id: keyLabel
                                  anchors.centerIn: parent
                                  text: root.displayKey(modelData)
                                  color: theme.info
                                  font.family: theme.fontFamily
                                  font.pixelSize: 10
                                  font.bold: true
                                  maximumLineCount: 1
                                  elide: Text.ElideRight
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.categories.length === 0 || root.message.length > 0
            text: root.message.length > 0 ? root.message : "No shortcuts"
            color: theme.textSecondary
            font.family: theme.fontFamily
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }

    Shortcut {
      sequence: "Esc"
      onActivated: root.closeSheet()
    }
  }
}
