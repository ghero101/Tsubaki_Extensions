// MangaKakalot Scraper Add-on (Rhai)
// Browser automation scraper for mangakakalot.com and related domains
// Requires browser automation due to Cloudflare protection
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   Browser: browser_launch(), browser_goto(id, url), browser_wait_for_selector(id, sel, timeout)
//            browser_get_html(id), browser_close(id), browser_is_available()
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   url_encode(text) -> string

const BASE_URL = "https://mangakakalot.com";
const ALT_DOMAINS = ["chapmanganelo.com", "manganelo.com", "readmanganato.com"];

/// Get headers for requests (fallback for HTTP-only mode)
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch HTML using browser automation (required for Cloudflare bypass)
fn fetch_html(url) {
    // Use browser automation to bypass Cloudflare
    if browser_is_available() {
        let browser_id = browser_launch();
        browser_goto(browser_id, url);
        // Wait for content to load
        browser_wait_for_selector(browser_id, "div.story_item, div.panel-story-info, div.container-chapter-reader, body", 15000);
        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    }
    // Fallback to HTTP (will likely fail due to Cloudflare)
    http_get_with_headers(url, get_headers())
}

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangakakalot-rhai",
        name: "MangaKakalot",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // MangaKakalot uses underscores for spaces in search
    let encoded_query = query.replace(" ", "_");
    let url = `${BASE_URL}/search/story/${encoded_query}`;
    if page > 1 {
        url = `${url}?page=${page}`;
    }

    let html = fetch_html(url);
    let series = [];

    // Select search result items
    let items = html_select(html, "div.story_item");

    for item in items {
        let links = html_select(item, "h3.story_name a");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let title = element_text(link).trim();
        if title == "" {
            continue;
        }

        // Extract manga ID from URL
        let id = extract_manga_id(href);

        // Get cover image
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        // Get author
        let authors = [];
        let author_spans = html_select(item, "span:contains('Author')");
        if author_spans.len() > 0 {
            let author_text = element_text(author_spans[0]);
            let author = author_text.replace("Author(s) :", "").trim();
            if author != "" && author != "Updating" {
                authors.push(author);
            }
        }

        series.push(#{
            id: id,
            title: title,
            url: href,
            cover_url: cover_url,
            alternate_titles: [],
            authors: authors,
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: ()
        });
    }

    // Check for next page
    let has_more = false;
    let next_pages = html_select(html, "a.page_last, a.page_select + a");
    if next_pages.len() > 0 {
        has_more = true;
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let id = id_or_url;

    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/manga/${id_or_url}`;
    } else {
        id = extract_manga_id(id_or_url);
    }

    let html = fetch_html(url);

    // Extract title
    let title = "";
    let title_els = html_select(html, "h1, ul.manga-info-text li h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover
    let cover_url = ();
    let cover_imgs = html_select(html, "div.manga-info-pic img");
    if cover_imgs.len() > 0 {
        cover_url = element_attr(cover_imgs[0], "src");
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "#noidungm, div.panel-story-info-description");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    // Extract info from list
    let authors = [];
    let genres = [];
    let status = ();
    let alt_titles = [];

    let info_items = html_select(html, "ul.manga-info-text li");
    for item in info_items {
        let text = element_text(item).to_lower();

        if text.contains("author") {
            let author_links = html_select(item, "a");
            for link in author_links {
                let author = element_text(link).trim();
                if author != "" && author != "Updating" && !authors.contains(author) {
                    authors.push(author);
                }
            }
        } else if text.contains("genres") || text.contains("genre") {
            let genre_links = html_select(item, "a");
            for link in genre_links {
                let genre = element_text(link).trim();
                if genre != "" && !genres.contains(genre) {
                    genres.push(genre);
                }
            }
        } else if text.contains("status") {
            if text.contains("ongoing") {
                status = "Ongoing";
            } else if text.contains("completed") {
                status = "Completed";
            }
        } else if text.contains("alternative") {
            let alt_text = text.replace("alternative :", "").trim();
            let alts = alt_text.split(";");
            for alt in alts {
                let cleaned = alt.trim();
                if cleaned != "" && cleaned != title {
                    alt_titles.push(cleaned);
                }
            }
        }
    }

    #{
        id: id,
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
    let url = series_id;

    if !series_id.starts_with("http") {
        url = `${BASE_URL}/manga/${series_id}`;
    }

    let html = fetch_html(url);
    let chapters = [];

    // Find chapter list - try multiple selectors
    let chapter_links = html_select(html, "div.chapter-list div.row a, ul.row-content-chapter li a");

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let chapter_title = element_text(link).trim();

        // Extract chapter number from URL or title
        let chapter_num = extract_chapter_number(href, chapter_title);

        chapters.push(#{
            id: href,
            series_id: series_id,
            number: chapter_num,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: href,
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
    let html = fetch_html(url);

    let pages = [];
    let idx = 0;

    // Find all page images in the reader container
    let page_imgs = html_select(html, "div#vungdoc img, div.container-chapter-reader img");

    for img in page_imgs {
        let img_url = element_attr(img, "src");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-src");
        }

        if img_url != () && img_url != "" && img_url.contains("http") {
            // Skip non-manga images
            if img_url.contains("logo") || img_url.contains("icon") || img_url.contains("banner") {
                continue;
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
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/manga_list?type=latest&category=all&state=all&page=${page}`;

    let html = fetch_html(url);
    let series = [];

    let items = html_select(html, "div.list-truyen-item-wrap");

    for item in items {
        let links = html_select(item, "a");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let id = extract_manga_id(href);

        let title = element_attr(link, "title");
        if title == () || title == "" {
            let h3s = html_select(item, "h3 a");
            if h3s.len() > 0 {
                title = element_text(h3s[0]);
            }
        }
        title = title.trim();

        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        if id != "" && title != "" {
            series.push(#{
                id: id,
                title: title,
                url: href,
                cover_url: cover_url,
                updated_at: ()
            });
        }
    }

    let has_more = page < 50;

    #{ series: series, has_more: has_more }
}

/// Browse manga (main browse endpoint)
fn browse(page, filters, auth) {
    // Default to popular manga for browse
    get_popular(page, auth)
}

/// Get popular series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/manga_list?type=topview&category=all&state=all&page=${page}`;

    let html = fetch_html(url);
    let series = [];

    let items = html_select(html, "div.list-truyen-item-wrap");

    for item in items {
        let links = html_select(item, "a");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let id = extract_manga_id(href);

        let title = element_attr(link, "title");
        if title == () || title == "" {
            let h3s = html_select(item, "h3 a");
            if h3s.len() > 0 {
                title = element_text(h3s[0]);
            }
        }
        title = title.trim();

        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        if id != "" && title != "" {
            series.push(#{
                id: id,
                title: title,
                url: href,
                cover_url: cover_url
            });
        }
    }

    let has_more = page < 100;

    #{ series: series, has_more: has_more }
}

// === Helper Functions ===

/// Extract manga ID from URL
fn extract_manga_id(url) {
    // URL formats:
    // https://mangakakalot.com/manga/xx123456
    // https://mangakakalot.com/read-xx123
    let parts = url.split("/");
    let last_part = parts[parts.len() - 1];

    // Return the last path segment as the ID
    if last_part != "" {
        return last_part;
    }

    // Try second to last if last is empty
    if parts.len() > 1 {
        return parts[parts.len() - 2];
    }

    ""
}

/// Extract chapter number from URL or title
fn extract_chapter_number(url, title) {
    // Try to extract from URL first (more reliable)
    // URL format: .../chapter_123 or .../chapter-123 or .../ch_123
    let parts = url.split("/");
    for part in parts {
        let part_lower = part.to_lower();
        if part_lower.starts_with("chapter") || part_lower.starts_with("ch") {
            let num = part_lower.replace("chapter_", "").replace("chapter-", "").replace("ch_", "").replace("ch-", "");
            let clean = num.split("?")[0];
            if clean != "" {
                return clean;
            }
        }
    }

    // Fall back to title parsing
    let title_lower = title.to_lower();
    if title_lower.contains("chapter") {
        let after = title_lower.split("chapter")[1];
        let cleaned = after.trim();
        let num_str = "";
        for c in cleaned.chars() {
            if c >= '0' && c <= '9' || c == '.' {
                num_str += c;
            } else if num_str.len() > 0 {
                break;
            }
        }
        if num_str != "" {
            return num_str;
        }
    }

    // Last resort
    "0"
}
