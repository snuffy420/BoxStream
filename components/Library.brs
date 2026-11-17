' The library as the screens see it: items by key, their details (meta) as they
' arrive, cards (ContentNodes) that update when posters come in, and resume
' points / watched marks kept in the registry.

sub initLibrary()
    m.library = invalid
    m.items = {}
    m.items.SetModeCaseSensitive()
    m.meta = {}
    m.meta.SetModeCaseSensitive()
    m.cards = {}
    m.cards.SetModeCaseSensitive()
    m.scanPhase = ""
    m.probes = {}
    m.probes.SetModeCaseSensitive()
    loadResume()
end sub

sub onTaskStatus()
    status = m.task.status
    m.scanPhase = status.phase
    if status.phase = "ready"
        setStatus(status.message)
    else if status.phase = "error"
        setStatus("")
        showToast(status.message)
    else
        setStatus(status.message)
    end if
    if m.view = "home" and m.library = invalid then refreshHome()
    if m.view = "settings" then refreshSettingsInfo()
end sub

sub onTaskLibrary()
    library = m.task.library
    m.library = library
    m.items = {}
    m.items.SetModeCaseSensitive()
    for each listName in ["movies", "shows", "albums"]
        for each item in library[listName]
            m.items[item.key] = item
        end for
    end for
    ' Rebuild whatever is on screen (details keep their place).
    if m.view = "home"
        refreshHome()
    else if m.view = "grid"
        showGrid(m.gridKind)
    else if m.view = "search"
        refreshSearch()
    else if m.view = "settings"
        refreshSettingsInfo()
    else if m.view = "details" and m.detailsItem <> invalid
        if m.items.DoesExist(m.detailsItem.key) then m.detailsItem = m.items[m.detailsItem.key]
    end if
end sub

sub onTaskMeta()
    batch = m.task.metaBatch
    if batch = invalid then return
    for each meta in batch
        m.meta[meta.key] = meta
        cards = m.cards[meta.key]
        if cards <> invalid
            item = m.items[meta.key]
            if item <> invalid
                for each card in cards
                    card.HDPosterUrl = posterFor(item)
                    card.ShortDescriptionLine1 = cardSubtitle(item)
                    if isUnmatched(item)
                        if card.badge = "" and optionOn("noMatch") then card.badge = "NO MATCH"
                    else if card.badge = "NO MATCH"
                        card.badge = ""
                    end if
                end for
            end if
        end if
        if m.heroKey = meta.key then showHero(m.items[meta.key])
        if m.view = "details" and m.detailsItem <> invalid
            if m.detailsItem.key = meta.key then refreshDetails()
        end if
    end for
end sub

' Looked up but nothing matched: the viewer can fix it with Fix match.
function isUnmatched(item as Object) as Boolean
    meta = m.meta[item.key]
    if meta = invalid then return false
    ' Singles and DJ mixes are rarely in music databases: no NO MATCH tag.
    if item.kind = "album" and item.tracks <> invalid
        if isSingleOrMix(item) then return false
    end if
    return meta.ok <> true
end function

' A song title reduced for matching against album details: lower case, no
' bracketed extras, no "feat." or " - Remastered" part, letters and digits.
function songKey(title as String) as String
    t = LCase(title)
    t = CreateObject("roRegex", "[\(\[][^\)\]]*[\)\]]", "").ReplaceAll(t, " ")
    t = CreateObject("roRegex", "\s(feat\.?|ft\.?|featuring)\s.*$", "").ReplaceAll(t, "")
    t = CreateObject("roRegex", "\s-\s.*(remaster|version|edit|mix|mono|stereo).*$", "").ReplaceAll(t, "")
    t = CreateObject("roRegex", "[^a-z0-9]", "").ReplaceAll(t, "")
    ' A title that is all brackets ("[Intro]") keeps its words; titles in
    ' other scripts have no a-z left and match as written.
    if t = "" then t = CreateObject("roRegex", "[^a-z0-9]", "").ReplaceAll(LCase(title), "")
    if t = "" then t = LCase(title.Trim())
    return t
end function

' MediaInfo results arrive by file URL.
sub onTaskProbes()
    batch = m.task.probeBatch
    if batch = invalid then return
    changed = {}
    for each p in batch
        m.probes[p.url] = p.info
        changed[p.url] = true
    end for
    if m.musicTracks <> invalid then checkTrackRates()
    playingProbed(changed)
    ' An album page open: song lengths from the files fill in.
    if m.view = "details" and m.detailsItem <> invalid and m.detailsItem.kind = "album" and m.detailsItem.tracks <> invalid
        for each t in m.detailsItem.tracks
            if changed.DoesExist(t.url)
                layoutAlbum(m.detailsItem, metaFor(m.detailsItem.key))
                exit for
            end if
        end for
    end if
    ' Cards whose tags gain a resolution, 10-bit or HDR from the file itself.
    for each key in m.cards
        item = m.items[key]
        if item <> invalid and item.kind = "movie"
            if changed.DoesExist(item.files[0].url)
                for each card in m.cards[key]
                    card.tags = cardTags(item.files[0])
                end for
            end if
        end if
    end for
    if m.view = "details" and m.detailsItem <> invalid then refreshDetails()
    if m.mediaInfoUrl <> invalid
        if changed.DoesExist(m.mediaInfoUrl) then showMediaInfo(m.mediaInfoUrl, m.mediaInfoTitle)
    end if
end sub

' Tags from the name, completed from MediaInfo: a resolution when the name
' has none, 10-BIT and HDR / DV when the file says so.
function fileTags(f as Object) as Object
    tags = []
    if f.tags <> invalid then tags.Append(f.tags)
    info = m.probes[f.url]
    if info = invalid or info.ok <> true then return tags
    if info.video = invalid or info.video.Count() = 0 then return tags
    v = info.video[0]
    has = {}
    for each t in tags
        has[t] = true
    end for
    hasRes = false
    for each t in tags
        if (Right(t, 1) = "p" and Val(t) > 0) or t = "4K" or t = "8K" or t = "2K" then hasRes = true
    end for
    hasCodec = has.DoesExist("HEVC") or has.DoesExist("H.264") or has.DoesExist("AV1") or has.DoesExist("XviD")
    out = []
    if not hasRes and v.height > 0 then out.Push(heightLabel(v.height, v.width))
    for each t in tags
        out.Push(t)
        if (Right(t, 1) = "p" and Val(t) > 0) or t = "4K" or t = "8K" or t = "2K"
            if v.hdr = "Dolby Vision" and not has.DoesExist("DV") then out.Push("DV")
            if (v.hdr = "HDR10" or v.hdr = "HLG") and not has.DoesExist("HDR") then out.Push("HDR")
            if v.bits >= 10 and not has.DoesExist("10-BIT") then out.Push("10-BIT")
        end if
    end for
    if not hasRes
        if v.hdr = "Dolby Vision" and not has.DoesExist("DV") then out.Push("DV")
        if (v.hdr = "HDR10" or v.hdr = "HLG") and not has.DoesExist("HDR") then out.Push("HDR")
        if v.bits >= 10 and not has.DoesExist("10-BIT") then out.Push("10-BIT")
    end if
    ' The codec from the file when the name doesn't say.
    if not hasCodec
        codec = v.codec
        if Left(codec, 4) = "HEVC" then codec = "HEVC"
        if Left(codec, 7) = "MPEG-4 " then codec = "XviD"
        out.Push(codec)
    end if
    return out
end function

function heightLabel(height as Integer, width as Integer) as String
    ' Wide films are short: 1920x800 is still 1080p.
    if width >= 4000 then return "4K"
    if width >= 3200 or height >= 1800 then return "2160p"
    if width >= 1990 and width < 3200 then return "2K"
    if width >= 1800 or height >= 900 then return "1080p"
    if width >= 1200 or height >= 650 then return "720p"
    if height >= 540 then return "576p"
    if height >= 440 then return "480p"
    if height >= 330 then return "360p"
    return "240p"
end function

function cardTags(f as Object) as String
    return tagsText(fileTags(f))
end function

' A show's badges from all its episodes: every resolution it has (highest
' first), each codec, and the source most episodes come from.
function showCardTags(show as Object) as String
    rank = {"8K": 90, "4K": 80, "2160p": 70, "1440p": 60, "2K": 50, "1080p": 40, "720p": 30, "576p": 20, "480p": 15, "SD": 12, "360p": 10, "240p": 5}
    resolutions = {}
    codecs = []
    seenCodec = {}
    sources = {}
    extras = {}
    for each episode in show.episodes
        for each f in episode.files
            for each t in fileTags(f)
                kind = tagOption(t)
                if kind = "tagRes"
                    resolutions[t] = true
                else if kind = "tagCodec"
                    if t <> "DD" and t <> "DD+" and t <> "DTS" and t <> "DTS-HD" and t <> "TrueHD" and t <> "ATMOS" and not seenCodec.DoesExist(t)
                        seenCodec[t] = true
                        codecs.Push(t)
                    end if
                else if kind = "tagSource"
                    if not sources.DoesExist(t) then sources[t] = 0
                    sources[t] = sources[t] + 1
                else
                    extras[t] = true
                end if
            end for
        end for
    end for
    list = []
    ordered = []
    for each r in resolutions
        value = rank[r]
        if value = invalid then value = Val(r) / 100
        ordered.Push({t: r, k: 1000 - value})
    end for
    ordered.SortBy("k")
    for each r in ordered
        list.Push(r.t)
    end for
    for each t in extras
        list.Push(t)
    end for
    for each c in codecs
        list.Push(c)
    end for
    best = ""
    for each s in sources
        if best = "" or sources[s] > sources[best] then best = s
    end for
    if best <> "" then list.Push(best)
    return tagsText(list)
end function

' Shown badges, filtered by Settings > Display, in one order on every poster.
function tagsText(tags as Object) as String
    shown = []
    for each t in tags
        if t <> "DD" and t <> "DD+" and t <> "DTS" and t <> "DTS-HD" and t <> "TrueHD" and t <> "ATMOS"
            if optionOn(tagOption(t)) then shown.Push(t)
        end if
    end for
    ' Same order on every poster: resolution, HDR, codec, source, the rest.
    order = {tagRes: 0, tagHdr: 1, tagHc: 2, tagCodec: 3, tagSource: 4, tagRemux: 5}
    ranked = []
    for i = 0 to shown.Count() - 1
        rank = order[tagOption(shown[i])]
        if rank = invalid then rank = 6
        ranked.Push({t: shown[i], k: rank * 100 + i})
    end for
    ranked.SortBy("k")
    shown = []
    for each r in ranked
        shown.Push(r.t)
    end for
    return shown.Join("|")
end function

' Which Display option turns a badge on or off.
function tagOption(t as String) as String
    if t = "4K" or t = "8K" or t = "2K" or t = "SD" or (Right(t, 1) = "p" and Val(t) > 0) then return "tagRes"
    if t = "HDR" or t = "DV" or t = "10-BIT" then return "tagHdr"
    if t = "REMUX" then return "tagRemux"
    if t = "HC SUBS" then return "tagHc"
    for each s in ["Web-DL", "WebRip", "Blu-Ray", "HDTV", "DVD", "DVDRip", "HDRip", "VHSRip", "DCP", "CAM", "TS", "Screener", "Workprint"]
        if t = s then return "tagSource"
    end for
    return "tagCodec"
end function

function unplayableReason(f as Object) as String
    if f.ext = "avi" or f.ext = "wmv" or f.ext = "mpg" or f.ext = "mpeg" then return "Roku can't play ." + f.ext + " files (or the XviD / DivX video they usually hold). An H.264 MP4 or MKV copy will play."
    if f.playable = false then return "This file is packed (rar / zip parts) or a disc file. Extract it on your seedbox first."
    if f.xvid = true then return "This file is XviD / DivX video, which Roku can't decode. An H.264 copy will play."
    if f.hevc = true and m.canHevc <> true then return "This file is HEVC (H.265). This Roku has no HEVC decoder, so the picture won't play."
    if m.can4k <> true and videoWidth(f) > 1920 and videoWidth(f) < 3200 then return "This is a 2K file (" + videoWidth(f).ToStr() + " pixels wide). This Roku's video chip decodes up to 1920 wide, so the picture won't play; it can't be shrunk on the Roku. A smaller copy (1080p or 720p), or re-encoding it to 1920 wide on your seedbox, will play."
    if f.uhd = true and m.can4k <> true then return "This is a 4K (2160p) H.264 file. This Roku decodes video up to 1080p, so the picture won't play. Roku can't shrink 4K while playing."
    return ""
end function

' Whether this Roku can make sound from an audio format (MediaInfo's name).
function audioPlayable(codec as Dynamic) as Boolean
    ' Settings > Display: the viewer says their setup plays these.
    if not optionOn("avoidUnplayableAudio") then return true
    c = UCase(textOr(codec))
    if Instr(1, c, "TRUEHD") > 0 or Instr(1, c, "MLP") > 0 then return m.canTrueHd = true
    if Left(c, 3) = "DTS" then return m.canDts = true
    return true
end function

' The file's audio formats when none of them can be heard on this Roku ("").
function silentAudio(f as Object) as String
    info = m.probes[f.url]
    if info = invalid or info.ok <> true or info.audio = invalid or info.audio.Count() = 0 then return ""
    names = []
    for each a in info.audio
        if audioPlayable(a.codec) then return ""
        if names.Count() < 3 then names.Push(textOr(a.codec))
    end for
    return names.Join(", ")
end function

function textOr(value as Dynamic) as String
    if value = invalid then return ""
    return value.ToStr()
end function

' Whether this Roku can play a file: not packed, not a disc file, and a
' codec / resolution its decoder handles.
function canPlayFile(f as Object) as Boolean
    if f.playable = false then return false
    if f.xvid = true then return false
    if f.hevc = true and m.canHevc <> true then return false
    if f.uhd = true and m.can4k <> true and f.hevc <> true then return false
    if m.can4k <> true and videoWidth(f) > 1920 then return false
    return true
end function

' The picture width: from MediaInfo when read, or 2048 for names saying 2K.
function videoWidth(f as Object) as Integer
    info = m.probes[f.url]
    if info <> invalid and info.ok = true and info.video <> invalid and info.video.Count() > 0 then return info.video[0].width
    if f.wide = true then return 2048
    if f.uhd = true then return 3840
    return 0
end function

function metaFor(key as String) as Dynamic
    meta = m.meta[key]
    if meta = invalid then return invalid
    if meta.ok <> true then return invalid
    return meta
end function

' Art from the viewer's own files wins; otherwise the looked-up poster.
function posterFor(item as Object) as String
    if item = invalid then return ""
    if item.poster <> invalid and item.poster <> "" then return item.poster
    meta = metaFor(item.key)
    if meta <> invalid
        if meta.poster <> invalid then return meta.poster
    end if
    return ""
end function

function largePosterFor(item as Object) as String
    if item.poster <> invalid and item.poster <> "" then return item.poster
    meta = metaFor(item.key)
    if meta <> invalid
        if meta.posterLarge <> invalid and meta.posterLarge <> "" then return meta.posterLarge
        if meta.poster <> invalid then return meta.poster
    end if
    return ""
end function

function backdropFor(item as Object) as String
    if item = invalid then return ""
    if item.fanart <> invalid and item.fanart <> "" then return item.fanart
    meta = metaFor(item.key)
    if meta <> invalid
        if meta.backdrop <> invalid and meta.backdrop <> "" then return meta.backdrop
    end if
    ' A square album cover makes a poor full-screen backdrop.
    if item.kind = "album" then return ""
    return largePosterFor(item)
end function

function displayTitle(item as Object) as String
    meta = metaFor(item.key)
    if meta <> invalid
        if meta.title <> invalid and meta.title <> "" and item.kind <> "album" then return meta.title
    end if
    return item.title
end function

function itemYear(item as Object) as String
    meta = metaFor(item.key)
    if meta <> invalid
        if meta.year <> invalid and meta.year <> "" then return meta.year
    end if
    if item.year <> invalid then return item.year
    return ""
end function

function cardSubtitle(item as Object) as String
    if item.kind = "movie"
        parts = []
        year = itemYear(item)
        if year <> "" then parts.Push(year)
        meta = metaFor(item.key)
        if meta <> invalid
            if meta.rating <> invalid and meta.rating <> "" then parts.Push(meta.rating + " IMDb")
        end if
        return parts.Join("  ·  ")
    else if item.kind = "show"
        seasons = item.seasons.Count()
        text = item.episodes.Count().ToStr() + " episodes"
        if item.episodes.Count() = 1 then text = "1 episode"
        if seasons > 1 then text = seasons.ToStr() + " seasons  ·  " + text
        return text
    else if item.kind = "album"
        return item.artist
    end if
    return ""
end function

' A card for a movie, show or album. Cards are remembered by key so posters
' that arrive later appear on them.
function makeCard(parent as Object, item as Object) as Object
    card = parent.CreateChild("ContentNode")
    card.AddFields({key: item.key, kind: item.kind, progress: 0.0, badge: "", pad: m.cardPad, tags: ""})
    card.title = displayTitle(item)
    card.ShortDescriptionLine1 = cardSubtitle(item)
    card.HDPosterUrl = posterFor(item)
    if item.kind = "movie"
        card.progress = progressFor(item.files[0].url)
        if item.files[0].playable = false then card.badge = UCase(item.files[0].ext)
        card.tags = cardTags(item.files[0])
    else if item.kind = "show"
        card.tags = showCardTags(item)
        if item.episodes.Count() > 0 and optionOn("episodesLeft")
            unwatched = 0
            for each episode in item.episodes
                if not watchedUrl(episode.files[0].url) then unwatched = unwatched + 1
            end for
            if unwatched > 0 and unwatched < item.episodes.Count() then card.badge = unwatched.ToStr()
        end if
    end if
    if card.badge = "" and isUnmatched(item) and optionOn("noMatch") then card.badge = "NO MATCH"
    list = m.cards[item.key]
    if list = invalid
        list = []
        m.cards[item.key] = list
    end if
    list.Push(card)
    return card
end function

sub forgetCards()
    m.cardPad = 0
    m.cards = {}
    m.cards.SetModeCaseSensitive()
end sub

function libraryList(kind as String) as Object
    if m.library = invalid then return []
    list = []
    if kind = "movies" then list = m.library.movies
    if kind = "shows" then list = m.library.shows
    if kind = "music"
        ' Music view: everything, albums only, or singles and mixes only.
        view = m.settings.musicView
        if view = invalid or view = "all" then return m.library.albums
        kept = []
        for each album in m.library.albums
            if isSingleOrMix(album) = (view = "singles") then kept.Push(album)
        end for
        return kept
    end if
    if not optionOn("hideUnplayable") then return list
    ' Settings > Display: only what this Roku can play.
    kept = []
    for each item in list
        files = []
        if item.files <> invalid then files.Append(item.files)
        if item.episodes <> invalid
            for each episode in item.episodes
                files.Append(episode.files)
            end for
        end if
        playable = false
        for each f in files
            if canPlayFile(f) then playable = true
        end for
        if playable then kept.Push(item)
    end for
    return kept
end function

' ---- Resume points and watched marks ----------------------------------------

sub loadResume()
    m.resume = {}
    section = CreateObject("roRegistrySection", "boxstream-resume")
    for each name in section.GetKeyList()
        value = ParseJson(section.Read(name))
        if type(value) = "roAssociativeArray" then m.resume[name] = value
    end for
end sub

function urlKey(url as String) as String
    digest = CreateObject("roEVPDigest")
    digest.Setup("md5")
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(url)
    return digest.Process(bytes)
end function

function resumeFor(url as String) as Dynamic
    return m.resume[urlKey(url)]
end function

function progressFor(url as String) as Float
    entry = resumeFor(url)
    if entry = invalid then return 0
    if entry.w = true then return 1
    if entry.d = invalid or entry.d <= 0 then return 0
    return entry.p / entry.d
end function

function watchedUrl(url as String) as Boolean
    entry = resumeFor(url)
    if entry = invalid then return false
    return entry.w = true
end function

' Resume seconds, or 0 when it should start from the beginning.
function resumeSeconds(url as String) as Integer
    entry = resumeFor(url)
    if entry = invalid then return 0
    if entry.w = true then return 0
    if entry.p < 30 then return 0
    return Int(entry.p)
end function

sub saveResume(url as String, position as Float, duration as Float, itemKey as String, episodeKey as String)
    if duration <= 0 then return
    name = urlKey(url)
    entry = {p: Int(position), d: Int(duration), t: CreateObject("roDateTime").AsSeconds(), key: itemKey, ep: episodeKey, w: false}
    ' Near the end counts as watched; credits rarely matter.
    if position >= duration * 0.92 or duration - position < 150 then entry.w = true
    m.resume[name] = entry
    section = CreateObject("roRegistrySection", "boxstream-resume")
    section.Write(name, FormatJson(entry))
    ' Keep the registry small: drop the oldest entries past 90.
    if m.resume.Count() > 90
        oldest = ""
        oldestTime = 0
        for each k in m.resume
            if oldest = "" or m.resume[k].t < oldestTime
                oldest = k
                oldestTime = m.resume[k].t
            end if
        end for
        m.resume.Delete(oldest)
        section.Delete(oldest)
    end if
    section.Flush()
end sub

sub setWatched(url as String, watched as Boolean, itemKey as String, episodeKey as String)
    name = urlKey(url)
    section = CreateObject("roRegistrySection", "boxstream-resume")
    if watched
        entry = {p: 0, d: 1, t: CreateObject("roDateTime").AsSeconds(), key: itemKey, ep: episodeKey, w: true}
        m.resume[name] = entry
        section.Write(name, FormatJson(entry))
    else
        m.resume.Delete(name)
        section.Delete(name)
    end if
    section.Flush()
end sub

' The episode to play next for a show: the one in progress, else the first
' unwatched after the last watched one, else the first.
function nextEpisode(show as Object) as Dynamic
    if show.episodes.Count() = 0 then return invalid
    newest = 0
    pick = invalid
    lastWatched = -1
    for i = 0 to show.episodes.Count() - 1
        entry = resumeFor(show.episodes[i].files[0].url)
        if entry <> invalid
            if entry.t > newest
                newest = entry.t
                if entry.w = true
                    lastWatched = i
                    pick = invalid
                else
                    pick = show.episodes[i]
                    lastWatched = -1
                end if
            end if
        end if
    end for
    if pick <> invalid then return pick
    if lastWatched >= 0 and lastWatched + 1 < show.episodes.Count() then return show.episodes[lastWatched + 1]
    return show.episodes[0]
end function

' Remuxes and very large files: a warning, or "" when the file should stream.
' Bitrate is estimated from the size and the runtime when both are known.
function heavyWarning(file as Object, runtimeMinutes as Float) as String
    if file = invalid then return ""
    sizeMb = file.size
    mbps = 0
    if sizeMb > 0 and runtimeMinutes > 0 then mbps = Int(sizeMb * 8.39 / (runtimeMinutes * 60))
    big = sizeMb > 20000 or mbps > 35
    if not (file.remux = true or big) then return ""
    parts = []
    if file.remux = true then parts.Push("Remux")
    if sizeMb > 0 then parts.Push(sizeText(sizeMb))
    if mbps > 0 then parts.Push("about " + mbps.ToStr() + " Mb/s")
    text = ""
    if parts.Count() > 0 then text = parts.Join(", ") + ". "
    return text + "Files this large usually can't stream smoothly from a seedbox; a smaller version will play far better."
end function

function runtimeOf(item as Object) as Float
    meta = metaFor(item.key)
    if meta = invalid then return 0
    if meta.runtime = invalid then return 0
    return Val(meta.runtime)
end function

function episodeLabel(episode as Object) as String
    if episode.dated = true then return episode.title
    return "S" + episode.season.ToStr() + " E" + episode.episode.ToStr()
end function

function episodeName(show as Object, episode as Object) as String
    meta = metaFor(show.key)
    if meta <> invalid and meta.episodes <> invalid
        info = meta.episodes[metaEpisodeKey(show, episode)]
        if info <> invalid
            if info.name <> "" then return info.name
        end if
    end if
    if episode.title <> "" then return episode.title
    return "Episode " + episode.episode.ToStr()
end function

function episodeInfo(show as Object, episode as Object) as Dynamic
    meta = metaFor(show.key)
    if meta = invalid or meta.episodes = invalid then return invalid
    return meta.episodes[metaEpisodeKey(show, episode)]
end function

' ---- Season numbers: the files' season -> the matched show's season ----------
' (Fix match > Match seasons. For anthology shows a release may call each
' story "Season 1" or "Season 4" while the show numbers them differently.)

function seasonMap(show as Object) as Object
    if m.seasonMaps = invalid then m.seasonMaps = {}
    if m.seasonMaps.DoesExist(show.key) then return m.seasonMaps[show.key]
    map = {}
    section = CreateObject("roRegistrySection", "boxstream-fixes")
    name = urlKey(show.key)
    if section.Exists(name)
        fix = ParseJson(section.Read(name))
        if type(fix) = "roAssociativeArray"
            if type(fix.seasons) = "roAssociativeArray" then map = fix.seasons
        end if
    end if
    m.seasonMaps[show.key] = map
    return map
end function

function mappedSeason(show as Object, season as Integer) as Integer
    map = seasonMap(show)
    value = map[season.ToStr()]
    if value = invalid then return season
    return Int(Val(value.ToStr()))
end function

function metaEpisodeKey(show as Object, episode as Object) as String
    return mappedSeason(show, episode.season).ToStr() + ":" + episode.episode.ToStr()
end function

' The matched show's seasons, in order, with their episode counts.
function metaSeasonList(meta as Object) as Object
    counts = {}
    for each k in meta.episodes
        s = k.Split(":")[0]
        if not counts.DoesExist(s) then counts[s] = 0
        counts[s] = counts[s] + 1
    end for
    list = []
    for each s in counts
        list.Push({season: Int(Val(s)), count: counts[s]})
    end for
    list.SortBy("season")
    return list
end function

' Seasons in the files that the matched show doesn't have.
function missingSeasons(show as Object) as Object
    out = []
    meta = metaFor(show.key)
    if meta = invalid or meta.episodes = invalid or meta.episodes.Count() = 0 then return out
    seen = {}
    for each e in show.episodes
        if e.dated <> true and not seen.DoesExist(e.season.ToStr())
            seen[e.season.ToStr()] = true
            found = false
            prefix = mappedSeason(show, e.season).ToStr() + ":"
            for each k in meta.episodes
                if Left(k, Len(prefix)) = prefix
                    found = true
                    exit for
                end if
            end for
            if not found then out.Push(e.season)
        end if
    end for
    return out
end function

' A single or a DJ set / mix: one track, or a few very long ones (a file of
' 150 MB or more is an hour or so of music).
function isSingleOrMix(album as Object) as Boolean
    n = album.tracks.Count()
    if n <= 1 then return true
    if n > 4 then return false
    for each t in album.tracks
        if t.size <> invalid and Val(t.size.ToStr()) >= 150000000 then return true
    end for
    return false
end function
