import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Label + dropdown row. Wraps the shell's Dropdown so every settings row in
// the panel reads the same, and maps the current value onto the option list.
Item {
  id: row
  required property QtObject host
  property string label: ""
  property var options: []
  property var currentValue: null

  signal picked(string value)

  implicitHeight: Math.max(labelText.implicitHeight, dropdown.implicitHeight)
  height: implicitHeight

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(2)
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, parent.width * 0.42)
    textFormat: Text.PlainText
    text: row.label
    color: row.host.bar.foreground
    font.family: row.host.bar.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  Dropdown {
    id: dropdown
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(Style.spacing.dropdownWidth, parent.width - labelText.width - Style.space(12))
    showLabel: false
    foreground: row.host.bar.foreground
    background: Commons.Color.popups.background
    popupBorder: Commons.Color.popups.border
    accent: Commons.Color.accent
    fontFamily: row.host.bar.fontFamily
    options: row.options
    value: row.currentValue === null || row.currentValue === undefined ? "" : String(row.currentValue)
    onChanged: function(v) { row.picked(v) }
  }
}
