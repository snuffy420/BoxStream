' Box://Stream scene: start-up, top bar, view switching and remote keys.
' Each area of the app lives in its own file (HomeView, BrowseViews,
' DetailsView, SettingsView, Player, Music); Library.brs holds the data.

sub init()
    m.top.backgroundColor = "0x06080DFF"
    ' The scene can't take focus back from a list inside it, so screens without
    ' a focused list focus this empty node; its keys reach onKeyEvent here.
    m.keySink = m.top.FindNode("keySink")
    m.top.backgroundUri = ""
    m.t = theme()
    m.global.AddFields({serverOrigin: "", serverAuth: "", serverAuths: {}})
    ' HEVC depends on the video chip, not on 4K: ask this Roku.
    m.canHevc = hevcSupported()

    m.backdrop = m.top.FindNode("backdrop")
    m.backdropFade = m.top.FindNode("backdropFade")
    m.backdropIn = m.top.FindNode("backdropIn")
    m.backdropFadePath = m.top.FindNode("backdropFadePath")
    m.tabsGroup = m.top.FindNode("tabs")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.clockLabel = m.top.FindNode("clockLabel")
    m.menu = m.top.FindNode("menu")
    m.keyboard = m.top.FindNode("keyboard")
    m.toast = m.top.FindNode("toast")
    m.toastLabel = m.top.FindNode("toastLabel")
    m.toastBack = m.top.FindNode("toastBack")
    m.topBar = m.top.FindNode("topBar")

    m.statusLabel.font = makeFont("regular", 22)
    m.clockLabel.font = makeFont("bold", 30)
    m.toastLabel.font = makeFont("bold", 24)

    m.views = {
        home: m.top.FindNode("homeView")
        grid: m.top.FindNode("gridView")
        search: m.top.FindNode("searchView")
        folders: m.top.FindNode("foldersView")
        settings: m.top.FindNode("settingsView")
        details: m.top.FindNode("detailsView")
    }
    m.tabs = [
        {id: "home", label: "Home", icon: "home"}
        {id: "movies", label: "Movies", icon: "movie"}
        {id: "shows", label: "TV Shows", icon: "tv"}
        {id: "music", label: "Music", icon: "music"}
        {id: "folders", label: "Folders", icon: "folder"}
        {id: "search", label: "Search", icon: "search"}
        {id: "settings", label: "Settings", icon: "settings"}
    ]
    m.tabIndex = 0
    m.currentTab = "home"
    m.area = "tabs"
    m.view = ""
    m.history = []
    buildTabs()

    m.clockTimer = m.top.FindNode("clockTimer")
    m.clockTimer.ObserveField("fire", "onClock")
    m.clockTimer.control = "start"
    onClock()
    m.toastTimer = m.top.FindNode("toastTimer")
    m.toastTimer.ObserveField("fire", "hideToast")
    m.focusTimer = m.top.FindNode("focusTimer")
    m.focusTimer.ObserveField("fire", "onFocusTimer")

    m.menu.ObserveField("chosen", "onMenuChosen")
    m.menu.ObserveField("closed", "onMenuClosed")
    m.keyboard.ObserveField("done", "onKeyboardDone")
    m.keyboard.ObserveField("cancel", "onKeyboardCancel")

    initLibrary()
    initHome()
    initBrowse()
    initDetails()
    initSettings()
    initPlayer()
    initMusic()

    m.task = CreateObject("roSGNode", "LibraryTask")
    m.task.ObserveField("status", "onTaskStatus")
    m.task.ObserveField("library", "onTaskLibrary")
    m.task.ObserveField("metaBatch", "onTaskMeta")
    m.task.ObserveField("listing", "onTaskListing")
    m.task.ObserveField("testResult", "onTaskTest")
    m.task.ObserveField("candidates", "onTaskCandidates")
    m.task.ObserveField("probeBatch", "onTaskProbes")
    m.task.ObserveField("nfoText", "onTaskNfo")
    m.task.control = "run"

    m.settings = loadSettings()
    m.sourceLabel = m.top.FindNode("sourceLabel")
    m.sourceLabel.font = makeFont("bold", 20)
    configureServer()
    showTab("home")
    focusTabs()
    sendCommand({action: "load"})
end sub

' Commands to the library worker go in a numbered queue: rapid sets of one
' field merge on the way to a task thread, so each set carries every recent
' command and the worker runs the ones it hasn't seen.
sub sendCommand(command as Object)
    if m.cmdQueue = invalid
        m.cmdQueue = []
        m.cmdSeq = 0
    end if
    m.cmdSeq = m.cmdSeq + 1
    command.seq = m.cmdSeq
    m.cmdQueue.Push(command)
    while m.cmdQueue.Count() > 20
        m.cmdQueue.Shift()
    end while
    m.task.commands = m.cmdQueue
end sub

' Asks the Roku whether it decodes HEVC (H.265). The answer depends on the
' profile asked about, so 1080p (level 4.1) is checked in 8-bit and 10-bit.
function hevcSupported() as Boolean
    info = CreateObject("roDeviceInfo")
    ' Its own variable: the audio checks below reuse "ok", and once overwrote
    ' this answer (HEVC showed as supported on a Roku that can't play it).
    hevc = false
    for each query in [{Codec: "hevc", Profile: "main", Level: "4.1"}, {Codec: "hevc", Profile: "main 10", Level: "4.1"}, {Codec: "hevc", Profile: "main", Level: "5.1"}, {Codec: "hevc", Profile: "main 10", Level: "5.1"}, {Codec: "hevc"}]
        result = info.CanDecodeVideo(query)
        answer = false
        if result <> invalid then answer = result.Result = true
        if answer then hevc = true
    end for
    m.canHevc = hevc
    m.can4k = canDecode4k()
    ' Decoded here, or passed on to a soundbar / receiver that can (Roku lists
    ' passthrough formats in GetAudioDecodeInfo when one is connected).
    m.canDts = false
    dts = info.CanDecodeAudio({Codec: "dts"})
    if dts <> invalid then m.canDts = dts.Result = true
    m.canTrueHd = false
    truehd = info.CanDecodeAudio({Codec: "truehd"})
    if truehd <> invalid then m.canTrueHd = truehd.Result = true
    for each codec in ["dts", "truehd"]
        pass = info.CanDecodeAudio({Codec: codec, PassThru: 1})
        ok = false
        if pass <> invalid then ok = pass.Result = true
        if ok and codec = "dts" then m.canDts = true
        if ok and codec = "truehd" then m.canTrueHd = true
    end for
    ' Highest FLAC sample rate this Roku says it plays at the right speed.
    ' (Roku says yes to 96 kHz, but this TV plays it slowed down: tested.)
    m.maxAudioRate = 48000
    ' What this Roku plays, for Settings > This Roku can play.
    m.supportLines = []
    ' The same as rows for the full page (Settings > This Roku can play).
    m.supportItems = [{group: "video", name: "H.264 (AVC) up to 1080p", ok: true}, {group: "video", name: "H.264 in 4K", ok: m.can4k = true}, {group: "video", name: "HEVC (H.265)", ok: m.canHevc = true}]
    m.supportLines.Push("Video  H.264 (AVC) up to 1080p:  yes")
    m.supportLines.Push("H.264 4K:  " + yesNoWord(m.can4k = true))
    m.supportLines.Push("HEVC (H.265):  " + yesNoWord(m.canHevc = true))
    for each v in [{c: "vp9", n: "VP9"}, {c: "av1", n: "AV1"}, {c: "mpeg4 part 2", n: "MPEG-4 (XviD/DivX)"}]
        r = info.CanDecodeVideo({Codec: v.c})
        m.supportLines.Push(v.n + ":  " + yesNoWord(r <> invalid and r.Result = true))
        m.supportItems.Push({group: "video", name: v.n, ok: r <> invalid and r.Result = true})
    end for
    for each a in [{c: "aac", n: "AAC"}, {c: "ac3", n: "Dolby Digital (AC3)"}, {c: "eac3", n: "Dolby Digital Plus (E-AC3)"}, {c: "dts", n: "DTS"}, {c: "truehd", n: "Dolby TrueHD"}, {c: "flac", n: "FLAC"}, {c: "lpcm", n: "PCM"}, {c: "mp3", n: "MP3"}, {c: "opus", n: "Opus"}, {c: "vorbis", n: "Vorbis"}]
        ok = false
        r = info.CanDecodeAudio({Codec: a.c})
        if r <> invalid and r.Result = true then ok = true
        r = info.CanDecodeAudio({Codec: a.c, PassThru: 1})
        if r <> invalid and r.Result = true then ok = true
        if a.c = "dts" then ok = m.canDts = true
        if a.c = "truehd" then ok = m.canTrueHd = true
        m.supportItems.Push({group: "audio", name: a.n, ok: ok, helper: (a.c = "dts" or a.c = "truehd") and not ok})
        if a.c = "flac" then m.supportItems.Push({group: "audio", name: "FLAC above 48 kHz", ok: false, helper: true})
        if a.c = "aac" then a.n = "Audio  AAC"
        m.supportLines.Push(a.n + ":  " + yesNoWord(ok))
    end for
    outputs = info.GetAudioDecodeInfo()
    if type(outputs) = "roAssociativeArray"
        for each name in outputs
            upper = UCase(name)
            if Left(upper, 3) = "DTS" then m.canDts = true
            if Instr(1, upper, "TRUEHD") > 0 or Instr(1, upper, "MLP") > 0 then m.canTrueHd = true
        end for
    end if
    return hevc
end function

' 4K (2160p) H.264 needs a decoder that handles level 5.1; 1080p TVs
' and players usually stop at 4.2.
function canDecode4k() as Boolean
    result = CreateObject("roDeviceInfo").CanDecodeVideo({Codec: "mpeg4 avc", Profile: "high", Level: "5.1"})
    ok = false
    if result <> invalid then ok = result.Result = true
    return ok
end function

' ---- Settings (registry) -----------------------------------------------------

function loadSettings() as Object
    section = CreateObject("roRegistrySection", "boxstream")
    settings = {sources: [], active: "", sort: "title", options: {}}
    if section.Exists("sources")
        list = ParseJson(section.Read("sources"))
        if type(list) = "roArray" then settings.sources = list
    end if
    if section.Exists("active") then settings.active = section.Read("active")
    if section.Exists("sort") then settings.sort = section.Read("sort")
    settings.musicView = "all"
    settings.helper = {url: "", code: ""}
    if section.Exists("helper")
        h = ParseJson(section.Read("helper"))
        if type(h) = "roAssociativeArray" then settings.helper = h
    end if
    if section.Exists("musicView") then settings.musicView = section.Read("musicView")
    if section.Exists("options")
        options = ParseJson(section.Read("options"))
        if type(options) = "roAssociativeArray" then settings.options = options
    end if
    return settings
end function

sub saveSettings()
    section = CreateObject("roRegistrySection", "boxstream")
    section.Write("sources", FormatJson(m.settings.sources))
    section.Write("active", m.settings.active)
    section.Write("sort", m.settings.sort)
    if m.settings.musicView <> invalid then section.Write("musicView", m.settings.musicView)
    if m.settings.helper <> invalid then section.Write("helper", FormatJson(m.settings.helper))
    section.Write("options", FormatJson(m.settings.options))
    section.Flush()
end sub

' Display options (Settings > Display), each with its default.
function optionOn(name as String) as Boolean
    defaults = {stereoAudio: false, gapless: true, avoidUnplayableAudio: true, episodesLeft: false, tagRes: true, tagCodec: true, tagSource: true, tagHdr: true, tagRemux: true, tagHc: true, noMatch: true, hideUnplayable: false}
    value = m.settings.options[name]
    if value = invalid then return defaults[name] = true
    return value = true
end function

' The source (seedbox) the library comes from, or an empty one.
function activeSource() as Object
    for each source in m.settings.sources
        if source.id = m.settings.active then return source
    end for
    if m.settings.sources.Count() > 0 then return m.settings.sources[0]
    return {id: "", label: "", url: "", user: "", pass: ""}
end function

function findSource(id as String) as Dynamic
    for each source in m.settings.sources
        if source.id = id then return source
    end for
    return invalid
end function

sub configureServer()
    source = activeSource()
    m.settings.active = source.id
    url = source.url.Trim()
    if url <> "" and Right(url, 1) <> "/" then url = url + "/"
    auth = ""
    if source.user <> ""
        bytes = CreateObject("roByteArray")
        bytes.FromAsciiString(source.user + ":" + source.pass)
        auth = "Basic " + bytes.ToBase64String()
    end if
    m.global.serverOrigin = originOf(url)
    m.global.serverAuth = auth
    ' Every source feeds the one library; each login goes only to its server.
    auths = {}
    list = []
    for each s in m.settings.sources
        base = s.url.Trim()
        if base <> ""
            if Right(base, 1) <> "/" then base = base + "/"
            list.Push({url: base, user: s.user, pass: s.pass})
            if s.user <> ""
                b = CreateObject("roByteArray")
                b.FromAsciiString(s.user + ":" + s.pass)
                auths[LCase(originOf(base))] = "Basic " + b.ToBase64String()
            end if
        end if
    end for
    m.global.serverAuths = auths
    m.sourceLabel.text = UCase(source.label)
    if list.Count() > 1 then m.sourceLabel.text = list.Count().ToStr() + " SOURCES"
    m.top.FindNode("sourceChip").visible = m.settings.sources.Count() > 1
    sendCommand({action: "configure", url: url, user: source.user, pass: source.pass, sources: list})
end sub

' Switches the library to another source.
sub useSource(id as String)
    m.settings.active = id
    saveSettings()
    m.library = invalid
    m.items = {}
    m.items.SetModeCaseSensitive()
    m.folderStack = []
    configureServer()
    sendCommand({action: "load"})
    showToast("Source: " + activeSource().label)
end sub

function originOf(url as String) as String
    schemeEnd = url.Instr("://")
    if schemeEnd < 0 then return ""
    slash = url.Instr(schemeEnd + 3, "/")
    if slash < 0 then return url
    return Left(url, slash)
end function

' ---- Top bar ---------------------------------------------------------------

sub buildTabs()
    m.tabNodes = []
    x = 0
    font = makeFont("bold", 24)
    for each tabInfo in m.tabs
        group = m.tabsGroup.CreateChild("Group")
        group.translation = [x, 0]
        glow = group.CreateChild("Poster")
        glow.uri = "pkg:/images/focus-tab.9.png"
        glow.opacity = 0
        icon = group.CreateChild("Poster")
        icon.uri = "pkg:/images/icon-" + tabInfo.icon + ".png"
        icon.width = 30
        icon.height = 30
        icon.translation = [16, 13]
        icon.blendColor = "0x8391AAFF"
        label = group.CreateChild("Label")
        label.font = font
        label.text = tabInfo.label
        label.color = "0x8391AAFF"
        label.translation = [56, 0]
        label.height = 56
        label.vertAlign = "center"
        w = 56 + label.BoundingRect().width + 22
        glow.translation = [-24, -24]
        glow.width = w + 48
        glow.height = 104
        underline = group.CreateChild("Poster")
        underline.uri = "pkg:/images/neon-bar.9.png"
        underline.translation = [16, 58]
        underline.width = w - 32
        underline.height = 6
        underline.visible = false
        m.tabNodes.Push({group: group, glow: glow, icon: icon, label: label, underline: underline, width: w})
        x = x + w + 14
    end for
    drawTabs()
end sub

sub drawTabs()
    for i = 0 to m.tabNodes.Count() - 1
        node = m.tabNodes[i]
        current = m.tabs[i].id = m.currentTab
        focused = m.area = "tabs" and i = m.tabIndex
        node.glow.opacity = 0
        if focused then node.glow.opacity = 1
        node.underline.visible = current
        if focused or current
            node.label.color = "0xFFFFFFFF"
            node.icon.blendColor = "0x39FF88FF"
        else
            node.label.color = "0x8391AAFF"
            node.icon.blendColor = "0x8391AAFF"
        end if
    end for
end sub

sub onClock()
    m.clockLabel.text = wallClock(0)
end sub

sub setStatus(text as String)
    m.statusLabel.text = text
end sub

sub showToast(text as String)
    ' Measure at natural width (the last message's width would cut this one off).
    m.toastLabel.width = 0
    m.toastLabel.text = text
    width = m.toastLabel.BoundingRect().width + 80
    if width > 1700 then width = 1700
    if width < 300 then width = 300
    m.toastBack.width = width
    m.toastLabel.width = width
    m.toast.translation = [(1920 - width) / 2, 140]
    m.toast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub hideToast()
    m.toast.visible = false
end sub

' ---- Views -----------------------------------------------------------------

sub showView(name as String)
    ' Music keeps playing while you browse; a paused song is put away.
    if m.audio <> invalid and m.audio.state = "paused" then stopMusic()
    for each key in m.views
        m.views[key].visible = key = name
    end for
    m.view = name
    useBackdrop = name = "home" or name = "details"
    if not useBackdrop then setBackdrop("")
end sub

' Opens a tab's screen. Focus stays on the tab bar until the viewer presses Down.
sub showTab(id as String)
    if m.currentTab <> id then m.gridGroup = ""
    m.currentTab = id
    for i = 0 to m.tabs.Count() - 1
        if m.tabs[i].id = id then m.tabIndex = i
    end for
    m.history = []
    if id = "home"
        showView("home")
        refreshHome()
    else if id = "movies" or id = "shows" or id = "music"
        showView("grid")
        showGrid(id)
    else if id = "folders"
        showView("folders")
        openFolders()
    else if id = "search"
        showView("search")
        refreshSearch()
    else if id = "settings"
        showView("settings")
        refreshSettings()
    end if
    drawTabs()
end sub

sub focusTabs()
    m.area = "tabs"
    m.keySink.SetFocus(true)
    drawTabs()
end sub

' Moves focus into the open screen.
function focusContent() as Boolean
    ok = false
    if m.view = "home" then ok = focusHome()
    if m.view = "grid" then ok = focusGrid()
    if m.view = "search" then ok = focusSearch()
    if m.view = "folders" then ok = focusFolders()
    if m.view = "settings" then ok = focusSettings()
    if m.view = "details" then ok = focusDetails()
    drawTabs()
    return ok
end function

sub setBackdrop(uri as String)
    if uri = ""
        m.backdrop.opacity = 0
        m.backdropFade.opacity = 0
        m.backdrop.uri = ""
        return
    end if
    m.backdropFade.opacity = 1
    if m.backdrop.uri <> uri
        m.backdrop.opacity = 0
        setArt(m.backdrop, uri, "")
        m.backdropIn.control = "stop"
        m.backdropIn.control = "start"
    end if
end sub

' ---- Menus and keyboard ------------------------------------------------------

sub openMenu(id as String, title as String, subtitle as String, options as Object)
    markSelected()
    m.menuId = id
    m.menuReturn = m.area
    m.menu.title = title
    m.menu.subtitle = subtitle
    m.menu.options = options
    m.menu.visible = true
    m.area = "menu"
    m.menu.SetFocus(true)
    deferFocus()
end sub

sub closeMenu()
    m.mediaInfoUrl = invalid
    m.menu.visible = false
    m.area = m.menuReturn
    restoreFocus()
end sub

sub onMenuClosed()
    id = m.menuId
    closeMenu()
    if id = "playersubs" or id = "playeraudio" then openPlayerMenu()
    if id = "subbrowse" then openSubtitleMenu()
end sub

sub onMenuChosen()
    markSelected()
    choice = m.menu.chosen
    id = m.menuId
    if id = "mediainfo" then return
    closeMenu()
    if id = "sort"
        sortChosen(choice)
    else if id = "details"
        detailsMenuChosen(choice)
    else if id = "episode"
        episodeMenuChosen(choice)
    else if id = "seasonPick"
        openSeasonMap(Int(Val(choice.id)))
    else if id = "seasonMap"
        seasonMapChosen(choice)
    else if id = "versions"
        versionChosen(choice)
    else if id = "candidates"
        candidateChosen(choice)
    else if id = "player" or id = "playersubs" or id = "playeraudio" or id = "subbrowse"
        playerMenuChosen(choice)
    else if id = "type"
        typeChosen(choice)
    else if id = "heavy"
        heavyChosen(choice)
    else if id = "settingsNote"
        ' Just a message: OK closes it.
    else if id = "confirmClear"
        if choice.id = "yes" then refreshAllDetails()
    else if id = "groups"
        groupChosen(choice)
    else if id = "removeSource"
        if choice.id = "remove" then removeSource(m.editingSource)
        focusSettings()
    else if id = "epversions"
        if m.pendingEpisode <> invalid then playEpisodeFile(m.detailsItem, m.pendingEpisode, Val(choice.id))
    else if id = "folderfile"
        folderFileChosen(choice)
    end if
end sub

' purpose: what the typed text is for (handled in onKeyboardDone).
sub openKeyboard(purpose as String, title as String, hint as String, value as String, secure as Boolean, mode as String)
    m.keyboardPurpose = purpose
    m.keyboardReturn = m.area
    m.keyboard.title = title
    m.keyboard.hint = hint
    m.keyboard.secure = secure
    m.keyboard.mode = mode
    m.keyboard.value = value
    m.keyboard.open = true
    m.keyboard.visible = true
    m.area = "keyboard"
    m.keyboard.SetFocus(true)
end sub

sub closeKeyboard()
    m.keyboard.open = false
    m.keyboard.visible = false
    m.area = m.keyboardReturn
    restoreFocus()
end sub

sub onKeyboardCancel()
    closeKeyboard()
end sub

sub onKeyboardDone()
    text = m.keyboard.done
    purpose = m.keyboardPurpose
    closeKeyboard()
    if purpose = "url" or purpose = "user" or purpose = "pass" or purpose = "label" or purpose = "hurl" or purpose = "hcode"
        settingTyped(purpose, text)
    else if purpose = "search"
        searchTyped(text)
    else if purpose = "fix"
        fixTyped(text)
    end if
end sub

' Puts focus back on whatever area is current (after a menu or keyboard).
sub restoreFocus()
    if m.area = "tabs"
        focusTabs()
    else if m.area = "player"
        m.keySink.SetFocus(true)
    else if m.area = "menu"
        m.menu.SetFocus(true)
    else if m.area = "keyboard"
        m.keyboard.SetFocus(true)
    else
        focusContent()
    end if
end sub

' ---- Remote ------------------------------------------------------------------

' A list's OK opens something and then also reaches the scene: that same
' press must not also press whatever the new screen has focused.
' Focus set while a list is still handling its key press doesn't stick:
' set it once more right after.
sub deferFocus()
    m.focusTimer.control = "stop"
    m.focusTimer.control = "start"
end sub

sub onFocusTimer()
    restoreFocus()
    ' The grid redraws after the first try: this second one sticks.
    m.gridReturn = invalid
end sub

function focusName() as String
    f = m.top.focusedChild
    if f = invalid then return "none"
    while f.focusedChild <> invalid and not f.focusedChild.IsSameNode(f)
        f = f.focusedChild
    end while
    return f.id
end function

sub markSelected()
    if m.keyClock = invalid then m.keyClock = CreateObject("roTimespan")
    m.selectedAt = m.keyClock.TotalMilliseconds()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if m.area = "info"
        if press then return infoKey(key)
        return true
    end if
    if key = "OK" and m.selectedAt <> invalid
        if m.keyClock.TotalMilliseconds() - m.selectedAt < 400
            m.selectedAt = invalid
            return true
        end if
    end if
    if m.area = "player" then return playerKey(key, press)
    if not press then return false
    if m.area = "tabs" then return tabsKey(key)
    if (key = "play") and musicActive() and m.area <> "details"
        toggleMusic()
        return true
    end if
    handled = false
    if m.view = "home" then handled = homeKey(key)
    if not handled and m.view = "grid" then handled = gridKey(key)
    if not handled and m.view = "search" then handled = searchKey(key)
    if not handled and m.view = "folders" then handled = foldersKey(key)
    if not handled and m.view = "settings" then handled = settingsKey(key)
    if not handled and m.view = "details" then handled = detailsKey(key)
    if handled then return true
    if (key = "fastforward" or key = "rewind") and musicActive()
        if key = "fastforward" then musicSkip(1) else musicSkip(-1)
        return true
    end if
    if key = "up"
        focusTabs()
        return true
    end if
    if key = "back"
        focusTabs()
        return true
    end if
    return false
end function

function tabsKey(key as String) as Boolean
    if key = "left"
        if m.tabIndex > 0
            m.tabIndex = m.tabIndex - 1
            showTab(m.tabs[m.tabIndex].id)
            focusTabs()
        end if
        return true
    else if key = "right"
        if m.tabIndex < m.tabs.Count() - 1
            m.tabIndex = m.tabIndex + 1
            showTab(m.tabs[m.tabIndex].id)
            focusTabs()
        end if
        return true
    else if key = "down" or key = "OK"
        if m.view = "details" or m.tabs[m.tabIndex].id = m.currentTab
            if focusContent() then return true
        end if
        showTab(m.tabs[m.tabIndex].id)
        focusContent()
        return true
    else if key = "back"
        if m.currentTab <> "home"
            showTab("home")
            focusTabs()
            return true
        end if
        return false
    else if key = "play" and musicActive()
        toggleMusic()
        return true
    end if
    return false
end function

function yesNoWord(value as Boolean) as String
    if value then return "yes"
    return "no"
end function
