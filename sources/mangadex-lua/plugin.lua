-- MangaDex Scraper Add-on (Lua)
-- Uses the official MangaDex API v5
--
-- Available APIs:
--   http_get(url) -> string
--   http_get_with_headers(url, headers) -> string
--   json_parse(text) -> table
--   json_stringify(value) -> string

local BASE_URL = "https://api.mangadex.org"
local COVERS_URL = "https://uploads.mangadex.org/covers"

--- Returns metadata about this source
function get_source_info()
    return {
        id = "mangadex-lua",
        name = "MangaDex (Lua)",
        base_url = BASE_URL,
        language = "en",
        supported_languages = {"en", "ja", "ko", "zh", "es", "fr", "de", "it", "pt-br", "ru"},
        requires_authentication = false,
        capability_level = "http_only"
    }
end

--- Extract title from MangaDex title object, preferring specified language
local function extract_title(title_obj, preferred_lang)
    if title_obj == nil then
        return ""
    end
    -- Try preferred language first
    if title_obj[preferred_lang] then
        return title_obj[preferred_lang]
    end
    -- Fall back to English
    if title_obj["en"] then
        return title_obj["en"]
    end
    -- Fall back to Japanese
    if title_obj["ja"] then
        return title_obj["ja"]
    end
    -- Return first available
    for _, v in pairs(title_obj) do
        return v
    end
    return ""
end

--- Extract cover URL from relationships
local function extract_cover_url(manga_id, relationships)
    if relationships == nil then
        return nil
    end
    for _, rel in ipairs(relationships) do
        if rel["type"] == "cover_art" then
            local attrs = rel["attributes"]
            if attrs and attrs["fileName"] then
                return COVERS_URL .. "/" .. manga_id .. "/" .. attrs["fileName"]
            end
        end
    end
    return nil
end

--- Extract authors from relationships
local function extract_authors(relationships)
    local authors = {}
    local seen = {}
    if relationships == nil then
        return authors
    end
    for _, rel in ipairs(relationships) do
        if rel["type"] == "author" or rel["type"] == "artist" then
            local attrs = rel["attributes"]
            if attrs and attrs["name"] then
                local name = attrs["name"]
                if not seen[name] then
                    table.insert(authors, name)
                    seen[name] = true
                end
            end
        end
    end
    return authors
end

--- Extract tags from manga data
local function extract_tags(tags, lang)
    local result = {}
    if tags == nil then
        return result
    end
    for _, tag in ipairs(tags) do
        local attrs = tag["attributes"]
        if attrs and attrs["name"] then
            local tag_name = extract_title(attrs["name"], lang)
            if tag_name ~= "" then
                table.insert(result, tag_name)
            end
        end
    end
    return result
end

--- Map status string to standard format
local function map_status(status)
    local status_map = {
        ongoing = "Ongoing",
        completed = "Completed",
        hiatus = "Hiatus",
        cancelled = "Cancelled"
    }
    return status_map[status] or status
end

--- Check if table contains value
local function table_contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

--- Search for series matching query
function search_series(query, page, auth)
    local offset = (page - 1) * 25
    local url = BASE_URL .. "/manga?title=" .. query .. "&limit=25&offset=" .. offset .. "&includes[]=cover_art&includes[]=author&includes[]=artist"

    local response_text = http_get(url)
    local response = json_parse(response_text)

    if response["result"] ~= "ok" then
        return { series = {}, has_more = false, total = 0 }
    end

    local data = response["data"]
    local total = response["total"] or 0
    local series = {}

    for _, manga in ipairs(data) do
        local id = manga["id"]
        local attrs = manga["attributes"]
        local rels = manga["relationships"]

        -- Extract title
        local title = extract_title(attrs["title"], "en")

        -- Extract alternate titles
        local alt_titles = {}
        if attrs["altTitles"] then
            for _, alt in ipairs(attrs["altTitles"]) do
                for _, alt_title in pairs(alt) do
                    if alt_title ~= title and not table_contains(alt_titles, alt_title) then
                        table.insert(alt_titles, alt_title)
                    end
                end
            end
        end

        -- Extract description
        local description = nil
        if attrs["description"] and attrs["description"]["en"] then
            description = attrs["description"]["en"]
        end

        table.insert(series, {
            id = id,
            title = title,
            url = "https://mangadex.org/title/" .. id,
            cover_url = extract_cover_url(id, rels),
            alternate_titles = alt_titles,
            authors = extract_authors(rels),
            artists = {},
            status = map_status(attrs["status"]),
            genres = extract_tags(attrs["tags"], "en"),
            tags = {},
            description = description
        })
    end

    local has_more = offset + 25 < total

    return { series = series, has_more = has_more, total = total }
end

--- Get detailed series information
function get_series(id_or_url, auth)
    -- Extract ID from URL if needed
    local id = id_or_url
    if string.find(id_or_url, "mangadex.org") then
        id = string.match(id_or_url, "/title/([^/]+)")
    end

    local url = BASE_URL .. "/manga/" .. id .. "?includes[]=cover_art&includes[]=author&includes[]=artist"

    local response_text = http_get(url)
    local response = json_parse(response_text)

    if response["result"] ~= "ok" then
        return {
            id = id,
            title = "",
            error = "Failed to fetch manga"
        }
    end

    local manga = response["data"]
    local attrs = manga["attributes"]
    local rels = manga["relationships"]

    local title = extract_title(attrs["title"], "en")

    -- Extract alternate titles
    local alt_titles = {}
    if attrs["altTitles"] then
        for _, alt in ipairs(attrs["altTitles"]) do
            for _, alt_title in pairs(alt) do
                if alt_title ~= title and not table_contains(alt_titles, alt_title) then
                    table.insert(alt_titles, alt_title)
                end
            end
        end
    end

    -- Extract description
    local description = nil
    if attrs["description"] and attrs["description"]["en"] then
        description = attrs["description"]["en"]
    end

    return {
        id = id,
        title = title,
        alternate_titles = alt_titles,
        description = description,
        cover_url = extract_cover_url(id, rels),
        authors = extract_authors(rels),
        artists = {},
        status = map_status(attrs["status"]),
        genres = extract_tags(attrs["tags"], "en"),
        tags = {},
        year = attrs["year"],
        content_rating = attrs["contentRating"],
        url = "https://mangadex.org/title/" .. id,
        extra = {
            original_language = attrs["originalLanguage"],
            last_chapter = attrs["lastChapter"],
            last_volume = attrs["lastVolume"],
            demographic = attrs["publicationDemographic"]
        }
    }
end

--- Get all chapters for a series
function get_chapters(series_id, auth)
    local chapters = {}
    local offset = 0
    local limit = 100

    while true do
        local url = BASE_URL .. "/manga/" .. series_id .. "/feed?limit=" .. limit .. "&offset=" .. offset .. "&translatedLanguage[]=en&order[chapter]=desc&includes[]=scanlation_group"

        local response_text = http_get(url)
        local response = json_parse(response_text)

        if response["result"] ~= "ok" then
            break
        end

        local data = response["data"]
        if #data == 0 then
            break
        end

        for _, chapter in ipairs(data) do
            local id = chapter["id"]
            local attrs = chapter["attributes"]
            local rels = chapter["relationships"]

            -- Extract scanlation group
            local scanlator = nil
            if rels then
                for _, rel in ipairs(rels) do
                    if rel["type"] == "scanlation_group" then
                        local rel_attrs = rel["attributes"]
                        if rel_attrs and rel_attrs["name"] then
                            scanlator = rel_attrs["name"]
                            break
                        end
                    end
                end
            end

            table.insert(chapters, {
                id = id,
                series_id = series_id,
                number = attrs["chapter"],
                title = attrs["title"],
                volume = attrs["volume"],
                language = attrs["translatedLanguage"],
                scanlator = scanlator,
                url = "https://mangadex.org/chapter/" .. id,
                published_at = attrs["publishAt"],
                page_count = attrs["pages"],
                extra = {
                    external_url = attrs["externalUrl"]
                }
            })
        end

        offset = offset + limit

        -- Prevent infinite loops
        if offset >= 10000 then
            break
        end
    end

    return chapters
end

--- Get page URLs for a chapter
function get_chapter_pages(chapter_id, auth)
    local url = BASE_URL .. "/at-home/server/" .. chapter_id

    local response_text = http_get(url)
    local response = json_parse(response_text)

    if response["result"] ~= "ok" then
        return {}
    end

    local base_url = response["baseUrl"]
    local chapter_data = response["chapter"]
    local hash = chapter_data["hash"]
    local data_pages = chapter_data["data"]

    local pages = {}

    for idx, filename in ipairs(data_pages) do
        table.insert(pages, {
            index = idx - 1,
            url = base_url .. "/data/" .. hash .. "/" .. filename,
            headers = {},
            referer = "https://mangadex.org/"
        })
    end

    return pages
end

--- Get latest updates
function get_latest_updates(page, auth)
    local offset = (page - 1) * 25
    local url = BASE_URL .. "/manga?limit=25&offset=" .. offset .. "&includes[]=cover_art&order[updatedAt]=desc"

    local response_text = http_get(url)
    local response = json_parse(response_text)

    if response["result"] ~= "ok" then
        return { series = {}, has_more = false }
    end

    local data = response["data"]
    local total = response["total"] or 0
    local series = {}

    for _, manga in ipairs(data) do
        local id = manga["id"]
        local attrs = manga["attributes"]
        local rels = manga["relationships"]

        table.insert(series, {
            id = id,
            title = extract_title(attrs["title"], "en"),
            url = "https://mangadex.org/title/" .. id,
            cover_url = extract_cover_url(id, rels),
            updated_at = attrs["updatedAt"]
        })
    end

    return { series = series, has_more = offset + 25 < total }
end
