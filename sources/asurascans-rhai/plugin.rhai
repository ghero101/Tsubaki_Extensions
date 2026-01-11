// Asura Scans Scraper Add-on (Rhai)
// Browser automation scraper for asuracomic.net (Next.js SPA with client-side pagination)
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   Regex: regex_match(pattern, text), regex_find(pattern, text)
//   Browser: browser_launch_stealth(), browser_goto(), browser_scroll_to_bottom(),
//            browser_click(), browser_get_html(), browser_close()

const BASE_URL = "https://asuracomic.net";

/// Get standard headers for requests
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch HTML using HTTP
fn fetch_html(url) {
    http_get_with_headers(url, get_headers())
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

/// Extract series from HTML document
fn extract_series_from_html(html, query, seen) {
    let series = [];
    let query_lower = if query != () { query.to_lower() } else { "" };

    let doc = html_parse(html);

    // Series cards are anchor tags with href containing "series/"
    let items = html_select(doc, "a[href*='series/']");

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" {
            continue;
        }

        // Extract slug from href (format: "series/slug-id" or full URL)
        let slug = "";
        if href.contains("/series/") {
            let parts = href.split("/series/");
            if parts.len() > 1 {
                slug = parts[1].split("/")[0].split("?")[0];
            }
        } else if href.starts_with("series/") {
            slug = href.sub_string(7, href.len()).split("/")[0].split("?")[0];
        }

        // Validate slug
        if slug == "" || slug.len() > 100 {
            continue;
        }

        // Skip duplicates
        if seen.contains(slug) {
            continue;
        }
        seen[slug] = true;

        // Get title from nested span with font-bold and block classes
        let title = "";

        // Try to find the title span (has "block" class)
        let title_spans = html_select(item, "span.block.font-bold");
        if title_spans.len() > 0 {
            title = element_text(title_spans[0]).trim();
        }

        // Fallback: look for div with font-weight style
        if title == "" || title == "MANHWA" || title == "MANGA" {
            let div_els = html_select(item, "div");
            for div_el in div_els {
                let div_text = element_text(div_el).trim();
                if div_text != "" && div_text.len() < 80 && div_text != "MANHWA" && div_text != "MANGA" {
                    if !div_text.starts_with("Chapter") && !div_text.contains("<!--") {
                        title = div_text;
                        break;
                    }
                }
            }
        }

        // Last fallback: convert slug to title (remove trailing ID)
        if title == "" || title == "MANHWA" || title == "MANGA" {
            let parts = slug.split("-");
            if parts.len() > 1 {
                let title_parts = [];
                for i in 0..(parts.len() - 1) {
                    title_parts.push(parts[i]);
                }
                title = title_parts.reduce(|a, b| a + " " + b);
                let words = title.split(" ");
                let capitalized = [];
                for word in words {
                    if word.len() > 0 {
                        let first = word.sub_string(0, 1).to_upper();
                        let rest = if word.len() > 1 { word.sub_string(1, word.len()) } else { "" };
                        capitalized.push(first + rest);
                    }
                }
                title = capitalized.reduce(|a, b| a + " " + b);
            } else {
                title = slug.replace("-", " ");
            }
        }

        // Get cover image
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        // Filter by query if provided
        if query != "" && query_lower != "" && !title.to_lower().contains(query_lower) {
            continue;
        }

        series.push(#{
            id: slug,
            title: title,
            url: `${BASE_URL}/series/${slug}`,
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

/// Search for series matching query (uses browser automation for pagination)
fn search_series(query, page, auth) {
    // Check if browser is available
    if !browser_is_available() {
        // Fallback to HTTP-only (limited to initial page load)
        let url = `${BASE_URL}/series?page=1`;
        let html = fetch_html(url);
        let seen = #{};
        let series = extract_series_from_html(html, query, seen);
        return #{ series: series, has_more: false, total: () };
    }

    // Use browser automation for full catalog access
    let session_id = browser_launch_stealth();

    // Navigate directly to the requested page
    let url = `${BASE_URL}/series?page=${page}`;
    browser_goto(session_id, url);

    // Wait for the series grid to load (JavaScript needs time to render)
    browser_wait_for_selector(session_id, "div.grid a[href*='series/']", 15000);

    // Get the rendered HTML
    let html = browser_get_html(session_id);

    // Clean up browser session
    browser_close(session_id);

    // Extract series from the HTML
    let seen = #{};
    let series = extract_series_from_html(html, query, seen);

    // Estimate has_more based on results (site shows ~20 per page)
    let has_more = series.len() >= 15;

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
            slug = parts[1].split("/")[0].split("?")[0];
        }
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Extract title from the bold span (main title element)
    let title = "";
    let title_els = html_select(doc, "span.text-xl.font-bold");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }
    // Fallback: try title tag
    if title == "" {
        let title_tags = html_select(doc, "title");
        if title_tags.len() > 0 {
            title = element_text(title_tags[0]).trim();
            // Remove " - Asura Scans" suffix
            if title.contains(" - Asura") {
                let parts = title.split(" - Asura");
                title = parts[0].trim();
            }
        }
    }

    // Extract cover from poster image
    let cover_url = ();
    let cover_els = html_select(doc, "img[alt='poster']");
    if cover_els.len() > 0 {
        cover_url = element_attr(cover_els[0], "src");
    }
    // Fallback: try rounded image
    if cover_url == () {
        let rounded_imgs = html_select(doc, "img.rounded");
        if rounded_imgs.len() > 0 {
            cover_url = element_attr(rounded_imgs[0], "src");
        }
    }

    // Extract description from the synopsis paragraph
    let description = ();
    let desc_els = html_select(doc, "span.font-medium.text-sm.text-\\[\\#A2A2A2\\]");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    // Extract status from the status row
    let status = ();
    for h3 in html_select(doc, "h3.text-sm") {
        let text = element_text(h3).trim().to_lower();
        if text == "ongoing" {
            status = "Ongoing";
            break;
        } else if text == "completed" {
            status = "Completed";
            break;
        } else if text == "hiatus" {
            status = "Hiatus";
            break;
        }
    }

    // Extract genres from genre buttons
    let genres = [];
    // Look for buttons after the "Genres" heading
    for btn in html_select(doc, "button.bg-\\[\\#343434\\]") {
        let genre = element_text(btn).trim();
        if genre != "" && genre.len() < 30 && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    #{
        id: slug,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: [],
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
    let slug = series_id;

    if !series_id.starts_with("http") {
        url = `${BASE_URL}/series/${series_id}`;
    } else {
        // Extract slug from URL
        let parts = series_id.split("/series/");
        if parts.len() > 1 {
            slug = parts[1].split("/")[0].split("?")[0];
        }
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    // Find all chapter links - they're in format "slug/chapter/N" or full URLs
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

        // Skip empty or invalid chapter numbers
        if chapter_num == "" {
            continue;
        }

        // Skip if already seen
        if seen.contains(chapter_num) {
            continue;
        }
        seen[chapter_num] = true;

        // Build full URL - handle relative URLs like "slug/chapter/N"
        let chapter_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                chapter_url = `${BASE_URL}${href}`;
            } else if href.contains("/chapter/") {
                // Relative URL like "slug/chapter/N" - need to add /series/ prefix
                chapter_url = `${BASE_URL}/series/${href}`;
            } else {
                chapter_url = `${BASE_URL}/${href}`;
            }
        }

        // Extract title from h3 inside the link
        let title = ();
        let h3_els = html_select(link, "h3");
        if h3_els.len() > 0 {
            let h3_text = element_text(h3_els[0]).trim();
            // Extract any title text after chapter number
            if h3_text.contains("{") {
                // Has a title like "{S2 Start}"
                let title_parts = h3_text.split("{");
                if title_parts.len() > 1 {
                    title = "{" + title_parts[1];
                }
            }
        }

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

    // Sort chapters by number (descending - newest first is default, but we want ascending)
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

    let pages = [];
    let idx = 0;
    let seen = #{};

    // Images are embedded in escaped JSON in Next.js page data
    // Extract URLs using regex - pattern matches page images
    // Format: https://gg.asuracomic.net/storage/media/XXXXX/conversions/FILENAME-optimized.webp
    // Filenames can be alphanumeric IDs like "01K0SK60JGY8VDJQQ2H7YJHHMW" or hex IDs like "5357f1a1"
    let matches = regex_find_all("https://gg\\.asuracomic\\.net/storage/media/\\d+/conversions/[A-Za-z0-9]+-optimized\\.webp", html);

    for img_url in matches {
        // Skip duplicates
        if seen.contains(img_url) {
            continue;
        }
        seen[img_url] = true;

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

/// Get latest updates - reuses search_series logic for home page
fn get_latest_updates(page, auth) {
    // The home page and series page have similar structure
    // Use search_series with empty query to get latest
    let result = search_series("", page, auth);

    // Convert to latest updates format
    let series = [];
    for s in result.series {
        series.push(#{
            id: s.id,
            title: s.title,
            url: s.url,
            cover_url: s.cover_url,
            updated_at: ()
        });
    }

    #{ series: series, has_more: result.has_more }
}

/// Legacy get_latest_updates_old - kept for reference
fn get_latest_updates_old(page, auth) {
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
