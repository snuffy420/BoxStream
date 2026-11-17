' Subtitle reader. The player sends a request:
'   {gen, kind: "mkv", url, track (TrackNumber), headers}  text track in an MKV
'   {gen, kind: "file", url, headers}                       external .srt / .vtt
'   {gen, kind: "stop"}
' and keeps "position" up to date. Lines come back in "cues" as
' {gen, cues: [{s, e, t}], error, done} (seconds, seconds, text).
'
' MKV: the file's index (Cues) says where each subtitle line sits, so only a
' few KB per line are read, a little ahead of playback.

sub init()
    m.top.functionName = "runSubtitles"
end sub

sub runSubtitles()
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("request", m.port)
    m.top.ObserveField("position", m.port)
    m.clock = CreateObject("roTimespan")
    m.jobs = {}
    m.req = invalid
    m.files = 0
    m.position = 0
    m.pgsFiles = 0
    m.out = invalid
    m.lastOut = 0
    while true
        message = Wait(250, m.port)
        try
            if type(message) = "roSGNodeEvent"
                if message.GetField() = "request"
                    startRequest(message.GetData())
                else if message.GetField() = "position"
                    m.position = message.GetData()
                end if
            else if type(message) = "roUrlEvent"
                onTransfer(message)
            end if
            pumpLines()
            flushOut(false)
        catch problem
            print "[subtitles] "; problem.message
            for each frame in problem.backtrace
                print "    "; frame.function; " line "; frame.line_number
            end for
            failRequest("Couldn't read this subtitle track.")
        end try
    end while
end sub

sub startRequest(request as Object)
    for each id in m.jobs.Keys()
        if m.jobs[id].kind <> "font"
            m.jobs[id].transfer.AsyncCancel()
            m.jobs.Delete(id)
        end if
    end for
    m.req = invalid
    m.pgsState = invalid
    clearPictures()
    if request = invalid or request.kind = invalid or request.kind = "stop" then return
    m.req = {gen: request.gen, kind: request.kind, url: request.url, track: request.track, headers: request.headers, stage: "", lines: [], next: 0, done: {}, ass: false, compressed: false, fontAsked: false, pgs: false, zlib: false, strip: invalid, sup: invalid, algo: -1}
    if request.font <> invalid and request.font <> "" then ensureFont(request.font)
    if request.position <> invalid then m.position = request.position
    if request.kind = "file" and LCase(Right(m.req.url, 4)) = ".idx"
        ' DVD subtitles: the .idx says when and where; pictures are in the .sub.
        m.req.vobfile = true
        fetch("idx", "", m.req.url)
    else if request.kind = "file" and LCase(Right(m.req.url, 4)) = ".sup"
        ' Picture subtitles in their own file: read it whole, then draw ahead.
        m.req.pgs = true
        fetch("sup", "", m.req.url)
    else if request.kind = "file"
        fetch("file", "", m.req.url)
    else
        m.req.stage = "head"
        fetch("head", "bytes=0-524287", m.req.url)
    end if
end sub

sub failRequest(message as String)
    if m.req = invalid then return
    post({gen: m.req.gen, cues: [], error: message, done: true})
    m.req = invalid
end sub

sub fetch(kind as String, range as String, url as String)
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.SetMessagePort(m.port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.RetainBodyOnError(true)
    if m.req.headers <> invalid
        for each h in m.req.headers
            cut = Instr(1, h, ":")
            if cut > 1 then transfer.AddHeader(Left(h, cut - 1).Trim(), Mid(h, cut + 1).Trim())
        end for
    end if
    if range <> "" then transfer.AddHeader("Range", range)
    job = {kind: kind, transfer: transfer, gen: m.req.gen, started: m.clock.TotalMilliseconds(), range: range}
    if kind = "file" or kind = "idx"
        ok = transfer.AsyncGetToString()
    else if kind = "sup"
        m.files = m.files + 1
        job.path = "tmp:/subs-" + m.files.ToStr() + ".sup"
        ok = transfer.AsyncGetToFile(job.path)
    else
        m.files = m.files + 1
        job.path = "tmp:/subs-" + m.files.ToStr() + ".bin"
        ok = transfer.AsyncGetToFile(job.path)
    end if
    if ok then m.jobs[transfer.GetIdentity().ToStr()] = job
end sub

function fetchLine(index as Integer) as Boolean
    line = m.req.lines[index]
    ' The block sits "rel" bytes into the cluster's data; the cluster's own
    ' header (ID + size) is 5 to 12 bytes, so read a little either side.
    first = m.req.segment + line.cluster + line.rel + 5
    size = 6144
    if m.req.pgs then size = 65536
    if line.need <> invalid then size = line.need
    last = first + 7 + size
    m.files = m.files + 1
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(m.req.url)
    transfer.SetMessagePort(m.port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    if m.req.headers <> invalid
        for each h in m.req.headers
            cut = Instr(1, h, ":")
            if cut > 1 then transfer.AddHeader(Left(h, cut - 1).Trim(), Mid(h, cut + 1).Trim())
        end for
    end if
    transfer.AddHeader("Range", "bytes=" + numText(first) + "-" + numText(last))
    path = "tmp:/subs-" + m.files.ToStr() + ".bin"
    if not transfer.AsyncGetToFile(path) then return false
    m.jobs[transfer.GetIdentity().ToStr()] = {kind: "line", transfer: transfer, gen: m.req.gen, path: path, index: index, first: first, started: m.clock.TotalMilliseconds()}
    return true
end function

' Byte offsets past 2 GB don't fit an Integer: print them in two parts.
function numText(value as Double) as String
    ' Every part kept as a Double: a Float here is off by hundreds of bytes
    ' in big files.
    million = toDouble(1000000)
    high = Int(value / million)
    low = Int(value - toDouble(high) * million + toDouble(0.5))
    if low >= 1000000
        high = high + 1
        low = low - 1000000
    end if
    if low < 0
        high = high - 1
        low = low + 1000000
    end if
    if high = 0 then return low.ToStr()
    return high.ToStr() + Right("000000" + low.ToStr(), 6)
end function

function toDouble(value as Double) as Double
    return value
end function

sub onTransfer(event as Object)
    id = event.GetSourceIdentity().ToStr()
    if not m.jobs.DoesExist(id) then return
    job = m.jobs[id]
    m.jobs.Delete(id)
    code = event.GetResponseCode()
    if job.kind = "font"
        if code = 200
            sendFont(job.path)
        else
            CreateObject("roFileSystem").Delete(job.path)
        end if
        return
    end if
    if m.req = invalid or job.gen <> m.req.gen
        if job.path <> invalid then CreateObject("roFileSystem").Delete(job.path)
        return
    end if
    if job.kind = "idx"
        if code <> 200 and code <> 206
            failRequest("Couldn't download the subtitle file (" + code.ToStr() + ").")
            return
        end if
        m.req.vob = vobsubIdx(event.GetString())
        lines = []
        for each e in m.req.vob.entries
            lines.Push({s: e.s, d: 0, pos: e.pos})
        end for
        if lines.Count() = 0
            failRequest("This .idx file lists no subtitles.")
            return
        end if
        lines.SortBy("s")
        m.req.lines = lines
        m.req.subUrl = Left(m.req.url, Len(m.req.url) - 4) + ".sub"
        if Right(m.req.url, 4) = ".IDX" then m.req.subUrl = Left(m.req.url, Len(m.req.url) - 4) + ".SUB"
        m.req.stage = "lines"
        m.req.next = lineAt(m.position - 10)
        return
    end if
    if job.kind = "file"
        if code <> 200 and code <> 206
            failRequest("Couldn't download the subtitle file (" + code.ToStr() + ").")
            return
        end if
        cues = parseTextSubtitles(event.GetString())
        if cues.Count() > 0 then checkScript(cues[0].t)
        post({gen: m.req.gen, cues: cues, error: "", done: true})
        m.req = invalid
        return
    end if
    if job.kind = "sup"
        if code <> 200 and code <> 206
            CreateObject("roFileSystem").Delete(job.path)
            failRequest("Couldn't download the subtitle file (" + code.ToStr() + ").")
            return
        end if
        sup = CreateObject("roByteArray")
        sup.ReadFile(job.path)
        CreateObject("roFileSystem").Delete(job.path)
        m.req.sup = sup
        m.req.lines = supDisplaySets(sup)
        if m.req.lines.Count() = 0
            failRequest("This .sup file has no pictures in it.")
            return
        end if
        m.req.stage = "lines"
        m.req.next = lineAt(m.position - 10)
        return
    end if
    ba = CreateObject("roByteArray")
    if code = 206 then ba.ReadFile(job.path)
    CreateObject("roFileSystem").Delete(job.path)
    if job.kind = "vob"
        if code = 206 or code = 200
            spu = vobsubDemux(ba)
            if spu <> invalid then showVobsub(job.index, vobsubPicture(spu, 0, spu.Count(), m.req.vob, m.req.gen.ToStr()))
        end if
        return
    end if
    if job.kind = "line"
        if code = 206
            readLine(job.index, ba, job.first)
        else
            ' Busy server or dropped connection: try that line again later.
            if m.req.tries = invalid then m.req.tries = {}
            tries = m.req.tries[job.index.ToStr()]
            if tries = invalid then tries = 0
            m.req.tries[job.index.ToStr()] = tries + 1
            if tries < 3 then m.req.done.Delete(job.index.ToStr())
            if job.index < m.req.next then m.req.next = job.index
            m.req.retryAt = m.clock.TotalMilliseconds() + 2000
        end if
        return
    end if
    if code <> 206
        if code = 200
            failRequest("This server doesn't allow reading part of a file.")
        else
            failRequest("Couldn't read the file (" + code.ToStr() + ").")
        end if
        return
    end if
    if job.kind = "head"
        readHead(ba)
    else if job.kind = "cues"
        readCues(ba)
    end if
end sub

' ---- MKV head: where the Segment starts, the time scale, the track's
' codec and where the index (Cues) is.
sub readHead(ba as Object)
    count = ba.Count()
    i = 0
    segment = -1
    cuesAt = -1
    scale = 1000000.0
    while i < count - 8
        idv = ebmlVint(ba, i, true)
        if idv = invalid then exit while
        sz = ebmlVint(ba, i + idv.length, false)
        if sz = invalid then exit while
        dataStart = i + idv.length + sz.length
        id = idv.value
        if id = 408125543 ' Segment
            segment = dataStart
            i = dataStart
        else if id = 290298740 ' SeekHead 0x114D9B74
            j = dataStart
            while j < dataStart + sz.value and j < count - 4
                cid = ebmlVint(ba, j, true)
                csz = ebmlVint(ba, j + cid.length, false)
                c = j + cid.length + csz.length
                if cid.value = 19899 ' Seek 0x4DBB
                    seekId = 0
                    seekPos = -1
                    k = c
                    while k < c + csz.value
                        eid = ebmlVint(ba, k, true)
                        esz = ebmlVint(ba, k + eid.length, false)
                        e = k + eid.length + esz.length
                        if eid.value = 21419 then seekId = beInt(ba, e, esz.value) ' SeekID
                        if eid.value = 21420 then seekPos = beInt(ba, e, esz.value) ' SeekPosition
                        k = e + esz.value
                    end while
                    if seekId = 475249515 then cuesAt = seekPos ' Cues 0x1C53BB6B
                end if
                j = c + csz.value
            end while
            i = dataStart + sz.value
        else if id = 357149030 ' Info
            j = dataStart
            while j < dataStart + sz.value and j < count - 4
                cid = ebmlVint(ba, j, true)
                csz = ebmlVint(ba, j + cid.length, false)
                c = j + cid.length + csz.length
                if cid.value = 2807729 then scale = beInt(ba, c, csz.value)
                j = c + csz.value
            end while
            i = dataStart + sz.value
        else if id = 374648427 ' Tracks: this track's codec and compression
            readTrackSetup(ba, dataStart, dataStart + sz.value)
            i = dataStart + sz.value
        else if id = 524531317 ' Cluster
            exit while
        else
            if sz.unknown then exit while
            i = dataStart + sz.value
        end if
    end while
    if segment < 0 or cuesAt < 0
        failRequest("This file has no index, so its subtitles can't be read ahead.")
        return
    end if
    if m.req.compressed
        failRequest("This subtitle track is encrypted.")
        return
    end if
    m.req.segment = segment
    m.req.cuesAt = cuesAt
    m.req.scale = scale
    m.req.stage = "cues"
    start = segment + cuesAt
    fetch("cues", "bytes=" + numText(start) + "-" + numText(start + 8388607), m.req.url)
end sub

sub readTrackSetup(ba as Object, start as Integer, stopAt as Integer)
    count = ba.Count()
    if stopAt > count then stopAt = count
    j = start
    while j < stopAt - 2
        cid = ebmlVint(ba, j, true)
        csz = ebmlVint(ba, j + cid.length, false)
        if cid = invalid or csz = invalid then exit while
        c = j + cid.length + csz.length
        if cid.value = 174 ' TrackEntry
            number = -1
            codec = ""
            encodings = invalid
            privateData = invalid
            k = c
            while k < c + csz.value and k < count - 2
                eid = ebmlVint(ba, k, true)
                esz = ebmlVint(ba, k + eid.length, false)
                if eid = invalid or esz = invalid then exit while
                e = k + eid.length + esz.length
                if eid.value = 215 then number = beInt(ba, e, esz.value)
                if eid.value = 134 then codec = bytesText(ba, e, esz.value)
                if eid.value = 28032 then encodings = {start: e, stop: e + esz.value} ' ContentEncodings
                if eid.value = 25506 then privateData = {start: e, length: esz.value} ' CodecPrivate
                k = e + esz.value
            end while
            if number = m.req.track
                upper = UCase(codec)
                m.req.ass = Instr(1, upper, "ASS") > 0 or Instr(1, upper, "SSA") > 0
                m.req.pgs = upper = "S_HDMV/PGS"
                m.req.vobsub = upper = "S_VOBSUB"
                if m.req.vobsub
                    setup = ""
                    if privateData <> invalid then setup = bytesText(ba, privateData.start, privateData.length)
                    m.req.vob = vobsubIdx(setup)
                end if
                if encodings <> invalid then readEncodings(ba, encodings.start, encodings.stop)
            end if
        end if
        j = c + csz.value
    end while
end sub

' ContentEncodings: zlib (algorithm 0) or header stripping (3) are read;
' encryption can't be.
sub readEncodings(ba as Object, start as Integer, stopAt as Integer)
    k = start
    while k < stopAt - 1
        eid = ebmlVint(ba, k, true)
        esz = ebmlVint(ba, k + eid.length, false)
        if eid = invalid or esz = invalid then return
        e = k + eid.length + esz.length
        if eid.value = 25152 or eid.value = 20532 ' ContentEncoding, ContentCompression: step in
            readEncodings(ba, e, e + esz.value)
            if eid.value = 20532 and m.req.strip = invalid and m.req.algo = -1 then m.req.zlib = true
        else if eid.value = 16980 ' ContentCompAlgo
            m.req.algo = beInt(ba, e, esz.value)
            m.req.zlib = m.req.algo = 0
        else if eid.value = 16981 ' ContentCompSettings (the stripped header bytes)
            strip = CreateObject("roByteArray")
            for q = e to e + esz.value - 1
                strip.Push(ba[q])
            end for
            m.req.strip = strip
        else if eid.value = 20533 ' ContentEncryption
            m.req.compressed = true
        end if
        k = e + esz.value
    end while
    if m.req.algo = 3 then m.req.zlib = false
end sub

' ---- The index: every place this track has a line.
sub readCues(ba as Object)
    count = ba.Count()
    ' The index should start right here; if the file's pointer is a little
    ' off, look for its marker (1C 53 BB 6B) nearby.
    at = 0
    if count > 4 and not (ba[0] = 28 and ba[1] = 83 and ba[2] = 187 and ba[3] = 107)
        at = -1
        limit = count - 4
        if limit > 1048576 then limit = 1048576
        for q = 0 to limit
            if ba[q] = 28 and ba[q + 1] = 83 and ba[q + 2] = 187 and ba[q + 3] = 107
                at = q
                exit for
            end if
        end for
    end if
    if at > 0
        moved = CreateObject("roByteArray")
        for q = at to count - 1
            moved.Push(ba[q])
        end for
        ba = moved
        count = ba.Count()
    end if
    idv = ebmlVint(ba, 0, true)
    if idv = invalid or idv.value <> 475249515
        failRequest("Couldn't find this file's index.")
        return
    end if
    sz = ebmlVint(ba, idv.length, false)
    i = idv.length + sz.length
    stopAt = i + sz.value
    if stopAt > count then stopAt = count
    wanted = m.req.track
    scale = m.req.scale
    billion = 1000000000.0
    lines = []
    while i < stopAt - 2
        cid = ebmlVint(ba, i, true)
        csz = ebmlVint(ba, i + cid.length, false)
        if cid = invalid or csz = invalid then exit while
        c = i + cid.length + csz.length
        if cid.value = 187 ' CuePoint 0xBB
            time = -1.0
            k = c
            pointEnd = c + csz.value
            while k < pointEnd and k < count - 2
                eid = ebmlVint(ba, k, true)
                esz = ebmlVint(ba, k + eid.length, false)
                if eid = invalid or esz = invalid then exit while
                e = k + eid.length + esz.length
                if eid.value = 179 ' CueTime
                    time = beInt(ba, e, esz.value)
                else if eid.value = 183 ' CueTrackPositions
                    track = -1
                    cluster = -1.0
                    rel = -1.0
                    duration = 0.0
                    p = e
                    while p < e + esz.value
                        fid = ebmlVint(ba, p, true)
                        fsz = ebmlVint(ba, p + fid.length, false)
                        if fid = invalid or fsz = invalid then exit while
                        f = p + fid.length + fsz.length
                        if fid.value = 247 then track = beInt(ba, f, fsz.value) ' CueTrack
                        if fid.value = 241 then cluster = beInt(ba, f, fsz.value) ' CueClusterPosition
                        if fid.value = 240 then rel = beInt(ba, f, fsz.value) ' CueRelativePosition
                        if fid.value = 178 then duration = beInt(ba, f, fsz.value) ' CueDuration
                        p = f + fsz.value
                    end while
                    if track = wanted and cluster >= 0 and rel >= 0 and time >= 0
                        lines.Push({s: time * scale / billion, d: duration * scale / billion, cluster: cluster, rel: rel})
                    end if
                end if
                k = e + esz.value
            end while
        end if
        i = c + csz.value
    end while
    if lines.Count() = 0
        failRequest("This file's index doesn't list where the subtitle lines are.")
        return
    end if
    lines.SortBy("s")
    m.req.lines = lines
    m.req.stage = "lines"
    m.req.next = lineAt(m.position - 10)
end sub

' First line starting at or after this time.
function lineAt(seconds as Float) as Integer
    lines = m.req.lines
    low = 0
    high = lines.Count()
    while low < high
        middle = Int((low + high) / 2)
        if lines[middle].s < seconds then low = middle + 1 else high = middle
    end while
    return low
end function

' Keeps a few reads going for the lines in the next two minutes.
sub pumpLines()
    if m.req = invalid or m.req.stage <> "lines" then return
    lines = m.req.lines
    ' A jump (seek) moves the read point.
    if m.req.next < lines.Count()
        if lines[m.req.next].s > m.position + 150 or (m.req.next > 0 and lines[m.req.next - 1].s < m.position - 60)
            m.req.next = lineAt(m.position - 10)
        end if
    else if lines.Count() > 0 and lines[lines.Count() - 1].s > m.position + 150
        m.req.next = lineAt(m.position - 10)
    end if
    now = m.clock.TotalMilliseconds()
    for each id in m.jobs.Keys()
        if now - m.jobs[id].started > 15000 and m.jobs[id].kind <> "font"
            m.jobs[id].transfer.AsyncCancel()
            m.jobs.Delete(id)
        end if
    end for
    if m.req.sup <> invalid
        made = 0
        while made < 2 and m.req.next < lines.Count()
            index = m.req.next
            if lines[index].s > m.position + 120 then exit while
            m.req.next = index + 1
            if not m.req.done.DoesExist(index.ToStr())
                m.req.done[index.ToStr()] = true
                showPicture(index, pgsDisplaySet(m.req.sup, lines[index].start, lines[index].stop, m.req.gen.ToStr(), 10))
                made = made + 1
            end if
        end while
        return
    end if
    if m.req.retryAt <> invalid
        if m.clock.TotalMilliseconds() < m.req.retryAt then return
    end if
    if m.req.vobfile = true
        while lineJobs() < 3 and m.req.next < lines.Count()
            index = m.req.next
            if lines[index].s > m.position + 120 then exit while
            m.req.next = index + 1
            if not m.req.done.DoesExist(index.ToStr())
                m.req.done[index.ToStr()] = true
                fetchVobsub(index)
            end if
        end while
        return
    end if
    while lineJobs() < 4 and m.req.next < lines.Count()
        index = m.req.next
        if lines[index].s > m.position + 120 then exit while
        m.req.next = index + 1
        if not m.req.done.DoesExist(index.ToStr())
            m.req.done[index.ToStr()] = true
            fetchLine(index)
        end if
    end while
end sub

' One block: find it (BlockGroup 0xA0 or SimpleBlock 0xA3) and take its text.
sub readLine(index as Integer, ba as Object, first as Double)
    line = m.req.lines[index]
    count = ba.Count()
    for offset = 0 to 7
        if offset >= count - 4 then exit for
        b = ba[offset]
        if b = 160 or b = 163
            sz = ebmlVint(ba, offset + 1, false)
            if sz <> invalid
                start = offset + 1 + sz.length
                stopAt = start + sz.value
                if stopAt > count and stopAt < 4194304 and line.need = invalid
                    ' Bigger than what was read: read it again, whole.
                    tv = invalid
                    if b = 163 then tv = ebmlVint(ba, start, false)
                    if b = 160 or (tv <> invalid and tv.value = m.req.track)
                        line.need = stopAt + 16
                        fetchLine(index)
                        return
                    end if
                end if
                if stopAt <= count
                    block = invalid
                    duration = 0.0
                    if b = 163
                        block = {start: start, stop: stopAt}
                    else
                        k = start
                        while k < stopAt - 1
                            eid = ebmlVint(ba, k, true)
                            esz = ebmlVint(ba, k + eid.length, false)
                            if eid = invalid or esz = invalid then exit while
                            e = k + eid.length + esz.length
                            if eid.value = 161 then block = {start: e, stop: e + esz.value} ' Block
                            if eid.value = 155 then duration = beInt(ba, e, esz.value) ' BlockDuration
                            k = e + esz.value
                        end while
                    end if
                    if block <> invalid
                        tv = ebmlVint(ba, block.start, false)
                        if tv <> invalid and tv.value = m.req.track
                            payload = blockPayload(ba, block.start + tv.length + 3, block.stop)
                            if payload = invalid then return
                            if m.req.pgs
                                showPicture(index, pgsDisplaySet(payload.ba, payload.start, payload.stop, m.req.gen.ToStr(), 0))
                                return
                            end if
                            if m.req.vobsub = true
                                showVobsub(index, vobsubPicture(payload.ba, payload.start, payload.stop, m.req.vob, m.req.gen.ToStr()))
                                return
                            end if
                            text = blockText(payload.ba, payload.start, payload.stop - payload.start)
                            seconds = line.d
                            if duration > 0 then seconds = duration * m.req.scale / 1000000000.0
                            if seconds <= 0 then seconds = 4
                            if index + 1 < m.req.lines.Count()
                                gap = m.req.lines[index + 1].s - line.s
                                if gap > 0 and seconds > gap then seconds = gap
                            end if
                            if text <> "" then checkScript(text)
                            if text <> "" then post({gen: m.req.gen, cues: [{s: line.s, e: line.s + seconds, t: text}], error: "", done: false})
                            return
                        end if
                    end if
                end if
            end if
        end if
    end for
end sub

' The block's data, unpacked if the track is stored compressed.
function blockPayload(ba as Object, start as Integer, stopAt as Integer) as Dynamic
    if m.req.zlib
        out = inflateZlib(ba, start, stopAt - start)
        if out = invalid then return invalid
        return {ba: out, start: 0, stop: out.Count()}
    end if
    if m.req.strip <> invalid
        out = CreateObject("roByteArray")
        out.Append(m.req.strip)
        for k = start to stopAt - 1
            out.Push(ba[k])
        end for
        return {ba: out, start: 0, stop: out.Count()}
    end if
    return {ba: ba, start: start, stop: stopAt}
end function

' A picture stays up until the next display set (which often clears it).
sub showPicture(index as Integer, set as Dynamic)
    if set = invalid or set.clear = true then return
    lines = m.req.lines
    line = lines[index]
    ends = line.s + 8
    if index + 1 < lines.Count()
        ends = lines[index + 1].s
        if ends - line.s > 15 then ends = line.s + 15
    end if
    post({gen: m.req.gen, cues: [{s: line.s, e: ends, t: "", img: set.images, vw: set.vw, vh: set.vh}], error: "", done: false})
end sub

sub clearPictures()
    fs = CreateObject("roFileSystem")
    for each name in fs.GetDirectoryListing("tmp:/")
        if Left(name, 4) = "pgs-" then fs.Delete("tmp:/" + name)
    end for
end sub

function blockText(ba as Object, start as Integer, length as Integer) as String
    bytes = CreateObject("roByteArray")
    for k = start to start + length - 1
        bytes.Push(ba[k])
    end for
    text = bytes.ToAsciiString()
    if m.req.ass
        ' ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text
        for n = 1 to 8
            cut = Instr(1, text, ",")
            if cut = 0 then exit for
            text = Mid(text, cut + 1)
        end for
        text = text.Replace("\N", Chr(10)).Replace("\n", Chr(10)).Replace("\h", " ")
        text = CreateObject("roRegex", "\{[^}]*\}", "").ReplaceAll(text, "")
    end if
    return cleanLine(text)
end function

' Drops formatting tags (<i>, <font ...>, {\an8}) and stray carriage returns.
function cleanLine(text as String) as String
    text = composeAccents(text.Replace(Chr(13), ""))
    ' Invisible direction marks (common in Arabic and Hebrew subtitles) have
    ' no shape in most fonts and would show as boxes.
    for each code in [8206, 8207, 8234, 8235, 8236, 8237, 8238, 8294, 8295, 8296, 8297, 1564, 65279, 8203]
        text = text.Replace(Chr(code), "")
    end for
    ' Typographic punctuation that the Arabic, Hebrew and Thai fonts lack.
    text = text.Replace(Chr(8230), "...").Replace(Chr(8220), Chr(34)).Replace(Chr(8221), Chr(34)).Replace(Chr(8216), "'").Replace(Chr(8217), "'").Replace(Chr(8211), "-").Replace(Chr(8212), "-")
    text = CreateObject("roRegex", "<[^>]*>", "").ReplaceAll(text, "")
    text = CreateObject("roRegex", "\{\\[^}]*\}", "").ReplaceAll(text, "")
    text = text.Replace("&amp;", "&").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&nbsp;", " ")
    text = text.Trim()
    ' Arabic: Roku shapes each word (its letters come out right to left) but
    ' lays the words out left to right, so the words are reordered here.
    ' Hebrew: Roku draws it exactly as stored, so the whole line is put in
    ' display order (checked on the TV with a test screen).
    hebrew = hasHebrew(text)
    if hasRtl(text) or hebrew
        rows = []
        for each row in text.Split(Chr(10))
            if hebrew then rows.Push(visualRtl(row.Trim())) else rows.Push(rtlRow(row.Trim(), true))
        end for
        text = rows.Join(Chr(10))
    end if
    return text
end function

function hasRtl(text as String) as Boolean
    for k = 1 to Len(text)
        c = Asc(Mid(text, k, 1))
        ' Arabic only: Roku already lays Hebrew out right to left itself.
        if (c >= 1536 and c <= 1919) or (c >= 64336 and c <= 65276) then return true
    end for
    return false
end function

' Roku shapes each Arabic word but lays the words out left to right:
' put the words in visual order, with end punctuation on the left and a
' leading dialogue dash on the right.
function hasHebrew(text as String) as Boolean
    for k = 1 to Len(text)
        c = Asc(Mid(text, k, 1))
        if (c >= 1424 and c <= 1535) or (c >= 64285 and c <= 64335) then return true
    end for
    return false
end function

' Hebrew: Roku orders the words itself but puts end punctuation on the
' wrong side, so only the ends move (words = false).
function rtlRow(row as String, words as Boolean) as String
    if row = "" then return row
    marks = ".,!?:;" + Chr(1548) + Chr(1563) + Chr(1567) + Chr(34) + "'"
    tail = ""
    while Len(row) > 0 and Instr(1, marks, Right(row, 1)) > 0
        tail = Right(row, 1) + tail
        row = Left(row, Len(row) - 1)
    end while
    head = ""
    while Len(row) > 0 and (Left(row, 1) = "-" or Left(row, 1) = " ")
        head = head + Left(row, 1)
        row = Mid(row, 2)
    end while
    if not words
        visual = row
        if tail <> "" then visual = tail + visual
        if head.Trim() <> "" then visual = visual + " " + head.Trim()
        return visual
    end if
    parts = row.Split(" ")
    out = []
    for k = parts.Count() - 1 to 0 step -1
        word = parts[k]
        ' A comma or stop after a word goes on its left.
        ending = ""
        while Len(word) > 1 and Instr(1, marks, Right(word, 1)) > 0
            ending = Right(word, 1) + ending
            word = Left(word, Len(word) - 1)
        end while
        if word <> "" then out.Push(ending + word)
    end for
    visual = out.Join(" ")
    if tail <> "" then visual = tail + visual
    if head.Trim() <> "" then visual = visual + " " + head.Trim()
    return visual
end function

' ---- .srt and .vtt files
function parseTextSubtitles(body as String) as Object
    cues = []
    body = body.Replace(Chr(13), "")
    if Left(body, 1) = Chr(65279) then body = Mid(body, 2)
    if Instr(1, body, "[Script Info]") > 0 or Instr(1, body, Chr(10) + "Dialogue:") > 0 then return parseAss(body)
    timing = CreateObject("roRegex", "(\d+):(\d\d):(\d\d)[,.](\d+)\s*-->\s*(\d+):(\d\d):(\d\d)[,.](\d+)", "")
    short = CreateObject("roRegex", "(\d\d):(\d\d)[,.](\d+)\s*-->\s*(\d\d):(\d\d)[,.](\d+)", "")
    for each block in CreateObject("roRegex", "\n\s*\n", "").Split(body)
        rows = block.Split(Chr(10))
        for r = 0 to rows.Count() - 1
            hit = timing.Match(rows[r])
            s = -1
            e = -1
            if hit.Count() > 8
                s = Val(hit[1]) * 3600 + Val(hit[2]) * 60 + Val(hit[3]) + Val(hit[4]) / 1000
                e = Val(hit[5]) * 3600 + Val(hit[6]) * 60 + Val(hit[7]) + Val(hit[8]) / 1000
            else
                hit = short.Match(rows[r])
                if hit.Count() > 6
                    s = Val(hit[1]) * 60 + Val(hit[2]) + Val(hit[3]) / 1000
                    e = Val(hit[4]) * 60 + Val(hit[5]) + Val(hit[6]) / 1000
                end if
            end if
            if s >= 0
                text = []
                for t = r + 1 to rows.Count() - 1
                    text.Push(rows[t])
                end for
                line = cleanLine(text.Join(Chr(10)))
                if line <> "" then cues.Push({s: s, e: e, t: line})
                exit for
            end if
        end for
    end for
    cues.SortBy("s")
    return cues
end function

function lineJobs() as Integer
    n = 0
    for each id in m.jobs
        if m.jobs[id].kind = "line" or m.jobs[id].kind = "vob" then n = n + 1
    end for
    return n
end function

' ---- Fonts for scripts Roku's own font can't draw (Korean, Japanese,
' Chinese, Thai, Arabic, Hebrew): Noto, downloaded once and kept.
function fontSource(key as String) as Object
    cjk = "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/SubsetOTF/"
    noto = "https://raw.githubusercontent.com/notofonts/notofonts.github.io/1daf901bd023a3811498e0b7e7284694ae06307e/fonts/"
    if key = "KR" or key = "JP" or key = "SC" or key = "TC" then return {url: cjk + key + "/NotoSans" + key + "-Bold.otf", ext: ".otf"}
    if key = "TH" then return {url: noto + "NotoSansThai/hinted/ttf/NotoSansThai-Bold.ttf", ext: ".ttf"}
    if key = "AR" then return {url: noto + "NotoSansArabic/hinted/ttf/NotoSansArabic-Bold.ttf", ext: ".ttf"}
    if key = "HE" then return {url: noto + "NotoSansHebrew/hinted/ttf/NotoSansHebrew-Bold.ttf", ext: ".ttf"}
    return invalid
end function

sub ensureFont(key as String)
    if m.req <> invalid then m.req.fontAsked = true
    shipped = {AR: "pkg:/fonts/IBMPlexSansArabic-Bold.ttf", HE: "pkg:/fonts/IBMPlexSansHebrew-Bold.ttf", TH: "pkg:/fonts/IBMPlexSansThai-Bold.ttf", VI: "pkg:/fonts/NotoSans-Bold.ttf"}
    if shipped.DoesExist(key)
        sendFont(shipped[key])
        return
    end if
    source = fontSource(key)
    if source = invalid then return
    path = "cachefs:/boxstream-font-" + key + source.ext
    if CreateObject("roFileSystem").Exists(path)
        sendFont(path)
        return
    end if
    for each id in m.jobs
        if m.jobs[id].kind = "font" and m.jobs[id].path = path then return
    end for
    ' Keep just one big CJK font, so fonts never push the library out of the cache.
    fs = CreateObject("roFileSystem")
    for each name in fs.GetDirectoryListing("cachefs:/")
        if Left(name, 15) = "boxstream-font-" and Right(name, 4) = ".otf" then fs.Delete("cachefs:/" + name)
    end for
    if m.req <> invalid then post({gen: m.req.gen, cues: [], error: "", done: false, note: "Downloading a font for these subtitles..."})
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(source.url)
    transfer.SetMessagePort(m.port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    if transfer.AsyncGetToFile(path)
        m.jobs[transfer.GetIdentity().ToStr()] = {kind: "font", transfer: transfer, path: path, gen: -1, started: m.clock.TotalMilliseconds()}
    end if
end sub

sub sendFont(path as String)
    gen = -1
    if m.req <> invalid then gen = m.req.gen
    post({gen: gen, cues: [], error: "", done: false, font: path})
end sub

' The first line's letters say which font is needed.
sub checkScript(text as String)
    if m.req = invalid or m.req.fontAsked then return
    key = ""
    n = Len(text)
    if n > 60 then n = 60
    for k = 1 to n
        c = Asc(Mid(text, k, 1))
        if (c >= 7840 and c <= 7929) or c = 432 or c = 417 or c = 273 or c = 431 or c = 416 or c = 272
            key = "VI" ' Vietnamese letters Roku's own font lacks
        else if (c >= 44032 and c <= 55215) or (c >= 4352 and c <= 4607) or (c >= 12592 and c <= 12687)
            key = "KR"
        else if c >= 12352 and c <= 12543
            key = "JP"
        else if c >= 19968 and c <= 40959
            key = "SC"
        else if c >= 3584 and c <= 3711
            key = "TH"
        else if (c >= 1536 and c <= 1791) or (c >= 1872 and c <= 1919) or (c >= 64336 and c <= 65279)
            key = "AR"
        else if c >= 1424 and c <= 1535
            key = "HE"
        end if
        if key <> "" then exit for
    end for
    m.req.fontAsked = true
    if key <> "" then ensureFont(key)
end sub

' Updates go to the player in batches: several sets in a row can reach it as one.
sub post(update as Object)
    if m.out <> invalid and m.out.gen <> update.gen and update.gen <> -1 then flushOut(true)
    if m.out = invalid then m.out = {gen: update.gen, cues: [], error: "", note: "", font: ""}
    if update.gen <> -1 then m.out.gen = update.gen
    if update.cues <> invalid
        for each c in update.cues
            m.out.cues.Push(c)
        end for
    end if
    if update.error <> invalid and update.error <> "" then m.out.error = update.error
    if update.note <> invalid and update.note <> "" then m.out.note = update.note
    if update.font <> invalid and update.font <> "" then m.out.font = update.font
    if update.done = true then flushOut(true)
end sub

sub flushOut(force as Boolean)
    if m.out = invalid then return
    now = m.clock.TotalMilliseconds()
    if not force and now - m.lastOut < 300 then return
    m.top.cues = m.out
    m.out = invalid
    m.lastOut = now
end sub

' Letters stored as a plain letter plus a separate accent mark (u + "̈") are
' joined into the single accented letter (ü), which Roku's font can draw.
function composeAccents(text as String) as String
    hasMark = false
    for k = 1 to Len(text)
        c = Asc(Mid(text, k, 1))
        if c >= 768 and c <= 879
            hasMark = true
            exit for
        end if
    end for
    if not hasMark then return text
    if m.compose = invalid
        m.compose = {}
        m.compose["768"] = [65,192,69,200,73,204,79,210,85,217,97,224,101,232,105,236,111,242,117,249,220,475,252,476,78,504,110,505,274,7700,275,7701,332,7760,333,7761,87,7808,119,7809,194,7846,226,7847,258,7856,259,7857,202,7872,234,7873,212,7890,244,7891,416,7900,417,7901,431,7914,432,7915,89,7922,121,7923]
        m.compose["769"] = [65,193,69,201,73,205,79,211,85,218,89,221,97,225,101,233,105,237,111,243,117,250,121,253,67,262,99,263,76,313,108,314,78,323,110,324,82,340,114,341,83,346,115,347,90,377,122,378,220,471,252,472,71,500,103,501,197,506,229,507,198,508,230,509,216,510,248,511,199,7688,231,7689,274,7702,275,7703,207,7726,239,7727,75,7728,107,7729,77,7742,109,7743,213,7756,245,7757,332,7762,333,7763,80,7764,112,7765,360,7800,361,7801,87,7810,119,7811,194,7844,226,7845,258,7854,259,7855,202,7870,234,7871,212,7888,244,7889,416,7898,417,7899,431,7912,432,7913]
        m.compose["770"] = [65,194,69,202,73,206,79,212,85,219,97,226,101,234,105,238,111,244,117,251,67,264,99,265,71,284,103,285,72,292,104,293,74,308,106,309,83,348,115,349,87,372,119,373,89,374,121,375,90,7824,122,7825,7840,7852,7841,7853,7864,7878,7865,7879,7884,7896,7885,7897]
        m.compose["771"] = [65,195,78,209,79,213,97,227,110,241,111,245,73,296,105,297,85,360,117,361,86,7804,118,7805,194,7850,226,7851,258,7860,259,7861,69,7868,101,7869,202,7876,234,7877,212,7894,244,7895,416,7904,417,7905,431,7918,432,7919,89,7928,121,7929]
        m.compose["772"] = [65,256,97,257,69,274,101,275,73,298,105,299,79,332,111,333,85,362,117,363,220,469,252,470,196,478,228,479,550,480,551,481,198,482,230,483,490,492,491,493,214,554,246,555,213,556,245,557,558,560,559,561,89,562,121,563,71,7712,103,7713,7734,7736,7735,7737,7770,7772,7771,7773]
        m.compose["774"] = [65,258,97,259,69,276,101,277,71,286,103,287,73,300,105,301,79,334,111,335,85,364,117,365,552,7708,553,7709,7840,7862,7841,7863]
        m.compose["775"] = [67,266,99,267,69,278,101,279,71,288,103,289,73,304,90,379,122,380,65,550,97,551,79,558,111,559,66,7682,98,7683,68,7690,100,7691,70,7710,102,7711,72,7714,104,7715,77,7744,109,7745,78,7748,110,7749,80,7766,112,7767,82,7768,114,7769,83,7776,115,7777,346,7780,347,7781,352,7782,353,7783,7778,7784,7779,7785,84,7786,116,7787,87,7814,119,7815,88,7818,120,7819,89,7822,121,7823,383,7835]
        m.compose["776"] = [65,196,69,203,73,207,79,214,85,220,97,228,101,235,105,239,111,246,117,252,121,255,89,376,72,7718,104,7719,213,7758,245,7759,362,7802,363,7803,87,7812,119,7813,88,7820,120,7821,116,7831]
        m.compose["777"] = [65,7842,97,7843,194,7848,226,7849,258,7858,259,7859,69,7866,101,7867,202,7874,234,7875,73,7880,105,7881,79,7886,111,7887,212,7892,244,7893,416,7902,417,7903,85,7910,117,7911,431,7916,432,7917,89,7926,121,7927]
        m.compose["778"] = [65,197,97,229,85,366,117,367,119,7832,121,7833]
        m.compose["779"] = [79,336,111,337,85,368,117,369]
        m.compose["780"] = [67,268,99,269,68,270,100,271,69,282,101,283,76,317,108,318,78,327,110,328,82,344,114,345,83,352,115,353,84,356,116,357,90,381,122,382,65,461,97,462,73,463,105,464,79,465,111,466,85,467,117,468,220,473,252,474,71,486,103,487,75,488,107,489,439,494,658,495,106,496,72,542,104,543]
        m.compose["783"] = [65,512,97,513,69,516,101,517,73,520,105,521,79,524,111,525,82,528,114,529,85,532,117,533]
        m.compose["785"] = [65,514,97,515,69,518,101,519,73,522,105,523,79,526,111,527,82,530,114,531,85,534,117,535]
        m.compose["795"] = [79,416,111,417,85,431,117,432]
        m.compose["803"] = [66,7684,98,7685,68,7692,100,7693,72,7716,104,7717,75,7730,107,7731,76,7734,108,7735,77,7746,109,7747,78,7750,110,7751,82,7770,114,7771,83,7778,115,7779,84,7788,116,7789,86,7806,118,7807,87,7816,119,7817,90,7826,122,7827,65,7840,97,7841,69,7864,101,7865,73,7882,105,7883,79,7884,111,7885,416,7906,417,7907,85,7908,117,7909,431,7920,432,7921,89,7924,121,7925]
        m.compose["804"] = [85,7794,117,7795]
        m.compose["805"] = [65,7680,97,7681]
        m.compose["806"] = [83,536,115,537,84,538,116,539]
        m.compose["807"] = [67,199,99,231,71,290,103,291,75,310,107,311,76,315,108,316,78,325,110,326,82,342,114,343,83,350,115,351,84,354,116,355,69,552,101,553,68,7696,100,7697,72,7720,104,7721]
        m.compose["808"] = [65,260,97,261,69,280,101,281,73,302,105,303,85,370,117,371,79,490,111,491]
        m.compose["813"] = [68,7698,100,7699,69,7704,101,7705,76,7740,108,7741,78,7754,110,7755,84,7792,116,7793,85,7798,117,7799]
        m.compose["814"] = [72,7722,104,7723]
        m.compose["816"] = [69,7706,101,7707,73,7724,105,7725,85,7796,117,7797]
        m.compose["817"] = [66,7686,98,7687,68,7694,100,7695,75,7732,107,7733,76,7738,108,7739,78,7752,110,7753,82,7774,114,7775,84,7790,116,7791,90,7828,122,7829,104,7830]
    end if
    out = []
    for k = 1 to Len(text)
        ch = Mid(text, k, 1)
        c = Asc(ch)
        joined = false
        if c >= 768 and c <= 879 and out.Count() > 0
            table = m.compose[c.ToStr()]
            if table <> invalid
                base = Asc(out[out.Count() - 1])
                for i = 0 to table.Count() - 2 step 2
                    if table[i] = base
                        out[out.Count() - 1] = Chr(table[i + 1])
                        joined = true
                        exit for
                    end if
                end for
            end if
        end if
        if not joined then out.Push(ch)
    end for
    return out.Join("")
end function

' .ass / .ssa: "Dialogue: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text"
function parseAss(body as String) as Object
    cues = []
    order = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
    stamp = CreateObject("roRegex", "(\d+):(\d\d):(\d\d)[.:](\d+)", "")
    for each row in body.Split(Chr(10))
        row = row.Trim()
        if LCase(Left(row, 7)) = "format:" and Instr(1, LCase(row), "text") > 0
            order = []
            for each f in Mid(row, 8).Split(",")
                order.Push(LCase(f.Trim()))
            end for
        else if LCase(Left(row, 9)) = "dialogue:"
            rest = Mid(row, 10)
            fields = {}
            for i = 0 to order.Count() - 1
                if i = order.Count() - 1
                    fields[order[i]] = rest
                else
                    cut = Instr(1, rest, ",")
                    if cut = 0 then exit for
                    fields[order[i]] = Left(rest, cut - 1).Trim()
                    rest = Mid(rest, cut + 1)
                end if
            end for
            a = stamp.Match(textOr(fields["start"]))
            b = stamp.Match(textOr(fields["end"]))
            if a.Count() > 4 and b.Count() > 4
                s = Val(a[1]) * 3600 + Val(a[2]) * 60 + Val(a[3]) + Val(a[4]) / (10 ^ Len(a[4]))
                e = Val(b[1]) * 3600 + Val(b[2]) * 60 + Val(b[3]) + Val(b[4]) / (10 ^ Len(b[4]))
                text = textOr(fields["text"]).Replace("\N", Chr(10)).Replace("\n", Chr(10)).Replace("\h", " ")
                text = CreateObject("roRegex", "\{[^}]*\}", "").ReplaceAll(text, "")
                line = cleanLine(text)
                if line <> "" then cues.Push({s: s, e: e, t: line})
            end if
        end if
    end for
    cues.SortBy("s")
    return cues
end function

function textOr(value as Dynamic) as String
    if value = invalid then return ""
    return value
end function

' One subtitle's piece of the .sub file (a few 2 KB packs from its position).
sub fetchVobsub(index as Integer)
    line = m.req.lines[index]
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(m.req.subUrl)
    transfer.SetMessagePort(m.port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    if m.req.headers <> invalid
        for each h in m.req.headers
            cut = Instr(1, h, ":")
            if cut > 1 then transfer.AddHeader(Left(h, cut - 1).Trim(), Mid(h, cut + 1).Trim())
        end for
    end if
    transfer.AddHeader("Range", "bytes=" + numText(line.pos) + "-" + numText(line.pos + 65535))
    m.files = m.files + 1
    path = "tmp:/subs-" + m.files.ToStr() + ".bin"
    if transfer.AsyncGetToFile(path)
        m.jobs[transfer.GetIdentity().ToStr()] = {kind: "vob", transfer: transfer, gen: m.req.gen, path: path, index: index, started: m.clock.TotalMilliseconds()}
    end if
end sub

' A DVD subtitle picture: shown for its own duration (or until the next one).
sub showVobsub(index as Integer, set as Dynamic)
    if set = invalid then return
    lines = m.req.lines
    line = lines[index]
    starts = line.s + set.delay
    ends = starts + set.dur
    if set.dur <= 0
        ends = starts + 5
        if index + 1 < lines.Count() and lines[index + 1].s < ends then ends = lines[index + 1].s
    end if
    post({gen: m.req.gen, cues: [{s: starts, e: ends, t: "", img: set.images, vw: set.vw, vh: set.vh}], error: "", done: false})
end sub
