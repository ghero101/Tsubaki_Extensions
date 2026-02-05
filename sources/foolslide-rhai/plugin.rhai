// FoolSlide Framework Scraper (Rhai)
// Configurable scraper for FoolSlide-based manga sites
//
// FoolSlide is a PHP-based manga reader CMS used by many scanlation groups.
// Common sites: Helvetica Scans, Sense Scans, Kirei Cake, etc.
//
// URL Patterns:
//   Directory: /directory/
//   Series:    /series/{slug}/
//   Chapter:   /read/{slug}/{lang}/{volume}/{chapter}/{subchapter}/
//   Search:    /search/ (POST)
//
// API Endpoints:
//   /api/reader/chapters?comic_stub={slug}
//   /api/reader/comic?comic_stub={slug}

/// Get base URL from settings or use default
fn get_base_url() {
    if settings != () && settings.contains("base_url") {
        let url = settings["base_url"];
        // Remove trailing slash
        if url.ends_with("/") {
            return url.sub_string(0, url.len() - 1);
        }
        return url;
    }
    "https://helveticascans.com/r"
}

/// Build request headers
fn get_headers() {
    let base = get_base_url();
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": base
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

/// Extract series slug from URL
fn extract_slug(url) {
    // /series/slug/ or /read/slug/...
    let series_match = regex_find("/series/([^/]+)", url);
    if series_match != "" {
        return series_match.replace("/series/", "");
    }

    let read_match = regex_find("/read/([^/]+)", url);
    if read_match != "" {
        return read_match.replace("/read/", "");
    }

    // Fallback: last path segment
    let parts = url.split("/");
    for i in (0..parts.len()).rev() {
        if parts[i] != "" {
            return parts[i];
        }
    }
    ""
}

/// Map status text to standard format
fn map_status(status) {
    let s = status.to_lower().trim();
    if s.contains("ongoing") || s.contains("releasing") {
        return "Ongoing";
    } else if s.contains("completed") || s.contains("finished") {
        return "Completed";
    } else if s.contains("hiatus") || s.contains("dropped") {
        return "Hiatus";
    } else if s.contains("licensed") {
        return "Licensed";
    }
    ()
}

// === Addon Interface Functions ===

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "foolslide-rhai",
        name: "FoolSlide",
        base_url: get_base_url(),
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Search for manga matching a query
fn search_series(query, page, auth) {
    let base = get_base_url();
    let encoded = url_encode(query);

    // FoolSlide search uses POST to /search/
    // For simplicity, use directory page and filter client-side
    let url = `${base}/directory/${page}/`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let query_lower = query.to_lower();

    // Parse directory listing
    // FoolSlide uses div.group or div.list with series items
    let items = html_select(html, "div.group div.title a, div.list div.title a, div.series_element a.title");

    if items.len() == 0 {
        // Try alternate selectors
        items = html_select(html, "div.comic a.title, a.comic_title");
    }

    for item in items {
        let href = element_attr(item, "href");
        let title = element_text(item).trim();

        if href == () || href == "" || title == "" {
            continue;
        }

        // Filter by search query
        if !title.to_lower().contains(query_lower) {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" {
            continue;
        }

        // Build full URL
        let full_url = href;
        if !href.starts_with("http") {
            full_url = `${base}${href}`;
        }

        series.push(#{
            id: slug,
            title: title,
            url: full_url,
            cover_url: (),
            alternate_titles: [],
            authors: [],
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: ()
        });
    }

    let has_more = html.contains(`/directory/${page + 1}/`);

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let base = get_base_url();
    let slug = id_or_url;
    let url = "";

    if id_or_url.starts_with("http") {
        slug = extract_slug(id_or_url);
        url = id_or_url;
    } else {
        url = `${base}/series/${slug}/`;
    }

    let html = fetch_html(url);

    if html == "" {
        throw `Failed to fetch series: ${slug}`;
    }

    // Extract title
    let title = "";
    let title_els = html_select(html, "h1.title, div.title h1, h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover
    let cover_url = ();
    let cover_els = html_select(html, "div.thumbnail img, div.comic img, img.thumbnail");
    if cover_els.len() > 0 {
        let src = element_attr(cover_els[0], "src");
        if src != () && src != "" {
            if !src.starts_with("http") {
                src = `${base}${src}`;
            }
            cover_url = src;
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "div.info div.description, div.summary, div.comic_description");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    // Extract authors
    let authors = [];
    let author_els = html_select(html, "div.info div.author a, span.author a");
    for el in author_els {
        let author = element_text(el).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    // Extract artists
    let artists = [];
    let artist_els = html_select(html, "div.info div.artist a, span.artist a");
    for el in artist_els {
        let artist = element_text(el).trim();
        if artist != "" && !artists.contains(artist) {
            artists.push(artist);
        }
    }

    // Extract genres
    let genres = [];
    let genre_els = html_select(html, "div.info div.genre a, span.genre a, a.tag");
    for el in genre_els {
        let genre = element_text(el).trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Extract status
    let status = ();
    let info_text = "";
    let info_els = html_select(html, "div.info");
    if info_els.len() > 0 {
        info_text = element_text(info_els[0]).to_lower();
    }
    if info_text.contains("ongoing") {
        status = "Ongoing";
    } else if info_text.contains("completed") {
        status = "Completed";
    }

    #{
        id: slug,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
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
    let base = get_base_url();
    let slug = series_id;
    let url = "";

    if series_id.starts_with("http") {
        slug = extract_slug(series_id);
        url = series_id;
    } else {
        url = `${base}/series/${slug}/`;
    }

    let html = fetch_html(url);

    if html == "" {
        return [];
    }

    let chapters = [];
    let seen = #{};

    // FoolSlide chapter lists are in div.list or div.chapters
    let chapter_links = html_select(html, "div.list div.element a.title, div.chapters a, div.chapter a.name");

    if chapter_links.len() == 0 {
        // Try alternate selector
        chapter_links = html_select(html, "a[href*='/read/']");
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Must be a reader link
        if !href.contains("/read/") {
            continue;
        }

        // Skip duplicates
        if seen[href] != () {
            continue;
        }
        seen[href] = true;

        let ch_title = element_text(link).trim();

        // Extract chapter number
        // FoolSlide URL: /read/slug/lang/vol/ch/subch/
        let ch_num = "0";
        let num_match = regex_find("/read/[^/]+/[^/]+/[^/]+/([^/]+)", href);
        if num_match != "" {
            ch_num = regex_find("\\d+\\.?\\d*", num_match);
            if ch_num == "" {
                ch_num = "0";
            }
        }

        // Fallback: extract from title
        if ch_num == "0" || ch_num == "" {
            let title_match = regex_find("(?:chapter|ch\\.?|#)\\s*(\\d+\\.?\\d*)", ch_title.to_lower());
            if title_match != "" {
                ch_num = regex_find("\\d+\\.?\\d*", title_match);
            }
        }

        if ch_title == "" {
            ch_title = `Chapter ${ch_num}`;
        }

        // Build full URL
        let full_url = href;
        if !href.starts_with("http") {
            full_url = `${base}${href}`;
        }

        chapters.push(#{
            id: full_url,
            series_id: slug,
            number: ch_num,
            title: ch_title,
            volume: (),
            language: "en",
            scanlator: (),
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
    let base = get_base_url();
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${base}${chapter_id}`;
    }

    let html = fetch_html(url);

    if html == "" {
        return [];
    }

    let pages = [];
    let idx = 0;
    let seen = #{};

    // Method 1: Extract from JavaScript pages array
    // FoolSlide embeds pages as: var pages = [{...}, {...}];
    let pages_match = regex_find_all("\"url\":\"([^\"]+)\"", html);

    for img_match in pages_match {
        let img_url = img_match.replace("\"url\":\"", "").replace("\"", "");

        // Unescape URL
        img_url = img_url.replace("\\/", "/");

        if img_url == "" || seen[img_url] != () {
            continue;
        }
        seen[img_url] = true;

        // Make absolute
        if !img_url.starts_with("http") {
            img_url = `${base}${img_url}`;
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

    // Method 2: Extract from img tags in reader
    if pages.len() == 0 {
        let page_imgs = html_select(html, "div.page img, div.reader img, img.page");

        for img in page_imgs {
            let src = element_attr(img, "src");
            if src == () || src == "" {
                src = element_attr(img, "data-src");
            }

            if src == () || src == "" || seen[src] != () {
                continue;
            }
            seen[src] = true;

            // Skip non-page images
            if src.contains("logo") || src.contains("banner") || src.contains("icon") {
                continue;
            }

            // Make absolute
            if !src.starts_with("http") {
                src = `${base}${src}`;
            }

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

/// Get latest updates / directory
fn get_latest_updates(page, auth) {
    let base = get_base_url();
    let url = `${base}/directory/${page}/`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    // Parse directory listing
    let items = html_select(html, "div.group, div.series_element");

    for item in items {
        // Get title link
        let title_link = element_select_first(item, "div.title a, a.title");
        if title_link == "" {
            continue;
        }

        let href = element_attr(title_link, "href");
        let title = element_text(title_link).trim();

        if href == () || href == "" || title == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        // Get cover
        let cover_url = ();
        let img = element_select_first(item, "img");
        if img != "" {
            let src = element_attr(img, "src");
            if src != () && src != "" {
                if !src.starts_with("http") {
                    src = `${base}${src}`;
                }
                cover_url = src;
            }
        }

        // Build full URL
        let full_url = href;
        if !href.starts_with("http") {
            full_url = `${base}${href}`;
        }

        series.push(#{
            id: slug,
            title: title,
            url: full_url,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    let has_more = html.contains(`/directory/${page + 1}/`) && series.len() > 0;

    #{ series: series, has_more: has_more }
}

/// Get popular series (same as directory for FoolSlide)
fn get_popular(page, auth) {
    get_latest_updates(page, auth)
}
