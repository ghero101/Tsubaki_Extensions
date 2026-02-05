// FoolSlide Framework Parser Add-on (Rhai)
// Generic parser for FoolSlide CMS-based manga sites
// FoolSlide is an open-source manga reading platform used by many scanlation groups
//
// FoolSlide API Endpoints:
//   GET /api/reader/comics - List all comics (series)
//   GET /api/reader/comic?id=X or ?stub=X - Get single comic with chapters
//   GET /api/reader/chapters - List all chapters
//   GET /api/reader/chapter?id=X - Get single chapter with pages
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   JSON: json_parse(text)
//   Regex: regex_find(pattern, text), regex_find_all(pattern, text)
//   String: url_encode(text)

// Base URL - MUST be configured via settings before use
// Example FoolSlide sites: reader.sensescans.com, jaiminisbox.com/reader, etc.
let BASE_URL = "";

/// Safely get a setting with fallback
fn safe_get_setting(key) {
    try {
        let val = get_setting(key);
        return val;
    } catch {
        return ();
    }
}

/// Get the configured base URL
fn get_configured_url() {
    let url = safe_get_setting("base_url");
    if url != () && url != "" {
        // Remove trailing slash
        if url.ends_with("/") {
            return url.sub_string(0, url.len() - 1);
        }
        return url;
    }
    ""
}

/// Check if extension is properly configured
fn is_configured() {
    let url = get_configured_url();
    url != "" && url.starts_with("http")
}

/// Returns metadata about this source
fn get_source_info() {
    let base = get_configured_url();
    if base == "" {
        base = "https://example.com";
    }
    #{
        id: "foolslide-rhai",
        name: "FoolSlide",
        base_url: base,
        language: "en",
        supported_languages: ["en", "es", "fr", "de", "it", "pt", "ru", "pl", "id", "vi"],
        requires_authentication: false,
        capability_level: "http_only",
        requires_configuration: true
    }
}

/// Get headers for API requests
fn get_headers() {
    let base = get_configured_url();
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/html, */*",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": base
    }
}

/// Build full URL from relative path
fn make_full_url(path) {
    let base = get_configured_url();
    if path.starts_with("http") {
        return path;
    }
    if path.starts_with("//") {
        return `https:${path}`;
    }
    if path.starts_with("/") {
        return `${base}${path}`;
    }
    `${base}/${path}`
}

/// Extract comic ID from various formats
fn extract_comic_id(id_or_url) {
    // If it's a full URL, extract the stub
    if id_or_url.contains("/series/") {
        let parts = id_or_url.split("/series/");
        if parts.len() > 1 {
            let stub = parts[1].split("/")[0].split("?")[0];
            return stub;
        }
    }
    if id_or_url.contains("/comic/") {
        let parts = id_or_url.split("/comic/");
        if parts.len() > 1 {
            let stub = parts[1].split("/")[0].split("?")[0];
            return stub;
        }
    }
    // Return as-is (could be ID or stub)
    id_or_url
}

/// Map FoolSlide status to standard format
fn map_status(status) {
    if status == () || status == "" {
        return ();
    }
    let status_lower = status.to_lower();
    if status_lower.contains("completed") || status_lower.contains("complete") {
        return "Completed";
    }
    if status_lower.contains("ongoing") || status_lower.contains("active") {
        return "Ongoing";
    }
    if status_lower.contains("dropped") || status_lower.contains("cancelled") {
        return "Cancelled";
    }
    if status_lower.contains("hiatus") {
        return "Hiatus";
    }
    ()
}

/// Parse FoolSlide API response for comics list
fn parse_comics_response(response) {
    let series = [];
    let base = get_configured_url();

    if response == () {
        return series;
    }

    // FoolSlide returns { comics: [...] } structure
    let comics = [];
    if response.contains("comics") {
        comics = response["comics"];
    } else if response.is_array() {
        // Some implementations return array directly
        comics = response;
    }

    for comic in comics {
        let id = "";
        let stub = "";

        // Get ID and stub
        if comic.contains("id") {
            id = comic["id"];
        }
        if comic.contains("stub") {
            stub = comic["stub"];
        }

        // Use stub as ID if available (more URL-friendly)
        let series_id = if stub != "" { stub } else { id };
        if series_id == "" {
            continue;
        }

        // Get title
        let title = "";
        if comic.contains("name") {
            title = comic["name"];
        } else if comic.contains("title") {
            title = comic["title"];
        }

        // Get description
        let description = ();
        if comic.contains("description") {
            description = comic["description"];
        }

        // Get cover/thumbnail URL
        let cover_url = ();
        if comic.contains("thumbnail") && comic["thumbnail"] != "" {
            // FoolSlide stores thumbnails in content/comics/[stub]_[uniqid]/[thumbnail]
            let thumb = comic["thumbnail"];
            if comic.contains("uniqid") && stub != "" {
                cover_url = `${base}/content/comics/${stub}_${comic["uniqid"]}/${thumb}`;
            } else if thumb.starts_with("http") || thumb.starts_with("/") {
                cover_url = make_full_url(thumb);
            }
        }

        // Get status
        let status = ();
        if comic.contains("status") {
            status = map_status(comic["status"]);
        }

        // Get author/artist
        let authors = [];
        let artists = [];
        if comic.contains("author") && comic["author"] != "" && comic["author"] != () {
            authors.push(comic["author"]);
        }
        if comic.contains("artist") && comic["artist"] != "" && comic["artist"] != () {
            artists.push(comic["artist"]);
        }

        // Build URL
        let url = `${base}/series/${stub}`;
        if stub == "" {
            url = `${base}/comic/${id}`;
        }

        series.push(#{
            id: series_id,
            title: title,
            url: url,
            cover_url: cover_url,
            alternate_titles: [],
            authors: authors,
            artists: artists,
            status: status,
            genres: [],
            tags: [],
            description: description
        });
    }

    series
}

/// Search for series matching query
/// FoolSlide doesn't have a native search API, so we fetch all comics and filter client-side
fn search_series(query, page, auth) {
    if !is_configured() {
        throw "FoolSlide extension requires configuration. Please set the base URL in extension settings.";
    }

    let base = get_configured_url();
    // FoolSlide API: /api/reader/comics
    // Parameters: page, per_page (max 100), orderby
    let per_page = 100;
    let url = `${base}/api/reader/comics?page=${page}&per_page=${per_page}`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    if response == () {
        // Fallback: try alternate endpoint format
        url = `${base}/api/reader/comics.json?page=${page}&per_page=${per_page}`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    let all_series = parse_comics_response(response);

    // Filter by query (case-insensitive)
    let query_lower = query.to_lower();
    let filtered = [];

    for series in all_series {
        let title_lower = series.title.to_lower();
        if title_lower.contains(query_lower) {
            filtered.push(series);
        } else if series.description != () {
            let desc_lower = series.description.to_lower();
            if desc_lower.contains(query_lower) {
                filtered.push(series);
            }
        }
    }

    // Check for more pages
    let has_more = all_series.len() >= per_page;

    #{ series: filtered, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    if !is_configured() {
        throw "FoolSlide extension requires configuration. Please set the base URL in extension settings.";
    }
    let base = get_configured_url();
    let series_id = extract_comic_id(id_or_url);

    // Try by stub first, then by id
    let url = `${base}/api/reader/comic?stub=${series_id}`;
    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    // If stub didn't work, try by id
    if response == () || (response.contains("error") && response["error"] != ()) {
        url = `${base}/api/reader/comic?id=${series_id}`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    // Fallback: try alternate endpoint format
    if response == () {
        url = `${base}/api/reader/comic.json?stub=${series_id}`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    if response == () {
        return #{
            id: series_id,
            title: "",
            error: "Failed to fetch comic data"
        };
    }

    // Extract comic data
    let comic = response;
    if response.contains("comic") {
        comic = response["comic"];
    }

    let id = "";
    let stub = "";

    if comic.contains("id") {
        id = comic["id"];
    }
    if comic.contains("stub") {
        stub = comic["stub"];
    }

    // Get title
    let title = "";
    if comic.contains("name") {
        title = comic["name"];
    } else if comic.contains("title") {
        title = comic["title"];
    }

    // Get description
    let description = ();
    if comic.contains("description") {
        description = comic["description"];
    }

    // Get cover URL
    let cover_url = ();
    if comic.contains("thumbnail") && comic["thumbnail"] != "" {
        let thumb = comic["thumbnail"];
        if comic.contains("uniqid") && stub != "" {
            cover_url = `${base}/content/comics/${stub}_${comic["uniqid"]}/${thumb}`;
        } else if thumb.starts_with("http") || thumb.starts_with("/") {
            cover_url = make_full_url(thumb);
        }
    }

    // Get status
    let status = ();
    if comic.contains("status") {
        status = map_status(comic["status"]);
    }

    // Get author/artist
    let authors = [];
    let artists = [];
    if comic.contains("author") && comic["author"] != "" && comic["author"] != () {
        authors.push(comic["author"]);
    }
    if comic.contains("artist") && comic["artist"] != "" && comic["artist"] != () {
        artists.push(comic["artist"]);
    }

    // Get genres
    let genres = [];
    if comic.contains("genres") {
        if comic["genres"].is_array() {
            for g in comic["genres"] {
                if g.is_string() {
                    genres.push(g);
                } else if g.contains("name") {
                    genres.push(g["name"]);
                }
            }
        }
    }

    // Build series URL
    let series_url = `${base}/series/${stub}`;
    if stub == "" {
        series_url = `${base}/comic/${id}`;
    }

    #{
        id: if stub != "" { stub } else { id },
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: status,
        genres: genres,
        tags: [],
        year: (),
        content_rating: "suggestive",
        url: series_url,
        extra: #{
            comic_id: id,
            stub: stub
        }
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    if !is_configured() {
        throw "FoolSlide extension requires configuration. Please set the base URL in extension settings.";
    }
    let base = get_configured_url();
    let comic_id = extract_comic_id(series_id);

    // Fetch comic with chapters
    let url = `${base}/api/reader/comic?stub=${comic_id}`;
    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    // If stub didn't work, try by id
    if response == () || (response.contains("error") && response["error"] != ()) {
        url = `${base}/api/reader/comic?id=${comic_id}`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    // Fallback: try alternate endpoint format
    if response == () {
        url = `${base}/api/reader/comic.json?stub=${comic_id}`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    if response == () {
        return [];
    }

    let chapters = [];
    let chapter_list = [];

    // Extract chapters array
    if response.contains("chapters") {
        chapter_list = response["chapters"];
    } else if response.contains("comic") && response["comic"].contains("chapters") {
        chapter_list = response["comic"]["chapters"];
    }

    // Get teams data for scanlator info
    let teams = #{};
    if response.contains("teams") {
        for team in response["teams"] {
            if team.contains("id") && team.contains("name") {
                teams[team["id"]] = team["name"];
            }
        }
    }

    // Get comic stub for URL building
    let comic_stub = comic_id;
    if response.contains("comic") && response["comic"].contains("stub") {
        comic_stub = response["comic"]["stub"];
    }

    for chapter in chapter_list {
        let ch_id = "";
        if chapter.contains("id") {
            ch_id = chapter["id"];
        }

        // Build chapter number string
        let ch_num = "";
        if chapter.contains("chapter") && chapter["chapter"] != () {
            ch_num = chapter["chapter"];
            // Handle subchapter (e.g., 10.5)
            if chapter.contains("subchapter") && chapter["subchapter"] != () && chapter["subchapter"] != "0" && chapter["subchapter"] != "" {
                ch_num = `${ch_num}.${chapter["subchapter"]}`;
            }
        }

        // Get volume
        let volume = ();
        if chapter.contains("volume") && chapter["volume"] != () && chapter["volume"] != "0" && chapter["volume"] != "" {
            volume = chapter["volume"];
        }

        // Get title
        let title = ();
        if chapter.contains("name") && chapter["name"] != "" && chapter["name"] != () {
            title = chapter["name"];
        } else if chapter.contains("title") && chapter["title"] != "" && chapter["title"] != () {
            title = chapter["title"];
        }

        // Get language
        let language = "en";
        if chapter.contains("language") && chapter["language"] != () {
            language = chapter["language"];
        }

        // Get scanlator from team_id
        let scanlator = ();
        if chapter.contains("team_id") && chapter["team_id"] != () {
            let team_id = chapter["team_id"];
            if teams.contains(team_id) {
                scanlator = teams[team_id];
            }
        }
        // Also check for joint translations
        if chapter.contains("joint_id") && chapter["joint_id"] != () {
            // Joint releases may have multiple teams
            // For now, just note it in the scanlator field
            if scanlator == () {
                scanlator = "Joint";
            }
        }

        // Get published date
        let published_at = ();
        if chapter.contains("created") {
            published_at = chapter["created"];
        } else if chapter.contains("updated") {
            published_at = chapter["updated"];
        }

        // Build chapter URL
        // FoolSlide read URL format: /read/[comic_stub]/[language]/[volume]/[chapter]/[subchapter]
        let ch_stub = "";
        if chapter.contains("stub") {
            ch_stub = chapter["stub"];
        }
        let vol_str = if volume != () { volume } else { "0" };
        let sub_str = if chapter.contains("subchapter") && chapter["subchapter"] != () { chapter["subchapter"] } else { "0" };
        let chapter_url = `${base}/read/${comic_stub}/${language}/${vol_str}/${ch_num}/${sub_str}`;

        chapters.push(#{
            id: ch_id,
            series_id: series_id,
            number: ch_num,
            title: title,
            volume: volume,
            language: language,
            scanlator: scanlator,
            url: chapter_url,
            published_at: published_at,
            page_count: (),
            extra: #{
                stub: ch_stub
            }
        });
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    if !is_configured() {
        throw "FoolSlide extension requires configuration. Please set the base URL in extension settings.";
    }
    let base = get_configured_url();
    // Fetch chapter by ID
    let url = `${base}/api/reader/chapter?id=${chapter_id}`;
    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    // Fallback: try alternate endpoint format
    if response == () {
        url = `${base}/api/reader/chapter.json?id=${chapter_id}`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    if response == () {
        return [];
    }

    let pages = [];
    let idx = 0;

    // Extract pages array
    let page_list = [];
    if response.contains("pages") {
        page_list = response["pages"];
    } else if response.contains("chapter") && response["chapter"].contains("pages") {
        page_list = response["chapter"]["pages"];
    }

    // Get chapter directory for building full URLs
    let chapter_dir = "";
    let comic_dir = "";
    if response.contains("chapter") {
        let chapter = response["chapter"];
        if chapter.contains("directory") {
            chapter_dir = chapter["directory"];
        }
        // Get comic info for directory
        if response.contains("comic") {
            let comic = response["comic"];
            if comic.contains("directory") {
                comic_dir = comic["directory"];
            } else if comic.contains("stub") && comic.contains("uniqid") {
                comic_dir = `${comic["stub"]}_${comic["uniqid"]}`;
            }
        }
    }

    for page in page_list {
        let img_url = "";

        // Pages can be objects with url/thumb_url or just URL strings
        if page.is_string() {
            img_url = page;
        } else if page.contains("url") {
            img_url = page["url"];
        }

        if img_url == "" {
            continue;
        }

        // Build full URL if needed
        // FoolSlide page URL format: content/comics/[comic_dir]/[chapter_dir]/[filename]
        if !img_url.starts_with("http") {
            if comic_dir != "" && chapter_dir != "" {
                img_url = `${base}/content/comics/${comic_dir}/${chapter_dir}/${img_url}`;
            } else {
                img_url = make_full_url(img_url);
            }
        }

        pages.push(#{
            index: idx,
            url: img_url,
            headers: #{
                "Referer": BASE_URL
            },
            referer: BASE_URL
        });
        idx += 1;
    }

    pages
}

/// Get latest chapter updates
fn get_latest_updates(page, auth) {
    if !is_configured() {
        throw "FoolSlide extension requires configuration. Please set the base URL in extension settings.";
    }
    let base = get_configured_url();
    // FoolSlide API: /api/reader/chapters with ordering
    let per_page = 50;
    let url = `${base}/api/reader/chapters?page=${page}&per_page=${per_page}&orderby=created`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    // Fallback: try alternate endpoint format
    if response == () {
        url = `${base}/api/reader/chapters.json?page=${page}&per_page=${per_page}&orderby=created`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    let series = [];
    let seen = #{};

    if response == () {
        return #{ series: [], has_more: false };
    }

    // Extract chapters
    let chapter_list = [];
    if response.contains("chapters") {
        chapter_list = response["chapters"];
    } else if response.is_array() {
        chapter_list = response;
    }

    for chapter in chapter_list {
        // Get comic info from chapter
        let comic_id = "";
        let comic_stub = "";
        let title = "";
        let cover_url = ();

        if chapter.contains("comic") {
            let comic = chapter["comic"];
            if comic.contains("id") {
                comic_id = comic["id"];
            }
            if comic.contains("stub") {
                comic_stub = comic["stub"];
            }
            if comic.contains("name") {
                title = comic["name"];
            }
            if comic.contains("thumbnail") && comic["thumbnail"] != "" {
                let thumb = comic["thumbnail"];
                if comic.contains("uniqid") && comic_stub != "" {
                    cover_url = `${base}/content/comics/${comic_stub}_${comic["uniqid"]}/${thumb}`;
                }
            }
        }

        // Skip if we've already seen this comic
        let series_id = if comic_stub != "" { comic_stub } else { comic_id };
        if series_id == "" || seen.contains(series_id) {
            continue;
        }
        seen[series_id] = true;

        // Get update time
        let updated_at = ();
        if chapter.contains("created") {
            updated_at = chapter["created"];
        }

        if title != "" {
            series.push(#{
                id: series_id,
                title: title,
                url: `${base}/series/${comic_stub}`,
                cover_url: cover_url,
                updated_at: updated_at
            });
        }
    }

    let has_more = chapter_list.len() >= per_page;

    #{ series: series, has_more: has_more }
}

/// Get popular/all series
fn get_popular(page, auth) {
    if !is_configured() {
        throw "FoolSlide extension requires configuration. Please set the base URL in extension settings.";
    }
    let base = get_configured_url();
    // FoolSlide doesn't have popularity metrics, so return all comics
    let per_page = 50;
    let url = `${base}/api/reader/comics?page=${page}&per_page=${per_page}`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    // Fallback: try alternate endpoint format
    if response == () {
        url = `${base}/api/reader/comics.json?page=${page}&per_page=${per_page}`;
        response_text = http_get_with_headers(url, get_headers());
        response = json_parse(response_text);
    }

    let all_series = parse_comics_response(response);
    let has_more = all_series.len() >= per_page;

    // Convert to simpler format
    let series = [];
    for s in all_series {
        series.push(#{
            id: s.id,
            title: s.title,
            url: s.url,
            cover_url: s.cover_url
        });
    }

    #{ series: series, has_more: has_more }
}
