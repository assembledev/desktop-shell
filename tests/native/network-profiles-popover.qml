import QtQuick
import Quickshell
import "modules/network"

ShellRoot {
  id: suite
  property int step: 0
  QtObject { id: bar; property int height: 37 }
  QtObject {
    id: controller
    property var controls: [{id:"private",label:"Private",selectCommand:["fixture-select"]}]
    property string selected: "north"
    signal statusRequested(string controlId)
    function status(control) { return {selectedProfile:selected,busy:false,error:""}; }
    function profiles(control) { return [{id:"north",label:"North"},{id:"south",label:"South"}]; }
    function selectProfile(control, profileId) { selected = profileId; }
  }
  NetworkProfiles { id: details; controller: controller; barSurface: bar }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL profile popover: " + message); Qt.exit(1); }
  }
  function findChoice(item, label) {
    if (item.modelData?.label === label) return item;
    for (const child of item.children || []) {
      const match = findChoice(child, label);
      if (match) return match;
    }
    return null;
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (suite.step === 0) {
        if (!Quickshell.screens.length) return;
        details.toggleDetails("private", Quickshell.screens[0]);
      } else if (suite.step === 1) {
        suite.verify(details.open && !details.surface.keyboardRequested, "pointer opening stole focus");
        const choice = suite.findChoice(details.surface.contentItem, "South");
        suite.verify(choice && !choice.selected, "missing unselected profile card");
        choice.clicked();
        suite.verify(controller.selected === "south" && choice.selected, "card did not select generic profile");
        details.toggleDetails("private", Quickshell.screens[0]);
      } else if (suite.step === 2) {
        suite.verify(!details.open, "second bar click did not close");
        details.openDetails("private");
      } else if (suite.step === 3) {
        suite.verify(details.open && details.surface.keyboardRequested, "keyboard opening did not request focus");
        details.closeDetails();
      } else {
        suite.verify(!details.surface.keyboardRequested, "closing retained keyboard focus");
        console.log("PASS profile popover: generic cards, pointer toggle and keyboard focus");
        Qt.quit();
      }
      suite.step++;
    }
  }
  Timer { interval: 7000; running: true; onTriggered: { console.error("FAIL profile popover: timeout"); Qt.exit(1); } }
}
