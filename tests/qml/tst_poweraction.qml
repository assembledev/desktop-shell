import QtQuick
import QtTest
import "../../src/modules/bar"

TestCase {
  id: suite
  name: "PowerAction"
  visible: true
  when: windowShown
  width: 240
  height: 180
  property int clicks: 0
  readonly property var colors: ({ accent: "#a78bfa", danger: "#f283a2", surfaceAccent: "#303650", textPrimary: "#eef0f8", uiFontFamily: "sans-serif", fontFamily: "sans-serif" })
  PowerAction { id: first; colors: suite.colors; label: "Lock"; width: 220; height: 42; onClicked: suite.clicks++ }
  PowerAction { id: hidden; colors: suite.colors; label: "Unavailable"; visible: false }
  PowerAction { id: disabled; colors: suite.colors; label: "Busy"; y: 48; enabled: false }
  PowerAction { id: last; colors: suite.colors; label: "Sleep"; width: 220; height: 42; y: 96 }

  function init() { clicks = 0; first.enabled = true; first.forceActiveFocus(Qt.TabFocusReason); }
  function test_keyboard_activation_data() {
    return [{ tag: "space", key: Qt.Key_Space }, { tag: "return", key: Qt.Key_Return }, { tag: "enter", key: Qt.Key_Enter }];
  }
  function test_keyboard_activation(row) {
    keyClick(row.key);
    compare(clicks, 1);
    first.enabled = false;
    keyClick(row.key);
    compare(clicks, 1);
  }
  function test_accessible_focus_and_tab_order() {
    compare(first.Accessible.name, "Lock");
    compare(first.Accessible.role, Accessible.Button);
    verify(first.visualFocus);
    keyClick(Qt.Key_Tab);
    verify(last.activeFocus);
    keyClick(Qt.Key_Tab, Qt.ShiftModifier);
    verify(first.activeFocus);
  }
}
