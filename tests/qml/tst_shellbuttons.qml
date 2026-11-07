import QtQuick
import QtTest
import "../../src/modules/common"

TestCase {
  id: suite
  name: "ShellButtons"
  width: 300
  height: 160
  visible: true
  when: windowShown
  property int clicks: 0
  property int presses: 0
  property int releases: 0
  property int toggles: 0
  readonly property var colors: ({accent:"blue",bgMuted:"black",bgHover:"gray",accentHover:"blue",textDisabled:"gray",textOnAccent:"white",textPrimary:"white",textMuted:"gray",textSecondary:"white",uiFontFamily:"sans-serif",controlRadius:4,borderMuted:"gray",surfaceRaised:"black",surfaceHover:"gray"})

  ShellButton {
    id: simple
    colors: suite.colors
    label: "Action"
    checkable: true
    onClicked: suite.clicks++
    onPressed: suite.presses++
    onReleased: suite.releases++
    onToggled: suite.toggles++
  }
  ShellTaskButton {
    id: task
    y: 60
    colors: suite.colors
    title: "Task"
    checkable: true
    onClicked: suite.clicks++
    onPressed: suite.presses++
    onReleased: suite.releases++
    onToggled: suite.toggles++
  }

  function init() {
    for (const button of [simple, task]) {
      button.enabled = true;
      button.checked = false;
    }
    clicks = presses = releases = toggles = 0;
  }
  function test_activation_data() {
    const rows = [];
    for (const kind of ["button", "task"])
      for (const entry of [["Space", Qt.Key_Space], ["Return", Qt.Key_Return], ["Enter", Qt.Key_Enter]])
        rows.push({tag: kind + entry[0], kind: kind, key: entry[1]});
    return rows;
  }
  function test_activation(row) {
    const button = row.kind === "button" ? simple : task;
    button.forceActiveFocus(Qt.TabFocusReason);
    keyClick(row.key);
    compare(clicks, 1);
    compare(presses, 1);
    compare(releases, 1);
    compare(toggles, 1);
    verify(button.checked);
    button.enabled = false;
    keyClick(row.key);
    compare(clicks, 1);
    compare(toggles, 1);
  }
  function test_tab_focus_and_unhandled_keys() {
    simple.forceActiveFocus(Qt.TabFocusReason);
    keyClick(Qt.Key_Tab);
    verify(task.activeFocus);
    keyClick(Qt.Key_A);
    compare(clicks, 0);
    keyClick(Qt.Key_Tab, Qt.ShiftModifier);
    verify(simple.activeFocus);
  }
}
