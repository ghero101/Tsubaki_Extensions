// Asura Scans Scraper Add-on (Rhai)
// HTTP-based scraper for asuracomic.net (Next.js server-rendered)
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   Regex: regex_match(pattern, text), regex_find(pattern, text)

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
        capability_level: "http_only"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let url = `${BASE_URL}/series?page=${page}`;
    let html = fetch_html(url);

    let series = [];
    let query_lower = query.to_lower();
    let seen = #{};

    // Split HTML by series card anchor tags to extract slug+cover pairs together
    // Each card starts with <a href="series/SLUG"> and contains <img src="COVER">
    // Find the main grid section first (skip preload/header images)
    let grid_start = "grid grid-cols-2 sm:grid-cols-2 md:grid-cols-5";
    let main_html = html;
    if html.contains(grid_start) {
        let parts = html.split(grid_start);
        if parts.len() > 1 {
            main_html = parts[1];
        }
    }

    // Extract card data: split by series links to process each card
    let card_parts = main_html.split("<a href=\"series/");

    let slugs = [];
    let covers = [];
    let titles = [];

    for i in 1..card_parts.len() {
        let card = card_parts[i];

        // Extract slug (everything before the closing quote)
        let slug = "";
        let quote_pos = card.index_of("\"");
        if quote_pos > 0 {
            slug = card.sub_string(0, quote_pos);
        }

        if slug == "" || slug.contains("/") || slug.len() > 100 {
            continue;
        }

        // Skip duplicates
        if seen.contains(slug) {
            continue;
        }
        seen[slug] = true;
        slugs.push(slug);

        // Extract cover from this card section (first img src after the anchor)
        // Look for both webp and gif formats
        let cover = ();

        // Try webp first (most common)
        let webp_match = regex_find_all("https://gg\\.asuracomic\\.net/storage/media/[0-9]+/conversions/[^\"\\\\\\s]+thumb-small\\.webp", card);
        if webp_match.len() > 0 {
            cover = webp_match[0];
        }

        // Try gif if no webp found
        if cover == () {
            let gif_match = regex_find_all("https://gg\\.asuracomic\\.net/storage/media/[0-9]+/[^\"\\\\\\s]+\\.gif", card);
            if gif_match.len() > 0 {
                cover = gif_match[0];
            }
        }

        // Try any image as last resort
        if cover == () {
            let any_img = regex_find_all("https://gg\\.asuracomic\\.net/storage/media/[0-9]+/[^\"\\\\\\s]+\\.(webp|gif|jpg|png)", card);
            if any_img.len() > 0 {
                cover = any_img[0];
            }
        }

        covers.push(cover);

        // Extract title from this card (span with font-bold)
        let title = slug.replace("-", " ");
        // Look for the title span pattern
        if card.contains("font-bold\">") {
            let title_parts = card.split("font-bold\">");
            if title_parts.len() > 1 {
                let title_text = title_parts[1];
                let end_pos = title_text.index_of("<");
                if end_pos > 0 && end_pos < 100 {
                    title = title_text.sub_string(0, end_pos);
                }
            }
        }
        titles.push(title);
    }

    // Build series list
    for idx in 0..slugs.len() {
        let slug = slugs[idx];
        let title = if idx < titles.len() { titles[idx] } else { slug.replace("-", " ") };
        let cover_url = if idx < covers.len() { covers[idx] } else { () };

        // Filter by query
        if query != "" && !title.to_lower().contains(query_lower) {
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

    // has_more is true if we got a full page of results (15 series)
    let count = series.len();
    let has_more = if count >= 15 { true } else { false };
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
