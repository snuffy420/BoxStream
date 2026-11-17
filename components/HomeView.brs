' Home: a hero for the focused title over its backdrop, and rows below.

sub initHome()
    m.homeRows = m.top.FindNode("homeRows")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroLogo = m.top.FindNode("heroLogo")
    m.heroMeta = m.top.FindNode("heroMeta")
    m.heroOverview = m.top.FindNode("heroOverview")
    m.homeEmpty = m.top.FindNode("homeEmpty")
    m.heroTitle.font = makeFont("bold", 72)
    m.heroMeta.font = makeFont("bold", 26)
    m.heroOverview.font = makeFont("regular", 27)
    m.top.FindNode("emptyTitle").font = makeFont("bold", 40)
    m.top.FindNode("emptyText").font = makeFont("regular", 26)
    m.top.FindNode("emptyAction").font = makeFont("bold", 26)
    m.homeRows.rowLabelFont = makeFont("bold", 28)
    m.homeRows.ObserveField("rowItemFocused", "onHomeFocused")
    m.homeRows.ObserveField("rowItemSelected", "onHomeSelected")
    m.heroLogo.ObserveField("loadStatus", "onHeroLogo")
    m.heroTimer = m.top.FindNode("heroTimer")
    m.heroTimer.ObserveField("fire", "onHeroTimer")
    m.homeData = []
end sub

sub refreshHome()
    forgetCards()
    m.homeData = []
    empty = m.library = invalid
    if not empty then empty = m.library.movies.Count() + m.library.shows.Count() + m.library.albums.Count() = 0
    m.homeEmpty.visible = empty
    m.homeRows.visible = not empty
    if empty
        m.heroKey = ""
        m.heroLogo.uri = ""
        m.heroTitle.text = ""
        m.heroMeta.text = ""
        m.heroOverview.text = ""
        setBackdrop("")
        text = m.top.FindNode("emptyText")
        action = m.top.FindNode("emptyAction")
        if activeSource().url = ""
            text.text = "Stream the movies, shows and music on your seedbox. Add your server's web address (the folder you browse in a web browser) and login to get started."
            action.text = "Press OK to open Settings"
        else if m.scanPhase = "scanning" or m.scanPhase = "sorting"
            text.text = "Reading your server's folders and sorting what's there into movies, TV shows and music. Posters and details follow."
            action.text = m.statusLabel.text
        else
            text.text = "Nothing playable was found yet. Check the server address in Settings, or browse Folders."
            action.text = "Press OK to open Settings"
        end if
        return
    end if

    rows = []
    continueRow = continueEntries()
    if continueRow.Count() > 0 then rows.Push({title: "Continue Watching", entries: continueRow, square: false})
    recent = []
    for each r in m.library.recent
        item = m.items[r.key]
        if item <> invalid then recent.Push({item: item})
        if recent.Count() >= 25 then exit for
    end for
    if recent.Count() > 0 then rows.Push({title: "Recently Added", entries: recent, square: false})
    for each section in [{list: m.library.movies, title: "Movies"}, {list: m.library.shows, title: "TV Shows"}]
        entries = []
        for each item in section.list
            entries.Push({item: item})
            if entries.Count() >= 30 then exit for
        end for
        if entries.Count() > 0 then rows.Push({title: section.title + "  ·  " + section.list.Count().ToStr(), entries: entries, square: false})
    end for
    albums = []
    for each item in m.library.albums
        albums.Push({item: item})
        if albums.Count() >= 30 then exit for
    end for
    if albums.Count() > 0 then rows.Push({title: "Music  ·  " + m.library.albums.Count().ToStr(), entries: albums, square: true})

    unmatched = []
    for each listName in ["movies", "shows", "albums"]
        for each item in m.library[listName]
            if isUnmatched(item) then unmatched.Push({item: item})
            if unmatched.Count() >= 40 then exit for
        end for
    end for
    if unmatched.Count() > 0 then rows.Push({title: "Needs a match  ·  " + unmatched.Count().ToStr(), entries: unmatched, square: false})

    root = CreateObject("roSGNode", "ContentNode")
    sizes = []
    heights = []
    for each row in rows
        rowNode = root.CreateChild("ContentNode")
        rowNode.title = row.title
        for each entry in row.entries
            card = makeCard(rowNode, entry.item)
            if entry.episode <> invalid
                card.ShortDescriptionLine1 = episodeLabel(entry.episode) + "  ·  " + episodeName(entry.item, entry.episode)
                card.progress = progressFor(entry.episode.files[0].url)
            end if
        end for
        if row.square
            sizes.Push([280, 342])
            heights.Push(420)
        else
            sizes.Push([210, 377])
            heights.Push(455)
        end if
    end for
    m.homeData = rows
    m.homeRows.rowItemSize = sizes
    m.homeRows.rowHeights = heights
    m.homeRows.content = root
    if rows.Count() > 0 and rows[0].entries.Count() > 0 then showHero(rows[0].entries[0].item)
end sub

' In-progress movies and episodes, newest first.
function continueEntries() as Object
    list = []
    for each name in m.resume
        entry = m.resume[name]
        if entry.w <> true and entry.p >= 30 and entry.key <> invalid
            item = m.items[entry.key]
            if item <> invalid
                record = {item: item, t: entry.t}
                if item.kind = "show" and entry.ep <> invalid and entry.ep <> ""
                    for each episode in item.episodes
                        if episode.key = entry.ep then record.episode = episode
                    end for
                    if record.episode = invalid then item = invalid
                end if
                if item <> invalid then list.Push(record)
            end if
        end if
    end for
    list.SortBy("t", "r")
    ' One card per show.
    seen = {}
    out = []
    for each record in list
        if not seen.DoesExist(record.item.key)
            seen[record.item.key] = true
            out.Push(record)
        end if
        if out.Count() >= 15 then exit for
    end for
    return out
end function

function focusHome() as Boolean
    m.area = "content"
    if m.homeEmpty.visible
        m.keySink.SetFocus(true)
        return true
    end if
    m.homeRows.SetFocus(true)
    return true
end function

function homeKey(key as String) as Boolean
    if m.homeEmpty.visible and key = "OK"
        showTab("settings")
        focusContent()
        return true
    end if
    if key = "options" and m.homeRows.HasFocus()
        entry = focusedHomeEntry()
        if entry <> invalid
            openDetails(entry.item)
            openDetailsMenu()
        end if
        return true
    end if
    return false
end function

function focusedHomeEntry() as Dynamic
    focus = m.homeRows.rowItemFocused
    if focus = invalid or focus.Count() < 2 then return invalid
    if focus[0] < 0 or focus[0] >= m.homeData.Count() then return invalid
    row = m.homeData[focus[0]]
    if focus[1] < 0 or focus[1] >= row.entries.Count() then return invalid
    return row.entries[focus[1]]
end function

sub onHomeFocused()
    entry = focusedHomeEntry()
    if entry = invalid then return
    m.heroPending = entry.item
    m.heroTimer.control = "stop"
    m.heroTimer.control = "start"
end sub

sub onHeroTimer()
    if m.heroPending <> invalid then showHero(m.heroPending)
end sub

sub onHomeSelected()
    selected = m.homeRows.rowItemSelected
    entry = focusedHomeEntry()
    if selected <> invalid and selected.Count() > 1
        row = m.homeData[selected[0]]
        if row <> invalid then entry = row.entries[selected[1]]
    end if
    if entry = invalid then return
    if entry.episode <> invalid
        ' Continue Watching plays straight away.
        playEpisode(entry.item, entry.episode, true)
        return
    end if
    if entry.item.kind = "movie" and row <> invalid
        if row.title = "Continue Watching"
            playMovie(entry.item, 0, true)
            return
        end if
    end if
    openDetails(entry.item)
end sub

sub showHero(item as Object)
    if item = invalid then return
    m.heroKey = item.key
    meta = metaFor(item.key)
    logo = ""
    if meta <> invalid
        if meta.logo <> invalid then logo = meta.logo
    end if
    m.heroTitle.text = displayTitle(item)
    if logo <> ""
        m.heroTitle.visible = false
        if m.heroLogo.uri <> logo then m.heroLogo.uri = logo
        m.heroLogo.visible = true
    else
        m.heroLogo.visible = false
        m.heroLogo.uri = ""
        m.heroTitle.visible = true
    end if
    m.heroMeta.text = metaLine(item)
    overview = ""
    if meta <> invalid
        if meta.overview <> invalid then overview = meta.overview
    end if
    if overview = "" and item.kind = "album" then overview = albumSummary(item)
    m.heroOverview.text = overview
    setBackdrop(backdropFor(item))
end sub

sub onHeroLogo()
    if m.heroLogo.loadStatus = "failed"
        m.heroLogo.visible = false
        m.heroTitle.visible = true
    end if
end sub

' "MOVIE  ·  2008  ·  2h 32m  ·  9.0 IMDb  ·  Action, Crime"
function metaLine(item as Object) as String
    parts = []
    meta = metaFor(item.key)
    if item.kind = "movie" then parts.Push("MOVIE")
    if item.kind = "show" then parts.Push("TV SHOW")
    if item.kind = "album" then parts.Push("ALBUM")
    if item.kind = "album" then parts.Push(item.artist)
    year = itemYear(item)
    if meta <> invalid and item.kind = "show"
        if meta.ended <> invalid and meta.ended <> "" and meta.ended <> year then year = year + "–" + meta.ended
    end if
    if year <> "" then parts.Push(year)
    if item.kind = "show"
        seasons = item.seasons.Count()
        if seasons = 1 then parts.Push("1 season") else parts.Push(seasons.ToStr() + " seasons")
    end if
    if meta <> invalid
        if meta.runtime <> invalid and meta.runtime <> "" and item.kind = "movie" then parts.Push(runtimeText(meta.runtime))
        if meta.rating <> invalid and meta.rating <> "" then parts.Push(meta.rating + " / 10")
        if meta.network <> invalid and meta.network <> "" then parts.Push(meta.network)
    end if
    if item.kind = "album" then parts.Push(item.tracks.Count().ToStr() + " tracks")
    return UCase(parts.Join("  ·  "))
end function

function runtimeText(runtime as String) as String
    minutes = Val(runtime)
    if minutes <= 0 then return runtime
    if minutes < 60 then return Int(minutes).ToStr() + "m"
    return Int(minutes / 60).ToStr() + "h " + (Int(minutes) mod 60).ToStr() + "m"
end function

function albumSummary(item as Object) as String
    meta = metaFor(item.key)
    parts = []
    if meta <> invalid
        if meta.label <> invalid and meta.label <> "" then parts.Push("Label: " + meta.label)
        if meta.genres <> invalid and meta.genres <> "" then parts.Push(meta.genres)
        if meta.released <> invalid and meta.released <> "" then parts.Push("Released " + meta.released)
    end if
    return parts.Join("   ·   ")
end function
