// Gelbooru Add-on (Rhai)
// Provides Gelbooru search and fan art browsing
//
// WARNING: This addon provides access to adult content.
// Users must be 18+ years old to use this addon.
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const GELBOORU_API = "https://gelbooru.com/index.php";

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "gelbooru-rhai",
        name: "Gelbooru",
        base_url: GELBOORU_API,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["gelbooru", "fanart", "anime"]
    }
}

/// Helper to build auth query string from credentials
fn build_auth_params(auth) {
    if auth == () {
        return "";
    }
    let user_id = auth["user_id"];
    let api_key = auth["api_key"];
    if user_id == () || api_key == () || user_id == "" || api_key == "" {
        return "";
    }
    `&user_id=${user_id}&api_key=${api_key}`
}

/// Helper to build series result from Gelbooru post
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
        url: `https://gelbooru.com/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: post["sample_url"],
            width: post["width"],
            height: post["height"],
            score: post["score"],
            is_video: is_video,
            source: post["source"],
            source_site: "gelbooru"
        }
    }
}

/// Search Gelbooru for content matching tags
fn search_series(query, page, auth) {
    let limit = 40;
    let pid = page;
    let search_tags = url_encode(query);
    let auth_params = build_auth_params(auth);

    let url = `${GELBOORU_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${limit}${auth_params}`;

    let response_text = http_get(url);

    // Handle empty results
    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let data = json_parse(response_text);

    // Gelbooru returns { post: [...], ... } or { "@attributes": {...}, "post": [...] }
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
    let auth_params = build_auth_params(auth);

    let url = `${GELBOORU_API}?page=dapi&s=post&q=index&json=1&pid=${pid}&limit=${limit}${auth_params}`;

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
    let auth_params = build_auth_params(auth);
    let url = `${GELBOORU_API}?page=dapi&s=post&q=index&json=1&id=${post_id}${auth_params}`;

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
    let auth_params = build_auth_params(auth);
    let url = `${GELBOORU_API}?page=dapi&s=post&q=index&json=1&id=${chapter_id}${auth_params}`;

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
        "large_breasts"
    ]
}
