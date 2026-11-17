' DVD subtitles (VobSub): small 4-colour pictures, in an MKV track
' (S_VOBSUB, setup text in CodecPrivate) or as an .idx + .sub file pair.
' Each subtitle is an SPU: run-length coded rows (two interlaced fields)
' plus control commands for timing, colours, transparency and position.
' Turned into PNGs with the writer in Pgs.brs. Runs on the subtitle task.

' The .idx text (or an MKV track's CodecPrivate): frame size, the 16-colour
' palette and, for .idx, each subtitle's time and place in the .sub file.
function vobsubIdx(text as String) as Object
    info = {w: 720, h: 480, palette: [], entries: []}
    for k = 0 to 15
        info.palette.Push([k * 16, k * 16, k * 16])
    end for
    stamp = CreateObject("roRegex", "timestamp:\s*(\d+):(\d+):(\d+):(\d+),\s*filepos:\s*([0-9a-fA-F]+)", "")
    streams = 0
    for each line in text.Split(Chr(10))
        line = line.Replace(Chr(13), "").Trim()
        low = LCase(line)
        if Left(low, 5) = "size:"
            parts = Mid(line, 6).Trim().Split("x")
            if parts.Count() = 2
                info.w = Int(Val(parts[0]))
                info.h = Int(Val(parts[1]))
            end if
        else if Left(low, 8) = "palette:"
            colors = Mid(line, 9).Split(",")
            for k = 0 to colors.Count() - 1
                if k < 16
                    hexText = colors[k].Trim()
                    v = Val(hexText, 16)
                    info.palette[k] = [Int(v / 65536) and 255, Int(v / 256) and 255, v and 255]
                end if
            end for
        else if Left(low, 3) = "id:"
            streams = streams + 1
        else if streams <= 1
            ' The first language in the file only.
            hit = stamp.Match(line)
            if hit.Count() > 5
                s = Val(hit[1]) * 3600 + Val(hit[2]) * 60 + Val(hit[3]) + Val(hit[4]) / 1000
                info.entries.Push({s: s, pos: hexValue(hit[5])})
            end if
        end if
    end for
    return info
end function

' A hex file position, which can pass 2 GB.
function hexValue(text as String) as Double
    v = toDouble(0)
    for k = 1 to Len(text)
        v = v * 16 + Val(Mid(text, k, 1), 16)
    end for
    return v
end function

' The SPU inside a piece of a .sub file (MPEG program stream): pack headers,
' then private-stream-1 PES packets whose payload is the SPU's next part.
function vobsubDemux(ba as Object) as Dynamic
    spu = CreateObject("roByteArray")
    n = ba.Count()
    at = 0
    total = -1
    while at + 6 < n
        if ba[at] = 0 and ba[at + 1] = 0 and ba[at + 2] = 1
            code = ba[at + 3]
            if code = 186 ' pack header (MPEG-2: 14 bytes + stuffing)
                if at + 14 > n then exit while
                at = at + 14 + (ba[at + 13] and 7)
            else if code = 189 ' private stream 1: the subtitle data
                size = ba[at + 4] * 256 + ba[at + 5]
                headerLength = ba[at + 8]
                payload = at + 9 + headerLength + 1 ' after the sub-stream id byte
                stopAt = at + 6 + size
                if stopAt > n then stopAt = n
                for k = payload to stopAt - 1
                    spu.Push(ba[k])
                end for
                if total < 0 and spu.Count() >= 2 then total = spu[0] * 256 + spu[1]
                if total > 0 and spu.Count() >= total then return spu
                at = at + 6 + size
            else if code >= 187 ' other streams (padding, video...): skip them
                at = at + 6 + ba[at + 4] * 256 + ba[at + 5]
            else
                at = at + 1
            end if
        else
            at = at + 1
        end if
    end while
    if total > 0 and spu.Count() >= total then return spu
    return invalid
end function

' One SPU -> {images, vw, vh, dur} (dur in seconds, 0 = until the next one).
function vobsubPicture(ba as Object, start as Integer, stopAt as Integer, info as Object, tag as String) as Dynamic
    if stopAt - start < 8 then return invalid
    dcsq = ba[start + 2] * 256 + ba[start + 3]
    colors = [0, 1, 2, 3]
    alpha = [0, 15, 15, 15]
    x1 = 0
    x2 = -1
    y1 = 0
    y2 = -1
    top = -1
    bottom = -1
    showAt = 0.0
    hideAt = 0.0
    off = dcsq
    guard = 0
    while off + 4 <= stopAt - start and guard < 32
        guard = guard + 1
        date = (ba[start + off] * 256 + ba[start + off + 1]) * 1024 / 90000.0
        nextOff = ba[start + off + 2] * 256 + ba[start + off + 3]
        p = start + off + 4
        while p < stopAt
            cmd = ba[p]
            p = p + 1
            if cmd = 255 then exit while
            if cmd = 0 or cmd = 1
                showAt = date
            else if cmd = 2
                hideAt = date
            else if cmd = 3
                colors = [ba[p + 1] and 15, (ba[p + 1] >> 4) and 15, ba[p] and 15, (ba[p] >> 4) and 15]
                p = p + 2
            else if cmd = 4
                alpha = [ba[p + 1] and 15, (ba[p + 1] >> 4) and 15, ba[p] and 15, (ba[p] >> 4) and 15]
                p = p + 2
            else if cmd = 5
                x1 = ba[p] * 16 + (ba[p + 1] >> 4)
                x2 = (ba[p + 1] and 15) * 256 + ba[p + 2]
                y1 = ba[p + 3] * 16 + (ba[p + 4] >> 4)
                y2 = (ba[p + 4] and 15) * 256 + ba[p + 5]
                p = p + 6
            else if cmd = 6
                top = ba[p] * 256 + ba[p + 1]
                bottom = ba[p + 2] * 256 + ba[p + 3]
                p = p + 4
            else
                exit while ' unknown command: stop reading this sequence
            end if
        end while
        if nextOff = off then exit while
        off = nextOff
    end while
    w = x2 - x1 + 1
    h = y2 - y1 + 1
    if w <= 0 or h <= 0 or top < 0 or bottom < 0 then return invalid
    ' Interlaced: even rows from the top field, odd rows from the bottom one.
    pixels = CreateObject("roByteArray")
    pixels.SetResize(w * h, false)
    for k = 0 to w * h - 1
        pixels.Push(0)
    end for
    vobsubField(ba, start + top, stopAt, pixels, w, h, 0)
    vobsubField(ba, start + bottom, stopAt, pixels, w, h, 1)
    palette = []
    for k = 0 to 3
        c = info.palette[colors[k]]
        palette.Push([c[0], c[1], c[2], alpha[k] * 17])
    end for
    m.pgsFiles = m.pgsFiles + 1
    path = "tmp:/pgs-" + tag + "-" + m.pgsFiles.ToStr() + ".png"
    if not indexedPng(pixels, w, h, palette, path) then return invalid
    dur = 0.0
    if hideAt > showAt then dur = hideAt - showAt
    return {images: [{path: path, x: x1, y: y1, w: w, h: h}], vw: info.w, vh: info.h, dur: dur, delay: showAt}
end function

' Run-length rows of one field: codes of 1-4 nibbles, (run << 2) | colour;
' a run of 0 fills the row; each row ends on a byte boundary.
sub vobsubField(ba as Object, start as Integer, stopAt as Integer, pixels as Object, w as Integer, h as Integer, firstRow as Integer)
    nib = start * 2
    last = stopAt * 2
    y = firstRow
    while y < h and nib < last
        x = 0
        rowBase = y * w
        while x < w and nib < last
            v = nibbleAt(ba, nib)
            nib = nib + 1
            if v < 4
                v = (v << 4) or nibbleAt(ba, nib)
                nib = nib + 1
                if v < 16
                    v = (v << 4) or nibbleAt(ba, nib)
                    nib = nib + 1
                    if v < 64
                        v = (v << 4) or nibbleAt(ba, nib)
                        nib = nib + 1
                    end if
                end if
            end if
            runLen = v >> 2
            color = v and 3
            if runLen = 0 or x + runLen > w then runLen = w - x
            if color <> 0
                for k = rowBase + x to rowBase + x + runLen - 1
                    pixels[k] = color
                end for
            end if
            x = x + runLen
        end while
        if (nib and 1) = 1 then nib = nib + 1
        y = y + 2
    end while
end sub

function nibbleAt(ba as Object, n as Integer) as Integer
    b = ba[n >> 1]
    if (n and 1) = 0 then return (b >> 4) and 15
    return b and 15
end function

' A palette PNG from one byte per pixel (stored deflate, as in pgsPng).
function indexedPng(pixels as Object, w as Integer, h as Integer, palette as Object, path as String) as Boolean
    idat = CreateObject("roByteArray")
    idat.Push(120)
    idat.Push(1)
    st = {idat: idat, head: 2, fill: 0, a: 1, b: 0, since: 0}
    pngBlockStart(st)
    for y = 0 to h - 1
        pngPut(st, 0, 1)
        base = y * w
        for x = 0 to w - 1
            pngPut(st, pixels[base + x], 1)
        end for
    end for
    pngBlockEnd(st, true)
    st.a = st.a mod 65521
    st.b = st.b mod 65521
    idat.Push((st.b >> 8) and 255)
    idat.Push(st.b and 255)
    idat.Push((st.a >> 8) and 255)
    idat.Push(st.a and 255)
    png = CreateObject("roByteArray")
    for each v in [137, 80, 78, 71, 13, 10, 26, 10]
        png.Push(v)
    end for
    header = CreateObject("roByteArray")
    putBE(header, w, 4)
    putBE(header, h, 4)
    for each v in [8, 3, 0, 0, 0]
        header.Push(v)
    end for
    pngChunk(png, "IHDR", header)
    colors = CreateObject("roByteArray")
    alpha = CreateObject("roByteArray")
    for each c in palette
        colors.Push(c[0])
        colors.Push(c[1])
        colors.Push(c[2])
        alpha.Push(c[3])
    end for
    pngChunk(png, "PLTE", colors)
    pngChunk(png, "tRNS", alpha)
    pngChunk(png, "IDAT", idat)
    pngChunk(png, "IEND", CreateObject("roByteArray"))
    return png.WriteFile(path)
end function
