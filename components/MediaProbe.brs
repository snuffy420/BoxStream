' MediaInfo: reads a file's own headers (first megabyte, plus the end of an
' MP4 whose index is stored last) and describes its streams.
' Runs in the library worker. Result: {container, sizeMb, seconds, bitrate,
' video: [{codec, width, height, fps, bits, hdr}], audio: [{codec, channels,
' rate, bits, lang, name, default}], subs: [{codec, lang, name, forced, text}]}

function probeResult() as Object
    return {container: "", sizeMb: -1, seconds: 0, bitrate: 0, video: [], audio: [], subs: [], partial: false, general: {}, chapters: []}
end function

' ---- Bytes ------------------------------------------------------------------------

function beInt(ba as Object, i as Integer, n as Integer) as Double
    v = 0#
    for k = 0 to n - 1
        v = v * 256 + ba[i + k]
    end for
    return v
end function

function leInt(ba as Object, i as Integer, n as Integer) as Double
    v = 0#
    for k = n - 1 to 0 step -1
        v = v * 256 + ba[i + k]
    end for
    return v
end function

function fourcc(ba as Object, i as Integer) as String
    s = ""
    for k = 0 to 3
        c = ba[i + k]
        if c < 32 or c > 126 then return ""
        s = s + Chr(c)
    end for
    return s
end function

function bytesText(ba as Object, i as Integer, n as Integer) as String
    s = ""
    for k = 0 to n - 1
        c = ba[i + k]
        if c = 0 then exit for
        if c >= 32 and c < 127 then s = s + Chr(c)
    end for
    return s
end function

' IEEE 754 float (4 or 8 bytes, big-endian).
function beFloat(ba as Object, i as Integer, n as Integer) as Double
    if n = 4
        raw = beInt(ba, i, 4)
        sign = 1
        half = 2147483648#
        if raw >= half then sign = -1
        exponent = Int(raw / 8388608) mod 256
        mantissa = raw - Int(raw / 8388608) * 8388608
        if exponent = 0 then return 0
        two = 2#
        return sign * (1 + mantissa / 8388608) * (two ^ (exponent - 127))
    end if
    two = 2#
    hi = beInt(ba, i, 2)
    sign = 1
    if hi >= 32768 then sign = -1
    exponent = Int(hi / 16) mod 2048
    mantissa = (hi mod 16) * (two ^ 48) + beInt(ba, i + 2, 6)
    if exponent = 0 then return 0
    return sign * (1 + mantissa / (two ^ 52)) * (two ^ (exponent - 1023))
end function

' ---- Matroska (MKV / WebM) ---------------------------------------------------------

' Reads an EBML variable-length number. id: keep the length marker.
function ebmlVint(ba as Object, i as Integer, id as Boolean) as Object
    if i >= ba.Count() then return invalid
    first = ba[i]
    length = 1
    mask = 128
    while length <= 8 and (first and mask) = 0
        length = length + 1
        mask = Int(mask / 2)
    end while
    if length > 8 or i + length > ba.Count() then return invalid
    if id
        value = beInt(ba, i, length)
        unknown = false
    else
        value = (first and (mask - 1)) * 1#
        allOnes = (first and (mask - 1)) = mask - 1
        for k = 1 to length - 1
            value = value * 256 + ba[i + k]
            if ba[i + k] <> 255 then allOnes = false
        end for
        unknown = allOnes
    end if
    return {value: value, length: length, unknown: unknown}
end function

function probeMkv(ba as Object) as Object
    result = probeResult()
    result.container = "MKV"
    count = ba.Count()
    i = 0
    scale = 1000000#
    duration = 0#
    ' Walk top level, step into Segment, then read Info and Tracks.
    while i < count - 8
        idv = ebmlVint(ba, i, true)
        if idv = invalid then exit while
        sz = ebmlVint(ba, i + idv.length, false)
        if sz = invalid then exit while
        dataStart = i + idv.length + sz.length
        id = idv.value
        if id = 440786851 ' EBML header 0x1A45DFA3
            j = dataStart
            while j < dataStart + sz.value and j < count - 2
                cid = ebmlVint(ba, j, true)
                csz = ebmlVint(ba, j + cid.length, false)
                if cid = invalid or csz = invalid then exit while
                c = j + cid.length + csz.length
                if cid.value = 17031 then result.general.version = beInt(ba, c, csz.value) ' DocTypeVersion
                if cid.value = 17026 then result.general.doctype = bytesText(ba, c, csz.value) ' DocType
                j = c + csz.value
            end while
            i = dataStart + sz.value
        else if id = 408125543 ' Segment 0x18538067
            i = dataStart
        else if id = 357149030 ' Info 0x1549A966
            j = dataStart
            stopAt = dataStart + sz.value
            while j < stopAt and j < count - 4
                cid = ebmlVint(ba, j, true)
                csz = ebmlVint(ba, j + cid.length, false)
                if cid = invalid or csz = invalid then exit while
                cstart = j + cid.length + csz.length
                if cid.value = 2807729 then scale = beInt(ba, cstart, csz.value) ' TimecodeScale
                if cid.value = 17545 then duration = beFloat(ba, cstart, csz.value) ' Duration
                if cid.value = 31657 then result.general.title = utf8Text(ba, cstart, csz.value) ' Title
                if cid.value = 19840 then result.general.muxer = bytesText(ba, cstart, csz.value) ' MuxingApp
                if cid.value = 22337 then result.general.writer = bytesText(ba, cstart, csz.value) ' WritingApp
                j = cstart + csz.value
            end while
            i = dataStart + sz.value
        else if id = 374648427 ' Tracks 0x1654AE6B
            j = dataStart
            stopAt = dataStart + sz.value
            if stopAt > count then
                stopAt = count
                result.partial = true
            end if
            while j < stopAt - 2
                cid = ebmlVint(ba, j, true)
                csz = ebmlVint(ba, j + cid.length, false)
                if cid = invalid or csz = invalid then exit while
                cstart = j + cid.length + csz.length
                if cid.value = 174 then mkvTrack(ba, cstart, cstart + csz.value, result) ' TrackEntry 0xAE
                j = cstart + csz.value
            end while
            i = dataStart + sz.value
        else if id = 272869232 ' Chapters 0x1043A770
            mkvChapters(ba, dataStart, dataStart + sz.value, result)
            i = dataStart + sz.value
        else if id = 524531317 ' Cluster: the streams themselves start here
            ' The encoder's own note (x264 / x265 settings) sits in the first frame.
            result.general.encoder = findEncoderNote(ba, dataStart)
            exit while
        else
            if sz.unknown then exit while
            i = dataStart + sz.value
        end if
    end while
    billion = 1000000000#
    if duration > 0 then result.seconds = duration * scale / billion
    return result
end function

sub mkvTrack(ba as Object, start as Integer, stopAt as Integer, result as Object)
    t = {kind: 0, codec: "", lang: "eng", name: "", default: true, forced: false, width: 0, height: 0, fps: 0, bits: 0, hdr: "", channels: 0, rate: 0, private: invalid, number: 0, profile: "", displayWidth: 0, displayHeight: 0, interlaced: 0, primaries: 0, range: 0, maxCll: 0, maxFall: 0}
    langSet = false
    count = ba.Count()
    if stopAt > count then stopAt = count
    j = start
    while j < stopAt - 1
        cid = ebmlVint(ba, j, true)
        if cid = invalid then exit while
        csz = ebmlVint(ba, j + cid.length, false)
        if csz = invalid then exit while
        c = j + cid.length + csz.length
        n = csz.value
        id = cid.value
        if id = 131 then t.kind = beInt(ba, c, n) ' TrackType
        if id = 215 then t.number = beInt(ba, c, n) ' TrackNumber
        if id = 134 then t.codec = bytesText(ba, c, n) ' CodecID
        if id = 2274716 and not langSet then t.lang = bytesText(ba, c, n) ' Language
        if id = 2274717
            t.lang = bytesText(ba, c, n) ' LanguageIETF (BCP 47)
            langSet = true
        end if
        if id = 21358 then t.name = bytesText(ba, c, n) ' Name
        if id = 136 then t.default = beInt(ba, c, n) = 1 ' FlagDefault
        if id = 21930 then t.forced = beInt(ba, c, n) = 1 ' FlagForced
        if id = 2352003 and n > 0 ' DefaultDuration (ns per frame)
            ns = beInt(ba, c, n)
            billion = 1000000000#
            if ns > 0 then t.fps = Int(billion / ns * 1000 + 0.5) / 1000
        end if
        if id = 25506 then t.private = {start: c, length: n} ' CodecPrivate
        if id = 224 then mkvVideo(ba, c, c + n, t) ' Video
        if id = 225 then mkvAudio(ba, c, c + n, t) ' Audio
        j = c + n
    end while
    ' Bit depth, profile and level from the codec's own setup block (hvcC / avcC).
    if t.private <> invalid
        codec = UCase(t.codec)
        if Instr(1, codec, "HEVC") > 0
            if t.bits = 0 then t.bits = hevcBits(ba, t.private.start, t.private.length)
            t.profile = hevcProfile(ba, t.private.start, t.private.length)
        else if Instr(1, codec, "AVC") > 0
            if t.bits = 0 then t.bits = avcBits(ba, t.private.start, t.private.length)
            t.profile = avcProfile(ba, t.private.start, t.private.length)
        end if
    end if
    addProbeTrack(result, t)
end sub

' hvcC: general_profile_idc (2 = Main 10) and bitDepthLumaMinus8.
function hevcBits(ba as Object, start as Integer, length as Integer) as Integer
    if length < 23 or start + 22 >= ba.Count() then return 0
    depth = (ba[start + 17] and 7) + 8
    if depth >= 8 and depth <= 16 then return depth
    if (ba[start + 1] and 31) = 2 then return 10
    return 8
end function

function avcProfile(ba as Object, start as Integer, length as Integer) as String
    if length < 4 or start + 3 >= ba.Count() then return ""
    names = {"66": "Baseline", "77": "Main", "88": "Extended", "100": "High", "110": "High 10", "122": "High 4:2:2", "244": "High 4:4:4"}
    profile = names[ba[start + 1].ToStr()]
    if profile = invalid then profile = "Profile " + ba[start + 1].ToStr()
    level = ba[start + 3]
    return profile + "@L" + (Int(level / 10)).ToStr() + "." + (level mod 10).ToStr()
end function

function hevcProfile(ba as Object, start as Integer, length as Integer) as String
    if length < 13 or start + 12 >= ba.Count() then return ""
    idc = ba[start + 1] and 31
    names = {"1": "Main", "2": "Main 10", "3": "Main Still", "4": "Range Extensions"}
    profile = names[idc.ToStr()]
    if profile = invalid then profile = "Profile " + idc.ToStr()
    tier = "Main"
    if (ba[start + 1] and 32) <> 0 then tier = "High"
    level = ba[start + 12]
    levelText = (Int(level / 30)).ToStr()
    if (level mod 30) <> 0 then levelText = levelText + "." + Int((level mod 30) / 3).ToStr()
    return profile + "@L" + levelText + "@" + tier
end function

' Text that may hold UTF-8 (titles): keeps Latin letters the font can draw.
function utf8Text(ba as Object, i as Integer, n as Integer) as String
    bytes = CreateObject("roByteArray")
    for k = 0 to n - 1
        if i + k < ba.Count() then bytes.Push(ba[i + k])
    end for
    text = bytes.ToAsciiString()
    out = ""
    for k = 1 to Len(text)
        c = Mid(text, k, 1)
        if Asc(c) >= 32 and Asc(c) <= 591 then out = out + c
    end for
    return out.Trim()
end function

' x264 / x265 write their version and settings into the first frame.
function findEncoderNote(ba as Object, start as Integer) as String
    limit = ba.Count() - 12
    marks = ["x264 - core", "x265 (build", "Lavc", "HandBrake"]
    i = start
    while i < limit and i < start + 300000
        if ba[i] = 120 or ba[i] = 76 or ba[i] = 72 ' x, L, H
            for each mark in marks
                if bytesText(ba, i, Len(mark)) = mark
                    text = ""
                    k = i
                    while k < ba.Count() and k < i + 2400
                        c = ba[k]
                        if c = 0 or c = 128 then exit while
                        if c >= 32 and c < 127 then text = text + Chr(c)
                        k = k + 1
                    end while
                    return text
                end if
            end for
        end if
        i = i + 1
    end while
    return ""
end function

sub mkvChapters(ba as Object, start as Integer, stopAt as Integer, result as Object)
    if stopAt > ba.Count() then stopAt = ba.Count()
    j = start
    while j < stopAt - 2
        cid = ebmlVint(ba, j, true)
        csz = ebmlVint(ba, j + cid.length, false)
        if cid = invalid or csz = invalid then exit while
        c = j + cid.length + csz.length
        if cid.value = 17849 ' EditionEntry: walk into it
            j = c
        else if cid.value = 182 ' ChapterAtom
            chapter = {t: 0, name: ""}
            k = c
            while k < c + csz.value - 1 and k < ba.Count() - 2
                aid = ebmlVint(ba, k, true)
                asz = ebmlVint(ba, k + aid.length, false)
                if aid = invalid or asz = invalid then exit while
                a = k + aid.length + asz.length
                billion = 1000000000#
                if aid.value = 145 then chapter.t = beInt(ba, a, asz.value) / billion ' ChapterTimeStart
                if aid.value = 128 ' ChapterDisplay -> ChapString
                    d = a
                    while d < a + asz.value - 1
                        did = ebmlVint(ba, d, true)
                        dsz = ebmlVint(ba, d + did.length, false)
                        if did = invalid or dsz = invalid then exit while
                        dd = d + did.length + dsz.length
                        if did.value = 133 and chapter.name = "" then chapter.name = utf8Text(ba, dd, dsz.value)
                        d = dd + dsz.value
                    end while
                end if
                k = a + asz.value
            end while
            if result.chapters.Count() < 60 then result.chapters.Push(chapter)
            j = c + csz.value
        else
            j = c + csz.value
        end if
    end while
end sub

' avcC: profile 110 (High 10) or higher means 10-bit.
function avcBits(ba as Object, start as Integer, length as Integer) as Integer
    if length < 4 or start + 1 >= ba.Count() then return 0
    profile = ba[start + 1]
    if profile = 110 or profile = 122 or profile = 244 then return 10
    return 8
end function

sub mkvVideo(ba as Object, start as Integer, stopAt as Integer, t as Object)
    j = start
    while j < stopAt - 1 and j < ba.Count() - 1
        cid = ebmlVint(ba, j, true)
        csz = ebmlVint(ba, j + cid.length, false)
        if cid = invalid or csz = invalid then exit while
        c = j + cid.length + csz.length
        if cid.value = 176 then t.width = beInt(ba, c, csz.value) ' PixelWidth
        if cid.value = 186 then t.height = beInt(ba, c, csz.value) ' PixelHeight
        if cid.value = 21680 then t.displayWidth = beInt(ba, c, csz.value) ' DisplayWidth
        if cid.value = 21690 then t.displayHeight = beInt(ba, c, csz.value) ' DisplayHeight
        if cid.value = 154 then t.interlaced = beInt(ba, c, csz.value) ' FlagInterlaced
        if cid.value = 21936 ' Colour
            k = c
            while k < c + csz.value - 1
                gid = ebmlVint(ba, k, true)
                gsz = ebmlVint(ba, k + gid.length, false)
                if gid = invalid or gsz = invalid then exit while
                g = k + gid.length + gsz.length
                if gid.value = 21946 ' TransferCharacteristics
                    transfer = beInt(ba, g, gsz.value)
                    if transfer = 16 then t.hdr = "HDR10"
                    if transfer = 18 then t.hdr = "HLG"
                end if
                if gid.value = 21938 then t.bits = beInt(ba, g, gsz.value) ' BitsPerChannel
                if gid.value = 21947 then t.primaries = beInt(ba, g, gsz.value) ' Primaries
                if gid.value = 21945 then t.range = beInt(ba, g, gsz.value) ' Range
                if gid.value = 21948 then t.maxCll = beInt(ba, g, gsz.value) ' MaxCLL
                if gid.value = 21949 then t.maxFall = beInt(ba, g, gsz.value) ' MaxFALL
                k = g + gsz.value
            end while
        end if
        j = c + csz.value
    end while
end sub

sub mkvAudio(ba as Object, start as Integer, stopAt as Integer, t as Object)
    j = start
    while j < stopAt - 1 and j < ba.Count() - 1
        cid = ebmlVint(ba, j, true)
        csz = ebmlVint(ba, j + cid.length, false)
        if cid = invalid or csz = invalid then exit while
        c = j + cid.length + csz.length
        if cid.value = 181 then t.rate = beFloat(ba, c, csz.value) ' SamplingFrequency
        if cid.value = 159 then t.channels = beInt(ba, c, csz.value) ' Channels
        if cid.value = 25188 then t.bits = beInt(ba, c, csz.value) ' BitDepth
        j = c + csz.value
    end while
end sub

sub addProbeTrack(result as Object, t as Object)
    codec = t.codec
    if t.kind = 1 or Left(codec, 2) = "V_"
        result.video.Push({codec: videoCodecName(codec), codecId: codec, width: t.width, height: t.height, fps: t.fps, bits: t.bits, hdr: t.hdr, profile: t.profile, displayWidth: t.displayWidth, displayHeight: t.displayHeight, interlaced: t.interlaced, primaries: t.primaries, range: t.range, maxCll: t.maxCll, maxFall: t.maxFall, lang: t.lang, default: t.default})
    else if t.kind = 2 or Left(codec, 2) = "A_"
        result.audio.Push({codec: audioCodecName(codec), channels: t.channels, rate: t.rate, bits: t.bits, lang: t.lang, name: t.name, default: t.default, number: t.number})
    else if t.kind = 17 or Left(codec, 2) = "S_"
        text = Left(codec, 6) = "S_TEXT" or codec = "S_SSA" or codec = "S_ASS"
        result.subs.Push({codec: subCodecName(codec), lang: t.lang, name: t.name, forced: t.forced, text: text, default: t.default, number: t.number})
    end if
end sub

function videoCodecName(codec as String) as String
    c = UCase(codec)
    if Instr(1, c, "HEVC") > 0 or c = "HVC1" or c = "HEV1" then return "HEVC"
    if c = "DVH1" or c = "DVHE" then return "HEVC (Dolby Vision)"
    if Instr(1, c, "AVC") > 0 or c = "AVC1" or c = "AVC3" then return "H.264"
    if Instr(1, c, "AV1") > 0 or c = "AV01" then return "AV1"
    if Instr(1, c, "VP9") > 0 or c = "VP09" then return "VP9"
    if Instr(1, c, "VP8") > 0 then return "VP8"
    if Instr(1, c, "MPEG2") > 0 or c = "MP2V" then return "MPEG-2"
    if Instr(1, c, "MPEG4/ISO/ASP") > 0 or c = "MP4V" or c = "XVID" then return "MPEG-4 (XviD)"
    if Instr(1, c, "VC1") > 0 then return "VC-1"
    return codec
end function

function audioCodecName(codec as String) as String
    c = UCase(codec)
    if c = "A_EAC3" or c = "EC-3" then return "E-AC-3 (DD+)"
    if c = "A_AC3" or c = "AC-3" then return "AC-3 (DD)"
    if c = "A_TRUEHD" then return "TrueHD"
    if Instr(1, c, "A_DTS") > 0 or c = "DTSC" or c = "DTSH" or c = "DTSL" then return "DTS"
    if Instr(1, c, "AAC") > 0 or c = "MP4A" then return "AAC"
    if c = "A_FLAC" or c = "FLAC" then return "FLAC"
    if c = "A_OPUS" or c = "OPUS" then return "Opus"
    if c = "A_VORBIS" then return "Vorbis"
    if Instr(1, c, "A_MPEG/L3") > 0 or c = ".MP3" then return "MP3"
    if Instr(1, c, "A_PCM") > 0 or c = "LPCM" or c = "SOWT" or c = "TWOS" then return "PCM"
    if c = "ALAC" then return "ALAC"
    return codec
end function

function subCodecName(codec as String) as String
    c = UCase(codec)
    if c = "S_TEXT/UTF8" or c = "TX3G" then return "SRT"
    if c = "S_TEXT/ASS" or c = "S_TEXT/SSA" or c = "S_ASS" or c = "S_SSA" then return "ASS"
    if c = "S_TEXT/WEBVTT" or c = "WVTT" then return "WebVTT"
    if c = "S_HDMV/PGS" then return "PGS (picture)"
    if c = "S_VOBSUB" then return "VobSub (picture)"
    if c = "S_DVBSUB" then return "DVB (picture)"
    return codec
end function

' ---- MP4 / MOV / M4A ---------------------------------------------------------------

' Finds "moov" (in the head, or anywhere in a tail read) and reads it.
function probeMp4(ba as Object, tail as Boolean) as Object
    result = probeResult()
    result.container = "MP4"
    moov = -1
    if tail
        i = 4
        while i < ba.Count() - 8
            if ba[i] = 109 and ba[i + 1] = 111 and ba[i + 2] = 111 and ba[i + 3] = 118 ' "moov"
                moov = i - 4
                exit while
            end if
            i = i + 1
        end while
    else
        i = 0
        while i < ba.Count() - 8
            size = beInt(ba, i, 4)
            kind = fourcc(ba, i + 4)
            if kind = "" then exit while
            if kind = "ftyp"
                brand = fourcc(ba, i + 8)
                if brand = "qt  " then result.container = "MOV"
                if brand = "M4A " then result.container = "M4A"
                if brand = "M4V " then result.container = "M4V"
            end if
            if kind = "moov"
                moov = i
                exit while
            end if
            if size = 1 then size = beInt(ba, i + 8, 8)
            if size < 8 then exit while
            i = i + size
        end while
    end if
    if moov < 0
        result.needTail = true
        return result
    end if
    moovEnd = moov + beInt(ba, moov, 4)
    if moovEnd > ba.Count()
        moovEnd = ba.Count()
        result.partial = true
    end if
    mp4Children(ba, moov + 8, moovEnd, result, invalid)
    if not tail then result.general.encoder = findEncoderNote(ba, moovEnd)
    return result
end function

' Walks boxes; the ones that hold other boxes are entered.
sub mp4Children(ba as Object, start as Integer, stopAt as Integer, result as Object, track as Dynamic)
    i = start
    while i < stopAt - 8
        size = beInt(ba, i, 4)
        kind = fourcc(ba, i + 4)
        if kind = "" or size < 8 then exit while
        body = i + 8
        boxEnd = i + size
        if boxEnd > stopAt then boxEnd = stopAt
        if kind = "mvhd"
            if ba[body] = 1
                timescale = beInt(ba, body + 20, 4)
                duration = beInt(ba, body + 24, 8)
            else
                timescale = beInt(ba, body + 12, 4)
                duration = beInt(ba, body + 16, 4)
            end if
            if timescale > 0 then result.seconds = duration / timescale
        else if kind = "trak"
            t = {handler: "", codec: "", width: 0, height: 0, channels: 0, rate: 0, bits: 0, lang: "", hdr: "", fps: 0, timescale: 0, samples: 0, profile: ""}
            mp4Children(ba, body, boxEnd, result, t)
            finishMp4Track(result, t)
        else if kind = "mdia" or kind = "minf" or kind = "stbl"
            mp4Children(ba, body, boxEnd, result, track)
        else if track <> invalid
            if kind = "mdhd"
                if ba[body] = 1
                    track.timescale = beInt(ba, body + 20, 4)
                    track.length = beInt(ba, body + 24, 8)
                    packed = beInt(ba, body + 32, 2)
                else
                    track.timescale = beInt(ba, body + 12, 4)
                    track.length = beInt(ba, body + 16, 4)
                    packed = beInt(ba, body + 20, 2)
                end if
                if packed > 0
                    track.lang = Chr(Int(packed / 1024) mod 32 + 96) + Chr(Int(packed / 32) mod 32 + 96) + Chr(packed mod 32 + 96)
                end if
            else if kind = "hdlr"
                track.handler = fourcc(ba, body + 8)
            else if kind = "stsd"
                entry = body + 8
                track.codec = fourcc(ba, entry + 4)
                if track.handler = "vide"
                    track.width = beInt(ba, entry + 32, 2)
                    track.height = beInt(ba, entry + 34, 2)
                    ' Dolby Vision and HDR markers inside the sample entry.
                    k = entry + 86
                    entryEnd = entry + beInt(ba, entry, 4)
                    while k < entryEnd - 8 and k < ba.Count() - 12
                        sub4 = fourcc(ba, k + 4)
                        subSize = beInt(ba, k, 4)
                        if sub4 = "dvcC" or sub4 = "dvvC" then track.hdr = "Dolby Vision"
                        if sub4 = "hvcC"
                            track.bits = hevcBits(ba, k + 8, subSize - 8)
                            track.profile = hevcProfile(ba, k + 8, subSize - 8)
                        end if
                        if sub4 = "avcC"
                            track.bits = avcBits(ba, k + 8, subSize - 8)
                            track.profile = avcProfile(ba, k + 8, subSize - 8)
                        end if
                        if sub4 = "colr" and fourcc(ba, k + 8) = "nclx"
                            transfer = beInt(ba, k + 14, 2)
                            if transfer = 16 and track.hdr = "" then track.hdr = "HDR10"
                            if transfer = 18 and track.hdr = "" then track.hdr = "HLG"
                        end if
                        if subSize < 8 then exit while
                        k = k + subSize
                    end while
                else if track.handler = "soun"
                    track.channels = beInt(ba, entry + 24, 2)
                    track.bits = beInt(ba, entry + 26, 2)
                    track.rate = beInt(ba, entry + 32, 2)
                end if
            else if kind = "stsz"
                track.samples = beInt(ba, body + 8, 4)
            end if
        end if
        i = i + size
    end while
end sub

sub finishMp4Track(result as Object, t as Object)
    if t.handler = "vide"
        fps = 0
        if t.length <> invalid and t.length > 0 and t.samples > 0 and t.timescale > 0 then fps = Int(t.samples / (t.length / t.timescale) * 1000 + 0.5) / 1000
        profile = ""
        if t.profile <> invalid then profile = t.profile
        result.video.Push({codec: videoCodecName(t.codec), codecId: t.codec, width: t.width, height: t.height, fps: fps, bits: t.bits, hdr: t.hdr, profile: profile, displayWidth: 0, displayHeight: 0, interlaced: 0, primaries: 0, range: 0, maxCll: 0, maxFall: 0, lang: t.lang, default: true})
    else if t.handler = "soun"
        result.audio.Push({codec: audioCodecName(t.codec), channels: t.channels, rate: t.rate, bits: t.bits, lang: t.lang, name: "", default: result.audio.Count() = 0})
    else if t.handler = "subt" or t.handler = "text" or t.handler = "sbtl"
        result.subs.Push({codec: subCodecName(t.codec), lang: t.lang, name: "", forced: false, text: true, default: false})
    end if
end sub

' ---- Music files ---------------------------------------------------------------------

function probeFlac(ba as Object) as Object
    result = probeResult()
    result.container = "FLAC"
    i = 0
    if bytesText(ba, 0, 3) = "ID3" then i = 10 + id3Size(ba)
    if bytesText(ba, i, 4) <> "fLaC" then return result
    s = i + 8
    rate = ba[s + 10] * 4096 + ba[s + 11] * 16 + Int(ba[s + 12] / 16)
    channels = Int(ba[s + 12] / 2) mod 8 + 1
    bits = (ba[s + 12] mod 2) * 16 + Int(ba[s + 13] / 16) + 1
    wrap = 4294967296#
    samples = (ba[s + 13] mod 16) * wrap + beInt(ba, s + 14, 4)
    if rate > 0 then result.seconds = samples / rate
    result.audio.Push({codec: "FLAC", channels: channels, rate: rate, bits: bits, lang: "", name: "", default: true})
    return result
end function

function probeWav(ba as Object) as Object
    result = probeResult()
    result.container = "WAV"
    i = 12
    byteRate = 0
    while i < ba.Count() - 8
        chunk = fourcc(ba, i)
        size = leInt(ba, i + 4, 4)
        if chunk = "fmt "
            format = leInt(ba, i + 8, 2)
            channels = leInt(ba, i + 10, 2)
            rate = leInt(ba, i + 12, 4)
            byteRate = leInt(ba, i + 16, 4)
            bits = leInt(ba, i + 22, 2)
            codec = "PCM"
            if format = 3 then codec = "PCM (float)"
            result.audio.Push({codec: codec, channels: channels, rate: rate, bits: bits, lang: "", name: "", default: true})
        else if chunk = "data"
            if byteRate > 0 then result.seconds = size / byteRate
            exit while
        else if chunk = ""
            exit while
        end if
        i = i + 8 + size + (size mod 2)
    end while
    return result
end function

function probeAiff(ba as Object) as Object
    result = probeResult()
    result.container = "AIFF"
    i = 12
    while i < ba.Count() - 8
        chunk = fourcc(ba, i)
        size = beInt(ba, i + 4, 4)
        if chunk = "COMM"
            channels = beInt(ba, i + 8, 2)
            frames = beInt(ba, i + 10, 4)
            bits = beInt(ba, i + 14, 2)
            ' 80-bit extended sample rate.
            exponent = beInt(ba, i + 16, 2) mod 32768
            mantissa = beInt(ba, i + 18, 8)
            two = 2#
            rate = Int(mantissa * (two ^ (exponent - 16383 - 63)) + 0.5)
            if rate > 0 then result.seconds = frames / rate
            result.audio.Push({codec: "PCM", channels: channels, rate: rate, bits: bits, lang: "", name: "", default: true})
            exit while
        else if chunk = ""
            exit while
        end if
        i = i + 8 + size + (size mod 2)
    end while
    return result
end function

function id3Size(ba as Object) as Integer
    return ((ba[6] mod 128) * 2097152) + ((ba[7] mod 128) * 16384) + ((ba[8] mod 128) * 128) + (ba[9] mod 128)
end function

function probeMp3(ba as Object, totalMb as Double) as Object
    result = probeResult()
    result.container = "MP3"
    i = 0
    if bytesText(ba, 0, 3) = "ID3" then i = 10 + id3Size(ba)
    limit = ba.Count() - 4
    while i < limit
        if ba[i] = 255 and ba[i + 1] >= 224 then exit while
        i = i + 1
    end while
    if i >= limit
        result.partial = true
        return result
    end if
    versionBits = Int(ba[i + 1] / 8) mod 4
    bitrateIndex = Int(ba[i + 2] / 16)
    rateIndex = Int(ba[i + 2] / 4) mod 4
    mode = Int(ba[i + 3] / 64)
    mpeg1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
    mpeg2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]
    rates = [44100, 48000, 32000, 0]
    kbps = mpeg1[bitrateIndex]
    rate = rates[rateIndex]
    if versionBits <> 3
        kbps = mpeg2[bitrateIndex]
        rate = rate / 2
    end if
    channels = 2
    if mode = 3 then channels = 1
    ' A Xing / VBRI header means variable bitrate (Info is a CBR marker).
    vbr = false
    frames = 0#
    for k = i + 4 to i + 40
        if k < limit
            tag = fourcc(ba, k)
            if tag = "Xing" or tag = "VBRI" then vbr = true
            ' Frame count: Xing / Info when flag 1 is set, VBRI at offset 14.
            if (tag = "Xing" or tag = "Info") and k + 12 < ba.Count()
                if (ba[k + 7] and 1) = 1 then frames = ((ba[k + 8] * 256 + ba[k + 9]) * 256 + ba[k + 10]) * 256# + ba[k + 11]
                exit for
            end if
            if tag = "VBRI" and k + 18 < ba.Count()
                frames = ((ba[k + 14] * 256 + ba[k + 15]) * 256 + ba[k + 16]) * 256# + ba[k + 17]
                exit for
            end if
        end if
    end for
    result.audio.Push({codec: "MP3", channels: channels, rate: rate, bits: 0, lang: "", name: "", default: true, kbps: kbps, vbr: vbr})
    if frames > 0 and rate > 0
        samplesPerFrame = 1152
        if versionBits <> 3 then samplesPerFrame = 576
        result.seconds = frames * samplesPerFrame / rate
    else if totalMb > 0 and kbps > 0 and not vbr
        result.seconds = totalMb * 8388.608 / kbps
    end if
    return result
end function
