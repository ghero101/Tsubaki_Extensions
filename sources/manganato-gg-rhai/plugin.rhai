// MangaNato.gg Mirror Cluster Scraper (Rhai)
// Distributes requests across mirror sites for reliability:
//   - manganato.gg (primary)
//   - mangakakalot.gg
//   - nelomanga.net
//   - natomanga.com
//
// All mirrors share the same content and URL structure.
// Image CDN: img-r1.2xstorage.com / imgs-2.2xstorage.com
//
// URL Patterns:
//   Search:   /search/story/{query}
//   Series:   /manga/{slug}
//   Chapter:  /manga/{slug}/chapter-{number}
//   Cover:    https://img-r1.2xstorage.com/thumb/{slug}.webp
//   Pages:    https://img-r1.2xstorage.com/{slug}/{chapter}/{page}.webp

// Mirror sites in priority order (inlined in functions due to Rhai scoping)
// Primary: manganato.gg, Fallbacks: mangakakalot.gg, nelomanga.net, natomanga.com

/// Get the primary mirror URL
fn get_mirror() {
    "https://www.manganato.gg"
}

/// Get all mirrors for fallback (try each one)
fn get_mirror_list() {
    [
        "https://www.manganato.gg",
        "https://www.mangakakalot.gg",
        "https://www.nelomanga.net",
        "https://www.natomanga.com"
    ]
}

/// Get image CDN URL
fn get_img_cdn() {
    "https://img-r1.2xstorage.com"
}

/// Get backup image CDN URL
fn get_img_cdn_backup() {
    "https://imgs-2.2xstorage.com"
}

/// Build request headers
fn get_headers(referer) {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": referer
    }
}

/// Fetch HTML with mirror fallback - tries each mirror until one works
/// Uses browser automation if available, falls back to HTTP
fn fetch_with_fallback(path) {
    let mirrors = get_mirror_list();

    for mirror in mirrors {
        let url = `${mirror}${path}`;
        let html = "";

        // Try browser first (handles JS-rendered content like chapter lists)
        if browser_is_available() {
            try {
                let browser_id = browser_launch();
                browser_goto(browser_id, url);
                browser_wait_for_selector(browser_id, "body", 10000);
                html = browser_get_html(browser_id);
                browser_close(browser_id);
            } catch {
                html = "";
            }
        }

        // Fallback to HTTP
        if html == "" || html.len() < 500 {
            try {
                html = http_get_with_headers(url, get_headers(mirror));
            } catch {
                try {
                    html = http_get(url);
                } catch {
                    html = "";
                }
            }
        }

        if html != "" && html.len() > 500 && !html.contains("404") && !html.contains("Page not found") {
            return html;
        }
    }

    ""
}

/// Fetch a full URL directly (for chapter pages that already have full URLs)
fn fetch_url(url) {
    let html = "";

    if browser_is_available() {
        try {
            let browser_id = browser_launch();
            browser_goto(browser_id, url);
            browser_wait_for_selector(browser_id, "body", 10000);
            html = browser_get_html(browser_id);
            browser_close(browser_id);
        } catch {
            html = "";
        }
    }

    if html == "" || html.len() < 500 {
        let referer = regex_find("https?://[^/]+", url);
        if referer == "" {
            referer = get_mirror();
        }
        try {
            html = http_get_with_headers(url, get_headers(referer));
        } catch {
            try {
                html = http_get(url);
            } catch {
                html = "";
            }
        }
    }

    html
}

/// Fetch with browser, waiting for chapter list to load
fn fetch_series_page(path) {
    let mirrors = get_mirror_list();

    for mirror in mirrors {
        let url = `${mirror}${path}`;
        let html = "";

        // Series pages need browser to load AJAX chapter list
        if browser_is_available() {
            try {
                let browser_id = browser_launch();
                browser_goto(browser_id, url);
                // Wait for chapter list to load (AJAX-rendered)
                browser_wait_for_selector(browser_id, "ul.row-content-chapter, div.chapter-list, a[href*='/chapter-']", 15000);
                html = browser_get_html(browser_id);
                browser_close(browser_id);
            } catch {
                html = "";
            }
        }

        // HTTP fallback (chapter list may not load without JS)
        if html == "" || html.len() < 500 {
            try {
                html = http_get_with_headers(url, get_headers(mirror));
            } catch {
                try {
                    html = http_get(url);
                } catch {
                    html = "";
                }
            }
        }

        if html != "" && html.len() > 500 && !html.contains("404") {
            return html;
        }
    }

    ""
}

/// Extract manga slug from URL path
/// e.g., /manga/one-piece -> one-piece
fn extract_slug(url) {
    let parts = url.split("/");
    for i in 0..parts.len() {
        if parts[i] == "manga" && i + 1 < parts.len() {
            // Return the slug, stripping any chapter part
            let slug = parts[i + 1];
            if slug != "" && !slug.starts_with("chapter") {
                return slug;
            }
        }
    }
    // Fallback: last non-empty path segment
    let last = "";
    for part in parts {
        if part != "" {
            last = part;
        }
    }
    last
}

/// Extract chapter number from URL or title text
fn extract_chapter_number(url, title) {
    // From URL: /manga/slug/chapter-123 or chapter-123.5
    let result = regex_find("chapter-(\\d+\\.?\\d*)", url);
    if result != "" {
        let num = regex_find("\\d+\\.?\\d*", result);
        if num != "" {
            return num;
        }
    }

    // From title text: "Chapter 123" or "Ch.123"
    let title_lower = title.to_lower();
    if title_lower.contains("chapter") {
        let after = title_lower.split("chapter")[1];
        let cleaned = after.trim();
        let num_str = "";
        for c in cleaned.chars() {
            if (c >= '0' && c <= '9') || c == '.' {
                num_str += c;
            } else if num_str.len() > 0 {
                break;
            }
        }
        if num_str != "" {
            return num_str;
        }
    }

    "0"
}

/// Build cover URL from slug
fn build_cover_url(slug) {
    let cdn = get_img_cdn();
    `${cdn}/thumb/${slug}.webp`
}

// === Addon Interface Functions ===

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "manganato-gg-rhai",
        name: "MangaNato.gg",
        base_url: get_mirror(),
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for manga matching a query
fn search_series(query, page, auth) {
    // These sites use the path-based search with spaces as underscores
    let encoded_query = query.replace(" ", "_");
    let path = `/search/story/${encoded_query}`;
    if page > 1 {
        path = `${path}?page=${page}`;
    }

    let html = fetch_with_fallback(path);

    if html == "" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let seen = #{};

    // Parse search results - try the .gg site structure
    // Search results use div.search-story-item or similar containers
    let items = html_select(html, "div.search-story-item");

    // Fallback selector if the first one doesn't match
    if items.len() == 0 {
        items = html_select(html, "div.story_item");
    }
    if items.len() == 0 {
        items = html_select(html, "div.content-genres-item");
    }

    for item in items {
        // Find the primary link
        let link = element_select_first(item, "a.item-img");
        if link == "" {
            link = element_select_first(item, "a");
        }
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == "" || href == () {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        // Get title
        let title = "";
        let title_el = element_select_first(item, "h3 a");
        if title_el != "" {
            title = element_text(title_el).trim();
        }
        if title == "" {
            title = element_attr(link, "title");
            if title == () {
                title = "";
            }
            title = title.trim();
        }
        if title == "" {
            continue;
        }

        // Get cover image
        let cover_url = "";
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "src");
            if cover_url == () {
                cover_url = "";
            }
        }
        if cover_url == "" {
            cover_url = build_cover_url(slug);
        }

        // Get authors
        let authors = [];
        let author_el = element_select_first(item, "span.item-author");
        if author_el != "" {
            let author = element_text(author_el).trim();
            if author != "" && author != "Updating" {
                authors.push(author);
            }
        }

        series.push(#{
            id: slug,
            title: title,
            url: `/manga/${slug}`,
            cover_url: cover_url,
            alternate_titles: [],
            authors: authors,
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: ()
        });
    }

    // Check for next page
    let has_more = false;
    let next_btn = html_select(html, "a.page-blue.page-last");
    if next_btn.len() > 0 {
        has_more = true;
    }
    // Also check by page number in links
    let next_page = page + 1;
    if html.contains(`page=${next_page}`) {
        has_more = true;
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let slug = id_or_url;
    let path = "";

    if id_or_url.starts_with("http") {
        slug = extract_slug(id_or_url);
    }

    if id_or_url.contains("/manga/") {
        path = regex_find("/manga/[^?#]+", id_or_url);
        if path == "" {
            path = `/manga/${slug}`;
        }
    } else {
        path = `/manga/${slug}`;
    }

    let html = fetch_series_page(path);

    if html == "" {
        throw `Failed to fetch series: ${slug}`;
    }

    // Extract title
    let title = "";
    let title_els = html_select(html, "h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover
    let cover_url = build_cover_url(slug);
    let cover_imgs = html_select(html, "span.info-image img, div.manga-info-pic img");
    if cover_imgs.len() > 0 {
        let src = element_attr(cover_imgs[0], "src");
        if src != () && src != "" {
            cover_url = src;
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "div.panel-story-info-description, div#noidungm");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
        if description.starts_with("Description :") {
            description = description.sub_string(13).trim();
        }
        if description.starts_with("Description:") {
            description = description.sub_string(12).trim();
        }
    }

    // Extract info from table rows
    let authors = [];
    let genres = [];
    let status = ();
    let alt_titles = [];

    // Try table-based info layout
    let table_rows = html_select(html, "table.variations-tableInfo tr");
    for row in table_rows {
        let label_els = html_select(row, "td.table-label");
        let value_els = html_select(row, "td.table-value");

        if label_els.len() > 0 && value_els.len() > 0 {
            let label = element_text(label_els[0]).to_lower();
            let value_html = value_els[0];

            if label.contains("author") {
                let links = html_select(value_html, "a");
                for link in links {
                    let author = element_text(link).trim();
                    if author != "" && author != "Updating" && !authors.contains(author) {
                        authors.push(author);
                    }
                }
            } else if label.contains("genre") {
                let links = html_select(value_html, "a");
                for link in links {
                    let genre = element_text(link).trim();
                    if genre != "" && !genres.contains(genre) {
                        genres.push(genre);
                    }
                }
            } else if label.contains("status") {
                let s = element_text(value_html).to_lower().trim();
                if s.contains("ongoing") {
                    status = "Ongoing";
                } else if s.contains("completed") {
                    status = "Completed";
                }
            } else if label.contains("alternative") {
                let alt_text = element_text(value_html);
                let alts = alt_text.split(";");
                for alt in alts {
                    let cleaned = alt.trim();
                    if cleaned != "" && cleaned != title {
                        alt_titles.push(cleaned);
                    }
                }
            }
        }
    }

    // Fallback: try list-based info layout
    if authors.len() == 0 && genres.len() == 0 {
        let info_items = html_select(html, "ul.manga-info-text li");
        for item in info_items {
            let text = element_text(item).to_lower();
            if text.contains("author") {
                let links = html_select(item, "a");
                for link in links {
                    let author = element_text(link).trim();
                    if author != "" && author != "Updating" && !authors.contains(author) {
                        authors.push(author);
                    }
                }
            } else if text.contains("genre") {
                let links = html_select(item, "a");
                for link in links {
                    let genre = element_text(link).trim();
                    if genre != "" && !genres.contains(genre) {
                        genres.push(genre);
                    }
                }
            } else if text.contains("status") {
                if text.contains("ongoing") {
                    status = "Ongoing";
                } else if text.contains("completed") {
                    status = "Completed";
                }
            } else if text.contains("alternative") {
                let alt_text = text.replace("alternative :", "").trim();
                let alts = alt_text.split(";");
                for alt in alts {
                    let cleaned = alt.trim();
                    if cleaned != "" && cleaned != title.to_lower() {
                        alt_titles.push(cleaned);
                    }
                }
            }
        }
    }

    #{
        id: slug,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: [],
        status: status,
        genres: genres,
        tags: [],
        year: (),
        content_rating: "suggestive",
        url: `${get_mirror()}/manga/${slug}`,
        extra: #{}
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let slug = series_id;

    if series_id.starts_with("http") {
        slug = extract_slug(series_id);
    } else if series_id.contains("/manga/") {
        slug = extract_slug(series_id);
    }

    let path = `/manga/${slug}`;

    // Use browser-capable fetch to let AJAX chapter list load
    let html = fetch_series_page(path);

    if html == "" {
        return [];
    }

    let chapters = [];
    let seen = #{};

    // Find chapter links - try multiple selector patterns
    let chapter_links = html_select(html, "ul.row-content-chapter li a.chapter-name");

    if chapter_links.len() == 0 {
        chapter_links = html_select(html, "div.chapter-list div.row a");
    }
    if chapter_links.len() == 0 {
        // Broader fallback: any link containing /chapter-
        chapter_links = html_select(html, "a[href*='/chapter-']");
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Skip non-chapter links (navigation, etc.)
        if !href.contains("/chapter-") {
            continue;
        }

        let chapter_title = element_text(link).trim();
        let chapter_num = extract_chapter_number(href, chapter_title);

        // Deduplicate by chapter number
        if seen[chapter_num] != () {
            continue;
        }
        seen[chapter_num] = true;

        // Normalize chapter URL to use slug-based ID
        let chapter_path = `/manga/${slug}/chapter-${chapter_num}`;

        if chapter_title == "" {
            chapter_title = `Chapter ${chapter_num}`;
        }

        chapters.push(#{
            id: chapter_path,
            series_id: slug,
            number: chapter_num,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: chapter_path,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let path = chapter_id;

    // Normalize to a path
    if chapter_id.starts_with("http") {
        path = regex_find("/manga/[^?#]+", chapter_id);
        if path == "" {
            path = chapter_id;
        }
    }

    // Fetch the chapter reader page
    let html = "";
    let used_mirror = get_mirror();
    let mirrors = get_mirror_list();

    for mirror in mirrors {
        let url = `${mirror}${path}`;
        try {
            html = http_get_with_headers(url, get_headers(mirror));
        } catch {
            try {
                html = http_get(url);
            } catch {
                html = "";
            }
        }

        if html != "" && html.len() > 1000 && (html.contains("chapterImages") || html.contains("container-chapter-reader")) {
            used_mirror = mirror;
            break;
        }

        // Try browser if HTTP didn't get the images
        if browser_is_available() {
            try {
                let browser_id = browser_launch();
                browser_goto(browser_id, url);
                browser_wait_for_selector(browser_id, ".container-chapter-reader img, img[loading='lazy']", 10000);
                html = browser_get_html(browser_id);
                browser_close(browser_id);
                if html != "" && html.len() > 1000 {
                    used_mirror = mirror;
                    break;
                }
            } catch {
                html = "";
            }
        }
    }

    if html == "" {
        return [];
    }

    let pages = [];
    let idx = 0;

    // Method 1: Extract from chapterImages JavaScript array
    // var chapterImages = ["one-piece/1/0.webp","one-piece/1/1.webp",...];
    let images_match = regex_find("chapterImages\\s*=\\s*\\[([^\\]]+)\\]", html);
    if images_match != "" {
        // Extract the array contents
        let array_content = regex_find("\\[([^\\]]+)\\]", images_match);
        array_content = array_content.replace("[", "").replace("]", "");

        // Extract individual image paths
        let image_paths = regex_find_all("\"([^\"]+)\"", array_content);

        // Find CDN URLs from the page
        let cdn_url = get_img_cdn();
        let cdn_match = regex_find("(https://[^\"']+2xstorage\\.com[^\"']*)", html);
        if cdn_match != "" {
            // Extract just the base CDN URL
            let cdn_base = regex_find("https://[^/]+\\.2xstorage\\.com", cdn_match);
            if cdn_base != "" {
                cdn_url = cdn_base;
            }
        }

        for img_path in image_paths {
            // Clean the path - remove quotes
            let clean_path = img_path.replace("\"", "").trim();
            if clean_path == "" {
                continue;
            }

            let full_url = `${cdn_url}/${clean_path}`;

            pages.push(#{
                index: idx,
                url: full_url,
                headers: #{
                    "Referer": `${used_mirror}${path}`
                },
                referer: `${used_mirror}${path}`
            });
            idx += 1;
        }
    }

    // Method 2: Fallback to parsing img tags in the reader container
    if pages.len() == 0 {
        let page_imgs = html_select(html, "div.container-chapter-reader img");

        for img in page_imgs {
            let img_url = element_attr(img, "src");
            if img_url == () || img_url == "" {
                img_url = element_attr(img, "data-src");
            }

            if img_url != () && img_url != "" && img_url.contains("http") {
                // Skip non-manga images
                if img_url.contains("logo") || img_url.contains("icon") || img_url.contains("banner") || img_url.contains("default_nato") {
                    continue;
                }

                pages.push(#{
                    index: idx,
                    url: img_url,
                    headers: #{
                        "Referer": `${used_mirror}${path}`
                    },
                    referer: `${used_mirror}${path}`
                });
                idx += 1;
            }
        }
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let path = `/?page=${page}`;
    let html = fetch_with_fallback(path);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    // Parse latest updates items
    let items = html_select(html, "div.content-genres-item");
    if items.len() == 0 {
        items = html_select(html, "div.list-truyen-item-wrap");
    }

    for item in items {
        let link = element_select_first(item, "a.genres-item-img");
        if link == "" {
            link = element_select_first(item, "a");
        }
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        let title = element_attr(link, "title");
        if title == () || title == "" {
            let title_el = element_select_first(item, "h3 a");
            if title_el != "" {
                title = element_text(title_el);
            }
        }
        if title == () {
            title = "";
        }
        title = title.trim();
        if title == "" {
            continue;
        }

        let cover_url = "";
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "src");
            if cover_url == () {
                cover_url = "";
            }
        }
        if cover_url == "" {
            cover_url = build_cover_url(slug);
        }

        series.push(#{
            id: slug,
            title: title,
            url: `/manga/${slug}`,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    let has_more = page < 50 && series.len() > 0;

    #{ series: series, has_more: has_more }
}
