import QtQuick
import QtQuick.Layouts
import "../addons/agents"

Rectangle {
  id: banner
  required property var host
  property var session: null
  readonly property var theme: host.theme
  readonly property bool shown: !!session
  property var displayed: null
  onSessionChanged: if (session) displayed = session

  readonly property bool asking: displayed?.noticeKind === "asking"
  readonly property bool failed: displayed?.noticeKind === "failed"
  readonly property color tint: asking ? theme.system.orange : failed ? theme.system.red : theme.system.green
  readonly property color mascotTint: host.agentMascotTint(displayed)
  readonly property string subtitle: asking ? host.liveActivities.tr("Агент задал вопрос", "Agent asked a question")
    : failed ? host.liveActivities.tr("Завершено с ошибкой", "Exited with an error")
    : host.liveActivities.tr("Работа завершена", "Task completed")
  readonly property real progress: shown ? 1 : 0
  property real reveal: progress
  Behavior on reveal { MotionAnimation { theme: banner.theme; pace: banner.shown ? "morph" : "exit" } }
  opacity: Math.min(1, reveal * 1.7)
  visible: opacity > 0.01
  y: -height + (height + (host.settings.notch ? 3 : 9)) * reveal
  anchors.horizontalCenter: parent.horizontalCenter
  width: Math.min(328, parent.width - 22)
  height: 62
  radius: 24
  z: 25
  color: theme.background
  border.width: 1
  border.color: theme.outlineColor
  scale: (0.96 + 0.04 * reveal) * (tap.pressed ? 0.975 : 1)
  Behavior on scale { MotionAnimation { theme: banner.theme; pace: "quick" } }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: 13
    anchors.rightMargin: 15
    spacing: 10

    Rectangle {
      Layout.preferredWidth: 39
      Layout.preferredHeight: 39
      radius: 13
      color: banner.theme.withAlpha(banner.mascotTint, 0.24)
      AgentAvatar {
        session: banner.displayed
        stackySource: banner.host.agents?.stackySource || ""
        anchors.centerIn: parent
        color: banner.mascotTint
        animationKey: banner.displayed ? banner.host.liveActivities.noticeKey(banner.displayed) : ""
        mood: banner.asking ? "wave" : banner.failed ? "failed" : "done"
        celebrationUntil: banner.displayed?.noticeKind === "done" ? banner.displayed.dismissAt - 500 : 0
        running: banner.shown && banner.reveal >= 0.86
        tempo: banner.theme.motionScale / 1.5
      }
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 3
      Text {
        Layout.fillWidth: true
        text: banner.displayed?.name || ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: banner.theme.text
        font.family: banner.theme.textFontFamily
        font.pixelSize: banner.theme.size.body
        font.weight: Font.DemiBold
      }
      Text {
        Layout.fillWidth: true
        text: banner.subtitle
        color: banner.theme.secondary
        font.family: banner.theme.textFontFamily
        font.pixelSize: banner.theme.size.subheadline
      }
    }
    Rectangle {
      Layout.preferredWidth: 23
      Layout.preferredHeight: 23
      radius: 12
      color: banner.theme.withAlpha(banner.tint, 0.16)
      Text {
        anchors.centerIn: parent
        text: banner.asking ? "󰋗" : banner.failed ? "󰅖" : "󰄬"
        color: banner.tint
        font.family: banner.theme.fontFamily
        font.pixelSize: banner.theme.px(15)
      }
    }
  }

  HoverHandler { enabled: banner.shown; cursorShape: Qt.PointingHandCursor }
  TapHandler {
    id: tap
    enabled: banner.shown
    onTapped: if (banner.session) banner.host.openAgentWindow(banner.session)
  }
  Accessible.role: Accessible.Button
  Accessible.name: (displayed?.name || "") + " · " + subtitle
  Accessible.description: host.liveActivities.tr("Открыть окно агента", "Open agent window")
  Accessible.onPressAction: if (session) host.openAgentWindow(session)
}
