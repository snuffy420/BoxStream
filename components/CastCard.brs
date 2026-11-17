sub init()
    m.top.FindNode("body").translation = [36, 36]
    m.glow = m.top.FindNode("glow")
    m.bezel = m.top.FindNode("bezel")
    m.initials = m.top.FindNode("initials")
    m.photo = m.top.FindNode("photo")
    m.name = m.top.FindNode("name")
    m.role = m.top.FindNode("role")
    m.name.font = makeFont("bold", 19)
    m.role.font = makeFont("regular", 17)
    m.initials.font = makeFont("bold", 44)
end sub

sub layout()
    w = m.top.width - 72
    h = m.top.height - 72
    if w <= 0 or h <= 0 then return
    photoH = h - 62
    m.photoH = photoH
    m.photo.width = w
    m.photo.height = photoH
    m.initials.width = w
    m.initials.height = photoH
    m.bezel.translation = [-6, -6]
    m.bezel.width = w + 12
    m.bezel.height = photoH + 12
    m.glow.translation = [-42, -42]
    m.glow.width = w + 84
    m.glow.height = photoH + 84
    m.name.translation = [0, photoH + 10]
    m.name.width = w
    m.role.translation = [0, photoH + 36]
    m.role.width = w
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.name.text = c.title
    m.role.text = c.ShortDescriptionLine1
    letters = ""
    for each word in c.title.Split(" ")
        if word <> "" and Len(letters) < 2 then letters = letters + UCase(Left(word, 1))
    end for
    m.initials.text = letters
    m.photo.uri = ""
    if c.HDPosterUrl <> invalid and c.HDPosterUrl <> "" then m.photo.uri = c.HDPosterUrl
    layout()
end sub

sub onRowFocus()
    m.isRow = true
    onFocus()
end sub

sub onFocus()
    p = m.top.focusPercent
    if m.isRow = true
        if not m.top.rowListHasFocus then p = 0
        p = p * m.top.rowFocusPercent
    else if not m.top.gridHasFocus
        p = 0
    end if
    m.glow.opacity = p
    if p > 0.5 then m.name.color = "0xFFFFFFFF" else m.name.color = "0xDCE4F2FF"
end sub
