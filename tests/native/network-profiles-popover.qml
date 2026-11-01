import QtQuick
import QtQuick.Layouts
import Quickshell
import "modules/bar"
import "modules/network"

ShellRoot {
  id: suite
  property int step: 0
  property real triggerStartX: 180
  property int barHeight: 37
  property int triggerY: 0
  property var testScreen: Quickshell.screens[0] || null
  property string invokedId: ""
  property var invokedTrigger: null
  QtObject {
    id: controller
    property var controls: [{id:"private",label:"Private",selectCommand:["fixture-select"]}]
    property string selected: "north"
    property bool busy: false
    property string error: ""
    signal statusRequested(string controlId)
    function status(control) { return {selectedProfile:selected,busy:busy,error:error}; }
    function profiles(control) { return [{id:"north",label:"North"},{id:"south",label:"South"}]; }
    function selectProfile(control, profileId) { selected = profileId; }
    function activate(control) { suite.verify(false, "arrow toggled provider"); }
  }
  PanelWindow {
    id: bar
    screen: suite.testScreen
    anchors { top: true; left: true; right: true }
    implicitHeight: suite.barHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    NetworkControls {
      id: barControls
      x: suite.triggerStartX
      y: suite.triggerY
      width: Layout.preferredWidth
      height: targetHeight
      controller: controller
      itemPadding: 8
      itemGap: 8
      contentGap: 6
      onProfilesRequested: (controlId, trigger) => {
        suite.invokedId = controlId;
        suite.invokedTrigger = trigger;
        details.toggleDetails(controlId, bar.screen, trigger);
      }
    }
  }
  NetworkProfiles { id: details; controller: controller; barSurface: bar }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL profile popover: " + message); Qt.exit(1); }
  }
  function find(item, predicate) {
    if (predicate(item)) return item;
    for (const child of item.children || []) {
      const match = find(child, predicate);
      if (match) return match;
    }
    return null;
  }
  function arrow() { return find(barControls, item => item.Accessible?.name === "Private profiles"); }
  function choice(label) { return find(details.surface.contentItem, item => item.modelData?.label === label); }
  function panel() {
    let item = find(details.surface.contentItem, item => item.text === "Private profiles");
    while (item && item !== details.surface.contentItem) {
      if (item.radius !== undefined && item.border !== undefined && item.width > 100) return item;
      item = item.parent;
    }
    return null;
  }
  function verifyPlacement() {
    const box = panel();
    const trigger = arrow();
    suite.verify(box && trigger, "missing real popup or bar arrow");
    const center = trigger.mapToItem(null, trigger.width / 2, trigger.height).x;
    const expected = Math.max(12, Math.min(center - box.width / 2, details.surface.width - box.width - 12));
    suite.verify(Math.abs(box.x - expected) < 0.5, "popup does not follow invoking trigger: " + box.x + " != " + expected);
    suite.verify(box.x >= 12 && box.x + box.width <= details.surface.width - 12, "popup escapes viewport");
    suite.verify(details.screen === bar.screen && details.surface.margins.top === bar.height, "popup used wrong output or bar height");
    console.log("PROFILE_POPUP_GEOMETRY", JSON.stringify({triggerCenter:center,panelX:box.x,panelWidth:box.width,viewportWidth:details.surface.width,barHeight:bar.height}));
  }
  Timer {
    interval: 150; running: true; repeat: true
    onTriggered: {
      if (suite.step === 0) {
        if (!bar.screen || !suite.arrow()) return;
        suite.arrow().clicked();
      } else if (suite.step === 1) {
        suite.verify(details.open && !details.surface.keyboardRequested, "pointer opening stole focus");
        suite.verifyPlacement();
        suite.verify(suite.invokedId === "private" && suite.invokedTrigger === suite.arrow(), "trigger identity was not forwarded");
        const row = suite.choice("South");
        suite.verify(row && !row.selected, "missing unselected profile row");
        suite.verify(row.background.color.a === 0, "profile row has a permanent fill");
        row.clicked();
        suite.verify(controller.selected === "south" && row.selected, "row did not select generic profile");
        const image = Quickshell.env("TEST_PROFILE_POPUP_IMAGE");
        if (image) suite.panel().grabToImage(result => {
          suite.verify(result.saveToFile(image), "failed popup capture");
          controller.busy = true;
        });
        else controller.busy = true;
      } else if (suite.step === 2) {
        if (!controller.busy) return;
        suite.verify(!suite.choice("North").enabled && !suite.choice("South").enabled, "transition did not disable rows");
        suite.verify(!suite.find(details.surface.contentItem, item => item.text === "Switching…" && item.visible), "redundant transition text is visible");
        controller.busy = false;
        controller.error = "Fixture connection error";
      } else if (suite.step === 3) {
        suite.verify(suite.find(details.surface.contentItem, item => item.text === controller.error && item.visible), "provider error is hidden");
        controller.error = "";
        suite.arrow().clicked();
      } else if (suite.step === 4) {
        suite.verify(!details.open, "second arrow click did not close");
        suite.triggerStartX = 0;
      } else if (suite.step === 5) {
        suite.arrow().clicked();
      } else if (suite.step === 6) {
        suite.verifyPlacement();
        suite.verify(suite.panel().x === 12, "left edge did not clamp");
        suite.arrow().clicked();
        suite.triggerStartX = bar.width - barControls.width;
      } else if (suite.step === 7) {
        suite.arrow().clicked();
      } else if (suite.step === 8) {
        suite.verifyPlacement();
        suite.verify(suite.panel().x + suite.panel().width === details.surface.width - 12, "right edge did not clamp");
        suite.arrow().clicked();
        suite.barHeight = 74;
        suite.triggerY = 37;
        suite.triggerStartX = 180;
      } else if (suite.step === 9) {
        suite.arrow().clicked();
      } else if (suite.step === 10) {
        suite.verifyPlacement();
        suite.arrow().clicked();
        details.openDetails("private");
      } else if (suite.step === 11) {
        suite.verify(details.open && details.surface.keyboardRequested, "keyboard opening did not request focus");
        details.closeDetails();
      } else {
        suite.verify(!details.surface.keyboardRequested, "closing retained keyboard focus");
        console.log("PASS profile popover: actual trigger, placement/clamping, flat rows, transition/error display and focus");
        Qt.quit();
      }
      suite.step++;
    }
  }
  Timer { interval: 7000; running: true; onTriggered: { console.error("FAIL profile popover: timeout"); Qt.exit(1); } }
}
