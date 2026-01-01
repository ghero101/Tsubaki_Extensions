// MangaPill Scraper Add-on (Rhai)
// HTTP-only scraper for mangapill.com
//
// URL Patterns:
//   Search: /search?q={query}&type=&status=
//   Manga:  /manga/{id}/{slug}
//   Chapter: /chapters/{id}-{chapter_code}/{slug}
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   JSON: json_parse(text)
//   Regex: regex_find(pattern, text), regex_find_all(pattern, text)
//   String: url_encode(text)

const BASE_URL = "https://mangapill.com";

// ============================================================================
// Helper Functions
// ============================================================================

/// Get headers for requests
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch HTML with headers
fn fetch_html(url) {
    http_get_with_headers(url, get_headers())
}

/// Extract manga ID from URL
/// URL format: /manga/{id}/{slug} or https://mangapill.com/manga/{id}/{slug}
fn extract_manga_id(url) {
    let parts = url.split("/manga/");
    if parts.len() > 1 {
        let after_manga = parts[1];
        let id_parts = after_manga.split("/");
        if id_parts.len() > 0 {
            return id_parts[0];
        }
    }
    ""
}

/// Extract slug from manga URL
fn extract_slug(url) {
    let parts = url.split("/manga/");
    if parts.len() > 1 {
        let after_manga = parts[1];
        let id_parts = after_manga.split("/");
        if id_parts.len() > 1 {
            return id_parts[1].split("?")[0];
        }
    }
    ""
}

/// Map status text to standard format
fn map_status(status_text) {
    let lower = status_text.to_lower();
    if lower.contains("finished") || lower.contains("completed") {
        return "Completed";
    }
    if lower.contains("publishing") || lower.contains("ongoing") {
        return "Ongoing";
    }
    if lower.contains("hiatus") {
        return "Hiatus";
    }
    if lower.contains("cancelled") || lower.contains("discontinued") {
        return "Cancelled";
    }
    ()
}

/// Clean title by removing chapter numbers and duplicates
/// Handles patterns like "Series Name Chapter 123" or "Series Name Series Name"
fn clean_title(raw_title) {
    let title = raw_title.trim();

    // Remove " Chapter X" or " Chapter X.X" patterns from end
    let chapter_match = regex_find("^(.+?)\\s+Chapter\\s+[\\d.]+$", title);
    if chapter_match != () && chapter_match != "" {
        title = chapter_match.trim();
    }

    // Handle duplicated titles (e.g., "Title Title")
    let half_len = title.len() / 2;
    if half_len > 3 {
        let first_half = title.sub_string(0, half_len).trim();
        let second_half = title.sub_string(half_len).trim();
        if first_half == second_half {
            title = first_half;
        }
    }

    title
}

/// Extract chapter number from chapter URL or title
/// Chapter URL format: /chapters/{manga_id}-{chapter_code}/{slug}
/// Chapter code format: 10001000 = chapter 1, 10010000 = chapter 10, 10100500 = chapter 100.5
fn extract_chapter_number(url, title) {
    // Try to extract from URL pattern first
    // URL: /chapters/3069-10001000/naruto-chapter-1
    let parts = url.split("/chapters/");
    if parts.len() > 1 {
        let after_chapters = parts[1];
        let dash_parts = after_chapters.split("-");
        if dash_parts.len() >= 2 {
            // Second part is the chapter code
            let chapter_code = dash_parts[1].split("/")[0];
            if chapter_code.len() >= 8 {
                // Decode: first digit is always 1, next 4 are chapter, last 3 are decimal
                // 10001000 -> chapter 1.0
                // 10010000 -> chapter 10.0
                // 10100500 -> chapter 100.5
                let ch_part = chapter_code.sub_string(1, 4);
                // Remove leading zeros
                while ch_part.starts_with("0") && ch_part.len() > 1 {
                    ch_part = ch_part.sub_string(1);
                }

                let decimal_part = chapter_code.sub_string(5, 3);
                // Remove leading zeros from decimal
                while decimal_part.starts_with("0") && decimal_part.len() > 1 {
                    decimal_part = decimal_part.sub_string(1);
                }

                if decimal_part != "0" && decimal_part != "" {
                    return `${ch_part}.${decimal_part}`;
                }
                return ch_part;
            }
        }
    }

    // Fallback: try to extract from title
    // Title format: "Chapter 1" or "Chapter 100.5"
    let title_lower = title.to_lower();
    let chapter_match = regex_find("chapter[\\s-]*(\\d+\\.?\\d*)", title_lower);
    if chapter_match != () && chapter_match != "" {
        return chapter_match;
    }

    "0"
}

// ============================================================================
// Required Interface Functions
// ============================================================================

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangapill-rhai",
        name: "MangaPill",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // MangaPill search URL: /search?q={query}&type=&status=
    // Convert spaces to + and encode
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/search?q=${encoded_query}&type=&status=`;

    // Note: MangaPill doesn't seem to support pagination in search
    // All results are returned on one page
    if page > 1 {
        return #{ series: [], has_more: false, total: 0 };
    }

    let html = fetch_html(url);

    let series = [];
    let seen = #{};

    // Select manga items from the grid
    // Selector: div.my-3.grid > div (each manga card)
    let items = html_select(html, "div.grid > div");

    // If that doesn't work, try the more specific selector
    if items.len() == 0 {
        items = html_select(html, "div.container div.grid div");
    }

    for item in items {
        // Get the link element
        let links = html_select(item, "a");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Only process manga links
        if !href.contains("/manga/") {
            continue;
        }

        // Make URL absolute if needed
        let manga_url = href;
        if !href.starts_with("http") {
            manga_url = `${BASE_URL}${href}`;
        }

        // Extract manga ID and skip duplicates
        let id = extract_manga_id(manga_url);
        if id == "" || seen.contains(id) {
            continue;
        }
        seen[id] = true;

        // Get cover and title from img element
        // MangaPill puts title in img alt attribute (may be repeated twice)
        let cover_url = ();
        let title = "";
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "src");
            }
            // Get title from alt attribute
            let alt = element_attr(imgs[0], "alt");
            if alt != () && alt != "" {
                // Alt may have title repeated twice, take first half
                let alt_trimmed = alt.trim();
                let half_len = alt_trimmed.len() / 2;
                let first_half = alt_trimmed.sub_string(0, half_len).trim();
                let second_half = alt_trimmed.sub_string(half_len).trim();
                if first_half == second_half {
                    title = first_half;
                } else {
                    title = alt_trimmed;
                }
            }
        }

        // Fallback: extract title from URL slug
        if title == "" {
            let slug = extract_slug(href);
            if slug != "" {
                title = slug.replace("-", " ");
            }
        }

        if title == "" {
            continue;
        }

        // Get type and status if available
        let status = ();
        let manga_type = ();
        let status_spans = html_select(item, "span");
        for span in status_spans {
            let text = element_text(span).to_lower();
            if text.contains("finished") || text.contains("publishing") || text.contains("hiatus") {
                status = map_status(text);
            }
            if text.contains("manga") || text.contains("manhwa") || text.contains("manhua") {
                manga_type = element_text(span).trim();
            }
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
            tags: if manga_type != () { [manga_type] } else { [] },
            description: ()
        });
    }

    #{ series: series, has_more: false, total: series.len() }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let id = id_or_url;

    if !id_or_url.starts_with("http") {
        // If only ID is provided, we need the slug too
        // Try to fetch the search page to find the full URL
        // For now, assume it's a full path like "123/slug-name"
        if id_or_url.contains("/") {
            url = `${BASE_URL}/manga/${id_or_url}`;
            id = id_or_url.split("/")[0];
        } else {
            // Just ID - we'll need to construct URL somehow
            // This is a limitation - we need the slug
            url = `${BASE_URL}/manga/${id_or_url}`;
        }
    } else {
        id = extract_manga_id(id_or_url);
    }

    let html = fetch_html(url);

    // Extract title from h1
    let title = "";
    let title_els = html_select(html, "h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover image
    let cover_url = ();
    let cover_imgs = html_select(html, "img");
    for img in cover_imgs {
        let src = element_attr(img, "data-src");
        if src == () || src == "" {
            src = element_attr(img, "src");
        }
        // Look for cover image (usually has manga in URL or is large)
        if src != () && src != "" && (src.contains("cover") || src.contains("manga")) {
            cover_url = src;
            break;
        }
    }

    // If no cover found, try first image
    if cover_url == () {
        let all_imgs = html_select(html, "img");
        if all_imgs.len() > 0 {
            cover_url = element_attr(all_imgs[0], "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(all_imgs[0], "src");
            }
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "p.text--secondary");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    // Try alternative selector for description
    if description == () || description == "" {
        let p_els = html_select(html, "div.container p");
        for p in p_els {
            let text = element_text(p).trim();
            if text.len() > 100 {
                description = text;
                break;
            }
        }
    }

    // Extract genres from genre links
    let genres = [];
    let genre_links = html_select(html, "a[href*='genre=']");
    for link in genre_links {
        let genre = element_text(link).trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Extract status, type, year from info section
    let status = ();
    let year = ();
    let manga_type = ();

    // Look for info labels and values
    let info_divs = html_select(html, "div.grid div");
    for div in info_divs {
        let text = element_text(div).to_lower();
        if text.contains("status") {
            let status_text = element_text(div);
            status = map_status(status_text);
        }
        if text.contains("type") {
            manga_type = element_text(div).replace("Type", "").replace("type", "").trim();
        }
    }

    // Try to find year
    let year_match = regex_find("\\b(19|20)\\d{2}\\b", html);
    if year_match != () && year_match != "" {
        year = year_match;
    }

    // Extract authors (if available)
    let authors = [];
    let author_links = html_select(html, "a[href*='author=']");
    for link in author_links {
        let author = element_text(link).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    #{
        id: id,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: [],
        status: status,
        genres: genres,
        tags: if manga_type != () { [manga_type] } else { [] },
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
        if series_id.contains("/") {
            url = `${BASE_URL}/manga/${series_id}`;
        } else {
            url = `${BASE_URL}/manga/${series_id}`;
        }
    }

    let html = fetch_html(url);

    let chapters = [];
    let seen = #{};

    // Select chapter links
    // Selector: div[data-filter-list] a or just links with /chapters/ in href
    let chapter_links = html_select(html, "a[href*='/chapters/']");

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

        // Make URL absolute
        let chapter_url = href;
        if !href.starts_with("http") {
            chapter_url = `${BASE_URL}${href}`;
        }

        // Get chapter title/text
        let chapter_title = element_text(link).trim();

        // Extract chapter number
        let chapter_num = extract_chapter_number(href, chapter_title);

        chapters.push(#{
            id: chapter_url,
            series_id: series_id,
            number: chapter_num,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // MangaPill lists chapters in reverse order (newest first)
    // We may want to reverse for consistency
    // chapters.reverse();  // Uncomment if needed

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

    // Select page images
    // MangaPill uses <picture><img data-src="..."></picture> for lazy loading
    let page_imgs = html_select(html, "picture img");

    // If no results, try just img tags
    if page_imgs.len() == 0 {
        page_imgs = html_select(html, "img[data-src]");
    }

    // If still no results, try all images in the reader container
    if page_imgs.len() == 0 {
        page_imgs = html_select(html, "div.container img");
    }

    for img in page_imgs {
        // Try data-src first (lazy loading)
        let img_url = element_attr(img, "data-src");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "src");
        }

        // Skip placeholder images, icons, ads
        if img_url == () || img_url == "" {
            continue;
        }
        if img_url.contains("placeholder") || img_url.contains("loading") {
            continue;
        }
        if img_url.contains("icon") || img_url.contains("logo") || img_url.contains("avatar") {
            continue;
        }
        if img_url.contains("ad") || img_url.contains("banner") {
            continue;
        }

        // Make URL absolute if needed
        if !img_url.starts_with("http") {
            if img_url.starts_with("//") {
                img_url = `https:${img_url}`;
            } else {
                img_url = `${BASE_URL}${img_url}`;
            }
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

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    // MangaPill has a chapters page with recently released chapters
    let url = `${BASE_URL}/chapters`;

    if page > 1 {
        // MangaPill may not support pagination on this page
        return #{ series: [], has_more: false };
    }

    let html = fetch_html(url);

    let series = [];
    let seen = #{};

    // Select manga cards
    let items = html_select(html, "div.grid > div");

    for item in items {
        let links = html_select(item, "a[href*='/manga/']");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let id = extract_manga_id(href);
        if id == "" || seen.contains(id) {
            continue;
        }
        seen[id] = true;

        let manga_url = href;
        if !href.starts_with("http") {
            manga_url = `${BASE_URL}${href}`;
        }

        // Get cover and title from img element
        let cover_url = ();
        let title = "";
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "src");
            }
            // Get title from alt attribute and clean it
            let alt = element_attr(imgs[0], "alt");
            if alt != () && alt != "" {
                title = clean_title(alt);
            }
        }

        // Fallback: extract title from URL slug
        if title == "" {
            let slug = extract_slug(href);
            if slug != "" {
                title = slug.replace("-", " ");
            }
        }

        if title != "" {
            series.push(#{
                id: id,
                title: title,
                url: manga_url,
                cover_url: cover_url,
                updated_at: ()
            });
        }
    }

    #{ series: series, has_more: false }
}

/// Get popular/new manga
fn get_popular(page, auth) {
    // MangaPill has a "new mangas" page
    let url = `${BASE_URL}/mangas/new`;

    if page > 1 {
        return #{ series: [], has_more: false };
    }

    let html = fetch_html(url);

    let series = [];
    let seen = #{};

    // Select manga cards
    let items = html_select(html, "div.grid > div");

    for item in items {
        let links = html_select(item, "a[href*='/manga/']");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let id = extract_manga_id(href);
        if id == "" || seen.contains(id) {
            continue;
        }
        seen[id] = true;

        let manga_url = href;
        if !href.starts_with("http") {
            manga_url = `${BASE_URL}${href}`;
        }

        // Get cover and title from img element
        let cover_url = ();
        let title = "";
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "src");
            }
            // Get title from alt attribute and clean it
            let alt = element_attr(imgs[0], "alt");
            if alt != () && alt != "" {
                title = clean_title(alt);
            }
        }

        // Fallback: extract title from URL slug
        if title == "" {
            let slug = extract_slug(href);
            if slug != "" {
                title = slug.replace("-", " ");
            }
        }

        if title != "" {
            series.push(#{
                id: id,
                title: title,
                url: manga_url,
                cover_url: cover_url
            });
        }
    }

    #{ series: series, has_more: false }
}
