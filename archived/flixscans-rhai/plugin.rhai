// Flix Scans Scraper Add-on (Rhai)
// Browser-based scraper for flixscans.net (Cloudflare protected)
// Uses WordPress Madara theme
//
// URL Patterns:
//   Home: /
//   Series List: /serie/ or /series/
//   Search: /?s={query}&post_type=wp-manga
//   Manga: /serie/{slug}/ or /manga/{slug}/
//   Chapter: /serie/{slug}/{chapter-slug}/
//   Reader: /serie/{slug}/{chapter-slug}/
//
// Available APIs:
//   HTTP (fallback): http_get(url), http_get_with_headers(url, headers)
//   Browser: browser_launch(), browser_goto(id, url), browser_wait_for_cloudflare(id, timeout)
//            browser_get_html(id), browser_close(id), browser_is_available()
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   Regex: regex_match(pattern, text), regex_find(pattern, text)

const BASE_URL = "https://flixscans.net";

// ============================================================================
// Helper Functions
// ============================================================================

/// Get headers for HTTP requests (fallback)
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch HTML using browser automation (bypasses Cloudflare)
/// Falls back to HTTP if browser not available
fn fetch_html(url) {
    // Try browser first if available (for Cloudflare bypass)
    if browser_is_available() {
        let browser_id = browser_launch();

        // Navigate and wait for Cloudflare
        browser_goto(browser_id, url);
        browser_wait_for_cloudflare(browser_id, 15000);  // 15 second timeout for CF challenge

        // Get the rendered HTML
        let html = browser_get_html(browser_id);

        // Close browser session to free resources
        browser_close(browser_id);

        return html;
    }

    // Fallback to HTTP (will likely fail with Cloudflare)
    http_get_with_headers(url, get_headers())
}

/// Extract series slug from URL
/// URL format: https://flixscans.net/serie/{slug}/ or /manga/{slug}/
fn extract_slug(url) {
    // Try /serie/ pattern first
    let parts = url.split("/serie/");
    if parts.len() > 1 {
        let slug = parts[1];
        // Remove trailing slash and any chapter path
        let slug_parts = slug.split("/");
        if slug_parts.len() > 0 && slug_parts[0] != "" {
            return slug_parts[0];
        }
    }

    // Try /manga/ pattern
    let parts = url.split("/manga/");
    if parts.len() > 1 {
        let slug = parts[1];
        let slug_parts = slug.split("/");
        if slug_parts.len() > 0 && slug_parts[0] != "" {
            return slug_parts[0];
        }
    }

    // Try /series/ pattern
    let parts = url.split("/series/");
    if parts.len() > 1 {
        let slug = parts[1];
        let slug_parts = slug.split("/");
        if slug_parts.len() > 0 && slug_parts[0] != "" {
            return slug_parts[0];
        }
    }

    ""
}

/// Map status text to standard format
fn map_status(status_text) {
    let lower = status_text.to_lower();
    if lower.contains("ongoing") || lower.contains("releasing") {
        return "Ongoing";
    }
    if lower.contains("completed") || lower.contains("finished") {
        return "Completed";
    }
    if lower.contains("hiatus") {
        return "Hiatus";
    }
    if lower.contains("cancelled") || lower.contains("dropped") {
        return "Cancelled";
    }
    ()
}

/// Extract chapter number from URL or title
fn extract_chapter_number(url, title) {
    // Try URL first - patterns like chapter-1, chapter-10, chapter-10-5
    let url_lower = url.to_lower();

    // Pattern: chapter-{number}
    if url_lower.contains("chapter-") {
        let parts = url_lower.split("chapter-");
        if parts.len() > 1 {
            let num_part = parts[1];
            // Clean up - remove trailing slash and extra path
            num_part = num_part.split("/")[0];
            num_part = num_part.split("?")[0];

            // Handle decimal chapters like "chapter-10-5" -> "10.5"
            if num_part.contains("-") {
                let num_parts = num_part.split("-");
                if num_parts.len() >= 2 {
                    // Check if second part is a number (decimal)
                    let second = num_parts[1];
                    if second.len() > 0 && second.len() <= 2 {
                        return `${num_parts[0]}.${second}`;
                    }
                }
                return num_parts[0];
            }

            return num_part;
        }
    }

    // Try title - pattern: "Chapter 1", "Ch. 10", "Ch 10.5"
    let title_lower = title.to_lower();

    if title_lower.contains("chapter") {
        let parts = title_lower.split("chapter");
        if parts.len() > 1 {
            let after = parts[1].trim();
            // Extract number
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

    // Try ch. or ch pattern
    if title_lower.contains("ch.") || title_lower.contains("ch ") {
        let parts = title_lower.split("ch");
        if parts.len() > 1 {
            let after = parts[1].trim();
            after = after.trim_start_matches(".");
            after = after.trim();
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

    "0"
}

/// Parse float from string (for chapter sorting)
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
        id: "flixscans-rhai",
        name: "Flix Scans",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // Madara theme search URL: /?s={query}&post_type=wp-manga
    let encoded_query = query.replace(" ", "+");
    let url = `${BASE_URL}/?s=${encoded_query}&post_type=wp-manga`;

    // Add pagination if not first page
    if page > 1 {
        url = `${BASE_URL}/page/${page}/?s=${encoded_query}&post_type=wp-manga`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let query_lower = query.to_lower();

    // Madara theme selectors for search results
    let items = html_select(doc, "div.c-tabs-item__content");

    // Alternative selectors if above doesn't work
    if items.len() == 0 {
        items = html_select(doc, "div.row.c-tabs-item__content");
    }
    if items.len() == 0 {
        items = html_select(doc, "div.page-item-detail");
    }

    for item in items {
        // Get title and link
        let title_links = html_select(item, "h3 a, h4 a, .post-title a");
        if title_links.len() == 0 {
            continue;
        }

        let link = title_links[0];
        let href = element_attr(link, "href");
        let title = element_text(link).trim();

        if href == () || href == "" || title == "" {
            continue;
        }

        // Extract slug
        let slug = extract_slug(href);
        if slug == "" {
            continue;
        }

        // Get cover image
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "src");
            }
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-lazy-src");
            }
        }

        // Get genres
        let genres = [];
        let genre_links = html_select(item, ".mg_genres a, .genres a, a[href*='genre']");
        for g in genre_links {
            let genre = element_text(g).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
            }
        }

        // Get status
        let status = ();
        let status_spans = html_select(item, ".mg_status, .summary-content, span.status");
        for span in status_spans {
            let text = element_text(span);
            let mapped = map_status(text);
            if mapped != () {
                status = mapped;
                break;
            }
        }

        series.push(#{
            id: slug,
            title: title,
            url: href,
            cover_url: cover_url,
            alternate_titles: [],
            authors: [],
            artists: [],
            status: status,
            genres: genres,
            tags: [],
            description: ()
        });
    }

    // Check for next page
    let has_more = false;
    let next_links = html_select(doc, "a.next, .nextpostslink, a[rel='next']");
    if next_links.len() > 0 {
        has_more = true;
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let slug = id_or_url;

    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/serie/${id_or_url}/`;
    } else {
        slug = extract_slug(id_or_url);
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Extract title
    let title = "";
    let title_els = html_select(doc, "h1.post-title, h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover
    let cover_url = ();
    let cover_imgs = html_select(doc, ".summary_image img, .thumb img, img.wp-post-image");
    if cover_imgs.len() > 0 {
        cover_url = element_attr(cover_imgs[0], "data-src");
        if cover_url == () || cover_url == "" {
            cover_url = element_attr(cover_imgs[0], "src");
        }
        if cover_url == () || cover_url == "" {
            cover_url = element_attr(cover_imgs[0], "data-lazy-src");
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(doc, ".description-summary p, .summary__content p, div.entry-content p, .manga-excerpt p");
    if desc_els.len() > 0 {
        let desc_parts = [];
        for p in desc_els {
            let text = element_text(p).trim();
            if text != "" && text.len() > 10 {
                desc_parts.push(text);
            }
        }
        if desc_parts.len() > 0 {
            description = "";
            for part in desc_parts {
                if description != "" {
                    description += " ";
                }
                description += part;
            }
        }
    }

    // Alternative description selector
    if description == () || description == "" {
        let desc_div = html_select(doc, ".summary__content, .manga-excerpt, .description-summary");
        if desc_div.len() > 0 {
            description = element_text(desc_div[0]).trim();
        }
    }

    // Extract metadata
    let authors = [];
    let artists = [];
    let genres = [];
    let alt_titles = [];
    let status = ();
    let year = ();

    // Parse summary rows (Madara theme)
    let summary_rows = html_select(doc, ".post-content_item, .summary-content");
    for row in summary_rows {
        let text = element_text(row).to_lower();

        // Authors
        if text.contains("author") {
            let author_links = html_select(row, "a");
            for a in author_links {
                let author = element_text(a).trim();
                if author != "" && !authors.contains(author) {
                    authors.push(author);
                }
            }
        }

        // Artists
        if text.contains("artist") {
            let artist_links = html_select(row, "a");
            for a in artist_links {
                let artist = element_text(a).trim();
                if artist != "" && !artists.contains(artist) {
                    artists.push(artist);
                }
            }
        }

        // Genres
        if text.contains("genre") {
            let genre_links = html_select(row, "a");
            for g in genre_links {
                let genre = element_text(g).trim();
                if genre != "" && !genres.contains(genre) {
                    genres.push(genre);
                }
            }
        }

        // Status
        if text.contains("status") {
            let mapped = map_status(text);
            if mapped != () {
                status = mapped;
            }
        }

        // Alternative titles
        if text.contains("alternative") || text.contains("other name") || text.contains("alt name") {
            let alt_text = element_text(row);
            let parts = alt_text.split(":");
            if parts.len() > 1 {
                let alts = parts[1].split(",");
                for alt in alts {
                    let cleaned = alt.trim();
                    if cleaned != "" && cleaned != title && !alt_titles.contains(cleaned) {
                        alt_titles.push(cleaned);
                    }
                }
            }
        }

        // Year/Release
        if text.contains("release") || text.contains("year") {
            let year_match = regex_find("\\b(19|20)\\d{2}\\b", text);
            if year_match != () && year_match != "" {
                year = year_match;
            }
        }
    }

    // Alternative genre extraction
    if genres.len() == 0 {
        let genre_links = html_select(doc, "a[href*='genre'], .genres a, .mg_genres a");
        for g in genre_links {
            let genre = element_text(g).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
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
        url = `${BASE_URL}/serie/${series_id}/`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    // Madara theme chapter list selectors
    let chapter_links = html_select(doc, "li.wp-manga-chapter a, ul.version-chap li a, .listing-chapters_wrap a");

    // Alternative selectors
    if chapter_links.len() == 0 {
        chapter_links = html_select(doc, "div.listing-chapters a, ul.main a[href*='chapter']");
    }
    if chapter_links.len() == 0 {
        chapter_links = html_select(doc, "a[href*='chapter-']");
    }

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

        // Skip non-chapter links
        if !href.contains("chapter") && !href.contains("/serie/") {
            continue;
        }

        // Make URL absolute
        let chapter_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                chapter_url = `${BASE_URL}${href}`;
            } else {
                chapter_url = `${BASE_URL}/${href}`;
            }
        }

        // Get chapter text
        let chapter_text = element_text(link).trim();

        // Extract chapter number
        let chapter_num = extract_chapter_number(href, chapter_text);

        // Clean up chapter title
        let chapter_title = chapter_text;
        if chapter_title.to_lower().contains("chapter") {
            // Keep as is
        }

        chapters.push(#{
            id: chapter_url,
            series_id: series_id,
            number: chapter_num,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: "Flix Scans",
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // Sort chapters by number (descending - newest first, like most Madara sites)
    chapters.sort(|a, b| {
        let num_a = parse_float(a.number);
        let num_b = parse_float(b.number);
        if num_a > num_b { -1 } else if num_a < num_b { 1 } else { 0 }
    });

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}${chapter_id}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let pages = [];
    let idx = 0;

    // Madara theme page image selectors
    let page_imgs = html_select(doc, "div.reading-content img, div.page-break img, .chapter-content img");

    // Alternative selectors
    if page_imgs.len() == 0 {
        page_imgs = html_select(doc, "div.entry-content img, div.text-left img");
    }
    if page_imgs.len() == 0 {
        page_imgs = html_select(doc, "img.wp-manga-chapter-img");
    }

    for img in page_imgs {
        let img_url = element_attr(img, "data-src");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "src");
        }
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-lazy-src");
        }

        // Skip invalid images
        if img_url == () || img_url == "" {
            continue;
        }

        // Skip placeholder, icons, ads
        let img_lower = img_url.to_lower();
        if img_lower.contains("placeholder") || img_lower.contains("loading") {
            continue;
        }
        if img_lower.contains("icon") || img_lower.contains("logo") || img_lower.contains("avatar") {
            continue;
        }
        if img_lower.contains("/ad") || img_lower.contains("banner") || img_lower.contains("promo") {
            continue;
        }

        // Make URL absolute
        if !img_url.starts_with("http") {
            if img_url.starts_with("//") {
                img_url = `https:${img_url}`;
            } else if img_url.starts_with("/") {
                img_url = `${BASE_URL}${img_url}`;
            }
        }

        // Clean up URL (trim whitespace)
        img_url = img_url.trim();

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

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = BASE_URL;
    if page > 1 {
        url = `${BASE_URL}/page/${page}/`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    // Try various selectors for latest updates
    let items = html_select(doc, "div.page-item-detail, .page-listing-item");

    // Alternative selectors
    if items.len() == 0 {
        items = html_select(doc, "div.col-6.col-md-3.badge-pos-1");
    }
    if items.len() == 0 {
        items = html_select(doc, "div.item-thumb");
    }

    for item in items {
        let links = html_select(item, "a[href*='serie'], a[href*='manga']");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || seen.contains(slug) {
            continue;
        }
        seen[slug] = true;

        // Get title
        let title = "";
        let title_els = html_select(item, "h3 a, h5 a, .post-title a, a.series-title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(link).trim();
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "src");
            }
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-lazy-src");
            }
        }

        if title != "" {
            let series_url = href;
            if !href.starts_with("http") {
                series_url = `${BASE_URL}${href}`;
            }

            series.push(#{
                id: slug,
                title: title,
                url: series_url,
                cover_url: cover_url,
                updated_at: ()
            });
        }
    }

    // Check for next page
    let has_more = false;
    let next_links = html_select(doc, "a.next, .nextpostslink, a[rel='next']");
    if next_links.len() > 0 {
        has_more = true;
    }

    // Limit pagination
    if page >= 20 {
        has_more = false;
    }

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    // Try popular/trending page - common Madara theme paths
    let url = `${BASE_URL}/serie/?m_orderby=views`;
    if page > 1 {
        url = `${BASE_URL}/serie/page/${page}/?m_orderby=views`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];

    // Select manga items
    let items = html_select(doc, "div.page-item-detail, div.manga");

    for item in items {
        let links = html_select(item, "a[href*='serie'], a[href*='manga']");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" {
            continue;
        }

        // Get title
        let title = "";
        let title_els = html_select(item, "h3 a, h5 a, .post-title a");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(link).trim();
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "src");
            }
        }

        if title != "" {
            let series_url = href;
            if !href.starts_with("http") {
                series_url = `${BASE_URL}${href}`;
            }

            series.push(#{
                id: slug,
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
    }

    series
}
