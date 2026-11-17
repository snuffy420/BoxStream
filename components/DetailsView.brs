' Details for a movie, show or album. Focus zones run top to bottom:
' buttons, then seasons and episodes (shows) or tracks (albums), then cast.
' The body scrolls up as focus moves down.

sub initDetails()
    m.detailsBody = m.top.FindNode("detailsBody")
    m.infoSheet = m.top.FindNode("infoSheet")
    m.infoText = m.top.FindNode("infoText")
    m.infoSubtitle = m.top.FindNode("infoSubtitle")
    m.infoText.font = makeFont("regular", 22)
    m.infoSubtitle.font = makeFont("regular", 22)
    m.top.FindNode("infoTitle").font = makeFont("bold", 36)
    buildHintRow(m.top.FindNode("infoFooter"), [{icons: ["dpad-updown"], text: "SCROLL"}, {icons: ["back"], text: "CLOSE"}])
    m.detailsPoster = m.top.FindNode("detailsPoster")
    m.detailsLogo = m.top.FindNode("detailsLogo")
    m.detailsTitle = m.top.FindNode("detailsTitle")
    m.detailsMeta = m.top.FindNode("detailsMeta")
    m.detailsGenres = m.top.FindNode("detailsGenres")
    m.detailsOverview = m.top.FindNode("detailsOverview")
    m.detailsCredits = m.top.FindNode("detailsCredits")
    m.detailsButtons = m.top.FindNode("detailsButtons")
    m.sectionA = m.top.FindNode("sectionA")
    m.sectionB = m.top.FindNode("sectionB")
    m.seasonList = m.top.FindNode("seasonList")
    m.episodeRow = m.top.FindNode("episodeRow")
    m.trackList = m.top.FindNode("trackList")
    m.castRow = m.top.FindNode("castRow")
    m.detailsFacts = m.top.FindNode("detailsFacts")
    m.bodyScroll = m.top.FindNode("bodyScroll")
    m.bodyScrollPath = m.top.FindNode("bodyScrollPath")
    m.detailsTitle.font = makeFont("bold", 64)
    m.detailsMeta.font = makeFont("bold", 26)
    m.detailsGenres.font = makeFont("regular", 24)
    m.detailsOverview.font = makeFont("regular", 27)
    m.detailsCredits.font = makeFont("regular", 23)
    m.sectionA.font = makeFont("bold", 30)
    m.sectionB.font = makeFont("bold", 30)
    m.detailsFacts.font = makeFont("regular", 23)
    m.detailsLogo.ObserveField("loadStatus", "onDetailsLogo")
    m.seasonList.ObserveField("itemFocused", "onSeasonFocused")
    m.episodeRow.ObserveField("rowItemSelected", "onEpisodeSelected")
    m.trackList.ObserveField("itemSelected", "onTrackSelected")
    m.detailsItem = invalid
    m.zone = "buttons"
    m.buttonIndex = 0
    m.buttons = []
    m.seasonIndex = 0
end sub

sub openDetails(item as Object)
    markSelected()
    ' Read the movie's file headers now so Media info is ready.
    if item.kind = "movie"
        for each f in item.files
            if m.probes[f.url] = invalid and f.playable = true then sendCommand({action: "probe", url: f.url, ext: f.ext})
        end for
    end if
    ' Each song's header gives its exact length (shown as they arrive).
    if item.kind = "album" and item.tracks <> invalid
        for each t in item.tracks
            if m.probes[t.url] = invalid then sendCommand({action: "probe", url: t.url, ext: t.ext})
        end for
    end if
    m.history.Push({view: m.view, area: m.area})
    m.detailsItem = item
    m.zone = "buttons"
    m.buttonIndex = 0
    m.seasonIndex = 0
    showView("details")
    m.detailsBody.translation = [0, 0]
    if item.kind = "show"
        nextUp = nextEpisode(item)
        if nextUp <> invalid
            for i = 0 to item.seasons.Count() - 1
                if item.seasons[i] = nextUp.season then m.seasonIndex = i
            end for
        end if
    end if
    refreshDetails()
    m.area = "content"
    focusDetails()
    deferFocus()
end sub

sub closeDetails()
    m.detailsItem = invalid
    previous = {view: "home", area: "content"}
    if m.history.Count() > 0 then previous = m.history.Pop()
    showView(previous.view)
    if previous.view = "home" then refreshHome()
    if previous.view = "grid"
        ' Redraw the cards (tags may have changed); focusGrid puts you back on
        ' the one you opened.
        m.grid.content = m.grid.content
        m.gridReturn = m.gridOpened
        deferFocus()
    end if
    m.area = previous.area
    restoreFocus()
end sub

' Redraws everything (called again when details or posters arrive).
sub refreshDetails()
    item = m.detailsItem
    if item = invalid then return
    meta = metaFor(item.key)
    ' Files say a season the matched show doesn't have: say so once.
    if item.kind = "show" and m.seasonWarned <> item.key
        missing = missingSeasons(item)
        if missing.Count() > 0
            m.seasonWarned = item.key
            showToast("Your files are Season " + missing[0].ToStr() + ", which this match doesn't have. More > Match seasons")
        end if
    end if
    setArt(m.detailsPoster, largePosterFor(item), fallbackArt(item.kind))
    albumLook(item.kind = "album")
    setBackdrop(backdropFor(item))
    m.detailsTitle.text = displayTitle(item)
    logo = ""
    if meta <> invalid
        if meta.logo <> invalid then logo = meta.logo
    end if
    if logo <> ""
        m.detailsLogo.uri = logo
        m.detailsLogo.visible = true
        m.detailsTitle.visible = false
    else
        m.detailsLogo.visible = false
        m.detailsTitle.visible = true
    end if
    m.detailsMeta.text = metaLine(item)
    genres = ""
    if meta <> invalid
        if meta.genres <> invalid then genres = meta.genres
    end if
    m.detailsGenres.text = genres
    overview = ""
    if meta <> invalid
        if meta.overview <> invalid then overview = meta.overview
    end if
    if overview = "" and item.kind = "album" then overview = albumSummary(item)
    if overview = "" and meta = invalid then overview = "Looking up details..."
    if isUnmatched(item) then overview = "No details were found for this title. Choose Fix match to search for the right one and pick it from the results."
    m.detailsOverview.text = overview
    m.detailsCredits.text = creditsText(item, meta)
    ' Credits sit under however many lines the plot took.
    plotHeight = m.detailsOverview.BoundingRect().height
    if m.detailsOverview.text = "" then plotHeight = 0
    m.detailsCredits.translation = [530, 428 + plotHeight + 16]
    buildButtons()
    if item.kind = "show"
        layoutShow(item, meta)
    else if item.kind = "album"
        layoutAlbum(item, meta)
    else
        layoutMovie(item, meta)
    end if
    focusZone(m.zone)
end sub

sub onDetailsLogo()
    if m.detailsLogo.loadStatus = "failed"
        m.detailsLogo.visible = false
        m.detailsTitle.visible = true
    end if
end sub

function creditsText(item as Object, meta as Dynamic) as String
    if meta = invalid then return ""
    lines = []
    if meta.director <> invalid and meta.director <> "" then lines.Push("Director:  " + meta.director)
    if meta.cast <> invalid and meta.cast.Count() > 0 and item.kind = "movie"
        names = []
        for each c in meta.cast
            names.Push(c.name)
            if names.Count() >= 5 then exit for
        end for
        lines.Push("Starring:  " + names.Join(", "))
    end if
    ' (Albums: the label is already in the line above the buttons.)
    return lines.Join(Chr(10))
end function

' ---- Buttons -------------------------------------------------------------------

sub buildButtons()
    item = m.detailsItem
    list = []
    if item.kind = "movie"
        file = item.files[0]
        resumeAt = resumeSeconds(file.url)
        if resumeAt > 0
            list.Push({id: "resume", label: "Resume  " + clockText(resumeAt), primary: true})
            list.Push({id: "restart", label: "From the beginning"})
        else
            list.Push({id: "play", label: "Play", primary: true})
        end if
        if item.files.Count() > 1 and item.multipart <> true then list.Push({id: "versions", label: "Versions  (" + item.files.Count().ToStr() + ")"})
        if watchedUrl(file.url) then list.Push({id: "unwatched", label: "Mark unwatched"}) else list.Push({id: "watched", label: "Mark watched"})
        list.Push({id: "mediainfo", label: "Media info"})
    else if item.kind = "show"
        nextUp = nextEpisode(item)
        if nextUp <> invalid
            verb = "Play"
            if resumeSeconds(nextUp.files[0].url) > 0 then verb = "Resume"
            if verb = "Play" and nextUp.key <> item.episodes[0].key then verb = "Continue"
            list.Push({id: "next", label: verb + "  " + episodeLabel(nextUp), primary: true})
        end if
    else if item.kind = "album"
        list.Push({id: "playAlbum", label: "Play", primary: true})
        list.Push({id: "shuffle", label: "Shuffle"})
    end if
    list.Push({id: "fix", label: "Fix match"})
    list.Push({id: "more", label: "More"})
    m.buttons = list
    m.detailsButtons.RemoveChildrenIndex(m.detailsButtons.GetChildCount(), 0)
    ' Full size when the row fits the screen; otherwise a step smaller (text,
    ' padding, gaps) so the last button isn't cut off.
    room = 1920 - 96 - m.detailsButtons.translation[0]
    sizes = [{font: 26, pad: 64, least: 170, gap: 20}, {font: 23, pad: 46, least: 136, gap: 14}, {font: 21, pad: 36, least: 112, gap: 10}]
    size = sizes[sizes.Count() - 1]
    probe = CreateObject("roSGNode", "Label")
    for each s in sizes
        probe.font = makeFont("bold", s.font)
        total = 0
        for each b in list
            probe.text = b.label
            w = probe.BoundingRect().width + s.pad
            if b.primary = true then w = w + 40
            if w < s.least then w = s.least
            total = total + w + s.gap
        end for
        if total - s.gap <= room
            size = s
            exit for
        end if
    end for
    x = 0
    font = makeFont("bold", size.font)
    for each b in list
        group = m.detailsButtons.CreateChild("Group")
        group.translation = [x, 0]
        glow = group.CreateChild("Poster")
        glow.uri = "pkg:/images/focus.9.png"
        glow.translation = [-38, -38]
        back = group.CreateChild("Poster")
        back.uri = "pkg:/images/button.9.png"
        label = group.CreateChild("Label")
        label.font = font
        label.text = b.label
        label.height = 78
        label.vertAlign = "center"
        label.horizAlign = "center"
        iconW = 0
        if b.primary = true then iconW = 40
        width = label.BoundingRect().width + size.pad + iconW
        if width < size.least then width = size.least
        label.width = width - iconW
        label.translation = [iconW, 0]
        back.width = width
        back.height = 78
        glow.width = width + 76
        glow.height = 154
        if b.primary = true
            icon = group.CreateChild("Poster")
            icon.uri = "pkg:/images/icon-play.png"
            icon.translation = [30, 22]
            icon.width = 34
            icon.height = 34
            b.icon = icon
        end if
        b.glow = glow
        b.back = back
        b.label = label
        x = x + width + size.gap
    end for
    if m.buttonIndex >= list.Count() then m.buttonIndex = 0
    drawButtons()
end sub

sub drawButtons()
    for i = 0 to m.buttons.Count() - 1
        b = m.buttons[i]
        focused = m.zone = "buttons" and i = m.buttonIndex and m.area = "content"
        if focused then b.glow.opacity = 1 else b.glow.opacity = 0
        if focused or b.primary = true then b.back.uri = "pkg:/images/button-on.9.png" else b.back.uri = "pkg:/images/button.9.png"
        if focused then b.label.color = "0xFFFFFFFF" else b.label.color = "0xC3CDDEFF"
        if b.icon <> invalid
            if focused then b.icon.blendColor = "0xFFFFFFFF" else b.icon.blendColor = "0x39FF88FF"
        end if
    end for
end sub

sub pressButton(id as String)
    item = m.detailsItem
    if id = "play" or id = "restart"
        confirmMovie(item, 0, false)
    else if id = "resume"
        confirmMovie(item, 0, true)
    else if id = "versions"
        options = []
        for i = 0 to item.files.Count() - 1
            f = item.files[i]
            detail = f.name
            value = ""
            if f.size > 0 then value = sizeText(f.size)
            label = fileTagText(f)
            if f.hevc = true and not m.canHevc then label = label + "  (needs HEVC)"
            if heavyWarning(f, runtimeOf(item)) <> "" then label = label + "  ·  may not stream"
            options.Push({id: i.ToStr(), label: label, detail: detail, value: value, checked: i = 0})
        end for
        openMenu("versions", "Versions", "Choose which copy to play.", options)
    else if id = "watched" or id = "unwatched"
        setWatched(item.files[0].url, id = "watched", item.key, "")
        refreshDetails()
    else if id = "next"
        nextUp = nextEpisode(item)
        if nextUp <> invalid then playEpisode(item, nextUp, true)
    else if id = "playAlbum"
        playAlbum(item, 0, false)
    else if id = "shuffle"
        playAlbum(item, 0, true)
    else if id = "mediainfo"
        f = item.files[0]
        showMediaInfo(f.url, displayTitle(item))
    else if id = "fix"
        startFixMatch()
    else if id = "more"
        openDetailsMenu()
    end if
end sub

' One line: "HEVC 3840x2160 10-bit HDR10 · 3 audio (English TrueHD 7.1) · 9 subtitles"
function mediaSummary(url as String) as String
    info = m.probes[url]
    if info = invalid then return ""
    if info.ok <> true then return ""
    parts = []
    if info.video.Count() > 0 then parts.Push(videoLine(info.video[0]))
    if info.audio.Count() > 0
        a = info.audio[0]
        text = audioLine(a)
        if not audioPlayable(a.codec)
            if helperOn() and LCase(Right(url, 4)) = ".mkv"
                text = text + " (converted to AC3)"
            else if silentAudio({url: url}) <> ""
                text = text + " (no sound on this TV)"
            end if
        end if
        if info.audio.Count() > 1 then text = info.audio.Count().ToStr() + " audio tracks (" + text + ")"
        parts.Push(text)
    end if
    if info.subs.Count() > 0 then parts.Push(info.subs.Count().ToStr() + " subtitle tracks inside")
    return "Media:  " + parts.Join("  ·  ")
end function

function videoLine(v as Object) as String
    parts = [v.codec]
    if v.width > 0 then parts.Push(v.width.ToStr() + "×" + v.height.ToStr())
    if v.fps > 0 then parts.Push(fpsText(v.fps) + " fps")
    if v.bits >= 10 then parts.Push(v.bits.ToStr() + "-bit")
    if v.hdr <> "" then parts.Push(v.hdr)
    return parts.Join("  ")
end function

function fpsText(fps as Float) as String
    rounded = Int(fps * 1000 + 0.5) / 1000
    text = rounded.ToStr()
    return text
end function

function audioLine(a as Object) as String
    parts = []
    if a.lang <> invalid and a.lang <> "" then parts.Push(languageName(a.lang))
    parts.Push(a.codec)
    if a.channels > 0 then parts.Push(channelText(a.channels))
    if a.bits <> invalid and a.bits > 0 and (a.codec = "FLAC" or a.codec = "PCM" or a.codec = "ALAC") then parts.Push(a.bits.ToStr() + "-bit")
    if a.rate <> invalid and a.rate > 0 then parts.Push((Int(a.rate / 100) / 10).ToStr() + " kHz")
    if a.kbps <> invalid and a.kbps > 0
        if a.vbr = true then parts.Push("VBR") else parts.Push(a.kbps.ToStr() + " kb/s")
    end if
    return parts.Join(" ")
end function

function channelText(channels as Integer) as String
    if channels = 1 then return "mono"
    if channels = 2 then return "stereo"
    if channels = 6 then return "5.1"
    if channels = 8 then return "7.1"
    return channels.ToStr() + " ch"
end function

' Media info: a MediaInfo-style sheet (General, Video, Chapters). Audio and
' subtitle tracks have their own pickers, so only their count is shown here.
sub showMediaInfo(url as String, title as String)
    nfoLook(false)
    m.mediaInfoUrl = url
    m.mediaInfoTitle = title
    info = m.probes[url]
    lines = []
    if info = invalid
        sendCommand({action: "probe", url: url, ext: LCase(fileExtOf(url))})
        lines.Push("Reading the file...")
    else if info.ok <> true
        lines.Push("No media info.")
        lines.Push(info.error)
    else
        lines.Append(mediaInfoLines(info, url))
    end if
    if m.area = "player" or m.view = "details" or m.area = "menu"
        live = ""
        if m.player.visible then live = liveStats()
        if live <> ""
            lines.Push("")
            lines.Push("NOW PLAYING")
            lines.Push("    " + live)
        end if
    end if
    m.infoText.text = lines.Join(Chr(10))
    m.infoSubtitle.text = title
    m.infoScroll = 0
    m.infoText.translation = [0, 0]
    if not m.infoSheet.visible
        if m.area = "menu"
            m.menu.visible = false
            m.area = m.menuReturn
        end if
        m.infoReturn = m.area
        m.infoSheet.visible = true
        m.area = "info"
        m.keySink.SetFocus(true)
        markSelected()
    end if
end sub

function mediaInfoLines(info as Object, url as String) as Object
    lines = []
    g = info.general
    if g = invalid then g = {}
    lines.Push("GENERAL")
    format = info.container
    if format = "MKV" then format = "Matroska"
    if g.doctype = "webm" then format = "WebM"
    if g.version <> invalid then format = format + "  (version " + g.version.ToStr() + ")"
    lines.Push(field("Format", format))
    if info.sizeMb > 0 then lines.Push(field("File size", sizeText(info.sizeMb)))
    if info.seconds > 0 then lines.Push(field("Duration", longDuration(info.seconds)))
    ' info.bitrate is in megabits per second.
    if info.bitrate > 0 then lines.Push(field("Overall bit rate", bitrateText(info.bitrate * 1000000)))
    if g.title <> invalid and g.title <> "" then lines.Push(field("Title", g.title))
    if g.writer <> invalid and g.writer <> "" then lines.Push(field("Writing application", g.writer))
    if g.muxer <> invalid and g.muxer <> "" then lines.Push(field("Writing library", g.muxer))
    lines.Push(field("File name", fileNameOf(url)))

    n = 1
    for each v in info.video
        lines.Push("")
        if info.video.Count() > 1 then lines.Push("VIDEO " + n.ToStr()) else lines.Push("VIDEO")
        codec = v.codec
        if codec = "H.264" then codec = "AVC (H.264)"
        if codec = "HEVC" then codec = "HEVC (H.265)"
        lines.Push(field("Format", codec))
        if v.profile <> invalid and v.profile <> "" then lines.Push(field("Profile", v.profile))
        if v.codecId <> invalid and v.codecId <> "" then lines.Push(field("Codec ID", v.codecId))
        if v.width > 0
            size = v.width.ToStr() + " × " + v.height.ToStr() + " pixels"
            lines.Push(field("Size", size))
            lines.Push(field("Display aspect ratio", aspectText(v)))
        end if
        if v.fps > 0 then lines.Push(field("Frame rate", fpsText(v.fps) + " fps"))
        bits = 8
        if v.bits > 0 then bits = v.bits
        lines.Push(field("Bit depth", bits.ToStr() + " bits"))
        if v.interlaced = 1 then lines.Push(field("Scan type", "Interlaced"))
        if v.interlaced = 2 then lines.Push(field("Scan type", "Progressive"))
        if v.hdr <> "" then lines.Push(field("HDR", v.hdr))
        if v.primaries = 9 then lines.Push(field("Color primaries", "BT.2020"))
        if v.primaries = 1 then lines.Push(field("Color primaries", "BT.709"))
        if v.range = 1 then lines.Push(field("Color range", "Limited"))
        if v.range = 2 then lines.Push(field("Color range", "Full"))
        if v.maxCll <> invalid and v.maxCll > 0 then lines.Push(field("Max content light", v.maxCll.ToStr() + " cd/m²"))
        if v.maxFall <> invalid and v.maxFall > 0 then lines.Push(field("Max frame average light", v.maxFall.ToStr() + " cd/m²"))
        if v.lang <> invalid and v.lang <> "" and v.lang <> "und" then lines.Push(field("Language", languageName(v.lang)))
        n = n + 1
    end for
    encoder = ""
    if g.encoder <> invalid then encoder = g.encoder
    if encoder <> ""
        lines.Push(field("Writing library", encoderName(encoder)))
        settings = encoderSettings(encoder)
        if settings <> "" then lines.Push(field("Encoding settings", settings))
    end if

    if info.audio.Count() + info.subs.Count() > 0
        lines.Push("")
        lines.Push("TRACKS")
        lines.Push(field("Audio", counted(info.audio.Count(), "track") + "  (choose under Audio)"))
        lines.Push(field("Subtitles", counted(info.subs.Count(), "track") + "  (choose under Subtitles)"))
    end if

    if info.chapters <> invalid and info.chapters.Count() > 0
        lines.Push("")
        lines.Push("CHAPTERS")
        for each c in info.chapters
            name = c.name
            if name = "" then name = "Chapter"
            lines.Push("    " + clockText(c.t) + "     " + name)
        end for
    end if
    if info.partial = true
        lines.Push("")
        lines.Push("Part of the header was past what was read; some details may be missing.")
    end if
    return lines
end function

function field(name as String, value as String) as String
    return "    " + name + ":   " + value
end function

function counted(n as Integer, noun as String) as String
    if n = 1 then return "1 " + noun
    return n.ToStr() + " " + noun + "s"
end function

function longDuration(seconds as Float) as String
    total = Int(seconds)
    h = Int(total / 3600)
    mins = Int((total mod 3600) / 60)
    secs = total mod 60
    if h > 0 then return h.ToStr() + " h " + mins.ToStr() + " min"
    return mins.ToStr() + " min " + secs.ToStr() + " s"
end function

function bitrateText(bitsPerSecond as Float) as String
    if bitsPerSecond >= 1000000 then return (Int(bitsPerSecond / 10000) / 100).ToStr() + " Mb/s"
    return Int(bitsPerSecond / 1000).ToStr() + " kb/s"
end function

function aspectText(v as Object) as String
    w = v.width
    h = v.height
    if v.displayWidth <> invalid and v.displayWidth > 0 and v.displayHeight > 0
        w = v.displayWidth
        h = v.displayHeight
    end if
    if h = 0 then return ""
    ratio = w / h
    if Abs(ratio - 16 / 9) < 0.02 then return "16:9"
    if Abs(ratio - 4 / 3) < 0.02 then return "4:3"
    if Abs(ratio - 2.39) < 0.04 then return "2.39:1"
    if Abs(ratio - 2.35) < 0.02 then return "2.35:1"
    if Abs(ratio - 1.85) < 0.02 then return "1.85:1"
    if Abs(ratio - 2.0) < 0.02 then return "2.00:1"
    return (Int(ratio * 100) / 100).ToStr() + ":1"
end function

function fileNameOf(url as String) as String
    clean = url
    q = clean.Instr("?")
    if q >= 0 then clean = Left(clean, q)
    parts = clean.Split("/")
    return (parts[parts.Count() - 1]).DecodeUriComponent()
end function

' "x264 - core 148 r2746 95846cf - H.264/MPEG-4 AVC codec - ... - options: cabac=1 ..."
function encoderName(note as String) as String
    cut = note.Instr(" - H.26")
    if cut < 0 then cut = note.Instr(" - options")
    name = note
    if cut > 0 then name = Left(note, cut)
    return name.Replace(" - ", " ").Trim()
end function

' The settings that matter most to quality, from the full option list.
function encoderSettings(note as String) as String
    at = note.Instr("options:")
    if at < 0 then return ""
    options = Mid(note, at + 9).Trim()
    keep = []
    rc = ""
    for each pair in options.Split(" ")
        bits = pair.Split("=")
        if bits.Count() = 2
            k = bits[0]
            v = bits[1]
            if k = "rc" then rc = v
            if k = "crf" then keep.Push("CRF " + v)
            if k = "bitrate" then keep.Push(v + " kb/s")
            if k = "ref" then keep.Push(v + " ref frames")
            if k = "bframes" then keep.Push(v + " B-frames")
            if k = "me" then keep.Push("motion " + v)
            if k = "subme" then keep.Push("subme " + v)
            if k = "keyint" then keep.Push("keyint " + v)
            if k = "vbv_maxrate" then keep.Push("max " + v + " kb/s")
        end if
    end for
    if rc = "2pass" then keep.Unshift("2-pass")
    if rc = "crf" and keep.Count() = 0 then keep.Unshift("CRF")
    if rc = "abr" then keep.Unshift("average bitrate")
    return keep.Join("  ·  ")
end function

sub closeMediaInfo()
    m.infoSheet.visible = false
    m.mediaInfoUrl = invalid
    m.area = m.infoReturn
    if m.area = invalid or m.area = "info" then m.area = "content"
    restoreFocus()
    if m.area = "player" then openPlayerMenu()
end sub

function infoKey(key as String) as Boolean
    if key = "back"
        closeMediaInfo()
    else if key = "down"
        height = m.infoText.BoundingRect().height
        if height + m.infoScroll > 800 then m.infoScroll = m.infoScroll - 120
        m.infoText.translation = [0, m.infoScroll]
    else if key = "up"
        m.infoScroll = m.infoScroll + 120
        if m.infoScroll > 0 then m.infoScroll = 0
        m.infoText.translation = [0, m.infoScroll]
    end if
    return true
end function

function fileExtOf(url as String) as String
    clean = url
    q = clean.Instr("?")
    if q >= 0 then clean = Left(clean, q)
    dot = -1
    i = clean.Instr(".")
    while i >= 0
        dot = i
        i = clean.Instr(i + 1, ".")
    end while
    if dot < 0 then return ""
    return Mid(clean, dot + 2)
end function

function fileTagText(f as Object) as String
    parts = fileTags(f)
    parts.Push(UCase(f.ext))
    return parts.Join("  ·  ")
end function

sub versionChosen(choice as Object)
    index = Val(choice.id)
    confirmMovie(m.detailsItem, index, resumeSeconds(m.detailsItem.files[index].url) > 0)
end sub

' Very large files ask first: play anyway, or pick another version.
sub confirmMovie(item as Object, index as Integer, resume as Boolean)
    ' A file this Roku can't decode (4K H.264 on a 1080p Roku, HEVC): say so,
    ' and offer a copy that does play.
    f = item.files[index]
    if not canPlayFile(f) and item.multipart <> true
        m.pendingPlay = {item: item, index: index, resume: resume}
        options = []
        for i = 0 to item.files.Count() - 1
            if i <> index and canPlayFile(item.files[i])
                options.Push({id: "other:" + i.ToStr(), label: "Play the " + fileTagText(item.files[i]) + " version"})
                exit for
            end if
        end for
        options.Push({id: "play", label: "Try anyway"})
        options.Push({id: "cancel", label: "Cancel"})
        openMenu("heavy", "This Roku can't play this file", unplayableReason(f), options)
        return
    end if
    silent = silentAudio(f)
    ' With a helper, DTS / TrueHD MKVs play with the audio converted.
    if silent <> "" and helperOn() and LCase(f.ext) = "mkv" then silent = ""
    if silent <> "" and item.multipart <> true and m.pendingSilentOk <> f.url
        m.pendingPlay = {item: item, index: index, resume: resume}
        m.pendingSilentOk = f.url
        options = [{id: "play", label: "Play anyway (no sound)"}]
        if item.files.Count() > 1 then options.Push({id: "versions", label: "Choose another version"})
        options.Push({id: "cancel", label: "Cancel"})
        openMenu("heavy", "No sound on this TV", "This file's audio is " + silent + ". This Roku can't decode it or pass it on, so the picture would play silently. A version with Dolby Digital, AAC or FLAC audio will have sound.", options)
        return
    end if
    warning = heavyWarning(item.files[index], runtimeOf(item))
    if warning = "" or item.multipart = true
        playMovie(item, index, resume)
        return
    end if
    m.pendingPlay = {item: item, index: index, resume: resume}
    options = [{id: "play", label: "Play anyway"}]
    if item.files.Count() > 1 then options.Push({id: "versions", label: "Choose another version"})
    options.Push({id: "cancel", label: "Cancel"})
    openMenu("heavy", "Very large file", warning, options)
end sub

sub heavyChosen(choice as Object)
    pending = m.pendingPlay
    if pending = invalid then return
    if choice.id = "play"
        playMovie(pending.item, pending.index, pending.resume)
    else if Left(choice.id, 6) = "other:"
        playMovie(pending.item, Int(Val(Mid(choice.id, 7))), pending.resume)
    else if choice.id = "versions"
        pressButton("versions")
    end if
end sub

' ---- Sections ------------------------------------------------------------------

sub layoutMovie(item as Object, meta as Dynamic)
    m.sectionA.visible = false
    m.seasonList.visible = false
    m.episodeRow.visible = false
    m.trackList.visible = false
    hasCast = fillCast(meta)
    m.sectionB.translation = [96, 800]
    m.castRow.translation = [18, 816]
    m.sectionB.text = "Cast"
    facts = []
    if meta <> invalid
        if meta.released <> invalid and meta.released <> "" then facts.Push("Released:  " + meta.released)
        if meta.country <> invalid and meta.country <> "" then facts.Push("Country:  " + meta.country)
        if meta.writer <> invalid and meta.writer <> "" then facts.Push("Writer:  " + meta.writer)
        if meta.awards <> invalid and meta.awards <> "" then facts.Push("Awards:  " + meta.awards)
    end if
    for each f in item.files
        line = "File:  " + fileTagText(f)
        if f.group <> invalid and f.group <> "" then line = line + "  ·  Group: " + f.group
        if f.size > 0 then line = line + "  ·  " + sizeText(f.size)
        if f.part > 0 then line = line + "  ·  Part " + f.part.ToStr()
        if f.subtitles <> invalid and f.subtitles.Count() > 0
            langs = []
            for each s in f.subtitles
                langs.Push(s.name.Replace(" - file", ""))
            end for
            line = line + "  ·  Subtitle files: " + langs.Join(", ")
        end if
        if f.playable = false then line = line + "  ·  This Roku can't play this format"
        if f.hevc = true and not m.canHevc then line = line + "  ·  HEVC: this Roku can't decode it"
        facts.Push(line)
        warning = heavyWarning(f, runtimeOf(item))
        if warning <> "" then facts.Push("        Warning: " + warning)
        summary = mediaSummary(f.url)
        if summary <> "" then facts.Push("        " + summary)
        facts.Push("        " + f.name)
    end for
    m.detailsFacts.text = facts.Join(Chr(10))
    if hasCast
        m.detailsFacts.translation = [96, 1190]
    else
        m.sectionB.visible = false
        m.detailsFacts.translation = [96, 800]
    end if
    m.zones = ["buttons"]
    if hasCast then m.zones.Push("cast")
end sub

sub layoutShow(item as Object, meta as Dynamic)
    m.trackList.visible = false
    m.sectionA.visible = true
    m.seasonList.visible = true
    m.episodeRow.visible = true
    m.sectionA.translation = [96, 800]
    m.sectionA.text = "Episodes"
    root = CreateObject("roSGNode", "ContentNode")
    for each season in item.seasons
        node = root.CreateChild("ContentNode")
        node.AddFields({kind: "", art: false, iconColor: "", playing: false, dim: false, number: ""})
        count = 0
        for each e in item.episodes
            if e.season = season then count = count + 1
        end for
        if season = 0 then node.title = "Specials" else node.title = "Season " + season.ToStr()
        if item.episodes.Count() > 0
            if item.episodes[0].dated = true then node.title = season.ToStr()
        end if
        node.ShortDescriptionLine1 = count.ToStr() + " episodes"
    end for
    m.seasonList.numColumns = 7
    m.seasonList.content = root
    if m.seasonIndex >= item.seasons.Count() then m.seasonIndex = 0
    m.seasonList.jumpToItem = m.seasonIndex
    fillEpisodes()
    hasCast = fillCast(meta)
    m.sectionB.text = "Cast"
    m.sectionB.translation = [96, 1420]
    m.castRow.translation = [18, 1436]
    m.sectionB.visible = hasCast
    facts = []
    if meta <> invalid
        if meta.network <> invalid and meta.network <> "" then facts.Push("Network:  " + meta.network)
        if meta.status <> invalid and meta.status <> "" then facts.Push("Status:  " + meta.status)
        if meta.runtime <> invalid and meta.runtime <> "" then facts.Push("Episode length:  " + meta.runtime)
    end if
    facts.Push("On your source:  " + item.episodes.Count().ToStr() + " episodes in " + item.seasons.Count().ToStr() + " seasons")
    m.detailsFacts.text = facts.Join(Chr(10))
    if hasCast then m.detailsFacts.translation = [96, 1800] else m.detailsFacts.translation = [96, 1420]
    m.zones = ["buttons", "seasons", "episodes"]
    if hasCast then m.zones.Push("cast")
end sub

sub fillEpisodes()
    item = m.detailsItem
    if item.seasons.Count() = 0 then return
    season = item.seasons[m.seasonIndex]
    root = CreateObject("roSGNode", "ContentNode")
    row = root.CreateChild("ContentNode")
    m.episodeList = []
    for each e in item.episodes
        if e.season = season
            m.episodeList.Push(e)
            node = row.CreateChild("ContentNode")
            node.AddFields({progress: 0.0, watched: false})
            info = episodeInfo(item, e)
            name = episodeName(item, e)
            node.title = e.episode.ToStr() + ".  " + name
            if e.dated = true then node.title = name
            parts = [episodeLabel(e)]
            still = e.still
            overview = ""
            if info <> invalid
                if info.airdate <> "" then parts.Push(info.airdate)
                if info.runtime <> "" then parts.Push(info.runtime + "m")
                if info.rating <> "" then parts.Push(info.rating + " / 10")
                if still = "" then still = info.still
                overview = info.overview
            end if
            if e.files.Count() > 1 then parts.Push(e.files.Count().ToStr() + " versions")
            node.ShortDescriptionLine1 = parts.Join("  ·  ")
            node.Description = overview
            node.HDPosterUrl = still
            node.progress = progressFor(e.files[0].url)
            node.watched = watchedUrl(e.files[0].url)
        end if
    end for
    m.episodeRow.content = root
end sub

sub onSeasonFocused()
    index = m.seasonList.itemFocused
    if index < 0 or m.detailsItem = invalid then return
    if index <> m.seasonIndex
        m.seasonIndex = index
        fillEpisodes()
    end if
end sub

sub onEpisodeSelected()
    selected = m.episodeRow.rowItemSelected
    if selected = invalid or m.episodeList = invalid then return
    index = selected[1]
    if index < 0 or index >= m.episodeList.Count() then return
    episode = m.episodeList[index]
    if episode.files.Count() > 1
        ' Two copies of this episode (720p and 1080p, say): ask which.
        m.pendingEpisode = episode
        options = []
        for i = 0 to episode.files.Count() - 1
            f = episode.files[i]
            value = ""
            if f.size > 0 then value = sizeText(f.size)
            label = fileTagText(f)
            if f.hevc = true and not m.canHevc then label = label + "  (needs HEVC)"
            options.Push({id: i.ToStr(), label: label, detail: f.name, value: value, checked: i = 0})
        end for
        openMenu("epversions", "Versions", episodeLabel(episode) + "  ·  " + episodeName(m.detailsItem, episode), options)
        return
    end if
    playEpisode(m.detailsItem, episode, true)
end sub

sub openEpisodeMenu(episode as Object)
    m.menuEpisode = episode
    options = [{id: "play", label: "Play from the beginning"}]
    if watchedUrl(episode.files[0].url) or resumeSeconds(episode.files[0].url) > 0
        options.Push({id: "unwatched", label: "Mark unwatched", detail: "Clears where you stopped"})
    end if
    if not watchedUrl(episode.files[0].url) then options.Push({id: "watched", label: "Mark watched"})
    options.Push({id: "mediainfo", label: "Media info", detail: "Format, video, audio and encoder details of this episode's file"})
    openMenu("episode", episodeLabel(episode), episodeName(m.detailsItem, episode), options)
end sub

sub episodeMenuChosen(choice as Object)
    episode = m.menuEpisode
    item = m.detailsItem
    if episode = invalid or item = invalid then return
    if choice.id = "play"
        playEpisode(item, episode, false)
        return
    end if
    if choice.id = "mediainfo"
        showMediaInfo(episode.files[0].url, displayTitle(item) + "  ·  " + episodeLabel(episode))
        return
    end if
    setWatched(episode.files[0].url, choice.id = "watched", item.key, episode.key)
    refreshDetails()
end sub

sub layoutAlbum(item as Object, meta as Dynamic)
    m.sectionA.visible = false
    m.seasonList.visible = false
    m.episodeRow.visible = false
    m.sectionB.visible = false
    m.castRow.visible = false
    m.trackList.visible = true
    m.trackList.translation = [96, 560]
    m.trackList.itemSize = [1728, 96]
    m.trackList.numRows = 4
    durations = {}
    if meta <> invalid and meta.tracks <> invalid
        for each t in meta.tracks
            key = songKey(textValue(t.title))
            if not durations.DoesExist(key) then durations[key] = t.seconds
        end for
    end if
    root = CreateObject("roSGNode", "ContentNode")
    i = 0
    for each t in item.tracks
        node = root.CreateChild("ContentNode")
        node.AddFields({kind: "track", art: false, iconColor: "", playing: false, dim: false, number: ""})
        number = t.number
        if number = 0 then number = i + 1
        node.number = number.ToStr()
        node.title = t.title
        format = UCase(t.ext)
        if t.disc > 0 then format = "Disc " + t.disc.ToStr() + "  ·  " + format
        node.ShortDescriptionLine1 = format
        ' The file's own length, else the album details' (by title, then by
        ' position when the song counts agree).
        seconds = invalid
        info = m.probes[t.url]
        if info <> invalid and info.seconds <> invalid and info.seconds > 0 then seconds = info.seconds
        if seconds = invalid then seconds = durations[songKey(t.title)]
        if seconds = invalid and meta <> invalid and meta.tracks <> invalid and meta.tracks.Count() = item.tracks.Count() then seconds = meta.tracks[i].seconds
        if seconds <> invalid then node.ShortDescriptionLine2 = clockText(seconds)
        node.playing = isPlayingTrack(t.url)
        i = i + 1
    end for
    ' Rebuilt while open (library refresh, a song starting): keep your place.
    keep = -1
    if m.trackListKey = item.key then keep = m.trackList.itemFocused
    m.trackList.content = root
    m.trackListKey = item.key
    if keep > 0 and keep < root.GetChildCount() then m.trackList.jumpToItem = keep
    facts = []
    formats = {}
    for each t in item.tracks
        formats[UCase(t.ext)] = true
    end for
    facts.Push("On your source:  " + item.tracks.Count().ToStr() + " tracks  ·  " + formats.Keys().Join(", "))
    m.detailsFacts.text = facts.Join(Chr(10))
    m.detailsFacts.translation = [96, 800 + item.tracks.Count() * 108 + 30]
    m.zones = ["buttons", "tracks", "player"]
end sub

sub onTrackSelected()
    index = m.trackList.itemSelected
    if index >= 0 and m.detailsItem <> invalid then playAlbum(m.detailsItem, index, false)
end sub

function fillCast(meta as Dynamic) as Boolean
    if meta = invalid or meta.cast = invalid or meta.cast.Count() = 0
        m.castRow.visible = false
        return false
    end if
    root = CreateObject("roSGNode", "ContentNode")
    row = root.CreateChild("ContentNode")
    for each c in meta.cast
        node = row.CreateChild("ContentNode")
        node.title = c.name
        node.ShortDescriptionLine1 = c.role
        node.HDPosterUrl = c.photo
    end for
    m.castRow.content = root
    m.castRow.visible = true
    m.sectionB.visible = true
    return true
end function

' ---- Focus zones -----------------------------------------------------------------

function focusDetails() as Boolean
    m.area = "content"
    focusZone(m.zone)
    return true
end function

sub focusZone(zone as String)
    if m.zones = invalid then return
    found = false
    for each z in m.zones
        if z = zone then found = true
    end for
    if not found then zone = "buttons"
    m.zone = zone
    scroll = 0
    item = m.detailsItem
    m.top.FindNode("miniFocus").visible = zone = "player"
    m.top.FindNode("miniHints").visible = zone = "player"
    ' Hints sit inside the bar (between the song title and the progress line)
    ' while it has focus; the title narrows to make room.
    if zone = "player"
        m.keySink.SetFocus(true)
        buildHintRow(m.top.FindNode("miniHints"), [{icons: ["dpad-leftright"], text: "15 SEC"}, {icons: ["ok"], text: "PAUSE"}, {icons: ["rewind", "forward"], text: "SONG"}, {icons: ["dpad-up"], text: "SONGS"}])
        m.top.FindNode("miniTitle").width = 290
        m.top.FindNode("miniArtist").width = 290
    else
        m.top.FindNode("miniTitle").width = 900
        m.top.FindNode("miniArtist").width = 900
    end if
    if zone = "buttons"
        m.keySink.SetFocus(true)
    else if zone = "seasons"
        m.seasonList.SetFocus(true)
        scroll = -480
    else if zone = "episodes"
        m.episodeRow.SetFocus(true)
        scroll = -480
    else if zone = "tracks"
        m.trackList.SetFocus(true)
        scroll = -420
        if item <> invalid and item.kind = "album" then scroll = 0
    else if zone = "cast"
        m.castRow.SetFocus(true)
        if item.kind = "show" then scroll = -1000 else scroll = -380
    end if
    ' A refresh while a dialog is open (e.g. the file's info arriving) leaves
    ' the dialog focused.
    if m.area = "menu"
        m.menu.SetFocus(true)
    else if m.area = "keyboard"
        m.keyboard.SetFocus(true)
    else if m.area <> "content"
        m.keySink.SetFocus(true)
    end if
    current = m.detailsBody.translation
    if current[1] <> scroll
        m.bodyScrollPath.keyValue = [current, [0, scroll]]
        m.bodyScroll.control = "start"
    end if
    drawButtons()
end sub

sub moveZone(delta as Integer)
    index = 0
    for i = 0 to m.zones.Count() - 1
        if m.zones[i] = m.zone then index = i
    end for
    index = index + delta
    if index < 0 or index >= m.zones.Count() then return
    focusZone(m.zones[index])
end sub

function detailsKey(key as String) as Boolean
    ' Music playing: Left / Right seek 15 s in the song, Play/Pause toggles
    ' (the track list keeps REW / FF for paging; Roku's list takes those).
    if m.zone = "player"
        if key = "up" or key = "back"
            focusZone("tracks")
        else if key = "left"
            musicSeek(-15)
        else if key = "right"
            musicSeek(15)
        else if key = "OK" or key = "play"
            toggleMusic()
        else if key = "fastforward"
            musicSkip(1)
        else if key = "rewind"
            musicSkip(-1)
        end if
        return true
    end if
    if m.zone = "tracks" and key = "down" and musicActive() and m.detailsItem <> invalid and m.detailsItem.kind = "album"
        focusZone("player")
        return true
    end if
    if musicActive() and m.detailsItem <> invalid and m.detailsItem.kind = "album"
        if m.zone = "tracks" and (key = "left" or key = "right")
            if key = "right" then musicSeek(15) else musicSeek(-15)
            return true
        end if
        if key = "play" and m.zone <> "buttons"
            toggleMusic()
            return true
        end if
    end if
    if key = "back"
        if m.zone <> "buttons"
            focusZone("buttons")
        else
            closeDetails()
        end if
        return true
    end if
    if key = "options"
        ' On an episode: that episode's options; elsewhere: the title's.
        if m.zone = "episodes" and m.episodeList <> invalid
            focused = m.episodeRow.rowItemFocused
            if focused <> invalid and focused[1] >= 0 and focused[1] < m.episodeList.Count()
                openEpisodeMenu(m.episodeList[focused[1]])
                return true
            end if
        end if
        openDetailsMenu()
        return true
    end if
    if key = "play" and m.zone = "buttons"
        pressButton(m.buttons[0].id)
        return true
    end if
    if m.zone = "buttons"
        if key = "left"
            if m.buttonIndex > 0 then m.buttonIndex = m.buttonIndex - 1
            drawButtons()
            return true
        else if key = "right"
            if m.buttonIndex < m.buttons.Count() - 1 then m.buttonIndex = m.buttonIndex + 1
            drawButtons()
            return true
        else if key = "OK"
            pressButton(m.buttons[m.buttonIndex].id)
            return true
        else if key = "down"
            moveZone(1)
            return true
        else if key = "up"
            return false
        end if
        return true
    end if
    if key = "up"
        moveZone(-1)
        return true
    else if key = "down"
        moveZone(1)
        return true
    end if
    return false
end function

' ---- More menu, fix match, change type, hide ------------------------------------

sub openDetailsMenu()
    item = m.detailsItem
    if item = invalid then return
    options = []
    options.Push({id: "fix", label: "Fix match", detail: "Search for the right title and use its poster and details"})
    if item.kind = "movie" then options.Push({id: "type", label: "This is a TV episode", detail: "Move it to TV Shows"})
    if item.kind = "show" then options.Push({id: "seasons", label: "Match seasons", detail: "When your files' season numbers aren't the show's"})
    if item.kind = "show" then options.Push({id: "watchedAll", label: "Mark all episodes watched"})
    if item.kind = "show" then options.Push({id: "unwatchedAll", label: "Mark all episodes unwatched"})
    if item.nfo <> invalid and item.nfo <> "" then options.Push({id: "nfo", label: "View NFO", detail: "The release notes file in this folder"})
    options.Push({id: "refresh", label: "Refresh details", detail: "Look this title up again"})
    options.Push({id: "hide", label: "Hide from library", detail: "Settings can bring hidden items back"})
    openMenu("details", displayTitle(item), "", options)
end sub

sub detailsMenuChosen(choice as Object)
    item = m.detailsItem
    if item = invalid then return
    if choice.id = "nfo"
        m.nfoTitle = displayTitle(item)
        sendCommand({action: "nfo", url: item.nfo})
        showToast("Opening NFO...")
    else if choice.id = "fix"
        startFixMatch()
    else if choice.id = "seasons"
        startSeasonMatch()
    else if choice.id = "type"
        for each f in item.files
            saveFix("file:" + f.url, {kind: "episode", title: displayTitle(item)})
        end for
        sendCommand({action: "rebuild"})
        showToast("Moved to TV Shows")
        closeDetails()
    else if choice.id = "hide"
        saveFix(item.key, {hidden: true})
        sendCommand({action: "rebuild"})
        showToast("Hidden: " + displayTitle(item))
        closeDetails()
    else if choice.id = "refresh"
        sendCommand({action: "applyMatch", kind: item.kind, key: item.key, id: currentMatchId(item)})
        showToast("Refreshing details...")
    else if choice.id = "watchedAll" or choice.id = "unwatchedAll"
        for each e in item.episodes
            setWatched(e.files[0].url, choice.id = "watchedAll", item.key, e.key)
        end for
        refreshDetails()
    end if
end sub

function currentMatchId(item as Object) as String
    meta = metaFor(item.key)
    if meta <> invalid
        if meta.id <> invalid then return meta.id
    end if
    return ""
end function

sub startFixMatch()
    item = m.detailsItem
    hint = "Type the right title. For movies, adding the year helps."
    if item.kind = "album" then hint = "Type the artist and album."
    query = displayTitle(item)
    if item.kind = "album" then query = item.artist + " " + item.title
    openKeyboard("fix", "Fix match", hint, query, false, "text")
end sub

sub fixTyped(text as String)
    item = m.detailsItem
    if item = invalid or text.Trim() = "" then return
    sendCommand({action: "candidates", kind: item.kind, query: text, key: item.key})
    showToast("Searching...")
end sub

sub onTaskCandidates()
    result = m.task.candidates
    if m.detailsItem = invalid or result.key <> m.detailsItem.key then return
    if result.results.Count() = 0
        showToast("No matches for " + Chr(34) + result.query + Chr(34))
        return
    end if
    options = []
    for each r in result.results
        options.Push({id: r.id, label: r.title, detail: r.year, art: r.poster, kind: m.detailsItem.kind, suggestion: r.suggestion})
    end for
    openMenu("candidates", "Choose the right match", Chr(34) + result.query + Chr(34), options)
end sub

sub candidateChosen(choice as Object)
    item = m.detailsItem
    if item = invalid then return
    sendCommand({action: "applyMatch", kind: item.kind, key: item.key, id: choice.id, suggestion: choice.suggestion})
    showToast("Matched: " + choice.label)
end sub

' Match seasons: pick a season in the files, then the show's season it is.
sub startSeasonMatch()
    item = m.detailsItem
    meta = metaFor(item.key)
    if meta = invalid or meta.episodes = invalid or meta.episodes.Count() = 0
        showToast("No episode list for this show yet. Use Fix match first.")
        return
    end if
    seasons = fileSeasons(item)
    if seasons.Count() = 1
        openSeasonMap(seasons[0])
        return
    end if
    options = []
    for each s in seasons
        mapped = mappedSeason(item, s)
        value = ""
        if mapped <> s then value = "is Season " + mapped.ToStr()
        options.Push({id: s.ToStr(), label: "Season " + s.ToStr() + " in your files", value: value})
    end for
    openMenu("seasonPick", "Match seasons", "Which season in your files?", options)
end sub

function fileSeasons(item as Object) as Object
    seen = {}
    list = []
    for each e in item.episodes
        if e.dated <> true and not seen.DoesExist(e.season.ToStr())
            seen[e.season.ToStr()] = true
            list.Push(e.season)
        end if
    end for
    list.Sort()
    return list
end function

sub openSeasonMap(fileSeason as Integer)
    item = m.detailsItem
    meta = metaFor(item.key)
    if meta = invalid then return
    m.seasonFile = fileSeason
    current = mappedSeason(item, fileSeason)
    options = []
    for each s in metaSeasonList(meta)
        first = meta.episodes[s.season.ToStr() + ":1"]
        detail = s.count.ToStr() + " episodes"
        if first <> invalid
            if first.name <> invalid and first.name <> "" then detail = detail + "  ·  1. " + first.name
        end if
        options.Push({id: s.season.ToStr(), label: "Season " + s.season.ToStr(), detail: detail, checked: s.season = current})
    end for
    openMenu("seasonMap", "Your Season " + fileSeason.ToStr() + " is...", displayTitle(item), options)
end sub

sub seasonMapChosen(choice as Object)
    item = m.detailsItem
    if item = invalid or m.seasonFile = invalid then return
    map = {}
    for each k in seasonMap(item)
        map[k] = seasonMap(item)[k]
    end for
    map[m.seasonFile.ToStr()] = Int(Val(choice.id))
    saveFix(item.key, {seasons: map})
    m.seasonMaps.Delete(item.key)
    showToast("Your Season " + m.seasonFile.ToStr() + " now uses the show's Season " + choice.id)
    refreshDetails()
end sub

sub typeChosen(choice as Object)
end sub

' Viewer fixes live in the registry; the worker reads them on every rebuild.
sub saveFix(key as String, fields as Object)
    section = CreateObject("roRegistrySection", "boxstream-fixes")
    name = urlKey(key)
    fix = {key: key}
    if section.Exists(name)
        existing = ParseJson(section.Read(name))
        if type(existing) = "roAssociativeArray" then fix = existing
    end if
    for each k in fields
        fix[k] = fields[k]
    end for
    fix.key = key
    section.Write(name, FormatJson(fix))
    section.Flush()
end sub

' NFO text: fixed width, no wrapping, no gaps between lines, so the ASCII
' art (box and block characters) joins up as it was drawn.
sub onTaskNfo()
    result = m.task.nfoText
    if result = invalid or m.detailsItem = invalid then return
    text = result.text
    if result.ok <> true or text = "" then text = "Couldn't open this NFO file."
    nfoLook(true)
    ' Blank lines at the top of an NFO would just push the art down.
    while Left(text, 1) = Chr(10)
        text = Mid(text, 2)
    end while
    m.infoText.text = text
    m.infoSubtitle.text = m.nfoTitle + "  ·  NFO"
    m.infoScroll = 0
    m.infoText.translation = [0, 0]
    if not m.infoSheet.visible
        if m.area = "menu"
            m.menu.visible = false
            m.area = m.menuReturn
        end if
        m.infoReturn = m.area
        m.infoSheet.visible = true
        m.area = "info"
        m.keySink.SetFocus(true)
        markSelected()
    end if
end sub

sub nfoLook(on as Boolean)
    if on
        if m.nfoFont = invalid
            m.nfoFont = CreateObject("roSGNode", "Font")
            m.nfoFont.uri = "pkg:/fonts/DejaVuSansMono.ttf"
            m.nfoFont.size = 17
        end if
        if m.infoFont = invalid then m.infoFont = m.infoText.font
        m.infoText.font = m.nfoFont
        ' Wrapping stays on (a Roku label without it shows one line); 80
        ' columns of this font fit the panel, so NFO lines never wrap.
        m.infoText.lineSpacing = -3
        m.top.FindNode("infoTitle").text = "NFO"
        m.infoText.color = "0xDCE4F2FF"
    else if m.infoFont <> invalid
        m.infoText.font = m.infoFont
        m.infoText.lineSpacing = 6
        m.top.FindNode("infoTitle").text = "Media info"
        m.infoText.color = "0xC3CDDEFF"
    end if
end sub

' Albums: a square cover, text and buttons tightened up under the title, all
' fixed; only the songs scroll (with fades), above the player bar. Movies and
' shows keep the tall poster layout.
sub albumLook(on as Boolean)
    poster = m.detailsPoster
    bezel = m.top.FindNode("detailsBezel")
    glow = m.top.FindNode("detailsGlow")
    x = 530
    if on
        poster.width = 300
        poster.height = 300
        bezel.width = 314
        bezel.height = 314
        glow.width = 384
        glow.height = 384
        x = 440
    else
        poster.width = 360
        poster.height = 540
        bezel.width = 374
        bezel.height = 554
        glow.width = 444
        glow.height = 624
    end if
    m.detailsTitle.translation = [x, 186]
    m.top.FindNode("detailsLogo").translation = [x, 176]
    if on
        m.top.FindNode("detailsMeta").translation = [x, 278]
        m.top.FindNode("detailsGenres").translation = [x, 318]
        m.top.FindNode("detailsOverview").translation = [x, 356]
        m.top.FindNode("detailsOverview").maxLines = 1
        m.top.FindNode("detailsCredits").visible = false
        m.detailsButtons.translation = [x, 412]
    else
        m.top.FindNode("detailsMeta").translation = [x, 340]
        m.top.FindNode("detailsGenres").translation = [x, 382]
        m.top.FindNode("detailsOverview").translation = [x, 428]
        m.top.FindNode("detailsOverview").maxLines = 3
        m.top.FindNode("detailsCredits").visible = true
        m.detailsButtons.translation = [x, 660]
    end if
    m.top.FindNode("trackFadeTop").visible = on
    m.top.FindNode("trackFadeBottom").visible = on
end sub
