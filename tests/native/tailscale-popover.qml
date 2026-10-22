import QtQuick
import Quickshell
import "modules/tailscale"

ShellRoot {
  id: suite
  property int step: 0
  readonly property var overlay: details.surface
  QtObject { id: bar; property int height: 37 }
  QtObject {
    id: fakeModel
    property string backend: Quickshell.env("DESKTOP_SHELL_TEST_BACKEND") || "/no-fixture-command-needed"
    property bool detailsActive: false
    property bool connected: true
    property bool fresh: true
    property double now: Date.now()
    property string selectedId: ""
    readonly property var selected: data.peers.find(peer => peer.id === selectedId) || null
    readonly property var online: data.peers.filter(peer => peer.online)
    readonly property var offline: data.peers.filter(peer => !peer.online)
    readonly property bool canSend: selected !== null && selected.canSend
    readonly property string connectionText: selected?.online ? "Direct" : "Offline"
    readonly property string pingText: selected?.online ? "12 ms" : "—"
    property var data: ({available:true,connected:true,self:{name:"Local desktop",addresses:["100.64.0.10"]},files:[],peers:[{id:"a",name:"Workstation",hostname:"workstation",os:"linux",online:true,canSend:true,addresses:["100.64.0.20","fd7a:115c:a1e0::20"]},{id:"b",name:"Server",os:"linux",online:true,canSend:false,tags:["tag:server","tag:backup"],addresses:["100.64.0.30"]}]})
    function refresh() {}
    function refreshInbox() {}
    function snapshot() { return data; }
  }
  QtObject { id: controller; property var controls: []; function activate(control) {} }
  TailscaleDetails { id: details; model: fakeModel; networkController: controller; barSurface: bar }
  function verify(condition, message) {
    if (!condition) { console.error("FAIL tailscale popover: " + message); Qt.exit(1); }
  }
  function findText(item, text) {
    if (item.text === text) return item;
    for (const child of item.children || []) {
      const match = findText(child, text);
      if (match) return match;
    }
    return null;
  }
  function findVisibleText(item, text) {
    if (item.text === text && item.visible) return item;
    for (const child of item.children || []) {
      const match = findVisibleText(child, text);
      if (match) return match;
    }
    return null;
  }
  Timer {
    interval: 250; running: true; repeat: true
    onTriggered: {
      if (suite.step === 0) {
        if (Quickshell.screens.length === 0) return;
        details.toggleDetails(Quickshell.screens[0]);
      } else if (suite.step === 1) {
        suite.verify(details.open && !suite.overlay.keyboardRequested, "pointer opening stole focus");
        const received = suite.findText(suite.overlay.contentItem, "Received files");
        suite.verify(received && !received.visible, "empty inbox entry is visible");
        suite.verify(details.statusText() === "", "connected device retains redundant subtitle");
        suite.verify(suite.findVisibleText(suite.overlay.contentItem, "tag:server"), "tagged peer missing tags in main list");
        details.toggleDetails(Quickshell.screens[0]);
      } else if (suite.step === 2) {
        suite.verify(!details.open, "second click did not close");
        details.openDetails();
        details.showPeer("a");
      } else if (suite.step === 3) {
        suite.verify(suite.overlay.keyboardRequested, "CLI opening did not request focus");
        const send = suite.findText(suite.overlay.contentItem, "Send files…");
        suite.verify(send && send.visible, "eligible peer missing send button");
        details.showPeer("b");
      } else if (suite.step === 4) {
        const send = suite.findText(suite.overlay.contentItem, "Send files…");
        suite.verify(send && !send.visible, "ineligible peer has send button");
        suite.verify(suite.findVisibleText(suite.overlay.contentItem, "tag:backup"), "tagged peer missing tags in details");
        details.showPeer("a");
        details.chooseFiles();
        console.log("DIALOG_OPEN_REQUESTED");
      } else if (suite.step === 5) {
        suite.verify(details.dialogOpen && !suite.overlay.visible, "file picker is covered by popup overlay");
      } else if (suite.step < 20) {
        // Keep the real dialog visible briefly for the external native check.
      } else if (suite.step === 20) {
        if (details.dialogOpen) return;
        if (Quickshell.env("DESKTOP_SHELL_TEST_ACCEPT_PICKER") === "1") {
          if (details.files.length === 0) return;
          suite.verify(details.files.length === 1 && details.files[0].name === "example.txt", "selected file metadata failed");
          details.startSend();
          suite.step = 21;
          return;
        }
        details.closeDetails();
        suite.step = 24;
      } else if (suite.step === 21) {
        if (!details.uploadInFlight) return;
        details.cancelSend();
        details.startSend();
        suite.verify(details.transferState === "cancelled", "retry raced a cancelled process");
      } else if (suite.step === 22) {
        if (details.uploadInFlight) return;
        details.startSend();
      } else if (suite.step === 23) {
        if (details.transferState !== "sent") return;
        suite.verify(details.sendIndex === 1, "file completion not observed");
        details.closeDetails();
      } else {
        suite.verify(!details.open && !details.dialogOpen && !fakeModel.detailsActive, "closing did not release picker and probes");
        console.log("PASS tailscale popover: pointer toggle, keyboard focus, hidden empty inbox/ineligible action, native picker lifecycle");
        Qt.quit();
      }
      suite.step++;
    }
  }
  Timer { interval: 10000; running: true; onTriggered: { console.error("FAIL tailscale popover: timeout"); Qt.exit(1); } }
}
