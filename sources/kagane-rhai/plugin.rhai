// Kagane Scraper Add-on (Rhai)
// Browser-based scraper for kagane.org
//
// Kagane uses DRM protection and Cloudflare, requiring browser automation.
// The site uses alphanumeric IDs for series and chapters.
//
// URL Patterns:
//   Homepage:  /
//   Series:    /series/{ALPHANUMERIC_ID}
//   Reader:    /series/{SERIES_ID}/reader/{CHAPTER_ID}
//   Search:    /search?q={query} (inferred)
//
// IDs are uppercase alphanumeric strings (e.g., 3OZXSUQCJ1EKRJSW9BKICKFRW5)

const BASE_URL = "https://kagane.org";

/// Build request headers (HTTP fallback)
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch page using FlareSolverr for Cloudflare bypass (primary method)
/// Falls back to browser automation, then plain HTTP
fn fetch_page(url) {
    // Method 1: FlareSolverr - dedicated Cloudflare bypass service
    if flaresolverr_is_available() {
        try {
            let html = flaresolverr_get(url, 60000);
            if html.len() > 500 {
                return html;
            }
        } catch {
            // Fall through to browser
        }
    }

    // Method 2: Browser automation with stealth mode
    if browser_is_available() {
        try {
            let browser_id = browser_launch_stealth();
            browser_goto(browser_id, url);
            browser_wait_for_cloudflare(browser_id, 35000);
            browser_wait_for_selector(browser_id, "body", 15000);
            let html = browser_get_html(browser_id);
            browser_close(browser_id);
            if html.len() > 500 {
                return html;
            }
        } catch {
            // Fall through to HTTP
        }
    }

    // Method 3: HTTP fallback (will likely fail due to Cloudflare/DRM)
    try {
        return http_get_with_headers(url, get_headers());
    } catch {
        return "";
    }
}

/// Fetch page waiting for specific content
/// FlareSolverr returns fully-rendered pages, so selector wait is only needed for browser fallback
fn fetch_page_wait(url, selector) {
    // Method 1: FlareSolverr - returns fully rendered page
    if flaresolverr_is_available() {
        try {
            let html = flaresolverr_get(url, 60000);
            if html.len() > 500 {
                return html;
            }
        } catch {
            // Fall through to browser
        }
    }

    // Method 2: Browser automation with selector wait
    if browser_is_available() {
        try {
            let browser_id = browser_launch_stealth();
            browser_goto(browser_id, url);
            browser_wait_for_cloudflare(browser_id, 35000);
            browser_wait_for_selector(browser_id, selector, 25000);
            let html = browser_get_html(browser_id);
            browser_close(browser_id);
            if html.len() > 500 {
                return html;
            }
        } catch {
            // Fall through
        }
    }

    // Method 3: HTTP fallback
    try {
        return http_get_with_headers(url, get_headers());
    } catch {
        return "";
    }
}

/// Extract series ID from URL
/// /series/3OZXSUQCJ1EKRJSW9BKICKFRW5 -> 3OZXSUQCJ1EKRJSW9BKICKFRW5
fn extract_series_id(url) {
    let result = regex_find("/series/([A-Z0-9]+)", url);
    if result != "" {
        return result.replace("/series/", "");
    }
    // Also try lowercase/mixed case
    result = regex_find("/series/([^/?#/]+)", url);
    if result != "" {
        let id = result.replace("/series/", "");
        // Don't return "reader" if we hit the reader path
        if id != "reader" && id.len() > 5 {
            return id;
        }
    }
    ""
}

/// Extract chapter ID from reader URL
/// /series/{SID}/reader/{CID} -> CID
fn extract_chapter_id(url) {
    let result = regex_find("/reader/([^/?#]+)", url);
    if result != "" {
        return result.replace("/reader/", "");
    }
    ""
}

/// Map status text to standard format
fn map_status(status) {
    let s = status.to_lower().trim();
    if s.contains("ongoing") || s.contains("releasing") {
        return "Ongoing";
    } else if s.contains("completed") || s.contains("finished") {
        return "Completed";
    } else if s.contains("hiatus") {
        return "Hiatus";
    } else if s.contains("cancelled") || s.contains("discontinued") {
        return "Cancelled";
    }
    status
}

// === Addon Interface Functions ===

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "kagane-rhai",
        name: "Kagane",
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

    // Try common search URL patterns
    let url = `${BASE_URL}/search?q=${encoded}&page=${page}`;

    let html = fetch_page(url);

    // If search URL doesn't work, try alternate patterns
    if html == "" || html.len() < 500 {
        url = `${BASE_URL}/search?keyword=${encoded}&page=${page}`;
        html = fetch_page(url);
    }
    if html == "" || html.len() < 500 {
        url = `${BASE_URL}/?s=${encoded}&page=${page}`;
        html = fetch_page(url);
    }

    if html == "" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let seen = #{};

    // Find all series links in the page
    // Kagane uses empty <a> overlay elements with aria-label for the title
    let series_links = html_select(html, "a[href*='/series/']");

    for link in series_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Skip reader links
        if href.contains("/reader/") {
            continue;
        }

        let sid = extract_series_id(href);
        if sid == "" || seen[sid] != () {
            continue;
        }
        seen[sid] = true;

        // Title: Kagane uses aria-label="Open series {Title}" on the <a> tag
        let title = "";
        let aria = element_attr(link, "aria-label");
        if aria != () && aria != "" {
            if aria.starts_with("Open series ") {
                title = aria.sub_string(12);
            } else {
                title = aria;
            }
        }
        if title == "" {
            title = element_text(link).trim();
        }
        if title == "" {
            let t = element_attr(link, "title");
            if t != () {
                title = t.trim();
            }
        }
        if title == "" || title.len() < 2 {
            continue;
        }

        // Cover: Use Komga-style thumbnail API endpoint
        // The image proxy with FlareSolverr cookies may be able to fetch these
        let cover_url = `${BASE_URL}/api/v1/series/${sid}/thumbnail`;

        series.push(#{
            id: sid,
            title: title,
            url: `${BASE_URL}/series/${sid}`,
            cover_url: cover_url,
            alternate_titles: [],
            authors: [],
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: ()
        });
    }

    // Fallback: extract from regex if DOM parsing found nothing
    if series.len() == 0 {
        let link_patterns = regex_find_all("href=\"(/series/[A-Z0-9]+)\"", html);
        for pattern in link_patterns {
            let href = regex_find("/series/[A-Z0-9]+", pattern);
            if href == "" {
                continue;
            }

            let sid = extract_series_id(href);
            if sid == "" || seen[sid] != () {
                continue;
            }
            seen[sid] = true;

            series.push(#{
                id: sid,
                title: `Series ${sid.sub_string(0, 8)}...`,
                url: `${BASE_URL}/series/${sid}`,
                cover_url: "",
                alternate_titles: [],
                authors: [],
                artists: [],
                status: (),
                genres: [],
                tags: [],
                description: ()
            });
        }
    }

    let has_more = html.contains(`page=${page + 1}`) && series.len() > 0;

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let sid = id_or_url;

    if id_or_url.starts_with("http") {
        sid = extract_series_id(id_or_url);
    } else if id_or_url.starts_with("/series/") {
        sid = id_or_url.replace("/series/", "");
    }

    if sid == "" {
        throw `Invalid series ID: ${id_or_url}`;
    }

    let url = `${BASE_URL}/series/${sid}`;
    let html = fetch_page_wait(url, "h1, h2, img, div.info, div.series-info");

    if html == "" {
        throw `Failed to fetch series: ${sid}`;
    }

    // Title - Kagane uses h1 for the series title
    let title = "";
    let title_els = html_select(html, "h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }
    if title == "" {
        let title_els2 = html_select(html, "h2");
        if title_els2.len() > 0 {
            title = element_text(title_els2[0]).trim();
        }
    }
    // Fallback: try <title> tag (format: "Title - Read Online for Free - Kagane")
    if title == "" {
        let title_match = regex_find("<title>([^<]+)</title>", html);
        if title_match != "" {
            title = title_match.replace("<title>", "").replace("</title>", "");
            let dash_idx = title.index_of(" - ");
            if dash_idx > 0 {
                title = title.sub_string(0, dash_idx).trim();
            }
        }
    }

    // Cover image - Use Komga-style thumbnail API endpoint
    // The image proxy with FlareSolverr cookies may be able to fetch these
    let cover_url = `${BASE_URL}/api/v1/series/${sid}/thumbnail`;

    // Description - from <meta name="description" content="...">
    let description = ();
    let desc_match = regex_find("name=\"description\"\\s+content=\"([^\"]+)\"", html);
    if desc_match != "" {
        description = desc_match.replace("name=\"description\" content=\"", "").replace("\"", "").trim();
    }
    // Fallback: try div selectors
    if description == () || description == "" {
        let desc_els = html_select(html, "div.description, div.synopsis, div.summary");
        if desc_els.len() > 0 {
            description = element_text(desc_els[0]).trim();
        }
    }

    // Status - Kagane shows status as "ONGOING", "COMPLETED" etc. in spans
    let status = ();
    let status_match = regex_find("(?i)(ONGOING|COMPLETED|HIATUS|CANCELLED|RELEASING|FINISHED)", html);
    if status_match != "" {
        status = map_status(status_match);
    }

    // Genres - Kagane uses spans with aria-label="Search by genre: {Genre}"
    let genres = [];
    let genre_spans = html_select(html, "span[aria-label*='genre']");
    for span in genre_spans {
        let aria = element_attr(span, "aria-label");
        if aria != () && aria != "" {
            let genre = aria.replace("Search by genre: ", "").trim();
            if genre != "" && genre.len() < 50 && !genres.contains(genre) {
                genres.push(genre);
            }
        }
    }
    // Fallback: try text content
    if genres.len() == 0 {
        let tag_links = html_select(html, "a[href*='genre'], span.genre, span.tag");
        for link in tag_links {
            let genre = element_text(link).trim();
            if genre != "" && genre.len() < 50 && !genres.contains(genre) {
                genres.push(genre);
            }
        }
    }

    // Authors - try various selectors
    let authors = [];
    let author_links = html_select(html, "a[href*='author'], a[href*='artist'], span.author");
    for link in author_links {
        let name = element_text(link).trim();
        if name != "" && !authors.contains(name) {
            authors.push(name);
        }
    }

    #{
        id: sid,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: [],
        status: status,
        genres: genres,
        tags: [],
        year: (),
        content_rating: "nsfw",
        url: url,
        extra: #{}
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let sid = series_id;

    if series_id.starts_with("http") {
        sid = extract_series_id(series_id);
    } else if series_id.starts_with("/series/") {
        sid = series_id.replace("/series/", "");
    }

    let url = `${BASE_URL}/series/${sid}`;
    let html = fetch_page_wait(url, "a[href*='/reader/'], div.chapter-list, ul.chapters");

    if html == "" {
        return [];
    }

    let chapters = [];
    let seen = #{};

    // Find chapter/reader links
    let chapter_links = html_select(html, "a[href*='/reader/']");

    // Also try generic chapter containers
    if chapter_links.len() == 0 {
        chapter_links = html_select(html, "a[href*='chapter'], a[href*='reader']");
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Must contain the reader path for this series
        if !href.contains("/reader/") && !href.contains(sid) {
            continue;
        }

        let ch_id = extract_chapter_id(href);
        if ch_id == "" {
            // Try extracting from the full URL
            // Handle hash fragments: /reader/{ID}#chapter-1-...
            let clean_href = href;
            let hash_idx = href.index_of("#");
            if hash_idx > 0 {
                clean_href = href.sub_string(0, hash_idx);
            }
            let parts = clean_href.split("/");
            let last = parts[parts.len() - 1];
            if last.len() > 5 {
                ch_id = last;
            }
        }

        if ch_id == "" || seen[ch_id] != () {
            continue;
        }
        seen[ch_id] = true;

        // Extract chapter title from <h3> inside the link (avoids getting page counts/views)
        let chapter_title = "";
        let h3 = element_select_first(link, "h3");
        if h3 != "" {
            chapter_title = element_text(h3).trim();
        }
        // Fallback to full text
        if chapter_title == "" {
            chapter_title = element_text(link).trim();
        }

        // Extract chapter number from title text
        let chapter_num = "0";
        let num_match = regex_find("(?:chapter|ch\\.?|#)\\s*(\\d+\\.?\\d*)", chapter_title.to_lower());
        if num_match != "" {
            chapter_num = regex_find("\\d+\\.?\\d*", num_match);
        }

        // If no number found, try sequential numbering
        if chapter_num == "0" {
            chapter_num = `${chapters.len() + 1}`;
        }

        if chapter_title == "" {
            chapter_title = `Chapter ${chapter_num}`;
        }

        // Build full reader URL
        let reader_url = href;
        if !reader_url.starts_with("http") {
            reader_url = `${BASE_URL}${href}`;
        }

        chapters.push(#{
            id: `${sid}/reader/${ch_id}`,
            series_id: sid,
            number: chapter_num,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: reader_url,
            published_at: (),
            page_count: (),
            extra: #{
                chapter_hash: ch_id
            }
        });
    }

    // Fallback: extract from regex
    if chapters.len() == 0 {
        let reader_patterns = regex_find_all("href=\"(/series/[^\"]+/reader/[^\"]+)\"", html);
        for pattern in reader_patterns {
            let href = regex_find("/series/[^\"]+/reader/[^\"]+", pattern);
            if href == "" {
                continue;
            }

            let ch_id = extract_chapter_id(href);
            if ch_id == "" || seen[ch_id] != () {
                continue;
            }
            seen[ch_id] = true;

            let chapter_num = `${chapters.len() + 1}`;

            chapters.push(#{
                id: `${sid}/reader/${ch_id}`,
                series_id: sid,
                number: chapter_num,
                title: `Chapter ${chapter_num}`,
                volume: (),
                language: "en",
                scanlator: (),
                url: `${BASE_URL}${href}`,
                published_at: (),
                page_count: (),
                extra: #{
                    chapter_hash: ch_id
                }
            });
        }
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = "";

    // chapter_id format: {series_id}/reader/{chapter_hash}
    if chapter_id.starts_with("http") {
        url = chapter_id;
    } else if chapter_id.contains("/reader/") {
        url = `${BASE_URL}/series/${chapter_id}`;
    } else {
        url = `${BASE_URL}/series/${chapter_id}`;
    }

    // Navigate to reader - DRM may require solving Cloudflare challenges
    let html = "";

    // Method 1: FlareSolverr for Cloudflare bypass
    if flaresolverr_is_available() {
        try {
            html = flaresolverr_get(url, 60000);
            if html.len() < 500 {
                html = "";
            }
        } catch {
            html = "";
        }
    }

    // Method 2: Browser automation with stealth for reader pages
    if html == "" && browser_is_available() {
        try {
            let browser_id = browser_launch_stealth();
            browser_goto(browser_id, url);
            browser_wait_for_cloudflare(browser_id, 35000);
            // Wait for reader images or canvas elements to load
            browser_wait_for_selector(browser_id, "img.page, img[src*='chapter'], div.reader img, canvas, div.page img", 25000);
            html = browser_get_html(browser_id);
            browser_close(browser_id);
        } catch {
            html = "";
        }
    }

    // Method 3: HTTP fallback
    if html == "" {
        try {
            html = http_get_with_headers(url, get_headers());
        } catch {
            return [];
        }
    }

    if html == "" {
        return [];
    }

    let pages = [];
    let idx = 0;
    let seen = #{};

    // Method 1: Find page images from rendered DOM
    let page_imgs = html_select(html, "div.reader img, div.page img, img.page, div.chapter-reader img");

    for img in page_imgs {
        let src = element_attr(img, "src");
        if src == () || src == "" {
            src = element_attr(img, "data-src");
        }
        if src == () || src == "" {
            continue;
        }

        // Skip non-page images
        if src.contains("logo") || src.contains("icon") || src.contains("avatar") || src.contains("banner") {
            continue;
        }

        if seen[src] != () {
            continue;
        }
        seen[src] = true;

        // Make URL absolute if relative
        let full_url = src;
        if !full_url.starts_with("http") {
            if full_url.starts_with("//") {
                full_url = `https:${full_url}`;
            } else if full_url.starts_with("/") {
                full_url = `${BASE_URL}${full_url}`;
            }
        }

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

    // Method 2: Extract image URLs from JavaScript/JSON embedded in page
    if pages.len() == 0 {
        // Look for image arrays in scripts
        let img_arrays = regex_find_all("\"(https?://[^\"]+\\.(jpg|jpeg|png|webp|gif)(?:\\?[^\"]*)?)", html);

        for img_url in img_arrays {
            let clean = img_url.replace("\"", "");

            // Filter out small/icon images
            if clean.contains("logo") || clean.contains("icon") || clean.contains("avatar") || clean.contains("thumb") {
                continue;
            }

            if seen[clean] != () {
                continue;
            }
            seen[clean] = true;

            pages.push(#{
                index: idx,
                url: clean,
                headers: #{
                    "Referer": url
                },
                referer: url
            });
            idx += 1;
        }
    }

    // Method 3: Check for canvas-based rendering (DRM)
    // If we find canvas elements but no images, the site uses canvas-based DRM
    // In that case, we can't extract images via HTML parsing
    if pages.len() == 0 {
        let canvases = html_select(html, "canvas");
        if canvases.len() > 0 {
            // Canvas-based DRM detected - images are rendered to canvas
            // This requires more advanced extraction not possible via basic scraping
            // Return empty with a note in extras
        }
    }

    pages
}

/// Get latest updates from homepage
fn get_latest_updates(page, auth) {
    let url = BASE_URL;
    if page > 1 {
        url = `${BASE_URL}/?page=${page}`;
    }

    let html = fetch_page(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    // Find series links on the homepage
    // Kagane uses empty <a> overlay elements with aria-label for the title
    let series_links = html_select(html, "a[href*='/series/']");

    for link in series_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Skip reader links
        if href.contains("/reader/") {
            continue;
        }

        let sid = extract_series_id(href);
        if sid == "" || seen[sid] != () {
            continue;
        }
        seen[sid] = true;

        // Title: Kagane uses aria-label="Open series {Title}" on the <a> tag
        let title = "";
        let aria = element_attr(link, "aria-label");
        if aria != () && aria != "" {
            if aria.starts_with("Open series ") {
                title = aria.sub_string(12);  // Remove "Open series " prefix
            } else {
                title = aria;
            }
        }
        // Fallback: try text content or title attr
        if title == "" {
            title = element_text(link).trim();
        }
        if title == "" {
            let t = element_attr(link, "title");
            if t != () {
                title = t.trim();
            }
        }
        if title == "" || title.len() < 2 {
            continue;
        }

        // Cover: Use Komga-style thumbnail API endpoint
        // The image proxy with FlareSolverr cookies may be able to fetch these
        let cover_url = `${BASE_URL}/api/v1/series/${sid}/thumbnail`;

        series.push(#{
            id: sid,
            title: title,
            url: `${BASE_URL}/series/${sid}`,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    let has_more = series.len() > 0 && page < 20;

    #{ series: series, has_more: has_more }
}
