// Danbooru Add-on (Rhai)
// Provides Danbooru search and artwork browsing
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const DANBOORU_API = "https://danbooru.donmai.us";

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "danbooru-rhai",
        name: "Danbooru",
        base_url: DANBOORU_API,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["danbooru", "fanart", "anime"]
    }
}

/// Helper to build auth query string from credentials
fn build_auth_params(auth) {
    if auth == () {
        return "";
    }
    let username = auth["username"];
    let api_key = auth["api_key"];
    if username == () || api_key == () || username == "" || api_key == "" {
        return "";
    }
    `&login=${username}&api_key=${api_key}`
}

/// Helper to build series result from Danbooru post
fn build_result(post) {
    let post_id = post["id"].to_string();

    let is_video = false;
    let file_ext = post["file_ext"];
    if file_ext != () {
        is_video = file_ext == "webm" || file_ext == "mp4" || file_ext == "zip";
    }

    // Parse tags into array
    let tag_string = post["tag_string"];
    let tag_list = [];
    if tag_string != () {
        tag_list = tag_string.split(" ");
    }

    // Build title from character + copyright tags, or first tags
    let char_tags = post["tag_string_character"];
    let copy_tags = post["tag_string_copyright"];
    let title = "";

    if char_tags != () && char_tags != "" {
        title = char_tags.replace("_", " ");
    }
    if copy_tags != () && copy_tags != "" {
        if title != "" {
            title = title + " (" + copy_tags.replace("_", " ") + ")";
        } else {
            title = copy_tags.replace("_", " ");
        }
    }
    if title == "" {
        // Fallback to first 5 tags
        let count = 0;
        for tag in tag_list {
            if count < 5 {
                if title != "" {
                    title = title + ", ";
                }
                title = title + tag.replace("_", " ");
                count += 1;
            }
        }
    }

    // Get URLs
    let file_url = post["file_url"];
    let preview_url = post["preview_file_url"];
    let large_url = post["large_file_url"];

    if preview_url == () {
        preview_url = large_url;
    }
    if preview_url == () {
        preview_url = file_url;
    }

    #{
        id: post_id,
        title: title,
        alternate_titles: [],
        description: "Tags: " + tag_string,
        cover_url: preview_url,
        authors: [],
        artists: [],
        status: (),
        genres: [],
        tags: tag_list,
        year: (),
        content_rating: post["rating"],
        url: `${DANBOORU_API}/posts/${post_id}`,
        extra: #{
            file_url: file_url,
            large_url: large_url,
            preview_url: preview_url,
            width: post["image_width"],
            height: post["image_height"],
            score: post["score"],
            fav_count: post["fav_count"],
            is_video: is_video,
            source: post["source"],
            source_site: "danbooru"
        }
    }
}

/// Search Danbooru for content matching tags
fn search_series(query, page, auth) {
    let limit = 40;
    let page_num = page + 1; // Danbooru uses 1-indexed pages
    let search_tags = url_encode(query);
    let auth_params = build_auth_params(auth);

    let url = `${DANBOORU_API}/posts.json?tags=${search_tags}&page=${page_num}&limit=${limit}${auth_params}`;

    let response_text = http_get(url);

    // Handle empty results
    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let posts = json_parse(response_text);

    if posts == () || type_of(posts) != "array" || posts.len() == 0 {
        return #{ series: [], has_more: false, total: () };
    }

    let results = [];
    for post in posts {
        // Skip deleted posts
        if post["is_deleted"] != true {
            results.push(build_result(post));
        }
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
    let page_num = page + 1;
    let auth_params = build_auth_params(auth);

    let url = `${DANBOORU_API}/posts.json?page=${page_num}&limit=${limit}${auth_params}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let posts = json_parse(response_text);

    if posts == () || type_of(posts) != "array" || posts.len() == 0 {
        return #{ series: [], has_more: false, total: () };
    }

    let results = [];
    for post in posts {
        if post["is_deleted"] != true {
            results.push(build_result(post));
        }
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
    let url = `${DANBOORU_API}/posts/${post_id}.json?${auth_params}`;

    let response_text = http_get(url);

    if response_text == "" {
        return ();
    }

    let post = json_parse(response_text);

    if post == () || post["id"] == () {
        return ();
    }

    build_result(post)
}

/// Get chapters (not applicable for image posts, returns empty)
fn get_chapters(series_id, auth) {
    []
}

/// Get pages for a "chapter" (the single image/video)
fn get_chapter_pages(chapter_id, auth) {
    let auth_params = build_auth_params(auth);
    let url = `${DANBOORU_API}/posts/${chapter_id}.json?${auth_params}`;

    let response_text = http_get(url);

    if response_text == "" {
        return [];
    }

    let post = json_parse(response_text);

    if post == () || post["id"] == () {
        return [];
    }

    let file_url = post["file_url"];
    if file_url == () {
        file_url = post["large_file_url"];
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

/// Get popular tags
fn get_popular_tags() {
    [
        "1girl",
        "solo",
        "highres",
        "long_hair",
        "looking_at_viewer",
        "breasts",
        "smile",
        "open_mouth",
        "blue_eyes",
        "simple_background"
    ]
}
