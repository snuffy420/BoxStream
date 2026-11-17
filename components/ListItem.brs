' Rows keep a margin around their strip so the list's own edges never
' crop the focus glow (sizes given to lists include it).
sub init()
    m.body = m.top.FindNode("body")
    m.body.translation = [24, 14]
    m.strip = m.top.FindNode("strip")
    m.stripOn = m.top.FindNode("stripOn")
    m.glow = m.top.FindNode("glow")
    m.icon = m.top.FindNode("icon")
    m.number = m.top.FindNode("number")
    m.title = m.top.FindNode("title")
    m.detail = m.top.FindNode("detail")
    m.value = m.top.FindNode("value")
    m.playing = m.top.FindNode("playing")
    m.title.font = makeFont("bold", 26)
    m.detail.font = makeFont("regular", 20)
    m.value.font = makeFont("regular", 22)
    m.number.font = makeFont("bold", 22)
end sub

sub layout()
    w = m.top.width - 48
    h = m.top.height - 28 + 8
    if w <= 0 or h <= 0 then return
    content = m.top.itemContent
    m.strip.width = w
    m.strip.height = h - 8
    m.stripOn.width = w
    m.stripOn.height = h - 8
    m.glow.translation = [-40, -40]
    m.glow.width = w + 80
    m.glow.height = h - 8 + 80
    x = 34
    hasNumber = false
    hasIcon = false
    art = false
    if content <> invalid
        hasNumber = content.number <> invalid and content.number <> ""
        hasIcon = content.HDPosterUrl <> invalid and content.HDPosterUrl <> ""
        art = content.art = true
    end if
    m.number.visible = hasNumber
    if hasNumber
        m.number.translation = [x, 0]
        m.number.width = 44
        m.number.height = h - 8
        x = x + 62
    end if
    m.icon.visible = hasIcon
    if hasIcon
        size = h - 28
        if art
            m.icon.translation = [12, 6]
            m.icon.width = Int((h - 20) * 0.68)
            m.icon.height = h - 20
            m.icon.loadDisplayMode = "scaleToZoom"
            x = 12 + m.icon.width + 20
        else
            m.icon.translation = [x, (h - 8 - 34) / 2]
            m.icon.width = 34
            m.icon.height = 34
            x = x + 54
        end if
    end if
    ' The value on the right takes only the room its text needs.
    valueWidth = 0
    if m.value.text <> ""
        m.value.width = 0
        valueWidth = Int(m.value.BoundingRect().width) + 8
        if valueWidth > 360 then valueWidth = 360
        if valueWidth < 40 then valueWidth = 40
    end if
    m.value.translation = [w - valueWidth - 26, 0]
    m.value.width = valueWidth
    m.value.height = h - 8
    m.playing.translation = [w - 56, (h - 8 - 26) / 2]
    titleWidth = w - x - valueWidth - 40
    ' A long title gets a smaller size before it would be cut short.
    m.title.width = 0
    for each size in [26, 23, 20]
        m.title.font = makeFont("bold", size)
        if m.title.BoundingRect().width <= titleWidth then exit for
    end for
    if m.detail.text = ""
        m.title.translation = [x, 0]
        m.title.height = h - 8
        m.title.width = titleWidth
    else
        ' A detail too long for one line wraps onto a second, in smaller type
        ' (title too) so the block stays inside the strip, clear of the focus
        ' glow on its edges. Rows too short for that keep one line.
        inner = h - 8
        m.detail.font = makeFont("regular", 20)
        m.detail.wrap = false
        m.detail.maxLines = 1
        m.detail.width = 0
        titleH = 34
        detailH = 26
        if m.detail.BoundingRect().width > titleWidth and inner >= 124
            ' A row made taller for it (rowHeightsFor): two lines at full size.
            m.detail.wrap = true
            m.detail.maxLines = 2
            m.detail.width = titleWidth
            detailH = Int(m.detail.BoundingRect().height)
            if detailH < 26 then detailH = 26
        else if m.detail.BoundingRect().width > titleWidth and inner >= 88
            m.detail.font = makeFont("regular", 17)
            m.detail.wrap = true
            m.detail.maxLines = 2
            m.detail.width = titleWidth
            detailH = Int(m.detail.BoundingRect().height)
            if detailH < 22 then detailH = 22
            m.title.width = 0
            if m.title.BoundingRect().width > titleWidth or m.title.font.size > 23 then m.title.font = makeFont("bold", 22)
            titleH = 30
        end if
        m.detail.width = titleWidth
        top = Int((inner - (titleH + 2 + detailH)) / 2)
        if top < 6
            ' Still too tall: one line after all.
            m.detail.font = makeFont("regular", 17)
            m.detail.wrap = false
            m.detail.maxLines = 1
            detailH = 22
            top = Int((inner - (titleH + 2 + detailH)) / 2)
        end if
        m.title.translation = [x, top]
        m.title.height = titleH
        m.title.width = titleWidth
        m.detail.translation = [x, top + titleH + 2]
    end if
end sub

sub onContent()
    content = m.top.itemContent
    if content = invalid then return
    m.title.text = content.title
    m.detail.text = content.ShortDescriptionLine1
    m.value.text = content.ShortDescriptionLine2
    number = ""
    if content.number <> invalid then number = content.number
    m.number.text = number
    if content.HDPosterUrl <> invalid and content.HDPosterUrl <> ""
        if content.art = true
            setArt(m.icon, content.HDPosterUrl, fallbackArt(content.kind))
            m.icon.blendColor = "0xFFFFFFFF"
        else
            m.icon.uri = content.HDPosterUrl
            m.icon.blendColor = content.iconColor
            if content.iconColor = invalid or content.iconColor = "" then m.icon.blendColor = "0x8391AAFF"
        end if
    end if
    m.playing.visible = content.playing = true
    if content.dim = true then m.title.color = "0x56627AFF" else m.title.color = "0xDCE4F2FF"
    layout()
end sub

sub onFocus()
    p = m.top.focusPercent
    if not (m.top.gridHasFocus or m.top.listHasFocus) then p = 0
    m.glow.opacity = p
    m.stripOn.opacity = p
    m.strip.opacity = 0.55 * (1 - p)
    content = m.top.itemContent
    dimmed = false
    if content <> invalid then dimmed = content.dim = true
    if p > 0.5
        m.title.color = "0xFFFFFFFF"
        m.value.color = "0x39FF88FF"
    else
        if dimmed then m.title.color = "0x56627AFF" else m.title.color = "0xDCE4F2FF"
        m.value.color = "0x8391AAFF"
    end if
end sub
