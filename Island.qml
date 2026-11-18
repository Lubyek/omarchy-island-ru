import QtQuick
import "i18n" as Locale
import Qt.labs.folderlistmodel
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "addons"
import "components"
import "services"
import "views"
import "components/Squircle.js" as Squircle
// Omarchy's own OSD payload model, so what the island shows matches it.
import "file:///usr/share/omarchy/shell/plugins/osd/OsdModel.js" as OsdModel

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property var barConfig: ({})
  property string omarchyPath: ""

  // The resting island's pills, highest first: a screen recording, an
  // addon's ongoing activity (see addonPill), a download or system update,
  // then the media playing. None shows while the companion needs setting up.
  readonly property bool resting: view === "rest" && !setup.needsSetup
  readonly property bool recordingPill: resting && settings.screenRecordingActivity && recorder.active
    && !liveActivities.isHidden("recording")
  readonly property bool restingFree: resting && !recordingPill && !addons.ongoing
  readonly property bool visibleFileActivity: !liveActivities.isHidden("downloads") && (downloads.active || downloads.finishedName !== "")
  readonly property bool visibleUpdateActivity: !liveActivities.isHidden("updates") && (packages.active || packages.finishedTitle !== "")
  readonly property bool downloadDone: restingFree && (visibleFileActivity ? downloads.finishedName !== ""
    : visibleUpdateActivity && packages.finishedTitle !== "")
  readonly property bool downloadActive: restingFree && (visibleFileActivity || visibleUpdateActivity) && !downloadDone
  readonly property bool downloadPill: downloadDone || downloadActive
  readonly property bool mediaAvailable: nowPlaying.playing && settings.mediaPill
    && !liveActivities.isHidden(liveActivities.mediaKey)
  readonly property bool mediaPill: restingFree && !downloadPill && mediaAvailable
  // The live-activity pills' height, and the resting clock's.
  readonly property real pillHeight: settings.notch ? 40 : 44
  readonly property real clockHeight: clockStacked ? (settings.notch ? 40 : 42) : (settings.notch ? 36 : 40)

  readonly property var nowPlaying: nowPlayingData
  readonly property var audioSpectrum: cavaSpectrum
  AudioSpectrum {
    id: cavaSpectrum
    wanted: root.nowPlaying.playing && window.visible && !window.islandHidden
      && (root.view === "player" || (mediaPillItem.shown && !agentBanner.shown))
  }
  NowPlaying { id: nowPlayingData; shell: root.shell; theme: root.theme }
  readonly property var recorder: screenRecorder
  ScreenRecorder { id: screenRecorder }
  readonly property var downloads: downloadTracker
  DownloadTracker { id: downloadTracker; enabled: root.settings.downloads }
  readonly property var packages: packageTracker
  PackageUpdateTracker { id: packageTracker; enabled: root.settings.systemUpdates }
  Process { id: downloadOpener }
  function openDownloads() {
    if (!visibleFileActivity) {
      packages.dismissFinished()
      return
    }
    var path = downloads.finishedName !== "" ? downloads.finishedPath : downloads.folder
    downloads.dismissFinished()
    downloadOpener.command = ["sh", "-c", '[ -e "$1" ] && exec xdg-open "$1"; exec xdg-open "$(dirname "$1")"', "sh", path]
    downloadOpener.startDetached()
  }

  readonly property real volume: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio
    ? Pipewire.defaultAudioSink.audio.volume : -1
  readonly property bool muted: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio
    && Pipewire.defaultAudioSink.audio.muted)
  readonly property string wantedOutput: String(barConfig.output || "DP-1")
  // The configured output is connected, so the island stays on it; otherwise
  // it follows the focused monitor.
  readonly property bool outputPinned: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === wantedOutput) return true
    return false
  }
  readonly property string outputName: {
    if (outputPinned) return wantedOutput
    var screens = Quickshell.screens
    var focused = Hyprland.focusedMonitor
    if (focused && focused.name) return String(focused.name)
    return screens.length ? String(screens[0].name) : ""
  }
  readonly property var outputScreen: Quickshell.screens.find(screen => screen.name === outputName) || null
  readonly property int screenHeight: outputScreen ? outputScreen.height : 1000
  readonly property string home: Quickshell.env("HOME")

  readonly property var theme: themeData
  Theme { id: themeData; settings: root.settings; home: root.home }
  readonly property QtObject settings: islandSettings.values
  IslandSettings { id: islandSettings; home: root.home }
  Binding { target: Locale.I18n; property: "language"; value: root.settings.language || "ru" }

  readonly property var clockDate: clock.date
  // The resting pill's text in the chosen Settings → Clock Format (one of
  // clockFormats), following the 24-hour and AM/PM switches.
  readonly property var clockFormats: [
    "time", "stackedDay", "stackedDate", "stackedFull",
    "day", "date", "short", "weekday", "full", "numeric"
  ]
  function isStackedClock(format) {
    return format === "stackedDay" || format === "stackedDate" || format === "stackedFull"
  }
  readonly property bool clockStacked: isStackedClock(settings.clockFormat)
  function formatClockTime(date) {
    var en = Qt.locale(Locale.I18n.localeName)
    return settings.clock24h ? en.toString(date, "HH:mm")
      : settings.clockAmPm ? en.toString(date, "h:mm AP")
      : en.toString(date, "h:mm AP").replace(/\s*[AP]M$/i, "")
  }
  function formatClockSub(date, format) {
    var en = Qt.locale(Locale.I18n.localeName)
    switch (format) {
    case "stackedDay": return en.toString(date, "dddd")
    case "stackedDate": return en.toString(date, "d MMM")
    case "stackedFull": return en.toString(date, "ddd d MMM")
    default: return ""
    }
  }
  readonly property string clockTimeText: formatClockTime(clockDate)
  readonly property string clockSubText: formatClockSub(clockDate, settings.clockFormat)
  readonly property string clockWidestText: clockTimeText.length > clockSubText.length ? clockTimeText : clockSubText
  readonly property string clockText: formatClock(clockDate, settings.clockFormat)
  function formatClock(date, format) {
    var en = Qt.locale(Locale.I18n.localeName)
    var time = formatClockTime(date)
    switch (format) {
    case "stackedDay":
    case "stackedDate":
    case "stackedFull":
      return time + "\n" + formatClockSub(date, format)
    case "day": return en.toString(date, "ddd") + " " + time
    case "date": return en.toString(date, "d MMM") + " " + time
    case "short": return en.toString(date, "ddd d MMM") + " " + time
    case "weekday": return en.toString(date, "dddd") + " " + time
    case "full": return en.toString(date, "ddd d MMM yyyy") + " " + time
    case "numeric": return en.toString(date, "dd/MM/yyyy") + " " + time
    default: return time
    }
  }
  property string view: "rest"
  // Settings opens on settingsPage (and, on Addons, with settingsAddon's
  // options out) the next time it's shown; both are cleared once taken.
  property string settingsPage: ""
  property string settingsAddon: ""
  function openSettings(page, addonId) {
    settingsPage = page || ""
    settingsAddon = addonId || ""
    view = "settings"
  }
  readonly property bool notificationPill: view === "feedback" && feedbackKind === "notification"
  readonly property bool volumePill: view === "feedback" && feedbackKind === "volume"
  readonly property bool osdPill: view === "feedback" && feedbackKind === "osd"
  readonly property bool clipboardPill: view === "feedback" && feedbackKind === "clipboard"
  readonly property bool activityPill: view === "feedback" && feedbackKind === "activity"
  readonly property bool workspacesPill: view === "feedback" && feedbackKind === "workspaces"
  // The addon whose pill is on the island, if any (see addons/Addon.qml):
  // the one shown for a moment, or at rest an ongoing one's.
  readonly property var addonPill: view === "feedback" ? addons.pillFor(feedbackKind)
    : resting && !recordingPill ? addons.ongoing : null

  // ---------- Workspace switches ----------

  // Omarchy's bar's workspaces: 1–5 always, and any other up to 10 that
  // exists. Switching shows them for a moment (see WorkspacePill).
  readonly property var workspaceIds: {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    return ids.sort(function(a, b) { return a - b })
  }
  readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  onFocusedWorkspaceIdChanged: {
    if (activities.ready && settings.workspaceHud && focusedWorkspaceId > 0) showFeedback("", 1200, "workspaces")
  }

  // ---------- Device live activities: battery, Bluetooth ----------

  readonly property var activities: deviceActivities
  DeviceActivities {
    id: deviceActivities
    settings: root.settings
    onShow: root.showFeedback("", 3200, "activity")
  }


  // Other plugins' bar widgets; the shell opens them through the three
  // functions below (see services/BarWidgetHost).
  readonly property var barWidgets: barWidgetHost
  BarWidgetHost { id: barWidgetHost; host: root }
  function summonBarWidget(id) {
    if (!barWidgetHost.widget(id)) return false
    view = "rest"
    return barWidgetHost.summon(id)
  }
  function hideBarWidget(id) { return barWidgetHost.hide(id) }
  function isBarWidgetOpen(id) { return barWidgetHost.isOpen(id) }

  readonly property var addons: addonHost
  Addons { id: addonHost; host: root; settings: root.settings }

  readonly property var agents: addons.root("agents")
  readonly property var agentSessions: agents ? agents.sessions : []
  readonly property LiveActivities liveActivities: LiveActivities { host: root }
  function openAgentWindow(session) {
    if (!session || agentWindow.running || agentFocusDelay.running) return
    agentWindow.targetNoticeKey = session.noticeKind ? liveActivities.noticeKey(session) : ""
    agentWindow.returnView = surfaceOpen ? view : ""
    agentWindow.command = ["python3", setup.companionDir + "/agent_window.py", JSON.stringify(session)]
    if (surfaceOpen) {
      // Release the Control Center's exclusive layer keyboard focus before
      // activating the window, especially when its scratchpad opens too.
      view = "rest"
      agentFocusDelay.restart()
    } else {
      agentWindow.running = true
    }
  }
  Timer {
    id: agentFocusDelay
    interval: 120
    onTriggered: agentWindow.running = true
  }
  Process {
    id: agentWindow
    property string targetNoticeKey: ""
    property string returnView: ""
    onExited: function(code) {
      if (code === 0) {
        var notice = root.liveActivities.notice
        if (notice && root.liveActivities.noticeKey(notice) === targetNoticeKey) root.liveActivities.advanceNotice()
      } else if (returnView && root.view === "rest" && root.surfaceOpenFor(returnView)) {
        root.view = returnView
      } else if (!root.surfaceOpen && !root.liveActivities.notice) {
        root.showFeedback(Locale.I18n.tr("The agent window is unavailable"), 1400, "system")
      }
    }
  }
  function agentGlyph(session) {
    return session.provider === "codex" ? "" : session.provider === "claude" ? "" : "󰆍"
  }
  function agentMascotTint(session) {
    if (session?.provider === "codex") return "#aca1c8"
    if (session?.provider === "claude") return "#d97757"
    return settings.colorfulLiveActivities ? "#bf8af6" : theme.accent
  }
  function agentTint(session) {
    if (session.state === "asking") return "#ff9f0a"
    if (session.state === "done") return "#30d158"
    if (session.state === "failed") return "#ff453a"
    if (!settings.colorfulLiveActivities) return theme.accent
    return session.provider === "claude" ? "#d97757" : session.provider === "codex" ? "#64d2ff" : "#bf8af6"
  }

  readonly property var keyboard: keyboardLayout
  KeyboardLayout { id: keyboardLayout }

  readonly property var clipboard: clipboardWatcher
  ClipboardWatcher {
    id: clipboardWatcher
    home: root.home
    settings: root.settings
    onCopied: root.showFeedback("", 2200, "clipboard")
  }

  property bool surfaceContentReady: false
  property string feedback: ""
  property string feedbackKind: ""
  property var surfaceNames: []
  // Once per screen's copy of a view; it stops counting as one when the last
  // copy goes (an addon switched off, a screen unplugged).
  function registerSurface(name) {
    surfaceNames = surfaceNames.concat([name])
  }
  function unregisterSurface(name) {
    var i = surfaceNames.indexOf(name)
    if (i === -1) return
    var next = surfaceNames.slice()
    next.splice(i, 1)
    surfaceNames = next
    if (view === name && next.indexOf(name) === -1) view = "rest"
  }
  readonly property bool surfaceOpen: surfaceNames.indexOf(view) !== -1
  property bool initialized: false
  readonly property bool barHidden: barOffFlag.count > 0
  FolderListModel {
    id: barOffFlag
    folder: "file://" + root.home + "/.local/state/omarchy/toggles"
    nameFilters: ["bar-off"]
    showDirs: false
    showHidden: true
  }

  // Auto-hide. The screensaver and fullscreen come live from Wayland and
  // Quickshell's own tracking; only "floating" lives in Hyprland's client
  // list, which Quickshell refetches on request. So while Hide on Tiling is
  // on, a burst of window events asks for it once.
  readonly property bool screensaverActive: ToplevelManager.toplevels.values
    .some(function(t) { return t.appId === "org.omarchy.screensaver" })
  readonly property bool autoHideTiling: settings.autoHideTiling
  onAutoHideTilingChanged: if (autoHideTiling) tilingRefreshTimer.restart()
  Connections {
    target: Hyprland
    enabled: root.autoHideTiling
    function onRawEvent(event) {
      var n = String((event && event.name) || "")
      if (["changefloatingmode", "openwindow", "closewindow", "movewindowv2"].indexOf(n) >= 0)
        tilingRefreshTimer.restart()
    }
  }
  Timer {
    id: tilingRefreshTimer
    interval: 60
    onTriggered: Hyprland.refreshToplevels()
  }

  function surfaceOpenFor(v) { return surfaceNames.indexOf(v) !== -1 }

  // Going straight from one view to another, the new one starts halfway
  // through the old one's fade: both are blurred by then (see Surface), so
  // there's no legible overlap and no empty moment.
  property string previousView: "rest"
  property bool switchingSurface: false

  onViewChanged: {
    if (view === "rest" && updateAnnouncePending) Qt.callLater(announceUpdate)
    surfaceContentReady = false
    switchingSurface = surfaceOpenFor(previousView) && surfaceOpenFor(view)
    previousView = view
    if (switchingSurface) surfaceSwitchEndTimer.restart()
    else surfaceSwitchEndTimer.stop()
    if (surfaceOpenFor(view)) surfaceRevealTimer.restart()
    else surfaceRevealTimer.stop()
  }

  SystemClock { id: clock; precision: SystemClock.Minutes }
  PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

  function showFeedback(message, duration, kind) {
    if (surfaceOpen) return
    if (feedbackKind === "notification" && kind !== "notification" && feedbackTimer.running) return
    feedback = String(message || "")
    feedbackKind = String(kind || "system")
    view = "feedback"
    feedbackTimer.interval = duration || 2800
    feedbackTimer.restart()
  }

  // The HUD shows when the volume or mute state differs from the last one seen
  // on the same output. An output's first reading (at startup, or after
  // switching outputs) is it reporting in, so it's only remembered.
  property var hudSink: null
  property real hudVolume: -1
  property bool hudMuted: false
  function volumeFeedback() {
    var sink = Pipewire.defaultAudioSink
    if (!initialized || !sink || !sink.ready || volume < 0) return
    var changed = hudSink === sink && (volume !== hudVolume || muted !== hudMuted)
    hudSink = sink
    hudVolume = volume
    hudMuted = muted
    if (changed && settings.volumeHud) showFeedback("", 1800, "volume")
  }
  readonly property bool sinkReady: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.ready)
  onVolumeChanged: volumeFeedback()
  onMutedChanged: volumeFeedback()
  onSinkReadyChanged: volumeFeedback()
  Component.onCompleted: {
    initialized = true
    if (autoHideTiling) tilingRefreshTimer.restart()
  }

  // The media service handles the media keys and summons the stock OSD, which
  // is off, so the island watches every player instead: the one that paused,
  // resumed or changed track is the one shown, whichever the service calls
  // active. The pill waits a beat so a skip (title and state changing
  // together) shows once, and a player that is closing (stopping, then
  // vanishing) shows nothing.
  Instantiator {
    model: Mpris.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.mediaFeedback(modelData) }
      function onTrackTitleChanged() { root.mediaFeedback(modelData) }
    }
  }
  function mediaFeedback(player) {
    if (!initialized || !settings.playbackOsd) return
    mediaFeedbackTimer.player = player
    mediaFeedbackTimer.restart()
  }
  Timer {
    id: mediaFeedbackTimer
    interval: 250
    property var player: null
    onTriggered: {
      var players = Mpris.players ? Mpris.players.values : []
      if (!player || players.indexOf(player) < 0 || !root.settings.playbackOsd) return
      var title = String(player.trackTitle || "")
      if (title === "") return
      var artist = String(player.trackArtist || "")
      root.showOsd(JSON.stringify({
        icon: player.isPlaying ? "media-play" : "media-pause",
        message: title + (artist ? " - " + artist : ""),
        duration: "1500"
      }))
    }
  }

  // ---------- Omarchy OSD ----------
  //
  // Payloads from the `osd` IPC target (omarchy-osd and Omarchy's scripts)
  // and from the backlight watch, shown in the island's own pill. Volume and
  // mute payloads are skipped while the sink watcher above covers them.
  property string osdIcon: ""
  property string osdMessage: ""
  property bool osdProgress: false
  property real osdValue: 0
  property real osdMaxValue: 100
  function showOsd(payloadJson) {
    var p
    try { p = JSON.parse(String(payloadJson || "{}")) } catch (e) { return }
    var state = OsdModel.stateForShow(p.icon || "", p.message || "",
      p.value === undefined ? "" : String(p.value),
      p.max === undefined ? "100" : String(p.max),
      p.progressText || "",
      p.duration === undefined ? "" : String(p.duration))
    if (settings.volumeHud && /^(volume|mute)/.test(state.iconKey)) return
    if (!settings.brightnessHud && /^(brightness|display)$/.test(state.iconKey)) return
    osdIcon = state.icon
    osdMessage = state.message
    osdProgress = state.hasProgress
    osdValue = state.value
    osdMaxValue = state.maxValue
    showFeedback("", state.duration > 0 ? state.duration : 1200, "osd")
  }

  readonly property var setup: companionSetup
  CompanionSetup {
    id: companionSetup
    home: root.home
    onFailureBanner: function(row) { root.showBanner(row, 10000) }
  }

  readonly property var updater: islandUpdater
  IslandUpdater {
    id: islandUpdater
    pluginDir: root.setup.pluginDir
    onAvailable: root.announceUpdate()
    onFailed: function(row) { root.showBanner(row, 15000) }
  }
  OsdBridge { id: osdBridge; host: root }
  // The banner waits until nothing else is on the island.
  property bool updateAnnouncePending: false
  function announceUpdate() {
    if (surfaceOpen || view === "feedback") { updateAnnouncePending = true; return }
    updateAnnouncePending = false
    showBanner(updater.bannerRow("A new version is ready. Click to update."), 10000)
  }
  function updateIsland() {
    if (updater.status === "updating") return
    showBanner(updater.bannerRow("Updating Island…"), 120000)
    updater.update()
  }

  Timer {
    id: feedbackTimer
    repeat: false
    onTriggered: {
      if (root.view === "feedback") root.view = "rest"
      root.feedbackKind = ""
    }
  }

  Timer {
    id: surfaceRevealTimer
    interval: root.switchingSurface ? Math.round(root.theme.motionDuration("exit") / 2) : root.theme.contentRevealDelay
    repeat: false
    onTriggered: root.surfaceContentReady = true
  }
  // Once the new view has settled the switch is over, so the view resizing
  // itself afterwards moves as usual.
  Timer {
    id: surfaceSwitchEndTimer
    interval: Math.round(root.theme.motionDuration("exit") / 2) + root.theme.motionDuration("morph")
    repeat: false
    onTriggered: root.switchingSurface = false
  }

  readonly property var notifications: notificationClient
  NotificationClient {
    id: notificationClient
    home: root.home
    historyVisible: root.view === "controls" || root.view === "notifications"
    stacked: root.settings.stackNotifications
    // Keeps the pill in step when the notification is dismissed elsewhere.
    onDismissedElsewhere: if (root.notificationPill) root.dismissFeedback()
    onArrived: function(row) {
      // One with buttons stays long enough to press one.
      if (!root.surfaceOpen) root.showFeedback(String(row.summary || row.app || "Notification"),
        Math.max(root.settings.bannerSeconds * 1000, root.settings.notificationButtons && (row.actions || []).length > 0 ? 8000 : 0), "notification")
    }
  }
  // The island's own banners (setup, updates) in the notification pill.
  function showBanner(row, duration) {
    notifications.last = row
    showFeedback("", duration, "notification")
  }

  function dismissFeedback() {
    feedbackTimer.stop()
    feedbackKind = ""
    view = "rest"
  }
  function dismissPillNotification() {
    var row = notifications.last
    dismissFeedback()
    if (row) notifications.command("dismissKey", row)
  }

  property string menuRoute: "root"

  // A tray app whose own menu the tray view opens straight to (see
  // TrayList), set by a right click on it in the hover capsules.
  property var trayMenuFor: null
  readonly property string hoverMode: settings.hoverStyle ? settings.hoverStyle : settings.hoverCapsules ? "capsules" : settings.hoverExpand ? "expand" : "none"

  function toggleView(name) {
    view = view === name ? "rest" : name
    return view
  }

  IpcHandler {
    target: "huesos.island"
    function audioStatus(): string {
      return JSON.stringify({source: "huesos.island.cava", available: root.audioSpectrum.available,
        playing: root.audioSpectrum.playing, levels: root.audioSpectrum.levels,
        error: root.audioSpectrum.lastError})
    }
    function activityStatus(): string {
      var timer = root.addons.root("timer")
      var notice = root.liveActivities.notice
      return JSON.stringify({view: root.view, mediaPlaying: root.nowPlaying.playing,
        timer: timer ? timer.phase : "disabled", agents: root.agentSessions.map(function(s) {
          return {id: s.id, name: s.name, provider: s.provider, state: s.state, startedAt: s.startedAt, doneAt: s.doneAt}
        }), primary: root.addonPill?.addon.id || (root.mediaPill ? "media" : ""),
        hidden: root.liveActivities.hiddenEntries.length,
        completion: notice && notice.noticeKind !== "asking" ? notice.name : "",
        question: notice?.noticeKind === "asking" ? notice.name : ""})
    }
    function show(name: string): string {
      if (name === "activities") return root.toggleView("controls")
      // A view that isn't there (a disabled addon's) leaves the island alone.
      if (!root.surfaceOpenFor(name)) return root.view
      if (name === "menu") root.menuRoute = "root"
      return root.toggleView(name)
    }
    function openMenu(route: string): string {
      root.menuRoute = String(route || "root")
      root.view = "menu"
      return root.view
    }
    // An addon's pane in Settings (System Stats, Agents, Displays); again, while it's
    // showing, closes Settings (see SettingsView).
    function addonSettings(id: string): string {
      var addon = root.addons.root(id)
      var pages = addon ? addon.settingsPages || [] : []
      if (!pages.length) return root.view
      // Already open: SettingsView takes the page itself (or closes).
      if (root.view === "settings") root.settingsPage = pages[0].title
      else root.openSettings(pages[0].title)
      return root.view
    }
    function toggle(): string { return root.toggleView("controls") }
    function themes(): string { return root.toggleView("themes") }
    function wallpapers(): string { return root.toggleView("wallpapers") }
    function apps(): string { return root.toggleView("apps") }
    function power(): string { return root.toggleView("power") }
    // Ask AI's, while that addon is enabled (see addons/ask).
    function ask(question: string): string {
      var ask = root.addons.root("ask")
      if (ask) ask.ask(question)
      return root.view
    }
    // From services/update.sh, when the update couldn't go ahead.
    function updateFailed(reason: string): string {
      root.updater.fail(reason)
      return "shown"
    }
    function companionStatus(): string { return root.setup.status }
    function installCompanion(): string {
      root.setup.install()
      return "installing"
    }
    function showHistory(): string {
      root.view = "controls"
      return root.view
    }
    function close(): string {
      root.view = "rest"
      return "rest"
    }
  }

  // An open view closes on a click outside the island (see outsideArea),
  // armed a moment after it opens so the click that opened it can't count.
  property bool outsideClickArmed: false
  property bool manuallyHidden: false
  readonly property bool closesOnOutsideClick: surfaceOpen && outsideClickArmed
  Timer {
    interval: 120
    running: root.surfaceOpen && !root.outsideClickArmed
    onTriggered: root.outsideClickArmed = true
  }
  onSurfaceOpenChanged: if (!surfaceOpen) outsideClickArmed = false
  component MonitorState: QtObject {
    required property var screen
    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property var activeWorkspace: monitor?.activeWorkspace || Hyprland.focusedWorkspace
    readonly property bool autoHideCondition: root.screensaverActive || fullscreen || tiled

    readonly property bool fullscreen: {
      if (!root.settings.autoHideFullscreen || !activeWorkspace) return false
      if (activeWorkspace.hasFullscreen) return true
      return activeWorkspace.toplevels.values.some(toplevel => toplevel.wayland?.fullscreen)
    }
    readonly property bool tiled: {
      if (!root.settings.autoHideTiling || !activeWorkspace) return false
      return activeWorkspace.toplevels.values.some(toplevel => {
        var ipc = toplevel.lastIpcObject
        return ipc && ipc.mapped !== false && !ipc.hidden && !ipc.floating
      })
    }
  }

  // Move the same scene between outputs. The resting layer covers just the
  // strip with the pills, capsules and banners. Expand it for outside clicks
  // and tall notifications, and keep it expanded until the collapse settles.
  PanelWindow {
    id: window
    screen: root.outputScreen
    visible: root.outputScreen !== null
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true; right: true }
    implicitHeight: expanded ? root.screenHeight : 96
    WlrLayershell.namespace: "omarchy-island"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: island.activeSurface && island.activeSurface.wantsKeyboard
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MonitorState { id: monitorState; screen: window.screen }
    readonly property Item hoverCapsules: capsulesLoader.item

    property bool expanded: false
    readonly property bool needsFullHeight: root.surfaceOpen || root.notificationPill
    onNeedsFullHeightChanged: {
      if (needsFullHeight) {
        compactTimer.stop()
        expanded = true
      } else {
        compactTimer.restart()
      }
    }
    Timer {
      id: compactTimer
      // Reopening a panel in quick succession can reuse the Wayland buffers.
      interval: Math.max(2400, root.theme.motionDuration("morph") + root.theme.morphLag)
      onTriggered: window.expanded = false
    }

    property bool edgeRevealed: false
    onScreenChanged: {
      edgeRevealed = false
      edgeLeaveTimer.stop()
    }
    readonly property bool manuallyHiddenAtRest: root.manuallyHidden && root.view === "rest"
    readonly property bool edgeClickAllowed: visible && !root.screensaverActive && root.view === "rest"
    readonly property bool clickRevealArmed: edgeClickAllowed && root.manuallyHidden

    MotionSpring {
      id: manualMotion
      theme: root.theme
      pace: root.manuallyHidden ? "collapse" : "expressive"
      bounce: root.manuallyHidden ? 0 : 0.27
      target: window.manuallyHiddenAtRest ? 100 : 0
    }

    component EdgeClick: MouseArea {
      required property bool revealing
      anchors.fill: parent
      z: 10
      acceptedButtons: Qt.RightButton

      onClicked: {
        if (revealing && window.isEffectivelyHidden) {
          window.edgeRevealed = true
          edgeLeaveTimer.restart()
        }
        if (!revealing) {
          island.glanceActive = false
          island.capsulesActive = false
          capsulesEnterTimer.stop()
        }
        root.manuallyHidden = !revealing
      }
    }

    Timer {
      id: edgeLeaveTimer
      interval: 400
      onTriggered: if (!revealHover.hovered && !bridgeHover.hovered && !islandPointerHover.hovered)
        window.edgeRevealed = false
    }

    readonly property bool isEffectivelyHidden: (root.barHidden || monitorState.autoHideCondition)
      && (root.view === "rest" || root.screensaverActive)
    onIsEffectivelyHiddenChanged: if (!isEffectivelyHidden) {
      edgeRevealed = false
      edgeLeaveTimer.stop()
    }

    // Hover at the top edge can bring a hidden island back.
    readonly property bool revealArmed: isEffectivelyHidden && !root.screensaverActive && !root.manuallyHidden

    readonly property bool autoHidden: root.screensaverActive || (isEffectivelyHidden && !edgeRevealed && !root.manuallyHidden)
    readonly property bool islandHidden: manuallyHiddenAtRest || autoHidden

    // Only the island takes input, except while a view is open: then the
    // whole screen does, so outsideArea can close it. While the island can
    // auto-hide, revealStrip takes hover input at the edge to slide it back.
    mask: Region {
      item: root.closesOnOutsideClick ? outsideArea : window.islandHidden || agentBanner.shown ? null : island
      regions: [
        Region { item: agentBanner.shown ? agentBanner : null },
        Region { item: window.clickRevealArmed ? clickRevealStrip : null },
        Region { item: window.revealArmed ? revealStrip : null },
        Region { item: window.revealArmed && window.edgeRevealed ? revealBridge : null },
        Region { item: window.hoverCapsules?.shown ? window.hoverCapsules.leftGroup : null },
        Region { item: window.hoverCapsules?.shown ? window.hoverCapsules.rightGroup : null }
      ]
    }
    MouseArea {
      id: outsideArea
      anchors.fill: parent
      enabled: root.closesOnOutsideClick
      acceptedButtons: Qt.AllButtons
      // Clicks on the island's blank space fall through to here too.
      onPressed: function(mouse) {
        if (!island.contains(mapToItem(island, mouse.x, mouse.y))) root.view = "rest"
      }
    }

    Item {
      id: clickRevealStrip
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.max(100, Math.min(280, island.targetWidth))
      height: 6
      visible: window.clickRevealArmed
      EdgeClick { revealing: true; enabled: window.clickRevealArmed }
    }

    Item {
      id: revealStrip
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      // The whole top edge can summon the hidden island.
      width: parent.width
      height: window.revealArmed ? 4 : 0
      visible: height > 0

      HoverHandler {
        id: revealHover
        onHoveredChanged: {
          if (hovered) {
            edgeLeaveTimer.stop()
            window.edgeRevealed = true
          } else {
            if (!bridgeHover.hovered && !islandPointerHover.hovered) edgeLeaveTimer.restart()
          }
        }
      }
    }

    // Keep the gap between the edge and the emerging pill interactive.
    // Its bounds stay steady while the visible dot stretches and grows.
    Item {
      id: revealBridge
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.max(island.targetWidth + 80, 260)
      height: window.revealArmed && window.edgeRevealed
        ? (root.settings.notch ? 0 : 8) + island.targetHeight + 12 : 0
      visible: height > 0
      HoverHandler {
        id: bridgeHover
        onHoveredChanged: {
          if (hovered) edgeLeaveTimer.stop()
          else if (!revealHover.hovered && !islandPointerHover.hovered) edgeLeaveTimer.restart()
        }
      }
    }

    // While a view is open the island floats over the windows: a soft,
    // wide shadow for depth plus a tight, darker one where it meets them
    // (the resting pill stays flat, like hardware).
    // Analytic shadows avoid resizing an offscreen blur texture on
    // every frame of the opening spring.
    IslandShadow { shape: island; offset.y: 2; blur: 8; spread: -1; color: Qt.rgba(0, 0, 0, 0.4) }
    IslandShadow { shape: island; offset.y: 14; blur: 48; spread: -4; color: Qt.rgba(0, 0, 0, 0.6) }

    // Hovering the resting island splits the bar's items into capsules
    // beside it (see HoverCapsules).
    Loader {
      id: capsulesLoader
      active: root.hoverMode === "capsules"
      anchors.fill: parent
      // Under the island, so the capsules can start tucked beneath it.
      z: -1
      sourceComponent: HoverCapsules {
        host: root
        island: island
        shown: island.capsulesShown && !window.islandHidden && !agentBanner.shown
      }
    }

    NotchEar { shape: island }
    NotchEar { shape: island; mirrored: true }

    Rectangle {
      id: island
      x: (parent.width - width) / 2
      AutoHideMotion {
        id: hideMotion
        theme: root.theme
        hidden: window.autoHidden
        edgeProgress: manualMotion.value / 100
        expandedWidth: Math.max(40, widthSpring.value)
        expandedHeight: Math.max(28, heightSpring.value)
        restY: root.settings.notch ? 0 : 8
      }
      y: hideMotion.renderY
      readonly property real hideProgress: hideMotion.collapseProgress
      readonly property Item activeSurface: views.surfaceFor(root.view)
      readonly property Item activePill: pills.active
      readonly property bool glanceHovered: clockHover.hovered || islandPointerHover.hovered
      property bool glanceActive: false
      readonly property Item glanceBar: glanceLoader.item
      readonly property bool hasGlanceItems: glanceBar?.hasItems ?? false
      Timer {
        id: glanceLeaveTimer
        interval: 180
        onTriggered: island.glanceActive = false
      }
      onGlanceHoveredChanged: {
        if (glanceHovered) {
          glanceLeaveTimer.stop()
          if (root.hoverMode === "expand" && island.hasGlanceItems && root.restingFree && !root.downloadPill && !island.hasNonMediaActivePill) island.glanceActive = true
        } else {
          glanceLeaveTimer.restart()
        }
      }

      readonly property bool capsulesHovered: clockHover.hovered || islandPointerHover.hovered || (window.hoverCapsules?.hovered ?? false)
      property bool capsulesActive: false
      Timer {
        id: capsulesLeaveTimer
        interval: 180
        onTriggered: island.capsulesActive = false
      }
      // A moment's pause before showing, like macOS's hover reveals, so
      // passing over the island doesn't flash the capsules.
      Timer {
        id: capsulesEnterTimer
        interval: root.theme.scaled(80)
        onTriggered: if (root.hoverMode === "capsules" && root.resting) island.capsulesActive = true
      }
      onCapsulesHoveredChanged: {
        if (capsulesHovered) {
          capsulesLeaveTimer.stop()
          if (!island.capsulesActive) capsulesEnterTimer.restart()
        } else {
          capsulesEnterTimer.stop()
          capsulesLeaveTimer.restart()
        }
      }

      Connections {
        target: root
        function onViewChanged() {
          if (root.view !== "rest" && !(root.volumePill && island.capsulesActive)) {
            island.glanceActive = false
            island.capsulesActive = false
            glanceLeaveTimer.stop()
            capsulesLeaveTimer.stop()
            capsulesEnterTimer.stop()
          }
        }
      }
      readonly property bool hasNonMediaActivePill: pills.active !== null && pills.active !== mediaPillItem
      readonly property bool isGlanceExpanded: island.glanceActive && (root.hoverMode === "expand") && island.hasGlanceItems && root.restingFree && !root.downloadPill && !island.hasNonMediaActivePill
      readonly property bool capsulesShown: island.capsulesActive && (root.hoverMode === "capsules") && (root.resting || root.volumePill)
      // How much wider than a bare time the chosen clock format is; the
      // resting pill and the pills that keep the clock in the middle grow by it.
      readonly property real clockExtra: Math.max(0, Math.ceil(clockLabel.advanceWidth || clockMetrics.advanceWidth) + 56 - 100)
      readonly property real baseGlanceWidth: root.settings.notch ? 420 : 440
      readonly property real glanceWidth: glanceBar && glanceBar.neededWidth > 0
        ? Math.min(baseGlanceWidth + clockExtra, Math.max(180, glanceBar.neededWidth))
        : baseGlanceWidth + clockExtra
      readonly property real surfaceWidth: activeSurface && (activeSurface.view || activeSurface.fixedWidth > 0)
        ? activeSurface.islandWidth : widthSpring.target
      readonly property real surfaceHeight: activeSurface?.view ? activeSurface.islandHeight : heightSpring.target
      readonly property real targetWidth: activeSurface ? surfaceWidth
        : island.isGlanceExpanded ? island.glanceWidth
        : activePill ? activePill.pillWidth + (activePill.keepsClock ? clockExtra : 0)
        : root.view === "feedback" ? 280
        : root.setup.needsSetup ? (root.setup.warning.length > 24 ? 320 : 250)
        : 100 + clockExtra
      readonly property real targetHeight: activeSurface ? surfaceHeight
        : island.isGlanceExpanded ? (root.mediaPill ? root.pillHeight : root.clockHeight)
        : activePill ? activePill.pillHeight
        : root.view === "rest" ? root.clockHeight : 52
      readonly property real targetRadius: activeSurface && activeSurface.cornerRadius > 0 ? activeSurface.cornerRadius
        : activePill && activePill.pillRadius > 0 ? activePill.pillRadius
        : root.surfaceOpen ? 30 : 38
      readonly property real radiusCap: radiusSpring.value
      radius: Math.min(width / 2, height / 2, root.settings.notch && !root.surfaceOpen ? Math.min(radiusCap, 16) : radiusCap)
      topLeftRadius: root.settings.notch ? radius * hideMotion.collapseProgress : radius
      topRightRadius: root.settings.notch ? radius * hideMotion.collapseProgress : radius
      readonly property bool lifted: root.view === "rest" && clockHover.hovered && !root.settings.notch && !island.isGlanceExpanded && !island.capsulesShown
      // Lifts a touch under the pointer and squishes while pressed, then
      // springs back past its size on release, like the iPhone's island.
      // The springs run in hundredths, as they settle to a tenth of a unit.
      readonly property bool squished: !root.settings.notch && (islandTap.pressed || squishHold.running)
      Timer { id: squishHold; interval: root.theme.motionDuration("press") }
      MotionSpring { id: liftSpring; theme: root.theme; pace: "quick"; target: island.lifted ? 100 : 0 }
      MotionSpring {
        id: pressSpring
        theme: root.theme
        pace: island.squished ? "press" : "standard"
        bounce: island.squished ? 0 : 0.35
        target: island.squished ? 100 : 0
      }
      scale: root.settings.notch ? 1.0 : (1 + liftSpring.value * 0.00018 - pressSpring.value * 0.0003)
      // With the notch the island hangs from the top edge, so it scales from there.
      transformOrigin: root.settings.notch ? Item.Top : Item.Center
      EdgeClick {
        revealing: false
        enabled: window.edgeClickAllowed && !window.islandHidden
      }
      HoverHandler { id: clockHover; enabled: root.view === "rest" }
      HoverHandler {
        id: islandPointerHover
        onHoveredChanged: {
          if (hovered) {
            edgeLeaveTimer.stop()
          } else {
            if (window.edgeRevealed && !revealHover.hovered && !bridgeHover.hovered) edgeLeaveTimer.restart()
          }
        }
      }
      // The black itself is the squircle below; the Rectangle only keeps
      // the radius and clipping the pills and views rely on.
      color: "transparent"
      clip: true
      opacity: agentBanner.visible && !root.surfaceOpen ? 1 - agentBanner.opacity : 1
      readonly property var cornerRadii: ({ topLeft: topLeftRadius, topRight: topRightRadius, bottomLeft: radius, bottomRight: radius })
      readonly property string outline: Squircle.path(width, height, cornerRadii, 0.6)
      // The same outline inset half a pixel, so a 1px edge stroke lands
      // inside the shape. Only built while the edge shows, so a resting
      // pill's morphs redraw one outline, not two.
      readonly property string edgeOutline: !islandEdge.visible ? ""
        : root.settings.notch && hideMotion.collapseProgress < 0.001 ? Squircle.notchPath(width - 1, height - 1, Math.max(0, radius - 0.5), 10, 0.6)
        : Squircle.path(width - 1, height - 1, ({
            topLeft: Math.max(0, topLeftRadius - 0.5), topRight: Math.max(0, topRightRadius - 0.5),
            bottomLeft: Math.max(0, radius - 0.5), bottomRight: Math.max(0, radius - 0.5) }), 0.6)
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: -1
          fillColor: root.theme.background
          Behavior on fillColor { MotionColorAnimation { theme: root.theme } }
          PathSvg { path: island.outline }
        }
      }
      // Width, height and corners ride springs, so a change of mind
      // mid-morph keeps its momentum. Growing, the width leads and the
      // height follows a beat later, each swinging a touch past its size
      // as the Dynamic Island does; shrinking, the height goes first. A
      // pill shrinking back (an activity ending) dips a little under its
      // size before it settles, a shrug; closing a view lands flat.
      // Going from one view to a smaller one is a way back, as quick as a close.
      property bool shrinkingToView: false
      readonly property string morphPace: root.surfaceOpen && !shrinkingToView ? "morph" : "collapse"
      MotionSpring { id: widthSpring; theme: root.theme; pace: island.morphPace }
      MotionSpring { id: heightSpring; theme: root.theme; pace: island.morphPace }
      MotionSpring { id: radiusSpring; theme: root.theme; pace: island.morphPace; target: island.targetRadius }
      Timer { id: widthLag; interval: root.theme.morphLag; onTriggered: widthSpring.target = island.targetWidth }
      Timer { id: heightLag; interval: root.theme.morphLag; onTriggered: heightSpring.target = island.targetHeight }
      // A view settles its height over a few frames as it lays out; a
      // lag already counting keeps counting and lands on the latest
      // size, so the height still trails the width by one beat.
      readonly property bool shrugs: !root.surfaceOpen && heightSpring.value <= 120
      onTargetWidthChanged: Qt.callLater(retarget)
      onTargetHeightChanged: Qt.callLater(retarget)
      function retarget() {
        // Combine size changes from the view's layout into one retarget and
        // keep the same spring response for the rest of that morph.
        var shrinkingWidth = targetWidth < widthSpring.value
        var growingHeight = targetHeight > heightSpring.value
        shrinkingToView = root.switchingSurface
          && (targetHeight < heightSpring.value - 1 || targetWidth < widthSpring.value - 1)
        if (targetWidth !== widthSpring.target || widthLag.running) {
          widthSpring.bounce = !shrinkingWidth && !root.switchingSurface ? root.theme.morphBounce : shrugs ? root.theme.shrugBounce : 0
          if (shrinkingWidth) {
            if (!widthLag.running) widthLag.start()
          } else {
            widthLag.stop()
            widthSpring.target = targetWidth
          }
        }
        if (targetHeight !== heightSpring.target || heightLag.running) {
          heightSpring.bounce = growingHeight && !root.switchingSurface ? root.theme.morphBounce : shrugs ? root.theme.shrugBounce : 0
          if (growingHeight) {
            if (!heightLag.running) heightLag.start()
          } else {
            heightLag.stop()
            heightSpring.target = targetHeight
          }
        }
      }
      Component.onCompleted: {
        widthSpring.target = widthSpring.value = targetWidth
        heightSpring.target = heightSpring.value = targetHeight
      }
      width: hideMotion.renderWidth
      height: hideMotion.renderHeight

      MouseArea {
        id: islandTap
        anchors.fill: parent
        enabled: !window.islandHidden && !agentBanner.shown && (root.view === "rest" || root.view === "feedback")
        onPressed: squishHold.restart()
        onClicked: function(mouse) {
          feedbackTimer.stop()
          if (island.activePill) island.activePill.clicked(mouse)
          else if (root.view === "rest" && root.setup.needsSetup) root.setup.pillClicked()
          else root.view = "controls"
        }
      }

      // Fade the content before the silhouette becomes a dot.
      Item {
        anchors.fill: parent
        opacity: hideMotion.contentOpacity
        enabled: !window.islandHidden

        // The live activities (see IslandPill); at most one is shown at a time.
        Item {
          id: pills
          anchors.fill: parent
          readonly property Item active: {
            for (var i = 0; i < children.length; i++) if (children[i].shown) return children[i]
            return null
          }
          NotificationPill { host: root; shape: island; anchors.fill: parent }
          VolumeSlider { host: root; anchors.fill: parent }
          OsdPill { host: root; anchors.fill: parent }
          ClipboardPill { host: root; anchors.fill: parent }
          DevicePill { host: root; anchors.fill: parent }
          WorkspacePill { host: root; anchors.fill: parent }
          AddonPills { host: root; anchors.fill: parent }
          RecordingPill { host: root; anchors.fill: parent }
          MediaPill { id: mediaPillItem; host: root; shape: island; anchors.fill: parent }
          DownloadPill { host: root; anchors.fill: parent }
        }

        Loader {
          id: glanceLoader
          active: root.hoverMode === "expand"
          anchors.fill: parent
          sourceComponent: GlanceBar {
            host: root
            shown: island.isGlanceExpanded
            clockWidth: Math.max(clockLabel.width, clockLabel.advanceWidth || clockMetrics.advanceWidth)
          }
        }

        IslandLabel { id: clockLabel; host: root; shape: island; pill: island.activePill; anchors.centerIn: parent }
        TextMetrics { id: clockMetrics; font: clockLabel.font; text: Locale.I18n.tr(root.clockStacked ? root.clockWidestText : root.clockText) }

        Views { id: views; host: root; anchors.fill: parent }
      }
    }
    AgentActivityBanner {
      id: agentBanner
      host: root
      session: !root.screensaverActive ? root.liveActivities.notice : null
    }

    // Keep a faint light edge even at rest, so the black pill remains
    // visible against a black wallpaper; brighten it while interacting.
    Item {
      id: islandEdge
      x: island.x
      y: island.y
      width: island.width
      height: island.height
      scale: island.scale
      transformOrigin: island.transformOrigin
      readonly property bool prominent: root.surfaceOpen || root.view === "feedback"
      opacity: (prominent ? 1 : (island.lifted || island.isGlanceExpanded) ? 0.9 : 0.75) * island.opacity
      visible: opacity > 0.01
      Behavior on opacity { MotionAnimation { theme: root.theme; pace: islandEdge.prominent || island.lifted || island.isGlanceExpanded ? "morph" : "exit"; curve: "fade" } }
      Shape {
        anchors.fill: parent
        anchors.margins: 0.5
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: 1
          strokeColor: root.theme.outlineColor
          fillColor: "transparent"
          PathSvg { path: island.edgeOutline }
        }
      }
    }
  }

  // Independent exclusive strips keep tiling stable when focus moves. They
  // contain no copy of the Island scene.
  Variants {
    model: Quickshell.screens
    delegate: PanelWindow {
      id: reserve
      required property var modelData
      screen: modelData
      MonitorState { id: reserveState; screen: reserve.screen }
      visible: (!root.outputPinned || screen === root.outputScreen) && root.settings.reserveSpace
        && !root.barHidden && !reserveState.autoHideCondition && !root.manuallyHidden
      color: "transparent"
      anchors { top: true; left: true; right: true }
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: (root.settings.notch ? 0 : 8) + root.clockHeight
      implicitHeight: exclusiveZone
      mask: Region {}
      WlrLayershell.namespace: "omarchy-island-reserve"
      WlrLayershell.layer: WlrLayer.Top
    }
  }

  // A shadow under the island, there while a view is open.
  component IslandShadow: RectangularShadow {
    required property Item shape
    x: shape.x
    y: shape.y
    width: shape.width
    height: shape.height
    radius: shape.radius
    scale: shape.scale
    transformOrigin: shape.transformOrigin
    opacity: root.surfaceOpen ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { MotionAnimation { theme: root.theme; pace: root.surfaceOpen ? "morph" : "exit"; curve: "fade" } }
  }

  // With the notch, a concave corner either side of the island where it
  // meets the top edge; `mirrored` is the right one.
  component NotchEar: Shape {
    id: ear
    required property Item shape
    property bool mirrored: false
    readonly property real r: 10
    visible: root.settings.notch && shape.y > -r && opacity > 0.01
    opacity: 1 - shape.hideProgress
    x: mirrored ? shape.x + shape.width - 0.5 : shape.x - r
    y: shape.y
    width: r + 0.5
    height: r
    property real edgeOpacity: (root.surfaceOpen || root.view === "feedback") ? 1 : (shape.lifted || shape.isGlanceExpanded) ? 0.9 : 0.75
    Behavior on edgeOpacity { MotionAnimation { theme: root.theme; pace: root.surfaceOpen || root.view === "feedback" || shape.isGlanceExpanded ? "morph" : "exit"; curve: "fade" } }
    // Drawn as the island is, so the two edges antialias alike where they meet.
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      fillColor: root.theme.background
      PathSvg {
        readonly property real r: ear.r
        path: ear.mirrored
          ? "M 0 0 L 0 " + r + " L 0.5 " + r + " A " + r + " " + r + " 0 0 1 " + (r + 0.5) + " 0 Z"
          : "M " + (r + 0.5) + " 0 L " + (r + 0.5) + " " + r + " L " + r + " " + r + " A " + r + " " + r + " 0 0 0 0 0 Z"
      }
    }
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      opacity: ear.edgeOpacity
      visible: opacity > 0.01
      ShapePath {
        strokeWidth: 1
        strokeColor: root.theme.outlineColor
        fillColor: "transparent"
        PathSvg {
          readonly property real r: ear.r
          path: ear.mirrored
            ? "M 0.5 " + r + " A " + r + " " + r + " 0 0 1 " + (r + 0.5) + " 0"
            : "M " + r + " " + r + " A " + r + " " + r + " 0 0 0 0 0"
        }
      }
    }
  }
}
