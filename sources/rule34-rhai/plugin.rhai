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

    // Auth context from Django has credentials nested: auth.credentials.user_id
    // But some calls pass credentials directly: auth.user_id
    let user_id = ();
    let api_key = ();

    // Try nested credentials first (from Django auth context)
    if auth["credentials"] != () {
        let creds = auth["credentials"];
        user_id = creds["user_id"];
        api_key = creds["api_key"];
    }

    // Fallback to direct fields (for direct calls)
    if user_id == () {
        user_id = auth["user_id"];
    }
    if api_key == () {
        api_key = auth["api_key"];
    }

    if user_id == () || api_key == () {
        return "";
    }
    `&user_id=${user_id}&api_key=${api_key}`
}

/// Join array elements with a separator (Rhai doesn't have built-in join)
fn join_array(arr, separator) {
    if arr.len() == 0 {
        return "";
    }
    let result = "";
    let first = true;
    for item in arr {
        if first {
            result = item.to_string();
            first = false;
        } else {
            result = result + separator + item.to_string();
        }
    }
    result
}

/// Check if response is an error message instead of JSON data
fn is_error_response(response_text) {
    if response_text == () || response_text == "" {
        return true;
    }
    // Check for common error indicators
    if response_text.contains("Missing authentication") {
        return true;
    }
    if response_text.contains("error") && !response_text.starts_with("[") {
        return true;
    }
    // Valid JSON array responses start with [
    if !response_text.starts_with("[") {
        return true;
    }
    false
}

/// Helper to build series result from Rule34 post
fn build_result(post) {
    // Validate post is a proper map object
    if post == () {
        return ();
    }

    let post_id_val = post["id"];
    if post_id_val == () {
        return ();
    }
    let post_id = post_id_val.to_string();

    let is_video = false;
    let file_url = post["file_url"];

    if file_url != () {
        let lower_url = file_url.to_lower();
        is_video = lower_url.ends_with(".webm") || lower_url.ends_with(".mp4");
    }

    // Parse tags into array
    let tag_string = post["tags"];
    let tag_list = [];
    if tag_string != () && tag_string != "" {
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
    let title = join_array(title_tags, ", ");

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
/// settings is available as a global variable (injected by the scraper)
fn search_series(query, page, auth) {
    // Access settings from global scope (injected by scraper)
    let s = if settings != () { settings } else { #{} };
    let limit = get_limit_from_settings(s);

    // Apply tag filters from settings (include/exclude tags)
    let filtered_query = apply_tag_filters(query, s);

    // Build the API URL - pid is 0-indexed in Rule34 API
    let pid = page;
    let search_tags = url_encode(filtered_query);
    let auth_params = build_auth_params(auth);

    // Check if auth is provided - Rule34 API requires authentication
    if auth_params == "" {
        return #{
            series: [],
            has_more: false,
            total: (),
            error: "Rule34 requires authentication. Please add your API credentials in the extension settings."
        };
    }

    let url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${limit}${auth_params}`;

    let response_text = http_get(url);

    // Check for error responses before parsing
    if is_error_response(response_text) {
        return #{
            series: [],
            has_more: false,
            total: (),
            error: "Authentication required or API error. Please check your Rule34 credentials."
        };
    }

    let posts = json_parse(response_text);

    if posts == () {
        return #{ series: [], has_more: false, total: () };
    }

    // Check if posts is an array
    if type_of(posts) != "array" {
        return #{ series: [], has_more: false, total: () };
    }

    if posts.len() == 0 {
        return #{ series: [], has_more: false, total: () };
    }

    let results = [];
    for post in posts {
        let result = build_result(post);
        if result != () {
            results.push(result);
        }
    }

    #{
        series: results,
        has_more: results.len() >= limit,
        total: ()
    }
}

/// Get latest updates (used for browse)
/// settings parameter contains user addon settings (always_include_tags, always_exclude_tags, etc.)
fn get_latest_updates(page, auth) {
    // Access settings from global scope (injected by scraper)
    let s = if settings != () { settings } else { #{} };
    let limit = get_limit_from_settings(s);
    let pid = page;
    let auth_params = build_auth_params(auth);

    // Check if auth is provided - Rule34 API requires authentication
    if auth_params == "" {
        return #{
            series: [],
            has_more: false,
            total: (),
            error: "Rule34 requires authentication. Please add your API credentials in the extension settings."
        };
    }

    // Apply tag filters for browse (empty query with filters)
    let filtered_query = apply_tag_filters("", s);
    let tags_param = "";
    if filtered_query != "" {
        tags_param = "&tags=" + url_encode(filtered_query);
    }

    let url = `${RULE34_API}?page=dapi&s=post&q=index&json=1&pid=${pid}&limit=${limit}${tags_param}${auth_params}`;

    let response_text = http_get(url);

    // Check for error responses before parsing
    if is_error_response(response_text) {
        return #{
            series: [],
            has_more: false,
            total: (),
            error: "Authentication required or API error. Please check your Rule34 credentials."
        };
    }

    let posts = json_parse(response_text);

    if posts == () {
        return #{ series: [], has_more: false, total: () };
    }

    // Check if posts is an array
    if type_of(posts) != "array" {
        return #{ series: [], has_more: false, total: () };
    }

    if posts.len() == 0 {
        return #{ series: [], has_more: false, total: () };
    }

    let results = [];
    for post in posts {
        let result = build_result(post);
        if result != () {
            results.push(result);
        }
    }

    #{
        series: results,
        has_more: results.len() >= limit,
        total: ()
    }
}

/// Get image details by ID
fn get_series(post_id, auth) {
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

/// Tag autocomplete - search for tags matching query
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn tag_autocomplete(query, limit, auth) {
    if query == () || query == "" {
        return [];
    }

    // Rule34 has an autocomplete endpoint
    let encoded_query = url_encode(query);
    let url = `https://api.rule34.xxx/autocomplete.php?q=${encoded_query}`;

    let response_text = http_get(url);

    if response_text == () || response_text == "" {
        return [];
    }

    // Response is array of tag strings like ["tag1", "tag2", ...]
    let tags = json_parse(response_text);

    if tags == () || type_of(tags) != "array" {
        return [];
    }

    // Convert to TagInfo format and apply limit
    let results = [];
    let count = 0;
    for tag in tags {
        if count >= limit {
            break;
        }
        // Rule34 autocomplete returns objects with label and value
        let tag_name = "";
        if type_of(tag) == "map" {
            tag_name = tag["value"];
            if tag_name == () {
                tag_name = tag["label"];
            }
        } else {
            tag_name = tag.to_string();
        }

        if tag_name != () && tag_name != "" {
            results.push(#{
                tag: tag_name,
                count: (),
                tag_type: "general"
            });
            count += 1;
        }
    }

    results
}

/// Get popular tags (commonly used tags on Rule34)
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn get_popular_tags(limit, auth) {
    // Rule34 doesn't have a dedicated popular tags API
    // Return commonly used tags with estimated popularity
    let popular = [
        #{ tag: "solo", count: 2500000, tag_type: "general" },
        #{ tag: "1girl", count: 2000000, tag_type: "general" },
        #{ tag: "breasts", count: 1800000, tag_type: "general" },
        #{ tag: "ass", count: 1500000, tag_type: "general" },
        #{ tag: "looking_at_viewer", count: 1200000, tag_type: "general" },
        #{ tag: "nude", count: 1100000, tag_type: "general" },
        #{ tag: "large_breasts", count: 1000000, tag_type: "general" },
        #{ tag: "blush", count: 900000, tag_type: "general" },
        #{ tag: "smile", count: 850000, tag_type: "general" },
        #{ tag: "long_hair", count: 800000, tag_type: "general" },
        #{ tag: "female", count: 750000, tag_type: "general" },
        #{ tag: "nipples", count: 700000, tag_type: "general" },
        #{ tag: "pussy", count: 650000, tag_type: "general" },
        #{ tag: "open_mouth", count: 600000, tag_type: "general" },
        #{ tag: "thighs", count: 550000, tag_type: "general" },
        #{ tag: "big_breasts", count: 500000, tag_type: "general" },
        #{ tag: "anime", count: 480000, tag_type: "meta" },
        #{ tag: "short_hair", count: 450000, tag_type: "general" },
        #{ tag: "video_games", count: 420000, tag_type: "copyright" },
        #{ tag: "highres", count: 400000, tag_type: "meta" }
    ];

    // Apply limit
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

/// Parse comma-separated tag string into array of trimmed tags
fn parse_tag_list(tag_string) {
    if tag_string == () || tag_string == "" {
        return [];
    }
    let tags = [];
    let parts = tag_string.split(",");
    for part in parts {
        let trimmed = part.trim();
        if trimmed != "" {
            // Convert spaces to underscores for booru format
            let tag = trimmed.to_lower().replace(" ", "_");
            tags.push(tag);
        }
    }
    tags
}

/// Build query with included/excluded tags from settings
/// Returns the modified query string with tag filters applied
fn apply_tag_filters(query, settings) {
    if settings == () {
        return query;
    }

    let result_query = query;

    // Get always include tags
    let include_tags_str = settings["always_include_tags"];
    let include_tags = parse_tag_list(include_tags_str);

    // Get always exclude tags
    let exclude_tags_str = settings["always_exclude_tags"];
    let exclude_tags = parse_tag_list(exclude_tags_str);

    // Add safe mode exclusions if enabled
    let safe_mode = settings["safe_mode"];
    if safe_mode == true {
        // Common extreme content tags to exclude in safe mode
        let safe_exclude = ["gore", "guro", "scat", "torture", "death", "necrophilia", "vore", "snuff"];
        for tag in safe_exclude {
            let already_excluded = false;
            for existing in exclude_tags {
                if existing == tag {
                    already_excluded = true;
                    break;
                }
            }
            if !already_excluded {
                exclude_tags.push(tag);
            }
        }
    }

    // Append included tags to query
    for tag in include_tags {
        if result_query != "" {
            result_query = result_query + " " + tag;
        } else {
            result_query = tag;
        }
    }

    // Append excluded tags with minus prefix
    for tag in exclude_tags {
        if result_query != "" {
            result_query = result_query + " -" + tag;
        } else {
            result_query = "-" + tag;
        }
    }

    result_query
}

/// Get limit from settings or use default
fn get_limit_from_settings(settings) {
    if settings == () {
        return 40;
    }
    let limit = settings["default_limit"];
    if limit == () || limit < 10 {
        return 40;
    }
    if limit > 100 {
        return 100;
    }
    limit
}
