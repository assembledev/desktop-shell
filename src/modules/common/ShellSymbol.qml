import QtQuick
import "ShellSymbols.js" as Symbols

Item {
  id: symbolItem
  property string symbol: ""
  property color tint: "white"
  property int size: 20
  implicitWidth: size
  implicitHeight: size
  Image {
    anchors.centerIn: parent
    width: symbolItem.size
    height: symbolItem.size
    sourceSize.width: 48
    sourceSize.height: 48
    fillMode: Image.PreserveAspectFit
    source: symbolItem.symbol.length === 0 ? "" : "data:image/svg+xml;utf8," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="' + Symbols.path(symbolItem.symbol) + '" fill="none" stroke="' + symbolItem.tint.toString() + '" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>')
  }
}
