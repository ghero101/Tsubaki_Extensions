// MangaTown Scraper Add-on (Rhai)
// HTTP-only scraper for mangatown.com
//
// URL Patterns:
//   Search: /search?name={query}&page={page}
//   Manga:  /manga/{slug}/
//   Chapter: /manga/{slug}/v{volume}/c{chapter}/
//   Pages: /manga/{slug}/v{volume}/c{chapter}/{page}.html
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   JSON: json_parse(text)
//   Regex: regex_find(pattern, text), regex_find_all(pattern, text)
//   String: url_encode(text)

const BASE_URL = "https://www.mangatown.com";

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

/// Extract manga slug from URL
/// URL format: /manga/{slug}/ or https://www.mangatown.com/manga/{slug}/
fn extract_manga_slug(url) {
    let parts = url.split("/manga/");
    if parts.len() > 1 {
        let after_manga = parts[1];
        let slug_parts = after_manga.split("/");
        if slug_parts.len() > 0 && slug_parts[0] != "" {
            return slug_parts[0];
        }
    }
    ""
}

/// Map status text to standard format
fn map_status(status_text) {
    let lower = status_text.to_lower();
    if lower.contains("completed") {
        return "Completed";
    }
    if lower.contains("ongoing") {
        return "Ongoing";
    }
    if lower.contains("hiatus") {
        return "Hiatus";
    }
    ()
}

/// Extract chapter number from chapter URL or title
/// URL format: /manga/{slug}/v{vol}/c{chapter}/ or /manga/{slug}/c{chapter}/
fn extract_chapter_number(url, title) {
    // Try to extract from URL first (more reliable)
    // Pattern: /c{number}/ or /c{number}.{decimal}/
    let chapter_match = regex_find("/c([0-9]+\\.?[0-9]*)/", url);
    if chapter_match != () && chapter_match != "" {
        // Remove /c and /
        let num = chapter_match.replace("/c", "").replace("/", "");
        if num != "" {
            return num;
        }
    }

    // Try title parsing
    // Title format: "Ch.123" or "Chapter 123" or "123"
    let title_match = regex_find("[Cc]h\\.?\\s*([0-9]+\\.?[0-9]*)", title);
    if title_match != () && title_match != "" {
        let num = regex_find("[0-9]+\\.?[0-9]*", title_match);
        if num != () && num != "" {
            return num;
        }
    }

    // Last attempt - find any number in title
    let num_match = regex_find("[0-9]+\\.?[0-9]*", title);
    if num_match != () && num_match != "" {
        return num_match;
    }

    "0"
}

/// Extract volume number from URL
fn extract_volume_number(url) {
    let vol_match = regex_find("/v([0-9]+)/", url);
    if vol_match != () && vol_match != "" {
        let num = vol_match.replace("/v", "").replace("/", "");
        return num;
    }
    ()
}

/// Clean text by removing extra whitespace
fn clean_text(text) {
    let cleaned = text.trim();
    // Replace multiple spaces/newlines with single space
    while cleaned.contains("  ") {
        cleaned = cleaned.replace("  ", " ");
    }
    while cleaned.contains("\n\n") {
        cleaned = cleaned.replace("\n\n", "\n");
    }
    cleaned.trim()
}

// ============================================================================
// Required Interface Functions
// ============================================================================

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangatown-rhai",
        name: "MangaTown",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // MangaTown search URL: /search?name={query}&page={page}
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/search?name=${encoded_query}&page=${page}`;

    let html = fetch_html(url);

    let series = [];

    // Search results are in a list structure
    // Look for links to manga pages
    let items = html_select(html, "ul.manga_pic_list li");

    // If that doesn't work, try alternative selector
    if items.len() == 0 {
        items = html_select(html, "li");
    }

    for item in items {
        // Look for manga link
        let links = html_select(item, "a[href*='/manga/']");
        if links.len() == 0 {
            continue;
        }

        // Find the main manga link (not chapter links)
        let main_link = ();
        let cover_url = ();
        let title = "";

        for link in links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }

            // Skip chapter links (contain /c or /v followed by numbers)
            if regex_find("/[cv][0-9]", href) != () {
                continue;
            }

            // This should be the main manga link
            if href.contains("/manga/") {
                main_link = link;
                let link_title = element_attr(link, "title");
                if link_title != () && link_title != "" {
                    title = link_title;
                }
                if title == "" {
                    title = element_text(link).trim();
                }
                break;
            }
        }

        if main_link == () {
            continue;
        }

        let href = element_attr(main_link, "href");
        let slug = extract_manga_slug(href);
        if slug == "" {
            continue;
        }

        // Get cover image
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        // Clean up title
        title = clean_text(title);
        if title == "" {
            continue;
        }

        // Get author if available
        let authors = [];
        let item_text = element_text(item);
        let author_match = regex_find("Author:\\s*([^\\n]+)", item_text);
        if author_match != () && author_match != "" {
            let author = author_match.replace("Author:", "").trim();
            if author != "" {
                authors.push(author);
            }
        }

        // Get status if available
        let status = ();
        let status_match = regex_find("Status:\\s*(\\w+)", item_text);
        if status_match != () && status_match != "" {
            let status_text = status_match.replace("Status:", "").trim();
            status = map_status(status_text);
        }

        // Get genres if available
        let genres = [];
        let genre_links = html_select(item, "a[href*='/directory/']");
        for g_link in genre_links {
            let genre = element_text(g_link).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
            }
        }

        // Make URL absolute
        let manga_url = href;
        if !href.starts_with("http") {
            manga_url = `${BASE_URL}${href}`;
        }

        series.push(#{
            id: slug,
            title: title,
            url: manga_url,
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

    // Check for next page - look for pagination
    let has_more = false;
    let next_links = html_select(html, "a.next");
    if next_links.len() > 0 {
        has_more = true;
    } else {
        // Check for page number links
        let page_links = html_select(html, "div.next-page a");
        for p_link in page_links {
            let p_href = element_attr(p_link, "href");
            if p_href != () && p_href.contains(`page=${page + 1}`) {
                has_more = true;
                break;
            }
        }
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let slug = id_or_url;

    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/manga/${id_or_url}/`;
    } else {
        slug = extract_manga_slug(id_or_url);
    }

    let html = fetch_html(url);

    // Extract title from h1 or title element
    let title = "";
    let title_els = html_select(html, "h1.title-top");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }
    if title == "" {
        let h1_els = html_select(html, "h1");
        if h1_els.len() > 0 {
            title = element_text(h1_els[0]).trim();
        }
    }

    // Extract cover image
    let cover_url = ();
    let cover_imgs = html_select(html, "div.detail_info img");
    if cover_imgs.len() > 0 {
        cover_url = element_attr(cover_imgs[0], "src");
    }
    if cover_url == () {
        let all_imgs = html_select(html, "img[src*='cover']");
        if all_imgs.len() > 0 {
            cover_url = element_attr(all_imgs[0], "src");
        }
    }
    if cover_url == () {
        let ocover_imgs = html_select(html, "img[src*='ocover']");
        if ocover_imgs.len() > 0 {
            cover_url = element_attr(ocover_imgs[0], "src");
        }
    }

    // Extract description/summary
    let description = ();
    let desc_els = html_select(html, "span#show");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }
    if description == () || description == "" {
        let p_els = html_select(html, "div.detail_info p");
        for p in p_els {
            let text = element_text(p).trim();
            if text.len() > 100 && !text.contains("Author:") && !text.contains("Status:") {
                description = text;
                break;
            }
        }
    }

    // Extract authors and artists from info list
    let authors = [];
    let artists = [];
    let status = ();
    let alt_titles = [];
    let year = ();

    // Look for detail info elements
    let info_els = html_select(html, "ul.detail_topText li");
    for info in info_els {
        let text = element_text(info);
        let lower = text.to_lower();

        if lower.contains("author") {
            let author_links = html_select(info, "a");
            for a_link in author_links {
                let author = element_text(a_link).trim();
                if author != "" && !authors.contains(author) {
                    authors.push(author);
                }
            }
        } else if lower.contains("artist") {
            let artist_links = html_select(info, "a");
            for a_link in artist_links {
                let artist = element_text(a_link).trim();
                if artist != "" && !artists.contains(artist) {
                    artists.push(artist);
                }
            }
        } else if lower.contains("status") {
            status = map_status(text);
        } else if lower.contains("alternative") {
            let alt_text = text.replace("Alternative:", "").replace("Alternative", "").trim();
            let alts = alt_text.split(";");
            for alt in alts {
                let cleaned = alt.trim();
                if cleaned != "" && cleaned != title {
                    alt_titles.push(cleaned);
                }
            }
        } else if lower.contains("year") || lower.contains("released") {
            let year_match = regex_find("\\b(19|20)\\d{2}\\b", text);
            if year_match != () && year_match != "" {
                year = year_match;
            }
        }
    }

    // Extract genres
    let genres = [];
    let genre_links = html_select(html, "li.detail_topText_genres a");
    if genre_links.len() == 0 {
        genre_links = html_select(html, "a[href*='/directory/']");
    }
    for g_link in genre_links {
        let genre = element_text(g_link).trim();
        if genre != "" && !genres.contains(genre) && genre.len() < 30 {
            genres.push(genre);
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
        url = `${BASE_URL}/manga/${series_id}/`;
    }

    let html = fetch_html(url);

    let chapters = [];
    let seen = #{};

    // Select chapter links from the chapter list
    let chapter_links = html_select(html, "ul.chapter_list li a");

    // If that doesn't work, try alternative selectors
    if chapter_links.len() == 0 {
        chapter_links = html_select(html, "a[href*='/manga/'][href*='/c']");
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Must contain chapter pattern /c{number}
        if !regex_find("/c[0-9]", href) {
            continue;
        }

        // Skip duplicates
        if seen.contains(href) {
            continue;
        }
        seen[href] = true;

        // Get chapter title/text
        let chapter_title = element_text(link).trim();

        // Extract chapter and volume numbers
        let chapter_num = extract_chapter_number(href, chapter_title);
        let volume = extract_volume_number(href);

        // Make URL absolute
        let chapter_url = href;
        if !href.starts_with("http") {
            chapter_url = `${BASE_URL}${href}`;
        }

        // Try to get date from sibling elements
        let published_at = ();

        chapters.push(#{
            id: chapter_url,
            series_id: series_id,
            number: chapter_num,
            title: chapter_title,
            volume: volume,
            language: "en",
            scanlator: (),
            url: chapter_url,
            published_at: published_at,
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

    // MangaTown uses a page selector dropdown to get all page URLs
    // First, try to find image directly
    let page_imgs = html_select(html, "#image");
    if page_imgs.len() == 0 {
        page_imgs = html_select(html, "div.read_img img");
    }
    if page_imgs.len() == 0 {
        page_imgs = html_select(html, "#viewer img");
    }

    // Get the first/current page image
    for img in page_imgs {
        let img_url = element_attr(img, "src");
        if img_url == () || img_url == "" {
            continue;
        }

        // Make URL absolute
        if img_url.starts_with("//") {
            img_url = `https:${img_url}`;
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

    // Look for page selector to get total pages and iterate through them
    let page_selectors = html_select(html, "select.page_select option");
    if page_selectors.len() == 0 {
        page_selectors = html_select(html, "div.page_select option");
    }

    // Build list of page URLs
    let page_urls = [];
    for option in page_selectors {
        let page_url = element_attr(option, "value");
        if page_url == () || page_url == "" {
            continue;
        }

        // Skip "featured" or invalid entries
        if page_url.contains("featured") || !page_url.contains("/manga/") {
            continue;
        }

        // Make absolute
        if !page_url.starts_with("http") {
            page_url = `${BASE_URL}${page_url}`;
        }

        // Avoid duplicates
        let is_dup = false;
        for existing in page_urls {
            if existing == page_url {
                is_dup = true;
                break;
            }
        }
        if !is_dup {
            page_urls.push(page_url);
        }
    }

    // If we found page URLs, fetch each one to get the image
    // Skip the first one if we already have it
    let start_idx = 1;
    if pages.len() == 0 {
        start_idx = 0;
    }

    for i in start_idx..page_urls.len() {
        let page_html = fetch_html(page_urls[i]);

        let imgs = html_select(page_html, "#image");
        if imgs.len() == 0 {
            imgs = html_select(page_html, "div.read_img img");
        }
        if imgs.len() == 0 {
            imgs = html_select(page_html, "#viewer img");
        }

        for img in imgs {
            let img_url = element_attr(img, "src");
            if img_url == () || img_url == "" {
                continue;
            }

            // Make URL absolute
            if img_url.starts_with("//") {
                img_url = `https:${img_url}`;
            }

            // Skip placeholder images
            if img_url.contains("loading") || img_url.contains("placeholder") {
                continue;
            }

            pages.push(#{
                index: idx,
                url: img_url,
                headers: #{
                    "Referer": page_urls[i]
                },
                referer: page_urls[i]
            });
            idx += 1;
            break;  // Only get first valid image per page
        }
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/latest/`;
    if page > 1 {
        url = `${BASE_URL}/latest/${page}.htm`;
    }

    let html = fetch_html(url);

    let series = [];
    let seen = #{};

    // Select manga items
    let items = html_select(html, "ul.manga_pic_list li");
    if items.len() == 0 {
        items = html_select(html, "li");
    }

    for item in items {
        // Find manga link (not chapter link)
        let links = html_select(item, "a[href*='/manga/']");
        let main_link = ();
        let title = "";

        for link in links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }

            // Skip chapter links
            if regex_find("/[cv][0-9]", href) != () {
                continue;
            }

            if href.contains("/manga/") {
                main_link = link;
                title = element_attr(link, "title");
                if title == () || title == "" {
                    title = element_text(link).trim();
                }
                break;
            }
        }

        if main_link == () {
            continue;
        }

        let href = element_attr(main_link, "href");
        let slug = extract_manga_slug(href);
        if slug == "" || seen.contains(slug) {
            continue;
        }
        seen[slug] = true;

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        // Clean title
        title = clean_text(title);
        if title == "" {
            continue;
        }

        // Make URL absolute
        let manga_url = href;
        if !href.starts_with("http") {
            manga_url = `${BASE_URL}${href}`;
        }

        series.push(#{
            id: slug,
            title: title,
            url: manga_url,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    // Check for more pages
    let has_more = false;
    let next_links = html_select(html, "a.next");
    if next_links.len() > 0 {
        has_more = true;
    } else {
        // Check page number
        let page_links = html_select(html, "div.next-page a");
        for p_link in page_links {
            let p_text = element_text(p_link).trim();
            if p_text == "Next" || p_text == ">" {
                has_more = true;
                break;
            }
        }
    }

    #{ series: series, has_more: has_more }
}

/// Get popular/hot manga
fn get_popular(page, auth) {
    let url = `${BASE_URL}/directory/`;
    if page > 1 {
        url = `${BASE_URL}/directory/${page}.htm`;
    }

    let html = fetch_html(url);

    let series = [];

    // Select manga items
    let items = html_select(html, "ul.manga_pic_list li");
    if items.len() == 0 {
        items = html_select(html, "li");
    }

    for item in items {
        // Find manga link
        let links = html_select(item, "a[href*='/manga/']");
        let main_link = ();
        let title = "";

        for link in links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }

            // Skip chapter links
            if regex_find("/[cv][0-9]", href) != () {
                continue;
            }

            if href.contains("/manga/") {
                main_link = link;
                title = element_attr(link, "title");
                if title == () || title == "" {
                    title = element_text(link).trim();
                }
                break;
            }
        }

        if main_link == () {
            continue;
        }

        let href = element_attr(main_link, "href");
        let slug = extract_manga_slug(href);
        if slug == "" {
            continue;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        // Clean title
        title = clean_text(title);
        if title == "" {
            continue;
        }

        // Make URL absolute
        let manga_url = href;
        if !href.starts_with("http") {
            manga_url = `${BASE_URL}${href}`;
        }

        series.push(#{
            id: slug,
            title: title,
            url: manga_url,
            cover_url: cover_url
        });
    }

    // Check for more pages
    let has_more = page < 300;  // MangaTown has ~334 pages

    #{ series: series, has_more: has_more }
}
