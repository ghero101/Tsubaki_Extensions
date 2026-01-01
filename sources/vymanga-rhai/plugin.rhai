// VyManga Scraper Add-on (Rhai)
// Browser-based scraper for vymanga.net (Cloudflare protected)
//
// VyManga is a manga aggregator site with extensive library of manga, manhwa, and manhua.
// It uses Cloudflare protection and requires browser automation for reliable access.
//
// URL Patterns:
//   Search: /search?q={query}&page={page}
//   Series: /manga/{slug}
//   Chapter: /manga/{series-slug}/{chapter-slug}
//   Genres: /genre/{genre-name}
//
// Available APIs:
//   HTTP (fallback): http_get(url), http_get_with_headers(url, headers)
//   Browser: browser_launch(), browser_goto(id, url), browser_wait_for_cloudflare(id, timeout)
//            browser_get_html(id), browser_close(id), browser_is_available()
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   Regex: regex_match(pattern, text), regex_find(pattern, text), regex_find_all(pattern, text)
//   url_encode(text) -> string

const BASE_URL = "https://vymanga.net";

// ============================================================================
// Helper Functions
// ============================================================================

/// Fetch HTML using browser automation (bypasses Cloudflare)
/// Falls back to HTTP if browser not available
fn fetch_html(url) {
    if browser_is_available() {
        let browser_id = browser_launch();
        browser_goto(browser_id, url);
        browser_wait_for_cloudflare(browser_id, 15000);

        // Wait for content to load
        browser_wait_for_selector(browser_id, "a[href*='/manga/'], .book-list, .comic-thumb, h1", 10000);

        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    }

    // Fallback to HTTP (may fail with Cloudflare)
    http_get_with_headers(url, get_headers())
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

/// Extract manga slug from URL
fn extract_manga_slug(url) {
    // URL patterns:
    // /manga/solo-leveling-78ay
    // https://vymanga.net/manga/solo-leveling-78ay

    if url.contains("/manga/") {
        let parts = url.split("/manga/");
        if parts.len() > 1 {
            let slug = parts[1];
            // Remove trailing path segments and query params
            slug = slug.split("/")[0];
            slug = slug.split("?")[0];
            return slug;
        }
    }

    ""
}

/// Extract chapter slug from URL
fn extract_chapter_slug(url) {
    // URL pattern: /manga/series-slug/chapter-slug
    let parts = url.split("/manga/");
    if parts.len() > 1 {
        let path_parts = parts[1].split("/");
        if path_parts.len() > 1 {
            return path_parts[1].split("?")[0];
        }
    }
    url
}

/// Extract chapter number from text or URL
fn extract_chapter_number(url, text) {
    // Try URL patterns first
    // Pattern: chapter-123, ch-123, -chapter-123-
    let url_lower = url.to_lower();

    // Try chapter- pattern
    if url_lower.contains("chapter-") {
        let parts = url_lower.split("chapter-");
        if parts.len() > 1 {
            let num_part = parts[parts.len() - 1];
            num_part = num_part.split("-")[0];
            num_part = num_part.split("/")[0];
            num_part = num_part.split("?")[0];
            // Extract just numbers and dots
            let num = extract_number_from_string(num_part);
            if num != "" {
                return num;
            }
        }
    }

    // Try ch- pattern
    if url_lower.contains("-ch-") || url_lower.contains("/ch-") {
        let parts = url_lower.split("ch-");
        if parts.len() > 1 {
            let num_part = parts[parts.len() - 1];
            num_part = num_part.split("-")[0];
            num_part = num_part.split("/")[0];
            let num = extract_number_from_string(num_part);
            if num != "" {
                return num;
            }
        }
    }

    // Try text patterns
    let text_lower = text.to_lower();

    // Look for "chapter X" or "ch. X" or "ch X"
    for prefix in ["chapter ", "ch. ", "ch ", "chap "] {
        if text_lower.contains(prefix) {
            let parts = text_lower.split(prefix);
            if parts.len() > 1 {
                let after = parts[1].trim();
                let num = extract_number_from_string(after);
                if num != "" {
                    return num;
                }
            }
        }
    }

    // Fallback: find any number in the text
    let num = extract_number_from_string(text);
    if num != "" {
        return num;
    }

    "0"
}

/// Extract numeric value (including decimals) from start of string
fn extract_number_from_string(s) {
    let num = "";
    let found_digit = false;

    for c in s.chars() {
        if c >= '0' && c <= '9' {
            num += c;
            found_digit = true;
        } else if c == '.' && found_digit {
            num += c;
        } else if found_digit {
            break;
        }
    }

    num
}

/// Make URL absolute
fn make_full_url(url) {
    if url == () || url == "" {
        return ();
    }
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

/// Check if URL is a valid page image (not icon, logo, etc.)
fn is_valid_page_url(url) {
    if url == () || url == "" {
        return false;
    }

    let url_lower = url.to_lower();

    // Skip non-page images
    if url_lower.contains("logo") { return false; }
    if url_lower.contains("icon") { return false; }
    if url_lower.contains("avatar") { return false; }
    if url_lower.contains("banner") { return false; }
    if url_lower.contains("blank.gif") { return false; }
    if url_lower.contains("placeholder") { return false; }
    if url_lower.contains("loading") { return false; }
    if url_lower.contains(".gif") && !url_lower.contains("page") { return false; }

    // Must look like an image or be from CDN
    if url_lower.contains(".jpg") || url_lower.contains(".jpeg") ||
       url_lower.contains(".png") || url_lower.contains(".webp") {
        return true;
    }

    // CDN URLs
    if url_lower.contains("cdnxyz") || url_lower.contains("vycdn") {
        return true;
    }

    // Dynamic image URLs
    if url_lower.contains("/chapter/") || url_lower.contains("/page/") ||
       url_lower.contains("/img/") || url_lower.contains("/image/") {
        return true;
    }

    false
}

// ============================================================================
// Required Interface Functions
// ============================================================================

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "vymanga-rhai",
        name: "VyManga",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/search?q=${encoded_query}&page=${page}`;

    let html = fetch_html(url);

    let series = [];
    let seen = #{};

    // Select all manga links - VyManga uses links to /manga/ paths
    let manga_links = html_select(html, "a[href*='/manga/']");

    for link in manga_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Extract slug
        let slug = extract_manga_slug(href);
        if slug == "" {
            continue;
        }

        // Skip chapter links (they have additional path segments)
        let path_after_manga = "";
        if href.contains("/manga/") {
            let parts = href.split("/manga/");
            if parts.len() > 1 {
                path_after_manga = parts[1];
            }
        }
        if path_after_manga.contains("/") {
            // This is a chapter link, skip
            continue;
        }

        // Skip duplicates
        if seen.contains(slug) {
            continue;
        }
        seen[slug] = true;

        // Get title from link text or alt attribute
        let title = element_text(link).trim();

        // Try to get title from parent or sibling elements if empty
        if title == "" || title.len() < 2 {
            let title_attr = element_attr(link, "title");
            if title_attr != () && title_attr != "" {
                title = title_attr;
            }
        }

        // Skip if we still don't have a valid title
        if title == "" || title.len() < 2 {
            continue;
        }

        // Clean up title - remove chapter info
        if title.to_lower().contains("chapter") {
            let parts = title.split("Chapter");
            if parts.len() > 0 {
                title = parts[0].trim();
            }
        }

        // Get cover image
        let cover_url = ();
        let imgs = html_select(link, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url == "" || cover_url.contains("blank.gif") {
                cover_url = element_attr(imgs[0], "data-src");
            }
            if cover_url == () || cover_url == "" || cover_url.contains("blank.gif") {
                // Try data-lazy attribute
                cover_url = element_attr(imgs[0], "data-lazy");
            }
        }

        // Make cover URL absolute
        cover_url = make_full_url(cover_url);

        series.push(#{
            id: slug,
            title: title,
            url: make_full_url(href),
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

    // Check for next page - VyManga uses standard pagination
    let has_more = false;
    let pagers = html_select(html, "nav a, .pagination a, a[href*='page=']");
    for pager in pagers {
        let pager_href = element_attr(pager, "href");
        if pager_href != () && pager_href.contains(`page=${page + 1}`) {
            has_more = true;
            break;
        }
        let text = element_text(pager).to_lower();
        if text.contains("next") || text == ">" || text == ">>" {
            has_more = true;
            break;
        }
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let slug = id_or_url;

    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/manga/${id_or_url}`;
    } else {
        slug = extract_manga_slug(id_or_url);
    }

    let html = fetch_html(url);

    // Extract title - usually in h1
    let title = "";
    let title_els = html_select(html, "h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract alternate titles
    let alt_titles = [];
    let alt_els = html_select(html, ".alt-name, .alias, .other-names, .alternative");
    for el in alt_els {
        let alt_text = element_text(el).trim();
        if alt_text != "" && alt_text != title {
            // Split by comma or semicolon
            let parts = alt_text.split(",");
            for p in parts {
                let cleaned = p.trim();
                if cleaned != "" && cleaned != title && !alt_titles.contains(cleaned) {
                    alt_titles.push(cleaned);
                }
            }
        }
    }

    // Extract cover - look for main image
    let cover_url = ();
    let cover_els = html_select(html, ".cover img, .thumb img, .manga-cover img, img.cover, img[alt*='cover'], .info img");
    if cover_els.len() > 0 {
        cover_url = element_attr(cover_els[0], "src");
        if cover_url == () || cover_url.contains("blank.gif") {
            cover_url = element_attr(cover_els[0], "data-src");
        }
    }
    // Try any img in main content area
    if cover_url == () || cover_url.contains("blank.gif") {
        let all_imgs = html_select(html, ".info img, .detail img, article img");
        for img in all_imgs {
            let src = element_attr(img, "src");
            if src != () && !src.contains("blank.gif") && !src.contains("avatar") {
                cover_url = src;
                break;
            }
        }
    }
    cover_url = make_full_url(cover_url);

    // Extract description
    let description = ();
    let desc_els = html_select(html, ".summary p, .description p, .synopsis, .manga-summary, .content p, .info p");
    if desc_els.len() > 0 {
        let desc_parts = [];
        for p in desc_els {
            let text = element_text(p).trim();
            if text != "" && text.len() > 20 {
                desc_parts.push(text);
            }
        }
        if desc_parts.len() > 0 {
            // Manual join since Rhai doesn't have built-in join
            description = "";
            let first = true;
            for part in desc_parts {
                if !first {
                    description += "\n\n";
                }
                description += part;
                first = false;
            }
        }
    }

    // Extract authors
    let authors = [];
    let author_els = html_select(html, "a[href*='/author/'], a[href*='/creator/'], .author a");
    for el in author_els {
        let author = element_text(el).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    // Extract artists
    let artists = [];
    let artist_els = html_select(html, "a[href*='/artist/'], .artist a");
    for el in artist_els {
        let artist = element_text(el).trim();
        if artist != "" && !artists.contains(artist) {
            artists.push(artist);
        }
    }

    // Extract genres
    let genres = [];
    let genre_els = html_select(html, "a[href*='/genre/'], a[href*='/tag/'], .genre a, .genres a");
    for el in genre_els {
        let genre = element_text(el).trim();
        if genre != "" && !genres.contains(genre) && genre.len() < 50 {
            genres.push(genre);
        }
    }

    // Extract status
    let status = ();
    let info_els = html_select(html, ".info span, .info div, .status, .detail span");
    for el in info_els {
        let text = element_text(el).to_lower();
        if text.contains("ongoing") || text.contains("releasing") {
            status = "Ongoing";
            break;
        } else if text.contains("completed") || text.contains("complete") || text.contains("finished") {
            status = "Completed";
            break;
        } else if text.contains("hiatus") {
            status = "Hiatus";
            break;
        } else if text.contains("cancelled") || text.contains("canceled") {
            status = "Cancelled";
            break;
        }
    }

    // Extract year
    let year = ();
    let year_match = regex_find(`(19|20)\d{2}`, html);
    if year_match != () && year_match != "" {
        year = year_match;
    }

    #{
        id: slug,
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
        url = `${BASE_URL}/manga/${series_id}`;
    }

    let html = fetch_html(url);

    let chapters = [];
    let seen = #{};

    // Find chapter links - they contain the series slug and additional path
    let slug = extract_manga_slug(url);

    // Select all links that look like chapter links
    let chapter_links = html_select(html, "a[href*='/manga/']");

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Check if this is a chapter link (has additional path after slug)
        let path_after_manga = "";
        if href.contains("/manga/") {
            let parts = href.split("/manga/");
            if parts.len() > 1 {
                path_after_manga = parts[1];
            }
        }

        // Chapter links have format: /manga/series-slug/chapter-slug
        // So they must have at least one "/" in the path after /manga/
        if !path_after_manga.contains("/") {
            continue;
        }

        // Extract chapter slug (everything after the series slug)
        let path_parts = path_after_manga.split("/");
        if path_parts.len() < 2 {
            continue;
        }

        let chapter_slug = path_parts[1].split("?")[0];
        if chapter_slug == "" {
            continue;
        }

        // Skip duplicates
        if seen.contains(chapter_slug) {
            continue;
        }
        seen[chapter_slug] = true;

        // Get chapter text
        let chapter_text = element_text(link).trim();

        // Extract chapter number
        let ch_num = extract_chapter_number(href, chapter_text);

        // Get title if different from chapter number
        let title = ();
        if chapter_text != "" && !chapter_text.to_lower().starts_with("ch") {
            title = chapter_text;
        }

        // Build full URL
        let chapter_url = make_full_url(href);

        chapters.push(#{
            id: chapter_url,
            series_id: series_id,
            number: ch_num,
            title: title,
            volume: (),
            language: "en",
            scanlator: (),
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

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
    let seen_urls = #{};

    // Try multiple selectors for page images
    // VyManga typically uses a reader container with images
    let selectors = [
        ".reading-content img",
        ".chapter-content img",
        ".reader-content img",
        ".chapter-images img",
        "#chapter-content img",
        ".container-chapter-reader img",
        "img.chapter-img",
        ".page-img img"
    ];

    for selector in selectors {
        let page_imgs = html_select(html, selector);

        for img in page_imgs {
            let img_url = element_attr(img, "src");

            // Try various data attributes for lazy loading
            if img_url == () || img_url == "" || img_url.contains("blank.gif") {
                img_url = element_attr(img, "data-src");
            }
            if img_url == () || img_url == "" || img_url.contains("blank.gif") {
                img_url = element_attr(img, "data-lazy");
            }
            if img_url == () || img_url == "" || img_url.contains("blank.gif") {
                img_url = element_attr(img, "data-original");
            }
            if img_url == () || img_url == "" || img_url.contains("blank.gif") {
                img_url = element_attr(img, "data-lazy-src");
            }

            // Validate and add
            if img_url != () && img_url != "" && is_valid_page_url(img_url) {
                let full_url = make_full_url(img_url);

                // Skip duplicates
                if seen_urls.contains(full_url) {
                    continue;
                }
                seen_urls[full_url] = true;

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

        // If we found pages, stop looking
        if pages.len() > 0 {
            break;
        }
    }

    // Fallback: try to find any images in the main content area
    if pages.len() == 0 {
        let all_imgs = html_select(html, "article img, main img, .content img, #content img");

        for img in all_imgs {
            let img_url = element_attr(img, "src");
            if img_url == () || img_url == "" || img_url.contains("blank.gif") {
                img_url = element_attr(img, "data-src");
            }

            if img_url != () && img_url != "" && is_valid_page_url(img_url) {
                let full_url = make_full_url(img_url);

                if seen_urls.contains(full_url) {
                    continue;
                }
                seen_urls[full_url] = true;

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
    }

    pages
}

// ============================================================================
// Optional Functions
// ============================================================================

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/?page=${page}`;

    let html = fetch_html(url);

    let series = [];
    let seen = #{};

    // Find update items - similar to search
    let manga_links = html_select(html, "a[href*='/manga/']");

    for link in manga_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_manga_slug(href);
        if slug == "" {
            continue;
        }

        // Skip chapter links
        if href.contains("/manga/") {
            let parts = href.split("/manga/");
            if parts.len() > 1 && parts[1].contains("/") {
                continue;
            }
        }

        // Skip duplicates
        if seen.contains(slug) {
            continue;
        }
        seen[slug] = true;

        let title = element_text(link).trim();
        if title == "" || title.len() < 2 {
            continue;
        }

        // Clean title
        if title.to_lower().contains("chapter") {
            let parts = title.split("Chapter");
            if parts.len() > 0 {
                title = parts[0].trim();
            }
        }

        if title == "" {
            continue;
        }

        let cover_url = ();
        let imgs = html_select(link, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url.contains("blank.gif") {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }
        cover_url = make_full_url(cover_url);

        series.push(#{
            id: slug,
            title: title,
            url: make_full_url(href),
            cover_url: cover_url,
            updated_at: ()
        });
    }

    // Check for next page
    let has_more = false;
    let pagers = html_select(html, "nav a, .pagination a, a[href*='page=']");
    for pager in pagers {
        let pager_href = element_attr(pager, "href");
        if pager_href != () && pager_href.contains(`page=${page + 1}`) {
            has_more = true;
            break;
        }
    }

    // Assume there's more if we got results
    if !has_more && series.len() > 0 {
        has_more = page < 100;
    }

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    // VyManga may have a popular/top page
    let url = `${BASE_URL}/search?sort=views&page=${page}`;

    let html = fetch_html(url);

    let series = [];
    let seen = #{};

    let manga_links = html_select(html, "a[href*='/manga/']");

    for link in manga_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_manga_slug(href);
        if slug == "" {
            continue;
        }

        // Skip chapter links
        if href.contains("/manga/") {
            let parts = href.split("/manga/");
            if parts.len() > 1 && parts[1].contains("/") {
                continue;
            }
        }

        if seen.contains(slug) {
            continue;
        }
        seen[slug] = true;

        let title = element_text(link).trim();
        if title == "" || title.len() < 2 {
            continue;
        }

        // Clean title
        if title.to_lower().contains("chapter") {
            let parts = title.split("Chapter");
            if parts.len() > 0 {
                title = parts[0].trim();
            }
        }

        if title == "" {
            continue;
        }

        let cover_url = ();
        let imgs = html_select(link, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url.contains("blank.gif") {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }
        cover_url = make_full_url(cover_url);

        series.push(#{
            id: slug,
            title: title,
            url: make_full_url(href),
            cover_url: cover_url
        });
    }

    // Check for next page
    let has_more = false;
    let pagers = html_select(html, "nav a, .pagination a, a[href*='page=']");
    for pager in pagers {
        let pager_href = element_attr(pager, "href");
        if pager_href != () && pager_href.contains(`page=${page + 1}`) {
            has_more = true;
            break;
        }
    }

    if !has_more && series.len() > 0 {
        has_more = page < 50;
    }

    #{ series: series, has_more: has_more }
}
