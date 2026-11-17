' Video player with Box://Stream's own controls: a neon seek bar on a bezel
' panel, timed seeking with a preview, subtitles / audio track menu,
' resume points and Up Next for episodes and multi-part movies.

sub initPlayer()
    m.player = m.top.FindNode("player")
    m.video = m.top.FindNode("video")
    m.overlay = m.top.FindNode("playerOverlay")
    m.playerTitle = m.top.FindNode("playerTitle")
    m.playerSubtitle = m.top.FindNode("playerSubtitle")
    m.playerClock = m.top.FindNode("playerClock")
    m.playIcon = m.top.FindNode("playIcon")
    m.elapsedLabel = m.top.FindNode("elapsedLabel")
    m.remainLabel = m.top.FindNode("remainLabel")
    m.barFill = m.top.FindNode("barFill")
    m.barKnob = m.top.FindNode("barKnob")
    m.seekLabel = m.top.FindNode("seekLabel")
    m.playerHints = m.top.FindNode("playerHints")
    m.endsLabel = m.top.FindNode("endsLabel")
    m.spinner = m.top.FindNode("playerSpinner")
    m.spinnerText = m.top.FindNode("spinnerText")
    m.spin = m.top.FindNode("spin")
    m.upNext = m.top.FindNode("upNext")
    m.upNextTitle = m.top.FindNode("upNextTitle")
    m.upNextCount = m.top.FindNode("upNextCount")
    m.playerError = m.top.FindNode("playerError")
    m.playerErrorText = m.top.FindNode("playerErrorText")
    m.playerTitle.font = makeFont("bold", 46)
    m.playerSubtitle.font = makeFont("bold", 26)
    m.playerClock.font = makeFont("bold", 32)
    m.elapsedLabel.font = makeFont("bold", 28)
    m.remainLabel.font = makeFont("regular", 28)
    m.seekLabel.font = makeFont("bold", 28)
    m.endsLabel.font = makeFont("regular", 22)
    m.spinnerText.font = makeFont("regular", 26)
    m.upNextTitle.font = makeFont("bold", 30)
    m.upNextCount.font = makeFont("regular", 24)
    m.top.FindNode("upNextLabel").font = makeFont("bold", 22)
    m.top.FindNode("playerErrorTitle").font = makeFont("bold", 36)
    m.playerErrorText.font = makeFont("regular", 25)
    buildHintRow(m.playerHints, [{icons: ["playpause"], text: "PAUSE"}, {icons: ["dpad-leftright"], text: "10 SEC"}, {icons: ["rewind", "forward"], text: "30 SEC"}, {icons: ["ok"], text: "OPTIONS"}, {icons: ["back"], text: "EXIT"}])
    m.barWidth = 1230
    ' Position four times a second keeps subtitles on their frame.
    m.video.notificationInterval = 0.25
    m.video.ObserveField("state", "onVideoState")
    m.video.ObserveField("bufferingStatus", "onBuffering")
    m.playerTimer = m.top.FindNode("playerTimer")
    m.playerTimer.ObserveField("fire", "onPlayerTick")
    m.overlayTimer = m.top.FindNode("overlayTimer")
    m.overlayTimer.ObserveField("fire", "hideOverlay")
    m.seekTimer = m.top.FindNode("seekTimer")
    m.seekTimer.ObserveField("fire", "commitSeek")
    m.upNextTimer = m.top.FindNode("upNextTimer")
    m.upNextTimer.ObserveField("fire", "onUpNextTick")
    ' Trick-play colors, in case the Roku shows its own bar anyway.
    m.video.trickPlayBar.filledBarBlendColor = "0x39FF88FF"
    m.video.bufferingBar.filledBarBlendColor = "0x2EA0FFFF"
    m.video.bufferingBar.visible = false
    m.video.retrievingBar.visible = false
    m.video.trickPlayBar.visible = false
    m.video.suppressCaptions = false
    m.queue = []
    m.queueIndex = 0
    m.seekTarget = -1
    ' Box://Stream draws subtitles itself (Roku's own drawing of text
    ' tracks in MKV files doesn't show up on every model).
    m.subLayer = m.top.FindNode("subLayer")
    m.subLabels = []
    for each name in ["subEdge1", "subEdge2", "subEdge3", "subEdge4", "subText"]
        label = m.top.FindNode(name)
        label.font = makeFont("bold", 50)
        m.subLabels.Push(label)
    end for
    m.subPics = [m.top.FindNode("subPic1"), m.top.FindNode("subPic2")]
    m.subPicNext = m.top.FindNode("subPicNext")
    m.subPicKey = ""
    m.subTask = CreateObject("roSGNode", "SubtitleTask")
    m.subTask.ObserveField("cues", "onSubCues")
    m.subTask.control = "run"
    m.subGen = 0
    m.subCues = []
    m.subShown = ""
    m.ownSubs = invalid
    m.posBase = 0
    m.posClock = CreateObject("roTimespan")
    m.subSent = 0
    m.subTimer = m.top.FindNode("subTimer")
    m.subTimer.ObserveField("fire", "onSubTick")
    m.video.ObserveField("position", "onVideoPosition")
end sub

' Remote buttons drawn as small icons (images/hints, from
' tools/build_hint_icons.py), each followed by one word.

' ---- Starting playback ---------------------------------------------------------

sub playMovie(item as Object, fileIndex as Integer, resume as Boolean)
    queue = []
    if item.multipart = true
        part = 1
        for each f in item.files
            queue.Push(entryFor(f, displayTitle(item), "Part " + part.ToStr() + " of " + item.files.Count().ToStr(), item.key, ""))
            part = part + 1
        end for
        fileIndex = 0
    else
        f = item.files[fileIndex]
        if f = invalid then f = item.files[0]
        subtitle = itemYear(item)
        meta = metaFor(item.key)
        if meta <> invalid
            if meta.runtime <> invalid and meta.runtime <> "" then subtitle = subtitle + "  ·  " + runtimeText(meta.runtime)
        end if
        queue.Push(entryFor(f, displayTitle(item), subtitle, item.key, ""))
        fileIndex = 0
    end if
    startAt = 0
    if resume then startAt = resumeSeconds(queue[0].url)
    startPlayback(queue, fileIndex, startAt)
end sub

sub playEpisode(show as Object, episode as Object, resume as Boolean)
    queue = []
    start = 0
    for each e in show.episodes
        if e.key = episode.key then start = queue.Count()
        queue.Push(entryFor(e.files[0], displayTitle(show), episodeLabel(e) + "  ·  " + episodeName(show, e), show.key, e.key))
    end for
    startAt = 0
    if resume then startAt = resumeSeconds(episode.files[0].url)
    startPlayback(queue, start, startAt)
end sub

' One episode in a chosen version; the rest of the season follows as usual.
sub playEpisodeFile(show as Object, episode as Object, fileIndex as Integer)
    queue = []
    start = 0
    for each e in show.episodes
        file = e.files[0]
        if e.key = episode.key
            start = queue.Count()
            file = e.files[fileIndex]
        end if
        queue.Push(entryFor(file, displayTitle(show), episodeLabel(e) + "  ·  " + episodeName(show, e), show.key, e.key))
    end for
    startPlayback(queue, start, resumeSeconds(episode.files[fileIndex].url))
end sub

sub playLooseFile(entry as Object)
    file = {url: entry.url, name: entry.name, ext: entry.ext, subtitle: ""}
    queue = [entryFor(file, fileStemOf(entry.name), activeSource().label, "", "")]
    startPlayback(queue, 0, resumeSeconds(entry.url))
end sub

function entryFor(file as Object, title as String, subtitle as String, itemKey as String, episodeKey as String) as Object
    subs = []
    if file.subtitles <> invalid then subs = file.subtitles
    return {url: file.url, ext: file.ext, title: title, subtitle: subtitle, subs: subs, itemKey: itemKey, episodeKey: episodeKey}
end function

function streamFormatFor(ext as String) as String
    if ext = "m3u8" then return "hls"
    if ext = "mkv" or ext = "webm" then return "mkv"
    if ext = "mp4" or ext = "m4v" or ext = "mov" then return "mp4"
    return ""
end function

' Auth header for files on the viewer's own server.
function authHeaders(url as String) as Object
    headers = []
    auth = serverAuthFor(url)
    if auth <> "" then headers.Push("Authorization:" + auth)
    return headers
end function

sub startPlayback(queue as Object, index as Integer, startAt as Integer)
    m.subPick = invalid
    m.audioPick = invalid
    stopMusic()
    m.queue = queue
    m.queueIndex = index
    markSelected()
    m.returnArea = m.area
    m.area = "player"
    m.player.visible = true
    m.topBar.visible = false
    m.keySink.SetFocus(true)
    deferFocus()
    m.playerTimer.control = "start"
    openEntry(startAt)
end sub

sub openEntry(startAt as Integer)
    entry = m.queue[m.queueIndex]
    m.playerError.visible = false
    m.upNext.visible = false
    m.upNextTimer.control = "stop"
    content = CreateObject("roSGNode", "ContentNode")
    content.url = entry.url
    content.title = entry.title
    format = streamFormatFor(entry.ext)
    if format <> "" then content.StreamFormat = format
    headers = authHeaders(entry.url)
    if headers.Count() > 0 then content.HttpHeaders = headers
    if entry.subs.Count() > 0
        tracks = []
        for each s in entry.subs
            ext = LCase(Right(s.url, 4))
            if ext = ".srt" or ext = ".vtt" then tracks.Push({Language: s.lang, TrackName: s.url, Description: s.name})
        end for
        if tracks.Count() > 0 then content.SubtitleTracks = tracks
    end if
    m.tracksApplied = false
    m.audioChoice = invalid
    if startAt > 0 then content.PlayStart = startAt
    ' Subtitles: the viewer's pick, or their language (from MediaInfo).
    pick = m.subPick
    if pick = invalid then pick = rememberedSubFile(entry.url)
    if pick = invalid then pick = preferredSubtitle(entry.url)
    stopOwnSubs()
    m.video.suppressCaptions = true
    m.posBase = startAt
    m.posClock.Mark()
    if pick <> invalid and pick <> "" then startOwnSubs(pick, startAt)
    m.activeSub = pick
    m.subChoice = pick
    sendCommand({action: "playing", on: true, url: entry.url})
    ' Read this file's headers (track numbers) if that hasn't happened yet.
    if m.probes[entry.url] = invalid then sendCommand({action: "probe", url: entry.url, ext: entry.ext})
    m.playerTitle.text = entry.title
    m.playerSubtitle.text = entry.subtitle
    m.lastSaved = 0
    m.seekTarget = -1
    if m.swap <> invalid then m.swap.quit = true
    m.swap = invalid
    m.swapActive = false
    m.swapOffset = 0
    m.audioPlan = audioPlan(entry)
    if m.audioPlan <> invalid and m.audioPlan.swap
        ' The chosen track doesn't play here (DTS / TrueHD): the user's helper
        ' converts it to Dolby Digital and the video comes as it is.
        startSwap(entry, startAt, m.audioPlan.index)
        showSpinner("Converting audio...")
        showOverlay()
        return
    end if
    m.video.content = content
    m.video.control = "play"
    showSpinner("Loading...")
    showOverlay()
end sub

' ---- Converted audio (AudioSwap + helper) --------------------------------------------

function vPos() as Float
    ' The rebuilt movie keeps the original timestamps, so the position is
    ' already the movie's own; a player that counts from zero gets the offset.
    if m.swapActive = true and m.video.position + 5 < m.swapOffset then return m.video.position + m.swapOffset
    return m.video.position
end function

function vDur() as Float
    if m.swapActive = true
        info = m.probes[m.queue[m.queueIndex].url]
        if info <> invalid and info.seconds <> invalid and info.seconds > 0 then return info.seconds
    end if
    return m.video.duration
end function

' ---- Choosing the audio track ------------------------------------------------------

' Tracks that aren't the movie's main sound: commentary, audio description,
' isolated score.
function isExtraAudio(a as Object) as Boolean
    name = LCase(textValue(a.name))
    if name = "" then return false
    for each word in ["comment", "descri", "isolated", "score only", "music only", "narrat"]
        if Instr(1, name, word) > 0 then return true
    end for
    return CreateObject("roRegex", "(^|[^a-z])ad([^a-z]|$)", "").IsMatch(name)
end function

function trackNumberOf(info as Object, i as Integer) as Integer
    number = info.audio[i].number
    if number = invalid or number <= 0 then number = info.video.Count() + i + 1
    return number
end function

' The audio to play, from an MKV's own track list: the track the viewer
' picked for this file; else the remembered language (or the file's default
' track's), and in it a track this Roku plays (a compatibility track) before
' one the helper has to convert; commentary and description tracks only when
' nothing else fits. Without a helper, a track with sound comes first.
' Invalid for other files (Roku's own choice then).
function audioPlan(entry as Object) as Dynamic
    if LCase(entry.ext) <> "mkv" then return invalid
    info = m.probes[entry.url]
    if info = invalid or info.ok <> true or info.audio = invalid or info.audio.Count() = 0 then return invalid
    helper = helperOn()
    best = 0
    if m.audioPick <> invalid and m.audioPickUrl = entry.url and m.audioPick < info.audio.Count()
        best = m.audioPick
    else
        lang = loadPreference("audioLang")
        if lang = ""
            for each a in info.audio
                if a.default = true and textValue(a.lang) <> "" then lang = textValue(a.lang)
                if lang <> "" then exit for
            end for
        end if
        if lang <> "" then lang = languageName(lang)
        bestScore = -1
        for i = 0 to info.audio.Count() - 1
            a = info.audio[i]
            playable = audioPlayable(a.codec)
            score = 0
            if playable and not helper then score = score + 10000
            if not isExtraAudio(a) then score = score + 1000
            if lang <> "" and languageName(textValue(a.lang)) = lang then score = score + 100
            if playable then score = score + 20
            ' Surround before stereo (a 5.1 compatibility track before a stereo
            ' original), unless the viewer wants everything in stereo.
            if a.channels <> invalid and a.channels > 0 and not optionOn("stereoAudio")
                if a.channels > 8 then score = score + 8 else score = score + a.channels
            end if
            if a.default = true then score = score + 1
            if score > bestScore
                bestScore = score
                best = i
            end if
        end for
    end if
    a = info.audio[best]
    return {index: best, number: trackNumberOf(info, best), swap: helper and not audioPlayable(a.codec)}
end function

' Dolby Digital for a track: its own channels up to 5.1 (7.1 is folded down;
' Dolby Digital has no 7.1), at a bitrate that suits that many.
function ac3Layout(a as Object) as Object
    ch = 6
    if a.channels <> invalid and a.channels > 0 then ch = a.channels
    if ch > 6 then ch = 6
    ' Settings > Helper: everything converted in stereo (TV speakers, 2.0 bars).
    if ch > 2 and optionOn("stereoAudio") then ch = 2
    kbps = 640
    if ch = 1 then kbps = 192
    if ch = 2 then kbps = 256
    if ch >= 3 and ch <= 5 then kbps = 448
    return {channels: ch, kbps: kbps}
end function

' The file's audio tracks (for the Audio menu), with what happens to each.
function fileAudioRows() as Object
    options = []
    info = m.probes[m.queue[m.queueIndex].url]
    helper = helperOn()
    for i = 0 to info.audio.Count() - 1
        a = info.audio[i]
        lang = languageName(textValue(a.lang))
        notes = cleanNotes(trackNotes(textValue(a.name), lang), lang)
        label = lang
        if notes.Count() > 0 then label = label + "  ·  " + notes.Join("  ·  ")
        detail = textValue(a.codec)
        if a.channels <> invalid and a.channels > 0 then detail = detail + " " + channelText(a.channels)
        if not audioPlayable(a.codec)
            if helper
                out = ac3Layout(a)
                detail = detail + "  >  AC3 " + channelText(out.channels)
            else
                detail = detail + "  ·  no sound on this TV"
            end if
        end if
        options.Push({id: "atrack:" + i.ToStr(), label: label, detail: detail, checked: i = m.audioPlan.index})
    end for
    return options
end function

' The playing movie's track list arrived after it started (first play of a
' file, e.g. from Continue Watching): apply the audio plan now, as openEntry
' would have (compatibility track, or the helper's conversion).
sub playingProbed(changed as Object)
    if m.player.visible <> true or m.audioPlan <> invalid or m.swapActive = true then return
    if m.queue = invalid or m.queue.Count() = 0 then return
    entry = m.queue[m.queueIndex]
    if not changed.DoesExist(entry.url) then return
    m.audioPlan = audioPlan(entry)
    if m.audioPlan = invalid then return
    if m.audioPlan.swap
        startSwap(entry, vPos(), m.audioPlan.index)
        showSpinner("Converting audio...")
    else
        m.video.audioTrack = m.audioPlan.number.ToStr()
        m.audioChoice = m.audioPlan.number.ToStr()
    end if
    if m.overlay.visible then drawPlayerBadges()
end sub

' A track picked in the Audio menu (MKV files): played as it is, or converted
' by the helper; switching between the two restarts at the same point.
sub chooseFileAudio(i as Integer, label as String)
    entry = m.queue[m.queueIndex]
    info = m.probes[entry.url]
    a = info.audio[i]
    m.audioPick = i
    m.audioPickUrl = entry.url
    savePreference("audioLang", textValue(a.lang))
    wasSwap = m.swapActive = true
    m.audioPlan = {index: i, number: trackNumberOf(info, i), swap: helperOn() and not audioPlayable(a.codec)}
    showToast("Audio: " + label)
    if m.audioPlan.swap
        startSwap(entry, vPos(), i)
        showSpinner("Converting audio...")
    else if wasSwap
        ' Back to the file as it is, with this track.
        openEntry(Int(vPos()))
    else
        m.video.audioTrack = m.audioPlan.number.ToStr()
        m.audioChoice = m.audioPlan.number.ToStr()
    end if
    drawPlayerBadges()
end sub

sub startSwap(entry as Object, startAt as Float, pick as Integer)
    info = m.probes[entry.url]
    if info = invalid or info.audio = invalid or pick >= info.audio.Count() then return
    number = trackNumberOf(info, pick)
    layout = ac3Layout(info.audio[pick])
    if m.swap <> invalid then m.swap.quit = true
    if m.swapPort = invalid then m.swapPort = 8920
    m.swapPort = m.swapPort + 1
    if m.swapPort > 8960 then m.swapPort = 8921
    m.swapActive = true
    m.swapIndex = pick
    m.video.control = "stop"
    m.swap = CreateObject("roSGNode", "AudioSwap")
    m.swap.ObserveField("address", "onSwapReady")
    m.swap.ObserveField("swapState", "onSwapState")
    m.swap.request = {url: entry.url, headers: authHeaders(entry.url), swapTrack: number, audioIndex: pick, channels: layout.channels, kbps: layout.kbps, start: startAt, helper: m.settings.helper, port: m.swapPort}
    m.swap.control = "run"
end sub

' Only the newest conversion counts (older ones were replaced by a seek).
function currentSwap(event as Object) as Boolean
    if m.swap = invalid then return false
    return event.GetRoSGNode().IsSameNode(m.swap)
end function

sub onSwapState(event as Object)
    if not currentSwap(event) then return
    s = m.swap.swapState
    if type(s) <> "roAssociativeArray" then return
    status = textValue(s.status)
    if status = "ready" and s.startSeconds <> invalid then m.swapOffset = s.startSeconds
    if status = "error"
        hideSpinner()
        showToast(textValue(s.message))
    end if
end sub

sub onSwapReady(event as Object)
    if not currentSwap(event) then return
    address = m.swap.address
    if address = "" then return
    content = CreateObject("roSGNode", "ContentNode")
    content.url = address
    content.title = m.playerTitle.text
    content.StreamFormat = "mkv"
    m.posBase = m.swapOffset
    m.posClock.Mark()
    m.video.content = content
    m.video.control = "play"
    drawPlayerBadges()
end sub

sub stopPlayback()
    if m.swap <> invalid then m.swap.quit = true
    m.swap = invalid
    m.swapActive = false
    stopOwnSubs()
    sendCommand({action: "playing", on: false, url: ""})
    saveProgress(true)
    m.video.control = "stop"
    m.video.content = invalid
    m.playerTimer.control = "stop"
    m.upNextTimer.control = "stop"
    m.spin.control = "stop"
    m.player.visible = false
    m.topBar.visible = true
    m.area = m.returnArea
    if m.area = invalid or m.area = "player" then m.area = "content"
    if m.view = "details" then refreshDetails()
    if m.view = "home" then refreshHome()
    restoreFocus()
end sub

sub saveProgress(force as Boolean)
    if m.queue.Count() = 0 then return
    entry = m.queue[m.queueIndex]
    position = vPos()
    duration = vDur()
    if duration <= 0 or position <= 0 then return
    if not force and Abs(position - m.lastSaved) < 15 then return
    m.lastSaved = position
    saveResume(entry.url, position, duration, entry.itemKey, entry.episodeKey)
end sub

' ---- Video events ----------------------------------------------------------------

sub onVideoState()
    state = m.video.state
    if state = "buffering"
        showSpinner("Loading...")
    else if state = "playing"
        hideSpinner()
        if not m.tracksApplied then applyTrackPreferences()
        m.playIcon.uri = "pkg:/images/icon-pause.png"
    else if state = "paused"
        m.playIcon.uri = "pkg:/images/icon-play.png"
        showOverlay()
        m.overlayTimer.control = "stop"
    else if state = "finished"
        saveProgress(true)
        if m.queueIndex + 1 < m.queue.Count()
            startUpNext()
        else
            stopPlayback()
        end if
    else if state = "error"
        hideSpinner()
        showPlayerError()
    end if
end sub

sub onBuffering()
    status = m.video.bufferingStatus
    if status <> invalid and m.spinner.visible
        m.spinnerText.text = "Loading  " + status.percentage.ToStr() + "%"
    end if
end sub

sub showSpinner(text as String)
    m.spinnerText.text = text
    m.spinner.visible = true
    m.spin.control = "start"
end sub

sub hideSpinner()
    m.spinner.visible = false
    m.spin.control = "stop"
end sub

sub showPlayerError()
    entry = m.queue[m.queueIndex]
    message = m.video.errorMsg
    print "[video] error "; m.video.errorCode; " "; message; " "; FormatJson(m.video.errorInfo)
    detail = ""
    if m.video.errorStr <> invalid then detail = m.video.errorStr
    lower = LCase(entry.url)
    hint = ""
    if entry.ext = "avi" or entry.ext = "wmv" or entry.ext = "mpg"
        hint = "Roku players can't play ." + entry.ext + " files."
    else if (Instr(1, lower, "hevc") > 0 or Instr(1, lower, "x265") > 0 or Instr(1, lower, "h265") > 0) and not m.canHevc
        hint = "This file is HEVC (H.265) and this Roku has no HEVC decoder. An H.264 copy would play."
    else if m.video.errorCode = -3 or Instr(1, LCase(detail), "401") > 0
        hint = "Check this source's login in Settings."
    end if
    text = message
    if hint <> "" then text = hint + Chr(10) + Chr(10) + message
    m.playerErrorText.text = text + Chr(10) + Chr(10) + "Press BACK to return."
    m.playerError.visible = true
    m.overlay.visible = false
end sub

' ---- The play bar -----------------------------------------------------------------

sub showOverlay()
    if not m.overlay.visible then drawPlayerBadges()
    m.overlay.visible = true
    drawBar()
    m.overlayTimer.control = "stop"
    if m.video.state <> "paused" then m.overlayTimer.control = "start"
end sub

' What's playing, like a player's status line: video codec, resolution, HDR,
' and the audio track (with the conversion when the helper makes it).
sub drawPlayerBadges()
    group = m.top.FindNode("playerBadges")
    while group.GetChildCount() > 0
        group.RemoveChildIndex(0)
    end while
    if m.queue = invalid or m.queue.Count() = 0 then return
    info = m.probes[m.queue[m.queueIndex].url]
    if info = invalid or info.ok <> true then return
    grey = "0x2A3344FF"
    light = "0xDCE4F2FF"
    x = 0
    if info.video <> invalid and info.video.Count() > 0
        v = info.video[0]
        x = badge(group, x, 0, textValue(v.codec), grey, light)
        res = ""
        if v.width >= 3800 then res = "4K" else if v.width >= 1900 then res = "1080p" else if v.width >= 1270 then res = "720p" else if v.width > 0 then res = "SD"
        if res <> "" then x = badge(group, x, 0, res, grey, light)
        if textValue(v.hdr) <> "" then x = badge(group, x, 0, textValue(v.hdr), grey, light)
        if v.bits <> invalid and v.bits >= 10 then x = badge(group, x, 0, v.bits.ToStr() + "-BIT", grey, light)
    end if
    if info.audio <> invalid and info.audio.Count() > 0
        index = 0
        if m.audioPlan <> invalid then index = m.audioPlan.index
        a = info.audio[index]
        name = textValue(a.codec)
        cut = Instr(1, name, " (")
        if cut > 0 then name = Left(name, cut - 1)
        channels = ""
        if a.channels <> invalid and a.channels > 0 then channels = " " + channelText(a.channels)
        if m.swapActive = true
            out = ac3Layout(a)
            x = badge(group, x, 0, name + channels + "  >  AC3 " + channelText(out.channels), grey, light)
            badge(group, x, 0, "HELPER", "0x28DCFFFF", "0x041318FF")
        else
            badge(group, x, 0, name + channels, grey, light)
        end if
    end if
end sub

sub hideOverlay()
    if m.video.state = "paused" or m.seekTarget >= 0 then return
    m.overlay.visible = false
end sub

sub onPlayerTick()
    if m.overlay.visible then drawBar()
    if m.video.state = "playing" then saveProgress(false)
end sub

sub drawBar()
    duration = vDur()
    position = vPos()
    if m.seekTarget >= 0 then position = m.seekTarget
    fraction = 0
    if duration > 0 then fraction = position / duration
    if fraction > 1 then fraction = 1
    if fraction < 0 then fraction = 0
    fillW = Int(m.barWidth * fraction)
    m.barFill.width = fillW
    ' A 9-patch can't be thinner than its corners: hide it until it is wider.
    m.barFill.visible = fillW >= 16
    m.barKnob.translation = [250 + fillW - 47, -4]
    m.elapsedLabel.text = clockText(position)
    remaining = duration - position
    if remaining < 0 then remaining = 0
    if duration > 0
        m.remainLabel.text = "-" + clockText(remaining)
        m.endsLabel.text = "Ends at " + wallClock(Int(remaining))
    else
        m.remainLabel.text = ""
        m.endsLabel.text = ""
    end if
    m.playerClock.text = wallClock(0)
    if m.seekTarget >= 0
        m.seekLabel.visible = true
        m.seekLabel.text = clockText(m.seekTarget)
        m.seekLabel.translation = [250 + fillW - 80, -46]
    else
        m.seekLabel.visible = false
    end if
end sub

' Seeking: presses move a preview point; the jump happens once they stop.
sub nudgeSeek(seconds as Integer)
    duration = vDur()
    if duration <= 0 then return
    if m.seekTarget < 0 then m.seekTarget = vPos()
    m.seekTarget = m.seekTarget + seconds
    if m.seekTarget < 0 then m.seekTarget = 0
    if m.seekTarget > duration - 3 then m.seekTarget = duration - 3
    showOverlay()
    ' Converted audio restarts the movie on each jump: wait for the presses to stop.
    if m.swapActive = true then m.seekTimer.duration = 1.5 else m.seekTimer.duration = 0.7
    m.seekTimer.control = "stop"
    m.seekTimer.control = "start"
end sub

sub commitSeek()
    if m.seekTarget < 0 then return
    target = m.seekTarget
    m.seekTarget = -1
    m.seekStreak = 0
    if m.swapActive = true
        ' Converted audio: the movie restarts at the new point (both streams).
        startSwap(m.queue[m.queueIndex], target, m.swapIndex)
    else
        m.video.seek = target
    end if
    showOverlay()
end sub

function playerKey(key as String, press as Boolean) as Boolean
    if not press then return true
    if m.playerError.visible
        if key = "back" or key = "OK" then stopPlayback()
        return true
    end if
    if m.upNext.visible
        if key = "OK" or key = "play"
            playNextNow()
        else if key = "back"
            m.upNextTimer.control = "stop"
            stopPlayback()
        end if
        return true
    end if
    if key = "back"
        stopPlayback()
    else if key = "OK"
        ' Roku keeps * for its own menu during video, so OK opens ours.
        if m.seekTarget >= 0 then commitSeek() else openPlayerMenu()
    else if key = "play"
        if m.seekTarget >= 0
            commitSeek()
        else if m.video.state = "paused"
            m.video.control = "resume"
            showOverlay()
        else
            m.video.control = "pause"
        end if
    else if key = "left"
        nudgeSeek(-10)
    else if key = "right"
        nudgeSeek(10)
    else if key = "rewind" or key = "fastforward"
        if m.seekStreak = invalid then m.seekStreak = 0
        m.seekStreak = m.seekStreak + 1
        step30 = 30
        if m.seekStreak > 3 then step30 = 60
        if m.seekStreak > 6 then step30 = 180
        if m.seekStreak > 10 then step30 = 600
        if key = "rewind" then nudgeSeek(-step30) else nudgeSeek(step30)
    else if key = "replay"
        nudgeSeek(-10)
        commitSeek()
    else if key = "up" or key = "down"
        showOverlay()
    else if key = "options"
        openPlayerMenu()
    end if
    return true
end function

' ---- Subtitles and audio tracks ------------------------------------------------------

' Playback panel: subtitles, then audio, then Media info. One clean row per
' track: the language as the title, the details (forced, SDH, format, where
' it comes from) underneath.
' Playback panel, first level: Subtitles and Audio (each opens its own list),
' Media info and Start over. A file can carry 40 subtitle tracks, so the
' lists are separate.
sub openPlayerMenu()
    subs = subtitleRows()
    current = "Off"
    for each r in subs
        if r.checked = true and r.id <> "sub:off" then current = r.label
    end for
    audios = audioRows()
    currentAudio = ""
    for each r in audios
        if r.checked = true then currentAudio = r.label.Replace("Audio:  ", "")
    end for
    options = []
    options.Push({id: "subs", label: "Subtitles", detail: (subs.Count() - 1).ToStr() + " available", value: current})
    options.Push({id: "audio", label: "Audio", detail: audios.Count().ToStr() + " available", value: currentAudio})
    options.Push({id: "mediainfo", label: "Media info", detail: liveStats()})
    options.Push({id: "restart", label: "Start from the beginning"})
    openMenu("player", "Playback", m.playerTitle.text, options)
end sub

sub openSubtitleMenu()
    openMenu("playersubs", "Subtitles", m.playerTitle.text, subtitleRows())
end sub

sub openAudioMenu()
    openMenu("playeraudio", "Audio", m.playerTitle.text, audioRows())
end sub

function subtitleRows() as Object
    options = []
    subtitles = m.video.availableSubtitleTracks
    captionsOn = m.video.suppressCaptions <> true
    currentSub = m.video.subtitleTrack
    if m.subChoice <> invalid
        currentSub = m.subChoice
        captionsOn = m.subChoice <> ""
    end if
    if m.ownSubs <> invalid
        captionsOn = true
        currentSub = m.ownSubs
    end if
    options.Push({id: "sub:off", label: "Off", checked: not captionsOn})
    seen = {}
    counts = {}
    rows = []
    if subtitles <> invalid
        for each t in subtitles
            trackName = textValue(t.TrackName)
            if trackName <> "" and not seen.DoesExist(trackName)
                seen[trackName] = true
                lang = languageName(t.Language)
                notes = trackNotes(textValue(t.Description), lang)
                if LCase(Left(trackName, 4)) = "http" then notes.Push("subtitle file")
                if lang = "Unknown" and notes.Count() > 0 then lang = notes.Shift()
                key = lang + "|" + notes.Join("|")
                if not counts.DoesExist(key) then counts[key] = 0
                counts[key] = counts[key] + 1
                rows.Push({trackName: trackName, lang: lang, notes: notes, key: key, n: counts[key]})
            end if
        end for
    end if
    for each extra in extraSubtitleTracks()
        if not seen.DoesExist(extra.trackName)
            seen[extra.trackName] = true
            key = extra.lang + "|" + extra.notes.Join("|")
            if not counts.DoesExist(key) then counts[key] = 0
            counts[key] = counts[key] + 1
            extra.key = key
            extra.n = counts[key]
            rows.Push(extra)
        end if
    end for
    for each r in rows
        notes = cleanNotes(r.notes, r.lang)
        ' Two tracks that look the same get numbers.
        if counts[r.key] > 1 then notes.Push("track " + r.n.ToStr())
        label = r.lang
        if notes.Count() > 0 then label = label + "  ·  " + notes.Join("  ·  ")
        options.Push({id: "sub:" + r.trackName, label: label, checked: captionsOn and currentSub = r.trackName})
    end for
    ' A subtitle file picked from elsewhere on the seedbox.
    if m.ownSubs <> invalid and LCase(Left(m.ownSubs, 4)) = "http" and not seen.DoesExist(m.ownSubs)
        options.Push({id: "subfile:" + m.ownSubs, label: subFileName(m.ownSubs), detail: "Your subtitle file", checked: true})
    end if
    options.Push({id: "subbrowse", label: "Choose a subtitle file...", detail: "From any folder on your seedbox"})
    return options
end function

' ---- A subtitle file from anywhere on the seedbox --------------------------------------

function subFileName(url as String) as String
    parts = url.Split("/")
    name = parts[parts.Count() - 1]
    if name = "" and parts.Count() > 1 then name = parts[parts.Count() - 2]
    return name.DecodeUriComponent()
end function

' The folder holding a file or folder URL (with its trailing slash).
function parentFolder(url as String) as String
    trimmed = url
    if Right(trimmed, 1) = "/" then trimmed = Left(trimmed, Len(trimmed) - 1)
    cut = 0
    for i = 1 to Len(trimmed)
        if Mid(trimmed, i, 1) = "/" then cut = i
    end for
    if cut = 0 then return url
    return Left(trimmed, cut)
end function

function seedboxRoot() as String
    root = activeSource().url
    if root <> "" and Right(root, 1) <> "/" then root = root + "/"
    return root
end function

function folderLabel(url as String) as String
    root = seedboxRoot()
    relative = url
    if root <> "" and Left(url, Len(root)) = root then relative = Mid(url, Len(root) + 1)
    path = activeSource().label
    if relative <> "" then path = path + "  /  " + (relative).DecodeUriComponent().Replace("/", "  /  ")
    return path
end function

' Opens the browser at a folder (the movie's own folder first).
sub openSubBrowser(url as Dynamic)
    if url = invalid
        if m.subBrowseUrl <> invalid then url = m.subBrowseUrl else url = parentFolder(m.queue[m.queueIndex].url)
    end if
    m.subBrowseUrl = url
    openMenu("subbrowse", "Choose a subtitle file", folderLabel(url), [{id: "none", label: "Opening..."}])
    sendCommand({action: "list", url: url})
end sub

' The folder's subtitle files first, then its folders, and the way up.
sub subBrowseListed(listing as Object)
    if m.menuId <> "subbrowse" or not m.menu.visible then return
    rows = []
    files = []
    folders = []
    if listing.error <> "" then rows.Push({id: "none", label: listing.error})
    for each e in listing.entries
        if e.isDir = true or e.kind = "folder"
            folders.Push({id: "subdir:" + e.url, label: e.name, detail: "Folder"})
        else
            dot = 0
            for i = 1 to Len(e.name)
                if Mid(e.name, i, 1) = "." then dot = i
            end for
            ext = ""
            if dot > 0 then ext = LCase(Mid(e.name, dot + 1))
            if ext = "srt" or ext = "vtt" or ext = "ass" or ext = "ssa" or ext = "sup" or ext = "idx"
                files.Push({id: "subfile:" + e.url, label: e.name, detail: UCase(ext) + " subtitles"})
            end if
        end if
    end for
    rows.Append(files)
    root = seedboxRoot()
    if m.subBrowseUrl <> root and Len(m.subBrowseUrl) > Len(root)
        up = parentFolder(m.subBrowseUrl)
        rows.Push({id: "subdir:" + up, label: "Up one folder", detail: folderLabel(up)})
    end if
    rows.Append(folders)
    if files.Count() = 0 and folders.Count() = 0 and listing.error = "" then rows.Unshift({id: "none", label: "No subtitle files or folders here"})
    m.menu.subtitle = folderLabel(m.subBrowseUrl)
    m.menu.options = rows
end sub

sub chooseSubFile(url as String)
    entry = m.queue[m.queueIndex]
    m.activeSub = url
    m.subChoice = url
    rememberSubFile(entry.url, url)
    showToast("Subtitles: " + subFileName(url))
    startOwnSubs(url, vPos())
end sub

' Picked files are remembered per movie (the 15 most recent; the Roku keeps
' little room for settings).
function subFilePicks() as Object
    raw = loadPreference("subFiles")
    if raw = "" then return []
    picks = ParseJson(raw)
    if type(picks) <> "roArray" then picks = []
    return picks
end function

function rememberedSubFile(movieUrl as String) as Dynamic
    for each p in subFilePicks()
        if p.movie = movieUrl then return p.sub
    end for
    return invalid
end function

sub rememberSubFile(movieUrl as String, subUrl as String)
    kept = [{movie: movieUrl, sub: subUrl}]
    for each p in subFilePicks()
        if p.movie <> movieUrl and kept.Count() < 15 then kept.Push(p)
    end for
    savePreference("subFiles", FormatJson(kept))
end sub

sub forgetSubFile(movieUrl as String)
    kept = []
    for each p in subFilePicks()
        if p.movie <> movieUrl then kept.Push(p)
    end for
    savePreference("subFiles", FormatJson(kept))
end sub

function audioRows() as Object
    ' Track info here but no plan yet: apply it now, then the file's own list.
    if m.audioPlan = invalid and m.queue <> invalid and m.queue.Count() > 0
        now = {}
        now[m.queue[m.queueIndex].url] = true
        playingProbed(now)
    end if
    if m.audioPlan <> invalid then return fileAudioRows()
    options = []
    audio = m.video.availableAudioTracks
    if audio = invalid then return options
    for each t in audio
        lang = languageName(t.Language)
        name = textValue(t.Name)
        if Left(name, 6) = "#uniq:" then name = Mid(name, 7)
        name = CreateObject("roRegex", "\(\d+\)$", "").ReplaceAll(name.Trim(), "")
        notes = trackNotes(name, lang)
        label = lang
        if notes.Count() > 0 then label = label + "  ·  " + notes.Join("  ·  ")
        detail = textValue(t.Format)
        currentTrack = m.video.currentAudioTrack
        if m.audioChoice <> invalid and m.audioChoice <> "" then currentTrack = m.audioChoice
        options.Push({id: "audio:" + textValue(t.Track), label: label, detail: detail, checked: currentTrack = t.Track})
    end for
    ' Tracks the file has but Roku left out of its list (often formats it
    ' says it can't decode): offered anyway so they can be tried.
    for each extra in hiddenAudioTracks(audio)
        options.Push(extra)
    end for
    if options.Count() = 0 then options.Push({id: "none", label: "No audio tracks reported", detail: "Roku hasn't listed any audio for this file"})
    return options
end function

' The probe's audio tracks Roku's own list doesn't have.
function hiddenAudioTracks(audio as Dynamic) as Object
    rows = []
    if m.queue.Count() = 0 then return rows
    info = m.probes[m.queue[m.queueIndex].url]
    if info = invalid or info.ok <> true or info.audio = invalid then return rows
    listed = 0
    if audio <> invalid then listed = audio.Count()
    if listed >= info.audio.Count() then return rows
    known = {}
    if audio <> invalid
        for each t in audio
            known[textValue(t.Track)] = true
        end for
    end if
    k = 0
    for each a in info.audio
        k = k + 1
        number = a.number
        if number = invalid or number <= 0 then number = info.video.Count() + k
        id = number.ToStr()
        if not known.DoesExist(id)
            label = languageName(a.lang)
            if textValue(a.name) <> "" and not isLanguageWord(textValue(a.name)) then label = label + "  ·  " + textValue(a.name)
            detail = textValue(a.codec)
            if a.channels <> invalid and a.channels > 0 then detail = detail + " " + channelText(a.channels)
            note = "  ·  not listed by Roku"
            if not audioPlayable(a.codec)
                if helperOn() then note = "  >  AC3 " + channelText(ac3Layout(a).channels) else note = "  ·  no sound on this TV"
            end if
            rows.Push({id: "audio:" + id, label: label, detail: detail + note, checked: m.audioChoice = id})
        end if
    end for
    return rows
end function

' The readable, useful words of a track's own description: "Original",
' "Dubtitle", "SDH", "Latinoamerica"... Parts in scripts the Roku font can't
' draw (Korean, Arabic, Thai...) and parts that only repeat the language go.
function trackNotes(description as String, lang as String) as Object
    notes = []
    if description = "" then return notes
    for each part in description.Split("|")
        clean = part.Trim().Replace("(SDH)", "SDH").Replace("(Forced)", "forced").Replace("(forced)", "forced")
        open = clean.Instr("(")
        inside = ""
        if open > 0 and Right(clean, 1) = ")"
            ' "Compatibility Track (5.1 Surround Remix)": both parts, in order.
            inside = Mid(clean, open + 2, Len(clean) - open - 2)
            clean = Left(clean, open).Trim()
        end if
        if clean <> "" and latinOnly(clean) and LCase(clean) <> LCase(lang) and not isLanguageWord(clean)
            if Instr(1, LCase(clean), "forced") > 0
                notes.Push("forced")
            else
                notes.Push(clean)
            end if
        end if
        if inside <> "" and latinOnly(inside) and not isLanguageWord(inside) then notes.Push(inside)
    end for
    return notes
end function

' Track notes without words already said: the language ("English Dub" under
' English becomes "Dub") and words an earlier note has ("English SDH PGS"
' after "PGS" becomes "SDH").
function cleanNotes(notes as Object, lang as String) as Object
    out = []
    said = {}
    said[LCase(lang)] = true
    for each note in notes
        words = []
        for each word in note.Split(" ")
            low = LCase(word)
            if low <> "" and not said.DoesExist(low) and not isLanguageWord(word) then words.Push(word)
        end for
        for each word in words
            said[LCase(word)] = true
        end for
        if words.Count() > 0 then out.Push(words.Join(" "))
    end for
    return out
end function

' True when every character is one the Roku system font can draw (Latin).
function latinOnly(text as String) as Boolean
    for i = 1 to Len(text)
        if Asc(Mid(text, i, 1)) > 591 then return false
    end for
    return true
end function

' Native language names only repeat what the English name already says.
function isLanguageWord(text as String) as Boolean
    stripped = ""
    lower = LCase(text)
    for i = 1 to Len(lower)
        c = Mid(lower, i, 1)
        if Asc(c) < 128 then stripped = stripped + c
    end for
    for each word in ["english", "deutsch", "dansk", "suomi", "filipino", "francais", "franais", "hrvatski", "magyar", "bahasa indonesia", "italiano", "bahasa malaysia", "norsk bokmal", "norsk bokml", "norsk", "nederlands", "polski", "romana", "romn", "svenska", "turkce", "trke", "espanol", "espaol", "portugues", "portugus", "cestina", "etina"]
        if stripped = word then return true
    end for
    return false
end function

function textValue(value as Dynamic) as String
    if value = invalid then return ""
    if type(value) = "roString" or type(value) = "String" then return value.Trim()
    if type(value) = "roInt" or type(value) = "Integer" then return value.ToStr()
    return ""
end function

sub playerMenuChosen(choice as Object)
    id = choice.id
    if id = "sub:off"
        if m.queue.Count() > 0 then forgetSubFile(m.queue[m.queueIndex].url)
        stopOwnSubs()
        m.video.suppressCaptions = true
        m.subPick = ""
        m.subChoice = ""
        savePreference("subLang", "off")
        showToast("Subtitles off")
    else if id = "subbrowse"
        openSubBrowser(invalid)
        return
    else if Left(id, 7) = "subdir:"
        openSubBrowser(Mid(id, 8))
        return
    else if Left(id, 8) = "subfile:"
        chooseSubFile(Mid(id, 9))
    else if Left(id, 4) = "sub:"
        track = Mid(id, 5)
        m.subPick = track
        lang = trackLanguage(m.video.availableSubtitleTracks, "TrackName", track)
        if lang = "" then lang = probeTrackLanguage(track)
        savePreference("subLang", lang)
        showToast("Subtitles: " + choice.label)
        m.activeSub = track
        m.subChoice = track
        startOwnSubs(track, vPos())
    else if Left(id, 7) = "atrack:"
        chooseFileAudio(Val(Mid(id, 8)), choice.label)
    else if Left(id, 6) = "audio:"
        m.video.audioTrack = Mid(id, 7)
        ' Roku reports the new track a moment later; show the choice now.
        m.audioChoice = Mid(id, 7)
        showToast("Audio: " + choice.label)
        savePreference("audioLang", trackLanguage(m.video.availableAudioTracks, "Track", Mid(id, 7)))
    else if id = "restart"
        m.video.seek = 0
    else if id = "mediainfo"
        showMediaInfo(m.queue[m.queueIndex].url, m.playerTitle.text)
        return
    else if id = "subs"
        openSubtitleMenu()
        return
    else if id = "audio"
        openAudioMenu()
        return
    end if
    m.area = "player"
    m.keySink.SetFocus(true)
end sub

' Puts back the viewer's last subtitle and audio languages once the file's
' tracks are known (Roku lists them after playback starts).
sub applyTrackPreferences()
    m.tracksApplied = true
    audioLang = loadPreference("audioLang")
    audio = m.video.availableAudioTracks
    if m.audioPlan <> invalid
        ' Chosen from the file's own track list (audioPlan); Roku numbers MKV
        ' tracks as the file does. A converted movie has only that track.
        if m.swapActive <> true and audio <> invalid
            want = m.audioPlan.number.ToStr()
            for each t in audio
                if t.Track = want and m.video.currentAudioTrack <> want then m.video.audioTrack = want
            end for
        end if
        audio = invalid
    end if
    if audioLang <> "" and audio <> invalid
        for each t in audio
            if languageName(t.Language) = languageName(audioLang)
                if m.video.currentAudioTrack <> t.Track then m.video.audioTrack = t.Track
                exit for
            end if
        end for
    end if
    ' A DTS / TrueHD track this Roku can't sound: move to one it can.
    if audio <> invalid
        current = invalid
        for each t in audio
            if t.Track = m.video.currentAudioTrack then current = t
        end for
        if current <> invalid
            if not audioPlayable(current.Format)
                for each t in audio
                    if audioPlayable(t.Format)
                        m.video.audioTrack = t.Track
                        m.audioChoice = t.Track
                        showToast("Audio: " + languageName(t.Language) + " (" + textValue(t.Format) + "): this TV can't play " + textValue(current.Format))
                        exit for
                    end if
                end for
            end if
        end if
    end if
    ' No MediaInfo yet for this file: find the remembered language in Roku's
    ' own track list and restart once with it named.
    if m.activeSub = invalid
        lang = loadPreference("subLang")
        subtitles = m.video.availableSubtitleTracks
        if lang <> "" and lang <> "off" and subtitles <> invalid
            for each t in subtitles
                if t.Language = lang and Instr(1, LCase(textValue(t.Description)), "forced") = 0
                    m.subPick = t.TrackName
                    m.activeSub = t.TrackName
                    m.subChoice = t.TrackName
                    startOwnSubs(t.TrackName, vPos())
                    return
                end if
            end for
        end if
    end if
end sub

function languageName(code as Dynamic) as String
    if code = invalid or code = "" then return "Unknown"
    names = {eng: "English", en: "English", spa: "Spanish", es: "Spanish", fre: "French", fra: "French", fr: "French", ger: "German", deu: "German", de: "German", ita: "Italian", it: "Italian", por: "Portuguese", pt: "Portuguese", jpn: "Japanese", ja: "Japanese", kor: "Korean", ko: "Korean", chi: "Chinese", zho: "Chinese", zh: "Chinese", rus: "Russian", ru: "Russian", dut: "Dutch", nld: "Dutch", nl: "Dutch", swe: "Swedish", sv: "Swedish", nor: "Norwegian", nob: "Norwegian", nno: "Norwegian", no: "Norwegian", dan: "Danish", da: "Danish", fin: "Finnish", fi: "Finnish", pol: "Polish", pl: "Polish", ara: "Arabic", ar: "Arabic", hin: "Hindi", hi: "Hindi", tur: "Turkish", tr: "Turkish", bul: "Bulgarian", bg: "Bulgarian", cze: "Czech", ces: "Czech", cs: "Czech", gre: "Greek", ell: "Greek", el: "Greek", heb: "Hebrew", he: "Hebrew", hrv: "Croatian", hr: "Croatian", hun: "Hungarian", hu: "Hungarian", ind: "Indonesian", id: "Indonesian", may: "Malay", msa: "Malay", ms: "Malay", fil: "Filipino", tgl: "Filipino", rum: "Romanian", ron: "Romanian", ro: "Romanian", tha: "Thai", th: "Thai", ukr: "Ukrainian", uk: "Ukrainian", vie: "Vietnamese", vi: "Vietnamese", slo: "Slovak", slk: "Slovak", sk: "Slovak", slv: "Slovenian", sl: "Slovenian", srp: "Serbian", sr: "Serbian", est: "Estonian", et: "Estonian", lav: "Latvian", lv: "Latvian", lit: "Lithuanian", lt: "Lithuanian", ice: "Icelandic", isl: "Icelandic", per: "Persian", fas: "Persian", fa: "Persian", urd: "Urdu", tam: "Tamil", tel: "Telugu", ben: "Bengali", cat: "Catalan", ca: "Catalan", baq: "Basque", eus: "Basque", glg: "Galician", afr: "Afrikaans", mal: "Malayalam", kan: "Kannada", mar: "Marathi", und: "Unknown", mul: "Multiple", zxx: "None"}
    lower = LCase(code)
    if names.DoesExist(lower) then return names[lower]
    return UCase(code)
end function

function trackLanguage(tracks as Dynamic, key as String, value as String) as String
    if tracks = invalid then return ""
    for each t in tracks
        if t[key] = value
            if t.Language <> invalid then return t.Language
        end if
    end for
    return ""
end function

function loadPreference(name as String) as String
    section = CreateObject("roRegistrySection", "boxstream")
    if section.Exists(name) then return section.Read(name)
    return ""
end function

sub savePreference(name as String, value as String)
    section = CreateObject("roRegistrySection", "boxstream")
    section.Write(name, value)
    section.Flush()
end sub

' What the player is doing right now: stream and network rates.
function liveStats() as String
    parts = []
    info = m.video.streamInfo
    if info <> invalid
        if info.measuredBitrate <> invalid and info.measuredBitrate > 0 then parts.Push("network " + (Int(info.measuredBitrate / 100000) / 10).ToStr() + " Mb/s")
        ' Only adaptive streams report a real stream rate.
        if info.streamBitrate <> invalid and info.streamBitrate > 300000 then parts.Push("stream " + (Int(info.streamBitrate / 100000) / 10).ToStr() + " Mb/s")
    end if
    if m.video.HasField("videoFormat")
        if m.video.videoFormat <> "" then parts.Push(m.video.videoFormat)
    end if
    if m.video.HasField("audioFormat")
        if m.video.audioFormat <> "" then parts.Push(m.video.audioFormat)
    end if
    return parts.Join("  ·  ")
end function

' Restarts the current file where it is (used to switch subtitles).
sub reopenAtPosition()
    position = Int(vPos())
    m.area = "player"
    m.keySink.SetFocus(true)
    openEntry(position)
end sub

' The remembered subtitle language, as Roku's name for that track in this
' file (from MediaInfo's track numbers). invalid = unknown, "" = off.
function preferredSubtitle(url as String) as Dynamic
    lang = loadPreference("subLang")
    if lang = "" then return invalid
    if lang = "off" then return ""
    info = m.probes[url]
    if info = invalid or info.ok <> true or info.subs = invalid then return invalid
    if LCase(info.container) <> "mkv" then return invalid
    ' Text in that language first, then a picture (PGS) track in it.
    picture = invalid
    for each s in info.subs
        if s.forced <> true and s.number <> invalid and s.number > 0
            if LCase(s.lang) = LCase(lang) or Left(LCase(s.lang), 2) = Left(LCase(lang), 2)
                if s.text = true then return "mkv/" + s.number.ToStr()
                if picture = invalid and Instr(1, s.codec, "PGS") > 0 then picture = "mkv/" + s.number.ToStr()
            end if
        end if
    end for
    return picture
end function

' ---- Subtitles drawn by Box://Stream -----------------------------------------------

' track: Roku's name for it ("mkv/9" inside the file, or a subtitle file's URL).
sub startOwnSubs(track as String, position as Float)
    entry = m.queue[m.queueIndex]
    m.subGen = m.subGen + 1
    m.subCues = []
    setSubText("")
    m.ownSubs = track
    ' Roku's font covers Latin, Greek and Cyrillic; other scripts get a Noto font.
    setSubFont(invalid)
    request = {gen: m.subGen, position: position, font: subtitleFontKey(track)}
    if LCase(Left(track, 4)) = "mkv/"
        request.kind = "mkv"
        request.url = entry.url
        request.track = Int(Val(Mid(track, 5)))
        request.headers = authHeaders(entry.url)
    else
        request.kind = "file"
        request.url = track
        request.headers = authHeaders(track)
    end if
    m.video.suppressCaptions = true
    m.subTask.request = request
    ' "Loading subtitles..." shows until the first lines arrive.
    m.subLoading = true
    if m.subLoadClock = invalid then m.subLoadClock = CreateObject("roTimespan")
    m.subLoadClock.Mark()
    m.subTimer.control = "start"
end sub

sub stopOwnSubs()
    if m.ownSubs = invalid then return
    m.subGen = m.subGen + 1
    m.ownSubs = invalid
    m.subLoading = false
    m.subCues = []
    setSubText("")
    showSubPicture(invalid)
    m.subTimer.control = "stop"
    m.subTask.request = {kind: "stop"}
end sub

sub onSubCues()
    data = m.subTask.cues
    if data = invalid or data.gen <> m.subGen then return
    m.subLoading = false
    if data.error <> invalid and data.error <> ""
        ' Can't read it ourselves: let Roku try to draw that track.
        track = m.ownSubs
        stopOwnSubs()
        showToast("Subtitles: " + data.error)
        if track <> invalid
            m.video.subtitleTrack = track
            m.video.suppressCaptions = false
        end if
        return
    end if
    if data.font <> invalid and data.font <> "" then setSubFont(data.font)
    if data.note <> invalid and data.note <> "" then showToast(data.note)
    if data.cues <> invalid and data.cues.Count() > 0
        for each c in data.cues
            m.subCues.Push(c)
        end for
        m.subCues.SortBy("s")
    end if
end sub

' Roku updates the position once a second; the clock fills in between.
sub onVideoPosition()
    m.posBase = vPos()
    m.posClock.Mark()
end sub

sub onSubTick()
    if m.ownSubs = invalid then return
    position = m.posBase
    if m.video.state = "playing"
        gone = m.posClock.TotalMilliseconds() / 1000
        if gone > 1.5 then gone = 1.5
        position = position + gone
    end if
    if Abs(position - m.subSent) >= 2
        m.subSent = position
        m.subTask.position = position
    end if
    ' The last line starting at or before now, plus any still showing with it.
    text = ""
    cues = m.subCues
    low = 0
    high = cues.Count()
    while low < high
        middle = Int((low + high) / 2)
        if cues[middle].s <= position then low = middle + 1 else high = middle
    end while
    shown = []
    picture = invalid
    k = low - 1
    while k >= 0 and k >= low - 4
        c = cues[k]
        if position < c.e
            if c.img <> invalid
                if picture = invalid then picture = c
            else
                shown.Unshift(c.t)
            end if
        end if
        k = k - 1
    end while
    showSubPicture(picture)
    if shown.Count() > 0 then text = shown.Join(Chr(10))
    if m.subLoading = true
        ' Still reading the track (picture subtitles take a while): say so,
        ' for up to a minute.
        if m.subLoadClock.TotalMilliseconds() < 60000 then text = "Loading subtitles..." else m.subLoading = false
    end if
    ' Load the next picture before its time comes.
    if low < cues.Count()
        upcoming = cues[low]
        if upcoming.img <> invalid and upcoming.s - position < 3
            if m.subPicNext.uri <> upcoming.img[0].path
                m.subPicNext.width = upcoming.img[0].w
                m.subPicNext.height = upcoming.img[0].h
                m.subPicNext.uri = upcoming.img[0].path
            end if
        end if
    end if
    if text <> m.subShown then setSubText(text)
    ' Above the play bar while it's showing.
    if m.overlay.visible then m.subLayer.translation = [0, -250] else m.subLayer.translation = [0, 0]
end sub

' Tracks Roku doesn't list itself: picture subtitles (PGS) inside the file,
' from MediaInfo, and .ass / .ssa / .sup files beside it.
function extraSubtitleTracks() as Object
    rows = []
    if m.queue.Count() = 0 then return rows
    entry = m.queue[m.queueIndex]
    info = m.probes[entry.url]
    if info <> invalid and info.ok = true and info.subs <> invalid and LCase(textValue(info.container)) = "mkv"
        for each s in info.subs
            ' Text tracks Roku doesn't list (WebVTT, ASS inside MKV) are read and
            ' drawn by Box://Stream too.
            if s.text = true and s.number <> invalid and s.number > 0
                notes = [textValue(s.codec)]
                if s.forced = true then notes.Push("forced")
                if textValue(s.name) <> "" and not isLanguageWord(textValue(s.name)) then notes.Push(textValue(s.name))
                rows.Push({trackName: "mkv/" + s.number.ToStr(), lang: languageName(s.lang), notes: notes})
            end if
            if Instr(1, s.codec, "VobSub") > 0 and s.number <> invalid and s.number > 0
                notes = ["DVD"]
                if s.forced = true then notes.Push("forced")
                rows.Push({trackName: "mkv/" + s.number.ToStr(), lang: languageName(s.lang), notes: notes})
            end if
            if Instr(1, s.codec, "PGS") > 0 and s.number <> invalid and s.number > 0
                notes = ["PGS"]
                if s.forced = true then notes.Push("forced")
                if textValue(s.name) <> "" and not isLanguageWord(textValue(s.name)) then notes.Push(textValue(s.name))
                rows.Push({trackName: "mkv/" + s.number.ToStr(), lang: languageName(s.lang), notes: notes})
            end if
        end for
    end if
    for each s in entry.subs
        ext = LCase(Right(s.url, 4))
        if ext = ".ass" or ext = ".ssa" or ext = ".sup" or ext = ".idx"
            notes = ["subtitle file", Mid(ext, 2)]
            if ext = ".idx" then notes = ["subtitle file", "DVD"]
            rows.Push({trackName: s.url, lang: languageName(s.lang), notes: notes})
        end if
    end for
    return rows
end function

' The language of an "mkv/N" track from MediaInfo (for tracks Roku doesn't list).
function probeTrackLanguage(track as String) as String
    if m.queue.Count() = 0 or LCase(Left(track, 4)) <> "mkv/" then return ""
    info = m.probes[m.queue[m.queueIndex].url]
    if info = invalid or info.subs = invalid then return ""
    number = Int(Val(Mid(track, 5)))
    for each s in info.subs
        if s.number = number then return textValue(s.lang)
    end for
    return ""
end function

sub setSubFont(path as Dynamic)
    ' Which characters this font can draw (see subtitleGlyphs).
    m.subGlyphs = ""
    if path <> invalid
        if Instr(1, path, "Arabic") > 0 then m.subGlyphs = "AR"
        if Instr(1, path, "Hebrew") > 0 then m.subGlyphs = "HE"
        if Instr(1, path, "Thai") > 0 then m.subGlyphs = "TH"
        if Instr(1, path, "NotoSans-Bold") > 0 then m.subGlyphs = "VI"
    end if
    if m.subShown <> invalid and m.subShown <> "" then setSubText(m.subShown)
    if path = invalid
        font = makeFont("bold", 50)
    else
        font = CreateObject("roSGNode", "Font")
        font.uri = path
        font.size = 50
    end if
    for each label in m.subLabels
        label.font = font
    end for
end sub

' Keeps only characters the Arabic / Hebrew / Thai font has (ranges read
' from the fonts' own tables), so nothing shows as an empty box.
function subtitleGlyphs(text as String, script as String) as String
    if m.glyphRanges = invalid
        m.glyphRanges = {
            AR: [32,126,160,255,272,272,305,307,309,309,320,322,338,339,352,353,376,376,381,382,402,402,567,567,699,700,710,711,728,733,768,772,775,776,778,780,789,789,807,808,960,960,1536,1540,1542,1563,1566,1697,1699,1791,1872,1919,2208,2208,2210,2220,2227,2227,2276,2302,3647,3647,7838,7838,8208,8208,8211,8213,8216,8218,8220,8222,8224,8226,8230,8230,8240,8240,8249,8250,8260,8260,8304,8304,8308,8313,8320,8329,8353,8353,8356,8356,8358,8358,8360,8366,8369,8370,8372,8373,8376,8378,8381,8381,8383,8383,8467,8467,8470,8470,8482,8482,8486,8486,8494,8494,8528,8529,8531,8542,8592,8601,8617,8618,8624,8627,8630,8631,8634,8635,8644,8644,8646,8646,8706,8706,8710,8710,8719,8719,8721,8722,8725,8725,8730,8730,8734,8734,8747,8747,8776,8776,8800,8800,8804,8805,9674,9674,9676,9676,10003,10003,10060,10060,11022,11025,60640,60640,61388,61388,64257,64258,64337,64337,64339,64341,64343,64345,64347,64349,64351,64353,64355,64357,64359,64361,64363,64365,64367,64369,64371,64373,64375,64377,64379,64381,64383,64385,64387,64387,64389,64389,64391,64391,64393,64393,64395,64395,64397,64397,64399,64401,64403,64405,64407,64409,64411,64413,64415,64415,64417,64417,64421,64421,64423,64425,64427,64429,64431,64431,64433,64449,64468,64470,64472,64472,64474,64474,64476,64476,64479,64479,64481,64481,64483,64483,64485,64489,64509,64511,64515,64516,64521,64522,64527,64528,64531,64532,64561,64562,64565,64566,64573,64574,64578,64580,64591,64592,64601,64605,64612,64613,64615,64619,64621,64625,64627,64631,64633,64635,64643,64644,64650,64651,64653,64658,64660,64662,64716,64716,64729,64729,64754,64756,64763,64766,64773,64776,64781,64784,64791,64794,64801,64804,64809,64812,64828,64831,65009,65010,65012,65012,65018,65021,65136,65140,65142,65276]
            HE: [32,126,160,255,272,272,305,307,309,309,320,322,338,339,352,353,376,376,381,382,402,402,567,567,699,700,710,711,728,733,768,772,775,776,778,780,789,789,807,808,960,960,1456,1468,1470,1471,1473,1474,1488,1514,1520,1524,3647,3647,7838,7838,8211,8212,8216,8218,8220,8222,8224,8226,8230,8230,8240,8240,8249,8250,8260,8260,8304,8304,8308,8313,8320,8329,8353,8353,8356,8356,8358,8358,8360,8366,8369,8370,8372,8373,8376,8378,8381,8381,8383,8383,8467,8467,8470,8470,8482,8482,8486,8486,8494,8494,8528,8529,8531,8542,8592,8601,8617,8618,8624,8627,8630,8631,8634,8635,8644,8644,8646,8646,8706,8706,8710,8710,8719,8719,8721,8722,8725,8725,8730,8730,8734,8734,8747,8747,8776,8776,8800,8800,8804,8805,9674,9674,10003,10003,10060,10060,11022,11025,60640,60640,61388,61388,64257,64258,64287,64288,64298,64310,64312,64316,64318,64318,64320,64321,64323,64324,64326,64335]
            TH: [32,126,160,255,272,272,305,307,309,309,320,322,338,339,352,353,376,376,381,382,402,402,567,567,699,700,710,711,727,733,771,771,817,817,847,847,960,960,3585,3642,3647,3675,7838,7838,8203,8205,8211,8212,8216,8218,8220,8222,8224,8226,8230,8230,8240,8240,8249,8250,8260,8260,8288,8288,8304,8304,8308,8313,8320,8329,8353,8353,8356,8356,8358,8358,8360,8366,8369,8370,8372,8373,8376,8378,8381,8381,8383,8383,8467,8467,8470,8470,8482,8482,8486,8486,8494,8494,8528,8529,8531,8542,8592,8601,8617,8618,8624,8627,8630,8631,8634,8635,8644,8644,8646,8646,8706,8706,8710,8710,8719,8719,8721,8722,8725,8725,8730,8730,8734,8734,8747,8747,8776,8776,8800,8800,8804,8805,9674,9674,9676,9676,9784,9784,10003,10003,10060,10060,11022,11025,60416,60427,60432,60434,60640,60640,61388,61388,64257,64258]
            VI: [32,126,160,887,890,895,900,906,908,908,910,929,931,993,1008,1327,4347,4347,6832,6848,6853,6853,6855,6862,7296,7304,7424,7673,7675,7957,7960,7965,7968,8005,8008,8013,8016,8023,8025,8025,8027,8027,8029,8029,8031,8061,8064,8116,8118,8132,8134,8147,8150,8155,8157,8175,8178,8180,8182,8190,8192,8292,8294,8305,8308,8334,8336,8348,8352,8384,8432,8432,8448,8543,8579,8580,8585,8585,8722,8722,9676,9676,11360,11391,11744,11869,42560,42655,42752,42954,42960,42961,42963,42963,42965,42969,42994,43007,43310,43310,43824,43883,64256,64262,65024,65024,65056,65071,65279,65279,65532,65533]
        }
    end if
    ranges = m.glyphRanges[script]
    if ranges = invalid then return text
    text = text.Replace(Chr(9834), "*").Replace(Chr(9835), "*")
    if script = "HE"
        text = hebrewMarks(text)
    else
        text = text.Replace(Chr(1470), "-").Replace(Chr(1523), "'").Replace(Chr(1524), Chr(34))
    end if
    out = ""
    count = ranges.Count()
    for k = 1 to Len(text)
        ch = Mid(text, k, 1)
        c = Asc(ch)
        keep = c = 10
        if not keep
            ' binary search over [first, last] pairs
            low = 0
            high = Int(count / 2) - 1
            while low <= high
                middle = Int((low + high) / 2)
                if c < ranges[middle * 2]
                    high = middle - 1
                else if c > ranges[middle * 2 + 1]
                    low = middle + 1
                else
                    keep = true
                    exit while
                end if
            end while
        end if
        if keep then out = out + ch
    end for
    return out
end function

' Inside Hebrew words, ' - " become the Hebrew geresh, maqaf and gershayim:
' plain ASCII marks break Roku's right-to-left layout of the word.
function hebrewMarks(text as String) as String
    out = ""
    n = Len(text)
    for k = 1 to n
        ch = Mid(text, k, 1)
        prev = 0
        nxt = 0
        if k > 1 then prev = Asc(Mid(text, k - 1, 1))
        if k < n then nxt = Asc(Mid(text, k + 1, 1))
        afterLetter = prev >= 1488 and prev <= 1514
        beforeLetter = nxt >= 1488 and nxt <= 1514
        if ch = "'" and afterLetter
            ch = Chr(1523)
        else if ch = Chr(34) and afterLetter and beforeLetter
            ch = Chr(1524)
        else if ch = "-" and afterLetter and beforeLetter
            ch = Chr(1470)
        end if
        out = out + ch
    end for
    return out
end function

' The font a subtitle track needs, from its language and name.
function subtitleFontKey(track as String) as String
    tracks = m.video.availableSubtitleTracks
    if tracks = invalid then tracks = []
    for each t in tracks
        if textValue(t.TrackName) = track
            lang = LCase(textValue(t.Language))
            about = textValue(t.Description)
            if lang = "kor" or lang = "ko" then return "KR"
            if lang = "jpn" or lang = "ja" then return "JP"
            if lang = "chi" or lang = "zho" or Left(lang, 2) = "zh"
                if Instr(1, about, "繁") > 0 or Instr(1, LCase(about), "trad") > 0 or Instr(1, lang, "hant") > 0 or Instr(1, lang, "tw") > 0 or Instr(1, lang, "hk") > 0 then return "TC"
                return "SC"
            end if
            if lang = "tha" or lang = "th" then return "TH"
            if lang = "ara" or lang = "ar" or lang = "per" or lang = "fas" or lang = "fa" or lang = "urd" then return "AR"
            if lang = "heb" or lang = "he" then return "HE"
            if lang = "vie" or lang = "vi" then return "VI"
            return ""
        end if
    end for
    return ""
end function

' Places a PGS picture set, scaled from the disc's frame to the screen.
sub showSubPicture(cue as Dynamic)
    key = ""
    if cue <> invalid then key = cue.img[0].path
    if key = m.subPicKey then return
    m.subPicKey = key
    for i = 0 to 1
        poster = m.subPics[i]
        if cue <> invalid and i < cue.img.Count()
            im = cue.img[i]
            if cue.vw <= 0 or cue.vh <= 0 then cue.vw = 1920 : cue.vh = 1080
            sx = 1920 / cue.vw
            sy = 1080 / cue.vh
            poster.width = im.w * sx
            poster.height = im.h * sy
            poster.translation = [im.x * sx, im.y * sy]
            poster.uri = im.path
            poster.visible = true
        else
            poster.visible = false
            poster.uri = ""
        end if
    end for
end sub



sub setSubText(text as String)
    m.subShown = text
    if m.subGlyphs <> invalid and m.subGlyphs <> "" then text = subtitleGlyphs(text, m.subGlyphs)
    for each label in m.subLabels
        label.text = text
    end for
end sub

' ---- Up next -----------------------------------------------------------------------

sub startUpNext()
    nextEntry = m.queue[m.queueIndex + 1]
    m.upNextTitle.text = nextEntry.subtitle
    if nextEntry.subtitle = "" then m.upNextTitle.text = nextEntry.title
    m.upNextSeconds = 10
    m.upNextCount.text = "Starts in 10"
    buildHintRow(m.top.FindNode("upNextHints"), [{icons: ["ok"], text: "PLAY NOW"}, {icons: ["back"], text: "STOP"}])
    m.overlay.visible = false
    m.upNext.visible = true
    m.upNextTimer.control = "start"
end sub

sub onUpNextTick()
    m.upNextSeconds = m.upNextSeconds - 1
    if m.upNextSeconds <= 0
        playNextNow()
    else
        m.upNextCount.text = "Starts in " + m.upNextSeconds.ToStr()
    end if
end sub

sub playNextNow()
    m.upNextTimer.control = "stop"
    m.upNext.visible = false
    m.queueIndex = m.queueIndex + 1
    openEntry(resumeSeconds(m.queue[m.queueIndex].url))
end sub

