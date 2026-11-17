' Settings: sources (each seedbox with its own label and login), library
' actions and information. Pages: "main", "sources", "source" (one source).

sub initSettings()
    m.settingsList = m.top.FindNode("settingsList")
    m.settingsTitle = m.top.FindNode("settingsTitle")
    m.settingsInfoTitle = m.top.FindNode("settingsInfoTitle")
    m.settingsInfo = m.top.FindNode("settingsInfo")
    m.settingsTitle.font = makeFont("bold", 52)
    m.settingsInfoTitle.font = makeFont("bold", 30)
    m.settingsInfo.font = makeFont("regular", 23)
    m.settingsList.ObserveField("itemSelected", "onSettingSelected")
    m.settingsList.ObserveField("itemFocused", "onSettingFocused")
    m.aboutPanel = m.top.FindNode("aboutPanel")
    m.supportPanel = m.top.FindNode("supportPanel")
    m.top.FindNode("supportTitle").font = makeFont("bold", 38)
    m.top.FindNode("supportSub").font = makeFont("regular", 22)
    m.top.FindNode("supportVideoHead").font = makeFont("bold", 22)
    m.top.FindNode("supportAudioHead").font = makeFont("bold", 22)
    m.top.FindNode("sideStatusText").font = makeFont("bold", 22)
    buildHintRow(m.top.FindNode("supportFooter"), [{icons: ["back"], text: "RETURN TO SETTINGS"}])
    m.top.FindNode("aboutVersion").font = makeFont("bold", 30)
    m.top.FindNode("aboutText").font = makeFont("regular", 24)
    m.top.FindNode("aboutQrLabel").font = makeFont("bold", 26)
    m.top.FindNode("aboutQrUrl").font = makeFont("regular", 20)
    buildHintRow(m.top.FindNode("aboutFooter"), [{icons: ["back"], text: "RETURN TO SETTINGS"}])
    m.settingsPage = "main"
    m.editingSource = ""
    m.testMessage = ""
end sub

sub refreshSettings()
    if m.aboutPanel.visible then hideAbout()
    if m.supportPanel.visible then hideSupport()
    m.settingsPage = "main"
    drawSettings(0)
    if helperOn() then testHelper(true)
end sub

sub drawSettings(focusIndex as Integer)
    rows = []
    if m.settingsPage = "main"
        m.settingsTitle.text = "Settings"
        source = activeSource()
        label = source.label
        if label = "" then label = "Add a source"
        rows.Push({id: "sources", title: "Sources", detail: "Your seedboxes and other servers", value: label, icon: "folder"})
        helperState = "Off"
        if helperOn()
            helperState = "On"
            if m.helperOnline = true then helperState = "Connected"
            if m.helperOnline = false then helperState = "Not reachable"
        end if
        rows.Push({id: "helper", title: "Helper (optional)", detail: "Your own server that converts audio this Roku can't play", value: helperState, icon: "settings"})
        rows.Push({id: "test", title: "Test connection", detail: "Check the active source's address and login", icon: "settings"})
        rows.Push({id: "scan", title: "Scan library now", detail: "Read every folder again and look for new files", icon: "search"})
        rows.Push({id: "clear", title: "Refresh posters and details", detail: "Look everything up again (your own art is kept)", icon: "movie"})
        rows.Push({id: "display", title: "Display", detail: "What shows on posters and screens", icon: "tv"})
        rows.Push({id: "unhide", title: "Show hidden items", detail: "Bring back everything you hid from the library", icon: "home"})
        rows.Push({id: "support", title: "This Roku can play", detail: "Video and audio formats this device supports", icon: "tv"})
        rows.Push({id: "about", title: "About Box://Stream", detail: "Version " + CreateObject("roAppInfo").GetVersion(), icon: "tv"})
    else if m.settingsPage = "sources"
        m.settingsTitle.text = "Sources"
        for each source in m.settings.sources
            value = ""
            if source.id = activeSource().id then value = "ACTIVE"
            rows.Push({id: "source:" + source.id, title: source.label, detail: hostOf(source.url), value: value, icon: "folder"})
        end for
        rows.Push({id: "add", title: "+  Add a source", detail: "Another seedbox or web folder of your files", icon: "settings"})
    else if m.settingsPage = "source"
        source = findSource(m.editingSource)
        if source = invalid
            m.settingsPage = "sources"
            drawSettings(0)
            return
        end if
        m.settingsTitle.text = source.label
        rows.Push({id: "label", title: "Label", detail: "The name shown in the top bar", value: source.label, icon: "tv"})
        rows.Push({id: "url", title: "Server address", detail: "The folder of your files, as in a web browser", value: shortText(source.url, 30), icon: "folder"})
        rows.Push({id: "user", title: "Username", detail: "Leave empty if the folder has no login", value: source.user, icon: "settings"})
        pass = ""
        if source.pass <> "" then pass = "********"
        rows.Push({id: "pass", title: "Password", detail: "Kept on this Roku only", value: pass, icon: "settings"})
        rows.Push({id: "test", title: "Test connection", detail: "Check this address and login", icon: "search"})
        rows.Push({id: "remove", title: "Remove this source", detail: "Forget its address, login and library", icon: "settings"})
    end if
    if m.settingsPage = "helper"
        m.settingsTitle.text = "Helper"
        h = m.settings.helper
        code = ""
        if h.code <> "" then code = "********"
        rows.Push({id: "hurl", title: "Address", detail: "From the helper installer, e.g. https://1-2-3-4.sslip.io", value: hostOf(h.url), icon: "settings"})
        rows.Push({id: "hcode", title: "Pairing code", detail: "The 8 letters the installer printed", value: code, icon: "settings"})
        stereo = "Off"
        if optionOn("stereoAudio") then stereo = "On"
        rows.Push({id: "opt:stereoAudio", title: "Converted audio in stereo", detail: "On: DTS / TrueHD become 2.0 (TV speakers). Off: 5.1 for surround systems", value: stereo, icon: "settings"})
        rows.Push({id: "htest", title: "Test helper", detail: "Check the address and pairing code", icon: "search"})
        rows.Push({id: "hoff", title: "Stop using the helper", detail: "Forget its address and code", icon: "settings"})
    end if
    if m.settingsPage = "display"
        m.settingsTitle.text = "Display"
        for each o in displayOptions()
            state = "Off"
            if optionOn(o.id) then state = "On"
            rows.Push({id: "opt:" + o.id, title: o.title, detail: o.detail, value: state, icon: "tv"})
        end for
    end if
    m.settingsRows = rows
    root = CreateObject("roSGNode", "ContentNode")
    for each row in rows
        node = root.CreateChild("ContentNode")
        node.AddFields({kind: "", art: false, iconColor: "0x39FF88FF", playing: false, dim: false, number: ""})
        node.title = row.title
        node.ShortDescriptionLine1 = row.detail
        if row.value <> invalid then node.ShortDescriptionLine2 = row.value
        node.HDPosterUrl = "pkg:/images/icon-" + row.icon + ".png"
    end for
    m.settingsList.content = root
    ' Rows with a two-line description are taller; fewer rows fit then.
    heights = rowHeightsFor(root, 1028, 138)
    m.settingsList.rowHeights = heights
    tallest = 138
    for each h in heights
        if h > tallest then tallest = h
    end for
    m.settingsList.numRows = Int(800 / tallest)
    if focusIndex >= rows.Count() then focusIndex = rows.Count() - 1
    if focusIndex < 0 then focusIndex = 0
    m.settingsList.jumpToItem = focusIndex
    placeScrollBar(m.settingsList, m.top.FindNode("settingsTrack"), m.top.FindNode("settingsThumb"))
    refreshSettingsInfo()
end sub

function displayOptions() as Object
    return [
        {id: "avoidUnplayableAudio", title: "Avoid DTS / TrueHD audio", detail: "Found automatically: a Roku that passes DTS to a receiver plays it as it is. Turn off only if your receiver plays DTS / TrueHD but they are still converted or avoided"}
        {id: "hideUnplayable", title: "Hide files this Roku can't play", detail: "Packed (rar / zip) parts, disc files, and video this Roku can't decode"}
        {id: "tagRes", title: "Resolution badges", detail: "1080p, 720p, 4K... on posters"}
        {id: "tagCodec", title: "Codec badges", detail: "H.264, HEVC, AV1..."}
        {id: "tagSource", title: "Source badges", detail: "Blu-Ray, Web-DL, WebRip, CAM, TS..."}
        {id: "tagHdr", title: "HDR and 10-bit badges", detail: "HDR, Dolby Vision, 10-BIT"}
        {id: "tagRemux", title: "REMUX badge", detail: "Very large files that may not stream well"}
        {id: "tagHc", title: "Hard-coded subtitles badge", detail: "HC SUBS: subtitles burned into the picture"}
        {id: "noMatch", title: "NO MATCH badge", detail: "On titles no poster or details were found for"}
        {id: "gapless", title: "Gapless albums", detail: "Play an album as one continuous stream, with no pause between songs (the next song loads before the current one ends)"},
        {id: "episodesLeft", title: "Episodes left on show posters", detail: "A number on shows you've started: how many episodes you haven't watched"}
    ]
end function

function hostOf(url as String) as String
    origin = originOf(url)
    if origin = "" then return "No address yet"
    return Mid(url, origin.Instr("://") + 4)
end function

' http:// to anything outside the home network is readable on the way.
function insecureRemote(url as String) as Boolean
    if LCase(Left(url, 7)) <> "http://" then return false
    host = LCase(Mid(url, 8))
    if Left(host, 8) = "192.168." or Left(host, 3) = "10." or Left(host, 9) = "localhost" or Left(host, 4) = "127." then return false
    if Left(host, 4) = "172."
        second = Val(Mid(host, 5, 2))
        if second >= 16 and second <= 31 then return false
    end if
    return true
end function

function shortText(text as String, limit as Integer) as String
    if Len(text) <= limit then return text
    return "…" + Right(text, limit - 1)
end function

function focusSettings() as Boolean
    m.area = "content"
    if m.aboutPanel.visible or m.supportPanel.visible
        m.keySink.SetFocus(true)
        return true
    end if
    m.settingsList.SetFocus(true)
    return true
end function

function settingsKey(key as String) as Boolean
    ' The right panel, when its text is longer than fits: Right moves in,
    ' Up/Down scroll, Left or Back come out.
    if m.infoScrolling = true
        if key = "down"
            if m.infoLast < m.infoLines.Count() - 1 then m.infoTop = m.infoTop + 1
            renderInfo()
        else if key = "up"
            if m.infoTop > 0 then m.infoTop = m.infoTop - 1
            renderInfo()
        else if key = "left" or key = "back"
            m.infoScrolling = false
            renderInfo()
            m.settingsList.SetFocus(true)
        end if
        return true
    end if
    if key = "right" and not m.aboutPanel.visible and not m.supportPanel.visible and m.infoLines <> invalid and infoTotalRows() > 18
        m.infoScrolling = true
        m.keySink.SetFocus(true)
        renderInfo()
        return true
    end if
    if m.aboutPanel.visible
        if key = "back"
            hideAbout()
            return true
        end if
        return key <> "up"
    end if
    if m.supportPanel.visible
        if key = "back" or key = "OK"
            hideSupport()
            return true
        end if
        return key <> "up"
    end if
    if key = "back"
        if m.settingsPage = "source"
            m.settingsPage = "sources"
            drawSettings(0)
            return true
        else if m.settingsPage = "sources" or m.settingsPage = "display" or m.settingsPage = "helper"
            m.settingsPage = "main"
            drawSettings(0)
            return true
        end if
    end if
    return false
end function

sub onSettingFocused()
    placeScrollBar(m.settingsList, m.top.FindNode("settingsTrack"), m.top.FindNode("settingsThumb"))
    refreshSettingsInfo()
end sub

sub refreshSettingsInfo()
    if m.settingsInfo = invalid then return
    lines = []
    title = "Library"
    focusedId = ""
    if m.settingsRows <> invalid and m.settingsList.itemFocused >= 0 and m.settingsList.itemFocused < m.settingsRows.Count() then focusedId = m.settingsRows[m.settingsList.itemFocused].id
    m.top.FindNode("sideQrGroup").visible = false
    showSideStatus(helperOn() and (focusedId = "support" or focusedId = "helper" or m.settingsPage = "helper"))
    ' Display and Helper: the highlighted row's full description, which the
    ' row itself may cut short.
    if (m.settingsPage = "display" or m.settingsPage = "helper") and focusedId <> ""
        row = m.settingsRows[m.settingsList.itemFocused]
        m.settingsInfoTitle.text = row.title
        info = [textValue(row.detail)]
        if row.value <> invalid and row.value <> ""
            info.Append(["", "Now:  " + row.value])
            if Left(row.id, 4) = "opt:" then info.Append(["", "OK switches it."])
        end if
        showInfoLines(info)
        return
    end if
    if m.settingsPage = "main" and focusedId = "about"
        showSideAbout()
        return
    end if
    if m.settingsPage = "main" and focusedId = "support" and m.supportLines <> invalid
        ' A short note here; the full list opens with OK.
        m.settingsInfoTitle.text = "This Roku can play"
        note = ["The video and audio formats this Roku plays by itself, and the ones your helper converts for it (DTS, TrueHD and FLAC above 48 kHz).", "", "OK opens the full list."]
        if not helperOn() then note = ["The video and audio formats this Roku plays by itself, and the ones an optional helper can convert for it (DTS, TrueHD and FLAC above 48 kHz).", "", "OK opens the full list."]
        showInfoLines(note)
        return
    end if
    rowInfo = invalid
    if m.settingsPage = "main" then rowInfo = mainRowInfo(focusedId)
    if rowInfo <> invalid
        title = rowInfo.title
        lines = rowInfo.lines
    else if m.settingsPage = "main"
        source = activeSource()
        if source.url = ""
            title = "Getting started"
            lines.Push("1.  Open Sources and add your seedbox.")
            lines.Push("2.  Enter the web address of the folder that holds your files: the page that lists them when you open it in a web browser.")
            lines.Push("3.  Add the username and password for that page, if it has one.")
            lines.Push("")
            lines.Push("Box://Stream reads the folders and sorts everything into Movies, TV Shows and Music, with posters, plots and cast.")
        else
            lines.Push("Source:  " + source.label)
            lines.Push(hostOf(source.url))
            lines.Push("")
            if m.library <> invalid
                lines.Push(m.library.movies.Count().ToStr() + " movies")
                lines.Push(m.library.shows.Count().ToStr() + " TV shows")
                lines.Push(m.library.albums.Count().ToStr() + " albums")
            end if
            if m.scanPhase = "scanning" or m.scanPhase = "checking" or m.scanPhase = "sorting"
                lines.Push("")
                lines.Push(m.statusLabel.text)
            end if
        end if
    else if m.settingsPage = "sources"
        title = "Sources"
        lines.Push("Add every seedbox or server you use and give each a label. Choose one to change its address and login.")
        lines.Push("")
        lines.Push("Every source feeds one library: Movies, TV Shows and Music show everything from all of them together.")
    else
        source = findSource(m.editingSource)
        title = "Source"
        if source <> invalid
            lines.Push(source.label)
            lines.Push(source.url)
            lines.Push("")
            if insecureRemote(source.url)
                lines.Push("Warning: this address uses http://, so your internet provider can see file names and your login. Use https:// if your seedbox offers it.")
                lines.Push("")
            end if
        end if
        lines.Push("Tip: on the Roku phone app you can type with your phone's keyboard.")
    end if
    if m.testMessage <> ""
        lines.Push("")
        lines.Push(m.testMessage)
    end if
    lines.Push("")
    lines.Push("Box://Stream  v" + CreateObject("roAppInfo").GetVersion())
    m.settingsInfoTitle.text = title
    showInfoLines(lines)
end sub

' The side panel for a highlighted main Settings row (Sources keeps the library
' summary below; invalid means use it).
function mainRowInfo(id as String) as Dynamic
    if id = "helper"
        lines = ["Your own small server (free on Oracle Cloud) that converts the audio this Roku can't play: DTS and TrueHD become Dolby Digital, and FLAC above 48 kHz becomes 48 kHz. Video never goes through it.", ""]
        if helperOn()
            lines.Push("Linked:  " + hostOf(m.settings.helper.url))
            if optionOn("stereoAudio") then lines.Push("Converted audio:  stereo") else lines.Push("Converted audio:  surround (5.1)")
        else
            lines.Push("Not set up. The Box://Stream README shows the one-step setup in Oracle Cloud Shell; then enter its address and pairing code here.")
        end if
        return {title: "Helper (optional)", lines: lines}
    else if id = "test"
        source = activeSource()
        lines = ["Checks that the active source's address and login work."]
        if source.url <> "" then lines.Append(["", "Source:  " + source.label, hostOf(source.url)])
        return {title: "Test connection", lines: lines}
    else if id = "scan"
        lines = ["Reads every folder again now. The library also checks for new, changed and removed files on its own when the app starts and every 30 minutes."]
        if m.library <> invalid
            lines.Append(["", m.library.movies.Count().ToStr() + " movies", m.library.shows.Count().ToStr() + " TV shows", m.library.albums.Count().ToStr() + " albums"])
        end if
        if m.scanPhase = "scanning" or m.scanPhase = "checking" or m.scanPhase = "sorting" then lines.Append(["", m.statusLabel.text])
        return {title: "Scan library now", lines: lines}
    else if id = "clear"
        return {title: "Refresh posters and details", lines: ["Looks up every title's poster, plot and cast again.", "", "Your own art and the matches you fixed are kept."]}
    else if id = "display"
        return {title: "Display", lines: ["What shows on posters and screens: badges for resolution, codec, source and HDR, episodes left, gapless albums, and which files to hide."]}
    else if id = "unhide"
        return {title: "Show hidden items", lines: ["Brings back everything you hid from Movies, TV Shows and Music."]}
    end if
    return invalid
end function

' About, in the side panel: a short version with the donation QR code; OK opens
' the full page.
sub showSideAbout()
    info = ParseJson(ReadAsciiFile("pkg:/images/about.json"))
    if info = invalid then info = {}
    version = "Version " + CreateObject("roAppInfo").GetVersion()
    if info.credit <> invalid and info.credit <> "" then version = version + "  ·  " + info.credit
    m.settingsInfoTitle.text = "About Box://Stream"
    showInfoLines([version, "", "Streams the movies, TV shows and music on your own seedbox, straight to your Roku.", "", "OK opens the full About page."])
    if info.donateQr <> invalid and info.donateQr <> ""
        m.top.FindNode("sideQr").uri = info.donateQr
        m.top.FindNode("sideQrLabel").text = textValue(info.donateLabel)
        m.top.FindNode("sideQrGroup").visible = true
    end if
end sub

sub onSettingSelected()
    index = m.settingsList.itemSelected
    if index < 0 or index >= m.settingsRows.Count() then return
    id = m.settingsRows[index].id
    m.testMessage = ""
    if id = "sources"
        m.settingsPage = "sources"
        drawSettings(0)
    else if id = "scan"
        sendCommand({action: "scan"})
        openMenu("settingsNote", "Scanning your library", "Every folder is read again. New, changed and removed files show up as they're found; the panel on the right shows the progress.", [{id: "ok", label: "OK"}])
    else if id = "test"
        if m.settingsPage = "source" and m.editingSource <> activeSource().id
            ' Test a source that isn't active: switch to it first.
            useSource(m.editingSource)
        end if
        m.testMessage = "Testing..."
        refreshSettingsInfo()
        sendCommand({action: "test"})
    else if id = "clear"
        openMenu("confirmClear", "Refresh posters and details?", "Every title's poster, plot and cast are looked up again. Your own art and the matches you fixed are kept.", [{id: "yes", label: "Refresh everything"}, {id: "no", label: "Cancel"}])
    else if id = "unhide"
        count = clearHidden()
        if count > 0
            sendCommand({action: "rebuild"})
            openMenu("settingsNote", "Hidden items are back", counted(count, "item") + " you hid show again in Movies, TV Shows and Music.", [{id: "ok", label: "OK"}])
        else
            openMenu("settingsNote", "Nothing is hidden", "Items you hide (from their More menu) come back here.", [{id: "ok", label: "OK"}])
        end if
    else if id = "support"
        showSupportPage()
    else if id = "about"
        showAbout()
    else if id = "display"
        m.settingsPage = "display"
        drawSettings(0)
    else if id = "helper"
        m.settingsPage = "helper"
        drawSettings(0)
    else if id = "hurl"
        value = m.settings.helper.url
        numbers = sslipNumbers(value)
        if value = "" or numbers <> ""
            ' The setup prints https://<numbers>.sslip.io: only the numbers are typed.
            openKeyboard("hurl", "Helper address", "Type the numbers from the address the setup printed. For a different kind of address, choose OTHER ADDRESS.", numbers, false, "ip")
        else
            openKeyboard("hurl", "Helper address", "The address of your helper.", value, false, "url")
        end if
    else if id = "hcode"
        openKeyboard("hcode", "Pairing code", "The 8 letters the helper installer printed.", m.settings.helper.code, false, "text")
    else if id = "htest"
        testHelper()
    else if id = "hoff"
        m.settings.helper = {url: "", code: ""}
        saveSettings()
        drawSettings(0)
        showToast("Helper turned off")
    else if Left(id, 4) = "opt:"
        name = Mid(id, 5)
        m.settings.options[name] = not optionOn(name)
        saveSettings()
        drawSettings(index)
        m.cards = {}
    else if Left(id, 7) = "source:"
        m.editingSource = Mid(id, 8)
        m.settingsPage = "source"
        drawSettings(0)
    else if id = "add"
        number = m.settings.sources.Count() + 1
        source = {id: CreateObject("roDateTime").AsSeconds().ToStr() + number.ToStr(), label: "Seedbox " + number.ToStr(), url: "", user: "", pass: ""}
        m.settings.sources.Push(source)
        if m.settings.sources.Count() = 1 then m.settings.active = source.id
        saveSettings()
        m.editingSource = source.id
        m.settingsPage = "source"
        drawSettings(0)
        openKeyboard("url", "Server address", "The web address of the folder with your files, for example https://myseedbox.example.com/downloads/", "https://", false, "url")
    else if id = "use"
        useSource(m.editingSource)
        drawSettings(0)
    else if id = "label"
        openKeyboard("label", "Label", "A short name for this source, shown in the top bar.", findSource(m.editingSource).label, false, "text")
    else if id = "url"
        value = findSource(m.editingSource).url
        if value = "" then value = "https://"
        openKeyboard("url", "Server address", "The web address of the folder with your files.", value, false, "url")
    else if id = "user"
        openKeyboard("user", "Username", "The login for that folder. Leave empty if there is none.", findSource(m.editingSource).user, false, "text")
    else if id = "pass"
        openKeyboard("pass", "Password", "Kept only on this Roku and sent only to this source.", findSource(m.editingSource).pass, true, "text")
    else if id = "remove"
        ' Ask first: this forgets the address and login.
        source = findSource(m.editingSource)
        label = "this source"
        if source <> invalid then label = source.label
        openMenu("removeSource", "Remove " + label + "?", "Its address and login are forgotten on this Roku.", [{id: "keep", label: "Keep it", checked: false}, {id: "remove", label: "Remove", checked: false}])
    end if
end sub

' "1-2-3-4" from https://1-2-3-4.sslip.io ("" for other addresses).
function sslipNumbers(url as String) as String
    match = CreateObject("roRegex", "^https?://(\d{1,3}-\d{1,3}-\d{1,3}-\d{1,3})\.sslip\.io/?$", "i").Match(url.Trim())
    if match.Count() > 1 then return match[1]
    return ""
end function

' This Roku's formats, with DTS and TrueHD saying what the optional helper does.
function supportLinesNow() as Object
    lines = []
    for each line in m.supportLines
        name = ""
        if Left(line, 4) = "DTS:" then name = "DTS"
        if Left(line, 13) = "Dolby TrueHD:" then name = "Dolby TrueHD"
        if name <> "" and Instr(1, line, "yes") = 0
            if helperOn() and m.helperOnline = false
                line = name + ":  your helper converts it (not reachable right now)"
            else if helperOn()
                line = name + ":  yes, converted by your helper"
            else
                line = name + ":  no  ·  yes with the optional helper"
            end if
        end if
        lines.Push(line)
        if Left(line, 5) = "FLAC:"
            ' This Roku plays FLAC above 48 kHz slowed down.
            if helperOn() and m.helperOnline = false
                lines.Push("FLAC above 48 kHz (96 / 192 kHz):  your helper converts it (not reachable right now)")
            else if helperOn()
                lines.Push("FLAC above 48 kHz (96 / 192 kHz):  yes, converted to 48 kHz by your helper")
            else
                lines.Push("FLAC above 48 kHz (96 / 192 kHz):  no (plays slowed down)  ·  yes with the optional helper")
            end if
        end if
    end for
    return lines
end function

sub settingTyped(purpose as String, text as String)
    if purpose = "hurl" or purpose = "hcode"
        if purpose = "hurl"
            text = text.Trim()
            if text = "https://" then text = ""
            if text <> "" and text.Instr("://") < 0 then text = "https://" + text
            if Right(text, 1) = "/" then text = Left(text, Len(text) - 1)
            m.settings.helper.url = text
        else
            m.settings.helper.code = UCase(text.Trim())
        end if
        saveSettings()
        drawSettings(m.settingsList.itemFocused)
        if helperOn() then testHelper()
        return
    end if
    source = findSource(m.editingSource)
    if source = invalid then return
    if purpose = "url"
        text = text.Trim()
        if text = "https://" or text = "http://" then text = ""
        if text <> "" and text.Instr("://") < 0 then text = "https://" + text
        source.url = text
    else if purpose = "label"
        if text.Trim() <> "" then source.label = text.Trim()
    else if purpose = "user"
        source.user = text.Trim()
    else if purpose = "pass"
        source.pass = text
    end if
    saveSettings()
    index = m.settingsList.itemFocused
    drawSettings(index)
    if source.id = activeSource().id and purpose <> "label"
        ' A new address or login: read the library again.
        configureServer()
        if source.url <> ""
            sendCommand({action: "scan"})
            m.testMessage = "Testing..."
            sendCommand({action: "test"})
        end if
    else if source.id = activeSource().id
        configureServer()
    end if
    refreshSettingsInfo()
end sub

sub removeSource(id as String)
    list = []
    for each source in m.settings.sources
        if source.id <> id then list.Push(source)
    end for
    wasActive = id = activeSource().id
    m.settings.sources = list
    if wasActive
        m.settings.active = ""
        if list.Count() > 0 then m.settings.active = list[0].id
    end if
    saveSettings()
    if wasActive then useSource(m.settings.active)
    m.settingsPage = "sources"
    drawSettings(0)
end sub

' About: version, where details come from, privacy, and the donation QR.
sub showAbout()
    markSelected()
    info = ParseJson(ReadAsciiFile("pkg:/images/about.json"))
    if info = invalid then info = {donateLabel: "", donateUrl: "", donateQr: "", projectUrl: ""}
    version = "Version " + CreateObject("roAppInfo").GetVersion()
    if info.credit <> invalid and info.credit <> "" then version = version + "   ·   " + info.credit
    m.top.FindNode("aboutVersion").text = version
    lines = []
    lines.Push("Streams the movies, TV shows and music on your own seedbox or web server, straight to your Roku.")
    lines.Push("")
    lines.Push("Posters and details:  IMDb data via Cinemeta (movies), TVmaze (TV, CC BY-SA), Deezer (music). Your own folder.jpg, cover and poster images always come first.")
    lines.Push("")
    lines.Push("Privacy:  your files are read from your own server and nothing is uploaded. Logins stay on this Roku and are only sent to the source they belong to. Title searches go to the services above.")
    if info.projectUrl <> invalid and info.projectUrl <> ""
        lines.Push("")
        lines.Push("Project:  " + info.projectUrl)
    end if
    ' What this Roku plays is on its own page (This Roku can play).
    m.top.FindNode("aboutText").text = lines.Join(Chr(10))
    qr = m.top.FindNode("aboutQrGroup")
    if info.donateQr <> invalid and info.donateQr <> ""
        m.top.FindNode("aboutQr").uri = info.donateQr
        m.top.FindNode("aboutQrLabel").text = info.donateLabel
        hint = "Scan with your phone"
        if info.donateHint <> invalid and info.donateHint <> "" then hint = info.donateHint
        m.top.FindNode("aboutQrUrl").text = hint + Chr(10) + info.donateUrl
        qr.visible = true
    else
        qr.visible = false
    end if
    m.settingsList.visible = false
    m.top.FindNode("settingsSide").visible = false
    m.settingsTitle.visible = false
    m.aboutPanel.visible = true
    m.keySink.SetFocus(true)
end sub

sub hideAbout()
    m.aboutPanel.visible = false
    m.settingsList.visible = true
    m.top.FindNode("settingsSide").visible = true
    m.settingsTitle.visible = true
    m.settingsList.SetFocus(true)
end sub

function yesNo(value as Boolean) as String
    if value then return "yes"
    return "no"
end function

sub onTaskTest()
    result = m.task.testResult
    m.testMessage = result.message
    if result.ok then showToast("Connected") else showToast("Connection problem")
    refreshSettingsInfo()
end sub

' Brings back everything hidden; returns how many there were.
function clearHidden() as Integer
    count = 0
    section = CreateObject("roRegistrySection", "boxstream-fixes")
    for each name in section.GetKeyList()
        fix = ParseJson(section.Read(name))
        if type(fix) = "roAssociativeArray"
            if fix.hidden = true or fix.kind = "ignore"
                section.Delete(name)
                count = count + 1
            end if
        end if
    end for
    section.Flush()
    return count
end function

sub refreshAllDetails()
    sendCommand({action: "clearMeta"})
    showToast("Looking up posters and details again...")
end sub

' The side panel's text: all of it when it fits (18 rows), otherwise a
' window of it with a note on how to scroll.
sub showInfoLines(lines as Object)
    m.infoLines = lines
    m.infoTop = 0
    m.infoScrolling = false
    renderInfo()
end sub

' Screen rows a line takes in the panel (it wraps at about 50 characters).
function rowsOf(line as String) as Integer
    n = Int((Len(line) + 49) / 50)
    if n < 1 then n = 1
    return n
end function

function infoTotalRows() as Integer
    total = 0
    for each line in m.infoLines
        total = total + rowsOf(line)
    end for
    return total
end function

sub renderInfo()
    lines = m.infoLines
    if lines = invalid then return
    m.infoLast = lines.Count() - 1
    if infoTotalRows() <= 18
        m.top.FindNode("settingsInfoHint").visible = false
        m.settingsInfo.text = lines.Join(Chr(10))
        return
    end if
    ' A window of 16 rows from infoTop, then a note on how to scroll.
    shown = []
    used = 0
    k = m.infoTop
    while k < lines.Count() and used + rowsOf(lines[k]) <= 16
        shown.Push(lines[k])
        used = used + rowsOf(lines[k])
        k = k + 1
    end while
    m.infoLast = k - 1
    hint = m.top.FindNode("settingsInfoHint")
    if m.infoScrolling = true
        buildHintRow(hint, [{icons: ["dpad-updown"], text: "SCROLL"}, {icons: ["dpad-left"], text: "BACK"}])
        hint.visible = true
    else if m.infoLast < lines.Count() - 1
        buildHintRow(hint, [{icons: ["dpad-right"], text: "MORE"}])
        hint.visible = true
    else
        hint.visible = false
    end if
    m.settingsInfo.text = shown.Join(Chr(10))
end sub

' ---- Helper (the user's own audio-converting server) --------------------------

function helperOn() as Boolean
    h = m.settings.helper
    return h <> invalid and h.url <> "" and h.code <> ""
end function

sub testHelper(quiet = false as Boolean)
    if not helperOn()
        if not quiet then showToast("Enter the helper's address and pairing code first")
        return
    end if
    m.helperQuiet = quiet
    m.helperTask = CreateObject("roSGNode", "HelperCheck")
    m.helperTask.ObserveField("result", "onHelperTested")
    m.helperTask.request = {url: m.settings.helper.url, code: m.settings.helper.code}
    m.helperTask.control = "run"
    if not quiet then showToast("Testing the helper...")
end sub

sub onHelperTested()
    r = m.helperTask.result
    if r = invalid then return
    ' A background check that fails once (often the network still waking
    ' after the app starts) is tried again before it counts.
    if r.ok <> true and m.helperQuiet = true and m.helperRetried <> true
        m.helperRetried = true
        testHelper(true)
        return
    end if
    m.helperRetried = false
    m.helperOnline = r.ok = true
    if m.helperQuiet <> true then showToast(r.error)
    ' The helper's state shows in Settings (row, side panel, This Roku can play).
    if m.view = "settings"
        if m.supportPanel.visible
            showSupportPage()
        else if m.settingsList.itemFocused >= 0
            drawSettings(m.settingsList.itemFocused)
        end if
    end if
end sub

' The green "Helper connected" line at the bottom of the side panel.
sub showSideStatus(show as Boolean)
    group = m.top.FindNode("sideStatus")
    group.visible = show
    if not show then return
    color = "0x8391AAFF"
    text = "Checking the helper..."
    if m.helperOnline = true
        color = "0x39FF88FF"
        text = "Helper connected"
    else if m.helperOnline = false
        color = "0xFFC857FF"
        text = "Helper not reachable"
    end if
    m.top.FindNode("sideStatusDot").color = color
    m.top.FindNode("sideStatusText").color = color
    m.top.FindNode("sideStatusText").text = text
end sub

' ---- This Roku can play: the full page ----------------------------------------------

sub showSupportPage()
    markSelected()
    details = CreateObject("roDeviceInfo").GetModelDetails()
    model = ""
    if details <> invalid
        if details.VendorName <> invalid then model = details.VendorName
        if details.ModelNumber <> invalid then model = (model + " " + details.ModelNumber).Trim()
    end if
    if model = "" then model = CreateObject("roDeviceInfo").GetModel()
    line = model
    if helperOn()
        if m.helperOnline = true then line = line + "   ·   Helper connected" else if m.helperOnline = false then line = line + "   ·   Helper not reachable" else line = line + "   ·   Checking the helper..."
    else
        line = line + "   ·   No helper (optional: it converts DTS, TrueHD and hi-res FLAC)"
    end if
    m.top.FindNode("supportSub").text = line
    fillSupport(m.top.FindNode("supportVideo"), "video")
    fillSupport(m.top.FindNode("supportAudio"), "audio")
    m.settingsList.visible = false
    m.top.FindNode("settingsSide").visible = false
    m.settingsTitle.visible = false
    m.supportPanel.visible = true
    m.keySink.SetFocus(true)
end sub

sub hideSupport()
    m.supportPanel.visible = false
    m.settingsList.visible = true
    m.top.FindNode("settingsSide").visible = true
    m.settingsTitle.visible = true
    m.settingsList.SetFocus(true)
end sub

' One column: each format with a badge (PLAYS, HELPER + CONNECTED, NO).
sub fillSupport(group as Object, kind as String)
    while group.GetChildCount() > 0
        group.RemoveChildIndex(0)
    end while
    if m.supportItems = invalid then return
    y = 0
    for each item in m.supportItems
        if item.group = kind
            name = group.CreateChild("Label")
            name.font = makeFont("regular", 24)
            name.color = "0xDCE4F2FF"
            name.text = item.name
            name.translation = [0, y]
            name.width = 400
            name.height = 40
            name.vertAlign = "center"
            x = 420
            if item.ok
                x = badge(group, x, y, "PLAYS", "0x39FF88FF", "0x06110AFF")
            else if item.helper = true and helperOn()
                x = badge(group, x, y, "YOUR HELPER", "0x28DCFFFF", "0x041318FF")
                if m.helperOnline = true
                    badge(group, x, y, "CONNECTED", "0x39FF88FF", "0x06110AFF")
                else if m.helperOnline = false
                    badge(group, x, y, "NOT REACHABLE", "0xFFC857FF", "0x1A1200FF")
                end if
            else if item.helper = true
                x = badge(group, x, y, "NO", "0x3A4456FF", "0xC3CDDEFF")
                note = group.CreateChild("Label")
                note.font = makeFont("regular", 20)
                note.color = "0x8391AAFF"
                note.text = "a helper can convert it"
                note.translation = [x, y]
                note.height = 40
                note.vertAlign = "center"
            else
                badge(group, x, y, "NO", "0x3A4456FF", "0xC3CDDEFF")
            end if
            y = y + 48
        end if
    end for
end sub

' A coloured badge with a word; returns the x after it.
function badge(group as Object, x as Integer, y as Integer, text as String, back as String, fore as String) as Integer
    label = group.CreateChild("Label")
    label.font = makeFont("bold", 18)
    label.text = text
    width = Int(label.BoundingRect().width) + 32
    pill = group.CreateChild("Poster")
    pill.uri = "pkg:/images/badge.9.png"
    pill.blendColor = back
    pill.translation = [x, y + 4]
    pill.width = width
    pill.height = 32
    ' The label over its badge.
    group.RemoveChild(label)
    group.AppendChild(label)
    label.color = fore
    label.translation = [x, y + 4]
    label.width = width
    label.height = 32
    label.horizAlign = "center"
    label.vertAlign = "center"
    return x + width + 10
end function
