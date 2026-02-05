// BatoTo Scraper Add-on (Rhai)
// Browser-based scraper for mto.to (Vue.js rendered site)
//
// Key details:
// - Base URL: https://mto.to (primary mirror)
// - Requires browser automation due to Vue.js rendering
// - URL patterns: /v3x-search?word={query}, /title/{id}-{slug}, /chapter/{id}
// - Chapter images are in JavaScript array: imgHttps = [...]
// - CDN fix needed: replace "//k" with "//n" in image URLs
//
// Available APIs:
//   Browser: browser_launch(), browser_goto(id, url), browser_wait_for_selector(id, sel, timeout)
//            browser_get_html(id), browser_close(id), browser_is_available()
//            browser_execute_script(id, script)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   Regex: regex_match(pattern, text), regex_find(pattern, text), regex_find_all(pattern, text)

const BASE_URL = "https://mto.to";

// ============================================================================
// Helper Functions
// ============================================================================

/// Fetch HTML using browser automation (required for Vue.js rendering)
/// Falls back to HTTP if browser not available
fn fetch_html(url) {
    if browser_is_available() {
        try {
            let browser_id = browser_launch();

            // Navigate to the page
            browser_goto(browser_id, url);

            // Wait for body to be ready, then give Vue time to render
            try {
                browser_wait_for_selector(browser_id, "body", 5000);
            } catch {}

            // Wait additional time for Vue.js to render content
            // Try multiple selectors that might indicate content is loaded
            try {
                browser_wait_for_selector(browser_id, "a[href*='/title/'], a[href*='/chapter/'], div.item, div.main", 10000);
            } catch {
                // If specific selectors fail, just wait a bit for Vue to render
                try {
                    browser_wait_for_selector(browser_id, "div, main, article", 5000);
                } catch {}
            }

            // Get the rendered HTML
            let html = browser_get_html(browser_id);

            // Close browser session to free resources
            browser_close(browser_id);

            if html != "" && html.len() > 500 {
                return html;
            }
        } catch {
            // Browser failed, fall through to HTTP
        }
    }

    // Fallback to HTTP (will likely return empty Vue shell)
    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5"
    };
    try {
        return http_get_with_headers(url, headers);
    } catch {
        return "";
    }
}

/// Fetch HTML and also get script execution results (for chapter pages)
fn fetch_html_with_script(url, script) {
    if browser_is_available() {
        try {
            let browser_id = browser_launch();

            // Navigate to the page
            browser_goto(browser_id, url);

            // Wait for content to load - try multiple selectors
            try {
                browser_wait_for_selector(browser_id, "div.chapter-page, img.page-img, div.viewer, div.reader", 15000);
            } catch {
                try {
                    browser_wait_for_selector(browser_id, "body", 5000);
                } catch {}
            }

            // Execute script to extract data
            let script_result = "";
            try {
                script_result = browser_execute_script(browser_id, script);
            } catch {}

            // Get the rendered HTML
            let html = browser_get_html(browser_id);

            // Close browser session
            browser_close(browser_id);

            return #{ html: html, script_result: script_result };
        } catch {
            return #{ html: "", script_result: "" };
        }
    }

    return #{ html: "", script_result: "" };
}

/// Fix CDN URLs by replacing //k with //n prefix
fn fix_cdn_url(url) {
    if url == () || url == "" {
        return "";
    }
    // Replace problematic CDN prefix
    let fixed = url.replace("//k.", "//n.");

    // Ensure URL has protocol
    if fixed.starts_with("//") {
        fixed = "https:" + fixed;
    }

    fixed
}

/// Extract series ID from URL
/// URL format: /title/{id}-{slug} or /series/{id}
fn extract_series_id(url) {
    // Handle /title/{id}-{slug} format
    if url.contains("/title/") {
        let parts = url.split("/title/");
        if parts.len() > 1 {
            let id_part = parts[1].split("/")[0];
            // Extract numeric ID before the dash-slug
            let id_parts = id_part.split("-");
            if id_parts.len() > 0 {
                return id_parts[0];
            }
            return id_part;
        }
    }

    // Handle /series/{id} format
    if url.contains("/series/") {
        let parts = url.split("/series/");
        if parts.len() > 1 {
            return parts[1].split("/")[0];
        }
    }

    url
}

/// Extract chapter ID from URL
/// URL format: /chapter/{id}
fn extract_chapter_id(url) {
    if url.contains("/chapter/") {
        let parts = url.split("/chapter/");
        if parts.len() > 1 {
            return parts[1].split("/")[0].split("?")[0];
        }
    }
    url
}

/// Map status text to standard format
fn map_status(status_text) {
    if status_text == () { return (); }
    let lower = status_text.to_lower();
    if lower.contains("ongoing") {
        return "Ongoing";
    } else if lower.contains("completed") || lower.contains("complete") {
        return "Completed";
    } else if lower.contains("hiatus") {
        return "Hiatus";
    } else if lower.contains("cancelled") || lower.contains("canceled") {
        return "Cancelled";
    }
    return ();
}

/// Parse chapter number from text
fn parse_chapter_number(text) {
    if text == () { return "0"; }

    // Try to find chapter number pattern
    let ch_match = regex_find("(?:ch(?:apter)?|ch\\.?)\\s*(\\d+(?:\\.\\d+)?)", text.to_lower());
    if ch_match != "" {
        let num = regex_find("\\d+(?:\\.\\d+)?", ch_match);
        if num != "" {
            return num;
        }
    }

    // Try bare number
    let num = regex_find("^\\d+(?:\\.\\d+)?$", text.trim());
    if num != "" {
        return num;
    }

    return "0";
}

/// Helper: Parse float from string
fn parse_float(s) {
    if s == () { return 0.0; }
    let result = 0.0;
    let parts = s.split(".");
    if parts.len() > 0 {
        result = parse_int(parts[0]);
    }
    if parts.len() > 1 {
        let decimal = parse_int(parts[1]);
        let divisor = 1.0;
        for i in 0..parts[1].len() {
            divisor *= 10.0;
        }
        result += decimal / divisor;
    }
    result
}

// ============================================================================
// Required Interface Functions
// ============================================================================

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "batoto-rhai",
        name: "BatoTo",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en", "ja", "ko", "zh", "es", "fr", "de", "it", "pt-br", "ru", "vi", "th", "id", "tr", "ar"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // BatoTo search URL format: /v3x-search?word={query}&page={page}
    let url = `${BASE_URL}/v3x-search?word=${url_encode(query)}&page=${page}`;

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    // Search results are in item cards
    // Common selectors: div.item, div.series-item, a[href*="/title/"]
    for item in html_select(doc, "div.item, div.series-item, div.item-cover") {
        // Get the link to the series
        let links = html_select(item, "a[href*='/title/']");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Build full URL
        let series_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                series_url = `${BASE_URL}${href}`;
            } else {
                series_url = `${BASE_URL}/${href}`;
            }
        }

        // Extract ID
        let id = extract_series_id(series_url);

        // Skip duplicates
        if seen.contains(id) {
            continue;
        }
        seen[id] = true;

        // Get title
        let title = "";
        let title_els = html_select(item, "h3, h4, span.title, a.title, div.item-title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(link).trim();
        }

        // Skip if no valid title
        if title == "" || title.len() < 2 {
            continue;
        }

        // Get cover image
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-src");
            }
            cover_url = fix_cdn_url(cover_url);
        }

        series.push(#{
            id: id,
            title: title,
            url: series_url,
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

    // Check for next page
    let next_links = html_select(doc, "a.page-link[rel='next'], a[href*='page='][aria-label*='Next'], li.page-item.next a");
    let has_more = next_links.len() > 0;

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let id = id_or_url;

    if !id_or_url.starts_with("http") {
        // Assume it's an ID, construct URL
        url = `${BASE_URL}/title/${id_or_url}`;
    } else {
        id = extract_series_id(id_or_url);
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Extract title
    let title = "";
    let title_els = html_select(doc, "h3.item-title, h1.title, div.series-title h3, h3.name");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract alternate titles
    let alt_titles = [];
    for alt_el in html_select(doc, "span.item-alias, div.alias span, div.alt-title") {
        let alt = element_text(alt_el).trim();
        if alt != "" && alt != title {
            // May be comma-separated
            let parts = alt.split(",");
            for part in parts {
                let trimmed = part.trim();
                if trimmed != "" && trimmed != title {
                    alt_titles.push(trimmed);
                }
            }
        }
    }

    // Extract cover image
    let cover_url = ();
    let cover_els = html_select(doc, "div.item-cover img, div.series-cover img, img.cover");
    if cover_els.len() > 0 {
        cover_url = element_attr(cover_els[0], "src");
        if cover_url == () || cover_url == "" {
            cover_url = element_attr(cover_els[0], "data-src");
        }
        cover_url = fix_cdn_url(cover_url);
    }

    // Extract description
    let description = ();
    let desc_els = html_select(doc, "div.item-summary div.limit-html, div.description, div.summary, pre.limit-height");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    // Extract status
    let status = ();
    for info_el in html_select(doc, "div.attr-item, span.item-status, div.status") {
        let text = element_text(info_el);
        if text.to_lower().contains("status") || text.to_lower().contains("ongoing") || text.to_lower().contains("completed") {
            status = map_status(text);
            if status != () {
                break;
            }
        }
    }

    // Extract authors
    let authors = [];
    for author_el in html_select(doc, "a[href*='/author/'], span.item-author a, div.author a") {
        let author = element_text(author_el).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    // Extract artists
    let artists = [];
    for artist_el in html_select(doc, "a[href*='/artist/'], span.item-artist a, div.artist a") {
        let artist = element_text(artist_el).trim();
        if artist != "" && !artists.contains(artist) {
            artists.push(artist);
        }
    }

    // Extract genres
    let genres = [];
    for genre_el in html_select(doc, "a[href*='/genre/'], span.item-genre a, div.genres a, span.genre") {
        let genre = element_text(genre_el).trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Extract year if available
    let year = ();
    for info_el in html_select(doc, "div.attr-item, span.year") {
        let text = element_text(info_el);
        let year_match = regex_find("(?:19|20)\\d{2}", text);
        if year_match != "" {
            year = parse_int(year_match);
            break;
        }
    }

    #{
        id: id,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: status,
        genres: genres,
        tags: [],
        year: year,
        content_rating: (),
        url: url,
        extra: #{}
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let url = series_id;

    if !series_id.starts_with("http") {
        url = `${BASE_URL}/title/${series_id}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    // Get preferred language from settings
    let preferred_lang = if settings.preferred_language != () { settings.preferred_language } else { "en" };

    // Find chapter list - common patterns
    // div.episode-list, div.chapter-list, a[href*="/chapter/"]
    for item in html_select(doc, "div.chapter-item, div.episode-item, a.chapt, div.main a[href*='/chapter/']") {
        // Get the link
        let link = item;
        let link_els = html_select(item, "a[href*='/chapter/']");
        if link_els.len() > 0 {
            link = link_els[0];
        }

        let href = element_attr(link, "href");
        if href == () || href == "" || !href.contains("/chapter/") {
            // Maybe item itself is the link
            if element_attr(item, "href") != () && element_attr(item, "href").contains("/chapter/") {
                href = element_attr(item, "href");
            } else {
                continue;
            }
        }

        // Build full URL
        let chapter_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                chapter_url = `${BASE_URL}${href}`;
            } else {
                chapter_url = `${BASE_URL}/${href}`;
            }
        }

        // Extract chapter ID
        let chapter_id = extract_chapter_id(chapter_url);

        // Skip duplicates
        if seen.contains(chapter_id) {
            continue;
        }
        seen[chapter_id] = true;

        // Get chapter text for number extraction
        let chapter_text = element_text(link).trim();
        if chapter_text == "" {
            chapter_text = element_text(item).trim();
        }

        // Parse chapter number
        let number = parse_chapter_number(chapter_text);
        if number == "0" {
            // Try from URL
            let url_match = regex_find("ch(?:apter)?[_-]?(\\d+(?:\\.\\d+)?)", chapter_url.to_lower());
            if url_match != "" {
                number = regex_find("\\d+(?:\\.\\d+)?", url_match);
            }
        }

        // Extract title (if different from chapter number)
        let title = ();
        let title_els = html_select(item, "span.title, span.name, span.ch-title");
        if title_els.len() > 0 {
            let title_text = element_text(title_els[0]).trim();
            // Only use if it's not just the chapter number
            if title_text != "" && !regex_match("^ch(?:apter)?\\s*\\d+$", title_text.to_lower()) {
                title = title_text;
            }
        }

        // Extract scanlator if available
        let scanlator = ();
        let group_els = html_select(item, "span.group, a.group, span.scanlator");
        if group_els.len() > 0 {
            scanlator = element_text(group_els[0]).trim();
        }

        // Extract language if available
        let language = "en";
        let lang_els = html_select(item, "span.lang, span.flag, img.flag");
        if lang_els.len() > 0 {
            let lang_attr = element_attr(lang_els[0], "data-lang");
            if lang_attr != () && lang_attr != "" {
                language = lang_attr;
            } else {
                let lang_text = element_text(lang_els[0]).to_lower();
                if lang_text.contains("english") { language = "en"; }
                else if lang_text.contains("japanese") { language = "ja"; }
                else if lang_text.contains("korean") { language = "ko"; }
                else if lang_text.contains("chinese") { language = "zh"; }
            }
        }

        chapters.push(#{
            id: chapter_id,
            series_id: series_id,
            number: number,
            title: title,
            volume: (),
            language: language,
            scanlator: scanlator,
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // Sort chapters by number (descending - newest first)
    chapters.sort(|a, b| {
        let num_a = parse_float(a["number"]);
        let num_b = parse_float(b["number"]);
        if num_a < num_b { 1 } else if num_a > num_b { -1 } else { 0 }
    });

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}/chapter/${chapter_id}`;
    }

    // BatoTo stores images in JavaScript array: imgHttps = [...]
    // We need to execute JavaScript to extract this
    let script = `
        (function() {
            // Try to get imgHttps array (primary method)
            if (typeof imgHttps !== 'undefined' && Array.isArray(imgHttps)) {
                return JSON.stringify(imgHttps);
            }

            // Try to get imgHttpLis array (alternative)
            if (typeof imgHttpLis !== 'undefined' && Array.isArray(imgHttpLis)) {
                return JSON.stringify(imgHttpLis);
            }

            // Fallback: extract from page elements
            var imgs = [];
            var pageImgs = document.querySelectorAll('img.page-img, img.chapter-img, div.page-container img');
            pageImgs.forEach(function(img) {
                var src = img.src || img.dataset.src || img.dataset.pageSrc;
                if (src && src.includes('http')) {
                    imgs.push(src);
                }
            });

            if (imgs.length > 0) {
                return JSON.stringify(imgs);
            }

            // Try to find in script tags
            var scripts = document.getElementsByTagName('script');
            for (var i = 0; i < scripts.length; i++) {
                var text = scripts[i].textContent;
                var match = text.match(/imgHttps\\s*=\\s*(\\[[^\\]]+\\])/);
                if (match) {
                    return match[1];
                }
            }

            return '[]';
        })()
    `;

    let pages = [];

    if browser_is_available() {
        let browser_id = browser_launch();

        // Navigate to the chapter page
        browser_goto(browser_id, url);

        // Wait for images to load
        browser_wait_for_selector(browser_id, "img.page-img, img.chapter-img, div.page-container", 15000);

        // Execute script to get image URLs
        let result = browser_execute_script(browser_id, script);

        // Close browser
        browser_close(browser_id);

        // Parse the result
        if result != () && result != "" && result != "[]" {
            let img_urls = json_parse(result);

            if img_urls != () {
                let idx = 0;
                for img_url in img_urls {
                    if img_url != () && img_url != "" {
                        // Fix CDN URL
                        let fixed_url = fix_cdn_url(img_url);

                        pages.push(#{
                            index: idx,
                            url: fixed_url,
                            headers: #{
                                "Referer": BASE_URL
                            },
                            referer: BASE_URL
                        });
                        idx += 1;
                    }
                }
            }
        }
    }

    // If no pages found via script, try HTML parsing fallback
    if pages.len() == 0 {
        let html = fetch_html(url);
        let doc = html_parse(html);

        let idx = 0;
        for img in html_select(doc, "img.page-img, img.chapter-img, div.page-container img, div.reader-area img") {
            let img_url = element_attr(img, "src");
            if img_url == () || img_url == "" {
                img_url = element_attr(img, "data-src");
            }
            if img_url == () || img_url == "" {
                img_url = element_attr(img, "data-page-src");
            }

            if img_url != () && img_url != "" && img_url.contains("http") {
                let fixed_url = fix_cdn_url(img_url);

                pages.push(#{
                    index: idx,
                    url: fixed_url,
                    headers: #{
                        "Referer": BASE_URL
                    },
                    referer: BASE_URL
                });
                idx += 1;
            }
        }
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/browse?sort=update&page=${page}`;

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    for item in html_select(doc, "div.item, div.series-item, div.item-cover") {
        let links = html_select(item, "a[href*='/title/']");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let series_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                series_url = `${BASE_URL}${href}`;
            } else {
                series_url = `${BASE_URL}/${href}`;
            }
        }

        let id = extract_series_id(series_url);

        if seen.contains(id) {
            continue;
        }
        seen[id] = true;

        let title = "";
        let title_els = html_select(item, "h3, h4, span.title, a.title, div.item-title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(link).trim();
        }

        if title == "" || title.len() < 2 {
            continue;
        }

        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-src");
            }
            cover_url = fix_cdn_url(cover_url);
        }

        series.push(#{
            id: id,
            title: title,
            url: series_url,
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

    let next_links = html_select(doc, "a.page-link[rel='next'], a[href*='page='][aria-label*='Next'], li.page-item.next a");
    let has_more = next_links.len() > 0;

    #{ series: series, has_more: has_more }
}

/// Get popular manga
fn get_popular(page, auth) {
    let url = `${BASE_URL}/browse?sort=views_w&page=${page}`;

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    for item in html_select(doc, "div.item, div.series-item, div.item-cover") {
        let links = html_select(item, "a[href*='/title/']");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let series_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                series_url = `${BASE_URL}${href}`;
            } else {
                series_url = `${BASE_URL}/${href}`;
            }
        }

        let id = extract_series_id(series_url);

        if seen.contains(id) {
            continue;
        }
        seen[id] = true;

        let title = "";
        let title_els = html_select(item, "h3, h4, span.title, a.title, div.item-title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(link).trim();
        }

        if title == "" || title.len() < 2 {
            continue;
        }

        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-src");
            }
            cover_url = fix_cdn_url(cover_url);
        }

        series.push(#{
            id: id,
            title: title,
            url: series_url,
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

    series
}
