import QtQuick

QtObject {
  property bool compact: false
  property bool portrait: false
  readonly property bool dense: compact && !portrait

  // The bar uses a 2 px base grid. Components consume semantic tokens rather
  // than composing visual gaps from unrelated child margins.
  readonly property int space1: 2
  readonly property int space2: 4
  readonly property int space3: 6
  readonly property int space4: 8
  readonly property int space5: 10
  readonly property int space6: 12
  readonly property int space8: 16
  readonly property int space10: 20

  readonly property int contentGap: dense ? space2 : space3
  readonly property int itemPadding: dense ? space2 : space3
  readonly property int itemGap: space2
  readonly property int groupGap: dense ? space4 : space6

  readonly property int edgeInset: space8
  readonly property int centerClearance: space10
  readonly property int portraitEdgeInset: space6
  readonly property int workspaceGap: dense ? space2 : space3
  readonly property int workspaceTextGap: dense ? space4 : space5

  readonly property int trayItemGap: dense ? space2 : space4
  readonly property int trayTightGap: dense ? space1 : space2
  readonly property int portraitTrayItemGap: space1
  readonly property int portraitTrayTightGap: 0
  readonly property int actionSize: portrait ? 36 : (dense ? 28 : 32)
}
