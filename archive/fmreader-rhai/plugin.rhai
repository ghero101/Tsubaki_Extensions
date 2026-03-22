// FMReader Framework Parser Add-on (Rhai)
// Template scraper for FMReader-based manga CMS sites
//
// FMReader is a multi-site manga CMS template used by sites like:
// - KissManga (kissmanga.org)
// - RawKuma (rawkuma.com)
// - MangaBTT (mangabtt.com)
// - And many others...
//
// URL Patterns:
//   Search: /manga-list.html?name={query}&page={page}
//   Browse: /manga-list.html?listType=pagination&page={page}&sort=views&sort_type=DESC
//   Latest: /manga-list.html?page={page}&sort=last_update&sort_type=DESC
//   Manga:  /{manga-slug}.html or /manga/{manga-slug}
//   Chapter: /{manga-slug}/{chapter-slug}.html
//
// CSS Selectors (FMReader standard):
//   Manga cards: div.media, .thumb-item-flow
//   Title/link: h3 a, .series-title a
//   Thumbnail: img, .thumb-wrapper .img-in-ratio
//   Next page: div.col-lg-9 button.btn-info, .pagination a:contains(Next)
//   Author: li a.btn-info
//   Genre: li a.btn-danger
//   Status: li a.btn-success
//   Description: div.detail .content, .summary-content p
//   Chapters: div#list-chapters p, table.table tr, .list-chapters > a
//   Page images: img.chapter-img
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   Browser: browser_launch(), browser_goto(id, url), browser_wait_for_selector(id, sel, timeout)
//            browser_get_html(id), browser_close(id), browser_is_available()
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   JSON: json_parse(text)
//   Regex: regex_find(pattern, text), regex_find_all(pattern, text), regex_match(pattern, text)
//   String: url_encode(text)

// Default base URL - can be overridden via settings
let BASE_URL = "https://rawkuma.net";

// ============================================================================
// Configuration - Override via settings
// ============================================================================

// Try to get base URL from settings, fallback to default
fn get_base_url() {
    if settings != () && settings.base_url != () && settings.base_url != "" {
        return settings.base_url;
    }
    "https://rawkuma.net"
}

// Check if browser automation should be used
fn should_use_browser() {
    if settings != () && settings.use_browser != () {
        return settings.use_browser;
    }
    false
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Get headers for HTTP requests
fn get_headers() {
    let base = get_base_url();
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": base
    }
}

/// Fetch HTML with headers, optionally using browser automation
fn fetch_html(url) {
    if should_use_browser() && browser_is_available() {
        let browser_id = browser_launch();
        browser_goto(browser_id, url);
        browser_wait_for_selector(browser_id, "div.media, .thumb-item-flow, div.detail, img.chapter-img", 15000);
        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    }

    http_get_with_headers(url, get_headers())
}

/// Extract manga ID/slug from URL
/// URL formats: /{slug}.html, /manga/{slug}, /truyen/{slug}
fn extract_manga_id(url) {
    // Remove base URL if present
    let path = url;
    let base = get_base_url();
    if path.starts_with(base) {
        path = path.replace(base, "");
    }
    if path.starts_with("http") {
        // Extract path from full URL
        let parts = path.split("/");
        if parts.len() >= 4 {
            path = "/" + parts[3];
            for i in 4..parts.len() {
                path = path + "/" + parts[i];
            }
        }
    }

    // Remove leading slash
    if path.starts_with("/") {
        path = path.sub_string(1);
    }

    // Remove common prefixes
    path = path.replace("manga/", "");
    path = path.replace("truyen/", "");
    path = path.replace("comic/", "");

    // Remove .html extension
    path = path.replace(".html", "");

    // Remove query params
    let qpos = path.index_of("?");
    if qpos > 0 {
        path = path.sub_string(0, qpos);
    }

    // Remove trailing slashes
    while path.ends_with("/") {
        path = path.sub_string(0, path.len() - 1);
    }

    path
}

/// Build manga URL from ID
fn build_manga_url(id) {
    let base = get_base_url();
    if id.starts_with("http") {
        return id;
    }
    // Most FMReader sites use /{slug}.html pattern
    `${base}/${id}.html`
}

/// Build chapter URL from chapter ID
fn build_chapter_url(chapter_id) {
    let base = get_base_url();
    if chapter_id.starts_with("http") {
        return chapter_id;
    }
    `${base}/${chapter_id}`
}

/// Extract chapter ID from URL
fn extract_chapter_id(url) {
    let path = url;
    let base = get_base_url();
    if path.starts_with(base) {
        path = path.replace(base, "");
    }

    // Remove leading slash
    if path.starts_with("/") {
        path = path.sub_string(1);
    }

    path
}

/// Map status text to standard format
fn map_status(status_text) {
    if status_text == () || status_text == "" {
        return ();
    }

    let lower = status_text.to_lower();

    if lower.contains("completed") || lower.contains("complete") || lower.contains("hoan thanh") || lower.contains("tamamlandi") {
        return "Completed";
    }
    if lower.contains("ongoing") || lower.contains("updating") || lower.contains("dang cap nhat") || lower.contains("devam ediyor") {
        return "Ongoing";
    }
    if lower.contains("hiatus") || lower.contains("paused") {
        return "Hiatus";
    }
    if lower.contains("cancelled") || lower.contains("canceled") || lower.contains("dropped") {
        return "Cancelled";
    }

    ()
}

/// Extract chapter number from text
fn extract_chapter_number(text) {
    if text == () || text == "" {
        return "0";
    }

    let lower = text.to_lower();

    // Try common patterns: "Chapter 123", "Ch. 123", "Ch 123.5", "Chap 123"
    let patterns = [
        "chapter[\\s:-]*(\\d+(?:\\.\\d+)?)",
        "ch(?:ap)?(?:ter)?[\\s.:-]*(\\d+(?:\\.\\d+)?)",
        "ep(?:isode)?[\\s.:-]*(\\d+(?:\\.\\d+)?)",
        "(\\d+(?:\\.\\d+)?)"
    ];

    for pattern in patterns {
        let match_result = regex_find(pattern, lower);
        if match_result != () && match_result != "" {
            // Extract just the number from the match
            let num = regex_find("\\d+(?:\\.\\d+)?", match_result);
            if num != "" {
                return num;
            }
        }
    }

    "0"
}

/// Parse relative date to timestamp
fn parse_relative_date(text) {
    if text == () || text == "" {
        return ();
    }

    let lower = text.to_lower();

    // Check for relative time patterns
    if lower.contains("just now") || lower.contains("second") {
        return (); // Very recent, no specific timestamp
    }
    if lower.contains("minute") {
        return ();
    }
    if lower.contains("hour") {
        return ();
    }
    if lower.contains("day") || lower.contains("yesterday") {
        return ();
    }

    // Try to extract a date pattern like "12/25/2024" or "2024-12-25"
    let date_match = regex_find("\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}", text);
    if date_match != "" {
        return date_match;
    }

    ()
}

/// Get image URL from element, checking various attributes
fn get_image_url(img_element) {
    // FMReader sites use various attributes for lazy loading
    let attrs = ["data-original", "data-src", "data-bg", "data-srcset", "data-lazy-src", "src"];

    for attr in attrs {
        let url = element_attr(img_element, attr);
        if url != () && url != "" && !url.contains("data:image") && !url.contains("blank.") {
            // Handle srcset (take first URL)
            if attr == "data-srcset" {
                let parts = url.split(",");
                if parts.len() > 0 {
                    url = parts[0].trim().split(" ")[0];
                }
            }

            // Handle background-image in style
            if attr == "style" {
                let bg_match = regex_find("url\\(['\"]?([^'\"\\)]+)['\"]?\\)", url);
                if bg_match != "" {
                    url = bg_match;
                }
            }

            // Make URL absolute if needed
            if url.starts_with("//") {
                url = "https:" + url;
            } else if url.starts_with("/") {
                let base = get_base_url();
                url = base + url;
            }

            return url;
        }
    }

    ()
}

/// Clean text by removing extra whitespace and newlines
fn clean_text(text) {
    if text == () {
        return "";
    }

    let result = text.trim();

    // Replace multiple spaces/newlines with single space
    while result.contains("  ") {
        result = result.replace("  ", " ");
    }
    while result.contains("\n\n") {
        result = result.replace("\n\n", "\n");
    }

    result
}

// ============================================================================
// Required Interface Functions
// ============================================================================

/// Returns metadata about this source
fn get_source_info() {
    let base = get_base_url();
    #{
        id: "fmreader-rhai",
        name: "FMReader",
        base_url: base,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: if should_use_browser() { "browser_automation" } else { "http_only" }
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let base = get_base_url();
    let encoded_query = url_encode(query);

    // FMReader search URL pattern
    let url = `${base}/manga-list.html?name=${encoded_query}&page=${page}`;

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    // Try multiple selectors used by different FMReader sites
    let selectors = [
        "div.media",
        ".thumb-item-flow",
        ".list-truyen-item-wrap",
        "div.row div.col-md-3",
        ".manga-item",
        "div.item"
    ];

    for selector in selectors {
        let items = html_select(doc, selector);

        for item in items {
            // Get the manga link
            let links = html_select(item, "h3 a, .series-title a, a.tooltip, a[href*='.html'], .thumb a, a.cover");
            if links.len() == 0 {
                // Try item itself if it's a link
                if element_attr(item, "href") != () {
                    links = [item];
                } else {
                    continue;
                }
            }

            let link = links[0];
            let href = element_attr(link, "href");

            if href == () || href == "" {
                continue;
            }

            // Make URL absolute
            let manga_url = href;
            if !href.starts_with("http") {
                if href.starts_with("/") {
                    manga_url = `${base}${href}`;
                } else {
                    manga_url = `${base}/${href}`;
                }
            }

            // Extract ID
            let id = extract_manga_id(manga_url);

            // Skip duplicates
            if id == "" || seen.contains(id) {
                continue;
            }
            seen[id] = true;

            // Get title
            let title = "";
            let title_els = html_select(item, "h3, .series-title, .title, .name");
            if title_els.len() > 0 {
                title = element_text(title_els[0]).trim();
            }
            if title == "" {
                title = element_attr(link, "title");
            }
            if title == "" {
                title = element_text(link).trim();
            }
            title = clean_text(title);

            if title == "" {
                continue;
            }

            // Get cover image
            let cover_url = ();
            let imgs = html_select(item, "img, .thumb-wrapper img, .img-in-ratio");
            if imgs.len() > 0 {
                cover_url = get_image_url(imgs[0]);
            }

            // Try to get status
            let status = ();
            let status_els = html_select(item, "a.btn-success, .status, .manga-status");
            if status_els.len() > 0 {
                status = map_status(element_text(status_els[0]));
            }

            series.push(#{
                id: id,
                title: title,
                url: manga_url,
                cover_url: cover_url,
                alternate_titles: [],
                authors: [],
                artists: [],
                status: status,
                genres: [],
                tags: [],
                description: ()
            });
        }

        // If we found results, don't try other selectors
        if series.len() > 0 {
            break;
        }
    }

    // Check for next page
    let has_more = false;
    let next_links = html_select(doc, "a.page-link[rel='next'], .pagination a:contains(Next), .pagination a:contains(>>), button.btn-info");
    if next_links.len() > 0 {
        has_more = true;
    } else {
        // Check if there are more pages by looking at page numbers
        let page_nums = html_select(doc, ".pagination a, .page-link");
        for pn in page_nums {
            let page_text = element_text(pn).trim();
            let page_num = regex_find("\\d+", page_text);
            if page_num != "" {
                let num = parse_int(page_num);
                if num > page {
                    has_more = true;
                    break;
                }
            }
        }
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let base = get_base_url();
    let url = id_or_url;
    let id = id_or_url;

    if !id_or_url.starts_with("http") {
        url = build_manga_url(id_or_url);
    } else {
        id = extract_manga_id(id_or_url);
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Extract title - try multiple selectors
    let title = "";
    let title_selectors = ["h1", "h2.title", ".manga-title", ".series-title", "div.detail h1", ".post-title h1"];
    for selector in title_selectors {
        let title_els = html_select(doc, selector);
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
            if title != "" {
                break;
            }
        }
    }

    // Extract alternate titles
    let alt_titles = [];
    let alt_selectors = ["li:contains(Other names)", "li:contains(Alternative)", ".alt-name", ".other-names"];
    for selector in alt_selectors {
        let alt_els = html_select(doc, selector);
        for alt_el in alt_els {
            let alt_text = element_text(alt_el);
            // Remove label part
            alt_text = alt_text.replace("Other names:", "").replace("Alternative:", "").replace("Autres noms:", "").trim();
            if alt_text != "" && alt_text != title {
                // Split by common delimiters
                let delimiters = [";", ",", "/"];
                for delim in delimiters {
                    if alt_text.contains(delim) {
                        let parts = alt_text.split(delim);
                        for part in parts {
                            let cleaned = part.trim();
                            if cleaned != "" && cleaned != title && !alt_titles.contains(cleaned) {
                                alt_titles.push(cleaned);
                            }
                        }
                        break;
                    }
                }
                if alt_titles.len() == 0 && alt_text != title {
                    alt_titles.push(alt_text);
                }
            }
        }
    }

    // Extract cover image
    let cover_url = ();
    let cover_selectors = ["img.thumbnail", ".manga-thumb img", ".series-thumb img", ".detail img", "div.detail .cover img", "meta[property='og:image']"];
    for selector in cover_selectors {
        let cover_els = html_select(doc, selector);
        if cover_els.len() > 0 {
            if selector.contains("meta") {
                cover_url = element_attr(cover_els[0], "content");
            } else {
                cover_url = get_image_url(cover_els[0]);
            }
            if cover_url != () && cover_url != "" {
                break;
            }
        }
    }

    // Extract description
    let description = ();
    let desc_selectors = ["div.detail .content", ".summary-content p", ".description", ".manga-description", ".story-content", "div.row ~ div.row:has(h3:first-child) p"];
    for selector in desc_selectors {
        let desc_els = html_select(doc, selector);
        if desc_els.len() > 0 {
            description = element_text(desc_els[0]);
            description = clean_text(description);
            if description != "" && description.len() > 20 {
                break;
            }
        }
    }

    // Extract authors
    let authors = [];
    let author_selectors = ["li a.btn-info", "a[href*='author'], a[href*='artist']", ".author a", ".manga-author a"];
    for selector in author_selectors {
        let author_els = html_select(doc, selector);
        for author_el in author_els {
            let author = element_text(author_el).trim();
            if author != "" && author.len() > 1 && !authors.contains(author) {
                authors.push(author);
            }
        }
        if authors.len() > 0 {
            break;
        }
    }

    // Extract genres
    let genres = [];
    let genre_selectors = ["li a.btn-danger", "a[href*='genre']", ".genre a", ".manga-genre a", ".categories a"];
    for selector in genre_selectors {
        let genre_els = html_select(doc, selector);
        for genre_el in genre_els {
            let genre = element_text(genre_el).trim();
            if genre != "" && genre.len() > 1 && !genres.contains(genre) {
                genres.push(genre);
            }
        }
        if genres.len() > 0 {
            break;
        }
    }

    // Extract status
    let status = ();
    let status_selectors = ["li a.btn-success", "a[href*='status']", ".status", ".manga-status"];
    for selector in status_selectors {
        let status_els = html_select(doc, selector);
        if status_els.len() > 0 {
            status = map_status(element_text(status_els[0]));
            if status != () {
                break;
            }
        }
    }

    // Try to find status in info list if not found
    if status == () {
        let info_items = html_select(doc, "li, .info-item, .manga-info p");
        for item in info_items {
            let text = element_text(item).to_lower();
            if text.contains("status") {
                status = map_status(text);
                if status != () {
                    break;
                }
            }
        }
    }

    // Extract year if available
    let year = ();
    let year_match = regex_find("\\b(19|20)\\d{2}\\b", html);
    if year_match != "" {
        year = parse_int(year_match);
    }

    #{
        id: id,
        title: title,
        alternate_titles: alt_titles,
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
        extra: #{}
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let base = get_base_url();
    let url = series_id;

    if !series_id.starts_with("http") {
        url = build_manga_url(series_id);
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    // Try multiple selectors for chapter lists
    let selectors = [
        "div#list-chapters p",
        "div#list-chapters a",
        "table.table tr a",
        ".list-chapters > a",
        ".chapter-list a",
        "ul.list-chapters li a",
        ".chapters-list a",
        "div.chapter-list a"
    ];

    for selector in selectors {
        let items = html_select(doc, selector);

        for item in items {
            // Get the link element
            let link = item;
            let href = element_attr(item, "href");

            // If item is a container, find link inside
            if href == () || href == "" {
                let links = html_select(item, "a");
                if links.len() > 0 {
                    link = links[0];
                    href = element_attr(link, "href");
                }
            }

            if href == () || href == "" {
                continue;
            }

            // Make URL absolute
            let chapter_url = href;
            if !href.starts_with("http") {
                if href.starts_with("/") {
                    chapter_url = `${base}${href}`;
                } else {
                    chapter_url = `${base}/${href}`;
                }
            }

            // Extract chapter ID
            let chapter_id = extract_chapter_id(chapter_url);

            // Skip duplicates
            if seen.contains(chapter_id) {
                continue;
            }
            seen[chapter_id] = true;

            // Get chapter text
            let chapter_text = element_text(link).trim();
            chapter_text = clean_text(chapter_text);

            // Extract chapter number
            let number = extract_chapter_number(chapter_text);
            if number == "0" {
                // Try from URL
                number = extract_chapter_number(chapter_url);
            }

            // Get title (separate from chapter number if possible)
            let title = ();
            // Try to find title element
            let title_els = html_select(item, ".chapter-title, .chap-title, span:not(.chapter-date)");
            if title_els.len() > 0 {
                let title_text = element_text(title_els[0]).trim();
                // Only use if it's not just the chapter number
                if title_text != "" && !regex_match("^ch(apter)?\\s*\\d+$", title_text.to_lower()) {
                    title = title_text;
                }
            }

            // Get publication date
            let published_at = ();
            let time_els = html_select(item, "time, .chapter-time, .publishedDate, span.time, .date");
            if time_els.len() > 0 {
                let time_text = element_text(time_els[0]).trim();
                published_at = parse_relative_date(time_text);
            }

            // Get scanlator if available
            let scanlator = ();
            let group_els = html_select(item, ".group, .scanlator, .team");
            if group_els.len() > 0 {
                scanlator = element_text(group_els[0]).trim();
            }

            chapters.push(#{
                id: chapter_id,
                series_id: series_id,
                number: number,
                title: title,
                volume: (),
                language: "en",
                scanlator: scanlator,
                url: chapter_url,
                published_at: published_at,
                page_count: (),
                extra: #{}
            });
        }

        // If we found chapters, don't try other selectors
        if chapters.len() > 0 {
            break;
        }
    }

    // Sort by chapter number (descending - newest first is typical for FMReader)
    // Note: chapters are usually already in descending order from the site

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let base = get_base_url();
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = build_chapter_url(chapter_id);
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let pages = [];
    let idx = 0;

    // Primary selector: img.chapter-img (standard FMReader)
    let selectors = [
        "img.chapter-img",
        ".reading-content img",
        ".chapter-content img",
        "div#chapter-content img",
        ".page-chapter img",
        ".chapter-pages img",
        "img[id*='page']",
        ".reader-area img"
    ];

    for selector in selectors {
        let page_imgs = html_select(doc, selector);

        for img in page_imgs {
            let img_url = get_image_url(img);

            // Skip invalid URLs
            if img_url == () || img_url == "" {
                continue;
            }

            // Skip known non-page images
            if img_url.contains("logo") || img_url.contains("icon") || img_url.contains("avatar") {
                continue;
            }
            if img_url.contains("ad") || img_url.contains("banner") || img_url.contains("sponsor") {
                continue;
            }
            if img_url.contains("placeholder") || img_url.contains("loading") || img_url.contains("blank") {
                continue;
            }

            pages.push(#{
                index: idx,
                url: img_url,
                headers: #{
                    "Referer": url
                },
                referer: url
            });
            idx += 1;
        }

        // If we found pages, don't try other selectors
        if pages.len() > 0 {
            break;
        }
    }

    // If no pages found via standard selectors, try to find base64-encoded image list
    // Some FMReader sites encode page URLs in JavaScript
    if pages.len() == 0 {
        // Try to find image array in script
        let img_match = regex_find("lstImages\\s*=\\s*\\[([^\\]]+)\\]", html);
        if img_match != "" {
            // Parse the array
            let imgs_str = regex_find("\\[([^\\]]+)\\]", img_match);
            if imgs_str != "" {
                // Extract URLs from the array string
                let url_matches = regex_find_all("\"(https?://[^\"]+)\"", imgs_str);
                for url_match in url_matches {
                    let img_url = url_match.replace("\"", "");
                    if img_url != "" {
                        pages.push(#{
                            index: idx,
                            url: img_url,
                            headers: #{
                                "Referer": url
                            },
                            referer: url
                        });
                        idx += 1;
                    }
                }
            }
        }
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let base = get_base_url();
    let url = `${base}/manga-list.html?listType=pagination&page=${page}&sort=last_update&sort_type=DESC`;

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    // Use same logic as search
    let selectors = [
        "div.media",
        ".thumb-item-flow",
        ".list-truyen-item-wrap",
        "div.row div.col-md-3",
        ".manga-item",
        "div.item"
    ];

    for selector in selectors {
        let items = html_select(doc, selector);

        for item in items {
            let links = html_select(item, "h3 a, .series-title a, a.tooltip, a[href*='.html'], .thumb a");
            if links.len() == 0 {
                continue;
            }

            let link = links[0];
            let href = element_attr(link, "href");

            if href == () || href == "" {
                continue;
            }

            let manga_url = href;
            if !href.starts_with("http") {
                if href.starts_with("/") {
                    manga_url = `${base}${href}`;
                } else {
                    manga_url = `${base}/${href}`;
                }
            }

            let id = extract_manga_id(manga_url);

            if id == "" || seen.contains(id) {
                continue;
            }
            seen[id] = true;

            let title = "";
            let title_els = html_select(item, "h3, .series-title, .title");
            if title_els.len() > 0 {
                title = element_text(title_els[0]).trim();
            }
            if title == "" {
                title = element_attr(link, "title");
            }
            if title == "" {
                title = element_text(link).trim();
            }
            title = clean_text(title);

            if title == "" {
                continue;
            }

            let cover_url = ();
            let imgs = html_select(item, "img");
            if imgs.len() > 0 {
                cover_url = get_image_url(imgs[0]);
            }

            series.push(#{
                id: id,
                title: title,
                url: manga_url,
                cover_url: cover_url,
                updated_at: ()
            });
        }

        if series.len() > 0 {
            break;
        }
    }

    // Check for next page
    let has_more = false;
    let next_links = html_select(doc, "a.page-link[rel='next'], .pagination a:contains(Next), .pagination a:contains(>>)");
    has_more = next_links.len() > 0;

    #{ series: series, has_more: has_more }
}

/// Browse manga (main browse endpoint)
fn browse(page, filters, auth) {
    // Default to popular manga for browse
    get_popular(page, auth)
}

/// Get popular manga
fn get_popular(page, auth) {
    let base = get_base_url();
    let url = `${base}/manga-list.html?listType=pagination&page=${page}&sort=views&sort_type=DESC`;

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    let selectors = [
        "div.media",
        ".thumb-item-flow",
        ".list-truyen-item-wrap",
        "div.row div.col-md-3",
        ".manga-item",
        "div.item"
    ];

    for selector in selectors {
        let items = html_select(doc, selector);

        for item in items {
            let links = html_select(item, "h3 a, .series-title a, a.tooltip, a[href*='.html'], .thumb a");
            if links.len() == 0 {
                continue;
            }

            let link = links[0];
            let href = element_attr(link, "href");

            if href == () || href == "" {
                continue;
            }

            let manga_url = href;
            if !href.starts_with("http") {
                if href.starts_with("/") {
                    manga_url = `${base}${href}`;
                } else {
                    manga_url = `${base}/${href}`;
                }
            }

            let id = extract_manga_id(manga_url);

            if id == "" || seen.contains(id) {
                continue;
            }
            seen[id] = true;

            let title = "";
            let title_els = html_select(item, "h3, .series-title, .title");
            if title_els.len() > 0 {
                title = element_text(title_els[0]).trim();
            }
            if title == "" {
                title = element_attr(link, "title");
            }
            if title == "" {
                title = element_text(link).trim();
            }
            title = clean_text(title);

            if title == "" {
                continue;
            }

            let cover_url = ();
            let imgs = html_select(item, "img");
            if imgs.len() > 0 {
                cover_url = get_image_url(imgs[0]);
            }

            series.push(#{
                id: id,
                title: title,
                url: manga_url,
                cover_url: cover_url
            });
        }

        if series.len() > 0 {
            break;
        }
    }

    // Check for next page
    let has_more = false;
    let next_links = html_select(doc, "a.page-link[rel='next'], .pagination a:contains(Next), .pagination a:contains(>>)");
    has_more = next_links.len() > 0 || page < 50;

    #{ series: series, has_more: has_more }
}
