// Comix Scraper Add-on (Rhai)
// Browser-based scraper for comix.to
//
// comix.to is a Next.js SPA that renders content client-side.
// All data fetching requires browser automation to execute JavaScript.
//
// URL Patterns:
//   Browse:   /browser?sort=recently_updated&page={page}
//   Search:   /browser?q={query}&page={page}
//   Series:   /title/{hash_id}-{slug}
//   Reader:   /title/{hash_id}-{slug}/{chapter_number} (inferred)
//   Covers:   https://static.comix.to/{id}/i/{path}@{size}.jpg
//
// Data is embedded in Next.js streaming format (__next_f.push)
// and rendered into DOM elements by React components.

const BASE_URL = "https://comix.to";
const CDN_URL = "https://static.comix.to";

/// Build request headers
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch page using browser automation (required for this SPA)
fn fetch_browser(url) {
    if !browser_is_available() {
        // Try HTTP as last resort (will likely return shell HTML only)
        try {
            return http_get_with_headers(url, get_headers());
        } catch {
            return "";
        }
    }

    try {
        let browser_id = browser_launch();
        browser_goto(browser_id, url);
        // Wait for content to render
        browser_wait_for_selector(browser_id, "a[href*='/title/'], div.chapter, img[src*='static.comix.to']", 15000);
        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    } catch {
        return "";
    }
}

/// Fetch page with extended wait (for chapter lists)
fn fetch_browser_wait(url, selector) {
    if !browser_is_available() {
        try {
            return http_get_with_headers(url, get_headers());
        } catch {
            return "";
        }
    }

    try {
        let browser_id = browser_launch();
        browser_goto(browser_id, url);
        browser_wait_for_selector(browser_id, selector, 20000);
        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    } catch {
        return "";
    }
}

/// Extract hash_id and slug from a title URL
/// /title/3rdr3-i-became-the-rogue-first-prince -> hash_id=3rdr3, slug=i-became-the-rogue-first-prince
fn parse_title_url(url) {
    let found = regex_find("/title/([^/?#]+)", url);
    if found == "" {
        return #{ hash_id: "", slug: "", full: "" };
    }

    let full = found.replace("/title/", "");

    // Hash ID is the part before the first hyphen followed by the slug
    // But the hash itself can vary in length (e.g., "3rdr3", "xy12z")
    // The pattern is: {hash_id}-{slug-with-hyphens}
    let dash_idx = full.index_of("-");
    if dash_idx != () && dash_idx > 0 {
        let hash_id = full.sub_string(0, dash_idx);
        let slug = full.sub_string(dash_idx + 1);
        return #{ hash_id: hash_id, slug: slug, full: full };
    }

    #{ hash_id: full, slug: "", full: full }
}

/// Extract manga data from Next.js embedded JSON in script tags
/// Looks for patterns like "manga_id":123,"hash_id":"abc"
fn extract_manga_json(html, hash_id) {
    // Try to find the JSON blob containing this manga's data
    let pattern = "\"hash_id\":\"" + hash_id + "\"";
    if !html.contains(pattern) {
        return ();
    }

    // Extract title
    let title = "";
    let title_match = regex_find("\"hash_id\":\"" + hash_id + "\"[^}]*\"title\":\"([^\"]+)\"", html);
    if title_match == "" {
        // Try reverse order
        title_match = regex_find("\"title\":\"([^\"]+)\"[^}]*\"hash_id\":\"" + hash_id + "\"", html);
    }
    if title_match != "" {
        title = regex_find("\"title\":\"([^\"]+)\"", title_match);
        title = title.replace("\"title\":\"", "").replace("\"", "");
    }

    // Extract synopsis
    let synopsis = "";
    let syn_match = regex_find("\"synopsis\":\"([^\"]*?)\"", html);
    if syn_match != "" {
        synopsis = syn_match.replace("\"synopsis\":\"", "").replace("\"", "");
    }

    // Extract status
    let status = "";
    let status_match = regex_find("\"status\":\"([^\"]+)\"", html);
    if status_match != "" {
        status = status_match.replace("\"status\":\"", "").replace("\"", "");
    }

    // Extract poster/cover - handle both old string format and new object format
    // Old: "poster":"path/to/image"
    // New: "poster":{"small":"...","medium":"...","large":"..."}
    let poster = "";

    // First try new object format - extract "large" or "medium" field
    let poster_large = regex_find("\"poster\":\\{[^}]*\"large\":\"([^\"]+)\"", html);
    if poster_large != "" {
        poster = regex_find("\"large\":\"([^\"]+)\"", poster_large);
        poster = poster.replace("\"large\":\"", "").replace("\"", "");
    }
    if poster == "" {
        let poster_medium = regex_find("\"poster\":\\{[^}]*\"medium\":\"([^\"]+)\"", html);
        if poster_medium != "" {
            poster = regex_find("\"medium\":\"([^\"]+)\"", poster_medium);
            poster = poster.replace("\"medium\":\"", "").replace("\"", "");
        }
    }
    // Fallback to old string format
    if poster == "" {
        let poster_match = regex_find("\"poster\":\"([^\"]+)\"", html);
        if poster_match != "" {
            poster = poster_match.replace("\"poster\":\"", "").replace("\"", "");
        }
    }

    // Extract year
    let year = ();
    let year_match = regex_find("\"year\":(\\d+)", html);
    if year_match != "" {
        year = regex_find("\\d+", year_match.replace("\"year\":", ""));
    }

    // Extract type
    let manga_type = "";
    let type_match = regex_find("\"type\":\"([^\"]+)\"", html);
    if type_match != "" {
        manga_type = type_match.replace("\"type\":\"", "").replace("\"", "");
    }

    #{
        title: title,
        synopsis: synopsis,
        status: status,
        poster: poster,
        year: year,
        manga_type: manga_type
    }
}

/// Map comix.to status to standard format
fn map_status(status) {
    let s = status.to_lower();
    if s == "releasing" || s.contains("ongoing") {
        return "Ongoing";
    } else if s == "complete" || s == "finished" || s.contains("completed") {
        return "Completed";
    } else if s == "on_hiatus" || s.contains("hiatus") {
        return "Hiatus";
    } else if s == "discontinued" || s.contains("cancelled") {
        return "Cancelled";
    }
    status
}

// === Addon Interface Functions ===

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "comix-rhai",
        name: "Comix",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for manga matching a query
fn search_series(query, page, auth) {
    let encoded = url_encode(query);
    let url = `${BASE_URL}/browser?q=${encoded}&page=${page}`;

    let html = fetch_browser(url);

    if html == "" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let seen = #{};

    // Extract cover URLs from DOM images for lookup
    // Structure: <img alt="Title" src="https://static.comix.to/...">
    let cover_map = #{};
    let cover_imgs = html_select(html, "img[src*='static.comix.to']");
    for img in cover_imgs {
        let alt = element_attr(img, "alt");
        let src = element_attr(img, "src");
        if alt != () && alt != "" && src != () && src != "" {
            cover_map[alt.to_lower()] = src;
        }
    }

    // Find all title links in the rendered page
    // Pattern: <a href="/title/{hash_id}-{slug}">
    let title_links = regex_find_all("href=\"(/title/[^\"]+)\"", html);

    for link_match in title_links {
        let href = regex_find("/title/[^\"]+", link_match);
        if href == "" {
            continue;
        }

        let parsed = parse_title_url(href);
        if parsed.hash_id == "" || seen[parsed.hash_id] != () {
            continue;
        }
        seen[parsed.hash_id] = true;

        // Try to extract title from nearby text or JSON data
        let title = "";
        let json_data = extract_manga_json(html, parsed.hash_id);
        if json_data != () {
            title = json_data.title;
        }

        // Fallback: construct title from slug
        if title == "" {
            title = parsed.slug.replace("-", " ");
            // Capitalize first letter of each word
            let words = title.split(" ");
            let capitalized = [];
            for word in words {
                if word.len() > 0 {
                    let first = word.sub_string(0, 1).to_upper();
                    let rest = if word.len() > 1 { word.sub_string(1) } else { "" };
                    capitalized.push(`${first}${rest}`);
                }
            }
            title = capitalized.reduce(|a, b| `${a} ${b}`).trim();
        }

        if title == "" {
            continue;
        }

        // Build cover URL - try DOM lookup by title, then JSON data
        let cover_url = "";
        let title_key = title.to_lower();
        if cover_map[title_key] != () {
            cover_url = cover_map[title_key];
        } else if json_data != () && json_data.poster != "" {
            if json_data.poster.starts_with("http") {
                cover_url = json_data.poster;
            } else {
                cover_url = `${CDN_URL}/${json_data.poster}@280.jpg`;
            }
        }

        let status = ();
        if json_data != () && json_data.status != "" {
            status = map_status(json_data.status);
        }

        series.push(#{
            id: parsed.full,
            title: title,
            url: `${BASE_URL}/title/${parsed.full}`,
            cover_url: cover_url,
            alternate_titles: [],
            authors: [],
            artists: [],
            status: status,
            genres: [],
            tags: [],
            description: if json_data != () { json_data.synopsis } else { () }
        });
    }

    // Check for next page
    let has_more = html.contains(`page=${page + 1}`);

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let title_path = id_or_url;

    if id_or_url.starts_with("http") {
        let parsed = parse_title_url(id_or_url);
        title_path = parsed.full;
    } else if id_or_url.starts_with("/title/") {
        title_path = id_or_url.replace("/title/", "");
    }

    let url = `${BASE_URL}/title/${title_path}`;
    let html = fetch_browser_wait(url, "h1, img[src*='static.comix.to'], div.synopsis");

    if html == "" {
        throw `Failed to fetch series: ${title_path}`;
    }

    let parsed = parse_title_url(`/title/${title_path}`);

    // Try JSON extraction from embedded Next.js data
    let json_data = extract_manga_json(html, parsed.hash_id);

    // Extract title from DOM
    let title = "";
    let title_els = html_select(html, "h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }
    if title == "" && json_data != () {
        title = json_data.title;
    }
    if title == "" {
        // Derive from slug
        title = parsed.slug.replace("-", " ");
    }

    // Cover URL
    let cover_url = "";
    if json_data != () && json_data.poster != "" {
        // Check if poster is already a full URL (new format)
        if json_data.poster.starts_with("http") {
            cover_url = json_data.poster;
        } else {
            cover_url = `${CDN_URL}/${json_data.poster}`;
        }
    }
    // Also try from DOM
    if cover_url == "" {
        let cover_imgs = html_select(html, "img[src*='static.comix.to']");
        if cover_imgs.len() > 0 {
            cover_url = element_attr(cover_imgs[0], "src");
            if cover_url == () {
                cover_url = "";
            }
        }
    }

    // Description
    let description = ();
    if json_data != () && json_data.synopsis != "" {
        description = json_data.synopsis;
    }
    // Try from DOM
    if description == () {
        let desc_match = regex_find("og:description[\"']\\s*content=[\"']([^\"']+)", html);
        if desc_match != "" {
            description = regex_find("content=[\"']([^\"']+)", desc_match);
            description = description.replace("content=\"", "").replace("content='", "").replace("\"", "").replace("'", "").trim();
        }
    }

    // Status
    let status = ();
    if json_data != () && json_data.status != "" {
        status = map_status(json_data.status);
    }

    // Year
    let year = ();
    if json_data != () && json_data.year != () {
        year = json_data.year;
    }

    // Genres from DOM (look for genre/tag links)
    let genres = [];
    let genre_links = html_select(html, "a[href*='/browser?genres='], a[href*='genre']");
    for link in genre_links {
        let genre = element_text(link).trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Authors from DOM
    let authors = [];
    let author_links = html_select(html, "a[href*='author'], a[href*='artist']");
    for link in author_links {
        let author = element_text(link).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    #{
        id: title_path,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: [],
        status: status,
        genres: genres,
        tags: [],
        year: year,
        content_rating: "suggestive",
        url: url,
        extra: #{
            hash_id: parsed.hash_id,
            manga_type: if json_data != () { json_data.manga_type } else { "" }
        }
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let title_path = series_id;

    if series_id.starts_with("http") {
        let parsed = parse_title_url(series_id);
        title_path = parsed.full;
    } else if series_id.starts_with("/title/") {
        title_path = series_id.replace("/title/", "");
    }

    let url = `${BASE_URL}/title/${title_path}`;

    // Need browser to load the dynamically rendered chapter list
    let html = fetch_browser_wait(url, "a[href*='/chapter'], div.chapter, ul.chapter-list");

    if html == "" {
        return [];
    }

    let chapters = [];
    let seen = #{};

    // Find chapter links in the rendered DOM
    // Look for links containing chapter references
    let chapter_links = html_select(html, "a[href*='chapter']");

    if chapter_links.len() == 0 {
        // Try broader patterns from embedded data
        let chapter_patterns = regex_find_all("\"chapter[_-]?(\\d+\\.?\\d*)\"", html);
        // Also look for chapter number references in JSON
        let ch_numbers = regex_find_all("\"number\":(\\d+\\.?\\d*)", html);
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Skip non-chapter navigation links
        if href.contains("/browser") || href.contains("/home") || href.contains("/groups") {
            continue;
        }

        let chapter_title = element_text(link).trim();

        // Extract chapter number
        let chapter_num = "0";
        let num_match = regex_find("chapter[\\s_-]*(\\d+\\.?\\d*)", href.to_lower());
        if num_match != "" {
            chapter_num = regex_find("\\d+\\.?\\d*", num_match);
        }
        if chapter_num == "0" || chapter_num == "" {
            num_match = regex_find("chapter[\\s_-]*(\\d+\\.?\\d*)", chapter_title.to_lower());
            if num_match != "" {
                chapter_num = regex_find("\\d+\\.?\\d*", num_match);
            }
        }

        // Skip duplicates
        if seen[chapter_num] != () {
            continue;
        }
        seen[chapter_num] = true;

        if chapter_title == "" {
            chapter_title = `Chapter ${chapter_num}`;
        }

        // Normalize the chapter URL/ID
        let chapter_id = href;
        if !chapter_id.starts_with("http") && !chapter_id.starts_with("/") {
            chapter_id = `/${chapter_id}`;
        }

        chapters.push(#{
            id: chapter_id,
            series_id: title_path,
            number: chapter_num,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: if chapter_id.starts_with("http") { chapter_id } else { `${BASE_URL}${chapter_id}` },
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // If no chapter links found, try to extract from Next.js JSON data
    if chapters.len() == 0 {
        let latest_ch = regex_find("\"latest_chapter\":(\\d+)", html);
        if latest_ch != "" {
            let max_ch = regex_find("\\d+", latest_ch.replace("\"latest_chapter\":", ""));
            if max_ch != "" {
                let parsed = parse_title_url(`/title/${title_path}`);
                let max_num = parse_int(max_ch);
                if max_num != () && max_num > 0 {
                    // Generate chapter entries based on known count
                    let ch = max_num;
                    while ch >= 1 {
                        let ch_str = `${ch}`;
                        chapters.push(#{
                            id: `/title/${title_path}/${ch_str}`,
                            series_id: title_path,
                            number: ch_str,
                            title: `Chapter ${ch_str}`,
                            volume: (),
                            language: "en",
                            scanlator: (),
                            url: `${BASE_URL}/title/${title_path}/${ch_str}`,
                            published_at: (),
                            page_count: (),
                            extra: #{}
                        });
                        ch -= 1;
                    }
                }
            }
        }
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}${chapter_id}`;
    }

    // Navigate to the reader page with browser
    let html = fetch_browser_wait(url, "img[src*='static.comix.to'], div.reader, div.chapter-reader");

    if html == "" {
        return [];
    }

    let pages = [];
    let idx = 0;
    let seen = #{};

    // Method 1: Find chapter page images from rendered DOM
    let all_imgs = html_select(html, "img[src*='static.comix.to']");

    for img in all_imgs {
        let src = element_attr(img, "src");
        if src == () || src == "" {
            src = element_attr(img, "data-src");
        }
        if src == () || src == "" {
            continue;
        }

        // Skip cover/thumbnail images (small sizes)
        if src.contains("@100") || src.contains("@280") {
            continue;
        }

        // Skip if already seen
        if seen[src] != () {
            continue;
        }
        seen[src] = true;

        pages.push(#{
            index: idx,
            url: src,
            headers: #{
                "Referer": url
            },
            referer: url
        });
        idx += 1;
    }

    // Method 2: Extract from embedded JSON data
    if pages.len() == 0 {
        // Look for image URL patterns in scripts
        let img_patterns = regex_find_all("static\\.comix\\.to/[^\"'\\s]+\\.(jpg|png|webp)", html);

        for img_url in img_patterns {
            // Skip covers/thumbnails
            if img_url.contains("@100") || img_url.contains("@280") {
                continue;
            }

            let full_url = `https://${img_url}`;
            if seen[full_url] != () {
                continue;
            }
            seen[full_url] = true;

            pages.push(#{
                index: idx,
                url: full_url,
                headers: #{
                    "Referer": url
                },
                referer: url
            });
            idx += 1;
        }
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/browser?sort=recently_updated&page=${page}`;

    let html = fetch_browser(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    // Extract cover URLs from DOM images for lookup
    let cover_map = #{};
    let cover_imgs = html_select(html, "img[src*='static.comix.to']");
    for img in cover_imgs {
        let alt = element_attr(img, "alt");
        let src = element_attr(img, "src");
        if alt != () && alt != "" && src != () && src != "" {
            cover_map[alt.to_lower()] = src;
        }
    }

    // Find title links in the rendered browse page
    let title_links = regex_find_all("href=\"(/title/[^\"]+)\"", html);

    for link_match in title_links {
        let href = regex_find("/title/[^\"]+", link_match);
        if href == "" {
            continue;
        }

        let parsed = parse_title_url(href);
        if parsed.hash_id == "" || seen[parsed.hash_id] != () {
            continue;
        }
        seen[parsed.hash_id] = true;

        let title = "";
        let json_data = extract_manga_json(html, parsed.hash_id);
        if json_data != () {
            title = json_data.title;
        }
        if title == "" {
            title = parsed.slug.replace("-", " ");
            let words = title.split(" ");
            let capitalized = [];
            for word in words {
                if word.len() > 0 {
                    let first = word.sub_string(0, 1).to_upper();
                    let rest = if word.len() > 1 { word.sub_string(1) } else { "" };
                    capitalized.push(`${first}${rest}`);
                }
            }
            title = capitalized.reduce(|a, b| `${a} ${b}`).trim();
        }

        if title == "" {
            continue;
        }

        // Build cover URL - try DOM lookup by title, then JSON data
        let cover_url = "";
        let title_key = title.to_lower();
        if cover_map[title_key] != () {
            cover_url = cover_map[title_key];
        } else if json_data != () && json_data.poster != "" {
            if json_data.poster.starts_with("http") {
                cover_url = json_data.poster;
            } else {
                cover_url = `${CDN_URL}/${json_data.poster}@280.jpg`;
            }
        }

        series.push(#{
            id: parsed.full,
            title: title,
            url: `${BASE_URL}/title/${parsed.full}`,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    let has_more = html.contains(`page=${page + 1}`) && series.len() > 0;

    #{ series: series, has_more: has_more }
}
