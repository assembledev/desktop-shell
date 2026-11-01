import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtTest
import "modules/bar"
ShellRoot {
 id:suite
 readonly property var item: SystemTray.items.values.length === 1 ? SystemTray.items.values[0] : null
 property int triggerCount:0
 PanelWindow {
  id:bar
  screen:Quickshell.screens[0]
  anchors { top:true; left:true }
  margins.left:100
  implicitWidth:220
  implicitHeight:37
  exclusionMode:ExclusionMode.Ignore
  exclusiveZone:0
  color:"#da202638"
  WlrLayershell.layer:WlrLayer.Overlay
  WlrLayershell.namespace:"desktop-shell:tray-test-bar"
  Rectangle {
   id:trigger
   width:120;height:37;color:"#d8384164"
   Text {anchors.centerIn:parent;text:"Tray fixture";color:"white"}
   MouseArea {anchors.fill:parent;onClicked:{suite.triggerCount++;menu.openFor(suite.item,160,0,false)}}
  }
 }
 TrayMenu {id:menu;shellScreen:bar.screen;barSurface:bar}
 TestEvent {id:events}
 function quickWindow() {return menu.surface.contentItem.Window.window}
 function controls(item, type) {
  if (!item) return [];
  if (item instanceof type) return [item];
  let found = [];
  for (const child of item.children || [])
   found = found.concat(controls(child, type));
  return found;
 }
 function rows() {return controls(menu.surface.contentItem, MenuItem).sort((a,b) => a.index - b.index)}
 function state() {
  const items = rows().map(row => ({text:row.text,enabled:row.enabled,checked:row.entryChecked,focus:row.activeFocus}));
  const list = controls(menu.surface.contentItem, Flickable)[0];
  return JSON.stringify({items:SystemTray.items.values.length,hasMenu:Boolean(item?.hasMenu),expanded:menu.expanded,depth:menu.depth,keyboardRequested:menu.surface.keyboardRequested,active:Boolean(quickWindow()?.active),triggerCount:triggerCount,contentY:list.contentY,listHeight:list.height,rows:items});
 }
 IpcHandler {
  target:"fixture"
  function state():string {return suite.state()}
  function open():void {menu.openFor(suite.item,160,0,false)}
  function key(name:string):bool {return Boolean(suite.quickWindow()?.active) && events.keyClick(Qt["Key_"+name],Qt.NoModifier,-1)}
  function mouse(index:int):bool {const row=suite.rows()[index];return Boolean(row)&&events.mouseClick(row,row.width/2,row.height/2,Qt.LeftButton,Qt.NoModifier,-1)}
  function quit():void {menu.closeImmediately();Qt.quit()}
 }
 Timer {interval:45000;running:true;onTriggered:Qt.quit()}
}
