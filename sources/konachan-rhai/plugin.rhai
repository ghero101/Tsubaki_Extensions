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
    let title = "";
    let first = true;
    for t in title_tags {
        if first {
            title = t;
            first = false;
        } else {
            title = title + ", " + t;
        }
    }

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
            let tag = trimmed.to_lower().replace(" ", "_");
            tags.push(tag);
        }
    }
    tags
}

/// Build query with rating filter and included/excluded tags from settings
fn apply_filters(query, s) {
    if s == () {
        return query;
    }

    let result_query = query;

    // Apply rating filter - Konachan uses rating:s, rating:q, rating:e
    let rating = s["rating_filter"];
    if rating != () && rating != "all" && rating != "" {
        result_query = result_query + " rating:" + rating;
    }

    // Get always include tags
    let include_tags = parse_tag_list(s["always_include_tags"]);
    for tag in include_tags {
        if result_query != "" {
            result_query = result_query + " " + tag;
        } else {
            result_query = tag;
        }
    }

    // Get always exclude tags
    let exclude_tags = parse_tag_list(s["always_exclude_tags"]);

    // Add safe mode exclusions if enabled
    let safe_mode = s["safe_mode"];
    if safe_mode == true {
        let safe_exclude = ["gore", "guro", "scat", "torture", "death", "vore", "snuff"];
        for tag in safe_exclude {
            let already = false;
            for existing in exclude_tags {
                if existing == tag { already = true; break; }
            }
            if !already {
                exclude_tags.push(tag);
            }
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

/// Search Konachan for content matching tags
fn search_series(query, page, auth) {
    let s = if settings != () { settings } else { #{} };
    let limit = 40;
    let page_num = page + 1; // Konachan uses 1-indexed pages
    let filtered_query = apply_filters(query, s);
    let search_tags = url_encode(filtered_query);

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
    let s = if settings != () { settings } else { #{} };
    let limit = 40;
    let page_num = page + 1;

    // Apply filters for browse
    let filtered_query = apply_filters("", s);
    let tags_param = "";
    if filtered_query != "" {
        tags_param = "&tags=" + url_encode(filtered_query);
    }

    let url = `${KONACHAN_API}/post.json?page=${page_num}&limit=${limit}${tags_param}`;

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
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn tag_autocomplete(query, limit, auth) {
    if query == () || query == "" || query.len() < 2 {
        return [];
    }

    let encoded_query = url_encode(query);
    let url = `${KONACHAN_API}/tag.json?name=${encoded_query}*&order=count&limit=${limit}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let tags = json_parse(response_text);

    if tags == () || type_of(tags) != "array" {
        return [];
    }

    let results = [];
    let count = 0;
    for tag in tags {
        if count >= limit {
            break;
        }
        let name = tag["name"];
        if name != () {
            // Konachan tag types: 0=general, 1=artist, 3=copyright, 4=character, 5=circle, 6=faults
            let tag_type_id = tag["tag_type"];
            let tag_type = "general";
            if tag_type_id == 1 { tag_type = "artist"; }
            else if tag_type_id == 3 { tag_type = "copyright"; }
            else if tag_type_id == 4 { tag_type = "character"; }
            else if tag_type_id == 5 { tag_type = "circle"; }

            results.push(#{
                tag: name,
                count: tag["count"],
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
        #{ tag: "highres", count: 500000, tag_type: "meta" },
        #{ tag: "long_hair", count: 450000, tag_type: "general" },
        #{ tag: "breasts", count: 400000, tag_type: "general" },
        #{ tag: "cleavage", count: 350000, tag_type: "general" },
        #{ tag: "dress", count: 320000, tag_type: "general" },
        #{ tag: "thighhighs", count: 300000, tag_type: "general" },
        #{ tag: "blue_eyes", count: 280000, tag_type: "general" },
        #{ tag: "blonde_hair", count: 260000, tag_type: "general" },
        #{ tag: "sword", count: 240000, tag_type: "general" },
        #{ tag: "landscape", count: 220000, tag_type: "general" },
        #{ tag: "sky", count: 200000, tag_type: "general" },
        #{ tag: "clouds", count: 180000, tag_type: "general" },
        #{ tag: "original", count: 160000, tag_type: "copyright" },
        #{ tag: "black_hair", count: 150000, tag_type: "general" },
        #{ tag: "water", count: 140000, tag_type: "general" },
        #{ tag: "ass", count: 130000, tag_type: "general" },
        #{ tag: "nipples", count: 120000, tag_type: "general" },
        #{ tag: "nude", count: 110000, tag_type: "general" },
        #{ tag: "sunset", count: 100000, tag_type: "general" },
        #{ tag: "building", count: 95000, tag_type: "general" }
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
