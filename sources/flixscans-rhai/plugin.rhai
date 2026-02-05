// Flix Scans Scraper (Rhai)
// HTTP-based scraper for flixscans.org
//
// URL Patterns (Madara-style):
//   Browse:   /manga/?m_orderby=latest
//   Search:   /?s={query}&post_type=wp-manga
//   Series:   /manga/{slug}/
//   Chapter:  /manga/{slug}/{chapter}/
//   Ajax:     /wp-admin/admin-ajax.php

const BASE_URL = "https://flixscans.org";

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

/// Extract series slug from URL
fn extract_slug(url) {
    let result = regex_find("/manga/([^/]+)", url);
    if result != "" {
        return result.replace("/manga/", "");
    }
    // Fallback: last path segment
    let parts = url.split("/");
    for i in (0..parts.len()).rev() {
        if parts[i] != "" && parts[i] != "manga" {
            return parts[i];
        }
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
        id: "flixscans-rhai",
        name: "Flix Scans",
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
    // Madara-style search
    let url = `${BASE_URL}/?s=${encoded}&post_type=wp-manga`;
    if page > 1 {
        url = `${BASE_URL}/page/${page}/?s=${encoded}&post_type=wp-manga`;
    }

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let seen = #{};

    // Madara search results
    let items = html_select(html, "div.c-tabs-item__content, div.row.c-tabs-item, div.search-item");

    if items.len() == 0 {
        items = html_select(html, "div.post-title a[href*='/manga/']");
    }

    for item in items {
        // Find manga link
        let link = "";
        let href = "";

        // Check if item is already a link
        href = element_attr(item, "href");
        if href != () && href != "" && href.contains("/manga/") {
            link = item;
        } else {
            // Find link inside
            let links = html_select(item, "a[href*='/manga/']");
            if links.len() > 0 {
                link = links[0];
                href = element_attr(link, "href");
            }
        }

        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        // Get title
        let title = "";
        let title_el = element_select_first(item, "div.post-title a, h3.h4 a, h4 a");
        if title_el != "" {
            title = element_text(title_el).trim();
        }
        if title == "" && link != "" {
            title = element_text(link).trim();
        }

        if title == "" || title.len() < 2 {
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
            id: slug,
            title: title,
            url: `${BASE_URL}/manga/${slug}/`,
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

    let has_more = html.contains(`/page/${page + 1}/`);

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let slug = id_or_url;
    let url = "";

    if id_or_url.starts_with("http") {
        slug = extract_slug(id_or_url);
        url = id_or_url;
    } else {
        url = `${BASE_URL}/manga/${slug}/`;
    }

    let html = fetch_html(url);

    if html == "" {
        throw `Failed to fetch series: ${slug}`;
    }

    // Extract title
    let title = "";
    let title_els = html_select(html, "div.post-title h1, div.post-title h3");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover
    let cover_url = ();
    let cover_imgs = html_select(html, "div.summary_image img, div.tab-summary img");
    if cover_imgs.len() > 0 {
        cover_url = element_attr(cover_imgs[0], "src");
        if cover_url == () || cover_url == "" {
            cover_url = element_attr(cover_imgs[0], "data-src");
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "div.summary__content, div.description-summary, div.manga-excerpt");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    // Extract info from content items
    let authors = [];
    let artists = [];
    let genres = [];
    let status = ();
    let alt_titles = [];

    let content_items = html_select(html, "div.post-content_item, div.post-content div.summary-content");

    for item in content_items {
        let label = "";
        let label_el = element_select_first(item, "div.summary-heading, h5");
        if label_el != "" {
            label = element_text(label_el).to_lower().trim();
        }

        let value_el = element_select_first(item, "div.summary-content");
        if value_el == "" {
            continue;
        }

        if label.contains("author") {
            let links = html_select(value_el, "a");
            for link in links {
                let author = element_text(link).trim();
                if author != "" && !authors.contains(author) {
                    authors.push(author);
                }
            }
        } else if label.contains("artist") {
            let links = html_select(value_el, "a");
            for link in links {
                let artist = element_text(link).trim();
                if artist != "" && !artists.contains(artist) {
                    artists.push(artist);
                }
            }
        } else if label.contains("genre") {
            let links = html_select(value_el, "a");
            for link in links {
                let genre = element_text(link).trim();
                if genre != "" && !genres.contains(genre) {
                    genres.push(genre);
                }
            }
        } else if label.contains("status") {
            let status_text = element_text(value_el).trim();
            status = map_status(status_text);
        } else if label.contains("alternative") || label.contains("alt") {
            let alt_text = element_text(value_el).trim();
            let alts = alt_text.split(",");
            for alt in alts {
                let cleaned = alt.trim();
                if cleaned != "" && cleaned != title && !alt_titles.contains(cleaned) {
                    alt_titles.push(cleaned);
                }
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
        year: (),
        content_rating: "suggestive",
        url: url,
        extra: #{}
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let slug = series_id;
    let url = "";

    if series_id.starts_with("http") {
        slug = extract_slug(series_id);
        url = series_id;
    } else {
        url = `${BASE_URL}/manga/${slug}/`;
    }

    let html = fetch_html(url);

    if html == "" {
        return [];
    }

    let chapters = [];
    let seen = #{};

    // Madara chapter list
    let chapter_items = html_select(html, "li.wp-manga-chapter, ul.main li");

    for item in chapter_items {
        let link = element_select_first(item, "a");
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Must be a chapter link
        if !href.contains(slug) {
            continue;
        }

        if seen[href] != () {
            continue;
        }
        seen[href] = true;

        let ch_title = element_text(link).trim();

        // Extract chapter number
        let ch_num = "0";
        let num_match = regex_find("(?:chapter|ch\\.?|-)\\s*(\\d+\\.?\\d*)", href.to_lower());
        if num_match != "" {
            ch_num = regex_find("\\d+\\.?\\d*", num_match);
        }
        if ch_num == "0" || ch_num == "" {
            num_match = regex_find("(?:chapter|ch\\.?|#)\\s*(\\d+\\.?\\d*)", ch_title.to_lower());
            if num_match != "" {
                ch_num = regex_find("\\d+\\.?\\d*", num_match);
            }
        }

        if ch_num == "" {
            ch_num = "0";
        }

        if ch_title == "" {
            ch_title = `Chapter ${ch_num}`;
        }

        // Get release date
        let published_at = ();
        let date_el = element_select_first(item, "span.chapter-release-date, i");
        if date_el != "" {
            published_at = element_text(date_el).trim();
        }

        chapters.push(#{
            id: href,
            series_id: slug,
            number: ch_num,
            title: ch_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: href,
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

    if html == "" {
        return [];
    }

    let pages = [];
    let idx = 0;
    let seen = #{};

    // Madara reader images
    let page_imgs = html_select(html, "div.reading-content img, div.page-break img");

    for img in page_imgs {
        let src = element_attr(img, "src");
        if src == () || src == "" {
            src = element_attr(img, "data-src");
        }

        if src == () || src == "" || seen[src] != () {
            continue;
        }

        // Skip non-page images
        let src_lower = src.to_lower();
        if src_lower.contains("logo") || src_lower.contains("banner") || src_lower.contains("icon") {
            continue;
        }

        seen[src] = true;

        // Clean URL (trim whitespace that might be in data-src)
        src = src.trim();

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

    // Fallback: extract from JavaScript
    if pages.len() == 0 {
        let img_patterns = regex_find_all("\"(https?://[^\"]+\\.(?:jpg|jpeg|png|webp)[^\"]*?)\"", html);

        for img_match in img_patterns {
            let img_url = img_match.replace("\"", "").trim();

            if seen[img_url] != () {
                continue;
            }

            // Filter for actual page images
            if img_url.contains("logo") || img_url.contains("banner") || img_url.contains("avatar") {
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
    }

    pages
}

/// Browse manga (main browse endpoint)
fn browse(page, filters, auth) {
    get_latest_updates(page, auth)
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/manga/?m_orderby=latest`;
    if page > 1 {
        url = `${BASE_URL}/manga/page/${page}/?m_orderby=latest`;
    }

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    // Madara manga listing
    let items = html_select(html, "div.page-item-detail, div.manga");

    for item in items {
        let link = element_select_first(item, "a[href*='/manga/']");
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        // Get title
        let title = "";
        let title_el = element_select_first(item, "h3.h5 a, h5 a, div.post-title a");
        if title_el != "" {
            title = element_text(title_el).trim();
        }
        if title == "" {
            title = element_attr(link, "title");
            if title == () {
                title = "";
            }
        }

        if title == "" || title.len() < 2 {
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
            id: slug,
            title: title,
            url: `${BASE_URL}/manga/${slug}/`,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    let has_more = html.contains(`/page/${page + 1}/`) && series.len() > 0;

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/manga/?m_orderby=views`;
    if page > 1 {
        url = `${BASE_URL}/manga/page/${page}/?m_orderby=views`;
    }

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    let items = html_select(html, "div.page-item-detail, div.manga");

    for item in items {
        let link = element_select_first(item, "a[href*='/manga/']");
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        let title = "";
        let title_el = element_select_first(item, "h3.h5 a, h5 a, div.post-title a");
        if title_el != "" {
            title = element_text(title_el).trim();
        }

        if title == "" || title.len() < 2 {
            continue;
        }

        let cover_url = ();
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "src");
        }

        series.push(#{
            id: slug,
            title: title,
            url: `${BASE_URL}/manga/${slug}/`,
            cover_url: cover_url
        });
    }

    let has_more = series.len() > 0;

    #{ series: series, has_more: has_more }
}
