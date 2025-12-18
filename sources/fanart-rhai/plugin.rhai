// Fan Art Gallery Plugin for Safebooru
// Searches and retrieves safe-for-work fan art
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const BASE_URL = "https://safebooru.org";
const API_URL = "https://safebooru.org/index.php";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "fanart-rhai",
        name: "Fan Art Gallery",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Helper to build result from post data
fn build_result(post) {
    // Get values from post - handle potential missing fields
    let post_id = "";
    if post.contains("id") {
        post_id = post["id"].to_string();
    }

    let tags_str = "";
    if post.contains("tags") {
        tags_str = post["tags"];
    }

    // Parse tags - split by space
    let tags = [];
    if tags_str != "" && tags_str != () {
        tags = tags_str.split(" ");
    }

    // Build title from first few tags manually
    let title = "Untitled";
    if tags.len() > 0 {
        title = tags[0];
        if tags.len() > 1 { title = title + ", " + tags[1]; }
        if tags.len() > 2 { title = title + ", " + tags[2]; }
        if tags.len() > 3 { title = title + ", " + tags[3]; }
        if tags.len() > 4 { title = title + ", " + tags[4]; }
    }

    // Get URLs - use direct URLs from response
    let preview_url = "";
    if post.contains("preview_url") {
        preview_url = post["preview_url"];
    }

    let file_url = "";
    if post.contains("file_url") {
        file_url = post["file_url"];
    }

    let sample_url = "";
    if post.contains("sample_url") {
        sample_url = post["sample_url"];
    }

    let width = 0;
    if post.contains("width") {
        width = post["width"];
    }

    let height = 0;
    if post.contains("height") {
        height = post["height"];
    }

    let source = "";
    if post.contains("source") {
        source = post["source"];
    }

    #{
        id: post_id,
        title: title,
        alternate_titles: [],
        description: "Tags: " + tags_str,
        cover_url: preview_url,
        authors: [],
        artists: [],
        status: (),
        genres: [],
        tags: tags,
        year: (),
        content_rating: "safe",
        url: `${BASE_URL}/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: sample_url,
            width: width,
            height: height,
            source: source
        }
    }
}

/// Search for fan art by tags/series name
fn search(query, page) {
    // Build tag query - add rating:safe for safe content
    let tags = query + " rating:safe";
    let limit = 40;

    let url = `${API_URL}?page=dapi&s=post&q=index&json=1&limit=${limit}&pid=${page}&tags=` + url_encode(tags);

    let body = http_get(url);
    let data = json_parse(body);

    // Empty check
    if data == () || type_of(data) != "array" || data.len() == 0 {
        return #{
            series: [],
            has_more: false,
            total: ()
        };
    }

    let results = [];
    for post in data {
        results.push(build_result(post));
    }

    #{
        series: results,
        has_more: results.len() >= limit,
        total: ()
    }
}

/// Get latest updates (used for browse)
fn get_latest_updates(page, auth) {
    let limit = 40;
    let url = `${API_URL}?page=dapi&s=post&q=index&json=1&limit=${limit}&pid=${page}&tags=rating:safe`;

    let body = http_get(url);
    let data = json_parse(body);

    // Empty check
    if data == () || type_of(data) != "array" || data.len() == 0 {
        return #{
            series: [],
            has_more: false,
            total: ()
        };
    }

    let results = [];
    for post in data {
        results.push(build_result(post));
    }

    #{
        series: results,
        has_more: results.len() >= limit,
        total: ()
    }
}

/// Get popular images (sorted by score)
fn get_popular(page) {
    let limit = 40;
    let url = `${API_URL}?page=dapi&s=post&q=index&json=1&limit=${limit}&pid=${page}&tags=sort:score+rating:safe`;

    let body = http_get(url);
    let data = json_parse(body);

    // Empty check
    if data == () || type_of(data) != "array" || data.len() == 0 {
        return #{
            series: [],
            has_more: false,
            total: ()
        };
    }

    let results = [];
    for post in data {
        results.push(build_result(post));
    }

    #{
        series: results,
        has_more: results.len() >= limit,
        total: ()
    }
}

/// Get details for a specific image
fn get_series_details(id) {
    let url = `${API_URL}?page=dapi&s=post&q=index&json=1&id=${id}`;

    let body = http_get(url);
    let data = json_parse(body);

    // Empty check
    if data == () || type_of(data) != "array" || data.len() == 0 {
        return ();
    }

    let post = data[0];
    build_result(post)
}

/// Get chapters (not applicable for image posts, returns empty)
fn get_chapters(series_id) {
    []
}

/// Get pages for a "chapter" (the single image)
fn get_chapter_pages(chapter_id) {
    // For image posts, chapter_id is the post ID
    let url = `${API_URL}?page=dapi&s=post&q=index&json=1&id=${chapter_id}`;

    let body = http_get(url);
    let data = json_parse(body);

    // Empty check
    if data == () || type_of(data) != "array" || data.len() == 0 {
        return [];
    }

    let post = data[0];
    let file_url = "";
    if post.contains("file_url") {
        file_url = post["file_url"];
    }

    [
        #{
            index: 0,
            url: file_url,
            headers: #{},
            referer: ()
        }
    ]
}
