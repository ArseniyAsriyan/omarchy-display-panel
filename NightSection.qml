pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// Night mode: a blue-light filter driven by hyprsunset, with a temperature
// slider. Mirrors `omarchy toggle nightlight` so the CLI and the panel agree.
Column {
  id: night
  required property QtObject host
  spacing: Style.space(8)

  PanelSeparator { foreground: night.host.bar.foreground }

  PanelSectionHeader {
    text: "NIGHT MODE"
    foreground: night.host.bar.foreground
    fontFamily: night.host.bar.fontFamily
  }

  Toggle {
    width: parent.width
    host: night.host
  }

  Column {
    width: parent.width
    spacing: Style.space(6)
    visible: night.host.nightEnabled

    Item {
      width: parent.width
      implicitHeight: Math.max(tempHeader.implicitHeight, tempValue.implicitHeight)

      PanelSectionHeader {
        id: tempHeader
        text: "COLOR TEMPERATURE"
        foreground: night.host.bar.foreground
        fontFamily: night.host.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: tempValue
        textFormat: Text.PlainText
        text: Math.round(nightSlider.dragging ? nightSlider.liveValue : night.host.nightTemperature) + "K"
        color: Qt.darker(night.host.bar.foreground, 1.4)
        font.family: night.host.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    PanelSlider {
      id: nightSlider
      bar: night.host.bar
      width: parent.width
      // Slider runs warm -> cool so dragging right cools the picture down.
      minimum: 2000
      maximum: 6500
      step: 100
      integer: true
      // Inverted: a lower Kelvin is a warmer (stronger) filter.
      value: 8500 - night.host.nightTemperature
      onMoved: function(v) { night.host.nightTemperature = Model.clampTemperature(8500 - v) }
      onReleased: function(v) { night.host.setNightTemperature(8500 - v) }
    }
  }

  component Toggle: Item {
    id: toggleRow
    width: parent.width
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight)
    required property QtObject host

    Column {
      id: toggleLabel
      anchors.left: parent.left
      anchors.right: toggleSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "Reduce blue light"
        color: toggleRow.host.bar.foreground
        font.family: toggleRow.host.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: toggleRow.host.nightEnabled
          ? "Warm tint on \u00b7 " + toggleRow.host.nightTemperature + "K"
          : "Screen tint is neutral"
        color: Qt.darker(toggleRow.host.bar.foreground, 1.4)
        font.family: toggleRow.host.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    ToggleSwitch {
      id: toggleSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: toggleRow.host.nightEnabled
      foreground: toggleRow.host.bar.foreground
      accent: Commons.Color.accent
      onToggled: toggleRow.host.setNightEnabled(!toggleRow.host.nightEnabled)
    }
  }
}
