// MangaNato Scraper Add-on (Rhai)
// HTML-based scraper for manganato.com
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   html_parse(html) -> Document
//   html_select(html, selector) -> array
//   element_text(element) -> string
//   element_attr(element, name) -> string
//   url_encode(text) -> string

const BASE_URL = "https://manganato.com";
const CHAPTER_BASE = "https://chapmanganato.to";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "manganato-rhai",
        name: "MangaNato",
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
        "Referer": BASE_URL
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // MangaNato uses underscores for spaces in search
    let encoded_query = query.replace(" ", "_");
    let url = `${BASE_URL}/search/story/${encoded_query}?page=${page}`;

    let html = http_get_with_headers(url, get_headers());
    let doc = html_parse(html);

    let series = [];

    // Select search result items
    let items = html_select(html, "div.search-story-item");

    for item in items {
        // Get the link element
        let links = html_select(item, "a.item-img");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Extract manga ID from URL (e.g., manga-xy123456)
        let id = extract_manga_id(href);
        if id == "" {
            continue;
        }

        // Get title
        let title_links = html_select(item, "h3 a");
        let title = "";
        if title_links.len() > 0 {
            title = element_text(title_links[0]);
        }
        if title == "" {
            title = element_attr(link, "title");
        }
        title = title.trim();

        // Get cover image
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        // Get author
        let authors = [];
        let author_links = html_select(item, "span.item-author");
        if author_links.len() > 0 {
            let author = element_text(author_links[0]).trim();
            if author != "" {
                authors.push(author);
            }
        }

        // Get status and latest chapter info
        let status = ();
        let info_spans = html_select(item, "span.item-time");
        for span in info_spans {
            let text = element_text(span).to_lower();
            if text.contains("ongoing") {
                status = "Ongoing";
            } else if text.contains("completed") {
                status = "Completed";
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
            status: status,
            genres: [],
            tags: [],
            description: ()
        });
    }

    // Check for next page
    let has_more = false;
    let next_pages = html_select(html, "a.page-blue.page-last");
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
        // Try chapmanganato first (more reliable)
        url = `${CHAPTER_BASE}/${id_or_url}`;
    } else {
        id = extract_manga_id(id_or_url);
    }

    let html = http_get_with_headers(url, get_headers());

    // If chapmanganato fails, try manganato
    if html.len() < 1000 || html.contains("404") {
        url = `${BASE_URL}/${id}`;
        html = http_get_with_headers(url, get_headers());
    }

    let doc = html_parse(html);

    // Extract title
    let title = "";
    let title_els = html_select(html, "h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover
    let cover_url = ();
    let cover_imgs = html_select(html, "span.info-image img");
    if cover_imgs.len() > 0 {
        cover_url = element_attr(cover_imgs[0], "src");
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "div.panel-story-info-description");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]);
        // Clean up description
        description = description.replace("Description :", "").trim();
    }

    // Extract info from table
    let authors = [];
    let genres = [];
    let status = ();
    let alt_titles = [];

    let table_rows = html_select(html, "table.variations-tableInfo tr");
    for row in table_rows {
        let label_els = html_select(row, "td.table-label");
        let value_els = html_select(row, "td.table-value");

        if label_els.len() > 0 && value_els.len() > 0 {
            let label = element_text(label_els[0]).to_lower();
            let value_html = value_els[0];

            if label.contains("author") {
                let author_links = html_select(value_html, "a");
                for link in author_links {
                    let author = element_text(link).trim();
                    if author != "" && !authors.contains(author) {
                        authors.push(author);
                    }
                }
            } else if label.contains("genre") {
                let genre_links = html_select(value_html, "a");
                for link in genre_links {
                    let genre = element_text(link).trim();
                    if genre != "" && !genres.contains(genre) {
                        genres.push(genre);
                    }
                }
            } else if label.contains("status") {
                let status_text = element_text(value_html).to_lower();
                if status_text.contains("ongoing") {
                    status = "Ongoing";
                } else if status_text.contains("completed") {
                    status = "Completed";
                }
            } else if label.contains("alternative") {
                let alt_text = element_text(value_html);
                let alts = alt_text.split(";");
                for alt in alts {
                    let cleaned = alt.trim();
                    if cleaned != "" && cleaned != title {
                        alt_titles.push(cleaned);
                    }
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
        url = `${CHAPTER_BASE}/${series_id}`;
    }

    let html = http_get_with_headers(url, get_headers());

    // If chapmanganato fails, try manganato
    if html.len() < 1000 || html.contains("404") {
        let id = extract_manga_id(series_id);
        url = `${BASE_URL}/${id}`;
        html = http_get_with_headers(url, get_headers());
    }

    let chapters = [];

    // Find chapter list
    let chapter_links = html_select(html, "ul.row-content-chapter li a.chapter-name");

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let chapter_title = element_text(link).trim();

        // Extract chapter number from URL or title
        let chapter_num = extract_chapter_number(href, chapter_title);

        // Get upload date from sibling span
        let uploaded_at = ();

        chapters.push(#{
            id: href,
            series_id: series_id,
            number: chapter_num,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: href,
            published_at: uploaded_at,
            page_count: (),
            extra: #{}
        });
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": CHAPTER_BASE
    };

    let html = http_get_with_headers(url, headers);

    let pages = [];
    let idx = 0;

    // Find all page images in the reader container
    let page_imgs = html_select(html, "div.container-chapter-reader img");

    for img in page_imgs {
        let img_url = element_attr(img, "src");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-src");
        }

        if img_url != () && img_url != "" && img_url.contains("http") {
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
    let url = `${BASE_URL}/?page=${page}`;

    let html = http_get_with_headers(url, get_headers());

    let series = [];

    // Parse latest updates panel
    let items = html_select(html, "div.content-genres-item");

    for item in items {
        let links = html_select(item, "a.genres-item-img");
        if links.len() == 0 {
            continue;
        }
        let link = links[0];

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let id = extract_manga_id(href);
        if id == "" {
            continue;
        }

        let title = element_attr(link, "title");
        if title == () || title == "" {
            let title_els = html_select(item, "h3 a");
            if title_els.len() > 0 {
                title = element_text(title_els[0]);
            }
        }
        title = title.trim();

        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
        }

        if title != "" {
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

/// Get popular series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/genre-all?page=${page}`;

    let html = http_get_with_headers(url, get_headers());

    let series = [];

    let items = html_select(html, "div.content-genres-item");

    for item in items {
        let links = html_select(item, "a.genres-item-img");
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
        if title == () {
            let title_els = html_select(item, "h3 a");
            if title_els.len() > 0 {
                title = element_text(title_els[0]);
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
    // URL format: https://manganato.com/manga-xy123456 or https://chapmanganato.to/manga-xy123456
    let parts = url.split("/");
    for part in parts {
        if part.starts_with("manga-") {
            return part;
        }
    }
    // Try to find any manga slug
    let last_part = parts[parts.len() - 1];
    if last_part.contains("manga") {
        return last_part;
    }
    ""
}

/// Extract chapter number from URL or title
fn extract_chapter_number(url, title) {
    // Try to extract from URL first (more reliable)
    // URL format: .../chapter-123 or .../chapter-123.5
    let parts = url.split("/");
    for part in parts {
        if part.starts_with("chapter-") {
            let num = part.replace("chapter-", "");
            // Clean up any query params
            let clean = num.split("?")[0];
            return clean;
        }
    }

    // Fall back to title parsing
    // Title format: "Chapter 123" or "Chapter 123.5" or "Ch. 123"
    let title_lower = title.to_lower();
    if title_lower.contains("chapter") {
        let after_chapter = title_lower.split("chapter")[1];
        let cleaned = after_chapter.trim();
        // Extract just the number part
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

    // Last resort - try to find any number
    "0"
}
