pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
  id: root

  signal succeeded(var clients)
  signal failed(string reason)

  property bool pending: false
  property bool requestSent: false
  property string response: ""
  readonly property int timeoutMs: 500

  function request() {
    if (pending || requestSocket.connected)
      return false;

    pending = true;
    requestSent = false;
    response = "";
    requestTimeout.restart();
    requestSocket.connected = true;
    return true;
  }

  function fail(reason) {
    if (!pending)
      return;
    pending = false;
    requestTimeout.stop();
    requestSocket.connected = false;
    failed(reason);
  }

  function complete(clients) {
    pending = false;
    requestTimeout.stop();
    requestSocket.connected = false;
    succeeded(clients);
  }

  function parseClients() {
    const clients = JSON.parse(response);
    if (!Array.isArray(clients))
      throw new Error("expected an array");
    return clients;
  }

  function finish() {
    if (!pending)
      return;

    try {
      complete(parseClients());
    } catch (error) {
      fail("invalid clients response: " + error);
    }
  }

  function consume(data) {
    if (!pending)
      return;
    response += data;

    // Hyprland sends one JSON document and then closes the request socket.
    // Closing as soon as the document is complete avoids treating that normal
    // protocol EOF as a QLocalSocket PeerClosedError.
    try {
      complete(parseClients());
    } catch (error) {
      // A response may arrive in several chunks. EOF or the timeout turns a
      // still-incomplete document into an explicit failure.
    }
  }

  Socket {
    id: requestSocket
    path: Hyprland.requestSocketPath

    parser: SplitParser {
      splitMarker: ""
      onRead: function(data) {
        root.consume(data);
      }
    }

    onConnectionStateChanged: {
      if (connected && root.pending) {
        root.requestSent = true;
        write("j/clients");
        flush();
      } else if (!connected && root.pending && root.requestSent) {
        root.finish();
      }
    }
  }

  Timer {
    id: requestTimeout
    interval: root.timeoutMs
    repeat: false
    onTriggered: root.fail("clients request timed out")
  }
}
