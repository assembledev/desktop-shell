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
  property var restingRow: null
  property var restingLabel: null
  property var restingAppearance: null
  property var restingCheck: null
  property var restingCheckAppearance: null
  NetworkState {
    id: profileState
    backend: Quickshell.env("DESKTOP_SHELL_TEST_BACKEND")
    configPath: Quickshell.env("DESKTOP_SHELL_TEST_CONFIG")
    pollingEnabled: false
    onControlsChanged: Qt.callLater(() => {
      if (controls.length) setStatus(controls[0], {
        selectedProfile: "north", profiles: [{id:"north",label:"North"},{id:"south",label:"South"}]
      });
    })
  }
  QtObject {
    id: controller
    property var controls: profileState.controls
    property string selected: "north"
    property bool busy: false
    property string error: ""
    signal statusRequested(string controlId)
    onBusyChanged: profileState.setStatus(controls[0], {busy:busy})
    onErrorChanged: profileState.setStatus(controls[0], {error:error})
    onSelectedChanged: profileState.setStatus(controls[0], {selectedProfile:selected})
    function status(control) { return profileState.status(control); }
    function profiles(control) { return profileState.profiles(control); }
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
  function appearance(label) {
    return {color:String(label.color),opacity:label.opacity,x:label.x,y:label.y,width:label.width,height:label.height};
  }
  function checkAppearance(symbol) {
    return {visible:symbol.visible,opacity:symbol.opacity,tint:String(symbol.tint),x:symbol.x,y:symbol.y,width:symbol.width,height:symbol.height};
  }
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
        suite.restingRow = suite.choice("North");
        suite.restingLabel = suite.find(suite.restingRow, item => item.text === "North");
        suite.restingAppearance = suite.appearance(suite.restingLabel);
        suite.restingCheck = suite.find(suite.restingRow, item => item.symbol === "check");
        suite.restingCheckAppearance = suite.checkAppearance(suite.restingCheck);
        const image = Quickshell.env("TEST_PROFILE_POPUP_IMAGE");
        if (image) suite.panel().grabToImage(result => {
          suite.verify(result.saveToFile(image), "failed popup capture");
          controller.busy = true;
        });
        else controller.busy = true;
      } else if (suite.step === 2) {
        if (!controller.busy) return;
        suite.verify(!suite.choice("North").enabled && !suite.choice("South").enabled, "transition did not disable rows");
        const busyRow = suite.choice("North");
        const busyLabel = suite.find(busyRow, item => item.text === "North");
        suite.verify(busyRow === suite.restingRow && busyLabel === suite.restingLabel, "busy state recreated profile delegates");
        suite.verify(JSON.stringify(suite.appearance(busyLabel)) === JSON.stringify(suite.restingAppearance), "busy state changed label appearance");
        suite.verify(JSON.stringify(suite.checkAppearance(suite.restingCheck)) === JSON.stringify(suite.restingCheckAppearance), "busy state changed selection check");
        suite.verify(!suite.find(details.surface.contentItem, item => item.text === "Switching…" && item.visible), "redundant transition text is visible");
        controller.busy = false;
        profileState.pollingEnabled = true;
      } else if (suite.step === 3) {
        if (!profileState.status(controller.controls[0]).fixtureSnapshot) return;
        const refreshedRow = suite.choice("North");
        const refreshedLabel = suite.find(refreshedRow, item => item.text === "North");
        const refreshedCheck = suite.find(refreshedRow, item => item.symbol === "check");
        suite.verify(JSON.stringify(suite.appearance(refreshedLabel)) === JSON.stringify(suite.restingAppearance), "status reconciliation changed label appearance");
        suite.verify(JSON.stringify(suite.checkAppearance(refreshedCheck)) === JSON.stringify(suite.restingCheckAppearance), "status reconciliation changed selection check");
        controller.error = "Fixture connection error";
        suite.verify(suite.find(details.surface.contentItem, item => item.text === controller.error && item.visible), "provider error is hidden");
        const row = suite.choice("South");
        row.clicked();
        suite.verify(controller.selected === "south" && row.selected, "row did not select generic profile");
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
