// Safebooru Extension
// Searches and retrieves safe-for-work anime artwork from Safebooru
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
        id: "safebooru-rhai",
        name: "Safebooru",
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
fn search_series(query, page, auth) {
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

/// Tag autocomplete - search for tags matching query
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn tag_autocomplete(query, limit, auth) {
    if query == () || query == "" || query.len() < 2 {
        return [];
    }

    let encoded_query = url_encode(query);
    let url = `${API_URL}?page=autocomplete2&term=${encoded_query}&type=tag_query&limit=${limit}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let data = json_parse(response_text);

    if type_of(data) != "array" {
        return [];
    }

    let results = [];
    let count = 0;
    for item in data {
        if count >= limit {
            break;
        }
        let tag_name = "";
        let tag_count = 0;
        let tag_type = "general";

        if type_of(item) == "map" {
            if item["value"] != () {
                tag_name = item["value"];
            } else if item["label"] != () {
                tag_name = item["label"];
            } else if item["name"] != () {
                tag_name = item["name"];
            }
            if item["count"] != () {
                tag_count = item["count"];
            } else if item["post_count"] != () {
                tag_count = item["post_count"];
            }
            if item["type"] != () {
                tag_type = item["type"];
            } else if item["category"] != () {
                tag_type = item["category"];
            }
        } else if type_of(item) == "string" {
            tag_name = item;
        }

        if tag_name != "" {
            results.push(#{
                tag: tag_name,
                count: tag_count,
                tag_type: tag_type
            });
            count += 1;
        }
    }

    results
}

/// Get popular tags
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn get_popular_tags(limit, auth) {
    let popular = [
        #{ tag: "1girl", count: 3000000, tag_type: "general" },
        #{ tag: "solo", count: 2500000, tag_type: "general" },
        #{ tag: "long_hair", count: 2000000, tag_type: "general" },
        #{ tag: "highres", count: 1800000, tag_type: "meta" },
        #{ tag: "looking_at_viewer", count: 1600000, tag_type: "general" },
        #{ tag: "smile", count: 1500000, tag_type: "general" },
        #{ tag: "short_hair", count: 1400000, tag_type: "general" },
        #{ tag: "blue_eyes", count: 1300000, tag_type: "general" },
        #{ tag: "open_mouth", count: 1200000, tag_type: "general" },
        #{ tag: "blonde_hair", count: 1100000, tag_type: "general" },
        #{ tag: "simple_background", count: 1000000, tag_type: "general" },
        #{ tag: "black_hair", count: 950000, tag_type: "general" },
        #{ tag: "multiple_girls", count: 900000, tag_type: "general" },
        #{ tag: "brown_hair", count: 850000, tag_type: "general" },
        #{ tag: "thighhighs", count: 800000, tag_type: "general" },
        #{ tag: "original", count: 750000, tag_type: "copyright" },
        #{ tag: "white_background", count: 700000, tag_type: "general" },
        #{ tag: "skirt", count: 650000, tag_type: "general" },
        #{ tag: "dress", count: 600000, tag_type: "general" },
        #{ tag: "blush", count: 550000, tag_type: "general" }
    ];

    let results = [];
    let count = 0;
    for tag_info in popular {
        if count >= limit {
            break;
        }
        results.push(tag_info);
        count += 1;
    }

    results
}
