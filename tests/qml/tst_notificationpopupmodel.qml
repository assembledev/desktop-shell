import QtQuick
import QtTest
import "../../src/modules/control_center" as ControlCenter

TestCase {
  id: suite
  name: "NotificationPopupModel"
  width: 400
  height: 400
  visible: true
  when: windowShown

  property string outputName: "one"
  property int created: 0

  ListModel {
    id: source
  }

  ControlCenter.NotificationPopupModel {
    id: rows
    model: source
    outputName: suite.outputName
  }

  Repeater {
    id: repeater
    model: rows
    delegate: Item {
      required property int popupId
      property int entranceCount: 0
      property bool hovered: false
      property bool closing: false
      property real entranceProgress: 0
      Component.onCompleted: {
        suite.created++;
        entranceCount++;
        entrance.start();
      }
      NumberAnimation on entranceProgress {
        id: entrance
        running: false
        from: 0
        to: 1
        duration: 180
      }
    }
  }

  function add(id, output = "one") {
    source.insert(0, {popupId: id, outputName: output});
  }

  function init() {
    source.clear();
    outputName = "one";
    created = 0;
  }

  function test_addingPopupPreservesExistingToast() {
    add(1);
    const first = repeater.itemAt(0);
    tryCompare(first, "entranceProgress", 1);
    add(2);
    compare(repeater.count, 2);
    compare(repeater.itemAt(1), first, "arrival must preserve the existing toast");
    compare(first.entranceProgress, 1, "arrival must not replay another toast's entrance");
    compare(created, 2);
  }

  function test_removingPopupPreservesSurvivors_data() {
    return [{tag: "first", index: 0}, {tag: "middle", index: 1}, {tag: "last", index: 2}];
  }

  function test_removingPopupPreservesSurvivors(data) {
    add(1);
    add(2);
    add(3);
    const survivors = [repeater.itemAt(0), repeater.itemAt(1), repeater.itemAt(2)];
    survivors.splice(data.index, 1);
    source.remove(data.index);
    compare(repeater.count, 2);
    compare(repeater.itemAt(0), survivors[0], "removal must preserve the first survivor");
    compare(repeater.itemAt(1), survivors[1], "removal must preserve the second survivor");
    compare(created, 3);
  }

  function test_otherOutputDoesNotTouchVisiblePopups() {
    add(1);
    const first = repeater.itemAt(0);
    add(2, "two");
    compare(repeater.count, 1);
    compare(repeater.itemAt(0), first);
    source.remove(0);
    compare(repeater.itemAt(0), first);
    compare(created, 1);
  }

  function test_localStateSurvivesSiblingChanges() {
    add(1);
    const first = repeater.itemAt(0);
    first.hovered = true;
    first.closing = true;
    add(2);
    compare(repeater.itemAt(1), first);
    compare(first.hovered, true, "hover pause must survive sibling arrival");
    compare(first.closing, true, "a closing popup must not be resurrected");
    source.remove(0);
    compare(repeater.itemAt(0), first);
    compare(first.entranceCount, 1);
  }

  function test_outputMigrationPreservesOtherPopups() {
    add(1);
    add(2);
    const first = repeater.itemAt(1);
    source.setProperty(0, "outputName", "two");
    compare(repeater.count, 1);
    compare(repeater.itemAt(0), first);
    source.setProperty(0, "outputName", "one");
    compare(repeater.count, 2);
    compare(repeater.itemAt(1), first);
    outputName = "two";
    compare(repeater.count, 0);
    source.setProperty(0, "outputName", "two");
    compare(repeater.count, 1);
    compare(repeater.itemAt(0).popupId, 2);
    outputName = "removed";
    compare(repeater.count, 0);
  }

  function test_roleUpdatesPreserveDelegates() {
    add(1);
    const first = repeater.itemAt(0);
    source.setProperty(0, "outputName", "one");
    compare(repeater.itemAt(0), first);
    compare(first.entranceCount, 1);
    compare(created, 1);
  }
}
