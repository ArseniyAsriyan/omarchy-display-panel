import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Windows 11-style "Keep these display settings?" prompt, shown as its own
// centred window on the focused monitor.
//
// State comes in as plain properties (not a host object) so the per-screen
// PanelWindows can bind to them without going through a nested QtObject, which
// was flaky inside Variants.
//
// One window per screen, full-screen sized, so nothing has to be resized when
// the arrangement reconfigures outputs (resizing a layer surface mid-
// reconfigure has crashed the Qt wayland client).
Item {
  id: dialog

  property bool pending: false
  property int seconds: 15
  property string summary: ""
  // Output name of the screen the prompt should appear on.
  property string focusedOutput: ""

  signal keepRequested()
  signal revertRequested()

  readonly property int cardWidth: Style.space(420)

  // Name of the screen to show on: the focused output, or the first screen so
  // the prompt is never lost if the names disagree.
  readonly property string targetScreenName: {
    var screens = Quickshell.screens || []
    var want = dialog.focusedOutput
    for (var i = 0; i < screens.length; i++) {
      if (screens[i] && screens[i].name === want) return screens[i].name
    }
    return screens.length > 0 && screens[0] ? screens[0].name : ""
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: window
      required property var modelData
      screen: modelData
      // Only the focused screen's window shows the prompt.
      visible: dialog.pending && (modelData && modelData.name === dialog.targetScreenName)

      WlrLayershell.namespace: "io-github-arseniyasriyan-display-confirm"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }

      // Dimmed backdrop; clicking anywhere reverts, since dismissing is the
      // safe outcome.
      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea {
          anchors.fill: parent
          onClicked: dialog.revertRequested()
        }
      }

      BorderSurface {
        id: card
        anchors.centerIn: parent
        width: card.width
        implicitHeight: content.implicitHeight + Style.spacing.panelPadding * 2
        color: Color.background
        borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
        }

        Column {
          id: content
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.space(12)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Keep these display settings?"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: dialog.summary !== "" ? dialog.summary
                                        : "The display settings will be reverted."
            color: Qt.darker(Color.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Rectangle {
            width: parent.width
            height: Math.max(4, Style.space(5))
            radius: height / 2
            color: Qt.darker(Color.foreground, 2.2)

            Rectangle {
              height: parent.height
              radius: parent.radius
              color: Color.accent
              width: parent.width * (dialog.seconds / 15)
              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.Linear } }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Reverting in " + dialog.seconds + "s"
            color: Qt.darker(Color.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            anchors.right: parent.right
            spacing: Style.spacing.sm

            Button {
              text: "Revert"
              foreground: Color.foreground
              fontFamily: Style.font.family
              horizontalPadding: Style.spacing.md
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: dialog.revertRequested()
            }

            Button {
              text: "Keep changes"
              foreground: Color.foreground
              fontFamily: Style.font.family
              horizontalPadding: Style.spacing.md
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              active: true
              onClicked: dialog.keepRequested()
            }
          }
        }
      }
    }
  }
}
