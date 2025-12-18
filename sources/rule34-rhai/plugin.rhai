// Adult Content Provider Add-on (Rhai)
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

const RULE34_API = "https://api.rule34.xxx/index.php";
const GELBOORU_API = "https://gelbooru.com/index.php";

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "adult-content-rhai",
        name: "Adult Content Provider",
        base_url: RULE34_API,
        language: "en",
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["rule34", "fanart"]
    }
}

/// Search Rule34 for content matching tags
/// tags: space-separated tags (use underscores for multi-word tags)
/// page: page number (0-indexed)
/// limit: results per page (max 100)
fn search_rule34(tags, page, limit, settings) {
    // Build the API URL
    let pid = page;
    let safe_limit = if limit > 100 { 100 } else { limit };

    // Exclude extreme content if safe_mode is enabled
    let search_tags = tags;
    if settings.contains("safe_mode") && settings["safe_mode"] == true {
        search_tags = `${tags} -gore -scat -guro -vore`;
    }

    // Exclude videos if disabled
    if settings.contains("video_enabled") && settings["video_enabled"] == false {
        search_tags = `${search_tags} -video -animated -webm -mp4`;
    }

    let url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${safe_limit}`;

    let response_text = http_get(url);

    // Handle empty results
    if response_text == "" || response_text == "[]" {
        return #{ results: [], has_more: false, total: 0, page: page, query: tags };
    }

    let posts = json_parse(response_text);

    if posts == () || posts.len() == 0 {
        return #{ results: [], has_more: false, total: 0, page: page, query: tags };
    }

    let results = [];

    for post in posts {
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

        results.push(#{
            id: post["id"],
            preview_url: post["preview_url"],
            sample_url: post["sample_url"],
            file_url: file_url,
            width: post["width"],
            height: post["height"],
            tags: tag_list,
            source: post["source"],
            rating: post["rating"],
            score: post["score"],
            is_video: is_video,
            created_at: post["created_at"],
            source_site: "rule34"
        });
    }

    // Determine if there are more results
    let has_more = results.len() >= safe_limit;

    #{
        results: results,
        has_more: has_more,
        total: -1,  // Rule34 API doesn't provide total count easily
        page: page,
        query: tags
    }
}

/// Search Gelbooru for content (alternative source)
fn search_gelbooru(tags, page, limit, settings) {
    let pid = page;
    let safe_limit = if limit > 100 { 100 } else { limit };

    let search_tags = tags;
    if settings.contains("safe_mode") && settings["safe_mode"] == true {
        search_tags = `${tags} -gore -scat -guro -vore`;
    }

    let url = `${GELBOORU_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${safe_limit}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return #{ results: [], has_more: false, total: 0, page: page, query: tags };
    }

    let data = json_parse(response_text);

    // Gelbooru returns { post: [...], @attributes: {...} }
    let posts = [];
    if data.contains("post") {
        posts = data["post"];
    } else if data.is_array() {
        posts = data;
    }

    if posts.len() == 0 {
        return #{ results: [], has_more: false, total: 0, page: page, query: tags };
    }

    let results = [];

    for post in posts {
        let is_video = false;
        let file_url = post["file_url"];

        if file_url != () {
            let lower_url = file_url.to_lower();
            is_video = lower_url.ends_with(".webm") || lower_url.ends_with(".mp4");
        }

        let tag_string = post["tags"];
        let tag_list = [];
        if tag_string != () {
            tag_list = tag_string.split(" ");
        }

        results.push(#{
            id: post["id"],
            preview_url: post["preview_url"],
            sample_url: post["sample_url"],
            file_url: file_url,
            width: post["width"],
            height: post["height"],
            tags: tag_list,
            source: post["source"],
            rating: post["rating"],
            score: post["score"],
            is_video: is_video,
            created_at: post["created_at"],
            source_site: "gelbooru"
        });
    }

    let has_more = results.len() >= safe_limit;
    let total = -1;

    if data.contains("@attributes") {
        let attrs = data["@attributes"];
        if attrs.contains("count") {
            total = attrs["count"];
        }
    }

    #{
        results: results,
        has_more: has_more,
        total: total,
        page: page,
        query: tags
    }
}

/// Get popular/trending tags
fn get_popular_tags(limit, settings) {
    // Rule34 doesn't have a direct trending API
    // Return commonly used character/series tags
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

/// Get image details by ID
fn get_post_details(post_id, source_site, settings) {
    let url = "";

    if source_site == "gelbooru" {
        url = `${GELBOORU_API}?page=dapi&s=post&q=index&json=1&id=${post_id}`;
    } else {
        // Default to rule34
        url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&id=${post_id}`;
    }

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return ();
    }

    let data = json_parse(response_text);
    let post = ();

    if data.is_array() && data.len() > 0 {
        post = data[0];
    } else if data.contains("post") && data["post"].len() > 0 {
        post = data["post"][0];
    }

    if post == () {
        return ();
    }

    let is_video = false;
    let file_url = post["file_url"];

    if file_url != () {
        let lower_url = file_url.to_lower();
        is_video = lower_url.ends_with(".webm") || lower_url.ends_with(".mp4");
    }

    let tag_string = post["tags"];
    let tag_list = [];
    if tag_string != () {
        tag_list = tag_string.split(" ");
    }

    #{
        id: post["id"],
        preview_url: post["preview_url"],
        sample_url: post["sample_url"],
        file_url: file_url,
        width: post["width"],
        height: post["height"],
        tags: tag_list,
        source: post["source"],
        rating: post["rating"],
        score: post["score"],
        is_video: is_video,
        created_at: post["created_at"],
        source_site: source_site
    }
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

/// Search for content related to a manga/comic series
fn search_series_content(series_name, page, limit, settings) {
    let tag = series_to_tag(series_name);
    search_rule34(tag, page, limit, settings)
}

/// Main search function - dispatches to appropriate source
fn search(query, page, settings) {
    let limit = 40;
    if settings.contains("default_limit") {
        limit = settings["default_limit"];
    }

    let source = "rule34";
    if settings.contains("source") {
        source = settings["source"];
    }

    if source == "gelbooru" {
        search_gelbooru(query, page, limit, settings)
    } else {
        search_rule34(query, page, limit, settings)
    }
}

/// Browse latest content
fn browse(page, settings) {
    search("", page, settings)
}
