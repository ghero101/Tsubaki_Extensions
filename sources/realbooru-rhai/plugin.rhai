// RealBooru Add-on (Rhai)
// Provides RealBooru search and browsing via HTML scraping
// The JSON API is currently offline, so we scrape the website directly
//
// WARNING: This addon provides access to adult content.
// Users must be 18+ years old to use this addon.
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string
//   html_parse(html) -> Dynamic
//   html_select(html, selector) -> Array
//   html_select_first(html, selector) -> String
//   element_text(element) -> String
//   element_attr(element, name) -> String

const REALBOORU_BASE = "https://realbooru.com";
const REALBOORU_API = "https://realbooru.com/index.php";

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

/// Returns metadata about this content provider
fn get_source_info() {
    #{
        id: "realbooru-rhai",
        name: "RealBooru",
        base_url: REALBOORU_API,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: true,
        content_types: ["realbooru", "photography", "real"]
    }
}

/// Extract post ID from a URL or href attribute
fn extract_post_id(href) {
    if href == () || href == "" {
        return ();
    }
    // Match id=XXXXX in URL
    if href.contains("id=") {
        let parts = href.split("id=");
        if parts.len() > 1 {
            let id_part = parts[1];
            // Get everything before & if there is one
            if id_part.contains("&") {
                let id_parts = id_part.split("&");
                return id_parts[0];
            }
            return id_part;
        }
    }
    ()
}

/// Derive full image URL from thumbnail URL
fn derive_file_url(thumbnail_url) {
    if thumbnail_url == () || thumbnail_url == "" {
        return ();
    }

    // Pattern: /thumbnails/xx/yy/thumbnail_HASH.jpg -> /images/xx/yy/HASH.jpg
    // Note: Extension might be wrong, but get_chapter_pages will have correct one
    let file_url = thumbnail_url;

    // Replace /thumbnails/ with /images/
    if file_url.contains("/thumbnails/") {
        file_url = file_url.replace("/thumbnails/", "/images/");
    }

    // Remove thumbnail_ prefix from filename
    if file_url.contains("/thumbnail_") {
        file_url = file_url.replace("/thumbnail_", "/");
    }

    file_url
}

/// Build result from scraped HTML elements
fn build_scraped_result(post_id, preview_url, tags_string) {
    if post_id == () || post_id == "" {
        return ();
    }

    // Note: We don't derive file_url from thumbnail because Realbooru uses
    // different extensions (.jpg thumbnail vs .jpeg/.png/.webm full image).
    // The frontend should use get_chapter_pages for the actual image URL.

    // Parse tags into array - Realbooru uses comma-separated tags
    let tag_list = [];
    if tags_string != () && tags_string != "" {
        // Tags are comma-separated in title attribute: "1girl, ass, ..."
        let raw_tags = tags_string.split(", ");
        for tag in raw_tags {
            let trimmed = tag.trim();
            if trimmed != "" {
                tag_list.push(trimmed);
            }
        }
    }

    // Build title from first 5 tags
    let title_tags = [];
    let count = 0;
    for tag in tag_list {
        if count < 5 && tag != "" {
            title_tags.push(tag);
            count += 1;
        }
    }
    let title = join_array(title_tags, ", ");
    if title == "" {
        title = `Post ${post_id}`;
    }

    #{
        id: post_id,
        title: title,
        alternate_titles: [],
        description: "Tags: " + tags_string,
        cover_url: preview_url,
        authors: [],
        artists: [],
        status: (),
        genres: [],
        tags: tag_list,
        year: (),
        content_rating: "explicit",
        url: `${REALBOORU_BASE}/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: (),  // Use get_chapter_pages - thumbnail extension differs from actual
            sample_url: preview_url,
            width: (),
            height: (),
            score: (),
            is_video: false,
            source: (),
            source_site: "realbooru"
        }
    }
}

/// Helper to build series result from RealBooru JSON post (for API - kept for future use)
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
        url: `${REALBOORU_BASE}/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: post["sample_url"],
            width: post["width"],
            height: post["height"],
            score: post["score"],
            is_video: is_video,
            source: post["source"],
            source_site: "realbooru"
        }
    }
}

/// Parse post listings from HTML page
fn parse_listing_html(html_content) {
    let results = [];

    // RealBooru uses thumbnail elements in a grid
    // Look for thumbnail containers - typically class="thumbnail-preview" or similar
    let thumbnails = html_select(html_content, ".thumbnail-preview");

    if thumbnails.len() == 0 {
        // Try alternative selectors
        thumbnails = html_select(html_content, "span.thumb");
    }

    if thumbnails.len() == 0 {
        // Try image-list selector
        thumbnails = html_select(html_content, ".image-list span");
    }

    if thumbnails.len() == 0 {
        // Last resort - look for any links with post IDs
        // Realbooru structure: <a id="pXXXXXX" href="..."><img src="..." title="tags..." alt="Image: XXXXX"/></a>
        let links = html_select(html_content, "a[href*='page=post'][href*='s=view']");
        for link in links {
            let href = element_attr(link, "href");
            let post_id = extract_post_id(href);
            if post_id != () && post_id != "" {
                // Try to find an img within this link
                let img = html_select_first(link, "img");
                let preview_url = "";
                let tags = "";
                if img != "" {
                    preview_url = element_attr(img, "src");
                    // Tags are in the title attribute (comma-separated), alt just has "Image: XXXX"
                    tags = element_attr(img, "title");
                    if tags == () || tags == "" {
                        tags = element_attr(img, "alt");
                    }
                }

                let result = build_scraped_result(post_id, preview_url, tags);
                if result != () {
                    results.push(result);
                }
            }
        }
        return results;
    }

    // Process thumbnails
    for thumb in thumbnails {
        // Find the link inside the thumbnail
        let link = html_select_first(thumb, "a");
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        let post_id = extract_post_id(href);
        if post_id == () || post_id == "" {
            continue;
        }

        // Find the image inside the link
        let img = html_select_first(link, "img");
        let preview_url = "";
        let tags = "";

        if img != "" {
            preview_url = element_attr(img, "src");
            // Tags are often in the title or alt attribute
            tags = element_attr(img, "title");
            if tags == () || tags == "" {
                tags = element_attr(img, "alt");
            }
        }

        // Make sure preview URL is absolute
        if preview_url != "" && !preview_url.starts_with("http") {
            preview_url = REALBOORU_BASE + "/" + preview_url;
        }

        let result = build_scraped_result(post_id, preview_url, tags);
        if result != () {
            results.push(result);
        }
    }

    results
}

/// Search RealBooru for content matching tags (HTML scraping version)
fn search_series(query, page, auth) {
    let limit = 40;
    let pid = page;
    let search_tags = url_encode(query);

    // Build HTML listing URL
    let url = `${REALBOORU_API}?page=post&s=list&tags=${search_tags}&pid=${pid}`;

    let response_text = http_get(url);

    // Handle empty or error responses
    if response_text == "" {
        return #{ series: [], has_more: false, total: () };
    }

    // Check for Cloudflare or error page
    if response_text.contains("Just a moment") || response_text.contains("Checking your browser") {
        return #{
            series: [],
            has_more: false,
            total: (),
            error: "Cloudflare protection detected. Please try again later."
        };
    }

    // Parse the HTML
    let results = parse_listing_html(response_text);

    #{
        series: results,
        has_more: results.len() >= 20,  // Assume more if we got a decent number
        total: ()
    }
}

/// Get latest updates (used for browse) - HTML scraping version
fn get_latest_updates(page, auth) {
    let limit = 40;
    let pid = page;

    // Build HTML listing URL (no tags = latest)
    let url = `${REALBOORU_API}?page=post&s=list&pid=${pid}`;

    let response_text = http_get(url);

    // Handle empty or error responses
    if response_text == "" {
        return #{ series: [], has_more: false, total: () };
    }

    // Check for Cloudflare or error page
    if response_text.contains("Just a moment") || response_text.contains("Checking your browser") {
        return #{
            series: [],
            has_more: false,
            total: (),
            error: "Cloudflare protection detected. Please try again later."
        };
    }

    // Parse the HTML
    let results = parse_listing_html(response_text);

    #{
        series: results,
        has_more: results.len() >= 20,  // Assume more if we got a decent number
        total: ()
    }
}

/// Get image details by ID (HTML scraping version)
fn get_series_details(post_id, auth) {
    let url = `${REALBOORU_API}?page=post&s=view&id=${post_id}`;

    let response_text = http_get(url);

    if response_text == "" {
        return ();
    }

    // Find the main image
    let img = html_select_first(response_text, "#image");
    if img == "" {
        // Try alternative selector
        img = html_select_first(response_text, "img.image");
    }

    let file_url = "";
    if img != "" {
        file_url = element_attr(img, "src");
    }

    // Find tags from the sidebar
    let tag_list = [];
    let tag_elements = html_select(response_text, "#tag-list li a, .tag a");
    for tag_el in tag_elements {
        let tag_text = element_text(tag_el);
        if tag_text != "" && tag_text != "?" && !tag_text.starts_with("(") {
            tag_list.push(tag_text.trim());
        }
    }

    let tags_string = join_array(tag_list, " ");

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
    if title == "" {
        title = `Post ${post_id}`;
    }

    // Get sample/preview URL
    let preview_url = file_url;
    if preview_url != "" && preview_url.contains("/images/") {
        preview_url = preview_url.replace("/images/", "/thumbnails/");
    }

    // Check if it's a video
    let is_video = false;
    if file_url != "" {
        let lower_url = file_url.to_lower();
        is_video = lower_url.ends_with(".webm") || lower_url.ends_with(".mp4");
    }

    #{
        id: post_id,
        title: title,
        alternate_titles: [],
        description: "Tags: " + tags_string,
        cover_url: preview_url,
        authors: [],
        artists: [],
        status: (),
        genres: [],
        tags: tag_list,
        year: (),
        content_rating: "explicit",
        url: `${REALBOORU_BASE}/index.php?page=post&s=view&id=${post_id}`,
        extra: #{
            file_url: file_url,
            sample_url: preview_url,
            width: (),
            height: (),
            score: (),
            is_video: is_video,
            source: (),
            source_site: "realbooru"
        }
    }
}

/// Get chapters (not applicable for image posts, returns empty)
fn get_chapters(series_id, auth) {
    []
}

/// Get pages for a "chapter" (the single image/video) - HTML scraping version
fn get_chapter_pages(chapter_id, auth) {
    let url = `${REALBOORU_API}?page=post&s=view&id=${chapter_id}`;

    let response_text = http_get(url);

    if response_text == "" {
        return [];
    }

    // Find the main image
    let img = html_select_first(response_text, "#image");
    if img == "" {
        // Try alternative selector
        img = html_select_first(response_text, "img.image");
    }

    let file_url = "";
    if img != "" {
        file_url = element_attr(img, "src");
    }

    // Also check for original link
    if file_url == "" {
        let original_link = html_select_first(response_text, "a[href*='/images/']");
        if original_link != "" {
            file_url = element_attr(original_link, "href");
        }
    }

    if file_url == "" {
        return [];
    }

    // Make sure URL is absolute
    if !file_url.starts_with("http") {
        file_url = REALBOORU_BASE + "/" + file_url;
    }

    // Clean up double slashes in URL path (Realbooru has //images/ in their HTML)
    // Keep the double slash after protocol (https://)
    if file_url.contains("://") {
        let parts = file_url.split("://");
        if parts.len() >= 2 {
            let protocol = parts[0];
            let rest = parts[1];
            // Replace any remaining double slashes with single
            while rest.contains("//") {
                rest = rest.replace("//", "/");
            }
            file_url = protocol + "://" + rest;
        }
    }

    [
        #{
            index: 0,
            url: file_url,
            headers: #{},
            referer: `${REALBOORU_BASE}/index.php?page=post&s=view&id=${chapter_id}`
        }
    ]
}

/// Tag autocomplete using RealBooru's autocomplete API
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn tag_autocomplete(query, limit, auth) {
    if query == () || query == "" || query.len() < 2 {
        return [];
    }

    let encoded_query = url_encode(query);
    let url = `${REALBOORU_API}?page=autocomplete2&term=${encoded_query}&type=tag_query&limit=${limit}`;

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

/// Get popular tags
/// Returns array of TagInfo objects: [{tag: "...", count: N, tag_type: "..."}]
fn get_popular_tags(limit, auth) {
    let popular = [
        #{ tag: "1girl", count: 500000, tag_type: "general" },
        #{ tag: "solo", count: 450000, tag_type: "general" },
        #{ tag: "photo", count: 400000, tag_type: "meta" },
        #{ tag: "looking_at_viewer", count: 350000, tag_type: "general" },
        #{ tag: "blonde", count: 320000, tag_type: "general" },
        #{ tag: "brunette", count: 300000, tag_type: "general" },
        #{ tag: "lingerie", count: 280000, tag_type: "general" },
        #{ tag: "bikini", count: 260000, tag_type: "general" },
        #{ tag: "dress", count: 240000, tag_type: "general" },
        #{ tag: "outdoors", count: 220000, tag_type: "general" },
        #{ tag: "indoors", count: 200000, tag_type: "general" },
        #{ tag: "smile", count: 180000, tag_type: "general" },
        #{ tag: "posing", count: 160000, tag_type: "general" },
        #{ tag: "model", count: 150000, tag_type: "general" },
        #{ tag: "professional", count: 140000, tag_type: "meta" },
        #{ tag: "amateur", count: 130000, tag_type: "meta" },
        #{ tag: "selfie", count: 120000, tag_type: "general" },
        #{ tag: "mirror", count: 110000, tag_type: "general" },
        #{ tag: "bedroom", count: 100000, tag_type: "general" },
        #{ tag: "beach", count: 95000, tag_type: "general" }
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

// ============================================================================
// ORIGINAL API CODE (Disabled - kept for future reference)
// The RealBooru JSON API is currently offline
// ============================================================================
//
// fn search_series_api(query, page, auth) {
//     let limit = 40;
//     let pid = page;
//     let search_tags = url_encode(query);
//     let url = `${REALBOORU_API}?page=dapi&s=post&q=index&json=1&tags=${search_tags}&pid=${pid}&limit=${limit}`;
//     let response_text = http_get(url);
//
//     if response_text == "" || response_text == "[]" {
//         return #{ series: [], has_more: false, total: () };
//     }
//
//     let data = json_parse(response_text);
//     let posts = [];
//     if data == () {
//         return #{ series: [], has_more: false, total: () };
//     }
//     if type_of(data) == "array" {
//         posts = data;
//     } else if type_of(data) == "map" && data["post"] != () {
//         posts = data["post"];
//     }
//
//     if posts == () || posts.len() == 0 {
//         return #{ series: [], has_more: false, total: () };
//     }
//
//     let results = [];
//     for post in posts {
//         let result = build_result(post);
//         if result != () {
//             results.push(result);
//         }
//     }
//
//     #{
//         series: results,
//         has_more: results.len() >= limit,
//         total: ()
//     }
// }
