sub init()
    m.body = m.top.FindNode("body")
    m.pad = 0
    m.glow = m.top.FindNode("glow")
    m.bezel = m.top.FindNode("bezel")
    m.art = m.top.FindNode("art")
    m.track = m.top.FindNode("track")
    m.bar = m.top.FindNode("bar")
    m.badgeBack = m.top.FindNode("badgeBack")
    m.badge = m.top.FindNode("badge")
    m.titleLabel = m.top.FindNode("title")
    m.subtitleLabel = m.top.FindNode("subtitle")
    m.titleLabel.font = makeFont("bold", 22)
    m.subtitleLabel.font = makeFont("regular", 19)
    m.badge.font = makeFont("bold", 16)
    m.tagRow = m.top.FindNode("tagRow")
    m.tagTop = m.top.FindNode("tagTop")
    m.tagFont = makeFont("bold", 15)
    m.tagText = ""
    m.progress = 0
end sub

sub layout()
    content = m.top.itemContent
    m.pad = 0
    if content <> invalid
        if content.pad <> invalid then m.pad = content.pad
    end if
    m.body.translation = [m.pad, m.pad]
    w = m.top.width - m.pad * 2
    h = m.top.height - m.pad * 2
    m.w = w
    if w <= 0 or h <= 0 then return
    textArea = 62
    content = m.top.itemContent
    if content <> invalid
        if content.kind = "cast" then textArea = 70
    end if
    artH = h - textArea
    m.artH = artH
    m.art.width = w
    m.art.height = artH
    m.art.loadWidth = w
    m.art.loadHeight = artH
    m.bezel.translation = [-7, -7]
    m.bezel.width = w + 14
    m.bezel.height = artH + 14
    m.glow.translation = [-42, -42]
    m.glow.width = w + 84
    m.glow.height = artH + 84
    m.track.translation = [10, artH - 18]
    m.track.width = w - 20
    m.track.height = 10
    m.bar.translation = [10, artH - 18]
    m.bar.height = 10
    m.tagRow.translation = [8, artH - 36]
    m.tagTop.translation = [8, 10]
    m.titleLabel.translation = [2, artH + 14]
    m.titleLabel.width = w - 4
    m.subtitleLabel.translation = [2, artH + 42]
    m.subtitleLabel.width = w - 4
    if m.badgeW = invalid then m.badgeW = 54
    m.badgeBack.translation = [w - m.badgeW - 10, 10]
    m.badgeBack.width = m.badgeW
    m.badgeBack.height = 30
    m.badge.translation = [w - m.badgeW - 10, 10]
    m.badge.width = m.badgeW
    m.badge.height = 30
    showProgress()
end sub

sub onContent()
    content = m.top.itemContent
    if content = invalid then return
    kind = content.kind
    if kind = invalid then kind = "movie"
    m.titleLabel.text = content.title
    m.subtitleLabel.text = content.ShortDescriptionLine1
    setArt(m.art, content.HDPosterUrl, fallbackArt(kind))
    m.progress = 0
    if content.progress <> invalid then m.progress = content.progress
    badge = ""
    if content.badge <> invalid then badge = content.badge
    tags = ""
    if content.tags <> invalid then tags = content.tags
    if tags <> m.tagText
        m.tagText = tags
        drawTags(tags)
    end if
    m.badge.text = badge
    m.badgeW = 54
    if Len(badge) > 3 then m.badgeW = 92
    if Len(badge) > 6 then m.badgeW = 118
    m.badge.visible = badge <> ""
    m.badgeBack.visible = badge <> ""
    layout()
    placePills()
end sub

' tags: "4K|HDR|HEVC|REMUX"
' Picture tags (resolution, HDR / DV, hard-coded subs) go along the top; the
' rest (codec, REMUX) along the bottom.
sub drawTags(tags as String)
    m.tagRow.RemoveChildrenIndex(m.tagRow.GetChildCount(), 0)
    m.tagTop.RemoveChildrenIndex(m.tagTop.GetChildCount(), 0)
    m.topPills = []
    m.bottomPills = []
    if tags = "" then return
    for each tag in tags.Split("|")
        top = tag = "4K" or tag = "8K" or tag = "2K" or (Right(tag, 1) = "p" and Val(tag) > 0) or tag = "SD" or tag = "HDR" or tag = "DV" or tag = "10-BIT" or tag = "HC SUBS"
        color = "0xC3CDDEFF"
        if tag = "REMUX" or tag = "HC SUBS" then color = "0xFFC857FF"
        if tag = "Web-DL" or tag = "WebRip" or tag = "Blu-Ray" or tag = "HDTV" or tag = "DVD" or tag = "DVDRip" or tag = "HDRip" or tag = "VHSRip" then color = "0x8FB8FFFF"
        if tag = "DCP" then color = "0x39FF88FF"
        if tag = "CAM" or tag = "TS" or tag = "Screener" or tag = "Workprint" then color = "0xFF5C7AFF"
        if tag = "4K" or tag = "2160p" or tag = "8K" then color = "0x39FF88FF"
        if tag = "HDR" or tag = "DV" or tag = "10-BIT" then color = "0x28DCFFFF"
        pill = CreateObject("roSGNode", "Group")
        label = CreateObject("roSGNode", "Label")
        label.font = m.tagFont
        label.text = tag
        label.color = color
        label.horizAlign = "center"
        label.vertAlign = "center"
        width = label.BoundingRect().width + 18
        back = pill.CreateChild("Poster")
        back.uri = "pkg:/images/pill.9.png"
        back.width = width
        back.height = 26
        back.opacity = 0.92
        label.width = width
        label.height = 26
        pill.AppendChild(label)
        if top
            m.tagTop.AppendChild(pill)
            m.topPills.Push({node: pill, width: width})
        else
            m.tagRow.AppendChild(pill)
            m.bottomPills.Push({node: pill, width: width})
        end if
    end for
    placePills()
end sub

' One badge sits in the left corner, two take both corners, more spread out
' evenly; a row never runs past the poster (what doesn't fit is left off).
sub placePills()
    if m.w = invalid or m.topPills = invalid then return
    inner = m.w - 16
    topRoom = inner
    if m.badge.visible then topRoom = inner - m.badgeW - 6
    spread(m.topPills, topRoom, m.badge.visible)
    spread(m.bottomPills, inner, false)
end sub

sub spread(pills as Object, room as Integer, leftOnly as Boolean)
    shown = []
    used = 0
    for each p in pills
        gap = 0
        if shown.Count() > 0 then gap = 4
        if used + gap + p.width <= room
            shown.Push(p)
            used = used + gap + p.width
            p.node.visible = true
        else
            p.node.visible = false
        end if
    end for
    if shown.Count() = 0 then return
    if shown.Count() = 1 or leftOnly
        x = 0
        for each p in shown
            p.node.translation = [x, 0]
            x = x + p.width + 6
        end for
        return
    end if
    total = 0
    for each p in shown
        total = total + p.width
    end for
    gap = (room - total) / (shown.Count() - 1)
    x = 0.0
    for each p in shown
        p.node.translation = [Int(x), 0]
        x = x + p.width + gap
    end for
end sub

sub showProgress()
    if m.artH = invalid then return
    visible = m.progress > 0.01 and m.progress < 0.97
    m.track.visible = visible
    m.bar.visible = visible
    if visible then m.bar.width = (m.w - 20) * m.progress
end sub

sub onRowFocus()
    m.isRow = true
    onFocus()
end sub

sub onFocus()
    p = m.top.focusPercent
    if m.isRow = true
        active = m.top.rowListHasFocus
        p = p * m.top.rowFocusPercent
    else
        active = m.top.gridHasFocus or m.top.listHasFocus
    end if
    if not active then p = 0
    m.glow.opacity = p
    if p > 0.5
        m.titleLabel.color = "0xFFFFFFFF"
        m.subtitleLabel.color = "0x39FF88FF"
    else
        m.titleLabel.color = "0xDCE4F2FF"
        m.subtitleLabel.color = "0x7F8CA6FF"
    end if
    if m.artH = invalid then return
    s = 1 + 0.05 * p
    m.top.scaleRotateCenter = [m.top.width / 2, m.pad + m.artH / 2]
    m.top.scale = [s, s]
end sub
