import QtQuick
import QtTest
import "../../src/modules/control_center" as ControlCenter

TestCase {
  id: suite
  name: "OsdModel"
  width: 300
  height: 100
  visible: true
  when: windowShown

  property var entries: []
  property string outputName: "one"
  ControlCenter.OsdModel {
    id: rows
    entries: suite.entries
    outputName: suite.outputName
  }

  Repeater {
    id: repeater
    model: rows
    delegate: Item {
      required property var modelData
      readonly property string kind: modelData.kind
      readonly property real level: modelData.osdLevel
      width: 200
      height: 8
      property alias fillWidth: fill.width
      Rectangle {
        id: fill
        width: parent.width * parent.level
        height: 8
        Behavior on width {
          NumberAnimation {
            duration: 220
          }
        }
      }
    }
  }

  function entry(kind, level, output = "one") {
    return {
      kind: kind,
      osdLevel: level,
      displayText: Math.round(level * 100) + "%",
      outputName: output
    };
  }

  function init() {
    entries = [];
    outputName = "one";
  }

  function test_stepsKeepDelegateAndLevel_data() {
    return [
      {
        tag: "volume",
        kind: "volume"
      },
      {
        tag: "brightness",
        kind: "brightness"
      }
    ];
  }

  function test_stepsKeepDelegateAndLevel(data) {
    entries = [entry(data.kind, .6)];
    tryCompare(repeater, "count", 1);
    const row = repeater.itemAt(0);
    tryCompare(row, "fillWidth", 120);
    entries = [entry(data.kind, .65)];
    compare(repeater.itemAt(0), row, "each step must retain the animated row");
    verify(row.fillWidth >= 120, "rising step must never fall through zero");
    tryCompare(row, "fillWidth", 130);
    for (let i = 0; i < 5; i++) {
      entries = [entry(data.kind, .70 + i * .05)];
      compare(repeater.itemAt(0), row);
      verify(row.fillWidth >= 130, "rapid steps reset the fill");
      wait(16);
    }
    tryCompare(row, "fillWidth", 180);
    entries = [entry(data.kind, .4)];
    compare(repeater.itemAt(0), row);
    wait(32);
    verify(row.fillWidth >= 80 && row.fillWidth <= 180);
    tryCompare(row, "fillWidth", 80);
  }

  function test_otherRowsAndOutputsDoNotResetExistingRow() {
    entries = [entry("volume", .6)];
    const volume = repeater.itemAt(0);
    entries = [entry("volume", .6), entry("brightness", .7), entry("other", .2, "two")];
    compare(repeater.count, 2);
    compare(repeater.itemAt(0), volume);
    const brightness = repeater.itemAt(1);
    entries = [entry("volume", .6), entry("brightness", .7), entry("other", .4, "two")];
    compare(repeater.itemAt(0), volume);
    compare(repeater.itemAt(1), brightness);
    // Expiring the preceding row must preserve the surviving row.
    entries = [entry("brightness", .7), entry("other", .4, "two")];
    compare(repeater.count, 1);
    compare(repeater.itemAt(0), brightness);
    entries = [];
    compare(repeater.count, 0);
  }

  function test_outputMigrationAndScreenChange() {
    entries = [entry("volume", .6), entry("brightness", .7)];
    const brightness = repeater.itemAt(1);
    entries = [entry("volume", .65, "two"), entry("brightness", .7)];
    compare(repeater.count, 1);
    compare(repeater.itemAt(0), brightness);
    outputName = "two";
    compare(repeater.count, 1);
    compare(repeater.itemAt(0).kind, "volume");
    compare(repeater.itemAt(0).level, .65);
    outputName = "removed";
    compare(repeater.count, 0);
  }

  function test_reorderPreservesDelegates() {
    entries = [entry("volume", .6), entry("brightness", .7)];
    const volume = repeater.itemAt(0);
    const brightness = repeater.itemAt(1);
    entries = [entry("brightness", .75), entry("volume", .65)];
    compare(repeater.itemAt(0), brightness);
    compare(repeater.itemAt(1), volume);
  }
}
