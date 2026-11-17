sub init()
    m.top.FindNode("body").translation = [36, 36]
    m.glow = m.top.FindNode("glow")
    m.bezel = m.top.FindNode("bezel")
    m.still = m.top.FindNode("still")
    m.track = m.top.FindNode("track")
    m.bar = m.top.FindNode("bar")
    m.check = m.top.FindNode("check")
    m.checkText = m.top.FindNode("checkText")
    m.title = m.top.FindNode("title")
    m.detail = m.top.FindNode("detail")
    m.overview = m.top.FindNode("overview")
    m.title.font = makeFont("bold", 24)
    m.detail.font = makeFont("regular", 19)
    m.overview.font = makeFont("regular", 19)
    m.checkText.font = makeFont("bold", 14)
    m.progress = 0
end sub

sub layout()
    w = m.top.width - 72
    h = m.top.height - 72
    m.w = w
    if w <= 0 or h <= 0 then return
    stillH = Int(w * 9 / 16)
    m.stillH = stillH
    m.still.width = w
    m.still.height = stillH
    m.still.loadWidth = w
    m.still.loadHeight = stillH
    m.bezel.translation = [-7, -7]
    m.bezel.width = w + 14
    m.bezel.height = stillH + 14
    m.glow.translation = [-42, -42]
    m.glow.width = w + 84
    m.glow.height = stillH + 84
    m.track.translation = [12, stillH - 18]
    m.track.width = w - 24
    m.track.height = 10
    m.bar.translation = [12, stillH - 18]
    m.bar.height = 10
    m.check.translation = [w - 112, 10]
    m.check.width = 102
    m.check.height = 28
    m.checkText.translation = [w - 112, 10]
    m.checkText.width = 102
    m.checkText.height = 28
    m.title.translation = [0, stillH + 14]
    m.title.width = w
    m.detail.translation = [0, stillH + 44]
    m.detail.width = w
    m.overview.translation = [0, stillH + 72]
    m.overview.width = w
    showProgress()
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.title.text = c.title
    m.detail.text = c.ShortDescriptionLine1
    m.overview.text = c.Description
    setArt(m.still, c.HDPosterUrl, "pkg:/images/thumb-episode.png")
    m.progress = 0
    if c.progress <> invalid then m.progress = c.progress
    watched = c.watched = true
    m.check.visible = watched
    m.checkText.visible = watched
    layout()
end sub

sub showProgress()
    if m.stillH = invalid then return
    visible = m.progress > 0.01 and m.progress < 0.97
    m.track.visible = visible
    m.bar.visible = visible
    if visible then m.bar.width = (m.w - 24) * m.progress
end sub

' Episodes sit in a RowList, which reports focus through rowListHasFocus.
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
        m.title.color = "0xFFFFFFFF"
        m.detail.color = "0x39FF88FF"
    else
        m.title.color = "0xDCE4F2FF"
        m.detail.color = "0x8391AAFF"
    end if
    if m.stillH = invalid then return
    s = 1 + 0.04 * p
    m.top.scaleRotateCenter = [m.top.width / 2, 36 + m.stillH / 2]
    m.top.scale = [s, s]
end sub
