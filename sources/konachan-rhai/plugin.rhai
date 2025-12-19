// Konachan Add-on (Rhai)
// Provides Konachan search and anime wallpaper/artwork browsing
//
// WARNING: This addon provides access to adult content.
// Users must be 18+ years old to use this addon.
//
// Konachan API is based on Moebooru (Danbooru fork)
// API: https://konachan.com/post.json?tags=TAG&page=1&limit=40
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const KONACHAN_API = "https://konachan.com";

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "konachan-rhai",
        name: "Konachan",
        base_url: KONACHAN_API,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["konachan", "wallpaper", "anime", "artwork"]
    }
}

/// Helper to build series result from Konachan post
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
            title_tags.push(tag.replace("_", " "));
            count += 1;
        }
    }
    let title = title_tags.join(", ");

    // Get URLs - Konachan uses preview_url, sample_url, file_url
    let preview_url = post["preview_url"];
    let sample_url = post["sample_url"];

    if preview_url == () {
        preview_url = sample_url;
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
        url: `${KONACHAN_API}/post/show/${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: sample_url,
            preview_url: preview_url,
            width: post["width"],
            height: post["height"],
            score: post["score"],
            is_video: is_video,
            source: post["source"],
            source_site: "konachan"
        }
    }
}

/// Search Konachan for content matching tags
fn search_series(query, page, auth) {
    let limit = 40;
    let page_num = page + 1; // Konachan uses 1-indexed pages
    let search_tags = url_encode(query);

    let url = `${KONACHAN_API}/post.json?tags=${search_tags}&page=${page_num}&limit=${limit}`;

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
    let page_num = page + 1;

    let url = `${KONACHAN_API}/post.json?page=${page_num}&limit=${limit}`;

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
    let url = `${KONACHAN_API}/post.json?tags=id:${post_id}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return ();
    }

    let posts = json_parse(response_text);

    if posts == () || type_of(posts) != "array" || posts.len() == 0 {
        return ();
    }

    build_result(posts[0])
}

/// Get chapters (not applicable for image posts, returns empty)
fn get_chapters(series_id, auth) {
    []
}

/// Get pages for a "chapter" (the single image/video)
fn get_chapter_pages(chapter_id, auth) {
    let url = `${KONACHAN_API}/post.json?tags=id:${chapter_id}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let posts = json_parse(response_text);

    if posts == () || type_of(posts) != "array" || posts.len() == 0 {
        return [];
    }

    let post = posts[0];
    let file_url = post["file_url"];

    if file_url == () {
        file_url = post["sample_url"];
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

/// Tag autocomplete for search suggestions
fn tag_autocomplete(query, auth) {
    if query == "" || query.len() < 2 {
        return [];
    }

    let encoded_query = url_encode(query);
    let url = `${KONACHAN_API}/tag.json?name=${encoded_query}*&order=count&limit=10`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let tags = json_parse(response_text);

    if tags == () || type_of(tags) != "array" {
        return [];
    }

    let results = [];
    for tag in tags {
        let name = tag["name"];
        if name != () {
            results.push(#{
                name: name,
                count: tag["count"]
            });
        }
    }

    results
}

/// Get popular tags
fn get_popular_tags() {
    [
        "highres",
        "long_hair",
        "breasts",
        "cleavage",
        "dress",
        "thighhighs",
        "blue_eyes",
        "blonde_hair",
        "sword",
        "landscape"
    ]
}
