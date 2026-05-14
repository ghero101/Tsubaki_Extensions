// Tsubaki Metadata Add-on Template (Rhai)
//
// Metadata add-ons provide series information from a tracking database
// (AniList, MyAnimeList, MangaUpdates, Kitsu, etc.) but do NOT download
// chapter content. They implement only `search_series` and `get_series`.
//
// AVAILABLE HOST FUNCTIONS
//
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string  (Chrome TLS impersonation)
//   http_get_plain(url, headers) -> string         (standard reqwest)
//   http_post(url, body) -> string
//   json_parse(text) -> Dynamic
//   json_stringify(value) -> string
//   url_encode(text) -> string
//   parse_int(str) -> int / parse_float(str) -> float

// ============================================================================
// Configuration
// ============================================================================

const API_URL = "https://api.yoursource.com";
const BASE_URL = "https://yoursource.com";

fn get_headers() {
    #{
        "User-Agent": "Tsubaki/1.0 (https://github.com/ghero101/Tsubaki_Extensions)",
        "Accept": "application/json",
        "Referer": BASE_URL
    }
}

// ============================================================================
// Helpers
// ============================================================================

/// Two-tier API fetch: TLS impersonation → plain reqwest. Each tier is
/// wrapped so a network error or empty response falls through to the next.
fn api_get(url) {
    try {
        let body = http_get_with_headers(url, get_headers());
        if body != "" { return body; }
    } catch {}
    try {
        return http_get_plain(url, get_headers());
    } catch {
        return "";
    }
}

/// Safely read a string field. Returns () if missing/null/empty.
fn read_str(obj, key) {
    if obj == () { return (); }
    let v = obj[key];
    if v == () { return (); }
    let s = `${v}`.trim();
    if s == "" { return (); }
    s
}

/// Safely read an array field. Returns [] if missing or wrong type.
fn read_arr(obj, key) {
    if obj == () { return []; }
    let v = obj[key];
    if v == () || type_of(v) != "array" { return []; }
    v
}

// ============================================================================
// Required interface
// ============================================================================

/// Returns metadata about this source. id MUST match manifest.id.
fn get_source_info() {
    #{
        id: "your-metadata-id",
        name: "Your Metadata Source",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Search for series matching query.
/// Returns: #{ series: [...], has_more: bool, total: int | () }
fn search_series(query, page, auth) {
    let per_page = 25;
    // ALWAYS url_encode the user-supplied query. Spaces and `&` break the URL.
    let url = `${API_URL}/search?q=${url_encode(query)}&page=${page}&per_page=${per_page}`;

    let body = api_get(url);
    if body == "" {
        return #{ series: [], has_more: false, total: () };
    }

    let data = ();
    try { data = json_parse(body); } catch {}
    if data == () {
        return #{ series: [], has_more: false, total: () };
    }

    // Many APIs return rate-limit / error responses as JSON with no `results`
    // key. Treat missing or non-array `results` as "no results" rather than
    // crashing on iteration.
    let results = read_arr(data, "results");
    let series = [];

    for item in results {
        let id = read_str(item, "id");
        let title = read_str(item, "title");
        if id == () || title == () { continue; }

        series.push(#{
            id: id,
            title: title,
            url: `${BASE_URL}/series/${id}`,
            cover_url: read_str(item, "cover_image"),
            alternate_titles: read_arr(item, "alternative_titles"),
            authors: read_arr(item, "authors"),
            artists: read_arr(item, "artists"),
            status: read_str(item, "status"),
            genres: read_arr(item, "genres"),
            tags: read_arr(item, "tags"),
            description: read_str(item, "synopsis"),
            year: read_str(item, "year"),
            content_rating: read_str(item, "content_rating")
        });
    }

    let total = data["total"];
    let total_int = if total != () { parse_int(`${total}`) } else { 0 };
    let has_more = total_int > 0 && (page * per_page) < total_int;

    #{ series: series, has_more: has_more, total: if total_int > 0 { total_int } else { () } }
}

/// Get detailed series information for one series.
/// Returns: SeriesInfo
fn get_series(id_or_url, auth) {
    let id = id_or_url;
    if id_or_url.contains("/") {
        let parts = id_or_url.split("/");
        // Take the last non-empty segment
        for i in 0..parts.len() {
            let p = parts[parts.len() - 1 - i];
            if p != "" {
                id = p;
                break;
            }
        }
    }

    let url = `${API_URL}/series/${id}`;
    let body = api_get(url);
    if body == "" {
        throw `Failed to fetch series: ${id}`;
    }

    let data = ();
    try { data = json_parse(body); } catch {}
    if data == () {
        throw `Invalid JSON response for series ${id}`;
    }

    // The wrapper key varies by API ("data" / "series" / nothing). Try common
    // shapes; fall back to data itself.
    let series_data = data;
    if data["data"] != () { series_data = data["data"]; }
    else if data["series"] != () { series_data = data["series"]; }

    let canonical_id = read_str(series_data, "id");
    if canonical_id == () { canonical_id = id; }

    #{
        id: canonical_id,
        title: read_str(series_data, "title"),
        alternate_titles: read_arr(series_data, "alternative_titles"),
        description: read_str(series_data, "synopsis"),
        cover_url: read_str(series_data, "cover_image"),
        authors: read_arr(series_data, "authors"),
        artists: read_arr(series_data, "artists"),
        status: read_str(series_data, "status"),
        genres: read_arr(series_data, "genres"),
        tags: read_arr(series_data, "tags"),
        year: read_str(series_data, "year"),
        content_rating: read_str(series_data, "content_rating"),
        url: `${BASE_URL}/series/${canonical_id}`,
        extra: #{
            // Store provider-specific IDs for cross-referencing
            provider_id: read_str(series_data, "id"),
            mal_id: read_str(series_data, "mal_id"),
            anilist_id: read_str(series_data, "anilist_id"),
            score: series_data["score"],
            popularity: series_data["popularity"]
        }
    }
}

// Metadata add-ons do NOT implement these functions:
//   - get_chapters()
//   - get_chapter_pages()
//   - download_page()

// Optional: Custom login for authenticated metadata access
// fn login(credentials) {
//     let api_key = credentials["api_key"];
//     #{
//         credentials: credentials,
//         cookies: [],
//         session_token: api_key
//     }
// }
