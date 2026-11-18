import QtQuick
import "../../components"
import "../timer"

Item {
  id: pill
  required property var agents
  readonly property var host: agents.host
  readonly property var theme: host.theme
  readonly property var session: agents.live
  readonly property string phase: session ? session.state : ""
  readonly property color timerInk: session?.provider === "codex" ? host.agentMascotTint(session) : agents.ink

  opacity: agents.pillShown ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { MotionAnimation { theme: pill.theme; pace: "fade"; curve: "fade" } }
  PillReveal { id: reveal; theme: pill.theme; shown: pill.agents.pillShown }

  AgentAvatar {
    session: pill.session
    stackySource: pill.agents.stackySource
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    color: pill.agents.ink
    mood: pill.phase === "tool" ? "walk" : pill.phase === "asking" ? "wave" : "think"
    running: pill.agents.pillShown
    tempo: pill.theme.motionScale / 1.5
    opacity: reveal.leadingIn
    PillPart { progress: reveal.leadingIn }
  }

  Item {
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    anchors.alignWhenCentered: false
    width: Math.min(38, pill.host.pillHeight - 4)
    height: width
    opacity: reveal.trailingIn
    PillPart { progress: reveal.trailingIn }

    TimerRing {
      id: minuteRing
      anchors.fill: parent
      track: pill.timerInk
      color: "transparent"
      progress: 0
    }

    TextMetrics {
      id: elapsedMetrics
      font: elapsedLabel.font
      text: elapsedLabel.text
    }

    RollingText {
      id: elapsedLabel
      readonly property rect ink: elapsedMetrics.tightBoundingRect
      // Align the visible ink with the ring, including the font's baseline and bearings.
      anchors.centerIn: parent
      anchors.alignWhenCentered: false
      anchors.horizontalCenterOffset: (implicitWidth / 2 - ink.x - ink.width / 2) * scale
      anchors.verticalCenterOffset: (implicitHeight / 2 - baselineOffset - ink.y - ink.height / 2) * scale
      scale: Math.min(1, (parent.width - 2 * minuteRing.thickness - 3) / Math.max(1, implicitWidth))
      theme: pill.theme
      text: pill.host.liveActivities.elapsed(pill.agents.turnTime)
      color: pill.timerInk
      font.family: pill.theme.textFontFamily
      font.pixelSize: pill.theme.size.body
      font.weight: Font.DemiBold
      font.features: { "tnum": 1 }
    }
  }
}
