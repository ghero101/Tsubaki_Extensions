// Asura Scans Scraper Add-on (Rhai)
// HTML-based scraper for asuracomic.net
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   html_parse(html) -> Document
//   regex_match(pattern, text) -> [string] | ()

const BASE_URL = "https://asuracomic.net";

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

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    };

    let html = http_get_with_headers(url, headers);
    let doc = html_parse(html);

    let series = [];
    let query_lower = query.to_lower();

    // Select all series links
    for link in doc.select("a[href*='series/']") {
        let href = link.attr("href");

        // Skip chapter links
        if href == () || href.contains("/chapter/") {
            continue;
        }

        // Extract slug from href
        let slug = "";
        if href.starts_with("series/") {
            slug = href.replace("series/", "");
        } else if href.contains("/series/") {
            let parts = href.split("/series/");
            if parts.len() > 1 {
                slug = parts[1];
            }
        }

        // Skip if slug has additional paths or is empty
        if slug.contains("/") || slug == "" {
            continue;
        }

        // Get title from span or link text
        let title_span = link.select_one("span");
        let title = if title_span != () { title_span.text() } else { link.text() };

        // Clean up title
        title = title.trim();
        if title.contains("Chapter") {
            let parts = title.split("Chapter");
            title = parts[0].trim();
        }
        title = title.replace("MANHWA", "").replace("MANGA", "").trim();

        // Skip invalid titles
        if title.len() < 3 || title.len() > 150 {
            continue;
        }

        // Filter by search query if provided
        if query != "" && !title.to_lower().contains(query_lower) {
            continue;
        }

        // Extract cover image
        let img = link.select_one("img");
        let cover_url = if img != () { img.attr("src") } else { () };

        let series_url = `${BASE_URL}/series/${slug}`;

        series.push(#{
            id: slug,
            title: title,
            url: series_url,
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
    let has_more = doc.select_one("a[rel='next']") != ();

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
            slug = parts[1].split("/")[0];
        }
    }

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    };

    let html = http_get_with_headers(url, headers);
    let doc = html_parse(html);

    // Extract title
    let title_el = doc.select_one("h1");
    let title = if title_el != () { title_el.text().trim() } else { "" };

    // Extract cover
    let cover_el = doc.select_one("img.rounded-md, img[alt='poster']");
    let cover_url = if cover_el != () { cover_el.attr("src") } else { () };

    // Extract description
    let desc_el = doc.select_one("div.prose, div.description");
    let description = if desc_el != () { desc_el.text().trim() } else { () };

    // Extract status
    let status = ();
    for span in doc.select("span") {
        let text = span.text().to_lower();
        if text.contains("ongoing") {
            status = "Ongoing";
            break;
        } else if text.contains("completed") {
            status = "Completed";
            break;
        } else if text.contains("hiatus") {
            status = "Hiatus";
            break;
        }
    }

    // Extract genres
    let genres = [];
    for genre_link in doc.select("a[href*='genre/']") {
        let genre = genre_link.text().trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Extract authors
    let authors = [];
    for author_el in doc.select("a[href*='author/'], span.author") {
        let author = author_el.text().trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    #{
        id: slug,
        title: title,
        alternate_titles: [],
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
        url = `${BASE_URL}/series/${series_id}`;
    }

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    };

    let html = http_get_with_headers(url, headers);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    // Find all chapter links
    for link in doc.select("a[href*='/chapter/']") {
        let href = link.attr("href");
        if href == () {
            continue;
        }

        // Extract chapter number from URL
        let chapter_num = "";
        let parts = href.split("/chapter/");
        if parts.len() > 1 {
            chapter_num = parts[1].split("/")[0].split("?")[0];
        }

        // Skip if already seen
        if seen.contains(chapter_num) {
            continue;
        }
        seen[chapter_num] = true;

        // Build full URL
        let chapter_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                chapter_url = `${BASE_URL}${href}`;
            } else {
                chapter_url = `${BASE_URL}/${href}`;
            }
        }

        // Extract title if available
        let title_span = link.select_one("span");
        let title = if title_span != () { title_span.text().trim() } else { () };

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

    // Sort chapters by number
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

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Referer": BASE_URL
    };

    let html = http_get_with_headers(url, headers);
    let doc = html_parse(html);

    let pages = [];
    let idx = 0;

    // Find all page images
    for img in doc.select("div.reader-content img, div.chapter-images img, img[src*='wp-content']") {
        let img_url = img.attr("src");
        if img_url == () {
            img_url = img.attr("data-src");
        }

        if img_url != () && img_url.contains("http") {
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
    let url = `${BASE_URL}?page=${page}`;

    let headers = #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    };

    let html = http_get_with_headers(url, headers);
    let doc = html_parse(html);

    let series = [];

    for item in doc.select("div.latest-update-item, article.update-item") {
        let link = item.select_one("a[href*='series/']");
        if link == () {
            continue;
        }

        let href = link.attr("href");
        let slug = "";
        if href.contains("/series/") {
            let parts = href.split("/series/");
            if parts.len() > 1 {
                slug = parts[1].split("/")[0];
            }
        }

        let title = link.text().trim();
        let img = item.select_one("img");
        let cover_url = if img != () { img.attr("src") } else { () };

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

    let has_more = doc.select_one("a[rel='next']") != ();

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
