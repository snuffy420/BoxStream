' Picture subtitles (PGS, from Blu-rays) and the pieces they need:
'   inflate()        zlib / deflate unpacking (tracks stored compressed)
'   pgsDisplaySet()  one PGS display set -> PNG images + positions
'   pgsPng()         a PGS bitmap (runLen-length coded) as a palette PNG
' Runs on the subtitle task's thread.

' ---- inflate (RFC 1951), after zlib's "puff" -------------------------------

function inflateZlib(src as Object, start as Integer, length as Integer) as Dynamic
    ' Skips the 2-byte zlib header; the Adler-32 at the end isn't checked.
    if length < 3 then return invalid
    return inflate(src, start + 2, start + length)
end function

function inflate(src as Object, start as Integer, stopAt as Integer) as Dynamic
    s = {src: src, at: start, stopAt: stopAt, bitbuf: 0, bitcnt: 0, out: CreateObject("roByteArray"), bad: false}
    lbase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    lext = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    dbase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    dext = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    final = 0
    while final = 0
        final = inflateBits(s, 1)
        kind = inflateBits(s, 2)
        if s.bad then return invalid
        if kind = 0
            ' stored
            s.bitbuf = 0
            s.bitcnt = 0
            if s.at + 4 > s.stopAt then return invalid
            n = src[s.at] + src[s.at + 1] * 256
            s.at = s.at + 4
            if s.at + n > s.stopAt then return invalid
            out = s.out
            for k = s.at to s.at + n - 1
                out.Push(src[k])
            end for
            s.at = s.at + n
        else if kind = 1 or kind = 2
            if kind = 1
                if m.fixedLen = invalid
                    lengths = []
                    for k = 0 to 143
                        lengths.Push(8)
                    end for
                    for k = 144 to 255
                        lengths.Push(9)
                    end for
                    for k = 256 to 279
                        lengths.Push(7)
                    end for
                    for k = 280 to 287
                        lengths.Push(8)
                    end for
                    m.fixedLen = huffTable(lengths)
                    dl = []
                    for k = 0 to 29
                        dl.Push(5)
                    end for
                    m.fixedDist = huffTable(dl)
                end if
                lencode = m.fixedLen
                distcode = m.fixedDist
            else
                nlen = inflateBits(s, 5) + 257
                ndist = inflateBits(s, 5) + 1
                ncode = inflateBits(s, 4) + 4
                order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                lengths = []
                for k = 0 to 18
                    lengths.Push(0)
                end for
                for k = 0 to ncode - 1
                    lengths[order[k]] = inflateBits(s, 3)
                end for
                codecode = huffTable(lengths)
                lengths = []
                while lengths.Count() < nlen + ndist
                    sym = huffDecode(s, codecode)
                    if sym < 0 then return invalid
                    if sym < 16
                        lengths.Push(sym)
                    else
                        value = 0
                        if sym = 16
                            if lengths.Count() = 0 then return invalid
                            value = lengths[lengths.Count() - 1]
                            rep = 3 + inflateBits(s, 2)
                        else if sym = 17
                            rep = 3 + inflateBits(s, 3)
                        else
                            rep = 11 + inflateBits(s, 7)
                        end if
                        for k = 1 to rep
                            lengths.Push(value)
                        end for
                    end if
                end while
                ll = []
                for k = 0 to nlen - 1
                    ll.Push(lengths[k])
                end for
                dl = []
                for k = nlen to nlen + ndist - 1
                    dl.Push(lengths[k])
                end for
                lencode = huffTable(ll)
                distcode = huffTable(dl)
            end if
            out = s.out
            while true
                sym = huffDecode(s, lencode)
                if sym < 0 or s.bad then return invalid
                if sym < 256
                    out.Push(sym)
                else if sym = 256
                    exit while
                else
                    sym = sym - 257
                    if sym >= 29 then return invalid
                    n = lbase[sym] + inflateBits(s, lext[sym])
                    dsym = huffDecode(s, distcode)
                    if dsym < 0 or dsym >= 30 then return invalid
                    dist = dbase[dsym] + inflateBits(s, dext[dsym])
                    from = out.Count() - dist
                    if from < 0 then return invalid
                    for k = 0 to n - 1
                        out.Push(out[from + k])
                    end for
                end if
            end while
        else
            return invalid
        end if
    end while
    return s.out
end function

function inflateBits(s as Object, need as Integer) as Integer
    value = s.bitbuf
    while s.bitcnt < need
        if s.at >= s.stopAt
            s.bad = true
            return 0
        end if
        value = value or (s.src[s.at] << s.bitcnt)
        s.at = s.at + 1
        s.bitcnt = s.bitcnt + 8
    end while
    s.bitbuf = value >> need
    s.bitcnt = s.bitcnt - need
    return value and ((1 << need) - 1)
end function

' Canonical Huffman table: counts per code length and symbols in order.
function huffTable(lengths as Object) as Object
    count = []
    for k = 0 to 15
        count.Push(0)
    end for
    for each n in lengths
        count[n] = count[n] + 1
    end for
    offs = [0, 0]
    for k = 1 to 14
        offs.Push(offs[k] + count[k])
    end for
    symbol = []
    for k = 0 to lengths.Count() - 1
        symbol.Push(0)
    end for
    for k = 0 to lengths.Count() - 1
        n = lengths[k]
        if n <> 0
            symbol[offs[n]] = k
            offs[n] = offs[n] + 1
        end if
    end for
    return {count: count, symbol: symbol}
end function

function huffDecode(s as Object, h as Object) as Integer
    code = 0
    first = 0
    index = 0
    count = h.count
    for n = 1 to 15
        code = code or inflateBits(s, 1)
        c = count[n]
        if code - c < first then return h.symbol[index + (code - first)]
        index = index + c
        first = (first + c) << 1
        code = code << 1
    end for
    return -1
end function

' ---- PGS --------------------------------------------------------------------

' One display set (the segments of one MKV block, or of one .sup entry).
' Returns {clear: true} for a "remove the picture" set, or
' {images: [{path, x, y, w, h}], vw, vh}, or invalid.
function pgsDisplaySet(ba as Object, start as Integer, stopAt as Integer, tag as String, skip as Integer) as Dynamic
    if m.pgsState = invalid then m.pgsState = {palette: invalid, objects: {}}
    state = m.pgsState
    pcs = invalid
    at = start
    while at + skip + 3 <= stopAt
        ' .sup files put a 10-byte "PG" header before every segment.
        at = at + skip
        kind = ba[at]
        size = ba[at + 1] * 256 + ba[at + 2]
        data = at + 3
        if data + size > stopAt then exit while
        if kind = 22 and size >= 11 ' PCS
            pcs = {vw: ba[data] * 256 + ba[data + 1], vh: ba[data + 2] * 256 + ba[data + 3], objects: []}
            n = ba[data + 10]
            p = data + 11
            for k = 1 to n
                if p + 8 > data + size then exit for
                o = {id: ba[p] * 256 + ba[p + 1], x: ba[p + 4] * 256 + ba[p + 5], y: ba[p + 6] * 256 + ba[p + 7]}
                if (ba[p + 3] and 128) <> 0 then p = p + 16 else p = p + 8
                pcs.objects.Push(o)
            end for
        else if kind = 20 ' PDS: palette entries Y Cr Cb A
            palette = state.palette
            if palette = invalid
                palette = []
                for k = 0 to 255
                    palette.Push([0, 0, 0, 0])
                end for
                state.palette = palette
            end if
            p = data + 2
            while p + 5 <= data + size
                y = ba[p + 1]
                cr = ba[p + 2] - 128
                cb = ba[p + 3] - 128
                r = Int(y + 1.5748 * cr + 0.5)
                g = Int(y - 0.1873 * cb - 0.4681 * cr + 0.5)
                b = Int(y + 1.8556 * cb + 0.5)
                if r < 0 then r = 0
                if r > 255 then r = 255
                if g < 0 then g = 0
                if g > 255 then g = 255
                if b < 0 then b = 0
                if b > 255 then b = 255
                palette[ba[p]] = [r, g, b, ba[p + 4]]
                p = p + 5
            end while
        else if kind = 21 and size >= 4 ' ODS (may come in several parts)
            id = ba[data] * 256 + ba[data + 1]
            flags = ba[data + 3]
            if (flags and 128) <> 0 and size >= 11
                obj = {w: ba[data + 7] * 256 + ba[data + 8], h: ba[data + 9] * 256 + ba[data + 10], rle: CreateObject("roByteArray"), path: ""}
                state.objects[id.ToStr()] = obj
                from = data + 11
            else
                obj = state.objects[id.ToStr()]
                from = data + 4
            end if
            if obj <> invalid
                rle = obj.rle
                for k = from to data + size - 1
                    rle.Push(ba[k])
                end for
                obj.path = ""
            end if
        end if
        at = data + size
    end while
    if pcs = invalid then return invalid
    if pcs.objects.Count() = 0 then return {clear: true}
    if state.palette = invalid then return invalid
    images = []
    for each o in pcs.objects
        obj = state.objects[o.id.ToStr()]
        if obj <> invalid and obj.w > 0 and obj.h > 0
            if obj.path = ""
                m.pgsFiles = m.pgsFiles + 1
                path = "tmp:/pgs-" + tag + "-" + m.pgsFiles.ToStr() + ".png"
                if pgsPng(obj, state.palette, path) then obj.path = path
            end if
            if obj.path <> "" then images.Push({path: obj.path, x: o.x, y: o.y, w: obj.w, h: obj.h})
        end if
    end for
    if images.Count() = 0 then return invalid
    return {images: images, vw: pcs.vw, vh: pcs.vh}
end function

' Decodes the bitmap's runs straight into a PNG's stored (uncompressed)
' deflate blocks: rows of one filter byte + one palette index per pixel.
function pgsPng(obj as Object, palette as Object, path as String) as Boolean
    w = obj.w
    h = obj.h
    rle = obj.rle
    n = rle.Count()
    idat = CreateObject("roByteArray")
    idat.Push(120) ' zlib header
    idat.Push(1)
    st = {idat: idat, head: 2, fill: 0, a: 1, b: 0, since: 0}
    pngBlockStart(st)
    i = 0
    rowsDone = 0
    x = 0
    pngPut(st, 0, 1) ' filter byte of the first row
    while i < n and rowsDone < h
        c = rle[i]
        i = i + 1
        if c <> 0
            if x < w
                pngPut(st, c, 1)
                x = x + 1
            end if
        else
            if i >= n then exit while
            f = rle[i]
            i = i + 1
            if f = 0
                ' end of row: pad short rows, start the next
                if x < w then pngPut(st, 0, w - x)
                rowsDone = rowsDone + 1
                x = 0
                if rowsDone < h then pngPut(st, 0, 1)
            else
                runLen = f and 63
                if (f and 64) <> 0
                    runLen = (runLen << 8) + rle[i]
                    i = i + 1
                end if
                color = 0
                if (f and 128) <> 0
                    color = rle[i]
                    i = i + 1
                end if
                if runLen > w - x then runLen = w - x
                if runLen > 0 then pngPut(st, color, runLen)
                x = x + runLen
            end if
        end if
    end while
    ' missing rows: transparent
    if rowsDone < h
        if x < w then pngPut(st, 0, w - x)
        rowsDone = rowsDone + 1
        while rowsDone < h
            pngPut(st, 0, 1 + w)
            rowsDone = rowsDone + 1
        end while
    end if
    pngBlockEnd(st, true)
    st.a = st.a mod 65521
    st.b = st.b mod 65521
    ' Adler-32: b then a, each two bytes, big-endian.
    idat.Push((st.b >> 8) and 255)
    idat.Push(st.b and 255)
    idat.Push((st.a >> 8) and 255)
    idat.Push(st.a and 255)
    ' palette: only the entries up to the highest one used
    used = 256
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
    for k = 0 to used - 1
        colors.Push(palette[k][0])
        colors.Push(palette[k][1])
        colors.Push(palette[k][2])
        alpha.Push(palette[k][3])
    end for
    pngChunk(png, "PLTE", colors)
    pngChunk(png, "tRNS", alpha)
    pngChunk(png, "IDAT", idat)
    pngChunk(png, "IEND", CreateObject("roByteArray"))
    ok = png.WriteFile(path)
    return ok
end function

' Appends "count" copies of a byte to the stored-deflate stream.
sub pngPut(st as Object, value as Integer, count as Integer)
    idat = st.idat
    a = st.a
    b = st.b
    fill = st.fill
    since = st.since
    for k = 1 to count
        if fill = 65535
            st.fill = fill
            pngBlockEnd(st, false)
            pngBlockStart(st)
            fill = 0
        end if
        idat.Push(value)
        fill = fill + 1
        a = a + value
        b = b + a
        since = since + 1
        if since >= 2000
            a = a mod 65521
            b = b mod 65521
            since = 0
        end if
    end for
    st.a = a
    st.b = b
    st.fill = fill
    st.since = since
end sub

sub pngBlockStart(st as Object)
    st.head = st.idat.Count()
    for k = 1 to 5
        st.idat.Push(0)
    end for
    st.fill = 0
end sub

sub pngBlockEnd(st as Object, last as Boolean)
    idat = st.idat
    n = st.fill
    if last then idat[st.head] = 1 else idat[st.head] = 0
    idat[st.head + 1] = n and 255
    idat[st.head + 2] = (n >> 8) and 255
    idat[st.head + 3] = (65535 - n) and 255
    idat[st.head + 4] = ((65535 - n) >> 8) and 255
end sub

sub putBE(ba as Object, value as Integer, bytes as Integer)
    for k = bytes - 1 to 0 step -1
        ba.Push((value >> (8 * k)) and 255)
    end for
end sub

sub pngChunk(png as Object, kind as String, data as Object)
    putBE(png, data.Count(), 4)
    chunk = CreateObject("roByteArray")
    chunk.FromAsciiString(kind)
    chunk.Append(data)
    crc = chunk.GetCRC32()
    png.Append(chunk)
    png.Push((crc >> 24) and 255)
    png.Push((crc >> 16) and 255)
    png.Push((crc >> 8) and 255)
    png.Push(crc and 255)
end sub

' ---- .sup files: "PG" + pts + dts + segment, repeated -----------------------

function supDisplaySets(ba as Object) as Object
    sets = []
    at = 0
    n = ba.Count()
    current = invalid
    while at + 13 <= n
        if ba[at] <> 80 or ba[at + 1] <> 71 then exit while ' "PG"
        pts = ((ba[at + 2] * 256.0 + ba[at + 3]) * 256.0 + ba[at + 4]) * 256.0 + ba[at + 5]
        size = ba[at + 11] * 256 + ba[at + 12]
        segment = at + 10
        if current = invalid then current = {s: pts / 90000.0, start: at, stop: at}
        current.stop = segment + 3 + size
        if ba[at + 10] = 128 ' END: the display set is complete
            sets.Push(current)
            current = invalid
        end if
        at = segment + 3 + size
    end while
    return sets
end function
