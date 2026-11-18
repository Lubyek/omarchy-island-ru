import QtQuick

Item {
  id: avatar
  required property var session
  property url stackySource: ""
  required property color color
  property string mood: "rest"
  property string animationKey: ""
  onAnimationKeyChanged: {
    sprite.frame = 0
    mascot.tick = 0
    Qt.callLater(syncCelebration)
  }
  property double celebrationUntil: 0
  property bool running: false
  property real tempo: 1
  readonly property bool codex: session?.provider === "codex"
  readonly property bool timedCelebration: mood === "done" && celebrationUntil > 0
  readonly property bool celebrationReady: timedCelebration && running
    && (!codex || atlas.status !== Image.Loading)
  onCelebrationReadyChanged: Qt.callLater(syncCelebration)
  onCelebrationUntilChanged: Qt.callLater(syncCelebration)

  property real jumpProgress: 0
  onJumpProgressChanged: if (hopAnimation.running) {
    var phase = jumpProgress % 1
    // Frame zero is grounded between hops; land() supplies the final pose.
    sprite.frame = Math.floor(phase * (sprite.count - 1))
    mascot.tick = Math.floor(phase * 4)
  }

  function land() {
    sprite.frame = sprite.count - 1
    mascot.tick = 5
  }

  function syncCelebration() {
    hopAnimation.stop()
    if (!timedCelebration) return
    var remaining = celebrationUntil - Date.now()
    if (!celebrationReady || remaining < 240) {
      if (!running || remaining < 240) land()
      return
    }

    // Fit whole hops between the reveal and the final resting pause.
    var nominalHop = (codex && atlas.status === Image.Ready ? 500 : 600) * tempo
    var cycles = Math.max(2, Math.round(remaining / nominalHop))
    sprite.frame = 0
    mascot.tick = 0
    jumpProgress = 0
    hopAnimation.to = Math.min(cycles, Math.floor(remaining / 240))
    hopAnimation.duration = remaining
    hopAnimation.start()
  }

  NumberAnimation {
    id: hopAnimation
    target: avatar
    property: "jumpProgress"
    from: 0
    easing.type: Easing.Linear
    onFinished: avatar.land()
  }

  implicitWidth: 34
  implicitHeight: 35

  Item {
    id: sprite
    anchors.fill: parent
    visible: avatar.codex && atlas.status === Image.Ready
    clip: true

    // The original ChatGPT Pets atlas, with 192 × 208 pixel cells.
    readonly property int row: avatar.mood === "failed" ? 5 : avatar.mood === "done" ? 4
      : avatar.mood === "wave" ? 6 : avatar.mood === "rest" ? 0 : 7
    readonly property int count: row === 5 ? 8 : row === 4 ? 5 : 6
    readonly property bool oneShot: row === 4 || row === 5
    readonly property real cellScale: Math.min(width / 192, height / 208)
    property int frame: 0
    onRowChanged: frame = 0

    Connections {
      target: avatar
      function onRunningChanged() { if (avatar.running) sprite.frame = 0 }
    }
    Timer {
      interval: Math.max(60, Math.round((sprite.row === 0 ? 180 : 125) * avatar.tempo))
      repeat: true
      running: sprite.visible && avatar.running && !avatar.timedCelebration
        && (!sprite.oneShot || sprite.frame < sprite.count - 1)
      onTriggered: sprite.frame = (sprite.frame + 1) % sprite.count
    }

    Image {
      id: atlas
      source: avatar.codex ? avatar.stackySource : ""
      asynchronous: true
      mipmap: true
      x: (sprite.width - 192 * sprite.cellScale) / 2 - sprite.frame * 192 * sprite.cellScale
      y: (sprite.height - 208 * sprite.cellScale) / 2 - sprite.row * 208 * sprite.cellScale
      width: 1536 * sprite.cellScale
      height: 1872 * sprite.cellScale
    }
  }

  AgentsMascot {
    id: mascot
    anchors.centerIn: parent
    visible: !sprite.visible
    color: avatar.color
    mood: avatar.mood === "failed" ? "rest" : avatar.mood
    running: avatar.running && visible && !avatar.timedCelebration && avatar.mood !== "failed"
    tempo: avatar.tempo
    onRunningChanged: if (running) tick = 0
  }
}
