pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "TailscaleStatus.js" as Status

Scope {
  id: root
  signal saveRequested(var files)

  function notify(files, icon) {
    if (files.length === 0) return;
    const process = sender.createObject(root, {files:files.slice(),command:Status.receivedNotification(files, icon)});
    process.running = true;
  }

  Component {
    id: sender
    Process {
      id: notification
      required property var files
      stdout: StdioCollector { id: output }
      onExited: function(code) {
        if (code === 0 && output.text.trim() === "save") root.saveRequested(files);
        notification.destroy();
      }
    }
  }
}
