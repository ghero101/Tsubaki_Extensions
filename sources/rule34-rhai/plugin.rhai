// Rule34 Add-on (Rhai)
// Provides Rule34 search and fan art management
//
// WARNING: This addon provides access to explicit adult content.
// Users must be 18+ years old to use this addon.
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   json_parse(text) -> Dynamic
//   json_stringify(value) -> string
//   url_encode(text) -> string

const RULE34_API = "https://api.rule34.xxx/index.php";

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "rule34-rhai",
        name: "Rule34",
        base_url: RULE34_API,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: true,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["rule34", "fanart"]
    }
}

/// Helper to build auth query string from credentials
fn build_auth_params(auth) {
    if auth == () {
        return "";
    }
    let user_id = auth["user_id"];
    let api_key = auth["api_key"];
    if user_id == () || api_key == () {
        return "";
    }
    `&user_id=${user_id}&api_key=${api_key}`
}

/// Helper to build series result from Rule34 post
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
        url: `https://rule34.xxx/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: post["sample_url"],
            width: post["width"],
            height: post["height"],
            score: post["score"],
            is_video: is_video,
            source: post["source"],
            source_site: "rule34"
        }
    }
}

/// Search Rule34 for content matching tags
/// auth parameter contains user_id and api_key from credentials
fn search_series(query, page, auth) {
    let limit = 40;

    // Build the API URL - pid is 0-indexed in Rule34 API
    let pid = page;
    let search_tags = url_encode(query);
    let auth_params = build_auth_params(auth);

    let url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${limit}${auth_params}`;

    let response_text = http_get(url);

    // Handle empty results
    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let posts = json_parse(response_text);

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

    let url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&pid=${pid}&limit=${limit}${auth_params}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let posts = json_parse(response_text);

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
    let url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&id=${post_id}${auth_params}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return ();
    }

    let data = json_parse(response_text);

    if data == () || data.len == () || data.len() == 0 {
        return ();
    }

    let post = data[0];
    build_result(post)
}

/// Get chapters (not applicable for image posts, returns empty)
fn get_chapters(series_id, auth) {
    []
}

/// Get pages for a "chapter" (the single image/video)
fn get_chapter_pages(chapter_id, auth) {
    let auth_params = build_auth_params(auth);
    // For image posts, chapter_id is the post ID
    let url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&id=${chapter_id}${auth_params}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let data = json_parse(response_text);

    if data == () || data.len == () || data.len() == 0 {
        return [];
    }

    let post = data[0];
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

/// Get popular tags (commonly used tags)
fn get_popular_tags() {
    [
        "solo",
        "1girl",
        "breasts",
        "ass",
        "looking_at_viewer",
        "nude",
        "large_breasts",
        "blush",
        "smile",
        "long_hair"
    ]
}

/// Convert series name to Rule34 tag format
fn series_to_tag(series_name) {
    // Rule34 tags use underscores and lowercase
    let tag = series_name.to_lower();
    tag = tag.replace(" ", "_");
    tag = tag.replace("-", "_");
    tag = tag.replace("'", "");
    tag = tag.replace(":", "");
    tag
}
