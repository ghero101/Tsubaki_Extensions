// Tsubaki Metadata Add-on Template (Rhai)
//
// This template provides the required functions for a metadata-only add-on.
// Metadata add-ons provide series information but do NOT download content.
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   http_post(url, body) -> string
//   json_parse(text) -> Dynamic
//   json_stringify(value) -> string
//   html_parse(html) -> Document (if needed)

// API base URL
const API_URL = "https://api.yoursource.com";
const BASE_URL = "https://yoursource.com";

/// Returns metadata about this source
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

/// Search for series matching query
/// Returns: #{ series: [...], has_more: bool, total: int | () }
fn search_series(query, page, auth) {
    // Build API URL
    let per_page = 25;
    let url = `${API_URL}/search?q=${query}&page=${page}&per_page=${per_page}`;

    // Fetch JSON
    let response = http_get(url);
    let data = json_parse(response);

    // Extract series
    let series = [];
    for item in data["results"] {
        series.push(#{
            id: item["id"].to_string(),
            title: item["title"],
            url: `${BASE_URL}/series/${item["id"]}`,
            cover_url: item["cover_image"],
            alternate_titles: item["alternative_titles"],
            authors: item["authors"],
            artists: item["artists"],
            status: item["status"],
            genres: item["genres"],
            tags: item["tags"],
            description: item["synopsis"],
            year: item["year"],
            content_rating: item["content_rating"]
        });
    }

    // Pagination info
    let total = data["total"];
    let has_more = page * per_page < total;

    #{ series: series, has_more: has_more, total: total }
}

/// Get detailed series information
/// Returns: SeriesInfo
fn get_series(id_or_url, auth) {
    // Extract ID from URL if needed
    let id = id_or_url;
    if id_or_url.contains("/") {
        // Extract ID from URL pattern like /series/12345
        let parts = id_or_url.split("/");
        id = parts[parts.len() - 1];
    }

    let url = `${API_URL}/series/${id}`;
    let response = http_get(url);
    let data = json_parse(response);

    #{
        id: data["id"].to_string(),
        title: data["title"],
        alternate_titles: data["alternative_titles"],
        description: data["synopsis"],
        cover_url: data["cover_image"],
        authors: data["authors"],
        artists: data["artists"],
        status: data["status"],
        genres: data["genres"],
        tags: data["tags"],
        year: data["year"],
        content_rating: data["content_rating"],
        url: `${BASE_URL}/series/${data["id"]}`,
        extra: #{
            // Store provider-specific IDs for cross-referencing
            provider_id: data["id"],
            mal_id: data["mal_id"],
            anilist_id: data["anilist_id"],
            score: data["score"],
            popularity: data["popularity"]
        }
    }
}

// Note: Metadata add-ons do NOT implement these functions:
// - get_chapters()
// - get_chapter_pages()
// - download_page()

// Optional: Custom login for authenticated metadata access
// fn login(credentials) {
//     let api_key = credentials["api_key"];
//     // Validate API key and return auth context
//     #{
//         credentials: credentials,
//         cookies: [],
//         session_token: api_key
//     }
// }
