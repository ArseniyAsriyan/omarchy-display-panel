import QtQuick
import qs.Commons

// Hero header for the panel: icon, title, and a one-line status.
Item {
  id: hero
  required property QtObject host

  implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

  Text {
    id: heroIcon
    textFormat: Text.PlainText
    text: hero.host.displays.length > 1 ? "󰍺" : "󰍹"
    color: hero.host.bar.foreground
    font.family: hero.host.bar.fontFamily
    font.pixelSize: Style.font.display
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
  }

  Column {
    id: heroLabels
    anchors.left: heroIcon.right
    anchors.leftMargin: Style.space(14)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: "Display"
      color: hero.host.bar.foreground
      font.family: hero.host.bar.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
      width: parent.width
    }

    Text {
      textFormat: Text.PlainText
      text: {
        var label = hero.host.enabledDisplayCount + " of " + hero.host.displays.length + " active"
        if (hero.host.nightEnabled) label += "  \u00b7  night " + hero.host.nightTemperature + "K"
        return label.toUpperCase()
      }
      color: Qt.darker(hero.host.bar.foreground, 1.4)
      font.family: hero.host.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      elide: Text.ElideRight
      width: parent.width
    }
  }
}
