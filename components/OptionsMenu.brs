sub init()
    buildHintRow(m.top.FindNode("footer"), [{icons: ["ok"], text: "CHOOSE"}, {icons: ["back"], text: "CLOSE"}])
    m.titleLabel = m.top.FindNode("titleLabel")
    m.subtitleLabel = m.top.FindNode("subtitleLabel")
    m.list = m.top.FindNode("list")
    m.titleLabel.font = makeFont("bold", 36)
    m.subtitleLabel.font = makeFont("regular", 22)
    m.list.ObserveField("itemSelected", "onSelected")
    m.top.ObserveField("focusedChild", "onFocusChange")
end sub

sub onTitle()
    m.titleLabel.text = m.top.title
    m.subtitleLabel.text = m.top.subtitle
    if m.top.subtitle = "" then m.list.translation = [1146, 156] else m.list.translation = [1146, 196]
end sub

' options: [{id, label, detail, value, checked, art, kind}]
sub onOptions()
    root = CreateObject("roSGNode", "ContentNode")
    for each option in m.top.options
        node = root.CreateChild("ContentNode")
        node.AddFields({kind: "", art: false, iconColor: "", playing: false, dim: false, number: ""})
        node.title = option.label
        if option.detail <> invalid then node.ShortDescriptionLine1 = option.detail
        value = ""
        if option.value <> invalid then value = option.value
        if option.checked = true then value = ("CURRENT  " + value)
        node.ShortDescriptionLine2 = value.Trim()
        if option.art <> invalid and option.art <> ""
            node.HDPosterUrl = option.art
            node.art = true
            node.kind = option.kind
        else if option.icon <> invalid
            node.HDPosterUrl = option.icon
            node.iconColor = "0x39FF88FF"
        end if
        node.dim = option.dim = true
    end for
    rowHeight = 120
    for each option in m.top.options
        if option.art <> invalid and option.art <> "" then rowHeight = 160
    end for
    m.list.itemSize = [738, rowHeight]
    ' Options with a two-line description get taller rows.
    heights = rowHeightsFor(root, 738, rowHeight)
    tallest = rowHeight
    for each h in heights
        if h > tallest then tallest = h
    end for
    m.list.numRows = Int(800 / tallest)
    m.list.content = root
    m.list.rowHeights = heights
    selected = 0
    i = 0
    for each option in m.top.options
        if option.checked = true then selected = i
        i = i + 1
    end for
    if root.GetChildCount() > 0 then m.list.jumpToItem = selected
end sub

sub onFocusChange()
    if m.top.HasFocus() then m.list.SetFocus(true)
end sub

sub onSelected()
    index = m.list.itemSelected
    if index >= 0 and index < m.top.options.Count() then m.top.chosen = m.top.options[index]
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "back" or key = "options" or key = "left"
        m.top.closed = true
        return true
    end if
    return false
end function
