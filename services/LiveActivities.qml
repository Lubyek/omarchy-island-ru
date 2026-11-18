import QtQuick
import "../i18n" as Locale
import "ActivityPriority.mjs" as Priority

Item {
  id: live
  required property var host
  readonly property var media: host.nowPlaying
  readonly property var timer: host.addons.root("timer")
  readonly property var pomodoro: host.barWidgets.widget("pomodoro-omarchy")
  readonly property var meetings: host.addons.root("meetings")
  readonly property var recorder: host.recorder
  readonly property var downloads: host.downloads
  readonly property var packages: host.packages

  readonly property var indicatorOrder: Priority.normalizeOrder(host.settings.indicatorOrder,
    host.addons.option("agents", "prioritizeMedia") === false)
  readonly property var defaultIndicatorOrder: Priority.defaultOrder
  readonly property var indicatorTypes: Priority.indicators

  function moveIndicator(id, offset) {
    var next = Priority.moveIndicator(indicatorOrder, id, offset)
    if (next !== indicatorOrder) host.settings.indicatorOrder = next.join(",")
  }
  function resetIndicatorOrder() {
    host.settings.indicatorOrder = defaultIndicatorOrder.join(",")
  }

  readonly property string mediaKey: media.player && (media.playing || media.title)
    ? "media:" + JSON.stringify([media.player.dbusName || "", media.title, media.artist]) : ""
  readonly property var entries: {
    var result = host.agentSessions.map(function(s) {
      return {
        key: agentKey(s), kind: "agent", label: s.name, session: s,
        glyph: s.state === "done" ? "󰄬" : s.state === "failed" ? "󰅖"
          : s.state === "asking" ? "󰋗" : host.agentGlyph(s),
        tint: host.agentTint(s),
        detail: s.state === "done" ? tr("Готово", "Done")
          : s.state === "failed" ? tr("Завершено с ошибкой", "Exited with an error")
          : s.state === "asking" ? tr("Ждёт ответа", "Waiting for input")
          : s.state === "tool" ? tr("Выполняет команду", "Running a command")
          : tr("Работает над задачей", "Working"),
        tail: function(now) { return elapsed((s.doneAt || now) - s.startedAt) },
        open: function() { host.openAgentWindow(s) }
      }
    })
    if (mediaKey) result.push({
      key: mediaKey, kind: "media", label: media.title || tr("Медиа", "Media"),
      detail: (media.playing ? tr("Воспроизводится", "Playing") : tr("На паузе", "Paused"))
        + (media.artist ? " · " + media.artist : ""),
      art: media.art, glyph: "󰝚", tint: media.tint, open: function() { host.view = "player" }
    })
    if (timer && timer.phase !== "idle") result.push({
      key: "timer", kind: "timer", label: tr("Таймер", "Timer"), glyph: "󰔛", tint: "#ff9f0a",
      detail: timer.phase === "paused" ? tr("На паузе", "Paused") : tr("До окончания", "Time remaining"),
      tail: function() { return timer ? timer.timeText(timer.remaining) : "" },
      open: function() { host.view = "timer" }
    })
    if (pomodoro && pomodoro.isSessionActive) result.push({
      key: "pomodoro", kind: "pomodoro", label: "Pomodoro", glyph: "󰔟", tint: "#ff6961",
      detail: pomodoro.paused ? tr("На паузе", "Paused")
        : pomodoro.phase === "break" ? tr("Перерыв", "Break") : tr("Фокус", "Focus"),
      tail: function() { return pomodoro ? pomodoro.formattedTime : "" },
      open: function() { host.summonBarWidget("pomodoro-omarchy") }
    })
    if (meetings && meetings.inCall) result.push({
      key: "meetings", kind: "meetings", label: tr("Звонок", "Call"), glyph: "󰏲", tint: "#30d158",
      tail: function() { return meetings ? elapsed(meetings.elapsed) : "" }
    })
    if (host.settings.screenRecordingActivity && recorder.active) result.push({
      key: "recording", kind: "recording", label: tr("Запись экрана", "Screen recording"),
      glyph: "󰑊", tint: "#ff453a", tail: function() { return elapsed(recorder.elapsed) }
    })
    if (downloads.active || downloads.finishedName) result.push({
      key: "downloads", kind: "downloads", label: downloads.finishedName || tr("Загрузки", "Downloads"),
      detail: downloads.finishedName ? tr("Загрузка завершена", "Download complete") : "",
      glyph: "󰇚", tint: "#64d2ff",
      tail: function() { return downloads.sized ? Math.floor(downloads.progress * 100) + "%" : "" },
      open: function() { host.openDownloads() }
    })
    if (packages.active || packages.finishedTitle) result.push({
      key: "updates", kind: "updates", label: tr("Обновления", "Updates"),
      detail: packages.finishedTitle ? Locale.I18n.tr(packages.finishedTitle) : "",
      glyph: "󰚰", tint: "#0a84ff",
      tail: function() { return Locale.I18n.tr(packages.status) }
    })
    return result
  }

  property var hiddenKeys: []
  readonly property var visibleEntries: entries.filter(function(entry) { return !isHidden(entry.key) })
  readonly property var activeAgents: visibleEntries.filter(function(e) {
    return e.kind === "agent" && e.session.state !== "done" && e.session.state !== "failed"
  }).map(function(e) { return e.session }).sort(function(a, b) {
    return Number(b.state === "asking") - Number(a.state === "asking") || b.startedAt - a.startedAt
  })
  readonly property var hiddenEntries: entries.filter(function(entry) { return isHidden(entry.key) })
  readonly property var byKey: {
    var map = {}
    for (var i = 0; i < entries.length; i++) map[entries[i].key] = entries[i]
    return map
  }
  function isHidden(key) { return hiddenKeys.indexOf(key) !== -1 }
  function setHidden(key, hidden) {
    if (hidden === isHidden(key)) return
    hiddenKeys = hidden ? hiddenKeys.concat([key]) : hiddenKeys.filter(function(id) { return id !== key })
  }
  // A new activity comes back by itself. Defer pruning until transient
  // changes in player metadata and the other activity sources have settled.
  onEntriesChanged: Qt.callLater(pruneHidden)
  function pruneHidden() {
    var next = hiddenKeys.filter(function(key) {
      return entries.some(function(entry) { return entry.key === key })
    })
    if (next.length !== hiddenKeys.length) hiddenKeys = next
  }

  function agentKey(s) { return "agent:" + s.id + ":" + s.startedAt }
  function tr(ru, en) { return Locale.I18n.language === "ru" ? ru : en }
  function elapsed(ms) {
    var seconds = Math.floor(Math.max(0, ms) / 1000)
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor(seconds % 3600 / 60)
    return (hours ? hours + ":" + ("0" + minutes).slice(-2) : minutes) + ":" + ("0" + seconds % 60).slice(-2)
  }

  property double watchingSince: Date.now()
  property var announced: ({})
  property var pending: []
  property var notice: null

  function noticeKey(event) {
    return agentKey(event) + ":" + event.noticeKind + ":" + event.noticeAt
      + (event.noticeKind === "asking" ? ":" + (event.questionId || "") : "")
  }

  Connections {
    target: live.host
    function onAgentSessionsChanged() { live.collectNotices() }
  }
  function collectNotices() {
    var now = Date.now()
    var cutoff = Math.max(watchingSince, now - 4400)
    var seen = {}
    for (var key in announced)
      if (announced[key] >= now - 60000) seen[key] = announced[key]
    var next = pending.slice()
    function add(session, kind, stamp) {
      if (!stamp || stamp < cutoff) return
      var event = Object.assign({}, session, {noticeKind: kind, noticeAt: stamp})
      var id = noticeKey(event)
      if (!seen[id]) next.push(event)
      seen[id] = stamp
    }
    for (var i = 0; i < host.agentSessions.length; i++) {
      var s = host.agentSessions[i]
      add(s, "asking", s.askedAt)
      if (s.state === "done" || s.state === "failed") add(s, s.state, s.doneAt)
    }
    announced = seen
    next.sort(function(a, b) { return a.noticeAt - b.noticeAt })
    pending = next.slice(-6)
    if (!notice) advanceNotice()
  }
  function advanceNotice() {
    var cutoff = Date.now() - 4400
    pending = pending.filter(function(event) { return event.noticeAt >= cutoff })
    if (!pending.length) {
      notice = null
      return
    }
    var next = pending[0]
    pending = pending.slice(1)
    notice = Object.assign({}, next, {dismissAt: Date.now() + noticeTimer.interval})
    noticeTimer.restart()
  }
  Timer {
    id: noticeTimer
    interval: 2200
    onTriggered: live.advanceNotice()
  }
}
