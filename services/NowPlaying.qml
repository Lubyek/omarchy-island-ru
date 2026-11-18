import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "ActivityPriority.mjs" as Priority

// What's playing, from Omarchy's media service: the active player, its cover
// art, and a tint picked from the cover for the media pill and player view.
Item {
  id: nowPlaying
  required property var shell
  required property var theme

  readonly property var service: shell ? shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var player: service ? service.activePlayer : null
  readonly property bool playing: !!(player && player.isPlaying)
  readonly property string title: player ? String(player.trackTitle || "") : ""
  readonly property string artist: player ? String(player.trackArtist || "") : ""
  // If the art URL goes empty while the title stays the same, the last art
  // keeps showing.
  readonly property string reportedArt: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
  property string keptArt: ""
  property string keptArtTitle: ""
  onReportedArtChanged: if (reportedArt) { keptArt = reportedArt; keptArtTitle = title }
  onTitleChanged: if (title !== keptArtTitle) { keptArt = reportedArt; keptArtTitle = title }
  readonly property string art: reportedArt || (title === keptArtTitle ? keptArt : "")

  readonly property string source: player ? [player.dbusName, player.identity, player.desktopEntry].join(" ") : ""
  readonly property string metadataKind: player ? Priority.mediaKind(player.metadata, reportedArt, source) : ""
  readonly property bool chromium: !!player && /^org\.mpris\.MediaPlayer2\.chromium(?:\.instance\d+)?$/.test(player.dbusName)
  readonly property var browserClass: /chromium|chrome|firefox|zen|brave|vivaldi|librewolf|floorp/i
  readonly property string tabKind: {
    if (!playing || metadataKind || !browserClass.test(source) || !title) return ""
    for (var window of ToplevelManager.toplevels.values) {
      if (!browserClass.test(window.appId)) continue
      var kind = Priority.browserTabKind(title, String(window.title || ""))
      if (kind) return kind
    }
    return ""
  }
  readonly property string probeKey: playing && chromium && title && !metadataKind && !tabKind
    ? JSON.stringify([player.dbusName, title, artist]) : ""
  readonly property string kind: metadataKind || tabKind
    || (probeKey && youtubeProbe.key === probeKey && youtubeProbe.matched ? "video" : "music")

  // Chromium may strip the URL from MPRIS. Ask the existing YouTube bridge
  // once for an ambiguous track, without a background polling loop.
  onProbeKeyChanged: if (probeKey) probeTimer.restart()
  Timer { id: probeTimer; interval: 150; onTriggered: nowPlaying.probeYoutube() }
  function probeYoutube() {
    if (!probeKey || youtubeProbe.running || youtubeProbe.key === probeKey) return
    youtubeProbe.key = probeKey
    youtubeProbe.track = title
    youtubeProbe.matched = false
    youtubeProbe.running = true
  }
  readonly property string browserBridge: decodeURIComponent(String(Qt.resolvedUrl("../browser/bridge.py")).replace(/^file:\/\//, ""))
  Process {
    id: youtubeProbe
    property string key: ""
    property string track: ""
    property bool matched: false
    command: ["python3", nowPlaying.browserBridge, "status", track]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { youtubeProbe.matched = JSON.parse(text).matched === true } catch (_) {}
      }
    }
    onExited: if (key !== nowPlaying.probeKey) Qt.callLater(nowPlaying.probeYoutube)
  }

  ColorQuantizer {
    id: coverColors
    source: nowPlaying.art
    depth: 2
    rescaleSize: 64
  }
  // The cover's most vivid colour, or the theme's accent for a grey cover.
  readonly property color tint: {
    var best = null, bestScore = -1
    var colors = coverColors.colors || []
    for (var i = 0; i < colors.length; i++) {
      var c = colors[i]
      var score = c.hsvSaturation * 0.7 + c.hsvValue * 0.3
      if (score > bestScore) { bestScore = score; best = c }
    }
    if (!best || best.hsvSaturation < 0.12) return theme.accent
    return Qt.hsva(best.hsvHue, Math.min(1, best.hsvSaturation), Math.max(0.75, best.hsvValue), 1)
  }
}
