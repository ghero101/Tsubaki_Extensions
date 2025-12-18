// MangaPark Scraper Add-on (Rhai)
// Browser-based scraper for mangapark.net (Qwik/JS framework, needs browser)
// Uses HTML parsing with some embedded JSON data
//
// Available APIs:
//   HTTP (fallback): http_get(url), http_get_with_headers(url, headers)
//   Browser: browser_launch(), browser_goto(id, url), browser_wait_for_cloudflare(id, timeout)
//            browser_get_html(id), browser_close(id), browser_is_available()
//   HTML: html_select(html, selector), element_text(el), element_attr(el, attr)
//   JSON: json_parse(text)
//   Regex: regex_find(pattern, text)
//   url_encode(text) -> string

const BASE_URL = "https://mangapark.net";

/// Fetch HTML using browser automation (bypasses Cloudflare and renders JS)
/// Falls back to HTTP if browser not available
fn fetch_html(url) {
    if browser_is_available() {
        let browser_id = browser_launch();
        browser_goto(browser_id, url);
        browser_wait_for_cloudflare(browser_id, 15000);

        // Wait for Qwik to render content
        browser_wait_for_selector(browser_id, ".item, .manga-item, h1", 10000);

        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    }

    // Fallback to HTTP
    http_get_with_headers(url, get_headers())
}

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangapark-rhai",
        name: "MangaPark",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Get headers for requests (used for HTTP fallback)
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/search?word=${encoded_query}&page=${page}`;

    let html = fetch_html(url);

    let series = [];

    // Select search result items
    let items = html_select(html, ".item, .manga-item, .search-item, div[data-manga-id]");

    for item in items {
        // Get link
        let links = html_select(item, "a.cover, a.title, h3 a, h2 a");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Get title
        let title = "";
        let title_els = html_select(item, "h3 a, h2 a, .title a, a.title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        if title == "" {
            title = element_text(link).trim();
        }

        if title == "" {
            continue;
        }

        // Extract manga ID/slug
        let manga_id = extract_manga_id(href);
        if manga_id == "" {
            continue;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img.cover, img.thumb, .cover img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }

        // Get authors
        let authors = [];
        let author_els = html_select(item, ".author a, .authors a, a[href*='/author/']");
        for a in author_els {
            let author = element_text(a).trim();
            if author != "" && !authors.contains(author) {
                authors.push(author);
            }
        }

        // Get genres
        let genres = [];
        let genre_els = html_select(item, ".genres a, .genre a, a[href*='/genre/']");
        for g in genre_els {
            let genre = element_text(g).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
            }
        }

        // Get status
        let status = ();
        let status_els = html_select(item, ".status, span.status");
        if status_els.len() > 0 {
            let status_text = element_text(status_els[0]).to_lower();
            if status_text.contains("ongoing") {
                status = "Ongoing";
            } else if status_text.contains("completed") || status_text.contains("complete") {
                status = "Completed";
            }
        }

        series.push(#{
            id: manga_id,
            title: title,
            url: make_full_url(href),
            cover_url: cover_url,
            alternate_titles: [],
            authors: authors,
            artists: [],
            status: status,
            genres: genres,
            tags: [],
            description: ()
        });
    }

    // Check for next page
    let has_more = false;
    let pagers = html_select(html, ".pager a, .pagination a, a.next");
    for pager in pagers {
        let text = element_text(pager).to_lower();
        if text.contains("next") || text.contains(">") || text.contains("→") {
            has_more = true;
            break;
        }
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let manga_id = id_or_url;

    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/title/${id_or_url}`;
    } else {
        manga_id = extract_manga_id(id_or_url);
    }

    let html = fetch_html(url);

    // Extract title
    let title = "";
    let title_els = html_select(html, "h1, h2.title, .manga-title, .detail-info h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract alternate titles
    let alt_titles = [];
    let alt_els = html_select(html, ".alias, .alt-name, .other-names span, .alternative");
    for el in alt_els {
        let alt = element_text(el).trim();
        if alt != "" && alt != title && !alt_titles.contains(alt) {
            // Split by comma or semicolon
            let parts = alt.split(",");
            for p in parts {
                let cleaned = p.trim();
                if cleaned != "" && cleaned != title && !alt_titles.contains(cleaned) {
                    alt_titles.push(cleaned);
                }
            }
        }
    }

    // Extract cover
    let cover_url = ();
    let cover_els = html_select(html, ".cover img, .thumb img, .manga-cover img, img.cover");
    if cover_els.len() > 0 {
        cover_url = element_attr(cover_els[0], "src");
        if cover_url == () {
            cover_url = element_attr(cover_els[0], "data-src");
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, ".summary p, .synopsis p, .description, .manga-summary p, .limit-html");
    if desc_els.len() > 0 {
        let desc_parts = [];
        for p in desc_els {
            let text = element_text(p).trim();
            if text != "" && text.len() > 10 {
                desc_parts.push(text);
            }
        }
        if desc_parts.len() > 0 {
            description = desc_parts.join("\n\n");
        }
    }

    // Extract authors
    let authors = [];
    let author_rows = html_select(html, ".attr-item");
    for row in author_rows {
        let label = element_text(row).to_lower();
        if label.contains("author") {
            let author_links = html_select(row, "a");
            for a in author_links {
                let author = element_text(a).trim();
                if author != "" && !authors.contains(author) {
                    authors.push(author);
                }
            }
        }
    }

    // Also check direct author links
    let author_els = html_select(html, "a[href*='/author/'], a[href*='/creator/']");
    for a in author_els {
        let author = element_text(a).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    // Extract artists
    let artists = [];
    for row in author_rows {
        let label = element_text(row).to_lower();
        if label.contains("artist") {
            let artist_links = html_select(row, "a");
            for a in artist_links {
                let artist = element_text(a).trim();
                if artist != "" && !artists.contains(artist) {
                    artists.push(artist);
                }
            }
        }
    }

    // Extract genres
    let genres = [];
    let genre_els = html_select(html, ".genres a, a[href*='/genre/'], .attr-item a[href*='/search?genres']");
    for g in genre_els {
        let genre = element_text(g).trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Extract status
    let status = ();
    for row in author_rows {
        let label = element_text(row).to_lower();
        if label.contains("status") {
            if label.contains("ongoing") {
                status = "Ongoing";
            } else if label.contains("completed") || label.contains("complete") {
                status = "Completed";
            } else if label.contains("hiatus") {
                status = "Hiatus";
            } else if label.contains("cancelled") || label.contains("canceled") {
                status = "Cancelled";
            }
            break;
        }
    }

    // Extract year
    let year = ();
    for row in author_rows {
        let text = element_text(row);
        if text.to_lower().contains("year") {
            let year_match = regex_find(`(19|20)\d{2}`, text);
            if year_match != () && year_match != "" {
                year = year_match;
            }
            break;
        }
    }

    #{
        id: manga_id,
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
        content_rating: "suggestive",
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

    let chapters = [];
    let seen = #{};

    // MangaPark may have multiple versions/sources
    // Find all chapter listings
    let chapter_containers = html_select(html, ".episode-list, .chapter-list, .version-chap, #chapterList");

    // If no container found, try direct chapter links
    if chapter_containers.len() == 0 {
        chapter_containers = [html];
    }

    for container in chapter_containers {
        // Get source/version name if available
        let source_name = ();
        let source_els = html_select(container, ".source-name, .version-name, h4");
        if source_els.len() > 0 {
            source_name = element_text(source_els[0]).trim();
        }

        // Find chapter links
        let chapter_links = html_select(container, "a[href*='/chapter/'], a[href*='/ch-'], .chapter-item a, .chap-item a");

        for link in chapter_links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }

            // Skip duplicates
            if seen.contains(href) {
                continue;
            }
            seen[href] = true;

            // Get chapter text
            let chapter_text = element_text(link).trim();

            // Extract chapter number
            let ch_num = extract_chapter_number(href, chapter_text);

            // Get title (if different from chapter number)
            let title = ();
            let title_els = html_select(link, ".name, .title, span.chapter-title");
            if title_els.len() > 0 {
                let title_text = element_text(title_els[0]).trim();
                // Only use if it's not just "Chapter X"
                if !title_text.to_lower().starts_with("ch") && title_text != ch_num {
                    title = title_text;
                }
            }

            // Get date
            let date = ();
            // Look for sibling date element
            let parent = html_select(link, "..");
            if parent.len() > 0 {
                let date_els = html_select(parent[0], ".time, .date, time, .chapter-date");
                if date_els.len() > 0 {
                    date = element_text(date_els[0]).trim();
                }
            }

            // Extract chapter ID from URL
            let ch_id = extract_chapter_id(href);

            chapters.push(#{
                id: ch_id,
                series_id: series_id,
                number: ch_num,
                title: title,
                volume: (),
                language: "en",
                scanlator: source_name,
                url: make_full_url(href),
                published_at: date,
                page_count: (),
                extra: #{}
            });
        }
    }

    // Sort by chapter number (descending, newest first is typical)
    // Note: Rhai may not have a built-in sort, so we skip for now

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}${chapter_id}`;
    }

    let html = fetch_html(url);

    let pages = [];
    let idx = 0;

    // Try multiple selectors for page images
    // MangaPark often uses data-src for lazy loading
    let page_imgs = html_select(html, ".page-img img, .reading-content img, #viewer img, .chapter-images img, img.chapter-img");

    // Also check for image container with data attributes
    let data_imgs = html_select(html, "div[data-src], img[data-src], div[data-img]");

    // Process regular images
    for img in page_imgs {
        let img_url = element_attr(img, "data-src");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "src");
        }
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-original");
        }
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-lazy-src");
        }

        if img_url != () && img_url != "" && is_valid_page_url(img_url) {
            pages.push(#{
                index: idx,
                url: make_full_url(img_url),
                headers: #{
                    "Referer": url
                },
                referer: url
            });
            idx += 1;
        }
    }

    // Process data attribute images
    for div in data_imgs {
        let img_url = element_attr(div, "data-src");
        if img_url == () || img_url == "" {
            img_url = element_attr(div, "data-img");
        }

        if img_url != () && img_url != "" && is_valid_page_url(img_url) {
            // Check if we already have this URL
            let exists = false;
            for p in pages {
                if p.url == make_full_url(img_url) {
                    exists = true;
                    break;
                }
            }

            if !exists {
                pages.push(#{
                    index: idx,
                    url: make_full_url(img_url),
                    headers: #{
                        "Referer": url
                    },
                    referer: url
                });
                idx += 1;
            }
        }
    }

    // Try to find embedded JSON with page list
    let json_match = regex_find(`pageData\s*=\s*(\[.*?\])`, html);
    if json_match != () && json_match != "" {
        let page_data = json_parse(json_match);
        if page_data != () && page_data.is_array() {
            for item in page_data {
                let img_url = "";
                if item.is_string() {
                    img_url = item;
                } else if item.contains("url") {
                    img_url = item["url"];
                } else if item.contains("src") {
                    img_url = item["src"];
                }

                if img_url != "" && is_valid_page_url(img_url) {
                    pages.push(#{
                        index: idx,
                        url: make_full_url(img_url),
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

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/latest/${page}`;

    let html = fetch_html(url);

    let series = [];

    // Find update items
    let items = html_select(html, ".item, .manga-item, .latest-item, .update-item");

    for item in items {
        let links = html_select(item, "a.cover, a.title, h3 a");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let manga_id = extract_manga_id(href);
        if manga_id == "" {
            continue;
        }

        // Get title
        let title = "";
        let title_els = html_select(item, "h3 a, h2 a, .title a, a.title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        if title == "" {
            continue;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }

        // Get update time
        let updated_at = ();
        let time_els = html_select(item, ".time, .date, time");
        if time_els.len() > 0 {
            updated_at = element_text(time_els[0]).trim();
        }

        series.push(#{
            id: manga_id,
            title: title,
            url: make_full_url(href),
            cover_url: cover_url,
            updated_at: updated_at
        });
    }

    // Check for next page
    let has_more = false;
    let pagers = html_select(html, ".pager a, .pagination a");
    for pager in pagers {
        let text = element_text(pager).to_lower();
        if text.contains("next") || text == ">" {
            has_more = true;
            break;
        }
    }

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/popular/${page}`;

    let html = fetch_html(url);

    let series = [];

    // Similar structure to latest
    let items = html_select(html, ".item, .manga-item, .ranking-item");

    for item in items {
        let links = html_select(item, "a.cover, a.title, h3 a");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let manga_id = extract_manga_id(href);
        if manga_id == "" {
            continue;
        }

        // Get title
        let title = "";
        let title_els = html_select(item, "h3 a, h2 a, .title a");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        if title == "" {
            continue;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }

        series.push(#{
            id: manga_id,
            title: title,
            url: make_full_url(href),
            cover_url: cover_url
        });
    }

    let has_more = series.len() >= 20;

    #{ series: series, has_more: has_more }
}

// === Helper Functions ===

/// Extract manga ID from URL
fn extract_manga_id(url) {
    // Patterns:
    // /title/manga-id
    // /manga/manga-id
    // /comic/manga-id

    for pattern in ["/title/", "/manga/", "/comic/"] {
        if url.contains(pattern) {
            let parts = url.split(pattern);
            if parts.len() > 1 {
                let id_part = parts[1];
                // Remove trailing path segments and query params
                id_part = id_part.split("/")[0];
                id_part = id_part.split("?")[0];
                return id_part;
            }
        }
    }

    ""
}

/// Extract chapter ID from URL
fn extract_chapter_id(url) {
    // Full URL as ID for chapters
    if url.starts_with("http") {
        return url;
    }

    // Patterns: /chapter/ch-id, /ch-X
    if url.contains("/chapter/") {
        let parts = url.split("/chapter/");
        if parts.len() > 1 {
            return parts[1].split("?")[0];
        }
    }

    url
}

/// Extract chapter number from URL or text
fn extract_chapter_number(url, text) {
    // Try URL patterns first
    // Pattern: /ch-123, /chapter-123, -c123-
    let url_lower = url.to_lower();

    // Try ch- pattern
    if url_lower.contains("/ch-") || url_lower.contains("-ch-") {
        let parts = url_lower.split("ch-");
        if parts.len() > 1 {
            let num_part = parts[parts.len() - 1];
            num_part = num_part.split("-")[0];
            num_part = num_part.split("/")[0];
            num_part = num_part.split("?")[0];
            if num_part != "" {
                return num_part;
            }
        }
    }

    // Try chapter- pattern
    if url_lower.contains("chapter-") {
        let parts = url_lower.split("chapter-");
        if parts.len() > 1 {
            let num_part = parts[parts.len() - 1];
            num_part = num_part.split("-")[0];
            num_part = num_part.split("/")[0];
            if num_part != "" {
                return num_part;
            }
        }
    }

    // Try -c followed by number
    if url_lower.contains("-c") {
        let parts = url_lower.split("-c");
        for i in 1..parts.len() {
            let num_part = parts[i];
            if num_part.len() > 0 {
                let first_char = num_part.chars()[0];
                if first_char >= '0' && first_char <= '9' {
                    // Extract number
                    let num = "";
                    for c in num_part.chars() {
                        if c >= '0' && c <= '9' || c == '.' {
                            num += c;
                        } else {
                            break;
                        }
                    }
                    if num != "" {
                        return num;
                    }
                }
            }
        }
    }

    // Try text
    let text_lower = text.to_lower();

    // Look for "chapter X" or "ch. X" or "ch X"
    for prefix in ["chapter ", "ch. ", "ch "] {
        if text_lower.contains(prefix) {
            let parts = text_lower.split(prefix);
            if parts.len() > 1 {
                let after = parts[1].trim();
                let num = "";
                for c in after.chars() {
                    if c >= '0' && c <= '9' || c == '.' {
                        num += c;
                    } else if num.len() > 0 {
                        break;
                    }
                }
                if num != "" {
                    return num;
                }
            }
        }
    }

    // Fallback: find any number in text
    let num = "";
    let found = false;
    for c in text.chars() {
        if c >= '0' && c <= '9' || (c == '.' && found) {
            num += c;
            found = true;
        } else if found {
            break;
        }
    }

    if num != "" {
        return num;
    }

    "0"
}

/// Check if URL is a valid manga page (not icon, banner, etc.)
fn is_valid_page_url(url) {
    let url_lower = url.to_lower();

    // Skip common non-page images
    if url_lower.contains("logo") { return false; }
    if url_lower.contains("icon") { return false; }
    if url_lower.contains("avatar") { return false; }
    if url_lower.contains("banner") { return false; }
    if url_lower.contains("thumb") && url_lower.contains("small") { return false; }
    if url_lower.contains("placeholder") { return false; }
    if url_lower.contains(".gif") { return false; }
    if url_lower.contains("loading") { return false; }

    // Must look like an image
    if url_lower.contains(".jpg") || url_lower.contains(".jpeg") ||
       url_lower.contains(".png") || url_lower.contains(".webp") {
        return true;
    }

    // Could be a dynamic URL without extension
    if url_lower.contains("chapter") || url_lower.contains("page") ||
       url_lower.contains("img") || url_lower.contains("image") {
        return true;
    }

    false
}

/// Make URL absolute
fn make_full_url(url) {
    if url.starts_with("http") {
        return url;
    }
    if url.starts_with("//") {
        return `https:${url}`;
    }
    if url.starts_with("/") {
        return `${BASE_URL}${url}`;
    }
    `${BASE_URL}/${url}`
}
