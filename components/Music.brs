' Music: the Audio node, a playlist, and the now-playing bar at the bottom.
' Formats: MP3 (up to 320 kb/s), AAC and ALAC (.m4a), FLAC, WAV and AIFF
' (up to 24-bit), WMA, and Ogg / Opus where this Roku can decode them.

sub initMusic()
    m.audio = m.top.FindNode("audio")
    m.miniPlayer = m.top.FindNode("miniPlayer")
    m.miniArt = m.top.FindNode("miniArt")
    m.miniIcon = m.top.FindNode("miniIcon")
    m.miniTitle = m.top.FindNode("miniTitle")
    m.miniArtist = m.top.FindNode("miniArtist")
    m.miniBar = m.top.FindNode("miniBar")
    m.miniTime = m.top.FindNode("miniTime")
    m.miniTitle.font = makeFont("bold", 26)
    m.miniArtist.font = makeFont("regular", 22)
    m.miniTime.font = makeFont("regular", 22)
    m.audio.ObserveField("state", "onAudioState")
    m.audio.ObserveField("contentIndex", "onAudioTrack")
    m.musicTimer = m.top.FindNode("musicTimer")
    m.musicTimer.ObserveField("fire", "drawMini")
    m.musicTracks = []
    m.musicAlbumKey = ""
end sub

function audioFormatFor(ext as String) as String
    if ext = "mp3" then return "mp3"
    if ext = "flac" then return "flac"
    if ext = "m4a" or ext = "alac" or ext = "mp4" then return "mp4"
    if ext = "aac" then return "es.aac-adts"
    if ext = "wma" then return "wma"
    if ext = "wav" then return "wav"
    return ""
end function

sub playAlbum(album as Object, index as Integer, shuffle as Boolean)
    tracks = []
    for each t in album.tracks
        tracks.Push({url: t.url, title: t.title, ext: t.ext})
    end for
    start = index
    if shuffle
        for i = tracks.Count() - 1 to 1 step -1
            j = Rnd(i + 1) - 1
            swap = tracks[i]
            tracks[i] = tracks[j]
            tracks[j] = swap
        end for
        start = 0
    end if
    artist = album.artist
    ' The cover shown on the album page (folder art or the matched cover).
    art = largePosterFor(album)
    if art = "" then art = posterFor(album)
    playTracks(tracks, start, art, artist, album.key)
end sub

sub playTracks(tracks as Object, start as Integer, art as String, artist as String, albumKey as String)
    markSelected()
    root = CreateObject("roSGNode", "ContentNode")
    m.musicTracks = []
    for i = start to tracks.Count() - 1
        t = tracks[i]
        node = root.CreateChild("ContentNode")
        node.url = t.url
        node.title = t.title
        format = audioFormatFor(t.ext)
        if format <> "" then node.StreamFormat = format
        headers = authHeaders(t.url)
        if headers.Count() > 0 then node.HttpHeaders = headers
        m.musicTracks.Push(t)
        ' Read each track's header: its sample rate decides if it plays right.
        if m.probes[t.url] = invalid then sendCommand({action: "probe", url: t.url, ext: t.ext})
    end for
    m.musicArtist = artist
    m.musicAlbumKey = albumKey
    setArt(m.miniArt, art, "pkg:/images/poster-music.png")
    m.albumStream = false
    m.audio.control = "stop"
    m.miniPlayer.visible = true
    m.musicTimer.control = "start"
    m.rateWarned = false
    m.viaHelper = false
    if gaplessFits(tracks)
        m.albumTracks = tracks
        startAlbumStream(start)
    else
        m.audio.content = root
        m.audio.contentIsPlaylist = true
        m.audio.control = "play"
    end if
    checkTrackRates()
    drawMini()
end sub

' Hi-res tracks (88.2 kHz and up) play slowed down on Rokus that only
' handle 48 kHz: say so instead of leaving people to wonder.
sub onSlimRelay()
    address = m.slimRelay.address
    if address = "" then return
    root = CreateObject("roSGNode", "ContentNode")
    node = root.CreateChild("ContentNode")
    node.url = address
    node.title = m.slimTrack.title
    node.StreamFormat = "flac"
    m.audio.control = "stop"
    m.audio.content = root
    m.audio.control = "play"
end sub

sub checkTrackRates()
    if m.rateWarned = true or m.musicTracks = invalid then return
    for each t in m.musicTracks
        info = m.probes[t.url]
        if info <> invalid and info.audio <> invalid and info.audio.Count() > 0
            rate = info.audio[0].rate
            if rate <> invalid and rate > m.maxAudioRate
                m.rateWarned = true
                kHz = Int(rate / 100) / 10.0
                ' This TV's FLAC decoder plays 88.2 kHz and up slowed down (tested:
                ' music player, movie player and a cleaned-up stream all the same).
                if helperOn()
                    playThroughHelper()
                    return
                end if
                showToast("This track is " + Str(kHz).Trim() + " kHz / " + info.audio[0].bits.ToStr() + "-bit FLAC: this TV plays it slowed down. A 44.1 or 48 kHz copy plays correctly.")
                return
            end if
        end if
    end for
end sub

function musicActive() as Boolean
    return m.audio.state = "playing" or m.audio.state = "paused" or m.audio.state = "buffering"
end function

sub toggleMusic()
    if m.audio.state = "paused" then m.audio.control = "resume" else m.audio.control = "pause"
end sub

sub stopMusic()
    if m.audio.state <> "none" and m.audio.state <> "stopped" then m.audio.control = "stop"
    m.miniPlayer.visible = false
    m.musicTimer.control = "stop"
end sub

function isPlayingTrack(url as String) as Boolean
    if not musicActive() then return false
    index = musicIndex()
    list = m.musicTracks
    if m.albumStream = true then list = m.albumTracks
    if index < 0 or index >= list.Count() then return false
    return list[index].url = url
end function

sub onAudioState()
    state = m.audio.state
    if state = "error" then print "[music] player error "; m.audio.errorMsg; " "; m.audio.errorCode
    if state = "playing"
        ' (A seek in a gapless album restarts the stream; the bar comes back.)
        m.miniPlayer.visible = true
        m.musicTimer.control = "start"
        m.miniIcon.uri = "pkg:/images/icon-pause.png"
    else if state = "paused"
        m.miniIcon.uri = "pkg:/images/icon-play.png"
    else if state = "finished" or state = "stopped"
        ' Not while a gapless album restarts at a new point (it plays again
        ' in a moment).
        if m.albumRestarting <> true
            m.miniPlayer.visible = false
            m.musicTimer.control = "stop"
        end if
    else if state = "error"
        showToast("Can't play this track: " + m.audio.errorMsg)
    end if
    drawMini()
end sub

sub onAudioTrack()
    drawMini()
    if m.view = "details" and m.detailsItem <> invalid
        if m.detailsItem.key = m.musicAlbumKey then refreshDetails()
    end if
end sub

sub drawMini()
    index = musicIndex()
    if index >= 0 and index < m.musicTracks.Count()
        m.miniTitle.text = m.musicTracks[index].title
        artist = m.musicArtist
        ext = UCase(m.musicTracks[index].ext)
        if artist <> "" then m.miniArtist.text = artist + "   ·   " + ext else m.miniArtist.text = ext
    end if
    duration = m.audio.duration
    position = m.audio.position
    if m.albumStream = true
        if m.seekPending <> invalid
            if m.miniClock <> invalid and m.seekAt <> invalid and m.miniClock.TotalMilliseconds() - m.seekAt >= 700 then onSeekTimer()
            return
        end if
        drawAlbumStream()
        return
    end if
    ' Some FLAC files make Roku report an impossible position (26 hours into
    ' a 2-minute track): count the playing time ourselves for those.
    if m.miniClock = invalid then m.miniClock = CreateObject("roTimespan")
    now = m.miniClock.TotalMilliseconds()
    if m.ownTrack <> index
        m.ownTrack = index
        m.ownPos = 0.0
        m.ownTick = invalid
    end if
    if m.audio.state = "playing" and m.ownTick <> invalid then m.ownPos = m.ownPos + (now - m.ownTick) / 1000.0
    m.ownTick = now
    if duration > 0 and (position > duration + 2 or position < 0) then position = m.ownPos
    ' Helper streams have no length: use the track's own (from its header).
    if m.viaHelper = true and index >= 0 and index < m.musicTracks.Count()
        info = m.probes[m.musicTracks[index].url]
        if info <> invalid and info.seconds <> invalid and info.seconds > 0
            duration = info.seconds
            position = m.ownPos
        end if
    end if
    if duration > 0 and position > duration then position = duration
    if position < 0 then position = 0
    if duration > 0
        m.miniBar.width = Int(460 * position / duration)
        m.miniTime.text = clockText(position) + " / " + clockText(duration)
    else
        m.miniBar.width = 0
        m.miniTime.text = clockText(position)
    end if
end sub

' Next / previous track from anywhere outside the video player.
sub musicSkip(direction as Integer)
    if not musicActive() then return
    if m.albumStream = true
        k = musicIndex() + direction
        if k < 0 then k = 0
        if k < m.albumTracks.Count() then startAlbumStream(k)
        return
    end if
    if direction > 0
        m.audio.control = "skipcontent"
    else
        index = musicIndex()
        if index > 0
            m.audio.nextContentIndex = index - 1
            m.audio.control = "skipcontent"
        else
            m.audio.seek = 0
        end if
    end if
end sub

' Hi-res FLAC this Roku plays slowed down: the user's helper re-frames it
' (lossless, standard 4096-sample frames) and the Roku plays that instead.
sub playThroughHelper()
    index = musicIndex()
    if m.albumStream = true
        ' Hi-res goes through the helper instead of the gapless relay stream.
        m.musicTracks = m.albumTracks
        m.albumStream = false
        if m.albumRelay <> invalid then m.albumRelay.quit = true
    end if
    if index < 0 then index = 0
    h = m.settings.helper
    root = CreateObject("roSGNode", "ContentNode")
    tracks = []
    for i = index to m.musicTracks.Count() - 1
        t = m.musicTracks[i]
        node = root.CreateChild("ContentNode")
        node.url = h.url + "/flac?src=" + escapeText(t.url)
        node.title = t.title
        node.StreamFormat = "flac"
        headers = ["X-Helper-Token:" + h.code]
        for each line in authHeaders(t.url)
            cut = Instr(1, line, ":")
            if cut > 1 then headers.Push("X-Source-Auth:" + Mid(line, cut + 1).Trim())
        end for
        node.HttpHeaders = headers
        tracks.Push(t)
    end for
    m.musicTracks = tracks
    m.viaHelper = true
    m.ownTrack = -1
    m.audio.control = "stop"
    m.audio.content = root
    m.audio.contentIsPlaylist = true
    m.audio.control = "play"
    showToast("Hi-res FLAC: playing through your helper")
end sub

function escapeText(text as String) as String
    if m.escaper = invalid then m.escaper = CreateObject("roUrlTransfer")
    return m.escaper.Escape(text)
end function

' ---- Gapless albums ----------------------------------------------------------------
' The relay on this Roku serves the album as one continuous FLAC or MP3 stream
' (each next song loads while the current one plays), so there is no pause
' between songs. The banner works out the song from the songs' lengths.

function musicIndex() as Integer
    if m.albumStream = true then return m.albumIndex
    return m.audio.contentIndex
end function

function gaplessFits(tracks as Object) as Boolean
    if not optionOn("gapless") or tracks.Count() < 2 then return false
    ext = LCase(tracks[0].ext)
    if ext <> "flac" and ext <> "mp3" then return false
    for each t in tracks
        if LCase(t.ext) <> ext then return false
    end for
    return true
end function

sub startAlbumStream(k as Integer, startAt = 0.0 as Float)
    if m.albumTracks = invalid then m.albumTracks = m.musicTracks
    m.albumStream = true
    m.albumFrom = k
    m.albumIndex = k
    m.albumSkip = startAt
    m.streamPos = 0.0
    m.streamTick = invalid
    urls = []
    sizes = []
    for i = k to m.albumTracks.Count() - 1
        urls.Push(m.albumTracks[i].url)
        ' Exact sizes the relay measured before (the folder listing only
        ' gives rounded megabytes).
        size = 0
        if m.trackBytes = invalid then m.trackBytes = {}
        if m.trackBytes[m.albumTracks[i].url] <> invalid then size = m.trackBytes[m.albumTracks[i].url]
        sizes.Push(size)
    end for
    m.albumRestarting = true
    m.audio.control = "stop"
    if m.albumRelay <> invalid then m.albumRelay.quit = true
    if m.relayPort = invalid then m.relayPort = 8900
    m.relayPort = m.relayPort + 1
    if m.relayPort > 8990 then m.relayPort = 8901
    m.albumRelay = CreateObject("roSGNode", "LocalRelay")
    m.albumRelay.ObserveField("address", "onAlbumRelay")
    m.albumRelay.ObserveField("stats", "onAlbumRelayStats")
    fraction = 0.0
    length = trackSeconds(m.albumTracks[k])
    if startAt > 0 and length > 0 then fraction = startAt / length
    m.albumRelay.request = {album: urls, headers: authHeaders(urls[0]), format: LCase(m.albumTracks[k].ext), port: m.relayPort, startFraction: fraction, sizes: sizes}
    m.albumRelay.control = "run"
end sub

sub onAlbumRelay()
    address = m.albumRelay.address
    if address = "" then return
    root = CreateObject("roSGNode", "ContentNode")
    node = root.CreateChild("ContentNode")
    node.url = address
    node.title = m.albumTracks[m.albumFrom].title
    node.StreamFormat = LCase(m.albumTracks[m.albumFrom].ext)
    ' A one-item playlist (with playlist mode off Roku plays the parent node
    ' itself, which has no address).
    m.audio.contentIsPlaylist = true
    m.audio.content = root
    m.audio.control = "play"
    m.albumRestarting = false
    m.miniPlayer.visible = true
    m.musicTimer.control = "start"
    drawMini()
end sub

sub drawAlbumStream()
    if m.miniClock = invalid then m.miniClock = CreateObject("roTimespan")
    now = m.miniClock.TotalMilliseconds()
    if m.audio.state = "playing" and m.streamTick <> invalid then m.streamPos = m.streamPos + (now - m.streamTick) / 1000.0
    m.streamTick = now
    ' Which song: add up song lengths from where the stream started.
    k = m.albumFrom
    start = 0.0
    while k < m.albumTracks.Count() - 1
        length = trackSeconds(m.albumTracks[k])
        if k = m.albumFrom then length = length - m.albumSkip
        if length <= 0 or m.streamPos < start + length then exit while
        start = start + length
        k = k + 1
    end while
    if m.lastBannerLog = invalid or now - m.lastBannerLog > 5000
        m.lastBannerLog = now
    end if
    if k <> m.albumIndex
        m.albumIndex = k
        if m.view = "details" and m.detailsItem <> invalid
            if m.detailsItem.key = m.musicAlbumKey then refreshDetails()
        end if
    end if
    t = m.albumTracks[k]
    m.miniTitle.text = t.title
    ext = UCase(t.ext)
    if m.musicArtist <> "" then m.miniArtist.text = m.musicArtist + "   ·   " + ext else m.miniArtist.text = ext
    position = m.streamPos - start
    if k = m.albumFrom then position = position + m.albumSkip
    duration = trackSeconds(t)
    if duration > 0
        if position > duration then position = duration
        m.miniBar.width = Int(460 * position / duration)
        m.miniTime.text = clockText(position) + " / " + clockText(duration)
    else
        m.miniBar.width = 0
        m.miniTime.text = clockText(position)
    end if
end sub

function trackSeconds(t as Object) as Float
    info = m.probes[t.url]
    if info <> invalid and info.seconds <> invalid and info.seconds > 0 then return info.seconds
    ' Not read from the file yet: the length the album's details give.
    meta = invalid
    if m.musicAlbumKey <> invalid then meta = m.meta[m.musicAlbumKey]
    if meta <> invalid and meta.tracks <> invalid
        for each mt in meta.tracks
            if songKey(textValue(mt.title)) = songKey(t.title) and mt.seconds <> invalid then return mt.seconds
        end for
    end if
    return 0
end function

' Seek within the playing song. Gapless album streams restart at the new
' point (the relay starts that song's audio part-way in; FLAC and MP3
' decoders find the next frame on their own).
sub musicSeek(seconds as Integer)
    if not musicActive() then return
    if m.albumStream <> true
        target = m.audio.position + seconds
        if target < 0 then target = 0
        m.audio.seek = target
        return
    end if
    ' Gapless album: each restart rebuffers, so presses add up and the stream
    ' restarts once, shortly after the last one.
    t = m.albumTracks[m.albumIndex]
    length = trackSeconds(t)
    if m.seekPending = invalid then m.seekPending = currentSongPosition()
    m.seekPending = m.seekPending + seconds
    if m.seekPending < 0 then m.seekPending = 0
    if length > 0 and m.seekPending > length - 2 then m.seekPending = length - 2
    m.miniTime.text = clockText(m.seekPending) + " / " + clockText(length)
    if length > 0 then m.miniBar.width = Int(460 * m.seekPending / length)
    ' The player's regular update carries the seek out 0.7 s after the last press.
    if m.miniClock = invalid then m.miniClock = CreateObject("roTimespan")
    m.seekAt = m.miniClock.TotalMilliseconds()
end sub

sub onSeekTimer()
    if m.seekPending = invalid or m.albumStream <> true then return
    target = m.seekPending
    m.seekPending = invalid
    startAlbumStream(m.albumIndex, target)
end sub

function currentSongPosition() as Float
    start = 0.0
    for k = m.albumFrom to m.albumIndex - 1
        start = start + trackSeconds(m.albumTracks[k])
    end for
    return m.streamPos - start + m.albumSkip
end function

sub onAlbumRelayStats()
    s = m.albumRelay.stats
    if s = invalid or s.sizes = invalid or s.urls = invalid then return
    if m.trackBytes = invalid then m.trackBytes = {}
    for i = 0 to s.urls.Count() - 1
        if i < s.sizes.Count() and s.sizes[i] > 0 then m.trackBytes[s.urls[i]] = s.sizes[i]
    end for
end sub
