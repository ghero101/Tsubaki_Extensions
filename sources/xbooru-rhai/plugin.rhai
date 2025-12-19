// XBooru Add-on (Rhai)
// Provides XBooru search and fan art browsing
// Uses Gelbooru-compatible API
//
// WARNING: This addon provides access to adult content.
// Users must be 18+ years old to use this addon.
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const XBOORU_API = "https://xbooru.com/index.php";

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "xbooru-rhai",
        name: "XBooru",
        base_url: XBOORU_API,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["xbooru", "fanart", "anime"]
    }
}

/// Helper to build series result from XBooru post
fn build_result(post) {
    let post_id = post["id"].to_string();

    let is_video = false;
    let file_url = post["file_url"];

    if file_url != () {
        let lower_url = file_url.to_lower();
        is_video = lower_url.ends_with(".webm") || lower_url.ends_with(".mp4");
    }

    // Parse tags into array
    let tag_string = post["tags"];
    let tag_list = [];
    if tag_string != () {
        tag_list = tag_string.split(" ");
    }

    // Build title from first 5 tags
    let title_tags = [];
    let count = 0;
    for tag in tag_list {
        if count < 5 {
            title_tags.push(tag);
            count += 1;
        }
    }
    let title = title_tags.join(", ");

    #{
        id: post_id,
        title: title,
        alternate_titles: [],
        description: "Tags: " + tag_string,
        cover_url: post["preview_url"],
        authors: [],
        artists: [],
        status: (),
        genres: [],
        tags: tag_list,
        year: (),
        content_rating: post["rating"],
        url: `https://xbooru.com/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: post["sample_url"],
            width: post["width"],
            height: post["height"],
            score: post["score"],
            is_video: is_video,
            source: post["source"],
            source_site: "xbooru"
        }
    }
}

/// Search XBooru for content matching tags
fn search_series(query, page, auth) {
    let limit = 40;
    let pid = page;
    let search_tags = url_encode(query);

    let url = `${XBOORU_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${limit}`;

    let response_text = http_get(url);

    // Handle empty results
    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let data = json_parse(response_text);

    // XBooru returns array directly or { post: [...] } format
    let posts = [];
    if data["post"] != () {
        posts = data["post"];
    } else if type_of(data) == "array" {
        posts = data;
    }

    if posts == () || posts.len == () || posts.len() == 0 {
        return #{ series: [], has_more: false, total: () };
    }

    let results = [];
    for post in posts {
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
    let pid = page;

    let url = `${XBOORU_API}?page=dapi&s=post&q=index&json=1&pid=${pid}&limit=${limit}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let data = json_parse(response_text);

    let posts = [];
    if data["post"] != () {
        posts = data["post"];
    } else if type_of(data) == "array" {
        posts = data;
    }

    if posts == () || posts.len == () || posts.len() == 0 {
        return #{ series: [], has_more: false, total: () };
    }

    let results = [];
    for post in posts {
        results.push(build_result(post));
    }

    #{
        series: results,
        has_more: results.len() >= limit,
        total: ()
    }
}

/// Get image details by ID
fn get_series_details(post_id, auth) {
    let url = `${XBOORU_API}?page=dapi&s=post&q=index&json=1&id=${post_id}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return ();
    }

    let data = json_parse(response_text);

    let posts = [];
    if data["post"] != () {
        posts = data["post"];
    } else if type_of(data) == "array" {
        posts = data;
    }

    if posts == () || posts.len == () || posts.len() == 0 {
        return ();
    }

    let post = posts[0];
    build_result(post)
}

/// Get chapters (not applicable for image posts, returns empty)
fn get_chapters(series_id, auth) {
    []
}

/// Get pages for a "chapter" (the single image/video)
fn get_chapter_pages(chapter_id, auth) {
    let url = `${XBOORU_API}?page=dapi&s=post&q=index&json=1&id=${chapter_id}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let data = json_parse(response_text);

    let posts = [];
    if data["post"] != () {
        posts = data["post"];
    } else if type_of(data) == "array" {
        posts = data;
    }

    if posts == () || posts.len == () || posts.len() == 0 {
        return [];
    }

    let post = posts[0];
    let file_url = post["file_url"];

    [
        #{
            index: 0,
            url: file_url,
            headers: #{},
            referer: ()
        }
    ]
}

/// Tag autocomplete using XBooru's autocomplete API
fn tag_autocomplete(query, auth) {
    if query == "" || query.len() < 2 {
        return [];
    }

    let encoded_query = url_encode(query);
    let url = `${XBOORU_API}?page=autocomplete2&term=${encoded_query}&type=tag_query&limit=10`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let data = json_parse(response_text);

    if type_of(data) != "array" {
        return [];
    }

    let results = [];
    for item in data {
        let tag_name = "";
        let tag_count = 0;

        // Handle different response formats
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
        } else if type_of(item) == "string" {
            tag_name = item;
        }

        if tag_name != "" {
            results.push(#{
                name: tag_name,
                count: tag_count
            });
        }
    }

    results
}

/// Get popular tags
fn get_popular_tags() {
    [
        "1girl",
        "solo",
        "breasts",
        "long_hair",
        "looking_at_viewer",
        "blush",
        "smile",
        "open_mouth",
        "blue_eyes",
        "large_breasts",
        "highres",
        "short_hair",
        "blonde_hair",
        "black_hair",
        "thighhighs",
        "simple_background",
        "nipples",
        "nude",
        "pussy",
        "ass"
    ]
}
