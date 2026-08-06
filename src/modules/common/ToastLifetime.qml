import QtQuick
import Quickshell

Scope {
  id: root

  property int duration: 0
  property bool persistent: false
  property bool active: false
  property bool hovered: false
  property double startedAt: 0
  property double pausedMs: 0
  property double hoverStartedAt: 0
  property real progress: 0
  readonly property real remainingProgress: 1 - progress

  signal expired

  function clamp(value) {
    return Math.max(0, Math.min(1, value));
  }

  function update(now) {
    if (!active || persistent) {
      progress = 0;
      return;
    }

    const timestamp = now === undefined ? Date.now() : Number(now);
    const activePauseMs = hovered ? Math.max(0, timestamp - hoverStartedAt) : 0;
    progress = clamp((timestamp - startedAt - pausedMs - activePauseMs) / Math.max(1, duration));
    if (!hovered && progress >= 1) {
      active = false;
      expired();
    }
  }

  function start(startTime, alreadyPausedMs) {
    startedAt = startTime === undefined ? Date.now() : Number(startTime);
    pausedMs = Math.max(0, Number(alreadyPausedMs || 0));
    hoverStartedAt = 0;
    hovered = false;
    progress = 0;
    active = true;
    update();
  }

  function restart(preserveHover) {
    const keepHover = preserveHover === undefined ? hovered : Boolean(preserveHover && hovered);
    startedAt = Date.now();
    pausedMs = 0;
    hoverStartedAt = keepHover ? startedAt : 0;
    hovered = keepHover;
    progress = 0;
    active = true;
  }

  function pause() {
    if (!active || hovered)
      return;
    update();
    if (!active)
      return;
    hovered = true;
    hoverStartedAt = Date.now();
  }

  function resume() {
    if (!active || !hovered)
      return;
    const now = Date.now();
    pausedMs += Math.max(0, now - hoverStartedAt);
    hoverStartedAt = 0;
    hovered = false;
    update(now);
  }

  function stop() {
    active = false;
    hovered = false;
    hoverStartedAt = 0;
    progress = 1;
  }

  onPersistentChanged: update()

  Timer {
    interval: 16
    running: root.active && !root.persistent && !root.hovered
    repeat: true
    onTriggered: root.update()
  }
}
