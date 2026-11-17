' Pure helpers: reading folder listings and working out what a file is.
' Used by the library worker; nothing here touches the screen or the network.

function rx(name as String) as Object
    if m.regexes = invalid then m.regexes = {}
    if m.regexes.DoesExist(name) then return m.regexes[name]
    patterns = {
        anchor: ["<a\s[^>]*?href\s*=\s*(?:" + Chr(34) + "([^" + Chr(34) + "]*)" + Chr(34) + "|'([^']*)')[^>]*>(.*?)</a>((?:(?!<a\s).){0,200})", "is"]
        tags: ["<[^>]*>", ""]
        spaces: ["\s+", ""]
        separators: ["[._]+", ""]
        dateNginx: ["(\d{2})-([A-Za-z]{3})-(\d{4})\s+(\d{2}):(\d{2})", ""]
        dateIso: ["(\d{4})-(\d{2})-(\d{2})[ T]+(\d{2}):(\d{2})", ""]
        sizeBytes: ["\s(\d{3,})\s*$", ""]
        sizeHuman: ["\s(\d+(?:\.\d+)?)\s*([KMGT])i?B?\s*$", "i"]
        episode: ["^(.*?)[\s\-\[\(]*\bS(\d{1,2})\s?[\.\-]?\s?E(\d{1,3})(?:\s?-?\s?E?(\d{1,3}))?\b(.*)$", "i"]
        episodeX: ["^(.*?)[\s\-\[\(]*\b(\d{1,2})x(\d{2,3})\b(.*)$", "i"]
        episodeOnly: ["^(?:.*?\b)?(?:E|EP|Episode\s?)(\d{1,3})\b(.*)$", "i"]
        leadingNumber: ["^(\d{1,3})(?:\s*[\.\-_)]\s*|\s+)(.*)$", ""]
        season: ["^(?:season|series|s)\s*(\d{1,2})\b", "i"]
        disc: ["^(?:cd|disc|disk)\s*\d+$", "i"]
        year: ["^(.*)[\s\(\[]+((?:19|20)\d{2})(?:[\s\)\]]|$)", ""]
        junk: ["\b(2160p|1080p|1080i|720p|576p|480p|4k|uhd|bluray|blu-ray|bdrip|brrip|bdremux|remux|webrip|web-dl|webdl|web|hdtv|hdrip|dvdrip|dvdscr|dvd|hdcam|camrip|hdts|telesync|screener|workprint|vhsrip|dcp|x264|x265|h\.?264|h\.?265|hevc|avc|xvid|divx|10bit|8bit|hdr10|hdr|dv|dts|dts-hd|truehd|atmos|aac|ac3|eac3|dd5\.1|ddp5\.1|5\.1|7\.1|proper|repack|extended|unrated|uncut|remastered|imax|limited|internal|multi|dubbed|subbed|complete|criterion)\b.*$", "i"]
        brackets: ["[\[\{][^\]\}]*[\]\}]", ""]
        trailing: ["[\s\-\(\[]+$", ""]
        artistAlbum: ["^(.+?)\s+-\s+(.+?)$", ""]
        albumYear: ["^(.*?)\s*[\(\[]((?:19|20)\d{2})[\)\]]\s*(.*)$", ""]
        nonAlnum: ["[^a-z0-9]+", ""]
        nonDigit: ["[^0-9]+", ""]
        aka: ["\s+a\.?k\.?a\.?\s+", "i"]
        leadingPart: ["^\d{1,2}\s+(.+)$", ""]
        groupSuffix: ["-([A-Za-z0-9]{2,24})$", ""]
        groupPrefix: ["^\[([^\]]{2,30})\]", ""]
        groupLead: ["^([a-z0-9]{3,20})-([A-Z][^ ]*\.(19|20)\d\d\..*)$", ""]
        bracketTail: ["\s*[\[\(][^\]\)]*[\]\)]\s*$", ""]
        tagHc: ["\b(hc|hardsub|hardsubs|hardcoded|hc-?subs)\b", "i"]
        tagRes: ["\b(\d{3,4})[pi]\b", "i"]
        tag4k: ["\b(2160p|4k|uhd)\b", "i"]
        tagDv: ["\b(dv|dovi|dolby ?vision)\b", "i"]
        tagHevc: ["\b(hevc|x265|h ?265|h\.265)\b", "i"]
        tagAvc: ["\b(avc|x264|h ?264|h\.264)\b", "i"]
        tagAv1: ["\bav1\b", "i"]
        tagDdp: ["\b(ddp|dd\+|eac3|e-ac-3)", "i"]
        tagWebDl: ["\b(web-?dl|web)\b", "i"]
        tagWebRip: ["\bweb-?rip\b", "i"]
        tagBluRay: ["\b(blu-?ray|bdrip|brrip|bd25|bd50|bdmv)\b", "i"]
        tagCam: ["\b(cam|hdcam|camrip|cam-rip)\b", "i"]
        tagTs: ["\b(ts|hdts|telesync|pdvd|tsrip)\b", "i"]
        tagScreener: ["\b(scr|screener|dvdscr|dvdscreener|bdscr|webscreener)\b", "i"]
        tagWorkprint: ["\b(workprint|wp)\b", "i"]
        tag10bit: ["\b(10 ?bit|10-bit|hi10p|hi10)\b", "i"]
        tagDcp: ["\bdcp\b", "i"]
        tagVhs: ["\b(vhsrip|vhs)\b", "i"]
        tagHdtv: ["\b(hdtv|pdtv|dsr)\b", "i"]
        tagDvdRip: ["\b(dvdrip|dvd-rip)\b", "i"]
        tagHdRip: ["\bhdrip\b", "i"]
        tagDvd: ["\b(dvd|dvd9|dvd5|dvdr|dvd-r)\b", "i"]
        tagAc3: ["\b(ac3|dd5 ?1|dd2 ?0)\b", "i"]
        absolute: ["^(.*?)\s+-\s+(\d{1,4})(?:v\d)?\b(.*)$", ""]
        sample: ["(^|[^a-z])sample([^a-z]|$)", "i"]
        extraSuffix: ["-(trailer|sample|featurette|behindthescenes|deleted|interview|scene|short|other)$", "i"]
        seasonPack: ["^(.*?)\b(?:S|Season\s?)(\d{1,2})\b(?!\s?E\d)", "i"]
        dated: ["^(.*?)\s((?:19|20)\d{2})\s(\d{2})\s(\d{2})\b", ""]
        part: ["\b(?:cd|disc|disk|part|pt)\s?(\d{1,2})\b", "i"]
        trackArtist: ["^(.+?)\s+-\s+(.+)$", ""]
    }
    p = patterns[name]
    regex = CreateObject("roRegex", p[0], p[1])
    m.regexes[name] = regex
    return regex
end function

' ---- Listings -------------------------------------------------------------
' Reads an autoindex-style page (nginx, Apache, lighttpd, h5ai, rclone serve,
' caddy file_server and most seedbox web listings): every link below this
' folder becomes an entry; dates and sizes are read from the text after it.
function parseListing(html as String, folderUrl as String, rootUrl as String) as Object
    entries = []
    seen = {}
    base = folderUrl
    if Right(base, 1) <> "/" then base = base + "/"
    for each match in rx("anchor").MatchAll(html)
        ' The address in double quotes (may hold an apostrophe: "Don't") or single.
        href = match[1]
        if href = "" then href = match[2]
        href = href.Replace("&amp;", "&").Trim()
        if href = "" or Left(href, 1) = "?" or Left(href, 1) = "#" then continue for
        if LCase(Left(href, 7)) = "mailto:" or LCase(Left(href, 11)) = "javascript:" then continue for
        url = joinUrl(base, href)
        clean = url
        q = clean.Instr("?")
        if q >= 0 then clean = Left(clean, q)
        q = clean.Instr("#")
        if q >= 0 then clean = Left(clean, q)
        ' Only things inside the folder being read (no parents, no other sites).
        if not isWithin(clean, base) or clean = base then continue for
        if seen.DoesExist(clean) then continue for
        seen[clean] = true
        isDir = Right(clean, 1) = "/"
        rest = Mid(clean, Len(base) + 1)
        if isDir then rest = Left(rest, Len(rest) - 1)
        ' Direct children only.
        if rest.Instr("/") >= 0 or rest = "" then continue for
        name = decodeName(rest)
        if hiddenName(name) then continue for
        tail = rx("tags").ReplaceAll(match[4], " ")
        cut = tail.Instr("<")
        if cut >= 0 then tail = Left(tail, cut)
        entries.Push({name: name, url: clean, isDir: isDir, date: parseDate(tail), size: parseSize(tail)})
    end for
    return entries
end function

function hiddenName(name as String) as Boolean
    if name = "" or Left(name, 1) = "." or Left(name, 1) = "@" or Left(name, 1) = "#" then return true
    lower = LCase(name)
    return lower = "lost+found" or lower = "$recycle.bin" or lower = "_unpack" or lower = "incomplete" or lower = ".incomplete" or lower = "thumbs.db" or lower = "desktop.ini" or Left(lower, 8) = "_unpack_" or Left(lower, 6) = "_fail_"
end function

function parseDate(text as String) as String
    months = {jan: "01", feb: "02", mar: "03", apr: "04", may: "05", jun: "06", jul: "07", aug: "08", sep: "09", oct: "10", nov: "11", dec: "12"}
    hit = rx("dateNginx").Match(text)
    if hit.Count() > 5
        mon = LCase(hit[2])
        if months.DoesExist(mon) then return hit[3] + "-" + months[mon] + "-" + hit[1] + " " + hit[4] + ":" + hit[5]
    end if
    hit = rx("dateIso").Match(text)
    if hit.Count() > 5 then return hit[1] + "-" + hit[2] + "-" + hit[3] + " " + hit[4] + ":" + hit[5]
    return ""
end function

' Size in megabytes (float), or -1 when the listing does not say.
function parseSize(text as String) as Float
    t = text.Trim()
    hit = rx("sizeHuman").Match(" " + t)
    if hit.Count() > 2
        value = Val(hit[1])
        unit = UCase(hit[2])
        if unit = "K" then return value / 1024
        if unit = "M" then return value
        if unit = "G" then return value * 1024
        if unit = "T" then return value * 1048576
    end if
    hit = rx("sizeBytes").Match(" " + t)
    if hit.Count() > 1 then return Val(hit[1]) / 1048576
    return -1
end function

function joinUrl(base as String, href as String) as String
    lower = LCase(href)
    if Left(lower, 7) = "http://" or Left(lower, 8) = "https://" then return href
    if Left(href, 2) = "//"
        scheme = "https:"
        if LCase(Left(base, 5)) = "http:" then scheme = "http:"
        return scheme + href
    end if
    if Left(href, 1) = "/" then return urlOrigin(base) + href
    if Left(href, 2) = "./" then href = Mid(href, 3)
    return base + href
end function

function urlOrigin(url as String) as String
    schemeEnd = url.Instr("://")
    if schemeEnd < 0 then return ""
    slash = url.Instr(schemeEnd + 3, "/")
    if slash < 0 then return url
    return Left(url, slash)
end function

function isWithin(url as String, folder as String) as Boolean
    return LCase(Left(url, Len(folder))) = LCase(folder)
end function

function decodeName(text as String) as String
    if m.unescaper = invalid then m.unescaper = CreateObject("roUrlTransfer")
    return m.unescaper.Unescape(text.Replace("+", "%2B"))
end function

function fileExtension(name as String) as String
    dot = -1
    i = name.Instr(".")
    while i >= 0
        dot = i
        i = name.Instr(i + 1, ".")
    end while
    if dot < 0 then return ""
    return LCase(Mid(name, dot + 2))
end function

function fileStem(name as String) as String
    ext = fileExtension(name)
    if ext = "" then return name
    return Left(name, Len(name) - Len(ext) - 1)
end function

function normKey(text as String) as String
    return rx("nonAlnum").ReplaceAll(LCase(text), "")
end function

function isVideoExt(ext as String) as Boolean
    ' Disc pieces (.m2ts, .vob, .mts) are left out: a ripped disc is hundreds
    ' of them, and Roku can't play them as a movie.
    return ext = "mp4" or ext = "m4v" or ext = "mkv" or ext = "mov" or ext = "ts" or ext = "webm" or ext = "m3u8" or ext = "avi" or ext = "wmv" or ext = "mpg" or ext = "mpeg"
end function

function isDiscExt(ext as String) as Boolean
    return ext = "m2ts" or ext = "mts" or ext = "vob" or ext = "ifo" or ext = "bup" or ext = "mpls" or ext = "clpi" or ext = "bdmv"
end function

' BDMV / VIDEO_TS / AVCHD: the inside of a ripped disc.
function discFolderIndex(folders as Object) as Integer
    for i = 0 to folders.Count() - 1
        lower = LCase(folders[i])
        if lower = "bdmv" or lower = "video_ts" or lower = "avchd" or lower = "certificate" or lower = "audio_ts" then return i
    end for
    return -1
end function

function isAudioExt(ext as String) as Boolean
    return ext = "mp3" or ext = "m4a" or ext = "aac" or ext = "flac" or ext = "wav" or ext = "wma" or ext = "ogg" or ext = "oga" or ext = "opus" or ext = "alac" or ext = "aif" or ext = "aiff"
end function

function isImageExt(ext as String) as Boolean
    return ext = "jpg" or ext = "jpeg" or ext = "png" or ext = "webp"
end function

function isSubtitleExt(ext as String) as Boolean
    return ext = "srt" or ext = "vtt" or ext = "ass" or ext = "ssa" or ext = "sup" or ext = "idx"
end function

' ---- Titles ---------------------------------------------------------------
' "The.Dark.Knight.2008.1080p.BluRay.x264-GRP" -> {title: "The Dark Knight", year: "2008"}
function cleanTitle(raw as String, fallback = true as Boolean) as Object
    ' A release group written before the title (lowercase, then a dash).
    lead = rx("groupLead").Match(raw)
    if lead.Count() > 2 then raw = lead[2]
    text = rx("separators").ReplaceAll(raw, " ")
    year = ""
    hit = rx("year").Match(text)
    if hit.Count() > 2
        if hit[1].Trim() <> ""
            text = hit[1]
            year = hit[2]
        end if
    end if
    text = rx("brackets").ReplaceAll(text, " ")
    text = rx("junk").ReplaceAll(text, "")
    text = rx("spaces").ReplaceAll(text, " ")
    text = rx("trailing").ReplaceAll(text, "").Trim()
    ' "Title AKA Other AKA Third": one name per AKA, all searched.
    aka = ""
    names = rx("aka").Split(text)
    if names.Count() > 1
        text = names[0].Trim()
        others = []
        for i = 1 to names.Count() - 1
            if names[i].Trim() <> "" then others.Push(names[i].Trim())
        end for
        aka = others.Join("|")
    end if
    if text = "" and fallback then text = raw
    return {title: text, year: year, aka: aka}
end function

' Works out what a video file is, from its name and the folders above it.
' folders: folder names from the library root down to the file's folder.
function classifyVideo(fileName as String, folders as Object) as Object
    stemName = rx("separators").ReplaceAll(fileStem(fileName), " ")
    hit = rx("episode").Match(stemName)
    if hit.Count() > 3
        return episodeInfo(hit[1], Val(hit[2]), Val(hit[3]), hit[hit.Count() - 1], folders)
    end if
    hit = rx("episodeX").Match(stemName)
    if hit.Count() > 3
        return episodeInfo(hit[1], Val(hit[2]), Val(hit[3]), hit[4], folders)
    end if
    ' A "Season 2" folder (or a TV folder) with numbered files is a show too.
    seasonNumber = -1
    if folders.Count() > 0
        s = rx("season").Match(folders[folders.Count() - 1])
        if s.Count() > 1 then seasonNumber = Val(s[1])
    end if
    if seasonNumber >= 0
        e = rx("episodeOnly").Match(stemName)
        if e.Count() < 2 then e = rx("leadingNumber").Match(stemName)
        if e.Count() > 2 then return episodeInfo("", seasonNumber, Val(e[1]), e[2], folders)
    end if
    info = cleanTitle(fileStem(fileName))
    ' A release folder often has the better name: "Movie (2010)/movie.mkv".
    if folders.Count() > 0
        folderInfo = cleanTitle(folders[folders.Count() - 1])
        generic = LCase(info.title).Len() < 3 or info.year = "" and folderInfo.year <> ""
        if generic and not mediaRootName(folders[folders.Count() - 1]) then info = folderInfo
    end if
    info.kind = "movie"
    return info
end function

function episodeInfo(showPart as String, season as Integer, episode as Integer, tail as String, folders as Object) as Object
    show = cleanTitle(showPart)
    title = show.title
    year = show.year
    if showPart.Trim() = ""
        title = ""
        ' Walk up past "Season N" folders to the show's own folder.
        i = folders.Count() - 1
        while i >= 0
            name = folders[i]
            if rx("season").IsMatch(name) or mediaRootName(name)
                i = i - 1
            else
                found = cleanTitle(name)
                title = found.title
                year = found.year
                exit while
            end if
        end while
        if title = "" then title = "Unknown show"
    end if
    episodeTitle = cleanTitle(tail, false).title
    if Len(episodeTitle) < 2 then episodeTitle = ""
    return {kind: "episode", title: title, year: year, season: season, episode: episode, episodeTitle: episodeTitle}
end function

function mediaRootName(name as String) as Boolean
    lower = LCase(name.Trim())
    return lower = "movies" or lower = "movie" or lower = "films" or lower = "tv" or lower = "tv shows" or lower = "shows" or lower = "series" or lower = "television" or lower = "downloads" or lower = "complete" or lower = "completed" or lower = "media" or lower = "video" or lower = "videos" or lower = "music" or lower = "files" or lower = "data" or lower = "rtorrent" or lower = "deluge" or lower = "qbittorrent" or lower = "torrents" or lower = "usenet" or lower = "sabnzbd" or lower = "anime" or lower = "4k" or lower = "uhd"
end function

' Music: album from the folder ("Artist - Album (Year)" or Artist/Album),
' track number and title from the file name.
function classifyTrack(fileName as String, folders as Object) as Object
    names = []
    for each f in folders
        names.Push(f)
    end for
    ' "CD1" / "Disc 2" folders belong to the album above them.
    disc = 0
    if names.Count() > 0
        if rx("disc").IsMatch(names[names.Count() - 1])
            disc = Val(rx("nonDigit").ReplaceAll(names.Pop(), ""))
        end if
    end if
    albumFolder = ""
    artist = ""
    if names.Count() > 0 then albumFolder = names[names.Count() - 1]
    if mediaRootName(albumFolder) then albumFolder = ""
    album = albumFolder
    year = ""
    hit = rx("artistAlbum").Match(albumFolder)
    if hit.Count() > 2
        artist = hit[1].Trim()
        album = hit[2].Trim()
    else if names.Count() > 1
        if not mediaRootName(names[names.Count() - 2]) then artist = names[names.Count() - 2]
    end if
    hit = rx("albumYear").Match(album)
    if hit.Count() > 2
        year = hit[2]
        album = (hit[1] + " " + hit[3]).Trim()
    end if
    album = rx("brackets").ReplaceAll(album, " ").Trim()
    album = rx("spaces").ReplaceAll(album, " ")
    title = rx("separators").ReplaceAll(fileStem(fileName), " ").Trim()
    number = 0
    ' "2-10 - Title" / "1.06 - Title": disc 2 track 10, disc 1 track 6.
    dt = CreateObject("roRegex", "^(\d{1,2})[\-\.](\d{2,3})(?:\s*[\.\-_)]\s*|\s+)(.*)$", "").Match(fileStem(fileName))
    if dt.Count() > 3
        if disc = 0 then disc = Val(dt[1])
        number = Val(dt[2])
        title = rx("separators").ReplaceAll(dt[3], " ").Trim()
    else
        n = rx("leadingNumber").Match(title)
        if n.Count() > 2
            number = Val(n[1])
            title = n[2].Trim()
        end if
    end if
    trackArtist = ""
    t = rx("trackArtist").Match(title)
    if t.Count() > 2
        if artist = "" or LCase(t[1].Trim()) = LCase(artist)
            trackArtist = t[1].Trim()
            title = t[2].Trim()
        end if
    end if
    if artist = "" then artist = trackArtist
    if artist = "" then artist = "Unknown artist"
    if album = "" then album = "Singles"
    if title = "" then title = fileStem(fileName)
    return {kind: "track", artist: artist, album: album, year: year, number: number, disc: disc, title: title}
end function
