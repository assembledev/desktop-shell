import QtQuick
import QtTest
import "../../src/modules/common" as Common
import "../../src/modules/control_center" as ControlCenter
import "../../src/modules/control_center/NotificationHistory.js" as History

TestCase {
  id: suite
  name: "ControlCenterControls"
  width: 500
  height: 650
  visible: true
  when: windowShown
  readonly property var colors: ({
      bgSolid: "#151725",
      bgRaised: "#23283b",
      bgMuted: "#1c2030",
      bgHover: "#303650",
      border: "#424a68",
      borderMuted: "#343b55",
      borderSubtle: "#70424a68",
      surfaceRaised: "#b823283b",
      surfaceHover: "#bd303650",
      textPrimary: "#eef0f8",
      textSecondary: "#c7ccdc",
      textMuted: "#929cb2",
      textDisabled: "#69748b",
      textOnAccent: "#151725",
      accent: "#a78bfa",
      accentHover: "#c4b5fd",
      info: "#67d4e8",
      special: "#d08cf3",
      caution: "#f3a66e",
      danger: "#f283a2",
      uiFontFamily: "sans-serif",
      groupRadius: 14,
      controlRadius: 6
    })
  property bool radioState: false
  property int clicks: 0
  Component {
    id: actionComponent
    Common.ShellButton {
      colors: suite.colors
      label: "Keep layout"
      active: true
      onClicked: suite.clicks++
    }
  }
  Component {
    id: iconComponent
    Common.ShellButton {
      colors: suite.colors
      glyph: "close"
      tooltip: "Close panel"
      width: 32
      height: 32
    }
  }
  Component {
    id: headerComponent
    Common.ShellTaskButton {
      colors: suite.colors
      title: "Display"
      navigation: true
      width: 396
      height: 34
    }
  }
  Component {
    id: switchComponent
    Common.ShellSwitch {
      colors: suite.colors
      checked: suite.radioState
      Accessible.name: "Wi-Fi radio"
      onClicked: suite.radioState = !suite.radioState
    }
  }
  Component {
    id: sliderComponent
    Common.ShellSlider {
      colors: suite.colors
      width: 240
      from: 0
      to: 1
      stepSize: .05
      value: .5
      Accessible.name: "Output level"
    }
  }
  Component {
    id: arrangementComponent
    ControlCenter.DisplayArrangement {
      colors: suite.colors
      width: 396
      height: 188
      draft: ({})
      outputs: [
        {
          name: "Display one",
          mode: "1920x1080@60",
          scale: 1,
          position: "0x0",
          enabled: true
        },
        {
          name: "Display two",
          mode: "1920x1080@60",
          scale: 1,
          position: "1920x0",
          enabled: true
        }
      ]
      selectedName: "Display one"
      onSelected: name => selectedName = name
    }
  }
  Component {
    id: quickComponent
    ControlCenter.QuickControls {
      controller: mock
      colors: suite.colors
      width: 396
      height: implicitHeight
    }
  }
  QtObject {
    id: mock
    property string page: "main"
    property bool wifiEnabled: true
    property bool wifiToggleAvailable: true
    property bool bluetoothEnabled: true
    property bool bluetoothStatusReady: true
    property bool bluetoothAvailable: true
    property bool bluetoothBusy: false
    property bool focusMode: false
    property bool dnd: false
    property bool brightnessSupported: true
    property bool brightnessWritable: true
    property bool displaysReady: true
    property real brightness: .75
    property var sink: ({
        audio: {
          volume: .64,
          muted: false
        }
      })
    property var source: ({
        audio: {
          volume: .72,
          muted: false
        }
      })
    function wifiSummaryText() {
      return "Connected network";
    }
    function bluetoothSummaryText() {
      return "2 connected";
    }
    function toggleWifi() {
      wifiEnabled = !wifiEnabled;
    }
    function toggleBluetooth() {
      bluetoothEnabled = !bluetoothEnabled;
    }
    function toggleDnd() {
      dnd = !dnd;
    }
    function setFocusMode(value) {
      focusMode = value;
    }
    function setBrightness(value) {
      brightness = value;
    }
    function setNodeVolume(node, value) {
      node.audio.volume = value;
    }
    function toggleNodeMute(node) {
      node.audio.muted = !node.audio.muted;
    }
  }
  function find(item, predicate) {
    if (predicate(item))
      return item;
    for (const child of item.children || []) {
      const found = find(child, predicate);
      if (found)
        return found;
    }
    return null;
  }
  function init() {
    radioState = false;
    clicks = 0;
    mock.page = "main";
    mock.dnd = false;
  }
  function test_nativeAction() {
    const b = createTemporaryObject(actionComponent, suite);
    verify(b);
    b.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Space);
    compare(clicks, 1);
    compare(b.Accessible.name, "Keep layout");
    verify(b.Accessible.role !== Accessible.NoRole);
    verify(b.visualFocus);
    b.enabled = false;
    tryCompare(b.background, "color", colors.bgMuted, 250);
    keyClick(Qt.Key_Space);
    compare(clicks, 1);
  }
  function test_iconAndHeaderCenters() {
    const icon = createTemporaryObject(iconComponent, suite);
    const glyph = find(icon, x => x.symbol === "close");
    verify(glyph);
    waitForRendering(icon);
    const center = glyph.mapToItem(icon, glyph.width / 2, glyph.height / 2);
    fuzzyCompare(center.x, icon.width / 2, .5);
    fuzzyCompare(center.y, icon.height / 2, .5);
    const header = createTemporaryObject(headerComponent, suite);
    waitForRendering(header);
    const title = find(header, x => x.text === "Display");
    const arrow = find(header, x => x.symbol === "right");
    verify(title && arrow);
    const titleCenter = title.mapToItem(header, title.width / 2, title.height / 2);
    const arrowCenter = arrow.mapToItem(header, arrow.width / 2, arrow.height / 2);
    fuzzyCompare(titleCenter.y, header.height / 2, .5);
    fuzzyCompare(arrowCenter.y, header.height / 2, .5);
  }
  function test_switchAuthoritativeState() {
    const b = createTemporaryObject(switchComponent, suite);
    verify(b);
    b.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Space);
    compare(radioState, true);
    compare(b.checked, true);
    radioState = false;
    compare(b.checked, false);
    compare(b.Accessible.name, "Wi-Fi radio");
    verify(b.Accessible.role !== Accessible.NoRole);
  }
  function test_keyboardSlider() {
    const b = createTemporaryObject(sliderComponent, suite);
    verify(b);
    b.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Right);
    verify(b.value > .5);
    compare(b.Accessible.name, "Output level");
  }
  function test_quickGeometry_data() {
    return [
      {
        tag: "ordinary",
        compact: false
      },
      {
        tag: "short",
        compact: true
      }
    ];
  }
  function test_quickGeometry(row) {
    const quick = createTemporaryObject(quickComponent, suite, {
      compact: row.compact
    });
    verify(quick);
    waitForRendering(quick);
    verify(quick.height > 100);
    verify(quick.height < (row.compact ? 280 : 370), "Quick controls grew beyond their bounded region: " + quick.height);
    const wifi = find(quick, x => x.title === "Wi-Fi" && x.visible && x.navigation === true);
    verify(wifi);
    compare(wifi.accent, colors.info);
    verify(wifi.width > 150 && wifi.width < 215, "Connectivity column lost its half-width: " + wifi.width);
    wifi.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Space);
    compare(mock.page, "wifi");
    const dnd = find(quick, x => x.title === "Do Not Disturb");
    verify(dnd);
    dnd.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Space);
    compare(mock.dnd, true);
  }
  function test_displayKeyboardSelection() {
    const arrangement = createTemporaryObject(arrangementComponent, suite);
    verify(arrangement);
    waitForRendering(arrangement);
    const second = find(arrangement, x => x.output?.name === "Display two");
    verify(second);
    verify(second.activeFocusOnTab);
    compare(second.Accessible.checked, false);
    second.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Space);
    compare(arrangement.selectedName, "Display two");
    compare(second.Accessible.checked, true);
    compare(second.Accessible.name, "Display 2: Display two");
    const first = find(arrangement, x => x.output?.name === "Display one");
    first.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Return);
    compare(arrangement.selectedName, "Display one");
    compare(second.Accessible.checked, false);
  }
  function test_historyRetainsEveryExpandedItem() {
    const one = Array.from({
      length: 1000
    }, (_, i) => ({
          id: i
        }));
    const groups = [
      {
        key: "priority:chat",
        items: one
      },
      {
        key: "recent:mail",
        items: [
          {
            id: 1001
          },
          {
            id: 1002
          }
        ]
      }
    ];
    const collapsed = History.entries(groups, {});
    compare(collapsed.length, 2);
    compare(collapsed[0].item.id, 0);
    compare(collapsed[1].group.key, "recent:mail");
    const expanded = History.entries(groups, {
      "priority:chat": true,
      "recent:mail": true
    });
    compare(expanded.length, 1002);
    compare(expanded[999].item.id, 999);
    compare(expanded[1001].item.id, 1002);
    verify(expanded[1000].first);
    verify(!expanded[1001].first);
    compare(one.length, 1000);
  }
}
