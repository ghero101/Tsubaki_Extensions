// Reaper Scans Scraper Add-on (Rhai)
// HTML-based scraper for reaperscans.com
// Uses WordPress/Madara-style theme
//
// Available APIs:
//   http_get_with_headers(url, headers) -> string
//   html_parse(html) -> Document
//   html_select(html, selector) -> array
//   element_text(element) -> string
//   element_attr(element, name) -> string
//   regex_find(pattern, text) -> string

const BASE_URL = "https://reaperscans.com";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "reaperscans-rhai",
        name: "Reaper Scans",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Get headers for requests
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Referer": BASE_URL
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let encoded_query = query.replace(" ", "+");
    let url = `${BASE_URL}/?s=${encoded_query}&post_type=wp-manga&paged=${page}`;

    let html = http_get_with_headers(url, get_headers());

    let series = [];

    // Select search result items
    let items = html_select(html, "div.c-tabs-item__content");

    for item in items {
        // Get title and link
        let title_links = html_select(item, "h3.h4 a, h4 a, .post-title a");
        if title_links.len() == 0 {
            continue;
        }

        let link = title_links[0];
        let href = element_attr(link, "href");
        let title = element_text(link).trim();

        if href == () || title == "" {
            continue;
        }

        // Extract slug from URL
        let slug = extract_slug(href);

        // Get cover image
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }

        // Get genres
        let genres = [];
        let genre_links = html_select(item, ".mg_genres a, .genres a");
        for g in genre_links {
            let genre = element_text(g).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
            }
        }

        // Get status
        let status = ();
        let status_spans = html_select(item, ".mg_status, .summary-content");
        for span in status_spans {
            let text = element_text(span).to_lower();
            if text.contains("ongoing") {
                status = "Ongoing";
                break;
            } else if text.contains("completed") {
                status = "Completed";
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
    let next_links = html_select(html, "a.next, .nav-previous a, .nextpostslink");
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
        url = `${BASE_URL}/series/${id_or_url}/`;
    } else {
        slug = extract_slug(id_or_url);
    }

    let html = http_get_with_headers(url, get_headers());

    // Extract title
    let title = "";
    let title_els = html_select(html, "h1.post-title, h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover
    let cover_url = ();
    let cover_imgs = html_select(html, ".summary_image img, .thumb img");
    if cover_imgs.len() > 0 {
        cover_url = element_attr(cover_imgs[0], "src");
        if cover_url == () {
            cover_url = element_attr(cover_imgs[0], "data-src");
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, ".description-summary p, .summary__content p, div.entry-content p");
    if desc_els.len() > 0 {
        let desc_parts = [];
        for p in desc_els {
            let text = element_text(p).trim();
            if text != "" {
                desc_parts.push(text);
            }
        }
        if desc_parts.len() > 0 {
            description = desc_parts.join(" ");
        }
    }

    // Extract metadata from summary rows
    let authors = [];
    let artists = [];
    let genres = [];
    let alt_titles = [];
    let status = ();

    let summary_rows = html_select(html, ".post-content_item, .summary-content");
    for row in summary_rows {
        let text = element_text(row).to_lower();

        // Get authors
        if text.contains("author") {
            let author_links = html_select(row, "a");
            for a in author_links {
                let author = element_text(a).trim();
                if author != "" && !authors.contains(author) {
                    authors.push(author);
                }
            }
        }

        // Get artists
        if text.contains("artist") {
            let artist_links = html_select(row, "a");
            for a in artist_links {
                let artist = element_text(a).trim();
                if artist != "" && !artists.contains(artist) {
                    artists.push(artist);
                }
            }
        }

        // Get genres
        if text.contains("genre") {
            let genre_links = html_select(row, "a");
            for g in genre_links {
                let genre = element_text(g).trim();
                if genre != "" && !genres.contains(genre) {
                    genres.push(genre);
                }
            }
        }

        // Get status
        if text.contains("status") {
            if text.contains("ongoing") {
                status = "Ongoing";
            } else if text.contains("completed") {
                status = "Completed";
            } else if text.contains("hiatus") {
                status = "Hiatus";
            }
        }

        // Get alternative titles
        if text.contains("alternative") || text.contains("other name") {
            let alt_text = element_text(row);
            // Remove the label
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
    let url = series_id;

    if !series_id.starts_with("http") {
        url = `${BASE_URL}/series/${series_id}/`;
    }

    let html = http_get_with_headers(url, get_headers());

    let chapters = [];
    let seen = #{};

    // Find chapter list
    let chapter_links = html_select(html, "li.wp-manga-chapter a, ul.version-chap li a, .listing-chapters_wrap a");

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

        let chapter_text = element_text(link).trim();

        // Extract chapter number
        let chapter_num = extract_chapter_number(href, chapter_text);

        // Get release date from sibling element
        let release_date = ();

        chapters.push(#{
            id: href,
            series_id: series_id,
            number: chapter_num,
            title: chapter_text,
            volume: (),
            language: "en",
            scanlator: "Reaper Scans",
            url: href,
            published_at: release_date,
            page_count: (),
            extra: #{}
        });
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    let html = http_get_with_headers(url, get_headers());

    let pages = [];
    let idx = 0;

    // Find page images - try multiple selectors
    let page_imgs = html_select(html, "div.reading-content img, div.page-break img, .chapter-content img");

    for img in page_imgs {
        let img_url = element_attr(img, "src");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-src");
        }
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-lazy-src");
        }

        if img_url != () && img_url != "" && img_url.contains("http") {
            // Clean up URL (remove query params if they're just tracking)
            let clean_url = img_url.trim();

            pages.push(#{
                index: idx,
                url: clean_url,
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
    let url = `${BASE_URL}/page/${page}/`;

    let html = http_get_with_headers(url, get_headers());

    let series = [];

    // Find latest update items
    let items = html_select(html, ".page-item-detail, .page-listing-item");

    for item in items {
        let links = html_select(item, "h3 a, h5 a, .post-title a");
        if links.len() == 0 {
            continue;
        }

        let link = links[0];
        let href = element_attr(link, "href");
        let title = element_text(link).trim();

        if href == () || title == "" {
            continue;
        }

        let slug = extract_slug(href);

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }

        series.push(#{
            id: slug,
            title: title,
            url: href,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    let has_more = page < 20;

    #{ series: series, has_more: has_more }
}

// === Helper Functions ===

/// Extract slug from URL
fn extract_slug(url) {
    // URL format: https://reaperscans.com/series/slug-name/
    let parts = url.split("/series/");
    if parts.len() > 1 {
        let slug = parts[1];
        // Remove trailing slash and any extra path
        slug = slug.trim_end_matches("/");
        let slug_parts = slug.split("/");
        return slug_parts[0];
    }

    // Try manga pattern
    let parts = url.split("/manga/");
    if parts.len() > 1 {
        let slug = parts[1].trim_end_matches("/");
        let slug_parts = slug.split("/");
        return slug_parts[0];
    }

    // Last resort - get last meaningful segment
    let segments = url.split("/");
    for i in (0..segments.len()).rev() {
        let seg = segments[i].trim();
        if seg != "" && !seg.contains("chapter") {
            return seg;
        }
    }

    ""
}

/// Extract chapter number from URL or title
fn extract_chapter_number(url, title) {
    // Try URL first
    // Pattern: /chapter-123/ or /chapter-123-5/
    let url_lower = url.to_lower();

    if url_lower.contains("chapter-") {
        let parts = url_lower.split("chapter-");
        if parts.len() > 1 {
            let num_part = parts[1];
            // Clean up - remove trailing slash and query params
            num_part = num_part.split("/")[0];
            num_part = num_part.split("?")[0];

            // Handle decimal chapters like "chapter-10-5" -> "10.5"
            if num_part.contains("-") {
                let num_parts = num_part.split("-");
                if num_parts.len() >= 2 {
                    return `${num_parts[0]}.${num_parts[1]}`;
                }
            }

            return num_part;
        }
    }

    // Try title
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

    // Try ch. pattern
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
