' AudioSwap (see AudioSwap.xml).
' Request: {url, headers, swapTrack (MKV track number of the DTS/TrueHD track),
'          audioIndex (its position among the audio tracks, for the helper),
'          start (seconds), helper: {url, code}, port}
' The movie is rebuilt on its way through: its header (DTS track -> Dolby
' Digital track, other audio tracks, index and attachments left out), then
' every cluster with video and subtitle blocks copied byte for byte, the old
' audio blocks dropped, and Dolby Digital frames from the helper (2,560 bytes,
' 32 ms each at 640 kb/s) put in at matching times.

sub init()
    m.top.functionName = "runSwap"
end sub

sub runSwap()
    req = m.top.request
    m.url = req.url
    m.headers = req.headers
    if m.headers = invalid then m.headers = []
    m.port = CreateObject("roMessagePort")
    m.swapTrack = req.swapTrack
    ' Dolby Digital layout from the player: channels kept up to 5.1, and the
    ' bitrate for that many (frames are bitrate x 32 ms: 640k = 2560 bytes).
    m.outChannels = req.channels
    m.kbps = req.kbps
    if m.outChannels = invalid or m.outChannels < 1 then m.outChannels = 6
    if m.kbps = invalid or m.kbps < 96 then m.kbps = 640
    m.frameBytes = m.kbps * 4
    ' Download a little further ahead: heavy remuxes (several audio tracks)
    ' need ~5 MB/s, and more requests in flight get closer to the line speed.
    m.piece = 3145728
    m.ahead = 6
    m.files = 0
    m.tmpName = "tmp:/swap-head-" + Str(req.port).Trim() + ".bin"
    m.total = sourceLength()
    if m.top.quit = true then return
    if m.total <= 0 
        report("error", "Couldn't reach the file on the source")
        return
    end if
    if not readHead() 
        report("error", "This file's layout isn't supported for audio conversion")
        return
    end if
    ' Where to begin: the cluster at or before the start time (from the index).
    m.startByte = m.firstCluster
    m.startMs = 0.0
    if m.top.quit = true then return
    if req.start <> invalid and req.start > 1 and m.cuesAt >= 0 then findStart(req.start)
    ' Replaced by a newer start (another seek): don't take over the helper.
    if m.top.quit = true then return
    if not startHelper(req) 
        report("error", "Your helper didn't start the conversion")
        return
    end if
    m.top.swapState = {status: "ready", startSeconds: m.startMs / 1000.0}
    serve(req.port)
end sub

sub report(status as String, message as String)
    print "[swap] "; status; ": "; message
    m.top.swapState = {status: status, message: message}
end sub

' ---- Reading the head of the file -------------------------------------------------

function readHead() as Boolean
    ba = fetchSync(0, 4194303)
    if ba = invalid then return false
    n = ba.Count()
    ' EBML header: copied as it is.
    id = vint(ba, 0, true)
    if id = invalid or id.value <> 440786851 then return false
    sz = vint(ba, id.length, false)
    ebmlEnd = id.length + sz.length + sz.value
    m.head = CreateObject("roByteArray")
    for k = 0 to ebmlEnd - 1
        m.head.Push(ba[k])
    end for
    id = vint(ba, ebmlEnd, true)
    if id = invalid or id.value <> 408125543 then return false
    sz = vint(ba, ebmlEnd + id.length, false)
    m.segStart = ebmlEnd + id.length + sz.length
    ' Segment with unknown size (the rebuilt movie's length isn't known).
    for each v in [24, 83, 128, 103, 1, 255, 255, 255, 255, 255, 255, 255]
        m.head.Push(v)
    end for
    m.scale = 1000000.0
    m.cuesAt = -1
    m.firstCluster = -1
    m.videoTrack = -1
    tracksOut = invalid
    infoOut = invalid
    i = m.segStart
    while i < n - 12
        cid = vint(ba, i, true)
        csz = vint(ba, i + cid.length, false)
        if cid = invalid or csz = invalid then exit while
        c = i + cid.length + csz.length
        if cid.value = 524531317 ' Cluster
            m.firstCluster = i
            exit while
        else if cid.value = 290298740 ' SeekHead: where the index is
            j = c
            while j < c + csz.value
                sid = vint(ba, j, true)
                ssz = vint(ba, j + sid.length, false)
                s = j + sid.length + ssz.length
                if sid.value = 19899
                    seekId = 0
                    seekPos = -1
                    k = s
                    while k < s + ssz.value
                        eid = vint(ba, k, true)
                        esz = vint(ba, k + eid.length, false)
                        e = k + eid.length + esz.length
                        if eid.value = 21419 then seekId = beValue(ba, e, esz.value)
                        if eid.value = 21420 then seekPos = beValue(ba, e, esz.value)
                        k = e + esz.value
                    end while
                    if seekId = 475249515 then m.cuesAt = seekPos
                end if
                j = s + ssz.value
            end while
        else if cid.value = 357149030 ' Info: copied; its TimecodeScale kept
            infoOut = slice(ba, i, cid.length + csz.length + csz.value)
            j = c
            while j < c + csz.value
                eid = vint(ba, j, true)
                esz = vint(ba, j + eid.length, false)
                e = j + eid.length + esz.length
                if eid.value = 2807729 then m.scale = beValue(ba, e, esz.value)
                j = e + esz.value
            end while
        else if cid.value = 374648427 ' Tracks: rebuilt
            tracksOut = rebuildTracks(ba, c, c + csz.value)
        end if
        if csz.unknown then exit while
        i = c + csz.value
    end while
    if m.firstCluster < 0 or tracksOut = invalid then return false
    if infoOut <> invalid then m.head.Append(infoOut)
    m.head.Append(tracksOut)
    return true
end function

' Tracks with the chosen audio track turned into Dolby Digital (same
' number, UID and language) and every other audio track left out.
function rebuildTracks(ba as Object, start as Integer, stopAt as Integer) as Object
    body = CreateObject("roByteArray")
    m.keptTracks = {}
    i = start
    while i < stopAt
        eid = vint(ba, i, true)
        esz = vint(ba, i + eid.length, false)
        e = i + eid.length + esz.length
        if eid.value = 174 ' TrackEntry
            number = -1
            kind = 0
            uid = invalid
            lang = invalid
            k = e
            while k < e + esz.value
                fid = vint(ba, k, true)
                fsz = vint(ba, k + fid.length, false)
                f = k + fid.length + fsz.length
                if fid.value = 215 then number = beValue(ba, f, fsz.value)
                if fid.value = 131 then kind = beValue(ba, f, fsz.value)
                if fid.value = 29637 then uid = slice(ba, k, fid.length + fsz.length + fsz.value)
                if fid.value = 2274716 then lang = slice(ba, k, fid.length + fsz.length + fsz.value)
                k = f + fsz.value
            end while
            if kind = 1 and m.videoTrack < 0 then m.videoTrack = number
            if kind <> 2 then m.keptTracks[number.ToStr()] = true
            if number = m.swapTrack
                entry = CreateObject("roByteArray")
                entry.Append(element([215], uintBytes(number)))
                if uid <> invalid then entry.Append(uid)
                entry.Append(element([131], uintBytes(2)))
                entry.Append(element([134], asciiBytes("A_AC3")))
                entry.Append(element([156], uintBytes(0)))
                entry.Append(element([136], uintBytes(1)))
                if lang <> invalid then entry.Append(lang)
                audio = CreateObject("roByteArray")
                audio.Append(element([181], doubleBytes48k()))
                audio.Append(element([159], uintBytes(m.outChannels)))
                entry.Append(element([225], audio))
                body.Append(element([174], entry))
            else if kind <> 2
                body.Append(slice(ba, i, eid.length + esz.length + esz.value))
            end if
        end if
        i = e + esz.value
    end while
    return element([22, 84, 174, 107], body)
end function

' The cluster to begin at for a start time, from the file's index (Cues).
sub findStart(seconds as Float)
    ba = fetchSync(m.segStart + m.cuesAt, m.segStart + m.cuesAt + 8388607)
    if ba = invalid then return
    id = vint(ba, 0, true)
    if id = invalid or id.value <> 475249515 then return
    sz = vint(ba, id.length, false)
    i = id.length + sz.length
    stopAt = i + sz.value
    if stopAt > ba.Count() then stopAt = ba.Count()
    wanted = seconds * 1000.0
    best = -1.0
    bestMs = 0.0
    while i < stopAt - 2
        cid = vint(ba, i, true)
        csz = vint(ba, i + cid.length, false)
        if cid = invalid or csz = invalid then exit while
        c = i + cid.length + csz.length
        if cid.value = 187
            time = -1.0
            cluster = -1.0
            k = c
            while k < c + csz.value
                eid = vint(ba, k, true)
                esz = vint(ba, k + eid.length, false)
                if eid = invalid or esz = invalid then exit while
                e = k + eid.length + esz.length
                if eid.value = 179 then time = beValue(ba, e, esz.value)
                if eid.value = 183
                    p = e
                    track = -1
                    cuePos = -1.0
                    while p < e + esz.value
                        fid = vint(ba, p, true)
                        fsz = vint(ba, p + fid.length, false)
                        f = p + fid.length + fsz.length
                        if fid.value = 247 then track = beValue(ba, f, fsz.value)
                        if fid.value = 241 then cuePos = beValue(ba, f, fsz.value)
                        p = f + fsz.value
                    end while
                    if track = m.videoTrack then cluster = cuePos
                end if
                k = e + esz.value
            end while
            if time >= 0 and cluster >= 0
                ms = time * m.scale / 1000000.0
                if ms <= wanted and ms >= bestMs
                    bestMs = ms
                    best = cluster
                end if
            end if
        end if
        i = c + csz.value
    end while
    if best >= 0
        m.startByte = m.segStart + best
        m.startMs = bestMs
    end if
end sub

' ---- The helper's Dolby Digital ------------------------------------------------------

function startHelper(req as Object) as Boolean
    h = req.helper
    auth = ""
    for each line in m.headers
        cut = Instr(1, line, ":")
        if cut > 1 and LCase(Left(line, cut - 1).Trim()) = "authorization" then auth = Mid(line, cut + 1).Trim()
    end for
    m.helperUrl = h.url
    m.helperCode = h.code
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(h.url + "/ac3/start?src=" + transfer.Escape(m.url) + "&track=" + req.audioIndex.ToStr() + "&ch=" + m.outChannels.ToStr() + "&kbps=" + m.kbps.ToStr() + "&start=" + Str(m.startMs / 1000.0).Trim())
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.AddHeader("X-Helper-Token", h.code)
    if auth <> "" then transfer.AddHeader("X-Source-Auth", auth)
    reply = ParseJson(transfer.GetToString())
    if reply = invalid or reply.id = invalid then return false
    m.session = reply.id
    m.ac3Chunks = []
    m.ac3Next = 0       ' next frame number to ask the helper for
    m.ac3Done = false
    m.ac3Job = invalid
    m.frameOut = 0      ' next frame number to put in the movie
    return true
end function

sub askHelper()
    if m.ac3Job <> invalid or m.ac3Done then return
    if m.ac3Next - m.frameOut > 900 then return ' about 29 s ahead is plenty
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(m.helperUrl + "/ac3/read?id=" + m.session + "&from=" + wholeNumber(m.ac3Next * (m.frameBytes * 1#)) + "&max=1024000")
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.AddHeader("X-Helper-Token", m.helperCode)
    transfer.SetMessagePort(m.port)
    m.files = m.files + 1
    path = "tmp:/swap-ac3-" + m.files.ToStr() + ".bin"
    if transfer.AsyncGetToFile(path)
        m.ac3Job = {transfer: transfer, path: path, id: transfer.GetIdentity().ToStr(), at: m.clock.TotalMilliseconds()}
    end if
end sub

sub helperDone(event as Object)
    job = m.ac3Job
    m.ac3Job = invalid
    ba = CreateObject("roByteArray")
    ba.ReadFile(job.path)
    DeleteFile(job.path)
    frames = Int(ba.Count() / m.frameBytes)
    done = event.GetResponseHeaders()["x-done"] = "1"
    if frames > 0
        m.ac3Chunks.Push({ba: ba, first: m.ac3Next, frames: frames})
        m.ac3Next = m.ac3Next + frames
    else if done
        m.ac3Done = true
    end if
    if frames = 0 and not done then m.ac3Wait = m.clock.TotalMilliseconds() + 400
end sub

' Frame k: its chunk and offset, or invalid if not here yet.
function frameAt(k as Integer) as Dynamic
    while m.ac3Chunks.Count() > 0 and m.ac3Chunks[0].first + m.ac3Chunks[0].frames <= k
        m.ac3Chunks.Shift()
    end while
    for each c in m.ac3Chunks
        if k >= c.first and k < c.first + c.frames then return {ba: c.ba, off: (k - c.first) * m.frameBytes}
    end for
    return invalid
end function

' Puts in every Dolby Digital frame up to time limitMs (ms of movie time).
' Returns false when a needed frame hasn't arrived yet.
function flushAudio(limitMs as Float) as Boolean
    if m.clusterTc < 0 then return true
    while true
        frameMs = m.startMs + m.frameOut * 32.0
        if frameMs > limitMs then return true
        f = frameAt(m.frameOut)
        if f = invalid
            if m.ac3Done then return true
            return false
        end if
        rel = Int(frameMs * 1000000.0 / m.scale - m.clusterTc)
        if rel > -32768 and rel < 32767
            if rel < 0 then rel = rel + 65536
            ' SimpleBlock: 2-byte size (frame + 4 header bytes), track, time, keyframe.
            size = m.frameBytes + 4
            h = CreateObject("roByteArray")
            for each v in [163, 64 + (size >> 8), size and 255, 128 + m.swapTrack, (rel >> 8) and 255, rel and 255, 128]
                h.Push(v)
            end for
            queue(h, 0, h.Count())
            queue(f.ba, f.off, m.frameBytes)
        end if
        m.frameOut = m.frameOut + 1
    end while
    return true
end function

' ---- The movie stream ----------------------------------------------------------------

sub serve(port as Integer)
    m.clock = CreateObject("roTimespan")
    m.listener = CreateObject("roStreamSocket")
    address = CreateObject("roSocketAddress")
    address.SetAddress("127.0.0.1:" + port.ToStr())
    m.listener.SetAddress(address)
    m.listener.SetMessagePort(m.port)
    m.listener.NotifyReadable(true)
    if not m.listener.Listen(8) 
        report("error", "couldn't listen")
        return
    end if
    m.clients = {}
    m.pieces = []
    m.transfers = {}
    m.hist = []
    m.histStart = 0#
    m.vEnd = 0#
    m.main = invalid
    m.parsePos = m.startByte
    m.fetchPos = m.startByte
    m.mode = "top"
    m.clusterTc = -1
    m.toCopy = 0
    m.toSkip = 0
    m.ended = false
    m.ac3Wait = 0
    m.headQueued = false
    m.top.address = "http://127.0.0.1:" + port.ToStr() + "/movie.mkv"
    while m.top.quit <> true
        event = Wait(10, m.port)
        if type(event) = "roUrlEvent"
            id = event.GetSourceIdentity().ToStr()
            if m.ac3Job <> invalid and id = m.ac3Job.id
                helperDone(event)
            else
                pieceDone(event)
            end if
        else if type(event) = "roSocketEvent"
            if m.listener.IsReadable()
                sock = m.listener.Accept()
                if sock <> invalid then addClient(sock)
            end if
        end if
        for each id in m.clients.Keys()
            serveClient(m.clients[id])
        end for
        if not m.headQueued
            ' The rebuilt movie starts with its new header.
            m.headQueued = true
            queue(m.head, 0, m.head.Count())
        end if
        if m.ac3Wait = 0 or m.clock.TotalMilliseconds() > m.ac3Wait
            m.ac3Wait = 0
            askHelper()
        end if
        fetchAhead()
        ' Stay up to 8 MB ahead of what the player has read.
        reader = 0#
        if m.main <> invalid then reader = m.main.next
        if m.vEnd - reader < 8388608 then parse()
    end while
    for each id in m.clients.Keys()
        m.clients[id].sock.Close()
    end for
    m.listener.Close()
end sub

sub addClient(sock as Object)
    sock.SetMessagePort(m.port)
    sock.NotifyReadable(true)
    id = sock.GetID().ToStr()
    m.clients[id] = {id: id, sock: sock, head: "", started: false, zeros: 0, next: 0#, clock: CreateObject("roTimespan")}
end sub

sub serveClient(c as Object)
    if not c.started
        text = c.sock.ReceiveStr(8192)
        if text <> invalid then c.head = c.head + text
        if Instr(1, c.head, Chr(13) + Chr(10) + Chr(13) + Chr(10)) = 0
            if c.clock.TotalMilliseconds() > 10000 then dropClient(c)
            return
        end if
        c.started = true
        first = 0#
        for each line in c.head.Split(Chr(10))
            low = LCase(line.Trim())
            if Left(low, 13) = "range: bytes=" then first = digits(Mid(low, 14).Split("-")[0])
        end for
        crlf = Chr(13) + Chr(10)
        declared = m.total + 50000000#
        if first >= m.histStart and first <= m.vEnd + 33554432
            ' The rebuilt movie from this point (the player often reads the
            ' header, then asks again from where it stopped).
            if first = 0
                c.sock.SendStr("HTTP/1.1 200 OK" + crlf + "Content-Type: video/x-matroska" + crlf + "Content-Length: " + wholeNumber(declared) + crlf + "Accept-Ranges: bytes" + crlf + "Connection: close" + crlf + crlf)
            else
                c.sock.SendStr("HTTP/1.1 206 Partial Content" + crlf + "Content-Type: video/x-matroska" + crlf + "Content-Length: " + wholeNumber(declared - first) + crlf + "Content-Range: bytes " + wholeNumber(first) + "-" + wholeNumber(declared - 1) + "/" + wholeNumber(declared) + crlf + "Connection: close" + crlf + crlf)
            end if
            ' One reader at a time: this request takes over.
            if m.main <> invalid and m.main.id <> c.id then dropClient(m.main)
            m.main = c
            c.next = first
        else
            ' Probes far into the file (players look for an index at the end):
            ' the rebuilt movie has none, so they read zeros.
            length = declared - first
            if length > 65536 then length = 65536
            if length < 0 then length = 0
            c.sock.SendStr("HTTP/1.1 206 Partial Content" + crlf + "Content-Type: video/x-matroska" + crlf + "Content-Length: " + wholeNumber(length) + crlf + "Content-Range: bytes " + wholeNumber(first) + "-" + wholeNumber(first + length - 1) + "/" + wholeNumber(declared) + crlf + "Connection: close" + crlf + crlf)
            c.zeros = length
        end if
        return
    end if
    if c.zeros > 0
        z = CreateObject("roByteArray")
        for k = 1 to c.zeros
            z.Push(0)
        end for
        c.sock.Send(z, 0, z.Count())
        dropClient(c)
        return
    end if
    if m.main = invalid or c.id <> m.main.id then return
    guard = 0
    while guard < 64
        guard = guard + 1
        chunk = invalid
        for each h in m.hist
            if c.next >= h.v and c.next < h.v + h.len
                chunk = h
                exit for
            end if
        end for
        if chunk = invalid then exit while
        skip = Int(c.next - chunk.v)
        k = c.sock.Send(chunk.ba, chunk.off + skip, chunk.len - skip)
        if k > 0
            c.next = c.next + k
        else
            if c.sock.eOK() or c.sock.eAgain() or c.sock.eWouldBlock() then return
            ' The player hung up (it stopped or will ask again elsewhere).
            dropClient(c)
            return
        end if
    end while
    ' Sent bytes well behind the reader are let go (16 MB kept for re-asks).
    while m.hist.Count() > 0
        h = m.hist[0]
        if h.v + h.len >= c.next - 16777216 then exit while
        m.hist.Shift()
        m.histStart = h.v + h.len
    end while
    if m.ended and c.next >= m.vEnd
        dropClient(c)
    end if
end sub

sub dropClient(c as Object)
    c.sock.Close()
    m.clients.Delete(c.id)
    if m.main <> invalid and m.main.id = c.id then m.main = invalid
end sub

sub queue(ba as Object, off as Integer, length as Integer)
    if length <= 0 then return
    m.hist.Push({v: m.vEnd, ba: ba, off: off, len: length})
    m.vEnd = m.vEnd + length
end sub

' Source pieces downloading ahead of the parser.
sub fetchAhead()
    loading = 0
    for each p in m.pieces
        if p.state = "loading" then loading = loading + 1
    end for
    while m.pieces.Count() < m.ahead + 2 and loading < m.ahead and m.fetchPos < m.total
        last = m.fetchPos + m.piece - 1
        if last > m.total - 1 then last = m.total - 1
        transfer = newTransfer(m.url)
        transfer.SetMessagePort(m.port)
        transfer.AddHeader("Range", "bytes=" + wholeNumber(m.fetchPos) + "-" + wholeNumber(last))
        m.files = m.files + 1
        path = "tmp:/swap-" + m.files.ToStr() + ".bin"
        piece = {abs: m.fetchPos, size: last - m.fetchPos + 1, path: path, state: "loading", ba: invalid}
        if transfer.AsyncGetToFile(path)
            m.transfers[transfer.GetIdentity().ToStr()] = {piece: piece, transfer: transfer}
            m.pieces.Push(piece)
            loading = loading + 1
        end if
        m.fetchPos = last + 1
    end while
end sub

sub pieceDone(event as Object)
    id = event.GetSourceIdentity().ToStr()
    job = m.transfers[id]
    if job = invalid then return
    m.transfers.Delete(id)
    p = job.piece
    code = event.GetResponseCode()
    if code = 206 or code = 200
        p.ba = CreateObject("roByteArray")
        p.ba.ReadFile(p.path)
        p.state = "ready"
    else
        p.state = "failed"
    end if
    DeleteFile(p.path)
end sub

' Bytes ready from the parse position on (contiguous, downloaded pieces).
function ready() as Double
    total = 0#
    for each p in m.pieces
        if p.state <> "ready" then exit for
        if p.abs + p.ba.Count() > m.parsePos
            if p.abs <= m.parsePos then total = total + (p.abs + p.ba.Count() - m.parsePos) else total = total + p.ba.Count()
        end if
    end for
    return total
end function

function byteAt(abs as Double) as Integer
    for each p in m.pieces
        if p.state = "ready" and abs >= p.abs and abs < p.abs + p.ba.Count() then return p.ba[Int(abs - p.abs)]
    end for
    return -1
end function

' The bytes at the parse position for reading a header: straight from the
' downloaded piece when n bytes sit in it (no copying; this is the hot path,
' run for every block), else a copy across pieces. {ba, at, count}: count is
' how many bytes from ba[at] can be read.
function window(n as Integer) as Object
    p = m.curPiece
    if p = invalid or p.state <> "ready" or m.parsePos < p.abs or m.parsePos >= p.abs + p.ba.Count()
        p = invalid
        for each q in m.pieces
            if q.state = "ready" and m.parsePos >= q.abs and m.parsePos < q.abs + q.ba.Count()
                p = q
                exit for
            end if
        end for
        m.curPiece = p
    end if
    if p <> invalid
        off = Int(m.parsePos - p.abs)
        left = p.ba.Count() - off
        if left >= n then return {ba: p.ba, at: off, count: left}
    end if
    h = peek(n)
    return {ba: h, at: 0, count: h.Count()}
end function

' Up to n bytes from the parse position (not used up).
function peek(n as Integer) as Object
    out = CreateObject("roByteArray")
    for k = 0 to n - 1
        b = byteAt(m.parsePos + k)
        if b < 0 then exit for
        out.Push(b)
    end for
    return out
end function

' Moves past n bytes, queueing them for the player when copying.
sub take(n as Double, copy as Boolean)
    while n > 0
        p = invalid
        for each q in m.pieces
            if q.state = "ready" and m.parsePos >= q.abs and m.parsePos < q.abs + q.ba.Count()
                p = q
                exit for
            end if
        end for
        if p = invalid then exit while
        off = Int(m.parsePos - p.abs)
        avail = p.ba.Count() - off
        k = n
        if k > avail then k = avail
        if copy then queue(p.ba, off, Int(k))
        m.parsePos = m.parsePos + k
        n = n - k
    end while
    ' Pieces fully used are let go.
    while m.pieces.Count() > 0
        q = m.pieces[0]
        if q.state <> "ready" or q.abs + q.ba.Count() > m.parsePos then exit while
        m.pieces.Shift()
    end while
end sub

' Walks the clusters, copying video and subtitles, dropping old audio and
' putting Dolby Digital in, as far as the downloaded data allows.
sub parse()
    guard = 0
    while guard < 400 and not m.ended
        guard = guard + 1
        if m.toSkip > 0 or m.toCopy > 0
            n = ready()
            if n <= 0 then return
            if m.toCopy > 0
                k = m.toCopy
                if k > n then k = n
                take(k, true)
                m.toCopy = m.toCopy - k
            else
                k = m.toSkip
                if k > n then k = n
                take(k, false)
                m.toSkip = m.toSkip - k
            end if
            if m.toSkip > 0 or m.toCopy > 0 then return
        end if
        if m.parsePos >= m.total
            m.ended = true
            exit while
        end if
        w = window(48)
        h = w.ba
        b0 = w.at
        if w.count < 12 and m.parsePos + w.count < m.total then return
        id = vint(h, b0, true)
        if id = invalid
            m.ended = true
            exit while
        end if
        sz = vint(h, b0 + id.length, false)
        if sz = invalid then return
        hlen = id.length + sz.length
        if id.value = 524531317 ' Cluster: written with unknown size
            take(hlen, false)
            c = CreateObject("roByteArray")
            for each v in [31, 67, 182, 117, 1, 255, 255, 255, 255, 255, 255, 255]
                c.Push(v)
            end for
            queue(c, 0, c.Count())
            m.mode = "cluster"
            m.clusterTc = -1
        else if m.mode = "top"
            ' Anything else at the top after the clusters (index, tags) ends the movie.
            m.ended = true
            exit while
        else if id.value = 231 ' Timecode of this cluster
            if w.count < hlen + sz.value then return
            m.clusterTc = beValue(h, b0 + hlen, sz.value)
            take(hlen + sz.value, true)
        else if id.value = 163 or id.value = 160 ' SimpleBlock / BlockGroup
            inner = hlen
            plain = false
            if id.value = 160
                ' BlockGroup: the track is in its Block (A1)
                bid = vint(h, b0 + hlen, true)
                if bid = invalid or bid.value <> 161
                    plain = true
                else
                    bsz = vint(h, b0 + hlen + bid.length, false)
                    if bsz = invalid then return
                    inner = hlen + bid.length + bsz.length
                end if
            end if
            if plain
                m.toCopy = hlen + sz.value
            else
                if w.count < inner + 4 then return
                track = h[b0 + inner] and 127
                rel = h[b0 + inner + 1] * 256 + h[b0 + inner + 2]
                if rel > 32767 then rel = rel - 65536
                if track = m.swapTrack or not m.keptTracks.DoesExist(track.ToStr())
                    ' The old DTS/TrueHD block, or another audio track left out.
                    m.toSkip = hlen + sz.value
                else
                    blockMs = (m.clusterTc + rel) * m.scale / 1000000.0
                    if not flushAudio(blockMs + 150) then return
                    m.toCopy = hlen + sz.value
                end if
            end if
        else if id.value = 167 or id.value = 171 ' Position / PrevSize: no longer true
            m.toSkip = hlen + sz.value
        else
            m.toCopy = hlen + sz.value
        end if
    end while
end sub

 ' ---- Small helpers ---------------------------------------------------------------------

function vint(ba as Object, at as Integer, keepMarker as Boolean) as Dynamic
    if at >= ba.Count() then return invalid
    b = ba[at]
    length = 1
    mask = 128
    while length <= 8 and (b and mask) = 0
        length = length + 1
        mask = mask >> 1
    end while
    if length > 8 or at + length > ba.Count() then return invalid
    v = 0#
    if keepMarker then v = b else v = b and (mask - 1)
    allOnes = (b and (mask - 1)) = mask - 1
    for k = 1 to length - 1
        v = v * 256 + ba[at + k]
        if ba[at + k] <> 255 then allOnes = false
    end for
    return {value: v, length: length, unknown: allOnes and not keepMarker}
end function

function beValue(ba as Object, at as Integer, count as Integer) as Double
    v = 0#
    for k = 0 to count - 1
        v = v * 256 + ba[at + k]
    end for
    return v
end function

function slice(ba as Object, at as Integer, count as Integer) as Object
    out = CreateObject("roByteArray")
    for k = at to at + count - 1
        out.Push(ba[k])
    end for
    return out
end function

' An EBML element with an 8-byte size.
function element(idBytes as Object, payload as Object) as Object
    out = CreateObject("roByteArray")
    for each v in idBytes
        out.Push(v)
    end for
    size = payload.Count()
    ' 8-byte size: 01 then 7 bytes (sizes here are far below 4 GB).
    for each v in [1, 0, 0, 0, (size >> 24) and 255, (size >> 16) and 255, (size >> 8) and 255, size and 255]
        out.Push(v)
    end for
    out.Append(payload)
    return out
end function

function uintBytes(v as Integer) as Object
    out = CreateObject("roByteArray")
    if v > 255 then out.Push((v >> 8) and 255)
    out.Push(v and 255)
    return out
end function

function asciiBytes(text as String) as Object
    out = CreateObject("roByteArray")
    out.FromAsciiString(text)
    return out
end function

' 48000.0 as a big-endian 8-byte float.
function doubleBytes48k() as Object
    out = CreateObject("roByteArray")
    for each v in [64, 231, 112, 0, 0, 0, 0, 0]
        out.Push(v)
    end for
    return out
end function

function fetchSync(first as Double, last as Double) as Dynamic
    transfer = newTransfer(m.url)
    transfer.AddHeader("Range", "bytes=" + wholeNumber(first) + "-" + wholeNumber(last))
    code = transfer.GetToFile(m.tmpName)
    if code <> 206 and code <> 200 then return invalid
    ba = CreateObject("roByteArray")
    ba.ReadFile(m.tmpName)
    DeleteFile(m.tmpName)
    return ba
end function

function newTransfer(url as String) as Object
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.EnableEncodings(false)
    for each h in m.headers
        cut = Instr(1, h, ":")
        if cut > 1 then transfer.AddHeader(Left(h, cut - 1).Trim(), Mid(h, cut + 1).Trim())
    end for
    return transfer
end function

function sourceLength() as Double
    transfer = newTransfer(m.url)
    transfer.AddHeader("Range", "bytes=0-0")
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.AsyncGetToString()
    event = Wait(30000, port)
    if type(event) <> "roUrlEvent" then return 0
    range = event.GetResponseHeaders()["content-range"]
    if range = invalid then return 0
    cut = Instr(1, range, "/")
    if cut = 0 then return 0
    return digits(Mid(range, cut + 1))
end function

function digits(text as String) as Double
    v = 0#
    text = text.Trim()
    for k = 1 to Len(text)
        c = Asc(Mid(text, k, 1))
        if c >= 48 and c <= 57 then v = v * 10 + (c - 48)
    end for
    return v
end function

function wholeNumber(v as Double) as String
    if v < 1000000 then return Int(v).ToStr()
    high = Int(v / 1000000)
    low = Int(v - high * 1000000#)
    lowText = low.ToStr()
    while Len(lowText) < 6
        lowText = "0" + lowText
    end while
    return high.ToStr() + lowText
end function
