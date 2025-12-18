// Asura Scans Scraper Add-on (Rhai)
// Browser-based scraper for asuracomic.net (Cloudflare protected)
//
// Available APIs:
//   HTTP (fallback): http_get(url), http_get_with_headers(url, headers)
//   Browser: browser_launch(), browser_goto(id, url), browser_wait_for_cloudflare(id, timeout)
//            browser_get_html(id), browser_close(id), browser_is_available()
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   Regex: regex_match(pattern, text), regex_find(pattern, text)

const BASE_URL = "https://asuracomic.net";

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
    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    };
    http_get_with_headers(url, headers)
}

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "asurascans",
        name: "Asura Scans",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let url = `${BASE_URL}/series?page=${page}`;
    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let query_lower = query.to_lower();

    // Select all series links
    for link in html_select(doc, "a[href*='series/']") {
        let href = element_attr(link, "href");

        // Skip chapter links
        if href == () || href.contains("/chapter/") {
            continue;
        }

        // Extract slug from href
        let slug = "";
        if href.starts_with("series/") {
            slug = href.replace("series/", "");
        } else if href.contains("/series/") {
            let parts = href.split("/series/");
            if parts.len() > 1 {
                slug = parts[1];
            }
        }

        // Skip if slug has additional paths or is empty
        if slug.contains("/") || slug == "" {
            continue;
        }

        // Get title from span or link text
        let title_spans = html_select(link, "span");
        let title = if title_spans.len() > 0 { element_text(title_spans[0]) } else { element_text(link) };

        // Clean up title
        title = title.trim();
        if title.contains("Chapter") {
            let parts = title.split("Chapter");
            title = parts[0].trim();
        }
        title = title.replace("MANHWA", "").replace("MANGA", "").trim();

        // Skip invalid titles
        if title.len() < 3 || title.len() > 150 {
            continue;
        }

        // Filter by search query if provided
        if query != "" && !title.to_lower().contains(query_lower) {
            continue;
        }

        // Extract cover image
        let imgs = html_select(link, "img");
        let cover_url = if imgs.len() > 0 { element_attr(imgs[0], "src") } else { () };

        let series_url = `${BASE_URL}/series/${slug}`;

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

    // Check for next page
    let next_links = html_select(doc, "a[rel='next']");
    let has_more = next_links.len() > 0;

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let slug = id_or_url;

    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/series/${id_or_url}`;
    } else {
        // Extract slug from URL
        let parts = id_or_url.split("/series/");
        if parts.len() > 1 {
            slug = parts[1].split("/")[0];
        }
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Extract title
    let title_els = html_select(doc, "h1");
    let title = if title_els.len() > 0 { element_text(title_els[0]).trim() } else { "" };

    // Extract cover
    let cover_els = html_select(doc, "img.rounded-md, img[alt='poster']");
    let cover_url = if cover_els.len() > 0 { element_attr(cover_els[0], "src") } else { () };

    // Extract description
    let desc_els = html_select(doc, "div.prose, div.description");
    let description = if desc_els.len() > 0 { element_text(desc_els[0]).trim() } else { () };

    // Extract status
    let status = ();
    for span in html_select(doc, "span") {
        let text = element_text(span).to_lower();
        if text.contains("ongoing") {
            status = "Ongoing";
            break;
        } else if text.contains("completed") {
            status = "Completed";
            break;
        } else if text.contains("hiatus") {
            status = "Hiatus";
            break;
        }
    }

    // Extract genres
    let genres = [];
    for genre_link in html_select(doc, "a[href*='genre/']") {
        let genre = element_text(genre_link).trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Extract authors
    let authors = [];
    for author_el in html_select(doc, "a[href*='author/'], span.author") {
        let author = element_text(author_el).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    #{
        id: slug,
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
        content_rating: "suggestive",
        url: url,
        extra: #{}
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let url = series_id;

    if !series_id.starts_with("http") {
        url = `${BASE_URL}/series/${series_id}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    // Find all chapter links
    for link in html_select(doc, "a[href*='/chapter/']") {
        let href = element_attr(link, "href");
        if href == () {
            continue;
        }

        // Extract chapter number from URL
        let chapter_num = "";
        let parts = href.split("/chapter/");
        if parts.len() > 1 {
            chapter_num = parts[1].split("/")[0].split("?")[0];
        }

        // Skip if already seen
        if seen.contains(chapter_num) {
            continue;
        }
        seen[chapter_num] = true;

        // Build full URL
        let chapter_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                chapter_url = `${BASE_URL}${href}`;
            } else {
                chapter_url = `${BASE_URL}/${href}`;
            }
        }

        // Extract title if available
        let title_spans = html_select(link, "span");
        let title = if title_spans.len() > 0 { element_text(title_spans[0]).trim() } else { () };

        chapters.push(#{
            id: chapter_url,
            series_id: series_id,
            number: chapter_num,
            title: title,
            volume: (),
            language: "en",
            scanlator: "Asura Scans",
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // Sort chapters by number
    chapters.sort(|a, b| {
        let num_a = parse_float(a.number);
        let num_b = parse_float(b.number);
        if num_a < num_b { -1 } else if num_a > num_b { 1 } else { 0 }
    });

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}/series/${chapter_id}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let pages = [];
    let idx = 0;

    // Find all page images
    for img in html_select(doc, "div.reader-content img, div.chapter-images img, img[src*='wp-content']") {
        let img_url = element_attr(img, "src");
        if img_url == () {
            img_url = element_attr(img, "data-src");
        }

        if img_url != () && img_url.contains("http") {
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

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}?page=${page}`;
    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];

    for item in html_select(doc, "div.latest-update-item, article.update-item") {
        let links = html_select(item, "a[href*='series/']");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        let slug = "";
        if href.contains("/series/") {
            let parts = href.split("/series/");
            if parts.len() > 1 {
                slug = parts[1].split("/")[0];
            }
        }

        let title = element_text(link).trim();
        let imgs = html_select(item, "img");
        let cover_url = if imgs.len() > 0 { element_attr(imgs[0], "src") } else { () };

        if slug != "" && title != "" {
            series.push(#{
                id: slug,
                title: title,
                url: `${BASE_URL}/series/${slug}`,
                cover_url: cover_url,
                updated_at: ()
            });
        }
    }

    let next_links = html_select(doc, "a[rel='next']");
    let has_more = next_links.len() > 0;

    #{ series: series, has_more: has_more }
}

/// Helper: Parse float from string
fn parse_float(s) {
    if s == () { return 0.0; }
    let result = 0.0;
    // Simple float parsing
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
