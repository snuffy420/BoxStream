' Local relay (see LocalRelay.xml): a small web server on the Roku that the
' player reads from. It serves one "virtual file" made of byte ranges of
' files on the source (with an optional header in front):
'   request {url, headers}                    the file unchanged
'   request {url, headers, slimFlac: true}    FLAC with only STREAMINFO before the audio
'   request {album: [urls], headers, format}  an album as ONE stream (gapless):
'       "flac": first track's STREAMINFO, then every track's audio frames
'       "mp3":  every track's frames, ID3 tags left out
' Each connection keeps a few 2 MB pieces downloading ahead (the next track
' starts loading well before the current one ends).

sub init()
    m.top.functionName = "runRelay"
end sub

sub runRelay()
    req = m.top.request
    m.port = CreateObject("roMessagePort")
    m.headers = req.headers
    if m.headers = invalid then m.headers = []
    m.piece = 2097152
    m.ahead = 4
    m.files = 0
    m.prefix = invalid
    m.segs = []
    m.ctype = "video/x-matroska"
    m.albumUrls = invalid
    if req.album <> invalid
        m.albumUrls = req.album
        m.albumFormat = req.format
        m.albumNext = 0
        m.albumV = -1#
        m.startFraction = 0
        if req.startFraction <> invalid then m.startFraction = req.startFraction
        ' The stream's declared length: all track files added up (the real
        ' audio is a little shorter; the end is padded with zeros).
        ' Sizes known from an earlier play give the exact length; otherwise
        ' playback starts at once with a large stand-in length (no padding at
        ' the end then) and each size is learned when its track comes up.
        m.albumSizes = []
        m.declared = 0#
        m.exactLength = true
        for i = 0 to req.album.Count() - 1
            size = 0#
            if req.sizes <> invalid and i < req.sizes.Count() and req.sizes[i] <> invalid then size = req.sizes[i]
            m.albumSizes.Push(size)
            if size <= 0 then m.exactLength = false
            m.declared = m.declared + size
        end for
        if not m.exactLength then m.declared = 4000.0 * 1000000.0
        resolveNextTrack()
        if m.prefix <> invalid then m.declared = m.declared + m.prefix.Count()
    else
        total = fileLength(req.url)
        start = 0#
        if req.slimFlac = true
            info = flacLayout(req.url, total)
            if info <> invalid
                m.prefix = info.prefix
                start = info.audioStart
                m.ctype = "audio/flac"
            end if
        end if
        m.segs.Push({url: req.url, src: start, len: total - start})
    end if
    vstart = 0#
    if m.prefix <> invalid then vstart = m.prefix.Count()
    if m.albumUrls = invalid
        for each s in m.segs
            s.v = vstart
            vstart = vstart + s.len
        end for
    else
        vstart = m.albumV
    end if
    m.vtotal = vstart
    starts = []
    for each s in m.segs
        starts.Push(s.v)
    end for
    m.listener = CreateObject("roStreamSocket")
    address = CreateObject("roSocketAddress")
    port = 8899
    if req.port <> invalid then port = req.port
    address.SetAddress("127.0.0.1:" + port.ToStr())
    m.listener.SetAddress(address)
    m.listener.SetMessagePort(m.port)
    m.listener.NotifyReadable(true)
    if not m.listener.Listen(8)
        print "[relay] couldn't listen"
        return
    end if
    m.clients = {}
    m.transfers = {}
    m.top.stats = {bytes: m.vtotal, trackStarts: starts, sizes: m.albumSizes, urls: m.albumUrls}
    ext = ".mkv"
    if m.ctype = "audio/flac" then ext = ".flac"
    if m.ctype = "audio/mpeg" then ext = ".mp3"
    m.top.address = "http://127.0.0.1:" + port.ToStr() + "/stream"
    while m.top.quit <> true
        event = Wait(20, m.port)
        if type(event) = "roUrlEvent"
            pieceDone(event)
        else if type(event) = "roSocketEvent"
            if m.listener.IsReadable()
                sock = m.listener.Accept()
                if sock <> invalid then addClient(sock)
            end if
        end if
        for each id in m.clients.Keys()
            pumpClient(m.clients[id])
        end for
    end while
    ' Told to quit: close everything so the port and downloads are freed.
    for each id in m.clients.Keys()
        dropClient(m.clients[id])
    end for
    m.listener.Close()
end sub

' ---- Album as one stream -----------------------------------------------------

' Adds the next album track's audio to the stream (its header is read now,
' while the previous track is still playing).
sub resolveNextTrack()
    if m.albumUrls = invalid or m.albumNext >= m.albumUrls.Count() then return
    url = m.albumUrls[m.albumNext]
    first = m.albumNext = 0
    m.albumNext = m.albumNext + 1
    format = m.albumFormat
    total = 0#
    if m.albumSizes <> invalid and m.albumNext - 1 < m.albumSizes.Count() then total = m.albumSizes[m.albumNext - 1]
    if total <= 0
        total = fileLength(url)
        if m.albumSizes <> invalid and m.albumNext - 1 < m.albumSizes.Count() then m.albumSizes[m.albumNext - 1] = total
        ' Tell the app, so the next start (a seek) knows this size.
        m.top.stats = {sizes: m.albumSizes, urls: m.albumUrls}
    end if
    ' (the first track's size is used from here too)
    if total <= 0 then total = fileLength(url)
    if total > 0
        if format = "flac"
            m.ctype = "audio/flac"
            info = flacLayout(url, total)
            if info <> invalid and first
                ' The first track's STREAMINFO, with the total length and MD5
                ' cleared (the joined stream is longer than one track).
                p = info.prefix
                p[21] = p[21] and 240
                for k = 22 to 41
                    p[k] = 0
                end for
                m.prefix = p
            end if
            if info <> invalid
                src = info.audioStart
                if first and m.startFraction > 0 then src = src + Int((total - info.audioStart) * m.startFraction)
                addSeg({url: url, src: src, len: total - src})
            end if
        else
            m.ctype = "audio/mpeg"
            start = 0#
            head = readBytes(url, 0, 9)
            if head <> invalid and head[0] = 73 and head[1] = 68 and head[2] = 51
                start = 10 + ((head[6] and 127) * 2097152) + ((head[7] and 127) * 16384) + ((head[8] and 127) * 128) + (head[9] and 127)
            end if
            stopAt = total
            tail = readBytes(url, total - 128, 2)
            if tail <> invalid and tail[0] = 84 and tail[1] = 65 and tail[2] = 71 then stopAt = total - 128
            if first and m.startFraction > 0 then start = start + Int((stopAt - start) * m.startFraction)
            addSeg({url: url, src: start, len: stopAt - start})
        end if
    end if
end sub

sub addSeg(s as Object)
    if m.albumV < 0
        m.albumV = 0
        if m.prefix <> invalid then m.albumV = m.prefix.Count()
    end if
    s.v = m.albumV
    m.albumV = m.albumV + s.len
    m.segs.Push(s)
end sub

' "fLaC" + STREAMINFO (42 bytes) and where the audio frames start.
function flacLayout(url as String, total as Double) as Dynamic
    at = 0#
    head = readBytes(url, 0, 9)
    if head = invalid then return invalid
    if head[0] = 73 and head[1] = 68 and head[2] = 51
        at = 10 + ((head[6] and 127) * 2097152) + ((head[7] and 127) * 16384) + ((head[8] and 127) * 128) + (head[9] and 127)
    end if
    sig = readBytes(url, at, 3)
    if sig = invalid or sig[0] <> 102 or sig[1] <> 76 or sig[2] <> 97 or sig[3] <> 67 then return invalid
    at = at + 4
    info = invalid
    guard = 0
    while guard < 64
        guard = guard + 1
        h = readBytes(url, at, 3)
        if h = invalid then return invalid
        isLast = (h[0] and 128) <> 0
        kind = h[0] and 127
        size = h[1] * 65536 + h[2] * 256 + h[3]
        if kind = 0 then info = readBytes(url, at + 4, 33)
        at = at + 4 + size
        if isLast then exit while
    end while
    if info = invalid then return invalid
    p = CreateObject("roByteArray")
    for each v in [102, 76, 97, 67, 128, 0, 0, 34]
        p.Push(v)
    end for
    for k = 0 to 33
        p.Push(info[k])
    end for
    return {prefix: p, audioStart: at}
end function

' ---- Serving -------------------------------------------------------------------

sub addClient(sock as Object)
    sock.SetMessagePort(m.port)
    sock.NotifyReadable(true)
    id = sock.GetID().ToStr()
    m.clients[id] = {id: id, sock: sock, head: "", started: false, pieces: [], next: 0#, last: -1#, buffer: invalid, offset: 0, sent: 0#, clock: CreateObject("roTimespan")}
end sub

sub dropClient(c as Object)
    for each p in c.pieces
        if p.transfer <> invalid then p.transfer.AsyncCancel()
        if p.path <> invalid then DeleteFile(p.path)
    end for
    c.sock.Close()
    m.clients.Delete(c.id)
end sub

sub pumpClient(c as Object)
    if not c.started
        text = c.sock.ReceiveStr(8192)
        if text <> invalid then c.head = c.head + text
        if Instr(1, c.head, Chr(13) + Chr(10) + Chr(13) + Chr(10)) = 0
            if c.clock.TotalMilliseconds() > 10000 then dropClient(c)
            return
        end if
        startReply(c)
        return
    end if
    ' Album: once the stream is reading the last known track, add the next.
    if m.albumUrls <> invalid and m.segs.Count() > 0
        lastSeg = m.segs[m.segs.Count() - 1]
        if c.next >= lastSeg.v and m.albumNext < m.albumUrls.Count() then resolveNextTrack()
        if m.albumNext >= m.albumUrls.Count() then c.last = m.albumV - 1
    end if
    ' Keep pieces downloading ahead, each within one part (track).
    while c.pieces.Count() < m.ahead and c.next <= c.last
        seg = segAt(c.next)
        if seg = invalid then exit while
        stopAt = c.next + m.piece - 1
        if stopAt > c.last then stopAt = c.last
        if stopAt > seg.v + seg.len - 1 then stopAt = seg.v + seg.len - 1
        c.pieces.Push(startPiece(seg.url, seg.src + (c.next - seg.v), seg.src + (stopAt - seg.v)))
        c.next = stopAt + 1
    end while
    guard = 0
    while guard < 64
        guard = guard + 1
        if c.buffer = invalid
            if c.pieces.Count() = 0
                if c.next > c.last
                    if c.padTo <> invalid and c.sent < c.padTo
                        ' Fill up to the declared length.
                        n = c.padTo - c.sent
                        if n > 65536 then n = 65536
                        if m.zeroBlock = invalid
                            m.zeroBlock = CreateObject("roByteArray")
                            for k = 1 to 65536
                                m.zeroBlock.Push(0)
                            end for
                        end if
                        c.buffer = m.zeroBlock
                        c.offset = Int(65536 - n)
                        return
                    end if
                    dropClient(c)
                end if
                return
            end if
            p = c.pieces[0]
            if p.state = "failed"
                dropClient(c)
                return
            end if
            if p.state <> "ready" then return
            c.pieces.Shift()
            c.buffer = CreateObject("roByteArray")
            c.buffer.ReadFile(p.path)
            DeleteFile(p.path)
            if c.chunked = true then c.buffer = chunkOf(c.buffer)
            c.offset = 0
        end if
        n = c.buffer.Count() - c.offset
        if n <= 0
            c.buffer = invalid
        else
            k = c.sock.Send(c.buffer, c.offset, n)
            if k > 0
                c.offset = c.offset + k
                c.sent = c.sent + k
            else
                if c.sock.eOK() or c.sock.eAgain() or c.sock.eWouldBlock() then return
                dropClient(c)
                return
            end if
        end if
    end while
end sub

function segAt(v as Double) as Dynamic
    for each s in m.segs
        if v >= s.v and v < s.v + s.len then return s
    end for
    return invalid
end function

sub startReply(c as Object)
    if UCase(Left(c.head, 4)) = "HEAD"
        ' Headers-only requests: refused, so the player goes straight to GET
        ' (answering them with a stream body confuses Roku's music player).
        c.sock.SendStr("HTTP/1.1 405 Method Not Allowed" + Chr(13) + Chr(10) + "Content-Length: 0" + Chr(13) + Chr(10) + "Connection: close" + Chr(13) + Chr(10) + Chr(13) + Chr(10))
        dropClient(c)
        return
    end if
    first = 0#
    last = m.vtotal - 1
    ranged = false
    for each line in c.head.Split(Chr(10))
        low = LCase(line.Trim())
        if Left(low, 13) = "range: bytes="
            ranged = true
            spec = Mid(low, 14).Split("-")
            first = digits(spec[0])
            if spec.Count() > 1 and spec[1].Trim() <> "" then last = digits(spec[1])
        end if
    end for
    if last > m.vtotal - 1 then last = m.vtotal - 1
    crlf = Chr(13) + Chr(10)
    if m.albumUrls <> invalid
        ' One continuous stream of unknown length, from the start.
        c.sock.SendStr("HTTP/1.1 200 OK" + crlf + "Content-Type: " + m.ctype + crlf + "Content-Length: " + wholeNumber(m.declared) + crlf + "Connection: close" + crlf + crlf)
        c.started = true
        if m.exactLength = true then c.padTo = m.declared
        c.next = 0
        c.last = 1000000.0 * 1000000.0
        if m.prefix <> invalid
            c.buffer = m.prefix
            c.offset = 0
            c.next = m.prefix.Count()
        end if
        c.clock.Mark()
        return
    end if
    reply = "HTTP/1.1 206 Partial Content" + crlf
    if not ranged then reply = "HTTP/1.1 200 OK" + crlf
    reply = reply + "Content-Type: " + m.ctype + crlf
    reply = reply + "Accept-Ranges: bytes" + crlf
    reply = reply + "Content-Length: " + wholeNumber(last - first + 1) + crlf
    if ranged then reply = reply + "Content-Range: bytes " + wholeNumber(first) + "-" + wholeNumber(last) + "/" + wholeNumber(m.vtotal) + crlf
    reply = reply + "Connection: close" + crlf + crlf
    c.sock.SendStr(reply)
    c.started = true
    c.next = first
    c.last = last
    if m.prefix <> invalid
        n = m.prefix.Count()
        if first < n
            stopAt = last
            if stopAt > n - 1 then stopAt = n - 1
            c.sock.Send(m.prefix, Int(first), Int(stopAt - first + 1))
            c.next = n
        end if
    end if
    c.clock.Mark()
end sub

function startPiece(url as String, first as Double, last as Double) as Object
    transfer = newTransfer(url)
    transfer.SetMessagePort(m.port)
    transfer.AddHeader("Range", "bytes=" + wholeNumber(first) + "-" + wholeNumber(last))
    m.files = m.files + 1
    path = "tmp:/relay-" + m.files.ToStr() + ".bin"
    piece = {path: path, transfer: transfer, state: "loading"}
    if transfer.AsyncGetToFile(path)
        m.transfers[transfer.GetIdentity().ToStr()] = piece
    else
        piece.state = "failed"
    end if
    return piece
end function

sub pieceDone(event as Object)
    id = event.GetSourceIdentity().ToStr()
    piece = m.transfers[id]
    if piece = invalid then return
    m.transfers.Delete(id)
    code = event.GetResponseCode()
    piece.transfer = invalid
    if code = 206 or code = 200 then piece.state = "ready" else piece.state = "failed"
end sub

' ---- Source requests -------------------------------------------------------------

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

function fileLength(url as String) as Double
    transfer = newTransfer(url)
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

function readBytes(url as String, first as Double, count as Double) as Dynamic
    transfer = newTransfer(url)
    transfer.AddHeader("Range", "bytes=" + wholeNumber(first) + "-" + wholeNumber(first + count))
    path = "tmp:/relay-head.bin"
    code = transfer.GetToFile(path)
    if code <> 206 and code <> 200 then return invalid
    ba = CreateObject("roByteArray")
    ba.ReadFile(path)
    if ba.Count() <= count then return invalid
    return ba
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

' One HTTP chunk: the length in hex, the data, CRLF.
function chunkOf(data as Object) as Object
    out = CreateObject("roByteArray")
    out.FromAsciiString(StrI(data.Count(), 16) + Chr(13) + Chr(10))
    out.Append(data)
    out.Push(13)
    out.Push(10)
    return out
end function

' Exact sizes of several files: the known ones as given, the rest asked for
' all at once (one round trip instead of one per file).
function fileLengths(urls as Object, known as Dynamic) as Object
    sizes = []
    port = CreateObject("roMessagePort")
    pending = {}
    for i = 0 to urls.Count() - 1
        size = 0#
        if known <> invalid and i < known.Count() and known[i] <> invalid then size = known[i]
        sizes.Push(size)
        if size <= 0
            transfer = newTransfer(urls[i])
            transfer.AddHeader("Range", "bytes=0-0")
            transfer.SetMessagePort(port)
            if transfer.AsyncGetToString() then pending[transfer.GetIdentity().ToStr()] = {index: i, transfer: transfer}
        end if
    end for
    while pending.Count() > 0
        event = Wait(30000, port)
        if type(event) <> "roUrlEvent" then exit while
        id = event.GetSourceIdentity().ToStr()
        job = pending[id]
        if job <> invalid
            pending.Delete(id)
            range = event.GetResponseHeaders()["content-range"]
            if range <> invalid
                cut = Instr(1, range, "/")
                if cut > 0 then sizes[job.index] = digits(Mid(range, cut + 1))
            end if
        end if
    end while
    return sizes
end function
