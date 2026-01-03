// HypnoHub Add-on (Rhai)
// Provides HypnoHub search and artwork browsing
// Uses Gelbooru-compatible API
//
// WARNING: This addon provides access to adult content.
// Users must be 18+ years old to use this addon.
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const HYPNOHUB_API = "https://hypnohub.net/index.php";

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "hypnohub-rhai",
        name: "HypnoHub",
        base_url: HYPNOHUB_API,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["hypnohub", "hypnosis", "mind_control", "fanart", "anime"]
    }
}

/// Helper to build series result from HypnoHub post
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
        url: `https://hypnohub.net/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: post["sample_url"],
            width: post["width"],
            height: post["height"],
            score: post["score"],
            is_video: is_video,
            source: post["source"],
            source_site: "hypnohub"
        }
    }
}

/// Search HypnoHub for content matching tags
fn search_series(query, page, auth) {
    let limit = 40;
    let pid = page;
    let search_tags = url_encode(query);

    let url = `${HYPNOHUB_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${limit}`;

    let response_text = http_get(url);

    // Handle empty results
    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let data = json_parse(response_text);

    // Check if data is an array first (HypnoHub returns array directly)
    let posts = [];
    if type_of(data) == "array" {
        posts = data;
    } else if type_of(data) == "map" && data["post"] != () {
        posts = data["post"];
    }

    if posts.len() == 0 {
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

    let url = `${HYPNOHUB_API}?page=dapi&s=post&q=index&json=1&pid=${pid}&limit=${limit}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return #{ series: [], has_more: false, total: () };
    }

    let data = json_parse(response_text);

    // Check if data is an array first (HypnoHub returns array directly)
    let posts = [];
    if type_of(data) == "array" {
        posts = data;
    } else if type_of(data) == "map" && data["post"] != () {
        posts = data["post"];
    }

    if posts.len() == 0 {
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
    let url = `${HYPNOHUB_API}?page=dapi&s=post&q=index&json=1&id=${post_id}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return ();
    }

    let data = json_parse(response_text);

    // Check if data is an array first
    let posts = [];
    if type_of(data) == "array" {
        posts = data;
    } else if type_of(data) == "map" && data["post"] != () {
        posts = data["post"];
    }

    if posts.len() == 0 {
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
    let url = `${HYPNOHUB_API}?page=dapi&s=post&q=index&json=1&id=${chapter_id}`;

    let response_text = http_get(url);

    if response_text == "" || response_text == "[]" {
        return [];
    }

    let data = json_parse(response_text);

    // Check if data is an array first
    let posts = [];
    if type_of(data) == "array" {
        posts = data;
    } else if type_of(data) == "map" && data["post"] != () {
        posts = data["post"];
    }

    if posts.len() == 0 {
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

/// Tag autocomplete using HypnoHub's autocomplete API
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn tag_autocomplete(query, limit, auth) {
    if query == () || query == "" || query.len() < 2 {
        return [];
    }

    let encoded_query = url_encode(query);
    let url = `${HYPNOHUB_API}?page=autocomplete2&term=${encoded_query}&type=tag_query&limit=${limit}`;

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
            if item["type"] != () {
                tag_type = item["type"];
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

/// Get popular tags for HypnoHub (hypnosis-themed)
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn get_popular_tags(limit, auth) {
    let popular = [
        #{ tag: "hypnosis", count: 100000, tag_type: "general" },
        #{ tag: "mind_control", count: 90000, tag_type: "general" },
        #{ tag: "spiral", count: 80000, tag_type: "general" },
        #{ tag: "empty_eyes", count: 70000, tag_type: "general" },
        #{ tag: "glowing_eyes", count: 65000, tag_type: "general" },
        #{ tag: "pendulum", count: 60000, tag_type: "general" },
        #{ tag: "spiral_eyes", count: 55000, tag_type: "general" },
        #{ tag: "blank_expression", count: 50000, tag_type: "general" },
        #{ tag: "hypnotized", count: 48000, tag_type: "general" },
        #{ tag: "brainwashing", count: 45000, tag_type: "general" },
        #{ tag: "drool", count: 42000, tag_type: "general" },
        #{ tag: "trance", count: 40000, tag_type: "general" },
        #{ tag: "1girl", count: 38000, tag_type: "general" },
        #{ tag: "solo", count: 36000, tag_type: "general" },
        #{ tag: "breasts", count: 34000, tag_type: "general" },
        #{ tag: "long_hair", count: 32000, tag_type: "general" },
        #{ tag: "looking_at_viewer", count: 30000, tag_type: "general" },
        #{ tag: "symbol_in_eyes", count: 28000, tag_type: "general" },
        #{ tag: "heart_eyes", count: 26000, tag_type: "general" },
        #{ tag: "kneeling", count: 24000, tag_type: "general" }
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
