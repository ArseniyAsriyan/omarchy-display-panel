pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Everything under the display list, laid out the way Windows 11 groups it:
// a display picker, then per-display Display resolution, Display orientation,
// Display position, Scale, Brightness and Text size. Night light follows in
// NightSection.
Column {
  id: sections
  required property QtObject host
  spacing: Style.space(14)

  DisplayList { width: parent.width; host: sections.host }

  // ---- Display resolution -----------------------------------------------------
  // Windows 11 pairs resolution and refresh rate in one "Display resolution"
  // group; a separate "Advanced display" page holds the refresh rate, so it is
  // kept right below the resolution here.

  Column {
    width: parent.width
    spacing: Style.space(6)
    visible: sections.host.targetEnabled

    PanelSectionHeader {
      text: "DISPLAY RESOLUTION"
      foreground: sections.host.bar.foreground
      fontFamily: sections.host.bar.fontFamily
    }

    Repeater {
      // Dropdown.value must equal one of the option values, so both sides use
      // the option index; the label carries the human-readable text.
      model: [{
        label: "Display resolution",
        value: String(sections.host.targetResolutionIndex),
        options: sections.host.targetResolutions.map(function(r, i) {
          return { value: String(i), label: String(r.width) + " \u00d7 " + String(r.height) }
        }),
        onPick: function(v) { sections.host.applyResolutionAndRate(Number(v), -1) }
      }, {
        label: "Refresh rate",
        value: String(sections.host.targetRateIndex),
        options: sections.host.targetRates.map(function(r, i) {
          return { value: String(i), label: r.label + " Hz" }
        }),
        onPick: function(v) { sections.host.applyRate(Number(v)) }
      }]

      SettingsDropdown {
        required property var modelData
        required property int index

        width: sections.width
        host: sections.host
        label: modelData.label
        options: modelData.options
        currentValue: modelData.value
        onPicked: function(v) { modelData.onPick(v) }
      }
    }
  }

  // ---- Display orientation ------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(6)
    visible: sections.host.targetEnabled

    PanelSectionHeader {
      text: "DISPLAY ORIENTATION"
      foreground: sections.host.bar.foreground
      fontFamily: sections.host.bar.fontFamily
    }

    SettingsDropdown {
      width: sections.width
      host: sections.host
      label: "Orientation"
      options: Model.orientations().map(function(o) {
        return { value: o.id, label: o.label }
      })
      currentValue: sections.host.targetDisplay
        ? Model.orientationForTransform(sections.host.targetDisplay.transform).id : "landscape"
      onPicked: function(v) { sections.host.applyOrientation(v) }
    }
  }

  // ---- Display position -----------------------------------------------------------
  // Move the monitor in space relative to the others (matters for which way the
  // cursor crosses between screens).
  Column {
    width: parent.width
    spacing: Style.space(6)
    visible: sections.host.targetEnabled && sections.host.displays.length > 1

    PanelSectionHeader {
      text: "DISPLAY POSITION"
      foreground: sections.host.bar.foreground
      fontFamily: sections.host.bar.fontFamily
    }

    Grid {
      columns: 2
      spacing: Style.space(4)

      Button {
        text: "Left"
        foreground: sections.host.bar.foreground
        fontFamily: sections.host.bar.fontFamily
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        onClicked: sections.host.moveTargetDisplay("left")
      }
      Button {
        text: "Right"
        foreground: sections.host.bar.foreground
        fontFamily: sections.host.bar.fontFamily
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        onClicked: sections.host.moveTargetDisplay("right")
      }
      Button {
        text: "Up"
        foreground: sections.host.bar.foreground
        fontFamily: sections.host.bar.fontFamily
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        onClicked: sections.host.moveTargetDisplay("up")
      }
      Button {
        text: "Down"
        foreground: sections.host.bar.foreground
        fontFamily: sections.host.bar.fontFamily
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        onClicked: sections.host.moveTargetDisplay("down")
      }
    }
  }

  // ---- Scale ----------------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(10)
    visible: sections.host.targetEnabled

    Item {
      width: parent.width
      implicitHeight: Math.max(scaleHeader.implicitHeight, scaleHint.implicitHeight)

      PanelSectionHeader {
        id: scaleHeader
        text: "SCALE"
        foreground: sections.host.bar.foreground
        fontFamily: sections.host.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: scaleHint
        textFormat: Text.PlainText
        text: "change the size of text and apps"
        color: Qt.darker(sections.host.bar.foreground, 1.6)
        font.family: sections.host.bar.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width * 0.6)
      }
    }

    Grid {
      id: scaleRow
      width: parent.width
      columns: Math.max(1, sections.host.scaleValues.length)
      spacing: Style.spacing.xs

      readonly property real cellWidth: sections.host.scaleValues.length > 0
        ? (width - spacing * (columns - 1)) / columns : 0

      Repeater {
        model: sections.host.scaleValues

        Button {
          required property string modelData
          required property int index

          width: scaleRow.cellWidth
          text: sections.host.targetDisplay
            ? Model.cleanScale(modelData, sections.host.targetDisplay.width, sections.host.targetDisplay.height) + "x"
            : modelData + "x"
          fontSize: Style.font.caption
          foreground: sections.host.bar.foreground
          fontFamily: sections.host.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          active: sections.host.targetDisplay
            ? Model.matchingScaleIndex(sections.host.scaleValues, sections.host.targetDisplay.scale,
                                      sections.host.targetDisplay.width, sections.host.targetDisplay.height) === index
            : false
          onClicked: sections.host.applyScale(modelData)
        }
      }
    }
  }

  // ---- Brightness --------------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(6)
    visible: sections.host.brightnessAvailable

    Item {
      width: parent.width
      implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

      PanelSectionHeader {
        id: brightnessHeader
        text: "BRIGHTNESS"
        foreground: sections.host.bar.foreground
        fontFamily: sections.host.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: brightnessPercent
        textFormat: Text.PlainText
        text: Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : sections.host.brightnessPercent) + "%"
        color: Qt.darker(sections.host.bar.foreground, 1.4)
        font.family: sections.host.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    PanelSlider {
      id: brightnessSlider
      bar: sections.host.bar
      width: parent.width
      minimum: 1
      maximum: 100
      step: 1
      integer: true
      value: sections.host.brightnessPercent
      onMoved: function(v) { sections.host.previewBrightness(v) }
      onReleased: function(v) {
        brightnessDebounce.stop()
        sections.host.setBrightness(v)
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: sections.host.setBrightness(sections.host.brightnessPercent)
  }

  // ---- Text size ----------------------------------------------------------------------

  Column {
    width: parent.width
    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(textSizeHeader.implicitHeight, textSizePx.implicitHeight)

      PanelSectionHeader {
        id: textSizeHeader
        text: "TEXT SIZE"
        foreground: sections.host.bar.foreground
        fontFamily: sections.host.bar.fontFamily
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: textSizePx
        textFormat: Text.PlainText
        text: (textSizeSlider.dragging
               ? sections.host.textSizeStops[Math.round(textSizeSlider.liveValue)]
               : sections.host.displayedTextPx()) + "px"
        color: Qt.darker(sections.host.bar.foreground, 1.4)
        font.family: sections.host.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    PanelSlider {
      id: textSizeSlider
      bar: sections.host.bar
      width: parent.width
      minimum: 0
      maximum: sections.host.textSizeStops.length - 1
      step: 1
      integer: true
      tickCount: sections.host.textSizeStops.length
      value: sections.host.currentTextIndex()
      onReleased: function(v) { sections.host.setTextSize(sections.host.textSizeStops[Math.round(v)]) }
    }
  }
}
