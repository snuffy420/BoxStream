' Layout: rows of 13 units. Each key is {label, value, col, span}; value is
' text to type or an action (#shift #space #delete #clear #show #done).

sub init()
    buildHintRow(m.top.FindNode("footer"), [{icons: ["ok"], text: "TYPE"}, {icons: ["star"], text: "CAPS"}, {icons: ["replay"], text: "DELETE"}, {icons: ["playpause"], text: "DONE"}, {icons: ["back"], text: "CANCEL"}])
    m.titleLabel = m.top.FindNode("titleLabel")
    m.hintLabel = m.top.FindNode("hintLabel")
    m.valueLabel = m.top.FindNode("valueLabel")
    m.caret = m.top.FindNode("caret")
    m.keysGroup = m.top.FindNode("keys")
    m.keyGlow = m.top.FindNode("keyGlow")
    m.footer = m.top.FindNode("footer")
    m.titleLabel.font = makeFont("bold", 38)
    m.hintLabel.font = makeFont("regular", 22)
    m.valueLabel.font = makeFont("regular", 36)

    m.blink = m.top.FindNode("blink")
    m.blink.ObserveField("fire", "onBlink")
    m.shift = false
    m.capsLock = false
    m.reveal = false
    m.text = ""
    m.row = 0
    m.col = 0
    m.unitW = 88
    m.rowH = 78
    buildKeys()
end sub

sub onTitle()
    m.titleLabel.text = m.top.title
    m.hintLabel.text = m.top.hint
end sub

sub onValue()
    if m.top.value <> m.text
        m.text = m.top.value
        showText()
    end if
end sub

sub onOpen()
    if m.top.open
        m.shift = false
        m.capsLock = false
        m.reveal = false
        m.row = 0
        m.col = 0
        m.text = m.top.value
        buildKeys()
        showText()
        m.blink.control = "start"
    else
        m.blink.control = "stop"
    end if
end sub

sub onBlink()
    m.caret.visible = not m.caret.visible
end sub

sub buildKeys()
    if m.keysGroup = invalid then return
    m.rows = []
    if m.top.mode = "ip"
        ' Number pad for https://<numbers>.sslip.io (the dashes go in by themselves).
        row = []
        for i = 0 to 9
            ch = ((i + 1) mod 10).ToStr()
            row.Push({label: ch, value: ch, col: i, span: 1})
        end for
        row.Push({label: "-", value: "-", col: 10, span: 1})
        row.Push({label: "DELETE", value: "#delete", col: 11, span: 2})
        m.rows.Push(row)
        m.rows.Push([{label: "CLEAR", value: "#clear", col: 0, span: 3}, {label: "OTHER ADDRESS", value: "#other", col: 3, span: 5}, {label: "DONE", value: "#done", col: 8, span: 5}])
        drawKeys()
        return
    end if
    ' QWERTY, like a computer keyboard: numbers on top, letters below, with
    ' the symbols addresses and searches need at the ends of the rows.
    layout = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "_", "."]
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "/", ":", "@"]
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", "?", "=", "&", "%"]
        ["z", "x", "c", "v", "b", "n", "m", "'", "!", "#", "~", "+", "$"]
    ]
    for each keys in layout
        row = []
        for i = 0 to 12
            ch = keys[i]
            if m.shift or m.capsLock then ch = UCase(ch)
            row.Push({label: ch, value: ch, col: i, span: 1})
        end for
        m.rows.Push(row)
    end for
    ' The on-screen key capitalises the next letter; * on the remote locks capitals.
    shiftLabel = "abc"
    if m.shift then shiftLabel = "ABC"
    if m.capsLock then shiftLabel = "CAPS"
    if m.top.secure
        eye = "SHOW"
        if m.reveal then eye = "HIDE"
        m.rows.Push([{label: shiftLabel, value: "#shift", col: 0, span: 2}, {label: "SPACE", value: "#space", col: 2, span: 3}, {label: "DELETE", value: "#delete", col: 5, span: 2}, {label: "CLEAR", value: "#clear", col: 7, span: 2}, {label: eye, value: "#show", col: 9, span: 2}, {label: "DONE", value: "#done", col: 11, span: 2}])
    else
        m.rows.Push([{label: shiftLabel, value: "#shift", col: 0, span: 2}, {label: "SPACE", value: "#space", col: 2, span: 4}, {label: "DELETE", value: "#delete", col: 6, span: 2}, {label: "CLEAR", value: "#clear", col: 8, span: 2}, {label: "DONE", value: "#done", col: 10, span: 3}])
    end if
    if m.top.mode = "url"
        m.rows.Push([{label: "https://", value: "https://", col: 0, span: 3}, {label: "http://", value: "http://", col: 3, span: 3}, {label: ".sslip.io", value: ".sslip.io", col: 6, span: 4}, {label: "www.", value: "www.", col: 10, span: 3}])
    end if
    drawKeys()
end sub

sub drawKeys()
    m.keysGroup.RemoveChildrenIndex(m.keysGroup.GetChildCount(), 0)
    keyFont = makeFont("bold", 30)
    smallFont = makeFont("bold", 22)
    for r = 0 to m.rows.Count() - 1
        for each key in m.rows[r]
            x = key.col * m.unitW
            w = key.span * m.unitW - 10
            back = m.keysGroup.CreateChild("Poster")
            back.uri = "pkg:/images/button.9.png"
            if Left(key.value, 1) = "#" and Len(key.value) > 1 then back.uri = "pkg:/images/pill.9.png"
            back.translation = [x, r * m.rowH]
            back.width = w
            back.height = m.rowH - 10
            label = m.keysGroup.CreateChild("Label")
            label.text = key.label
            label.translation = [x, r * m.rowH]
            label.width = w
            label.height = m.rowH - 10
            label.horizAlign = "center"
            label.vertAlign = "center"
            label.color = "0xDCE4F2FF"
            if key.span > 1 then label.font = smallFont else label.font = keyFont
            if key.value = "#done" then label.color = "0x39FF88FF"
            key.label = label
        end for
    end for
    ' Panel height follows the number of rows.
    panelH = 282 + m.rows.Count() * m.rowH + 80
    m.top.FindNode("panel").height = panelH
    m.footer.translation = [250, panelH - 66]
    m.top.FindNode("panelGroup").translation = [330, Int((1080 - panelH) / 2)]
    if m.row >= m.rows.Count() then m.row = m.rows.Count() - 1
    moveFocus()
end sub

function keyAt(r as Integer, c as Integer) as Object
    for each key in m.rows[r]
        if c >= key.col and c < key.col + key.span then return key
    end for
    return m.rows[r][m.rows[r].Count() - 1]
end function

sub moveFocus()
    if m.rows = invalid then return
    key = keyAt(m.row, m.col)
    for each r in m.rows
        for each k in r
            if k.value = "#done" then k.label.color = "0x39FF88FF" else k.label.color = "0xDCE4F2FF"
        end for
    end for
    key.label.color = "0xFFFFFFFF"
    x = 62 + key.col * m.unitW
    y = 282 + m.row * m.rowH
    w = key.span * m.unitW - 10
    m.keyGlow.translation = [x - 40, y - 40]
    m.keyGlow.width = w + 80
    m.keyGlow.height = m.rowH - 10 + 80
end sub

sub showText()
    if m.top.mode = "ip"
        ' The whole address, with the typed numbers and the caret after them.
        m.valueLabel.text = "https://" + m.text
        typedW = m.valueLabel.BoundingRect().width
        m.valueLabel.text = "https://" + m.text + ".sslip.io"
        m.valueLabel.translation = [0, 0]
        m.caret.translation = [typedW + 4, 21]
        m.caret.visible = true
        return
    end if
    shown = m.text
    if m.top.secure and not m.reveal
        shown = ""
        for i = 1 to Len(m.text)
            shown = shown + "*"
        end for
    end if
    m.valueLabel.text = shown
    width = 0
    if shown <> "" then width = m.valueLabel.BoundingRect().width
    ' Keep the end of a long entry in view.
    shift = 0
    if width > 1060 then shift = width - 1060
    m.valueLabel.translation = [-shift, 0]
    m.caret.translation = [width - shift + 4, 21]
    m.caret.visible = true
end sub

sub typeText(value as String)
    if m.top.mode = "ip"
        for i = 1 to Len(value)
            typeIp(Mid(value, i, 1))
        end for
        showText()
        return
    end if
    m.text = m.text + value
    if m.shift and not m.capsLock and Len(value) = 1
        m.shift = false
        buildKeys()
    end if
    showText()
end sub

' One character on the number pad: digits, with a dash after each group of
' three (or typed for a shorter group); four groups at most.
sub typeIp(ch as String)
    if ch = "." then ch = "-"
    dashes = 0
    last = 0
    for i = 1 to Len(m.text)
        if Mid(m.text, i, 1) = "-"
            dashes = dashes + 1
            last = i
        end if
    end for
    group = Len(m.text) - last
    if ch = "-"
        if group > 0 and dashes < 3 then m.text = m.text + "-"
    else if Len(ch) = 1 and ch >= "0" and ch <= "9"
        if group < 3 then m.text = m.text + ch
        if group + 1 = 3 and dashes < 3 then m.text = m.text + "-"
    end if
end sub

function ipComplete() as Boolean
    return CreateObject("roRegex", "^\d{1,3}-\d{1,3}-\d{1,3}-\d{1,3}$", "").IsMatch(m.text)
end function

sub pressKey(key as Object)
    v = key.value
    if v = "#other"
        ' A different server: the full keyboard, starting from https://.
        m.top.mode = "url"
        m.text = "https://"
        m.row = 0
        m.col = 0
        showText()
    else if v = "#shift"
        ' With caps lock on, this key turns it off.
        if m.capsLock
            m.capsLock = false
            m.shift = false
        else
            m.shift = not m.shift
        end if
        buildKeys()
    else if v = "#space"
        typeText(" ")
    else if v = "#delete"
        if Len(m.text) > 0 then m.text = Left(m.text, Len(m.text) - 1)
        showText()
    else if v = "#clear"
        m.text = ""
        showText()
    else if v = "#show"
        m.reveal = not m.reveal
        buildKeys()
        showText()
    else if v = "#done"
        finish()
    else
        typeText(v)
    end if
end sub

sub finish()
    if m.top.mode = "ip"
        if m.text = ""
            m.top.done = ""
        else if ipComplete()
            m.top.done = "https://" + m.text + ".sslip.io"
        else
            m.hintLabel.text = "Type all four groups of numbers (e.g. 1-2-3-4)."
        end if
        return
    end if
    m.top.value = m.text
    m.top.done = m.text
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return true
    if Left(key, 4) = "Lit_"
        ch = Mid(key, 5)
        if ch = "%20" then ch = " "
        if Len(ch) > 1 then ch = (ch).DecodeUriComponent()
        typeText(ch)
        return true
    end if
    if key = "up"
        m.row = (m.row - 1 + m.rows.Count()) mod m.rows.Count()
    else if key = "down"
        m.row = (m.row + 1) mod m.rows.Count()
    else if key = "left"
        current = keyAt(m.row, m.col)
        m.col = current.col - 1
        if m.col < 0 then m.col = 12
        m.col = keyAt(m.row, m.col).col
    else if key = "right"
        current = keyAt(m.row, m.col)
        m.col = current.col + current.span
        if m.col > 12 then m.col = 0
    else if key = "OK"
        pressKey(keyAt(m.row, m.col))
    else if key = "replay" or key = "backspace"
        if Len(m.text) > 0 then m.text = Left(m.text, Len(m.text) - 1)
        showText()
    else if key = "play" or key = "enter"
        finish()
    else if key = "options"
        ' * on the remote: caps lock on or off (not on the number pad).
        if m.top.mode <> "ip"
            m.capsLock = not m.capsLock
            m.shift = false
            buildKeys()
        end if
    else if key = "back"
        m.top.cancel = true
    else if key = "rewind"
        m.col = 0
    else if key = "fastforward"
        m.col = 12
    end if
    moveFocus()
    return true
end function
