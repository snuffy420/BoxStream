' Shared by the scene and the item components: theme colors, fonts, art loading.

function theme() as Object
    return {
        text: "0xEEF4FFFF"
        soft: "0xC3CDDEFF"
        muted: "0x8391AAFF"
        dim: "0x56627AFF"
        green: "0x39FF88FF"
        blue: "0x2EA0FFFF"
        cyan: "0x28DCFFFF"
        ink: "0x06080DFF"
        red: "0xFF5C7AFF"
        amber: "0xFFC857FF"
    }
end function

' System font at any size. bold: "bold", "regular".
function makeFont(weight as String, size as Integer) as Object
    if m.fontCache = invalid then m.fontCache = {}
    name = weight + size.ToStr()
    if m.fontCache.DoesExist(name) then return m.fontCache[name]
    f = CreateObject("roSGNode", "Font")
    if weight = "bold" then f.uri = "font:BoldSystemFontFile" else f.uri = "font:SystemFontFile"
    f.size = size
    m.fontCache[name] = f
    return f
end function

' Loads art into a Poster. Art from the viewer's own server needs the login,
' so only those requests carry it; posters from metadata sites never do.
sub setArt(poster as Object, uri as String, fallback as String)
    poster.failedBitmapUri = fallback
    poster.loadingBitmapUri = fallback
    if uri = ""
        poster.uri = fallback
        return
    end if
    if poster.uri = uri then return
    g = m.global
    if g <> invalid
        auth = serverAuthFor(uri)
        if auth <> ""
            if true
                agent = CreateObject("roHttpAgent")
                agent.AddHeader("Authorization", auth)
                poster.SetHttpAgent(agent)
            end if
        end if
    end if
    poster.uri = uri
end sub

function fallbackArt(kind as String) as String
    if kind = "show" or kind = "episode" then return "pkg:/images/poster-tv.png"
    if kind = "album" or kind = "track" then return "pkg:/images/poster-music.png"
    if kind = "folder" then return "pkg:/images/poster-folder.png"
    return "pkg:/images/poster-movie.png"
end function

function clockText(seconds as Dynamic) as String
    if seconds = invalid then return "0:00"
    total = Int(seconds)
    if total < 0 then total = 0
    h = Int(total / 3600)
    mins = Int((total mod 3600) / 60)
    secs = total mod 60
    s = Right("0" + secs.ToStr(), 2)
    if h > 0 then return h.ToStr() + ":" + Right("0" + mins.ToStr(), 2) + ":" + s
    return mins.ToStr() + ":" + s
end function

function wallClock(offsetSeconds as Integer) as String
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    total = now.GetHours() * 3600 + now.GetMinutes() * 60 + offsetSeconds
    total = total mod 86400
    h = Int(total / 3600)
    mins = Int((total mod 3600) / 60)
    suffix = "AM"
    if h >= 12 then suffix = "PM"
    h = h mod 12
    if h = 0 then h = 12
    return h.ToStr() + ":" + Right("0" + mins.ToStr(), 2) + " " + suffix
end function

' The login for a URL on one of the viewer's sources ("" for anything else).
function serverAuthFor(url as String) as String
    auths = m.global.serverAuths
    if auths = invalid then return ""
    schemeEnd = Instr(1, url, "://")
    if schemeEnd = 0 then return ""
    slash = Instr(schemeEnd + 3, url, "/")
    origin = url
    if slash > 0 then origin = Left(url, slash - 1)
    auth = auths[LCase(origin)]
    if auth = invalid then return ""
    return auth
end function

' Footer hints drawn as Roku remote buttons (images/hints, tools/build_hint_icons.py).
' Row heights for a list of ListItem rows: a row whose detail won't fit on one
' line gets taller (room for a second line), so its glow is drawn round it.
' Mirrors ListItem's layout to know the text width each row has.
function rowHeightsFor(root as Object, itemWidth as Integer, baseH as Integer) as Object
    if m.measureLabel = invalid then m.measureLabel = CreateObject("roSGNode", "Label")
    probe = m.measureLabel
    heights = []
    for i = 0 to root.GetChildCount() - 1
        node = root.GetChild(i)
        height = baseH
        detail = node.ShortDescriptionLine1
        if detail <> invalid and detail <> ""
            w = itemWidth - 48
            x = 34
            if node.number <> invalid and node.number <> "" then x = x + 62
            if node.HDPosterUrl <> invalid and node.HDPosterUrl <> ""
                if node.art = true then x = 12 + Int((baseH - 40) * 0.68) + 20 else x = x + 54
            end if
            valueWidth = 0
            value = node.ShortDescriptionLine2
            if value <> invalid and value <> ""
                probe.font = makeFont("regular", 22)
                probe.text = value
                valueWidth = Int(probe.BoundingRect().width) + 8
                if valueWidth > 360 then valueWidth = 360
                if valueWidth < 40 then valueWidth = 40
            end if
            probe.font = makeFont("regular", 20)
            probe.text = detail
            if probe.BoundingRect().width > w - x - valueWidth - 40 then height = baseH + 40
        end if
        heights.Push(height)
    end for
    return heights
end function

sub buildHintRow(group as Object, items as Object)
    ' Remote-button pictures with a word each (purple pad and OK, dark round
    ' buttons), replacing what was there before.
    while group.GetChildCount() > 0
        group.RemoveChildIndex(0)
    end while
    widths = {"dpad-updown": 52, "dpad-leftright": 52, "dpad-all": 36, "dpad-up": 36, "dpad-down": 36, "dpad-left": 36, "dpad-right": 36, "ok": 44, "rewind": 36, "forward": 36, "playpause": 36, "back": 36, "star": 36, "replay": 36}
    x = 0
    for each item in items
        for each icon in item.icons
            poster = group.CreateChild("Poster")
            poster.uri = "pkg:/images/hints/" + icon + ".png"
            poster.width = widths[icon]
            poster.height = 34
            poster.translation = [x, 0]
            x = x + poster.width + 4
        end for
        label = group.CreateChild("Label")
        label.font = makeFont("bold", 20)
        label.color = "0xC3CDDEFF"
        label.height = 34
        label.vertAlign = "center"
        label.text = item.text
        label.translation = [x + 6, 0]
        width = label.BoundingRect().width
        if width <= 0 then width = Len(item.text) * 13
        x = x + 6 + width + 34
    end for
end sub
