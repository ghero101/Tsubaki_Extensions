// nhentai Scraper Add-on (Rhai)
// Provides access to nhentai doujinshi/manga
//
// WARNING: This addon provides access to EXPLICIT adult content.
// Users MUST be 18+ years old to use this addon.
// By using this addon, you confirm you are of legal age in your jurisdiction.
//
// API Reference:
//   Search: https://nhentai.net/api/galleries/search?query=TAG&page=1
//   Gallery: https://nhentai.net/api/gallery/{id}
//   Images: https://i.nhentai.net/galleries/{media_id}/{page}.{ext}
//   Thumbnails: https://t.nhentai.net/galleries/{media_id}/thumb.jpg
//
// Available Rhai APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const BASE_URL = "https://nhentai.net";
const API_URL = "https://nhentai.net/api";
const IMAGE_URL = "https://i.nhentai.net/galleries";
const THUMB_URL = "https://t.nhentai.net/galleries";

// --- Helper Functions ---

/// Get file extension from image type
fn get_extension(type_char) {
    if type_char == "j" {
        return "jpg";
    } else if type_char == "p" {
        return "png";
    } else if type_char == "g" {
        return "gif";
    } else if type_char == "w" {
        return "webp";
    }
    return "jpg";
}

/// Extract tags of a specific type from gallery data
fn extract_tags_by_type(tags, tag_type) {
    let result = [];
    if tags == () {
        return result;
    }
    for tag in tags {
        if tag["type"] == tag_type {
            let name = tag["name"];
            if name != () {
                result.push(name);
            }
        }
    }
    return result;
}

/// Get all tag names from gallery
fn extract_all_tags(tags) {
    let result = [];
    if tags == () {
        return result;
    }
    for tag in tags {
        if tag["type"] == "tag" {
            let name = tag["name"];
            if name != () {
                result.push(name);
            }
        }
    }
    return result;
}

/// Build title from gallery data
fn build_title(gallery) {
    let title = gallery["title"];
    if title == () {
        return "Unknown";
    }
    // Prefer English title, fall back to Japanese, then pretty
    if title["english"] != () && title["english"] != "" {
        return title["english"];
    }
    if title["japanese"] != () && title["japanese"] != "" {
        return title["japanese"];
    }
    if title["pretty"] != () && title["pretty"] != "" {
        return title["pretty"];
    }
    return "Unknown";
}

/// Build alternate titles from gallery data
fn build_alternate_titles(gallery) {
    let alt_titles = [];
    let title = gallery["title"];
    if title == () {
        return alt_titles;
    }
    let main_title = build_title(gallery);

    if title["english"] != () && title["english"] != "" && title["english"] != main_title {
        alt_titles.push(title["english"]);
    }
    if title["japanese"] != () && title["japanese"] != "" && title["japanese"] != main_title {
        alt_titles.push(title["japanese"]);
    }
    if title["pretty"] != () && title["pretty"] != "" && title["pretty"] != main_title {
        alt_titles.push(title["pretty"]);
    }
    return alt_titles;
}

/// Build cover URL from gallery data
fn build_cover_url(gallery) {
    let media_id = gallery["media_id"];
    if media_id == () {
        return "";
    }
    let images = gallery["images"];
    if images == () {
        return `${THUMB_URL}/${media_id}/thumb.jpg`;
    }
    let cover = images["cover"];
    if cover == () {
        return `${THUMB_URL}/${media_id}/thumb.jpg`;
    }
    let ext = get_extension(cover["t"]);
    return `${THUMB_URL}/${media_id}/cover.${ext}`;
}

/// Build a series result from nhentai gallery data
fn build_series_result(gallery) {
    let id = gallery["id"];
    if id == () {
        return ();
    }
    let id_str = id.to_string();
    let media_id = gallery["media_id"];
    let tags = gallery["tags"];

    // Extract different tag types
    let artists = extract_tags_by_type(tags, "artist");
    let parodies = extract_tags_by_type(tags, "parody");
    let characters = extract_tags_by_type(tags, "character");
    let groups = extract_tags_by_type(tags, "group");
    let languages = extract_tags_by_type(tags, "language");
    let categories = extract_tags_by_type(tags, "category");
    let content_tags = extract_all_tags(tags);

    // Build description from parodies and characters
    let desc_parts = [];
    if parodies.len() > 0 {
        desc_parts.push("Parody: " + parodies.join(", "));
    }
    if characters.len() > 0 {
        desc_parts.push("Characters: " + characters.join(", "));
    }
    if groups.len() > 0 {
        desc_parts.push("Group: " + groups.join(", "));
    }
    if languages.len() > 0 {
        desc_parts.push("Language: " + languages.join(", "));
    }
    let description = desc_parts.join("\n");

    // Get page count
    let num_pages = gallery["num_pages"];
    if num_pages == () {
        num_pages = 0;
    }

    // Get upload date
    let upload_date = gallery["upload_date"];

    #{
        id: id_str,
        title: build_title(gallery),
        alternate_titles: build_alternate_titles(gallery),
        description: description,
        cover_url: build_cover_url(gallery),
        authors: artists,
        artists: artists,
        status: "Completed",
        genres: categories,
        tags: content_tags,
        year: (),
        content_rating: "explicit",
        url: `${BASE_URL}/g/${id_str}/`,
        extra: #{
            media_id: media_id,
            num_pages: num_pages,
            parodies: parodies,
            characters: characters,
            groups: groups,
            languages: languages,
            upload_date: upload_date,
            source_site: "nhentai"
        }
    }
}

// --- Addon Interface Functions ---

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "nhentai-rhai",
        name: "nhentai",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en", "ja", "zh"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["doujinshi", "manga", "hentai"]
    }
}

/// Search for galleries matching a query
/// API: https://nhentai.net/api/galleries/search?query=TAG&page=1
fn search_series(query, page, auth) {
    let search_query = url_encode(query);
    let url = `${API_URL}/galleries/search?query=${search_query}&page=${page}`;

    // Add language filter if set in settings (settings is a scope variable)
    let lang = settings["preferred_language"];
    if lang != () && lang != "" {
        url = `${API_URL}/galleries/search?query=${search_query}+language:${lang}&page=${page}`;
    }

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": BASE_URL
    };

    let response_text = "";
    // Try with headers first, fall back to simple get
    try {
        response_text = http_get_with_headers(url, headers);
    } catch {
        response_text = http_get(url);
    }

    if response_text == "" || response_text == "null" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let data = json_parse(response_text);

    if data == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let result_array = data["result"];
    if result_array == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    for gallery in result_array {
        let item = build_series_result(gallery);
        if item != () {
            series.push(item);
        }
    }

    let total = data["num_pages"];
    if total == () {
        total = 0;
    }
    let per_page = data["per_page"];
    if per_page == () {
        per_page = 25;
    }

    let has_more = page < total;
    let total_results = total * per_page;

    #{ series: series, has_more: has_more, total: total_results }
}

/// Get detailed gallery information by ID
/// API: https://nhentai.net/api/gallery/{id}
fn get_series(id_or_url, auth) {
    let id = id_or_url;

    // Extract ID from URL if provided
    // URLs can be: https://nhentai.net/g/123456/ or just 123456
    if id_or_url.contains("nhentai.net/g/") {
        let parts = id_or_url.split("/g/");
        if parts.len() > 1 {
            let id_part = parts[1];
            // Remove trailing slash if present
            id = id_part.split("/")[0];
        }
    }

    let url = `${API_URL}/gallery/${id}`;

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": BASE_URL
    };

    let response_text = "";
    try {
        response_text = http_get_with_headers(url, headers);
    } catch {
        response_text = http_get(url);
    }

    if response_text == "" || response_text == "null" {
        throw `Failed to fetch gallery with ID: ${id}`;
    }

    let gallery = json_parse(response_text);

    if gallery == () {
        throw `Failed to parse gallery data for ID: ${id}`;
    }

    // Check for error response
    if gallery["error"] != () {
        throw `API error: ${gallery["error"]}`;
    }

    build_series_result(gallery)
}

/// Get chapters for a gallery
/// For nhentai, each gallery IS the chapter (single chapter per gallery)
fn get_chapters(series_id, auth) {
    // First get the gallery details to get page count
    let url = `${API_URL}/gallery/${series_id}`;

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": BASE_URL
    };

    let response_text = "";
    try {
        response_text = http_get_with_headers(url, headers);
    } catch {
        response_text = http_get(url);
    }

    if response_text == "" || response_text == "null" {
        return [];
    }

    let gallery = json_parse(response_text);

    if gallery == () || gallery["error"] != () {
        return [];
    }

    let title = build_title(gallery);
    let num_pages = gallery["num_pages"];
    if num_pages == () {
        num_pages = 0;
    }

    let upload_date = gallery["upload_date"];

    // nhentai galleries are single-chapter works
    // The chapter ID is the same as the gallery ID
    [
        #{
            id: series_id,
            series_id: series_id,
            number: "1",
            title: title,
            volume: (),
            language: "en",
            scanlator: "",
            url: `${BASE_URL}/g/${series_id}/`,
            published_at: upload_date,
            page_count: num_pages,
            extra: #{
                is_oneshot: true
            }
        }
    ]
}

/// Get page URLs for a chapter (gallery)
/// API: https://nhentai.net/api/gallery/{id}
/// Images: https://i.nhentai.net/galleries/{media_id}/{page}.{ext}
fn get_chapter_pages(chapter_id, auth) {
    let url = `${API_URL}/gallery/${chapter_id}`;

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": BASE_URL
    };

    let response_text = "";
    try {
        response_text = http_get_with_headers(url, headers);
    } catch {
        response_text = http_get(url);
    }

    if response_text == "" || response_text == "null" {
        return [];
    }

    let gallery = json_parse(response_text);

    if gallery == () || gallery["error"] != () {
        return [];
    }

    let media_id = gallery["media_id"];
    if media_id == () {
        return [];
    }

    let images = gallery["images"];
    if images == () {
        return [];
    }

    let pages_data = images["pages"];
    if pages_data == () {
        return [];
    }

    let pages = [];
    let i = 0;
    for page_info in pages_data {
        let ext = get_extension(page_info["t"]);
        let page_num = i + 1;
        let image_url = `${IMAGE_URL}/${media_id}/${page_num}.${ext}`;

        pages.push(#{
            index: i,
            url: image_url,
            headers: #{
                "Referer": `${BASE_URL}/g/${chapter_id}/`
            },
            referer: `${BASE_URL}/g/${chapter_id}/`,
            width: page_info["w"],
            height: page_info["h"]
        });

        i += 1;
    }

    pages
}

/// Get latest/popular galleries
fn get_latest_updates(page, auth) {
    // Use the all galleries endpoint sorted by recent
    let url = `${API_URL}/galleries/all?page=${page}`;

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": BASE_URL
    };

    let response_text = "";
    try {
        response_text = http_get_with_headers(url, headers);
    } catch {
        response_text = http_get(url);
    }

    if response_text == "" || response_text == "null" {
        return #{ series: [], has_more: false };
    }

    let data = json_parse(response_text);

    if data == () {
        return #{ series: [], has_more: false };
    }

    let result_array = data["result"];
    if result_array == () {
        return #{ series: [], has_more: false };
    }

    let series = [];
    for gallery in result_array {
        let item = build_series_result(gallery);
        if item != () {
            series.push(item);
        }
    }

    let total_pages = data["num_pages"];
    if total_pages == () {
        total_pages = 0;
    }

    let has_more = page < total_pages;

    #{ series: series, has_more: has_more }
}

/// Get popular tags for browsing
fn get_popular_tags() {
    // Common search tags on nhentai
    [
        "english",
        "japanese",
        "chinese",
        "translated",
        "full color",
        "sole female",
        "sole male",
        "manga",
        "doujinshi"
    ]
}

/// Search by tag (convenience function)
fn search_by_tag(tag, page, auth) {
    // Tags can be searched using the tag: prefix
    let query = `tag:"${tag}"`;
    search_series(query, page, auth)
}

/// Search by artist (convenience function)
fn search_by_artist(artist, page, auth) {
    let query = `artist:"${artist}"`;
    search_series(query, page, auth)
}

/// Search by parody (convenience function)
fn search_by_parody(parody, page, auth) {
    let query = `parody:"${parody}"`;
    search_series(query, page, auth)
}
