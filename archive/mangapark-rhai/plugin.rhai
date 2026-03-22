// MangaPark Scraper (Rhai)
// HTTP-based scraper for mangapark.to
//
// MangaPark is a manga aggregator with multiple sources per series.
// Uses Next.js with server-side rendering.
//
// URL Patterns:
//   Search:   /search?word={query}
//   Browse:   /browse?sort=update or /latest
//   Series:   /comic/{id}/{slug}
//   Chapter:  /comic/{id}/{slug}/{source}/{chapter}
//   Images:   https://xfs-s01.mangapark.to/...

const BASE_URL = "https://mangapark.to";

/// Build request headers
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch HTML page
fn fetch_html(url) {
    try {
        return http_get_with_headers(url, get_headers());
    } catch {
        return "";
    }
}

/// Extract comic ID from URL
/// /comic/12345/slug -> 12345
fn extract_comic_id(url) {
    let result = regex_find("/comic/(\\d+)", url);
    if result != "" {
        return result.replace("/comic/", "");
    }
    ""
}

/// Extract full comic path (id/slug) from URL
fn extract_comic_path(url) {
    let result = regex_find("/comic/\\d+/[^/?#]+", url);
    if result != "" {
        return result.replace("/comic/", "");
    }
    ""
}

/// Map status text
fn map_status(status) {
    let s = status.to_lower().trim();
    if s.contains("ongoing") || s.contains("releasing") {
        return "Ongoing";
    } else if s.contains("completed") || s.contains("finished") {
        return "Completed";
    } else if s.contains("hiatus") {
        return "Hiatus";
    } else if s.contains("cancelled") || s.contains("dropped") {
        return "Cancelled";
    }
    ()
}

// === Addon Interface Functions ===

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangapark-rhai",
        name: "MangaPark",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Search for manga matching a query
fn search_series(query, page, auth) {
    let encoded = url_encode(query);
    let url = `${BASE_URL}/search?word=${encoded}&page=${page}`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let seen = #{};

    // MangaPark search results are in div.item or similar containers
    // Look for comic links
    let items = html_select(html, "div.item, div.pb-2");

    if items.len() == 0 {
        // Try to find comic links directly
        items = html_select(html, "a[href*='/comic/']");
    }

    for item in items {
        // Find comic link
        let link = "";
        let href = "";

        // If item is already a link
        href = element_attr(item, "href");
        if href != () && href != "" && href.contains("/comic/") {
            link = item;
        } else {
            // Find link inside item
            let links = html_select(item, "a[href*='/comic/']");
            if links.len() > 0 {
                link = links[0];
                href = element_attr(link, "href");
            }
        }

        if href == () || href == "" || !href.contains("/comic/") {
            continue;
        }

        let comic_path = extract_comic_path(href);
        if comic_path == "" || seen[comic_path] != () {
            continue;
        }
        seen[comic_path] = true;

        // Get title
        let title = "";
        if link != "" {
            title = element_attr(link, "title");
            if title == () || title == "" {
                let title_el = element_select_first(item, "h3, h4, div.fw-bold, a.fw-bold");
                if title_el != "" {
                    title = element_text(title_el).trim();
                }
            }
            if title == () || title == "" {
                title = element_text(link).trim();
            }
        }

        if title == () || title == "" || title.len() < 2 {
            continue;
        }

        // Get cover
        let cover_url = ();
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(img, "data-src");
            }
        }

        series.push(#{
            id: comic_path,
            title: title,
            url: `${BASE_URL}/comic/${comic_path}`,
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
    let has_more = html.contains(`page=${page + 1}`) && series.len() > 0;

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let comic_path = id_or_url;
    let url = "";

    if id_or_url.starts_with("http") {
        comic_path = extract_comic_path(id_or_url);
        url = id_or_url;
    } else {
        url = `${BASE_URL}/comic/${comic_path}`;
    }

    let html = fetch_html(url);

    if html == "" {
        throw `Failed to fetch series: ${comic_path}`;
    }

    // Extract title from h3.item-title or og:title
    let title = "";
    let title_els = html_select(html, "h3.item-title, h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }
    if title == "" {
        let og_match = regex_find("og:title[\"']\\s+content=[\"']([^\"']+)", html);
        if og_match != "" {
            title = regex_find("content=[\"']([^\"']+)", og_match);
            title = title.replace("content=\"", "").replace("content='", "").replace("\"", "").replace("'", "").trim();
        }
    }

    // Extract cover
    let cover_url = ();
    let cover_imgs = html_select(html, "img.detail-cover, div.detail-set img");
    if cover_imgs.len() > 0 {
        cover_url = element_attr(cover_imgs[0], "src");
    }
    if cover_url == () || cover_url == "" {
        let og_img = regex_find("og:image[\"']\\s+content=[\"']([^\"']+)", html);
        if og_img != "" {
            cover_url = regex_find("content=[\"']([^\"']+)", og_img);
            cover_url = cover_url.replace("content=\"", "").replace("content='", "").replace("\"", "").replace("'", "").trim();
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "div.limit-height-body, div.summary");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    // Extract authors
    let authors = [];
    let author_links = html_select(html, "a[href*='/author/'], a[href*='/artist/']");
    for link in author_links {
        let author = element_text(link).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    // Extract genres
    let genres = [];
    let genre_links = html_select(html, "a[href*='/genre/'], a.badge");
    for link in genre_links {
        let href = element_attr(link, "href");
        if href != () && href.contains("/genre/") {
            let genre = element_text(link).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
            }
        }
    }

    // Extract status
    let status = ();
    let status_els = html_select(html, "span.item-status, div.attr-item");
    for el in status_els {
        let text = element_text(el).to_lower();
        if text.contains("status") {
            status = map_status(text);
            break;
        }
    }

    // Extract alternate titles
    let alt_titles = [];
    let alt_els = html_select(html, "div.alias-set span, div.alt-name");
    for el in alt_els {
        let alt = element_text(el).trim();
        if alt != "" && alt != title && !alt_titles.contains(alt) {
            alt_titles.push(alt);
        }
    }

    #{
        id: comic_path,
        title: title,
        alternate_titles: alt_titles,
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
    let comic_path = series_id;
    let url = "";

    if series_id.starts_with("http") {
        comic_path = extract_comic_path(series_id);
        url = series_id;
    } else {
        url = `${BASE_URL}/comic/${comic_path}`;
    }

    let html = fetch_html(url);

    if html == "" {
        return [];
    }

    let chapters = [];
    let seen = #{};

    // MangaPark has chapter links with format /comic/{id}/{slug}/{source}/{chapter}
    let chapter_links = html_select(html, "a.ch-name, a[href*='/comic/'][href*='/c']");

    if chapter_links.len() == 0 {
        // Try broader selector
        chapter_links = html_select(html, "div.episode-item a, div.chapter-item a");
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Must be a chapter link (contains comic path and chapter indicator)
        if !href.contains("/comic/") {
            continue;
        }

        // Skip duplicates
        if seen[href] != () {
            continue;
        }
        seen[href] = true;

        let ch_title = element_text(link).trim();

        // Extract chapter number
        let ch_num = "0";
        // Try from URL: /c123 or /ch123
        let num_match = regex_find("/c(\\d+\\.?\\d*)", href);
        if num_match != "" {
            ch_num = regex_find("\\d+\\.?\\d*", num_match);
        }

        // Fallback: from title
        if ch_num == "0" || ch_num == "" {
            let title_match = regex_find("(?:chapter|ch\\.?|c)\\s*(\\d+\\.?\\d*)", ch_title.to_lower());
            if title_match != "" {
                ch_num = regex_find("\\d+\\.?\\d*", title_match);
            }
        }

        if ch_num == "" {
            ch_num = "0";
        }

        if ch_title == "" {
            ch_title = `Chapter ${ch_num}`;
        }

        // Build full URL
        let full_url = href;
        if !href.starts_with("http") {
            full_url = `${BASE_URL}${href}`;
        }

        // Detect source/scanlator from URL
        let scanlator = ();
        let source_match = regex_find("/comic/[^/]+/[^/]+/([^/]+)/", href);
        if source_match != "" {
            scanlator = source_match.replace("/comic/", "").split("/")[2];
        }

        chapters.push(#{
            id: full_url,
            series_id: comic_path,
            number: ch_num,
            title: ch_title,
            volume: (),
            language: "en",
            scanlator: scanlator,
            url: full_url,
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

    if html == "" {
        return [];
    }

    let pages = [];
    let idx = 0;
    let seen = #{};

    // Method 1: Extract from JavaScript data
    // MangaPark embeds page data in scripts
    let img_patterns = regex_find_all("\"(https?://[^\"]+\\.(?:jpg|jpeg|png|webp)[^\"]*?)\"", html);

    for img_match in img_patterns {
        let img_url = img_match.replace("\"", "").trim();

        // Filter for actual manga page images
        if !img_url.contains("xfs-") && !img_url.contains("/manga/") && !img_url.contains("/chapter/") {
            continue;
        }

        // Skip thumbnails and covers
        if img_url.contains("thumb") || img_url.contains("cover") || img_url.contains("logo") {
            continue;
        }

        if seen[img_url] != () {
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

    // Method 2: Find images in reader container
    if pages.len() == 0 {
        let page_imgs = html_select(html, "div.reader-main img, div.page-img img, img.page-img");

        for img in page_imgs {
            let src = element_attr(img, "src");
            if src == () || src == "" {
                src = element_attr(img, "data-src");
            }

            if src == () || src == "" || seen[src] != () {
                continue;
            }

            // Skip non-page images
            if src.contains("logo") || src.contains("banner") || src.contains("icon") || src.contains("cover") {
                continue;
            }

            seen[src] = true;

            pages.push(#{
                index: idx,
                url: src,
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

/// Browse manga (main browse endpoint)
fn browse(page, filters, auth) {
    get_latest_updates(page, auth)
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/latest?page=${page}`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    // Parse latest updates - look for comic cards/items
    let items = html_select(html, "div.item, div.pb-2, div.flex");

    for item in items {
        // Find comic link
        let links = html_select(item, "a[href*='/comic/']");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");

        if href == () || href == "" || !href.contains("/comic/") {
            continue;
        }

        let comic_path = extract_comic_path(href);
        if comic_path == "" || seen[comic_path] != () {
            continue;
        }
        seen[comic_path] = true;

        // Get title
        let title = element_attr(link, "title");
        if title == () || title == "" {
            let title_el = element_select_first(item, "h3, h4, div.fw-bold");
            if title_el != "" {
                title = element_text(title_el).trim();
            }
        }
        if title == () || title == "" {
            title = element_text(link).trim();
        }

        if title == () || title == "" || title.len() < 2 {
            continue;
        }

        // Get cover
        let cover_url = ();
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(img, "data-src");
            }
        }

        series.push(#{
            id: comic_path,
            title: title,
            url: `${BASE_URL}/comic/${comic_path}`,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    let has_more = html.contains(`page=${page + 1}`) && series.len() > 0;

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/browse?sort=d007&page=${page}`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    let items = html_select(html, "div.item, div.pb-2");

    for item in items {
        let links = html_select(item, "a[href*='/comic/']");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");

        if href == () || href == "" {
            continue;
        }

        let comic_path = extract_comic_path(href);
        if comic_path == "" || seen[comic_path] != () {
            continue;
        }
        seen[comic_path] = true;

        let title = element_attr(link, "title");
        if title == () || title == "" {
            title = element_text(link).trim();
        }

        if title == () || title == "" {
            continue;
        }

        let cover_url = ();
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "src");
        }

        series.push(#{
            id: comic_path,
            title: title,
            url: `${BASE_URL}/comic/${comic_path}`,
            cover_url: cover_url
        });
    }

    let has_more = series.len() > 0;

    #{ series: series, has_more: has_more }
}
