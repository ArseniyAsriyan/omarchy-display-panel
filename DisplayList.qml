pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// The list of connected displays. Each row is selectable and switchable on/off.
// Like the built-in Display panel, it only reports which output has focus
// ("· focused"); there is no user-chosen primary display.
Column {
  id: list
  required property QtObject host
  spacing: Style.space(10)

  PanelSectionHeader {
    text: "DISPLAYS"
    foreground: list.host.bar.foreground
    fontFamily: list.host.bar.fontFamily
  }

  Repeater {
    model: list.host.displays

    delegate: Rectangle {
      id: row
      required property var modelData
      required property int index

      readonly property var display: modelData
      readonly property bool isTarget: list.host.targetName === display.name
      readonly property bool isFocused: list.host.focusedName === display.name && display.enabled
      readonly property bool canToggle: display.enabled ? list.host.enabledDisplayCount > 1 : true

      width: list.width
      height: inner.implicitHeight + Style.spacing.xl
      radius: Style.cornerRadius
      color: isTarget ? Style.selectedFillFor(list.host.bar.foreground, Commons.Color.accent)
                      : Style.hoverFillFor(list.host.bar.foreground, Commons.Color.accent)
      border.width: isTarget ? 1 : 0
      border.color: Commons.Color.accent
      opacity: display.enabled ? 1.0 : 0.55

      Row {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(8)

        // Number badge, matching the tile's number on the map above.
        Rectangle {
          width: Style.space(20)
          height: Style.space(20)
          radius: width / 2
          color: display.enabled
            ? (row.isFocused ? Commons.Color.accent : Qt.darker(list.host.bar.foreground, 2.0))
            : Qt.darker(list.host.bar.foreground, 2.6)
          anchors.verticalCenter: parent.verticalCenter

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(list.host.displayNumber(display.name))
            color: list.host.bar.foreground
            font.family: list.host.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Column {
          width: parent.width - Style.space(20) - Style.space(8)
            - toggleSwitch.width - Style.space(16)
          spacing: 2
          anchors.verticalCenter: parent.verticalCenter

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: display.name + (row.isFocused ? "  \u00b7  focused" : "")
            color: list.host.bar.foreground
            font.family: list.host.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: isTarget
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: display.enabled
            text: {
              var size = Model.logicalSize(display)
              return size.width + "\u00d7" + size.height + "  \u00b7  " + Model.trimHz(display.refreshRate) + " Hz"
            }
            color: Qt.darker(list.host.bar.foreground, 1.4)
            font.family: list.host.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: !display.enabled
            text: "off"
            color: Qt.darker(list.host.bar.foreground, 1.4)
            font.family: list.host.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        ToggleSwitch {
          id: toggleSwitch
          anchors.verticalCenter: parent.verticalCenter
          checked: display.enabled
          interactive: row.canToggle
          foreground: list.host.bar.foreground
          accent: Commons.Color.accent
          onToggled: if (row.canToggle) list.host.toggleDisplay(row.display)
        }
      }

      MouseArea {
        anchors.fill: parent
        // Let the switch keep its own clicks; everything else selects the row.
        acceptedButtons: Qt.LeftButton
        onClicked: list.host.selectByName(row.display.name)
        // Sit under the interactive controls so they win where they overlap.
        z: -1
      }
    }
  }
}
