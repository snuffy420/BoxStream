' Movies / TV Shows / Music grids, Search, and the raw Folders browser.

sub initBrowse()
    m.grid = m.top.FindNode("grid")
    m.gridTitle = m.top.FindNode("gridTitle")
    m.gridCount = m.top.FindNode("gridCount")
    m.sortLabel = m.top.FindNode("sortLabel")
    m.gridEmpty = m.top.FindNode("gridEmpty")
    m.gridTitle.font = makeFont("bold", 52)
    m.gridCount.font = makeFont("regular", 24)
    m.sortLabel.font = makeFont("bold", 20)
    m.gridEmpty.font = makeFont("regular", 28)
    m.grid.ObserveField("itemSelected", "onGridSelected")
    m.gridItems = []

    m.searchGrid = m.top.FindNode("searchGrid")
    m.searchText = m.top.FindNode("searchText")
    m.searchGlow = m.top.FindNode("searchGlow")
    m.searchEmpty = m.top.FindNode("searchEmpty")
    m.top.FindNode("searchHeading").font = makeFont("bold", 52)
    m.searchText.font = makeFont("regular", 32)
    m.searchEmpty.font = makeFont("regular", 28)
    m.searchGrid.ObserveField("itemSelected", "onSearchSelected")
    m.searchGrid.ObserveField("itemFocused", "onSearchFocused")
    m.searchQuery = ""
    m.searchItems = []

    m.folderList = m.top.FindNode("folderList")
    m.foldersPath = m.top.FindNode("foldersPath")
    m.foldersEmpty = m.top.FindNode("foldersEmpty")
    m.top.FindNode("foldersTitle").font = makeFont("bold", 52)
    m.foldersPath.font = makeFont("regular", 24)
    m.foldersEmpty.font = makeFont("regular", 28)
    m.folderList.ObserveField("itemSelected", "onFolderSelected")
    m.folderList.ObserveField("itemFocused", "onFolderFocused")
    m.folderStack = []
    m.folderEntries = []
end sub

' ---- Grids -------------------------------------------------------------------

sub showGrid(kind as String)
    forgetCards()
    m.gridKind = kind
    titles = {movies: "Movies", shows: "TV Shows", music: "Music"}
    m.gridTitle.text = titles[kind]
    source = libraryList(kind)
    if m.gridGroup <> invalid and m.gridGroup <> "" and kind <> "music"
        filtered = []
        for each item in source
            g = item.group
            if g = invalid then g = ""
            if g = m.gridGroup or (m.gridGroup = "-" and g = "") then filtered.Push(item)
        end for
        source = filtered
    end if
    list = sortedList(source, m.settings.sort)
    m.gridItems = list
    nouns = {movies: " movies", shows: " shows", music: " albums"}
    m.gridCount.text = list.Count().ToStr() + nouns[kind]
    if kind = "music" and m.settings.musicView = "singles" then m.gridCount.text = list.Count().ToStr() + " singles & mixes"
    if m.gridGroup <> invalid and m.gridGroup <> "" and kind <> "music"
        groupName = m.gridGroup
        if groupName = "-" then groupName = "none"
        m.gridCount.text = m.gridCount.text + "   ·   Group: " + groupName
    end if
    sortNames = {title: "Title A–Z", added: "Recently added", year: "Newest first", rating: "Top rated"}
    m.sortLabel.text = "SORT: " + UCase(sortNames[m.settings.sort]) + "      *"
    m.cardPad = 44
    if kind = "music"
        m.grid.itemSize = [270 + 88, 332 + 88]
        m.grid.numColumns = 5
    else
        m.grid.itemSize = [210 + 88, 377 + 88]
        m.grid.numColumns = 6
    end if
    m.grid.itemSpacing = [0, 0]
    root = CreateObject("roSGNode", "ContentNode")
    for each item in list
        makeCard(root, item)
    end for
    m.grid.content = root
    m.gridEmpty.visible = list.Count() = 0
    if list.Count() = 0
        if m.library = invalid then m.gridEmpty.text = "Your library is loading..." else m.gridEmpty.text = "Nothing here yet. Box://Stream looks through every folder on your source; check Folders to see what it found."
    end if
end sub

function sortedList(list as Object, order as String) as Object
    wrapped = []
    for each item in list
        k = item.sortKey
        if order = "added"
            k = item.date
        else if order = "year"
            k = itemYear(item) + item.sortKey
        else if order = "rating"
            rating = 0
            meta = metaFor(item.key)
            if meta <> invalid
                if meta.rating <> invalid and meta.rating <> "" then rating = Val(meta.rating)
            end if
            k = Right("000" + Int(rating * 10).ToStr(), 3)
        end if
        wrapped.Push({k: k, item: item})
    end for
    if order = "title" then wrapped.SortBy("k") else wrapped.SortBy("k", "r")
    out = []
    for each w in wrapped
        out.Push(w.item)
    end for
    return out
end function

function focusGrid() as Boolean
    m.area = "content"
    if m.gridItems.Count() = 0 then return false
    ' Back from a details page: on the card that was opened.
    if m.gridReturn <> invalid
        for i = 0 to m.gridItems.Count() - 1
            if m.gridItems[i].key = m.gridReturn
                if m.grid.itemFocused <> i then m.grid.jumpToItem = i
                exit for
            end if
        end for
    end if
    m.grid.SetFocus(true)
    return true
end function

function gridKey(key as String) as Boolean
    if key = "options"
        current = m.settings.sort
        options = []
        for each o in [{id: "title", label: "Title A–Z"}, {id: "added", label: "Recently added"}, {id: "year", label: "Newest first"}, {id: "rating", label: "Top rated"}]
            o.checked = o.id = current
            options.Push(o)
        end for
        if m.gridKind = "music"
            view = m.settings.musicView
            if view = invalid then view = "all"
            for each o in [{id: "mv:all", label: "Show all music"}, {id: "mv:albums", label: "Show albums only"}, {id: "mv:singles", label: "Show singles & mixes", detail: "One-track releases and long DJ sets"}]
                o.checked = o.id = "mv:" + view
                options.Push(o)
            end for
        end if
        if m.gridKind <> "music"
            label = "By release group..."
            value = ""
            if m.gridGroup <> invalid and m.gridGroup <> "" then value = m.gridGroup
            options.Push({id: "groups", label: label, detail: "Show one group's releases (AOC, RAWR...)", value: value})
        end if
        openMenu("sort", "Sort", "", options)
        return true
    end if
    return false
end function

sub sortChosen(choice as Object)
    if Left(choice.id, 3) = "mv:"
        m.settings.musicView = Mid(choice.id, 4)
        saveSettings()
        showGrid(m.gridKind)
        m.grid.SetFocus(true)
        return
    end if
    if choice.id = "groups"
        openGroupMenu()
        return
    end if
    m.settings.sort = choice.id
    saveSettings()
    showGrid(m.gridKind)
    m.grid.SetFocus(true)
end sub

' Every release group in this grid, most titles first.
sub openGroupMenu()
    counts = {}
    for each item in libraryList(m.gridKind)
        g = item.group
        if g = invalid or g = "" then g = "(no group)"
        if not counts.DoesExist(g) then counts[g] = 0
        counts[g] = counts[g] + 1
    end for
    rows = []
    for each g in counts
        rows.Push({g: g, n: counts[g], k: Right("00000" + counts[g].ToStr(), 6) + LCase(g)})
    end for
    rows.SortBy("k", "r")
    options = [{id: "", label: "All groups", checked: m.gridGroup = invalid or m.gridGroup = ""}]
    for each r in rows
        noun = " titles"
        if r.n = 1 then noun = " title"
        id = r.g
        if r.g = "(no group)" then id = "-"
        options.Push({id: id, label: r.g, value: r.n.ToStr() + noun, checked: m.gridGroup = id})
    end for
    openMenu("groups", "Release groups", counts.Count().ToStr() + " groups in " + LCase(m.gridTitle.text), options)
end sub

sub groupChosen(choice as Object)
    m.gridGroup = choice.id
    showGrid(m.gridKind)
    focusGrid()
end sub

sub onGridSelected()
    index = m.grid.itemSelected
    if index >= 0 and index < m.gridItems.Count()
        m.gridOpened = m.gridItems[index].key
        openDetails(m.gridItems[index])
    end if
end sub

' ---- Search ------------------------------------------------------------------

sub refreshSearch()
    if m.searchQuery = "" then m.searchText.text = "Titles, actors, directors, artists..." else m.searchText.text = m.searchQuery
    if m.searchQuery = "" then m.searchText.color = "0x56627AFF" else m.searchText.color = "0xEEF4FFFF"
    runSearch()
end sub

sub runSearch()
    forgetCards()
    results = []
    query = LCase(m.searchQuery.Trim())
    if query <> "" and m.library <> invalid
        for each listName in ["movies", "shows", "albums"]
            for each item in m.library[listName]
                if searchMatches(item, query) then results.Push(item)
                if results.Count() >= 120 then exit for
            end for
        end for
    end if
    m.searchItems = results
    m.cardPad = 44
    root = CreateObject("roSGNode", "ContentNode")
    for each item in results
        makeCard(root, item)
    end for
    m.searchGrid.content = root
    m.searchGrid.visible = results.Count() > 0
    if query = ""
        m.searchEmpty.text = "Press OK to type. Search finds titles, actors, directors, artists and genres."
    else if results.Count() = 0
        m.searchEmpty.text = "Nothing matches " + Chr(34) + m.searchQuery + Chr(34) + "."
    else
        m.searchEmpty.text = ""
    end if
    m.searchEmpty.visible = results.Count() = 0
end sub

function searchMatches(item as Object, query as String) as Boolean
    if Instr(1, LCase(displayTitle(item)), query) > 0 then return true
    if Instr(1, LCase(item.title), query) > 0 then return true
    ' Punctuation and spacing don't matter: "dead end" finds "Dead-End Job".
    squeezed = squeeze(query)
    if squeezed <> ""
        if Instr(1, squeeze(displayTitle(item)), squeezed) > 0 then return true
        if Instr(1, squeeze(item.title), squeezed) > 0 then return true
    end if
    if item.artist <> invalid
        if Instr(1, LCase(item.artist), query) > 0 then return true
    end if
    meta = metaFor(item.key)
    if meta <> invalid
        if meta.cast <> invalid
            for each c in meta.cast
                if Instr(1, LCase(c.name), query) > 0 then return true
            end for
        end if
        for each fieldName in ["director", "writer", "genres", "network"]
            value = meta[fieldName]
            if value <> invalid
                if Instr(1, LCase(value), query) > 0 then return true
            end if
        end for
    end if
    return false
end function

function squeeze(text as String) as String
    if m.squeezeRx = invalid then m.squeezeRx = CreateObject("roRegex", "[^a-z0-9]+", "")
    return m.squeezeRx.ReplaceAll(LCase(text), "")
end function

function focusSearch() as Boolean
    m.area = "content"
    m.searchFocus = "field"
    m.searchGlow.opacity = 1
    m.keySink.SetFocus(true)
    return true
end function

function searchKey(key as String) as Boolean
    if m.searchFocus = "field"
        if key = "OK"
            openKeyboard("search", "Search", "Titles, actors, directors, artists or genres.", m.searchQuery, false, "text")
            return true
        else if key = "down" and m.searchItems.Count() > 0
            m.searchFocus = "grid"
            m.searchGlow.opacity = 0
            m.searchGrid.SetFocus(true)
            return true
        else if key = "up" or key = "back"
            m.searchGlow.opacity = 0
            return false
        end if
        return true
    end if
    if key = "up" or key = "back"
        focusSearch()
        return true
    end if
    return false
end function

sub searchTyped(text as String)
    m.searchQuery = text
    refreshSearch()
    if m.searchItems.Count() > 0
        m.searchFocus = "grid"
        m.searchGlow.opacity = 0
        m.searchGrid.SetFocus(true)
    end if
end sub

sub onSearchSelected()
    index = m.searchGrid.itemSelected
    if index >= 0 and index < m.searchItems.Count() then openDetails(m.searchItems[index])
end sub

' ---- Folders -----------------------------------------------------------------

sub openFolders()
    root = activeSource().url
    if root <> "" and Right(root, 1) <> "/" then root = root + "/"
    if root = ""
        m.folderList.content = CreateObject("roSGNode", "ContentNode")
        m.foldersPath.text = ""
        m.foldersEmpty.text = "Add a source in Settings to browse its folders."
        m.foldersEmpty.visible = true
        return
    end if
    if m.folderStack.Count() = 0 then m.folderStack.Push(root)
    requestFolder()
end sub

sub requestFolder()
    markSelected()
    url = m.folderStack.Peek()
    m.foldersEmpty.text = "Opening..."
    m.foldersEmpty.visible = true
    m.folderList.content = CreateObject("roSGNode", "ContentNode")
    m.folderEntries = []
    showFolderPath(url)
    sendCommand({action: "list", url: url})
end sub

sub showFolderPath(url as String)
    root = m.folderStack[0]
    relative = Mid(url, Len(root) + 1)
    path = activeSource().label
    if relative <> "" then path = path + "  /  " + (relative).DecodeUriComponent().Replace("/", "  /  ")
    m.foldersPath.text = path
end sub

sub onTaskListing()
    listing = m.task.listing
    ' A folder the player's subtitle browser asked for.
    if m.subBrowseUrl <> invalid and listing.url = m.subBrowseUrl
        subBrowseListed(listing)
        if m.folderStack.Count() = 0 then return
        if listing.url <> m.folderStack.Peek() then return
    end if
    if m.folderStack.Count() = 0 then return
    if listing.url <> m.folderStack.Peek() then return
    if listing.error <> ""
        m.foldersEmpty.text = listing.error
        m.foldersEmpty.visible = true
        return
    end if
    m.folderEntries = listing.entries
    icons = {folder: "folder", video: "movie", audio: "music", image: "home", archive: "settings", file: "settings"}
    tags = {folder: "", video: "VIDEO", audio: "AUDIO", image: "IMAGE", archive: "PACKED", file: ""}
    colors = {folder: "0x39FF88FF", video: "0x2EA0FFFF", audio: "0x28DCFFFF", image: "0x8391AAFF", archive: "0xFFC857FF", file: "0x56627AFF"}
    root = CreateObject("roSGNode", "ContentNode")
    for each entry in listing.entries
        node = root.CreateChild("ContentNode")
        node.AddFields({kind: "", art: false, iconColor: colors[entry.kind], playing: false, dim: entry.kind = "file" or entry.kind = "archive", number: ""})
        node.title = entry.name
        detail = []
        if entry.date <> "" then detail.Push(entry.date)
        if entry.size > 0 then detail.Push(sizeText(entry.size))
        node.ShortDescriptionLine1 = detail.Join("   ·   ")
        node.ShortDescriptionLine2 = tags[entry.kind]
        node.HDPosterUrl = "pkg:/images/icon-" + icons[entry.kind] + ".png"
    end for
    m.folderList.content = root
    onFolderFocused()
    m.foldersEmpty.visible = listing.entries.Count() = 0
    if listing.entries.Count() = 0 then m.foldersEmpty.text = "This folder is empty."
    if m.area = "content" and m.view = "folders" and listing.entries.Count() > 0 then m.folderList.SetFocus(true)
end sub

function sizeText(megabytes as Float) as String
    if megabytes >= 1024 then return (Int(megabytes / 102.4) / 10).ToStr() + " GB"
    if megabytes >= 1 then return Int(megabytes).ToStr() + " MB"
    return Int(megabytes * 1024).ToStr() + " KB"
end function

function focusFolders() as Boolean
    m.area = "content"
    if m.folderEntries.Count() = 0
        m.keySink.SetFocus(true)
        return true
    end if
    m.folderList.SetFocus(true)
    return true
end function

function foldersKey(key as String) as Boolean
    if key = "back" and m.folderStack.Count() > 1
        m.folderStack.Pop()
        requestFolder()
        return true
    end if
    return false
end function

sub onFolderSelected()
    index = m.folderList.itemSelected
    if index < 0 or index >= m.folderEntries.Count() then return
    entry = m.folderEntries[index]
    if entry.kind = "folder"
        m.folderStack.Push(entry.url)
        requestFolder()
    else if entry.kind = "video"
        playLooseFile(entry)
    else if entry.kind = "audio"
        tracks = []
        start = 0
        for each e in m.folderEntries
            if e.kind = "audio"
                if e.url = entry.url then start = tracks.Count()
                tracks.Push({url: e.url, title: fileStemOf(e.name), ext: e.ext})
            end if
        end for
        playTracks(tracks, start, "", activeSource().label, "")
    else if entry.kind = "archive"
        showToast("Packed file: extract it on your seedbox to play it")
    else
        showToast("Box://Stream can't open this kind of file")
    end if
end sub

function fileStemOf(name as String) as String
    dot = -1
    i = name.Instr(".")
    while i >= 0
        dot = i
        i = name.Instr(i + 1, ".")
    end while
    if dot <= 0 then return name
    return Left(name, dot)
end function

sub folderFileChosen(choice as Object)
end sub

sub onFolderFocused()
    placeScrollBar(m.folderList, m.top.FindNode("folderTrack"), m.top.FindNode("folderThumb"))
end sub

' A list's scroll bar: hidden when every row fits; otherwise the thumb's
' size is the share of rows on screen and it moves with the focused row.
sub placeScrollBar(list as Object, track as Object, thumb as Object)
    if list = invalid or track = invalid or thumb = invalid then return
    count = 0
    if list.content <> invalid then count = list.content.GetChildCount()
    rows = list.numRows
    if count <= rows
        track.visible = false
        thumb.visible = false
        return
    end if
    height = track.height
    size = Int(height * rows / count)
    if size < 40 then size = 40
    focused = list.itemFocused
    if focused < 0 then focused = 0
    top = Int((height - size) * focused / (count - 1))
    start = track.translation
    thumb.height = size
    thumb.translation = [start[0], start[1] + top]
    track.visible = true
    thumb.visible = true
end sub

' The background follows the highlighted search result.
sub onSearchFocused()
    index = m.searchGrid.itemFocused
    if index >= 0 and index < m.searchItems.Count() then setBackdrop(backdropFor(m.searchItems[index]))
end sub
