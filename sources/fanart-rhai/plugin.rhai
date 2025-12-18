// Fan Art Gallery Plugin for Safebooru
// Searches and retrieves safe-for-work fan art
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
        id: "fanart-rhai",
        name: "Fan Art Gallery",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Helper to build result from post data
fn build_result(post) {
    let post_id = post["id"].to_string();
    let directory = post["directory"];
    let image = post["image"];
    let tags_str = post["tags"];

    // Parse tags - split by space
    let tags = [];
    if tags_str != () {
        tags = tags_str.split(" ");
    }

    // Build title from first 5 tags
    let title_tags = [];
    let count = 0;
    for tag in tags {
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
        description: "Tags: " + tags_str,
        cover_url: `https://safebooru.org/thumbnails/${directory}/thumbnail_${image}`,
        authors: [],
        artists: [],
        status: (),
        genres: [],
        tags: tags,
        year: (),
        content_rating: "safe",
        url: `${BASE_URL}/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: `https://safebooru.org/images/${directory}/${image}`,
            width: post["width"],
            height: post["height"],
            source: post["source"]
        }
    }
}

/// Search for fan art by tags/series name
fn search(query, page) {
    // Build tag query - add rating:safe for safe content
    let tags = query + " rating:safe";
    let limit = 40;

    let url = `${API_URL}?page=dapi&s=post&q=index&json=1&limit=${limit}&pid=${page}&tags=` + url_encode(tags);

    let body = http_get(url);
    let data = json_parse(body);

    if data == () || data.len == () || data.len() == 0 {
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
fn get_latest_updates(page) {
    let limit = 40;
    let url = `${API_URL}?page=dapi&s=post&q=index&json=1&limit=${limit}&pid=${page}&tags=rating:safe`;

    let body = http_get(url);
    let data = json_parse(body);

    if data == () || data.len == () || data.len() == 0 {
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

    if data == () || data.len == () || data.len() == 0 {
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

    if data == () || data.len == () || data.len() == 0 {
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

    if data == () || data.len == () || data.len() == 0 {
        return [];
    }

    let post = data[0];
    let directory = post["directory"];
    let image = post["image"];

    [
        #{
            index: 0,
            url: `https://safebooru.org/images/${directory}/${image}`,
            headers: #{},
            referer: ()
        }
    ]
}
