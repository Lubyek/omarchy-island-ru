import QtQuick

// iOS-style bars driven by the existing CAVA service's real spectrum.
// Frequency bins are grouped to fit each view; no synthetic motion is added.
Row {
  id: wave
  property color color: "white"
  property bool playing: false
  property var spectrum: null
  readonly property var levels: spectrum && spectrum.available ? spectrum.levels : []
  readonly property bool reacting: playing && !!spectrum && spectrum.available && spectrum.playing
  property int bars: 5
  property real barWidth: 3
  property real maxHeight: 18

  spacing: barWidth

  function levelAt(index) {
    if (!reacting || !levels.length || bars <= 0) return 0
    // RMS preserves a beat in a narrow band without exaggerating quiet bins.
    var start = Math.floor(index * levels.length / bars)
    var end = Math.max(start + 1, Math.floor((index + 1) * levels.length / bars))
    var power = 0, count = 0
    for (var i = start; i < Math.min(end, levels.length); i++) {
      var level = Number(levels[i])
      if (!isFinite(level)) level = 0
      level = Math.max(0, Math.min(1, level))
      power += level * level
      count++
    }
    return count ? Math.sqrt(power / count) : 0
  }

  Repeater {
    id: repeater
    model: wave.bars + 2
    delegate: Rectangle {
      required property int index
      objectName: "islandAudioBar_" + index
      readonly property bool dot: index === 0 || index === wave.bars + 1
      property real level: 0
      property real target: 0
      width: wave.barWidth
      height: dot ? wave.barWidth : wave.barWidth + (wave.maxHeight - wave.barWidth) * level
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: wave.color
      opacity: dot ? 0.8 : 1
    }
  }

  property real lastTick: 0
  property bool settling: true
  onPlayingChanged: settling = true
  onReactingChanged: settling = true
  onLevelsChanged: settling = true
  // 30 Hz: the bars ease toward their targets by elapsed time, so this looks
  // the same as every frame at half the redraws.
  Timer {
    interval: 33
    repeat: true
    running: wave.visible && (wave.settling || wave.reacting)
    onRunningChanged: wave.lastTick = Date.now()
    onTriggered: {
      var now = Date.now()
      var elapsed = Math.min(64, Math.max(0, now - wave.lastTick))
      wave.lastTick = now
      var moving = false
      for (var i = 1; i <= wave.bars; i++) {
        var bar = repeater.itemAt(i)
        if (!bar) continue
        bar.target = wave.levelAt(i - 1)
        // Fast attack follows transients; a softer release avoids flicker.
        var response = 1 - Math.exp(-elapsed / (bar.target > bar.level ? 35 : 100))
        bar.level += (bar.target - bar.level) * response
        if (Math.abs(bar.target - bar.level) < 0.002) bar.level = bar.target
        else moving = true
      }
      wave.settling = moving
    }
  }
}
