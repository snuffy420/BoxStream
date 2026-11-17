' Library worker (Task thread).
'
' Commands (m.top.command):
'   {action: "configure", url, user, pass}   server settings
'   {action: "load"}        send the cached library and details, then scan
'   {action: "scan"}        read every folder again and rebuild the library
'   {action: "rebuild"}     re-sort the last scan (after the viewer fixes something)
'   {action: "list", url}   one folder's listing, for the Folders screen
'   {action: "test"}        check the server address and login
'   {action: "candidates", kind, query, key}   possible matches, for Fix match
'   {action: "applyMatch", kind, key, id}      use this match from now on
'
' Everything the worker learns goes back through fields: status, library,
' metaBatch (details as they arrive), listing, testResult, candidates.

sub init()
    m.top.functionName = "runWorker"
end sub

sub runWorker()
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("commands", m.port)
    m.lastSeq = 0
    m.server = {base: "", auth: ""}
    m.jobs = {}
    m.scan = invalid
    m.lastFiles = invalid
    m.metaQueue = []
    m.metaOut = []
    m.metaDirty = 0
    m.clock = CreateObject("roTimespan")
    m.lastFlush = 0
    m.meta = readJson("cachefs:/boxstream-meta.json")
    if type(m.meta) <> "roAssociativeArray" then m.meta = {}
    m.meta.SetModeCaseSensitive()
    ' Lookups improved (AKA titles): failed ones from older versions try again.
    if m.meta["_v"] <> 11
        fixes = loadAllFixes()
        for each key in m.meta.Keys()
            entry = m.meta[key]
            if type(entry) = "roAssociativeArray"
                if entry.ok <> true or Left(key, 2) = "a:"
                    ' (Albums: matched under the old, loose rule; look again.)
                    m.meta.Delete(key)
                else if weakMatch(key, entry, fixes)
                    ' Matched under the old, looser rule: look it up again.
                    m.meta.Delete(key)
                end if
            end if
        end for
        m.meta["_v"] = 11
    end if
    m.probes = readJson("cachefs:/boxstream-probes.json")
    if type(m.probes) <> "roAssociativeArray" then m.probes = {}
    ' Version 2 reads profiles, chapters and encoder notes: read files again.
    if m.probes["_v"] <> 4 then m.probes = {_v: 4}
    for each url in m.probes.Keys()
        entry = m.probes[url]
        if type(entry) = "roAssociativeArray"
            if entry.ok <> true and entry.error = "Couldn't read this file's headers." then m.probes.Delete(url)
        end if
    end for
    m.probes.SetModeCaseSensitive()
    m.probeQueue = []
    m.probeActive = 0
    m.probeOut = []
    m.probeDirty = 0
    m.probeFiles = 0
    m.nextScan = 0
    ' Commands sent before this thread was listening.
    waiting = m.top.commands
    if type(waiting) = "roArray"
        for each command in waiting
            if command.seq > m.lastSeq
                m.lastSeq = command.seq
                handleCommand(command)
            end if
        end for
    end if
    while true
        message = Wait(100, m.port)
        try
            if type(message) = "roSGNodeEvent"
                for each command in message.GetData()
                    if command.seq > m.lastSeq
                        m.lastSeq = command.seq
                        handleCommand(command)
                    end if
                end for
            else if type(message) = "roUrlEvent"
                handleResponse(message)
            end if
            pump()
            flushMeta(false)
            flushProbes(false)
            ' Look for new files every 30 minutes while the app is open.
            if m.nextScan > 0 and m.clock.TotalMilliseconds() > m.nextScan and m.scan = invalid and m.playing <> true
                m.quiet = true
                startScan()
            end if
        catch problem
            print "[worker] "; problem.message
            for each frame in problem.backtrace
                print "    "; frame.filename; ":"; frame.line_number
            end for
        end try
    end while
end sub

' ---- Commands -------------------------------------------------------------

sub handleCommand(command as Dynamic)
    if type(command) <> "roAssociativeArray" then return
    action = command.action
    if action = "configure"
        base = command.url.Trim()
        if base <> "" and Right(base, 1) <> "/" then base = base + "/"
        m.server.base = base
        m.server.auth = ""
        if command.user <> invalid and command.user <> ""
            bytes = CreateObject("roByteArray")
            bytes.FromAsciiString(command.user + ":" + command.pass)
            m.server.auth = "Basic " + bytes.ToBase64String()
        end if
        ' All sources (the library is built from every one of them).
        m.servers = []
        if command.sources <> invalid
            for each s in command.sources
                entry = {base: s.url, auth: ""}
                if s.user <> invalid and s.user <> ""
                    b = CreateObject("roByteArray")
                    b.FromAsciiString(s.user + ":" + s.pass)
                    entry.auth = "Basic " + b.ToBase64String()
                end if
                m.servers.Push(entry)
            end for
        end if
        if m.servers.Count() = 0 and base <> "" then m.servers.Push({base: base, auth: m.server.auth})
    else if action = "load"
        cached = readJson(libraryCachePath())
        m.lastSignature = invalid
        if type(cached) = "roAssociativeArray"
            if cached.server = serversKey()
                m.top.library = cached
                m.library = cached
                m.lastSignature = cached.signature
                sendAllMeta(cached)
                sendAllProbes(cached)
            end if
        end if
        m.quiet = m.lastSignature <> invalid
        ' Whether the saved scan survived (a reinstall can clear cachefs:).
        startScan()
    else if action = "scan"
        startScan()
    else if action = "clearMeta"
        m.meta = {}
        m.meta.SetModeCaseSensitive()
        CreateObject("roFileSystem").Delete("cachefs:/boxstream-meta.json")
        if m.library <> invalid
            m.fixes = loadAllFixes()
            queueAllMeta(m.library)
        end if
    else if action = "rebuild"
        if m.lastFiles <> invalid then finishScan(m.lastFiles, false) else startScan()
    else if action = "list"
        startJob(command.url, true, {kind: "list", url: command.url})
    else if action = "test"
        if m.server.base = ""
            m.top.testResult = {ok: false, message: "Enter your server address first."}
        else
            startJob(m.server.base, true, {kind: "test"})
        end if
    else if action = "probe"
        queueProbe(command.url, command.ext, true)
    else if action = "nfo"
        startNfoRead(command.url)
    else if action = "playing"
        m.playing = command.on = true
        m.playingUrl = command.url
        if m.playing and m.scan <> invalid
            ' A scan already running is put off until playback ends.
            for each id in m.jobs.Keys()
                if m.jobs[id].kind = "dir"
                    m.jobs[id].transfer.AsyncCancel()
                    m.jobs.Delete(id)
                end if
            end for
            m.scan = invalid
            m.nextScan = m.clock.TotalMilliseconds() + 60000
        end if
    else if action = "candidates"
        m.candidateResults = {key: command.key, kind: command.kind, query: command.query, first: invalid, imdb: invalid}
        startJob(searchUrl(command.kind, command.query), false, {kind: "candidates", target: command.kind, key: command.key, query: command.query})
        if command.kind = "movie" or command.kind = "show"
            startJob(imdbSearchUrl(command.query), false, {kind: "candidatesImdb", target: command.kind, key: command.key, query: command.query})
        else
            m.candidateResults.imdb = []
        end if
    else if action = "applyMatch"
        if command.id <> invalid and command.id <> ""
            fix = loadFix(command.key)
            fix.id = command.id
            fix.suggestion = command.suggestion
            saveFix(command.key, fix)
        end if
        m.fixes = loadAllFixes()
        item = findItem(command.key)
        if item <> invalid
            m.meta.Delete(command.key)
            queueMeta(item, true)
        end if
    end if
end sub

' ---- Network --------------------------------------------------------------

function startJob(url as String, useAuth as Boolean, job as Object) as Boolean
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.SetMessagePort(m.port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.RetainBodyOnError(true)
    transfer.EnableEncodings(true)
    transfer.AddHeader("User-Agent", "BoxStream/" + appVersion() + " (Roku)")
    ' The login only ever goes to the viewer's own server.
    if useAuth
        auth = authFor(url)
        if auth <> "" then transfer.AddHeader("Authorization", auth)
    end if
    if not transfer.AsyncGetToString() then return false
    job.transfer = transfer
    job.started = m.clock.TotalMilliseconds()
    job.url = url
    m.jobs[transfer.GetIdentity().ToStr()] = job
    return true
end function

' Each source keeps its own library file, so switching back is instant.
function libraryCachePath() as String
    return "cachefs:/boxstream-library-" + Left(fixName(serversKey()), 12) + ".json"
end function

' Which login a URL gets: the source it's on (a login never goes elsewhere).
function authFor(url as String) as String
    if m.servers <> invalid
        for each s in m.servers
            if s.auth <> "" and isWithin(url, urlOrigin(s.base)) then return s.auth
        end for
    end if
    if m.server.auth <> "" and isWithin(url, urlOrigin(m.server.base)) then return m.server.auth
    return ""
end function

' All sources' addresses: the library (and its cache) belong to this set.
function serversKey() as String
    if m.servers = invalid or m.servers.Count() = 0 then return m.server.base
    bases = []
    for each s in m.servers
        bases.Push(s.base)
    end for
    return bases.Join(" + ")
end function

function showing4k() as Boolean
    if m.uhd = invalid
        mode = CreateObject("roDeviceInfo").GetVideoMode()
        m.uhd = Left(mode, 4) = "2160"
    end if
    return m.uhd
end function

function canDecodeHevc() as Boolean
    if m.hevc = invalid
        m.hevc = false
        info = CreateObject("roDeviceInfo")
        for each query in [{Codec: "hevc", Profile: "main", Level: "4.1"}, {Codec: "hevc", Profile: "main 10", Level: "4.1"}, {Codec: "hevc"}]
            result = info.CanDecodeVideo(query)
            if result <> invalid
                if result.Result = true then m.hevc = true
            end if
        end for
    end if
    return m.hevc
end function

function canDecode4kAvc() as Boolean
    if m.avc4k = invalid
        result = CreateObject("roDeviceInfo").CanDecodeVideo({Codec: "mpeg4 avc", Profile: "high", Level: "5.1"})
        m.avc4k = false
        if result <> invalid then m.avc4k = result.Result = true
    end if
    return m.avc4k
end function

function appVersion() as String
    if m.version = invalid then m.version = CreateObject("roAppInfo").GetVersion()
    return m.version
end function

sub handleResponse(event as Object)
    id = event.GetSourceIdentity().ToStr()
    if not m.jobs.DoesExist(id) then return
    job = m.jobs[id]
    m.jobs.Delete(id)
    code = event.GetResponseCode()
    body = event.GetString()
    if job.kind = "dir"
        m.scan.active = m.scan.active - 1
        if code = 200 then readFolder(job, body) else m.scan.errors = m.scan.errors + 1
        if code = 401 or code = 403 then m.scan.denied = true
    else if job.kind = "meta"
        m.metaActive = m.metaActive - 1
        handleMeta(job, code, body)
    else if job.kind = "list"
        if code = 200
            m.top.listing = {url: job.url, entries: describeEntries(parseListing(body, job.url, m.server.base)), error: ""}
        else
            m.top.listing = {url: job.url, entries: [], error: httpProblem(code)}
        end if
    else if job.kind = "test"
        if code = 200
            entries = parseListing(body, m.server.base, m.server.base)
            if entries.Count() = 0
                m.top.testResult = {ok: false, message: "Connected, but this page has no file listing. Use the address of a folder that shows your files in a web browser."}
            else
                m.top.testResult = {ok: true, message: "Connected. " + entries.Count().ToStr() + " items in this folder."}
            end if
        else
            m.top.testResult = {ok: false, message: httpProblem(code)}
        end if
    else if job.kind = "candidates" or job.kind = "candidatesImdb"
        set = m.candidateResults
        if set <> invalid and set.key = job.key
            if job.kind = "candidates" then set.first = readCandidates(job.target, code, body) else set.imdb = readImdbCandidates(job.target, code, body)
            if set.first <> invalid and set.imdb <> invalid
                ' Main source first, then IMDb titles it didn't have.
                results = []
                ids = {}
                for each r in set.first
                    results.Push(r)
                    ids[r.id] = true
                end for
                for each r in set.imdb
                    if not ids.DoesExist(r.id) and results.Count() < 16 then results.Push(r)
                end for
                m.top.candidates = {key: job.key, kind: job.target, query: job.query, results: results}
            end if
        end if
    else if job.kind = "probe"
        m.probeActive = m.probeActive - 1
        probeResponse(job, event)
    else if job.kind = "nfo"
        finishNfoRead(job, code)
    end if
end sub

function httpProblem(code as Integer) as String
    if code = 401 then return "The server asked for a login (401). Check your username and password."
    if code = 403 then return "The server refused access (403). Check the address and login."
    if code = 404 then return "Nothing found at that address (404)."
    if code < 0 then return "Couldn't reach the server. Check the address and your connection."
    return "The server answered with error " + code.ToStr() + "."
end function

' Starts queued work and drops anything that has hung for too long.
sub pump()
    now = m.clock.TotalMilliseconds()
    for each id in m.jobs.Keys()
        job = m.jobs[id]
        limit = 20000
        if job.kind = "meta" then limit = 12000
        if job.kind = "probe" then limit = 25000
        if now - job.started > limit
            job.transfer.AsyncCancel()
            m.jobs.Delete(id)
            if job.kind = "dir"
                m.scan.active = m.scan.active - 1
                m.scan.errors = m.scan.errors + 1
            else if job.kind = "meta"
                m.metaActive = m.metaActive - 1
                handleMeta(job, -28, "")
            else if job.kind = "list"
                m.top.listing = {url: job.url, entries: [], error: httpProblem(-28)}
            else if job.kind = "test"
                m.top.testResult = {ok: false, message: httpProblem(-28)}
            else if job.kind = "probe"
                m.probeActive = m.probeActive - 1
                finishProbe(job, {ok: false, error: "The server took too long to answer."})
            end if
        end if
    end for
    if m.scan <> invalid
        while m.scan.active < 6 and m.scan.queue.Count() > 0
            folder = m.scan.queue.Shift()
            if startJob(folder.url, true, {kind: "dir", folder: folder}) then m.scan.active = m.scan.active + 1
        end while
        if m.scan.queue.Count() = 0 and m.scan.active = 0
            files = m.scan.files
            denied = m.scan.denied
            m.scan = invalid
            if denied and files.Count() = 0
                m.top.status = {phase: "error", message: httpProblem(401)}
            else
                finishScan(files, true)
            end if
        else if now - m.scan.reported > 400 and m.quiet <> true
            m.scan.reported = now
            m.top.status = {phase: "scanning", folders: m.scan.folders, files: m.scan.files.Count(), message: "Scanning your server: " + m.scan.folders.ToStr() + " folders, " + m.scan.files.Count().ToStr() + " files"}
        end if
    end if
    if m.regroupAt <> invalid
        if m.clock.TotalMilliseconds() > m.regroupAt and m.scan = invalid and m.lastFiles <> invalid
            m.regroupAt = invalid
            finishScan(m.lastFiles, false)
        end if
    end if
    ' While a video plays, the network belongs to it: only the playing file's
    ' own header read goes ahead; folder scans, other files and poster
    ' lookups wait until playback stops.
    if m.playing = true
        ' Wherever it sits in the queue, and even while another header read
        ' is still finishing (its tracks fill the subtitle and audio menus).
        if m.probeActive < 3
            for k = 0 to m.probeQueue.Count() - 1
                if m.probeQueue[k].url = m.playingUrl
                    job = m.probeQueue[k]
                    m.probeQueue.Delete(k)
                    if startProbeStep(job) then m.probeActive = m.probeActive + 1
                    exit for
                end if
            end for
        end if
        return
    end if
    while m.probeActive < 2 and m.probeQueue.Count() > 0
        job = m.probeQueue.Shift()
        if startProbeStep(job) then m.probeActive = m.probeActive + 1
    end while
    if m.metaActive = invalid then m.metaActive = 0
    while m.metaActive < 4 and m.metaQueue.Count() > 0
        ' Deezer allows 50 requests per 5 seconds: stay under 40, and after a
        ' "quota exceeded" answer wait before asking again.
        if Instr(1, m.metaQueue[0].nextUrl, "api.deezer.com") > 0
            now = m.clock.TotalMilliseconds()
            if m.deezerPause <> invalid and now < m.deezerPause then exit while
            if m.deezerTimes = invalid then m.deezerTimes = []
            while m.deezerTimes.Count() > 0 and now - m.deezerTimes[0] > 5000
                m.deezerTimes.Shift()
            end while
            if m.deezerTimes.Count() >= 40 then exit while
            m.deezerTimes.Push(now)
        end if
        job = m.metaQueue.Shift()
        if startJob(job.nextUrl, job.stage = "nfo", job)
            m.metaActive = m.metaActive + 1
        else
            storeMeta(job.item, {ok: false})
        end if
    end while
end sub

' ---- Scanning -------------------------------------------------------------

sub startScan()
    if m.server.base = ""
        m.top.status = {phase: "setup", message: "Add your server in Settings to build your library."}
        return
    end if
    for each id in m.jobs.Keys()
        if m.jobs[id].kind = "dir"
            m.jobs[id].transfer.AsyncCancel()
            m.jobs.Delete(id)
        end if
    end for
    queue = []
    for each s in m.servers
        queue.Push({url: s.base, folders: [], depth: 0, root: s.base})
    end for
    if queue.Count() = 0 then queue.Push({url: m.server.base, folders: [], depth: 0, root: m.server.base})
    m.scan = {queue: queue, active: 0, folders: 0, files: [], errors: 0, denied: false, reported: 0}
    if m.quiet = true
        m.top.status = {phase: "checking", message: "Checking for new files..."}
    else
        m.top.status = {phase: "scanning", folders: 0, files: 0, message: "Scanning your server..."}
    end if
end sub

sub readFolder(job as Object, body as String)
    folder = job.folder
    m.scan.folders = m.scan.folders + 1
    root = folder.root
    if root = invalid then root = m.server.base
    for each entry in parseListing(body, folder.url, root)
        if entry.isDir
            if folder.depth < 14 and m.scan.folders + m.scan.queue.Count() < 6000
                names = []
                names.Append(folder.folders)
                names.Push(entry.name)
                m.scan.queue.Push({url: entry.url, folders: names, depth: folder.depth + 1, root: root})
            end if
        else if m.scan.files.Count() < 60000
            entry.folders = folder.folders
            entry.folderUrl = folder.url
            entry.ext = fileExtension(entry.name)
            m.scan.files.Push(entry)
        end if
    end for
end sub

' ---- Sorting the library --------------------------------------------------
' Turns every file the scan found into movies, shows (seasons, episodes) and
' albums (tracks). Archives, samples, extras and junk are set aside.

sub finishScan(files as Object, fresh as Boolean)
    m.lastFiles = files
    m.top.status = {phase: "sorting", message: "Sorting " + files.Count().ToStr() + " files..."}
    m.fixes = loadAllFixes()

    ' Pass 1: what each folder holds (art, subtitles, archives, playable files).
    folders = {}
    for each f in files
        info = folders[f.folderUrl]
        if info = invalid
            info = {art: {}, poster: "", fanart: "", subs: {}, subList: [], archives: 0, archiveSize: 0, media: 0, mainMedia: 0, name: "", folders: f.folders, nfo: "", nfoByStem: {}}
            if f.folders.Count() > 0 then info.name = f.folders[f.folders.Count() - 1]
            folders[f.folderUrl] = info
        end if
        ext = f.ext
        stemLower = LCase(fileStem(f.name))
        if isImageExt(ext)
            info.art[stemLower] = f.url
            if stemLower = "poster" or stemLower = "folder" or stemLower = "cover" or stemLower = "front" or stemLower = "movie" or stemLower = "show" or stemLower = "albumart" or stemLower = "albumartlarge"
                if info.poster = "" or stemLower = "poster" then info.poster = f.url
            else if stemLower = "fanart" or stemLower = "backdrop" or stemLower = "background" or stemLower = "art"
                info.fanart = f.url
            end if
        else if ext = "nfo"
            ' Release notes / Kodi info: by name ("Movie.2012.1080p.nfo" beside
            ' "Movie.2012.1080p.mkv"), and one per folder (not a sample's).
            info.nfoByStem[stemLower] = f.url
            if info.nfo = "" or Instr(1, LCase(f.name), "sample") = 0 then info.nfo = f.url
        else if isSubtitleExt(ext)
            ' "Movie.en.srt" belongs to "Movie".
            subStem = LCase(fileStem(fileStem(f.name)))
            info.subs[stemLower] = f.url
            if not info.subs.DoesExist(subStem) then info.subs[subStem] = f.url
            info.subs["*"] = f.url
            info.subList.Push({stem: stemLower, url: f.url})
        else if isArchiveName(f.name)
            info.archives = info.archives + 1
            if f.size > 0 then info.archiveSize = info.archiveSize + f.size
        else if isVideoExt(ext) or isAudioExt(ext)
            info.media = info.media + 1
            if Instr(1, LCase(f.name), "sample") = 0 and Instr(1, LCase(f.name), "trailer") = 0 then info.mainMedia = info.mainMedia + 1
        end if
    end for

    ' Ripped discs: one entry per disc (the folder above BDMV / VIDEO_TS).
    discs = {}
    for each f in files
        if isDiscExt(f.ext)
            i = discFolderIndex(f.folders)
            if i >= 0
                name = "Disc"
                if i > 0 then name = f.folders[i - 1]
                if not discs.DoesExist(name) then discs[name] = {name: name, size: 0}
                if f.size > 0 then discs[name].size = discs[name].size + f.size
            end if
        end if
    end for

    ' Pass 2: classify every video and audio file.
    movies = {}
    shows = {}
    albums = {}
    loose = []
    extras = 0
    for each f in files
        ext = f.ext
        if isVideoExt(ext)
            if skipVideo(f)
                extras = extras + 1
                continue for
            end if
            fixKey = "file:" + f.url
            fix = m.fixes[fixKey]
            info = classifyVideo(f.name, f.folders)
            info = applyFileHints(info, f)
            if fix <> invalid
                if fix.kind = "ignore" then continue for
                if fix.kind = "movie" and info.kind = "episode"
                    info = cleanTitle(fileStem(f.name))
                    info.kind = "movie"
                else if fix.kind = "episode" and info.kind = "movie"
                    info = {kind: "episode", title: info.title, year: info.year, season: 1, episode: 1, episodeTitle: ""}
                    if fix.title <> invalid then info.title = fix.title
                    if fix.season <> invalid then info.season = fix.season
                    if fix.episode <> invalid then info.episode = fix.episode
                end if
            end if
            record = {url: f.url, name: f.name, size: f.size, date: f.date, ext: ext, folderUrl: f.folderUrl, folders: f.folders, subtitles: findSubtitles(folders, f), playable: canPlay(ext)}
            if info.kind = "episode"
                addEpisode(shows, info, record, folders)
            else
                loose.Push({info: info, record: record})
            end if
        else if isAudioExt(ext)
            info = classifyTrack(f.name, f.folders)
            addTrack(albums, info, {url: f.url, name: f.name, size: f.size, date: f.date, ext: ext, folderUrl: f.folderUrl}, folders)
        end if
    end for

    ' Pass 3: a run of numbered "movies" in one folder ("Show - 01", "Show - 02",
    ' ...) is really a show with absolute episode numbers.
    runs = {}
    for each candidate in loose
        hit = rx("absolute").Match(rx("separators").ReplaceAll(fileStem(candidate.record.name), " "))
        if hit.Count() > 2
            number = Val(hit[2])
            if number > 0 and (number < 1900 or number > 2099)
                runKey = candidate.record.folderUrl + "|" + normKey(cleanTitle(hit[1]).title)
                if not runs.DoesExist(runKey) then runs[runKey] = []
                runs[runKey].Push({candidate: candidate, title: cleanTitle(hit[1]).title, number: number, rest: hit[3]})
            end if
        end if
    end for
    absorbed = {}
    for each runKey in runs
        group = runs[runKey]
        if group.Count() >= 3
            for each part in group
                info = {kind: "episode", title: part.title, year: "", season: 1, episode: part.number, episodeTitle: cleanTitle(part.rest, false).title}
                if Len(info.episodeTitle) < 2 then info.episodeTitle = ""
                addEpisode(shows, info, part.candidate.record, folders)
                absorbed[part.candidate.record.url] = true
            end for
        end if
    end for
    for each candidate in loose
        if not absorbed.DoesExist(candidate.record.url) then addMovie(movies, candidate.info, candidate.record, folders)
    end for

    ' Folders that hold only archives: nothing to play until they are extracted.
    packed = []
    for each folderUrl in folders
        info = folders[folderUrl]
        if info.archives > 0 and info.media = 0
            packed.Push({name: info.name, url: folderUrl, parts: info.archives, size: info.archiveSize, sortKey: LCase(info.name)})
        end if
    end for
    for each name in discs
        packed.Push({name: name + "  (disc folder)", url: "", parts: 0, size: discs[name].size, sortKey: LCase(name), disc: true})
    end for
    packed.SortBy("sortKey")

    library = finishLibrary(movies, shows, albums)

    signature = librarySignature(files)
    library.signature = signature
    library.packed = packed
    library.extras = extras
    library.server = serversKey()
    library.scannedAt = CreateObject("roDateTime").AsSeconds()
    unchanged = false
    if m.library <> invalid and fresh
        unchanged = m.library.signature = signature
    end if
    if not unchanged and fresh and m.lastSignature <> invalid then unchanged = m.lastSignature = signature
    m.library = library
    m.lastSignature = signature
    if not unchanged
        m.top.library = library
        writeJson(libraryCachePath(), library)
    end if
    m.top.status = {phase: "ready", message: summaryLine(library)}
    m.quiet = false
    m.nextScan = m.clock.TotalMilliseconds() + 30 * 60 * 1000
    if not unchanged then queueAllMeta(library)
    queueResolutionProbes(library)
end sub

function summaryLine(library as Object) as String
    return counted(library.movies.Count(), "movie") + "  ·  " + counted(library.shows.Count(), "show") + "  ·  " + counted(library.albums.Count(), "album")
end function

function counted(n as Integer, noun as String) as String
    if n = 1 then return "1 " + noun
    return n.ToStr() + " " + noun + "s"
end function

function isArchiveName(name as String) as Boolean
    ext = fileExtension(name)
    if ext = "rar" or ext = "zip" or ext = "7z" or ext = "tar" or ext = "gz" or ext = "tgz" or ext = "bz2" or ext = "xz" or ext = "iso" or ext = "001" then return true
    ' Old-style split parts: .r00 .r01 ... .s00
    if Len(ext) = 3 and (Left(ext, 1) = "r" or Left(ext, 1) = "s") and Val(Mid(ext, 2)) > 0 then return true
    if ext = "r00" or ext = "s00" then return true
    return false
end function

' Samples, trailers, extras and similar never go in the library.
function skipVideo(f as Object) as Boolean
    if discFolderIndex(f.folders) >= 0 then return true
    lowerName = LCase(f.name)
    for each folderName in f.folders
        lower = LCase(folderName)
        if lower = "sample" or lower = "samples" or lower = "proof" or lower = "screens" or lower = "screenshots" or lower = "extras" or lower = "featurettes" or lower = "behind the scenes" or lower = "deleted scenes" or lower = "trailers" or lower = "interviews" or lower = "shorts" or lower = "bonus" or lower = "other" or lower = "scenes" then return true
    end for
    if rx("sample").IsMatch(lowerName)
        if f.size < 0 or f.size < 400 then return true
    end if
    if rx("extraSuffix").IsMatch(fileStem(lowerName)) then return true
    return false
end function

function canPlay(ext as String) as Boolean
    return not (ext = "avi" or ext = "wmv" or ext = "mpg" or ext = "mpeg")
end function

' Folder names can settle what a file is: anything under a "TV" folder with a
' season folder is a show; a season pack folder ("Show.S02.1080p") names the
' show and season for files numbered "01.mkv".
function applyFileHints(info as Object, f as Object) as Object
    if info.kind = "episode" then return info
    i = f.folders.Count() - 1
    while i >= 0 and i >= f.folders.Count() - 2
        pack = rx("seasonPack").Match(rx("separators").ReplaceAll(f.folders[i], " "))
        if pack.Count() > 2
            numbered = rx("leadingNumber").Match(rx("separators").ReplaceAll(fileStem(f.name), " "))
            e = rx("episodeOnly").Match(rx("separators").ReplaceAll(fileStem(f.name), " "))
            number = -1
            rest = ""
            if e.Count() > 2
                number = Val(e[1])
                rest = e[2]
            else if numbered.Count() > 2
                number = Val(numbered[1])
                rest = numbered[2]
            end if
            if number > 0
                show = cleanTitle(pack[1]).title
                if pack[1].Trim() = "" and i > 0 then show = cleanTitle(f.folders[i - 1]).title
                if show = "" then show = "Unknown show"
                episodeTitle = cleanTitle(rest, false).title
                if Len(episodeTitle) < 2 then episodeTitle = ""
                return {kind: "episode", title: show, year: cleanTitle(pack[1]).year, season: Val(pack[2]), episode: number, episodeTitle: episodeTitle}
            end if
        end if
        i = i - 1
    end while
    ' Date-based episodes: "Show 2026 11 13".
    dated = rx("dated").Match(rx("separators").ReplaceAll(fileStem(f.name), " "))
    if dated.Count() > 4
        if dated[1].Trim() <> ""
            show = cleanTitle(dated[1]).title
            return {kind: "episode", title: show, year: "", season: Val(dated[2]), episode: Val(dated[3]) * 100 + Val(dated[4]), episodeTitle: dated[2] + "-" + dated[3] + "-" + dated[4], dated: true}
        end if
    end if
    return info
end function

' All subtitle files for a video: "Movie.srt", "Movie.en.srt",
' "Movie.eng.forced.srt" beside it, or anything in a Subs folder next to it
' (when that folder serves just this video, or names it).
function findSubtitles(folders as Object, f as Object) as Object
    found = []
    seen = {}
    stemLower = LCase(fileStem(f.name))
    here = folders[f.folderUrl]
    videos = 0
    if here <> invalid then videos = here.mainMedia
    if m.subEpisodeRx = invalid then m.subEpisodeRx = CreateObject("roRegex", "s(\d{1,2})[ ._-]?e(\d{1,3})", "i")
    episode = ""
    hit = m.subEpisodeRx.Match(stemLower)
    if hit.Count() > 2 then episode = "s" + Right("0" + Val(hit[1]).ToStr(), 2) + "e" + Right("0" + Val(hit[2]).ToStr(), 2)
    ' Every subtitle file in the video's folder or any folder inside it
    ' (Subs/, Subs/English/...): all of them when the folder holds one video,
    ' otherwise the ones named after this video or its episode.
    for each folderUrl in folders
        if Left(folderUrl, Len(f.folderUrl)) = f.folderUrl
            info = folders[folderUrl]
            for each s in info.subList
                rest = ""
                take = false
                if Left(s.stem, Len(stemLower)) = stemLower
                    take = true
                    rest = Mid(s.stem, Len(stemLower) + 1)
                else if episode <> ""
                    other = m.subEpisodeRx.Match(s.stem)
                    if other.Count() > 2
                        take = "s" + Right("0" + Val(other[1]).ToStr(), 2) + "e" + Right("0" + Val(other[2]).ToStr(), 2) = episode
                    end if
                    rest = s.stem
                else if videos <= 1
                    take = true
                    rest = s.stem
                end if
                if take and not seen.DoesExist(s.url)
                    seen[s.url] = true
                    found.Push(subtitleEntry(s.url, rest))
                end if
            end for
        end if
    end for
    return found
end function

' Language and "forced" from what follows the video's name: ".en", "_eng",
' "2_English", ".pt-BR.forced"...
function subtitleEntry(url as String, rest as String) as Object
    words = rx("nonAlnum").ReplaceAll(LCase(rest), " ").Trim().Split(" ")
    codes = {en: "eng", eng: "eng", english: "eng", es: "spa", spa: "spa", spanish: "spa", espanol: "spa", fr: "fre", fre: "fre", fra: "fre", french: "fre", de: "ger", ger: "ger", deu: "ger", german: "ger", it: "ita", ita: "ita", italian: "ita", pt: "por", por: "por", portuguese: "por", br: "por", ja: "jpn", jpn: "jpn", japanese: "jpn", ko: "kor", kor: "kor", korean: "kor", zh: "chi", chi: "chi", zho: "chi", chinese: "chi", ru: "rus", rus: "rus", russian: "rus", nl: "dut", dut: "dut", nld: "dut", dutch: "dut", sv: "swe", swe: "swe", swedish: "swe", no: "nor", nor: "nor", norwegian: "nor", da: "dan", dan: "dan", danish: "dan", fi: "fin", fin: "fin", finnish: "fin", pl: "pol", pol: "pol", polish: "pol", ar: "ara", ara: "ara", arabic: "ara", hi: "hin", hin: "hin", hindi: "hin", tr: "tur", tur: "tur", turkish: "tur", el: "gre", gre: "gre", greek: "gre", he: "heb", heb: "heb", hebrew: "heb", cs: "cze", cze: "cze", czech: "cze", hu: "hun", hun: "hun", hungarian: "hun", ro: "rum", rum: "rum", romanian: "rum", th: "tha", tha: "tha", thai: "tha", vi: "vie", vie: "vie", vietnamese: "vie", id: "ind", ind: "ind", indonesian: "ind"}
    names = {eng: "English", spa: "Spanish", fre: "French", ger: "German", ita: "Italian", por: "Portuguese", jpn: "Japanese", kor: "Korean", chi: "Chinese", rus: "Russian", dut: "Dutch", swe: "Swedish", nor: "Norwegian", dan: "Danish", fin: "Finnish", pol: "Polish", ara: "Arabic", hin: "Hindi", tur: "Turkish", gre: "Greek", heb: "Hebrew", cze: "Czech", hun: "Hungarian", rum: "Romanian", tha: "Thai", vie: "Vietnamese", ind: "Indonesian"}
    lang = ""
    forced = false
    sdh = false
    for each w in words
        if w = "forced" then forced = true
        if w = "sdh" or w = "cc" or w = "hi" then sdh = true
        if lang = "" and codes.DoesExist(w) and w <> "hi" then lang = codes[w]
    end for
    name = "Subtitles"
    if lang <> "" then name = names[lang]
    if forced then name = name + " (forced)"
    if sdh then name = name + " (SDH)"
    if lang = "" then lang = "und"
    return {url: url, lang: lang, name: name + " - file", forced: forced}
end function

function findSubtitle(folders as Object, f as Object) as String
    stemLower = LCase(fileStem(f.name))
    here = folders[f.folderUrl]
    if here <> invalid
        if here.subs.DoesExist(stemLower) then return here.subs[stemLower]
    end if
    ' A "Subs" folder beside the video.
    for each folderUrl in [f.folderUrl + "Subs/", f.folderUrl + "subs/", f.folderUrl + "Subtitles/", f.folderUrl + "subtitles/"]
        info = folders[folderUrl]
        if info <> invalid
            if info.subs.DoesExist(stemLower) then return info.subs[stemLower]
            for each k in info.subs
                if Instr(1, k, "eng") > 0 or Instr(1, k, "english") > 0 then return info.subs[k]
            end for
            return info.subs["*"]
        end if
    end for
    return ""
end function

function folderArt(folders as Object, folderUrl as String, stemLower as String) as Object
    art = {poster: "", fanart: "", thumb: ""}
    info = folders[folderUrl]
    if info <> invalid
        if info.art.DoesExist(stemLower) then art.thumb = info.art[stemLower]
        if info.art.DoesExist(stemLower + "-poster") then art.poster = info.art[stemLower + "-poster"]
        if info.art.DoesExist(stemLower + "-fanart") then art.fanart = info.art[stemLower + "-fanart"]
        if art.poster = "" then art.poster = info.poster
        if art.fanart = "" then art.fanart = info.fanart
    end if
    return art
end function

function parentFolderUrl(folderUrl as String) as String
    trimmed = Left(folderUrl, Len(folderUrl) - 1)
    slash = -1
    i = trimmed.Instr("/")
    while i >= 0
        slash = i
        i = trimmed.Instr(i + 1, "/")
    end while
    if slash < 0 then return ""
    return Left(trimmed, slash + 1)
end function

sub addMovie(movies as Object, info as Object, record as Object, folders as Object)
    key = "m:" + normKey(info.title) + info.year
    fix = m.fixes[key]
    if fix <> invalid
        if fix.kind = "ignore" or fix.hidden = true then return
    end if
    art = folderArt(folders, record.folderUrl, LCase(fileStem(record.name)))
    if art.poster = "" and art.thumb <> "" then art.poster = art.thumb
    movie = movies[key]
    if movie = invalid
        movie = {key: key, kind: "movie", title: info.title, aka: info.aka, year: info.year, files: [], poster: art.poster, fanart: art.fanart, date: record.date, sortKey: sortTitle(info.title) + info.year}
        movies[key] = movie
    end if
    if movie.poster = "" then movie.poster = art.poster
    if movie.fanart = "" then movie.fanart = art.fanart
    here = folders[record.folderUrl]
    if here <> invalid and (movie.nfo = invalid or movie.nfo = "")
        byName = here.nfoByStem[LCase(fileStem(record.name))]
        if byName <> invalid
            movie.nfo = byName
        else if here.nfo <> "" and here.mainMedia <= 1
            movie.nfo = here.nfo
        end if
    end if
    if record.date > movie.date then movie.date = record.date
    record.part = partNumber(record.name)
    record.label = versionLabel(record.name, record.ext)
    movie.files.Push(record)
end sub

sub addEpisode(shows as Object, info as Object, record as Object, folders as Object)
    key = "s:" + normKey(info.title)
    fix = m.fixes[key]
    if fix <> invalid
        if fix.kind = "ignore" or fix.hidden = true then return
    end if
    show = shows[key]
    showFolder = record.folderUrl
    if record.folders.Count() > 0
        if rx("season").IsMatch(record.folders[record.folders.Count() - 1]) or rx("seasonPack").IsMatch(rx("separators").ReplaceAll(record.folders[record.folders.Count() - 1], " ")) then showFolder = parentFolderUrl(record.folderUrl)
    end if
    showArt = folderArt(folders, showFolder, "")
    seasonArt = folderArt(folders, record.folderUrl, LCase(fileStem(record.name)))
    if show = invalid
        show = {key: key, kind: "show", title: info.title, aka: "", year: info.year, episodes: [], poster: showArt.poster, fanart: showArt.fanart, date: record.date, sortKey: sortTitle(info.title)}
        shows[key] = show
    end if
    if show.year = "" then show.year = info.year
    if show.poster = "" then show.poster = showArt.poster
    if show.fanart = "" then show.fanart = showArt.fanart
    if show.nfo = invalid or show.nfo = ""
        for each folderUrl in [showFolder, record.folderUrl]
            here = folders[folderUrl]
            if here <> invalid
                if here.nfo <> "" and (show.nfo = invalid or show.nfo = "") then show.nfo = here.nfo
            end if
        end for
    end if
    if record.date > show.date then show.date = record.date
    ' Two copies of one episode (720p and 1080p) become versions of it.
    episodeKey = key + ":" + info.season.ToStr() + ":" + info.episode.ToStr()
    for each existing in show.episodes
        if existing.key = episodeKey
            record.label = versionLabel(record.name, record.ext)
            existing.files.Push(record)
            return
        end if
    end for
    record.label = versionLabel(record.name, record.ext)
    episode = {key: episodeKey, season: info.season, episode: info.episode, title: info.episodeTitle, still: seasonArt.thumb, files: [record], date: record.date, dated: info.dated = true}
    episode.sortKey = Right("000" + info.season.ToStr(), 4) + Right("0000" + info.episode.ToStr(), 5)
    show.episodes.Push(episode)
end sub

sub addTrack(albums as Object, info as Object, record as Object, folders as Object)
    key = "a:" + normKey(info.artist) + "|" + normKey(info.album)
    ' The album's own folder (the folder above "CD1" / "Disc 2" when the
    ' tracks sit in disc folders). Two copies of an album in different
    ' folders (say a 2025 and a 2026 release) stay two albums.
    root = record.folderUrl
    if CreateObject("roRegex", "/(cd|disc|disk)[ _\.-]*\d+/?$", "i").IsMatch(root) then root = parentFolderUrl(root)
    first = albums[key]
    if first <> invalid and first.root <> invalid and first.root <> root
        key = key + "|" + normKey(Right(root, 40))
    end if
    fix = m.fixes[key]
    if fix <> invalid
        if fix.kind = "ignore" or fix.hidden = true then return
    end if
    album = albums[key]
    if album = invalid
        art = folderArt(folders, record.folderUrl, "")
        if art.poster = "" and record.folderUrl <> ""
            ' Covers in the album folder when the tracks sit in "CD1".
            art = folderArt(folders, parentFolderUrl(record.folderUrl), "")
        end if
        shown = albumSearchTitle(info.album)
        if shown = "" then shown = info.album
        album = {key: key, root: root, kind: "album", title: shown, artist: info.artist, year: info.year, tracks: [], poster: art.poster, fanart: "", date: record.date, sortKey: LCase(info.artist) + "|" + info.year + "|" + LCase(info.album)}
        albums[key] = album
    end if
    if record.date > album.date then album.date = record.date
    record.title = info.title
    record.number = info.number
    record.disc = info.disc
    record.sortKey = Right("00" + info.disc.ToStr(), 3) + Right("000" + info.number.ToStr(), 4) + LCase(info.title)
    album.tracks.Push(record)
end sub

function partNumber(name as String) as Integer
    hit = rx("part").Match(rx("separators").ReplaceAll(fileStem(name), " "))
    if hit.Count() > 1 then return Val(hit[1])
    return 0
end function

' "2160p HDR", "1080p", "720p", plus the container, for the Versions menu.
function versionLabel(name as String, ext as String) as String
    lower = LCase(name)
    parts = []
    for each res in ["2160p", "1080p", "720p", "576p", "480p"]
        if Instr(1, lower, res) > 0
            parts.Push(res)
            exit for
        end if
    end for
    if Instr(1, lower, "hdr") > 0 then parts.Push("HDR")
    if Instr(1, lower, "remux") > 0 then parts.Push("Remux")
    if Instr(1, lower, "hevc") > 0 or Instr(1, lower, "x265") > 0 or Instr(1, lower, "h265") > 0 then parts.Push("HEVC")
    parts.Push(UCase(ext))
    return parts.Join(" · ")
end function

' Short labels for a file: resolution, HDR, video codec, audio, remux.
' x264 / H.264 / AVC are one codec and x265 / H.265 / HEVC another, so each
' family gets one name.
function mediaTags(name as String, ext as String) as Object
    lower = " " + LCase(rx("separators").ReplaceAll(fileStem(name), " ")) + " "
    tags = []
    res = rx("tagRes").Match(lower)
    if res.Count() > 1 and Val(res[1]) >= 144 and Val(res[1]) <= 4320
        tags.Push(resolutionLabel(Val(res[1])))
    else if Instr(1, lower, " 4k ") > 0
        tags.Push("4K")
    else if Instr(1, lower, " 2k ") > 0
        tags.Push("2K")
    else if Instr(1, lower, " uhd ") > 0
        tags.Push("2160p")
    end if
    if rx("tagDv").IsMatch(lower) then tags.Push("DV")
    if Instr(1, lower, "hdr") > 0 then tags.Push("HDR")
    if rx("tag10bit").IsMatch(lower) then tags.Push("10-BIT")
    if rx("tagHc").IsMatch(lower) then tags.Push("HC SUBS")
    if rx("tagHevc").IsMatch(lower)
        tags.Push("HEVC")
    else if rx("tagAvc").IsMatch(lower)
        tags.Push("H.264")
    else if rx("tagAv1").IsMatch(lower)
        tags.Push("AV1")
    else if Instr(1, lower, "xvid") > 0 or Instr(1, lower, "divx") > 0
        tags.Push("XviD")
    end if
    if Instr(1, lower, "atmos") > 0
        tags.Push("ATMOS")
    else if Instr(1, lower, "truehd") > 0
        tags.Push("TrueHD")
    else if Instr(1, lower, "dts-hd") > 0 or Instr(1, lower, "dts hd") > 0 or Instr(1, lower, "dts-x") > 0
        tags.Push("DTS-HD")
    else if Instr(1, lower, " dts") > 0
        tags.Push("DTS")
    else if rx("tagDdp").IsMatch(lower)
        tags.Push("DD+")
    else if rx("tagAc3").IsMatch(lower)
        tags.Push("DD")
    end if
    ' Where it came from. A remux is straight off the disc, so it says REMUX.
    ' Theater copies first: they matter most to know about.
    if rx("tagCam").IsMatch(lower)
        tags.Push("CAM")
    else if rx("tagTs").IsMatch(lower)
        tags.Push("TS")
    else if rx("tagScreener").IsMatch(lower)
        tags.Push("Screener")
    else if rx("tagWorkprint").IsMatch(lower)
        tags.Push("Workprint")
    else if rx("tagDcp").IsMatch(lower)
        tags.Push("DCP")
    else if Instr(1, lower, "remux") > 0
        tags.Push("REMUX")
    else if rx("tagWebRip").IsMatch(lower)
        tags.Push("WebRip")
    else if rx("tagWebDl").IsMatch(lower)
        tags.Push("Web-DL")
    else if rx("tagBluRay").IsMatch(lower)
        tags.Push("Blu-Ray")
    else if rx("tagVhs").IsMatch(lower)
        tags.Push("VHSRip")
    else if rx("tagHdtv").IsMatch(lower)
        tags.Push("HDTV")
    else if rx("tagDvdRip").IsMatch(lower)
        tags.Push("DVDRip")
    else if rx("tagHdRip").IsMatch(lower)
        tags.Push("HDRip")
    else if rx("tagDvd").IsMatch(lower)
        tags.Push("DVD")
    end if
    return tags
end function

' "Movie.2010.1080p.BluRay.x264-AOC.mkv" -> "AOC"; "[SubsPlease] Show - 05.mkv" -> "SubsPlease".
function releaseGroup(name as String) as String
    stem = fileStem(name)
    hit = rx("groupPrefix").Match(stem)
    if hit.Count() > 1 then return hit[1].Trim()
    hit = rx("groupLead").Match(stem)
    if hit.Count() > 2 then return hit[1]
    ' Drop trailing [rarbg] / (eztv) style tags first.
    stem = rx("bracketTail").ReplaceAll(stem, "")
    hit = rx("groupSuffix").Match(stem)
    if hit.Count() < 2 then return ""
    group = hit[1]
    lower = LCase(group)
    ' The end of the name can be a format word rather than a group.
    for each word in ["dl", "rip", "x264", "x265", "h264", "h265", "hevc", "avc", "aac", "ac3", "dts", "web", "hdtv", "bluray", "remux", "1080p", "720p", "2160p", "480p", "10bit", "hdr", "sdr", "atmos", "proper", "repack", "eng", "subs", "sample", "trailer", "dub", "dubbed"]
        if lower = word then return ""
    end for
    if Val(group) > 0 and Len(group) <= 4 then return ""
    return group
end function

function resolutionLabel(height as Integer) as String
    if height >= 4000 then return "8K"
    if height >= 1800 then return "2160p"
    if height >= 1300 then return "1440p"
    if height >= 900 then return "1080p"
    if height >= 650 then return "720p"
    if height >= 540 then return "576p"
    if height >= 440 then return "480p"
    if height >= 330 then return "360p"
    return "240p"
end function

function sortTitle(title as String) as String
    lower = LCase(title)
    if Left(lower, 4) = "the " then lower = Mid(lower, 5)
    if Left(lower, 2) = "a " then lower = Mid(lower, 3)
    if Left(lower, 3) = "an " then lower = Mid(lower, 4)
    return lower
end function

function finishLibrary(movies as Object, shows as Object, albums as Object) as Object
    ' Copies whose names differ (year, title spelling) but that were matched
    ' to the same film become versions of one movie.
    byId = {}
    for each key in movies.Keys()
        meta = m.meta[key]
        if type(meta) = "roAssociativeArray"
            if meta.ok = true and meta.id <> invalid and meta.id <> ""
                first = byId[meta.id]
                if first = invalid
                    byId[meta.id] = key
                else if movies[first] <> invalid and movies[first].multipart <> true
                    movies[first].files.Append(movies[key].files)
                    movies.Delete(key)
                end if
            end if
        end if
    end for
    movieList = []
    for each key in movies
        movie = movies[key]
        ' Parts play in order; otherwise the best version comes first.
        for each file in movie.files
            file.rank = fileRank(file)
        end for
        if movie.files.Count() > 1
            hasParts = false
            for each file in movie.files
                if file.part > 0 then hasParts = true
            end for
            if hasParts then movie.files.SortBy("part") else movie.files.SortBy("rank", "r")
            movie.multipart = hasParts
        end if
        movie.group = movie.files[0].group
        movieList.Push(movie)
    end for
    movieList.SortBy("sortKey")

    showList = []
    for each key in shows
        show = shows[key]
        show.episodes.SortBy("sortKey")
        seasons = []
        last = -1
        for each episode in show.episodes
            for each file in episode.files
                file.rank = fileRank(file)
            end for
            if episode.files.Count() > 1 then episode.files.SortBy("rank", "r")
            if episode.season <> last
                seasons.Push(episode.season)
                last = episode.season
            end if
        end for
        show.seasons = seasons
        ' The group most of the episodes came from.
        counts = {}
        top = ""
        for each episode in show.episodes
            g = episode.files[0].group
            if g <> invalid and g <> ""
                if not counts.DoesExist(g) then counts[g] = 0
                counts[g] = counts[g] + 1
                if top = "" or counts[g] > counts[top] then top = g
            end if
        end for
        show.group = top
        showList.Push(show)
    end for
    showList.SortBy("sortKey")

    albumList = []
    for each key in albums
        album = albums[key]
        album.tracks.SortBy("sortKey")
        albumList.Push(album)
    end for
    albumList.SortBy("sortKey")

    recent = []
    for each movie in movieList
        if movie.date <> "" then recent.Push({key: movie.key, date: movie.date})
    end for
    for each show in showList
        if show.date <> "" then recent.Push({key: show.key, date: show.date})
    end for
    for each album in albumList
        if album.date <> "" then recent.Push({key: album.key, date: album.date})
    end for
    recent.SortBy("date", "r")
    while recent.Count() > 40
        recent.Pop()
    end while
    return {movies: movieList, shows: showList, albums: albumList, recent: recent}
end function

' Higher is better: plays on Roku, sensible resolution, mp4 over mkv.
function fileRank(file as Object) as Integer
    rank = 0
    if file.playable then rank = rank + 1000
    lower = LCase(file.name)
    if Instr(1, lower, "1080p") > 0 then rank = rank + 300
    ' 4K first only when this Roku is showing a 4K picture.
    if Instr(1, lower, "2160p") > 0
        if showing4k() then rank = rank + 350 else rank = rank + 250
    end if
    if Instr(1, lower, "720p") > 0 then rank = rank + 200
    hevc = Instr(1, lower, "hevc") > 0 or Instr(1, lower, "x265") > 0 or Instr(1, lower, "h265") > 0 or Instr(1, lower, "h.265") > 0
    file.hevc = hevc
    ' XviD / DivX (MPEG-4 Part 2): Roku has no decoder for it in any container.
    file.xvid = Instr(1, lower, "xvid") > 0 or Instr(1, lower, "divx") > 0
    if file.xvid then rank = rank - 600
    ' Wider than 1920 (2K cinema, 4K): too big for a 1080p Roku's decoder.
    spaced = " " + rx("separators").ReplaceAll(lower, " ") + " "
    file.wide = Instr(1, spaced, " 2k ") > 0
    if file.wide and not canDecode4kAvc() then rank = rank - 600
    file.uhd = Instr(1, lower, "2160p") > 0 or Instr(1, lower, ".4k.") > 0 or Instr(1, lower, " 4k ") > 0 or Instr(1, lower, "uhd") > 0
    file.remux = Instr(1, lower, "remux") > 0
    file.tags = mediaTags(file.name, file.ext)
    file.group = releaseGroup(file.name)
    ' Remuxes (30-80 GB) rarely stream well from a seedbox: pick a smaller copy first.
    if file.remux then rank = rank - 400
    if file.size > 25000 then rank = rank - 200
    ' A Roku without an HEVC decoder should get the H.264 copy when there is one.
    if hevc and not canDecodeHevc() then rank = rank - 600
    ' A 1080p Roku can't decode 4K H.264: the 1080p copy first.
    if file.uhd and not hevc and not canDecode4kAvc() then rank = rank - 600
    if file.ext = "mp4" or file.ext = "m4v" then rank = rank + 20
    if file.ext = "mkv" then rank = rank + 10
    return rank
end function

function describeEntries(entries as Object) as Object
    out = []
    for each entry in entries
        kind = "file"
        ext = fileExtension(entry.name)
        if entry.isDir
            kind = "folder"
        else if isVideoExt(ext)
            kind = "video"
        else if isAudioExt(ext)
            kind = "audio"
        else if isImageExt(ext)
            kind = "image"
        else if isArchiveName(entry.name)
            kind = "archive"
        end if
        entry.kind = kind
        entry.ext = ext
        entry.sortKey = "1" + LCase(entry.name)
        if entry.isDir then entry.sortKey = "0" + LCase(entry.name)
        out.Push(entry)
    end for
    out.SortBy("sortKey")
    return out
end function

function findItem(key as String) as Dynamic
    if m.library = invalid then return invalid
    for each listName in ["movies", "shows", "albums"]
        for each item in m.library[listName]
            if item.key = key then return item
        end for
    end for
    return invalid
end function

' ---- Viewer fixes (kept in the registry, so they survive cache clears) -----

function fixSection() as Object
    return CreateObject("roRegistrySection", "boxstream-fixes")
end function

function loadAllFixes() as Object
    fixes = {}
    fixes.SetModeCaseSensitive()
    section = fixSection()
    for each name in section.GetKeyList()
        value = ParseJson(section.Read(name))
        if type(value) = "roAssociativeArray" and value.key <> invalid then fixes[value.key] = value
    end for
    return fixes
end function

function loadFix(key as String) as Object
    section = fixSection()
    name = fixName(key)
    if section.Exists(name)
        value = ParseJson(section.Read(name))
        if type(value) = "roAssociativeArray" then return value
    end if
    return {key: key}
end function

sub saveFix(key as String, fix as Object)
    fix.key = key
    section = fixSection()
    section.Write(fixName(key), FormatJson(fix))
    section.Flush()
end sub

function fixName(key as String) as String
    digest = CreateObject("roEVPDigest")
    digest.Setup("md5")
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(key)
    return digest.Process(bytes)
end function

' ---- Details: posters, plots, cast ----------------------------------------
' Movies: Cinemeta (IMDb data, no key). TV: TVmaze (no key). Music: Deezer
' (no key). Results are cached; failed lookups are retried after three days.

sub sendAllMeta(library as Object)
    batch = []
    for each listName in ["movies", "shows", "albums"]
        for each item in library[listName]
            meta = m.meta[item.key]
            if meta <> invalid then batch.Push(meta)
        end for
    end for
    if batch.Count() > 0 then m.top.metaBatch = batch
end sub

sub queueAllMeta(library as Object)
    m.metaQueue = []
    now = CreateObject("roDateTime").AsSeconds()
    batch = []
    for each listName in ["movies", "shows", "albums"]
        for each item in library[listName]
            meta = m.meta[item.key]
            if meta = invalid
                queueMeta(item, false)
            else if meta.ok = true
                batch.Push(meta)
            else if now - meta.at > 3 * 86400
                queueMeta(item, false)
            else
                batch.Push(meta)
            end if
        end for
    end for
    if batch.Count() > 0 then m.top.metaBatch = batch
end sub

sub queueMeta(item as Object, first as Boolean)
    if m.fixes = invalid then m.fixes = loadAllFixes()
    fix = m.fixes[item.key]
    if fix = invalid then fix = {}
    job = {kind: "meta", item: {key: item.key, kind: item.kind, title: item.title, aka: item.aka, year: item.year, artist: item.artist}, stage: "search", source: "first", qIndex: 0}
    nfoUrl = ""
    if item.nfo <> invalid then nfoUrl = item.nfo
    if fix.id <> invalid
        job.stage = "detail"
        job.id = fix.id
        if type(fix.suggestion) = "roAssociativeArray" then job.suggestion = fix.suggestion
        job.nextUrl = detailUrl(item.kind, fix.id)
        if item.kind = "show" and Left(fix.id, 2) = "tt"
            job.stage = "lookup"
            job.nextUrl = "https://api.tvmaze.com/lookup/shows?imdb=" + fix.id
        end if
    else
        job.queries = lookupNames(item, fix)
        job.nextUrl = searchUrl(item.kind, job.queries[0])
        ' A release NFO or Kodi .nfo usually carries the IMDb id: read it first.
        if nfoUrl <> "" and (item.kind = "movie" or item.kind = "show") and fix.query = invalid
            job.stage = "nfo"
            job.nextUrl = nfoUrl
        end if
    end if
    if first then m.metaQueue.Unshift(job) else m.metaQueue.Push(job)
end sub

' The names to try, in order: the title, each AKA title, then the same
' without a leading part number ("1 Maugli Raksha" -> "Maugli Raksha").
function lookupNames(item as Object, fix as Object) as Object
    names = []
    if fix.query <> invalid
        names.Push(fix.query)
        return names
    end if
    if item.kind = "album"
        ' Release extras ([WEB FLAC 24-44], {label, catalog no.}, (2024),
        ' "Deluxe Edition") make Deezer find nothing, so cleaner searches
        ' follow, and last the artist alone (the right album is picked from
        ' their list by its title).
        artist = ""
        if item.artist <> invalid and item.artist <> "Unknown artist" then artist = item.artist
        clean = albumSearchTitle(item.title)
        seen = {}
        for each q in [(artist + " " + item.title).Trim(), (artist + " " + clean).Trim(), clean, artist]
            if q <> "" and not seen.DoesExist(LCase(q))
                seen[LCase(q)] = true
                names.Push(q)
            end if
        end for
        return names
    end if
    base = [item.title]
    if item.aka <> invalid and item.aka <> ""
        for each other in item.aka.Split("|")
            base.Push(other)
        end for
    end if
    seen = {}
    for each name in base
        if not seen.DoesExist(LCase(name))
            seen[LCase(name)] = true
            names.Push(name)
        end if
    end for
    for each name in base
        hit = rx("leadingPart").Match(name)
        if hit.Count() > 1
            if not seen.DoesExist(LCase(hit[1]))
                seen[LCase(hit[1])] = true
                names.Push(hit[1])
            end if
        end if
    end for
    return names
end function

function imdbSearchUrl(query as String) as String
    return "https://v3.sg.media-imdb.com/suggestion/x/" + escape(LCase(query)) + ".json"
end function

function escape(text as String) as String
    if m.escaper = invalid then m.escaper = CreateObject("roUrlTransfer")
    return m.escaper.Escape(text)
end function

function searchUrl(kind as String, query as String) as String
    if kind = "movie" then return "https://v3-cinemeta.strem.io/catalog/movie/top/search=" + escape(query) + ".json"
    if kind = "show" then return "https://api.tvmaze.com/search/shows?q=" + escape(query)
    return "https://api.deezer.com/search/album?limit=10&q=" + escape(query)
end function

function detailUrl(kind as String, id as String) as String
    if kind = "movie" then return "https://v3-cinemeta.strem.io/meta/movie/" + id + ".json"
    if kind = "show" then return "https://api.tvmaze.com/shows/" + id + "?embed%5B%5D=episodes&embed%5B%5D=cast"
    return "https://api.deezer.com/album/" + id
end function

sub handleMeta(job as Object, code as Integer, body as String)
    item = job.item
    ' Deezer's "quota exceeded" (error code 4): the same request again later.
    if Instr(1, job.nextUrl, "api.deezer.com") > 0 and Instr(1, body, "Quota limit exceeded") > 0
        m.deezerPause = m.clock.TotalMilliseconds() + 6000
        m.metaQueue.Push(job)
        return
    end if
    if job.stage = "nfo"
        id = ""
        if code = 200
            hit = CreateObject("roRegex", "(tt\d{7,9})", "").Match(body)
            if hit.Count() > 1 then id = hit[1]
        end if
        job.fromNfo = id
        if id <> ""
            if item.kind = "movie"
                job.stage = "detail"
                job.nextUrl = detailUrl("movie", id)
            else
                job.stage = "lookup"
                job.nextUrl = "https://api.tvmaze.com/lookup/shows?imdb=" + id
            end if
        else
            job.stage = "search"
            job.nextUrl = searchUrl(item.kind, job.queries[0])
        end if
        m.metaQueue.Unshift(job)
        return
    end if
    data = invalid
    if code = 200 then data = ParseJson(body)
    if job.stage = "search"
        query = job.queries[job.qIndex]
        ' Movies and shows are scored against the name searched for; albums
        ' keep their own title (their searches add the artist).
        if item.kind <> "album" then item.title = query
        if job.source = "first"
            id = ""
            if data <> invalid then id = bestMatch(item, data)
            if id <> ""
                job.stage = "detail"
                job.nextUrl = detailUrl(item.kind, id)
                m.metaQueue.Unshift(job)
                return
            end if
            ' Not in Cinemeta / TVmaze under this name: ask IMDb's own search.
            if item.kind = "movie" or item.kind = "show"
                job.source = "imdb"
                job.nextUrl = imdbSearchUrl(query)
                m.metaQueue.Unshift(job)
                return
            end if
        else
            pick = invalid
            if data <> invalid then pick = bestImdb(item, data)
            if pick <> invalid
                job.suggestion = pick
                if item.kind = "movie"
                    job.stage = "detail"
                    job.nextUrl = detailUrl("movie", pick.id)
                else
                    job.stage = "lookup"
                    job.nextUrl = "https://api.tvmaze.com/lookup/shows?imdb=" + pick.id
                end if
                m.metaQueue.Unshift(job)
                return
            end if
        end if
        ' Next name (AKA, without the part number...).
        job.qIndex = job.qIndex + 1
        if job.qIndex < job.queries.Count()
            job.source = "first"
            job.nextUrl = searchUrl(item.kind, job.queries[job.qIndex])
            m.metaQueue.Unshift(job)
            return
        end if
        storeMeta(item, {ok: false})
        return
    end if
    if job.stage = "lookup"
        ' TVmaze by IMDb id: then the full details with episodes and cast.
        if data <> invalid and data.id <> invalid
            job.stage = "detail"
            job.nextUrl = detailUrl("show", data.id.ToStr())
            m.metaQueue.Unshift(job)
        else if job.suggestion <> invalid
            storeMeta(item, imdbMeta(job.suggestion, item.kind))
        else if job.fromNfo <> invalid and job.fromNfo <> ""
            job.fromNfo = ""
            job.stage = "search"
            job.source = "first"
            job.qIndex = 0
            job.nextUrl = searchUrl(item.kind, job.queries[0])
            m.metaQueue.Unshift(job)
        else
            storeMeta(item, {ok: false})
        end if
        return
    end if
    ' Details.
    meta = {ok: false}
    if data <> invalid
        if item.kind = "movie"
            meta = movieMeta(data.meta)
        else if item.kind = "show"
            meta = showMeta(data)
        else
            meta = albumMeta(data)
        end if
    end if
    if meta.ok <> true and job.fromNfo <> invalid and job.fromNfo <> "" and job.suggestion = invalid
        job.fromNfo = ""
        job.stage = "search"
        job.source = "first"
        job.qIndex = 0
        job.nextUrl = searchUrl(item.kind, job.queries[0])
        m.metaQueue.Unshift(job)
        return
    end if
    ' Found on IMDb but Cinemeta has no page for it: IMDb's own summary.
    if meta.ok <> true and job.suggestion <> invalid then meta = imdbMeta(job.suggestion, item.kind)
    storeMeta(item, meta)
end sub

'  A stored match whose title doesn't fit the file's name (and that the
' viewer didn't choose with Fix match).
function weakMatch(key as String, entry as Object, fixes as Object) as Boolean
    if Left(key, 2) <> "m:" and Left(key, 2) <> "s:" then return false
    fix = fixes[key]
    if fix <> invalid
        if fix.id <> invalid then return false
    end if
    if entry.title = invalid then return false
    wanted = Mid(key, 3)
    year = ""
    if Len(wanted) > 4 and Val(Right(wanted, 4)) > 1880
        year = Right(wanted, 4)
        wanted = Left(wanted, Len(wanted) - 4)
    end if
    score = titleScore(normKey(textOf(entry.title)), wanted)
    if year <> "" and textOf(entry.year) <> ""
        found = Left(textOf(entry.year), 4)
        if found = year then score = score + 30
        if Abs(Val(found) - Val(year)) > 1 then score = score - 40
    end if
    return score < 40
end function

' How alike two titles are (both already normalised): the same, the same
' without a leading "the", or one inside the other covering most of it.
function titleScore(name as String, wanted as String) as Integer
    if name = "" or wanted = "" then return 0
    if name = wanted then return 50
    if Left(name, 3) = "the" and Mid(name, 4) = wanted then return 45
    if Left(wanted, 3) = "the" and Mid(wanted, 4) = name then return 45
    shorter = Len(name)
    longer = Len(wanted)
    if longer < shorter
        shorter = Len(wanted)
        longer = Len(name)
    end if
    if Instr(1, name, wanted) > 0 or Instr(1, wanted, name) > 0
        if shorter * 10 >= longer * 8 then return 35
        return 5
    end if
    ' A letter or two off ("Vsceral" for "Visceral").
    same = likeness(name, wanted)
    if same >= 90 then return 42
    if same >= 80 and shorter >= 6 then return 32
    ' The file names only the start of a long title ("Vsceral Between the
    ' Ropes" for "Visceral: Between the Ropes of Madness").
    if shorter >= 8 and shorter * 2 >= longer
        if Len(name) > Len(wanted) then head = Left(name, Len(wanted)) else head = Left(wanted, Len(name))
        if Len(name) > Len(wanted) then other = wanted else other = name
        if likeness(head, other) >= 88 then return 34
    end if
    return 0
end function

' How alike two strings are, 0-100 (edit distance against the longer one).
function likeness(a as String, b as String) as Integer
    la = Len(a)
    lb = Len(b)
    if la = 0 or lb = 0 then return 0
    if la > 60 or lb > 60 then return 0
    prev = []
    for j = 0 to lb
        prev.Push(j)
    end for
    for i = 1 to la
        cur = [i]
        ca = Mid(a, i, 1)
        for j = 1 to lb
            cost = 1
            if ca = Mid(b, j, 1) then cost = 0
            v = prev[j - 1] + cost
            if prev[j] + 1 < v then v = prev[j] + 1
            if cur[j - 1] + 1 < v then v = cur[j - 1] + 1
            cur.Push(v)
        end for
        prev = cur
    end for
    longer = la
    if lb > longer then longer = lb
    return Int(100 - prev[lb] * 100 / longer)
end function

' IMDb search results: the right kind of title, best name and year fit.
function bestImdb(item as Object, data as Object) as Dynamic
    if data.d = invalid then return invalid
    wanted = normKey(item.title)
    best = invalid
    bestScore = -1
    fitting = 0
    index = 0
    for each r in data.d
        kind = textOf(r.qid)
        fits = false
        if item.kind = "movie" then fits = kind = "movie" or kind = "short" or kind = "tvMovie" or kind = "video" or kind = "tvSpecial" or kind = "musicVideo"
        if item.kind = "show" then fits = kind = "tvSeries" or kind = "tvMiniSeries"
        if fits and Left(textOf(r.id), 2) = "tt"
            fitting = fitting + 1
            score = 10 - index
            name = normKey(textOf(r.l))
            score = score + titleScore(name, wanted)
            year = textOf(r.y)
            if item.year <> "" and year = item.year then score = score + 40
            if item.year <> "" and year <> "" and year <> item.year
                if Abs(Val(year) - Val(item.year)) = 1 then score = score + 10 else score = score - 40
            end if
            if score > bestScore
                bestScore = score
                best = r
            end if
        end if
        index = index + 1
    end for
    if bestScore < 40 and not (fitting = 1 and bestScore >= 15) then return invalid
    image = ""
    if best.i <> invalid then image = textOf(best.i.imageUrl)
    return {id: textOf(best.id), title: textOf(best.l), year: textOf(best.y), image: image, stars: textOf(best.s)}
end function

function imdbMeta(s as Object, kind as String) as Object
    meta = {ok: true, source: "IMDb", id: s.id, title: s.title, year: s.year}
    poster = s.image
    if poster <> "" and Instr(1, poster, "._V1_") > 0 then poster = Left(poster, Instr(1, poster, "._V1_") - 1) + "._V1_SX400.jpg"
    meta.poster = poster
    meta.posterLarge = s.image
    meta.backdrop = ""
    meta.logo = ""
    meta.overview = ""
    meta.rating = ""
    meta.runtime = ""
    meta.genres = ""
    meta.cast = []
    if s.stars <> ""
        for each name in s.stars.Split(", ")
            meta.cast.Push({name: name.Trim(), role: "", photo: ""})
        end for
    end if
    meta.director = ""
    meta.writer = ""
    meta.episodes = {}
    return meta
end function

' Picks the result whose title (and year, when known) fits best.
function bestMatch(item as Object, data as Object) as String
    wanted = normKey(item.title)
    if item.kind = "album" then wanted = normKey(albumSearchTitle(item.title))
    best = ""
    bestScore = -1
    list = []
    if item.kind = "movie"
        if data.metas <> invalid then list = data.metas
    else if item.kind = "show"
        if type(data) = "roArray" then list = data
    else
        if data.data <> invalid then list = data.data
    end if
    index = 0
    for each result in list
        score = 10 - index
        if item.kind = "movie"
            id = result.id
            name = result.name
            year = ""
            if result.releaseInfo <> invalid then year = Left(result.releaseInfo.ToStr(), 4)
        else if item.kind = "show"
            show = result.show
            id = show.id.ToStr()
            name = show.name
            year = ""
            if show.premiered <> invalid then year = Left(show.premiered, 4)
        else
            id = result.id.ToStr()
            name = result.title
            year = ""
            if result.artist <> invalid and item.artist <> invalid
                if normKey(result.artist.name) = normKey(item.artist) then score = score + 40
            end if
        end if
        if name <> invalid
            score = score + titleScore(normKey(name), wanted)
        end if
        if item.year <> "" and year = item.year then score = score + 30
        if item.year <> "" and year <> "" and year <> item.year
            if Abs(Val(year) - Val(item.year)) = 1 then score = score + 10 else score = score - 40
        end if
        if score > bestScore
            bestScore = score
            best = id
        end if
        index = index + 1
        if index >= 10 then exit for
    end for
    ' Movies and shows need the same title, or a nearly identical one with
    ' the right year ("Mars" 2024 is not "Marsupilami" 2026); otherwise
    ' the IMDb search gets a turn. A search with just one answer that looks
    ' like the name (and doesn't contradict the year) is that answer.
    if item.kind = "movie" or item.kind = "show"
        if index = 1 and bestScore >= 15 then return best
        if bestScore < 40 then return ""
    else
        ' Albums: the same artist and a close title (Deezer answers almost any
        ' search with something, e.g. a DJ mix with a random album).
        need = 42
        if item.artist <> invalid and item.artist <> "" and item.artist <> "Unknown artist" then need = 72
        if bestScore < need then return ""
    end if
    return best
end function

function readImdbCandidates(kind as String, code as Integer, body as String) as Object
    results = []
    if code <> 200 then return results
    data = ParseJson(body)
    if data = invalid or data.d = invalid then return results
    for each r in data.d
        qid = textOf(r.qid)
        fits = false
        if kind = "movie" then fits = qid = "movie" or qid = "short" or qid = "tvMovie" or qid = "video" or qid = "tvSpecial"
        if kind = "show" then fits = qid = "tvSeries" or qid = "tvMiniSeries"
        if fits and Left(textOf(r.id), 2) = "tt"
            image = ""
            if r.i <> invalid then image = textOf(r.i.imageUrl)
            poster = image
            if poster <> "" and Instr(1, poster, "._V1_") > 0 then poster = Left(poster, Instr(1, poster, "._V1_") - 1) + "._V1_SX300.jpg"
            detail = textOf(r.y)
            if textOf(r.s) <> "" then detail = detail + "  ·  " + textOf(r.s)
            results.Push({id: textOf(r.id), title: textOf(r.l), year: detail, poster: poster, suggestion: {id: textOf(r.id), title: textOf(r.l), year: textOf(r.y), image: image, stars: textOf(r.s)}})
        end if
    end for
    return results
end function

function readCandidates(kind as String, code as Integer, body as String) as Object
    results = []
    if code <> 200 then return results
    data = ParseJson(body)
    if data = invalid then return results
    if kind = "movie" and data.metas <> invalid
        for each r in data.metas
            results.Push({id: r.id, title: textOf(r.name), year: textOf(r.releaseInfo), poster: textOf(r.poster).Replace("/small/", "/medium/")})
            if results.Count() >= 12 then exit for
        end for
    else if kind = "show" and type(data) = "roArray"
        for each r in data
            poster = ""
            if r.show.image <> invalid then poster = textOf(r.show.image.medium)
            results.Push({id: r.show.id.ToStr(), title: textOf(r.show.name), year: Left(textOf(r.show.premiered), 4), poster: poster})
            if results.Count() >= 12 then exit for
        end for
    else if data.data <> invalid
        for each r in data.data
            artist = ""
            if r.artist <> invalid then artist = textOf(r.artist.name)
            results.Push({id: r.id.ToStr(), title: textOf(r.title), year: artist, poster: textOf(r.cover_big)})
            if results.Count() >= 12 then exit for
        end for
    end if
    return results
end function

function textOf(value as Dynamic) as String
    if value = invalid then return ""
    t = type(value)
    if t = "roString" or t = "String" then return value
    if t = "roInt" or t = "Integer" or t = "roFloat" or t = "Float" or t = "roDouble" or t = "Double" or t = "LongInteger" then return value.ToStr()
    if t = "roArray"
        parts = []
        for each v in value
            parts.Push(textOf(v))
        end for
        return parts.Join(", ")
    end if
    return ""
end function

function plainText(html as Dynamic) as String
    text = rx("tags").ReplaceAll(textOf(html), "")
    return text.Replace("&amp;", "&").Replace("&quot;", Chr(34)).Replace("&#39;", "'").Replace("&nbsp;", " ").Trim()
end function

function movieMeta(data as Dynamic) as Object
    if type(data) <> "roAssociativeArray" then return {ok: false}
    id = textOf(data.id)
    meta = {ok: true, source: "IMDb via Cinemeta", id: id}
    meta.title = textOf(data.name)
    meta.year = Left(textOf(data.releaseInfo), 4)
    if meta.year = "" then meta.year = Left(textOf(data.year), 4)
    meta.poster = textOf(data.poster).Replace("/small/", "/medium/")
    meta.posterLarge = meta.poster.Replace("/medium/", "/large/")
    meta.backdrop = textOf(data.background).Replace("/medium/", "/large/")
    meta.logo = textOf(data.logo)
    meta.overview = plainText(data.description)
    meta.rating = textOf(data.imdbRating)
    meta.runtime = textOf(data.runtime)
    genres = data.genres
    if genres = invalid then genres = data.genre
    meta.genres = textOf(genres)
    meta.cast = []
    if type(data.cast) = "roArray"
        for each name in data.cast
            meta.cast.Push({name: textOf(name), role: "", photo: ""})
            if meta.cast.Count() >= 12 then exit for
        end for
    end if
    meta.director = textOf(data.director)
    meta.writer = textOf(data.writer)
    meta.awards = textOf(data.awards)
    meta.country = textOf(data.country)
    meta.released = Left(textOf(data.released), 10)
    meta.certification = ""
    return meta
end function

function showMeta(data as Dynamic) as Object
    if type(data) <> "roAssociativeArray" then return {ok: false}
    meta = {ok: true, source: "TVmaze", id: textOf(data.id)}
    meta.title = textOf(data.name)
    meta.year = Left(textOf(data.premiered), 4)
    meta.ended = Left(textOf(data.ended), 4)
    meta.status = textOf(data.status)
    if data.image <> invalid
        meta.poster = textOf(data.image.medium)
        meta.posterLarge = textOf(data.image.original)
    end if
    imdb = ""
    if data.externals <> invalid then imdb = textOf(data.externals.imdb)
    meta.imdb = imdb
    meta.backdrop = ""
    meta.logo = ""
    if imdb <> ""
        meta.backdrop = "https://images.metahub.space/background/large/" + imdb + "/img"
        meta.logo = "https://images.metahub.space/logo/medium/" + imdb + "/img"
    end if
    meta.overview = plainText(data.summary)
    if data.rating <> invalid then meta.rating = textOf(data.rating.average)
    meta.runtime = textOf(data.averageRuntime)
    if meta.runtime = "" then meta.runtime = textOf(data.runtime)
    if meta.runtime <> "" then meta.runtime = meta.runtime + " min"
    meta.genres = textOf(data.genres)
    meta.network = ""
    if data.network <> invalid then meta.network = textOf(data.network.name)
    if meta.network = "" and data.webChannel <> invalid then meta.network = textOf(data.webChannel.name)
    meta.cast = []
    meta.episodes = {}
    embedded = data._embedded
    if embedded <> invalid
        if type(embedded.cast) = "roArray"
            for each c in embedded.cast
                photo = ""
                if c.person <> invalid
                    if c.person.image <> invalid then photo = textOf(c.person.image.medium)
                    role = ""
                    if c.character <> invalid then role = textOf(c.character.name)
                    meta.cast.Push({name: textOf(c.person.name), role: role, photo: photo})
                end if
                if meta.cast.Count() >= 15 then exit for
            end for
        end if
        if type(embedded.episodes) = "roArray"
            for each e in embedded.episodes
                still = ""
                if e.image <> invalid then still = textOf(e.image.medium)
                rating = ""
                if e.rating <> invalid then rating = textOf(e.rating.average)
                meta.episodes[textOf(e.season) + ":" + textOf(e.number)] = {name: textOf(e.name), airdate: textOf(e.airdate), runtime: textOf(e.runtime), still: still, overview: plainText(e.summary), rating: rating}
            end for
        end if
    end if
    return meta
end function

function albumMeta(data as Dynamic) as Object
    if type(data) <> "roAssociativeArray" then return {ok: false}
    if data.error <> invalid then return {ok: false}
    meta = {ok: true, source: "Deezer", id: textOf(data.id)}
    meta.title = textOf(data.title)
    meta.poster = textOf(data.cover_big)
    meta.posterLarge = textOf(data.cover_xl)
    meta.released = textOf(data.release_date)
    meta.year = Left(meta.released, 4)
    meta.label = textOf(data.label)
    meta.genres = ""
    if data.genres <> invalid and type(data.genres.data) = "roArray"
        names = []
        for each g in data.genres.data
            names.Push(textOf(g.name))
        end for
        meta.genres = names.Join(", ")
    end if
    meta.backdrop = ""
    meta.artist = ""
    if data.artist <> invalid
        meta.artist = textOf(data.artist.name)
        meta.artistPhoto = textOf(data.artist.picture_xl)
        meta.backdrop = meta.artistPhoto
    end if
    total = 0
    if data.duration <> invalid then total = data.duration
    meta.runtime = ""
    if total > 0 then meta.runtime = Int(total / 60).ToStr() + " min"
    meta.trackCount = textOf(data.nb_tracks)
    meta.tracks = []
    if data.tracks <> invalid and type(data.tracks.data) = "roArray"
        for each t in data.tracks.data
            meta.tracks.Push({title: textOf(t.title), seconds: t.duration})
        end for
    end if
    meta.overview = ""
    return meta
end function

sub storeMeta(item as Object, meta as Object)
    if item.kind = "movie" and meta.ok = true and meta.id <> invalid and m.library <> invalid and m.lastFiles <> invalid
        for each other in m.library.movies
            if other.key <> item.key
                known = m.meta[other.key]
                if type(known) = "roAssociativeArray"
                    if known.id = meta.id then m.regroupAt = m.clock.TotalMilliseconds() + 5000
                end if
            end if
        end for
    end if
    meta.key = item.key
    meta.kind = item.kind
    meta.at = CreateObject("roDateTime").AsSeconds()
    m.meta[item.key] = meta
    m.metaDirty = m.metaDirty + 1
    m.metaOut.Push(meta)
    if m.metaQueue.Count() = 0 and m.metaActive = 0 then flushMeta(true)
end sub

sub flushMeta(force as Boolean)
    now = m.clock.TotalMilliseconds()
    if m.metaOut.Count() > 0 and (force or now - m.lastFlush > 350)
        m.top.metaBatch = m.metaOut
        m.metaOut = []
        m.lastFlush = now
    end if
    if m.lastMetaSave = invalid then m.lastMetaSave = now
    if m.metaDirty >= 40 or (m.metaDirty > 0 and (force or now - m.lastMetaSave > 20000))
        writeJson("cachefs:/boxstream-meta.json", m.meta)
        m.metaDirty = 0
        m.lastMetaSave = now
    end if
end sub

' ---- MediaInfo probes -------------------------------------------------------
' Steps: HEAD (does the server allow partial reads, and how big is it?), the
' first megabyte, and for an MP4 with its index at the end, the last 4 MB.

function librarySignature(files as Object) as String
    ' The sorter's version is part of it: a smarter sorter rebuilds the library.
    parts = ["sorter 10"]
    for each f in files
        parts.Push(f.url + "|" + f.size.ToStr())
    end for
    digest = CreateObject("roEVPDigest")
    digest.Setup("md5")
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(parts.Join(Chr(10)))
    return digest.Process(bytes)
end function

sub queueProbe(url as String, ext as String, first as Boolean)
    cached = m.probes[url]
    if cached <> invalid
        m.probeOut.Push({url: url, info: cached})
        flushProbes(true)
        return
    end if
    for each job in m.probeQueue
        if job.url = url
            return
        end if
    end for
    job = {kind: "probe", url: url, ext: LCase(ext), stage: "head", total: -1}
    if first then m.probeQueue.Unshift(job) else m.probeQueue.Push(job)
end sub

' Movies whose names don't say their resolution get read in the background.
sub queueResolutionProbes(library as Object)
    for each movie in library.movies
        for each f in movie.files
            hasRes = false
            hasCodec = false
            if f.tags <> invalid
                for each t in f.tags
                    if (Right(t, 1) = "p" and Val(t) > 0) or t = "4K" or t = "8K" or t = "2K" then hasRes = true
                    if t = "HEVC" or t = "H.264" or t = "AV1" or t = "XviD" then hasCodec = true
                end for
            end if
            if (not hasRes or not hasCodec) and f.playable = true and not m.probes.DoesExist(f.url) then queueProbe(f.url, f.ext, false)
        end for
    end for
end sub

function startProbeStep(job as Object) as Boolean
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(job.url)
    transfer.SetMessagePort(m.port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.RetainBodyOnError(true)
    transfer.AddHeader("User-Agent", "BoxStream/" + appVersion() + " (Roku)")
    auth = authFor(job.url)
    if auth <> "" then transfer.AddHeader("Authorization", auth)
    ok = false
    if job.stage = "head"
        ok = transfer.AsyncHead()
    else
        m.probeFiles = m.probeFiles + 1
        job.path = "tmp:/probe-" + m.probeFiles.ToStr() + ".bin"
        if job.stage = "first"
            transfer.AddHeader("Range", "bytes=0-1048575")
        else
            transfer.AddHeader("Range", "bytes=-4194304")
        end if
        ok = transfer.AsyncGetToFile(job.path)
    end if
    if not ok then return false
    job.transfer = transfer
    job.started = m.clock.TotalMilliseconds()
    m.jobs[transfer.GetIdentity().ToStr()] = job
    return true
end function

function headerValue(event as Object, name as String) as String
    headers = event.GetResponseHeaders()
    if headers = invalid then return ""
    for each k in headers
        if LCase(k) = name then return headers[k]
    end for
    return ""
end function

sub probeResponse(job as Object, event as Object)
    code = event.GetResponseCode()
    if job.stage = "head"
        if code <> 200 and code <> 206
            finishProbe(job, {ok: false, error: httpProblem(code)})
            return
        end if
        length = headerValue(event, "content-length")
        if length <> "" then job.total = Val(length) / 1048576
        ' Without partial reads the whole file would come down: don't.
        if LCase(headerValue(event, "accept-ranges")) <> "bytes"
            finishProbe(job, {ok: false, error: "This server doesn't allow reading part of a file, so MediaInfo can't look inside it."})
            return
        end if
        job.stage = "first"
        m.probeQueue.Unshift(job)
        return
    end if
    if code <> 206
        CreateObject("roFileSystem").Delete(job.path)
        if code = 200
            finishProbe(job, {ok: false, error: "This server doesn't allow reading part of a file."})
        else
            finishProbe(job, {ok: false, error: httpProblem(code)})
        end if
        return
    end if
    ba = CreateObject("roByteArray")
    ba.ReadFile(job.path)
    CreateObject("roFileSystem").Delete(job.path)
    info = invalid
    try
        info = parseProbe(job, ba)
    catch problem
        print "[probe] "; problem.message; " "; job.url
        for each frame in problem.backtrace
            print "    "; frame.function; " line "; frame.line_number
        end for
        info = {ok: false, error: "Couldn't read this file's headers.", retry: true}
    end try
    if info = invalid then return ' waiting for the tail of an MP4
    finishProbe(job, info)
end sub

function parseProbe(job as Object, ba as Object) as Dynamic
    ext = job.ext
    tail = job.stage = "tail"
    if ba.Count() < 16 then return {ok: false, error: "The file is empty."}
    result = invalid
    if ext = "mkv" or ext = "webm" or (ba[0] = 26 and ba[1] = 69 and ba[2] = 223 and ba[3] = 163)
        result = probeMkv(ba)
    else if ext = "mp4" or ext = "m4v" or ext = "mov" or ext = "m4a" or ext = "alac"
        result = probeMp4(ba, tail)
        if result.needTail = true and not tail
            job.stage = "tail"
            m.probeQueue.Unshift(job)
            return invalid
        end if
    else if ext = "flac"
        result = probeFlac(ba)
    else if ext = "wav"
        result = probeWav(ba)
    else if ext = "aif" or ext = "aiff"
        result = probeAiff(ba)
    else if ext = "mp3"
        result = probeMp3(ba, job.total)
    else
        return {ok: false, error: "MediaInfo doesn't read ." + ext + " files yet."}
    end if
    result.ok = true
    result.sizeMb = job.total
    if result.seconds > 0 and job.total > 0 then result.bitrate = Int(job.total * 8.388608 / result.seconds * 100) / 100
    return result
end function

sub finishProbe(job as Object, info as Object)
    ' A reader crash is not remembered, so a fixed version tries again.
    if info.retry <> true then m.probes[job.url] = info
    m.probeDirty = m.probeDirty + 1
    m.probeOut.Push({url: job.url, info: info})
end sub

sub sendAllProbes(library as Object)
    for each movie in library.movies
        for each f in movie.files
            if m.probes.DoesExist(f.url) then m.probeOut.Push({url: f.url, info: m.probes[f.url]})
        end for
    end for
    flushProbes(true)
end sub

sub flushProbes(force as Boolean)
    if m.probeOut.Count() > 0
        now = m.clock.TotalMilliseconds()
        if force or m.lastProbeFlush = invalid or now - m.lastProbeFlush > 400
            m.top.probeBatch = m.probeOut
            m.probeOut = []
            m.lastProbeFlush = now
        end if
    end if
    if m.probeDirty >= 10 or (m.probeDirty > 0 and m.probeQueue.Count() = 0 and m.probeActive = 0)
        writeJson("cachefs:/boxstream-probes.json", m.probes)
        m.probeDirty = 0
    end if
end sub

' ---- Files ----------------------------------------------------------------

function readJson(path as String) as Dynamic
    fs = CreateObject("roFileSystem")
    ' Stopped between the two steps of a save: the new copy is complete.
    if not fs.Exists(path) and fs.Exists(path + ".new") then fs.Rename(path + ".new", path)
    if not fs.Exists(path) then return invalid
    text = ReadAsciiFile(path)
    if text = "" then return invalid
    return ParseJson(text)
end function

' Saved through a temporary file, so a restart in the middle of a save never
' leaves a half-written library behind (which would mean a full rescan).
sub writeJson(path as String, value as Object)
    text = FormatJson(value)
    if text = ""
        print "[worker] could not save "; path
        return
    end if
    fresh = path + ".new"
    if not WriteAsciiFile(fresh, text)
        print "[worker] could not write "; path
        return
    end if
    fs = CreateObject("roFileSystem")
    if fs.Exists(path) then fs.Delete(path)
    if not fs.Rename(fresh, path)
        fs.CopyFile(fresh, path)
        fs.Delete(fresh)
    end if
end sub

' ---- NFO files for the viewer: read as bytes, then decoded (old DOS text,
' code page 437, unless the file is valid UTF-8).
sub startNfoRead(url as String)
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.SetMessagePort(m.port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    auth = authFor(url)
    if auth <> "" then transfer.AddHeader("Authorization", auth)
    m.probeFiles = m.probeFiles + 1
    path = "tmp:/nfo-" + m.probeFiles.ToStr() + ".txt"
    if transfer.AsyncGetToFile(path)
        m.jobs[transfer.GetIdentity().ToStr()] = {kind: "nfo", transfer: transfer, url: url, path: path, started: m.clock.TotalMilliseconds()}
    end if
end sub

sub finishNfoRead(job as Object, code as Integer)
    text = ""
    if code = 200
        ba = CreateObject("roByteArray")
        ba.ReadFile(job.path)
        text = decodeNfo(ba)
    end if
    CreateObject("roFileSystem").Delete(job.path)
    m.top.nfoText = {url: job.url, text: text, ok: code = 200}
end sub

function decodeNfo(ba as Object) as String
    n = ba.Count()
    if n > 65536 then n = 65536
    high = false
    utf8 = true
    i = 0
    while i < n
        b = ba[i]
        if b >= 128
            high = true
            extra = 0
            if b >= 194 and b <= 223 then extra = 1
            if b >= 224 and b <= 239 then extra = 2
            if b >= 240 and b <= 244 then extra = 3
            if extra = 0
                utf8 = false
                exit while
            end if
            for k = 1 to extra
                if i + k >= n or ba[i + k] < 128 or ba[i + k] > 191
                    utf8 = false
                    exit for
                end if
            end for
            if not utf8 then exit while
            i = i + extra
        end if
        i = i + 1
    end while
    if not high or utf8
        text = ba.ToAsciiString()
    else
        table = [199,252,233,226,228,224,229,231,234,235,232,239,238,236,196,197,201,230,198,244,246,242,251,249,255,214,220,162,163,165,8359,402,225,237,243,250,241,209,170,186,191,8976,172,189,188,161,171,187,9617,9618,9619,9474,9508,9569,9570,9558,9557,9571,9553,9559,9565,9564,9563,9488,9492,9524,9516,9500,9472,9532,9566,9567,9562,9556,9577,9574,9568,9552,9580,9575,9576,9572,9573,9561,9560,9554,9555,9579,9578,9496,9484,9608,9604,9612,9616,9600,945,223,915,960,931,963,181,964,934,920,937,948,8734,966,949,8745,8801,177,8805,8804,8992,8993,247,8776,176,8729,183,8730,8319,178,9632,160]
        parts = []
        for i = 0 to n - 1
            b = ba[i]
            if b < 128 then parts.Push(Chr(b)) else parts.Push(Chr(table[b - 128]))
        end for
        text = parts.Join("")
    end if
    text = text.Replace(Chr(13) + Chr(10), Chr(10)).Replace(Chr(13), Chr(10)).Replace(Chr(9), "        ")
    return text
end function

' An album title without release extras: anything in (), [] or {}, format
' and source words, and edition notes.
function albumSearchTitle(title as String) as String
    t = CreateObject("roRegex", "[\(\[\{][^\)\]\}]*[\)\]\}]", "").ReplaceAll(title, " ")
    t = CreateObject("roRegex", "\b(web|flac|mp3|320|v0|cd|cdda|vinyl|lp|ep|24-?bit|16-?bit|hi-?res|deluxe( edition)?|remaster(ed)?|expanded( edition)?|anniversary edition)\b", "i").ReplaceAll(t, " ")
    t = CreateObject("roRegex", "\b\d{2,3}-\d{2,3}(\.\d)?\b", "").ReplaceAll(t, " ")
    ' Scene-style names: lossless/year words and a trailing release group (-TT).
    t = CreateObject("roRegex", "\b(lossless|(19|20)\d\d)\b", "i").ReplaceAll(t, " ")
    t = CreateObject("roRegex", "-[A-Za-z0-9]{2,8}$", "").ReplaceAll(t.Trim(), "")
    t = CreateObject("roRegex", "[_\.]+", "").ReplaceAll(t, " ")
    ' A bare bit depth left at the end ("Redux - 24").
    t = CreateObject("roRegex", "[\s-]+(16|24|32)\s*$", "").ReplaceAll(t.Trim(), "")
    t = CreateObject("roRegex", "\s*-\s*$|^\s*-\s*", "").ReplaceAll(t.Trim(), "")
    return CreateObject("roRegex", "\s+", "").ReplaceAll(t, " ").Trim()
end function
