import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../common"

Item {
  id: root

  Theme { id: theme }

  required property int workspaceId
  required property string label
  required property bool active
  required property bool occupied
  required property var applications
  required property string activeTitle
  required property color activeColor
  required property color textColor
  required property color mutedColor
  required property color hoverColor

  property bool expandActive: true
  property int compactWidth: 68
  property int expandedWidth: 280
  property int targetHeight: 37

  readonly property bool expanded: active && expandActive
  readonly property int shownApplicationCount: Math.min(3, applications?.length || 0)
  readonly property real inactiveOpacity: occupied ? 0.86 : 0.55
  readonly property int labelWidth: Math.ceil(workspaceText.implicitWidth)
  readonly property int compactIconClusterWidth: shownApplicationCount === 1 ? 21
    : shownApplicationCount === 2 ? 34
    : shownApplicationCount >= 3 ? 33
    : (occupied ? 18 : 16)
  readonly property int compactContentGap: shownApplicationCount >= 2 ? 3 : 7
  readonly property real compactContentX: 0
  readonly property real compactIconOriginX: compactContentX + labelWidth + compactContentGap
  readonly property int expandedIconClusterWidth: shownApplicationCount === 1 ? 22
    : shownApplicationCount === 2 ? 46
    : shownApplicationCount >= 3 ? 70
    : (occupied ? 18 : 16)
  readonly property real expandedIconOriginX: labelWidth + 7
  readonly property int portraitWidth: expanded
    ? Math.ceil(expandedIconOriginX + expandedIconClusterWidth + 2)
    : compactWidth
  readonly property string displayTitle: activeTitle.length > 0
    ? activeTitle
    : (occupied ? "Workspace " + label : "Empty workspace")
  readonly property bool hovered: pointer.containsMouse

  signal clicked

  implicitWidth: expanded ? expandedWidth : compactWidth
  implicitHeight: targetHeight
  clip: true
  scale: pointer.pressed ? 0.965 : (root.hovered ? 1.018 : 1)
  transformOrigin: Item.Center
  Layout.preferredWidth: implicitWidth
  Layout.minimumWidth: implicitWidth
  Layout.maximumWidth: implicitWidth
  Layout.preferredHeight: targetHeight

  function iconSource(icon) {
    const value = String(icon || "");
    if (value.length === 0)
      return "";
    if (value.startsWith("/") )
      return "file://" + value;
    if (value.indexOf(":") >= 0)
      return value;
    return Quickshell.iconPath(value, "application-x-executable");
  }

  Behavior on implicitWidth {
    MotionNumberAnimation {
      role: MotionNumberAnimation.FocusTravel
      speedMultiplier: 5
    }
  }

  Behavior on scale {
    MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
  }

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: 3
    anchors.bottomMargin: 2
    radius: 9
    color: root.hovered ? root.hoverColor : "transparent"

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
  }

  Rectangle {
    anchors.top: parent.top
    anchors.topMargin: 2
    anchors.left: parent.left
    width: root.active ? parent.width : (root.occupied ? root.compactWidth : 0)
    height: root.active ? 3 : 2
    radius: 2
    color: root.active ? root.activeColor : root.textColor
    opacity: root.active ? 1 : root.inactiveOpacity

    Behavior on color {
      MotionColorAnimation { role: MotionNumberAnimation.Feedback }
    }
    Behavior on opacity {
      MotionNumberAnimation { role: MotionNumberAnimation.Feedback }
    }
  }

  Item {
    id: portrait
    anchors.left: parent.left
    anchors.top: parent.top
    width: root.portraitWidth
    height: parent.height

    Repeater {
      model: root.shownApplicationCount

      IconImage {
        required property int index
        readonly property bool expandedLayout: root.expanded
        readonly property int count: root.shownApplicationCount
        readonly property int iconSize: expandedLayout ? 22 : (count === 1 ? 21 : count === 2 ? 18 : 17)

        width: iconSize
        height: iconSize
        x: {
          if (expandedLayout)
            return root.expandedIconOriginX + index * 24;
          if (count === 1)
            return root.compactIconOriginX;
          if (count === 2)
            return root.compactIconOriginX + index * 16;
          return index === 2
            ? root.compactIconOriginX + 16
            : root.compactIconOriginX;
        }
        y: {
          if (expandedLayout || count < 3)
            return Math.round((parent.height - height) / 2) + 1;
          if (index === 0)
            return 3;
          if (index === 1)
            return 19;
          return 11;
        }
        z: index
        asynchronous: false
        smooth: true
        mipmap: true
        source: root.iconSource(root.applications[index]?.icon)
        opacity: index === count - 1 ? 1 : 0.88

        Behavior on x {
          MotionNumberAnimation {
            role: MotionNumberAnimation.FocusTravel
            speedMultiplier: 5
          }
        }
        Behavior on y {
          MotionNumberAnimation {
            role: MotionNumberAnimation.FocusTravel
            speedMultiplier: 5
          }
        }
        Behavior on width {
          MotionNumberAnimation {
            role: MotionNumberAnimation.FocusTravel
            speedMultiplier: 5
          }
        }
        Behavior on height {
          MotionNumberAnimation {
            role: MotionNumberAnimation.FocusTravel
            speedMultiplier: 5
          }
        }
      }
    }

    Text {
      visible: root.occupied && root.shownApplicationCount === 0
      x: root.expanded ? root.expandedIconOriginX : root.compactIconOriginX
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 1
      text: ""
      color: root.mutedColor
      font.family: theme.fontFamily
      font.pixelSize: 18
    }

    Row {
      visible: !root.occupied
      x: root.expanded ? root.expandedIconOriginX : root.compactIconOriginX
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 1
      spacing: 3

      Repeater {
        model: 3

        Rectangle {
          required property int index
          width: index === 1 ? 4 : 3
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: root.mutedColor
          opacity: index === 1 ? 0.62 : 0.34
        }
      }
    }

    Item {
      id: workspaceLabel
      x: root.expanded ? 0 : root.compactContentX
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 1
      width: root.labelWidth
      height: 18

      Text {
        id: workspaceText
        anchors.fill: parent
        text: root.label
        color: root.active ? root.activeColor : root.textColor
        opacity: root.active ? 1 : root.inactiveOpacity
        font.family: theme.fontFamily
        font.pixelSize: 17
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  Text {
    anchors.left: portrait.right
    anchors.leftMargin: 8
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: 1
    text: root.displayTitle
    color: root.occupied ? root.textColor : root.mutedColor
    opacity: root.expanded ? (root.occupied ? 1 : 0.74) : 0
    font.family: theme.fontFamily
    font.pixelSize: root.occupied ? 16 : 14
    font.bold: true
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter

    Behavior on opacity {
      MotionNumberAnimation { role: MotionNumberAnimation.Content }
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
