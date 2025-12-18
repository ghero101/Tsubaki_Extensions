// MangaSee Scraper Add-on (Rhai)
// Scrapes mangasee123.com (also works with manga4life.com)
// Uses embedded JSON data from page JavaScript
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   json_parse(text) -> Dynamic
//   regex_find(pattern, text) -> string
//   regex_find_all(pattern, text) -> array

const BASE_URL = "https://mangasee123.com";
const COVER_URL = "https://cover.nep.li/cover";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangasee-rhai",
        name: "MangaSee",
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

/// Extract JSON from vm.Variable = [...]; pattern
fn extract_vm_json(html, var_name) {
    // Look for vm.VarName = [...]
    let pattern = `vm\\.${var_name}\\s*=\\s*(\\[.*?\\]);`;
    let match = regex_find(pattern, html);

    if match == () || match == "" {
        return [];
    }

    // Parse the JSON
    let parsed = json_parse(match);
    if parsed == () {
        return [];
    }

    parsed
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // MangaSee uses client-side search from directory
    // We need to fetch the directory and filter
    let url = `${BASE_URL}/search/`;

    let html = http_get_with_headers(url, get_headers());

    // Extract directory JSON
    let directory = extract_vm_json(html, "Directory");

    let series = [];
    let query_lower = query.to_lower();
    let start_idx = (page - 1) * 25;
    let end_idx = start_idx + 25;
    let count = 0;

    for manga in directory {
        // Check if title matches
        let title = manga["s"];
        let alt_titles = manga["al"];

        let matches = false;
        if title.to_lower().contains(query_lower) {
            matches = true;
        }

        // Check alternate titles
        if !matches && alt_titles != () {
            for alt in alt_titles {
                if alt.to_lower().contains(query_lower) {
                    matches = true;
                    break;
                }
            }
        }

        if matches {
            if count >= start_idx && count < end_idx {
                let slug = manga["i"];

                // Get genres
                let genres = [];
                if manga.contains("g") {
                    genres = manga["g"];
                }

                // Get status
                let status = ();
                if manga.contains("ss") {
                    let ss = manga["ss"];
                    if ss == "Ongoing" {
                        status = "Ongoing";
                    } else if ss == "Complete" {
                        status = "Completed";
                    } else if ss == "Hiatus" {
                        status = "Hiatus";
                    }
                }

                series.push(#{
                    id: slug,
                    title: title,
                    url: `${BASE_URL}/manga/${slug}`,
                    cover_url: `${COVER_URL}/${slug}.jpg`,
                    alternate_titles: if alt_titles != () { alt_titles } else { [] },
                    authors: [],
                    artists: [],
                    status: status,
                    genres: genres,
                    tags: [],
                    description: ()
                });
            }
            count += 1;
        }
    }

    let has_more = count > end_idx;

    #{ series: series, has_more: has_more, total: count }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let slug = id_or_url;

    // Extract slug from URL if needed
    if id_or_url.contains("mangasee") || id_or_url.contains("manga4life") {
        let parts = id_or_url.split("/manga/");
        if parts.len() > 1 {
            slug = parts[1].split("/")[0].split("?")[0];
        }
    }

    let url = `${BASE_URL}/manga/${slug}`;

    let html = http_get_with_headers(url, get_headers());

    // Extract title from page
    let title = slug;
    let title_match = regex_find(`<h1[^>]*>([^<]+)</h1>`, html);
    if title_match != () && title_match != "" {
        title = title_match.trim();
    }

    // Extract description
    let description = ();
    let desc_match = regex_find(`<span class="mlabel">Description:</span>\\s*<div[^>]*>([^<]+)`, html);
    if desc_match != () {
        description = desc_match.trim();
    }

    // Try to extract from Li-PageHeading
    let heading_match = regex_find(`class=".*?Description[^"]*"[^>]*>([^<]+)`, html);
    if heading_match != () && heading_match != "" {
        description = heading_match.trim();
    }

    // Extract authors
    let authors = [];
    let author_matches = regex_find_all(`/search/\\?author=[^"]+">([^<]+)`, html);
    for author in author_matches {
        let cleaned = author.trim();
        if cleaned != "" && !authors.contains(cleaned) {
            authors.push(cleaned);
        }
    }

    // Extract genres
    let genres = [];
    let genre_matches = regex_find_all(`/search/\\?genre=[^"]+">([^<]+)`, html);
    for genre in genre_matches {
        let cleaned = genre.trim();
        if cleaned != "" && !genres.contains(cleaned) {
            genres.push(cleaned);
        }
    }

    // Extract status
    let status = ();
    if html.contains("Ongoing (Pub") || html.contains("Status(Pub</") && html.contains("Ongoing") {
        status = "Ongoing";
    } else if html.contains("Complete (Pub") || html.contains("Complete") {
        status = "Completed";
    }

    // Extract alternate titles
    let alt_titles = [];
    let alt_match = regex_find(`<span class="mlabel">Alternate Name\\(s\\):</span>([^<]+)`, html);
    if alt_match != () && alt_match != "" {
        let alts = alt_match.split(",");
        for alt in alts {
            let cleaned = alt.trim();
            if cleaned != "" && cleaned != title {
                alt_titles.push(cleaned);
            }
        }
    }

    #{
        id: slug,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: `${COVER_URL}/${slug}.jpg`,
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
    let slug = series_id;

    if series_id.contains("/") {
        let parts = series_id.split("/manga/");
        if parts.len() > 1 {
            slug = parts[1].split("/")[0];
        }
    }

    let url = `${BASE_URL}/manga/${slug}`;

    let html = http_get_with_headers(url, get_headers());

    // Extract chapters JSON
    let chapters_data = extract_vm_json(html, "Chapters");

    let chapters = [];

    for ch in chapters_data {
        // Chapter field is encoded: "100010" = Chapter 1
        // Format: CCCVVVVPP where C=chapter, V=volume, P=decimal
        let chapter_str = ch["Chapter"];

        // Decode chapter number
        let ch_num = decode_chapter_number(chapter_str);

        // Get chapter type (usually empty or "1" for normal chapters)
        let ch_type = ch["Type"];

        // Get date
        let date = ch["Date"];

        // Build chapter URL
        // URL format: /read-online/Slug-chapter-X.html or /read-online/Slug-chapter-X-index-2.html
        let chapter_url = `${BASE_URL}/read-online/${slug}-chapter-${ch_num}.html`;

        chapters.push(#{
            id: chapter_url,
            series_id: slug,
            number: ch_num,
            title: (),
            volume: (),
            language: "en",
            scanlator: (),
            url: chapter_url,
            published_at: date,
            page_count: (),
            extra: #{
                chapter_type: ch_type
            }
        });
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    let html = http_get_with_headers(url, get_headers());

    // Extract chapter data
    let cur_chapter = ();
    let cur_match = regex_find(`vm\\.CurChapter\\s*=\\s*(\\{[^}]+\\})`, html);
    if cur_match != () && cur_match != "" {
        cur_chapter = json_parse(cur_match);
    }

    if cur_chapter == () {
        return [];
    }

    // Extract index name (manga slug)
    let index_name = regex_find(`vm\\.IndexName\\s*=\\s*"([^"]+)"`, html);
    if index_name == () {
        // Try to extract from URL
        let parts = url.split("/read-online/");
        if parts.len() > 1 {
            index_name = parts[1].split("-chapter")[0];
        }
    }

    if index_name == () || index_name == "" {
        return [];
    }

    // Get page count
    let page_count = 0;
    if cur_chapter.contains("Page") {
        page_count = parse_int(cur_chapter["Page"]);
    }

    // Get chapter number for URL
    let chapter_str = cur_chapter["Chapter"];
    let chapter_num = decode_chapter_number(chapter_str);

    // Determine image server
    // Usually: https://official-ongoing-1.ivalice.us/manga/Slug/CCCC-PPP.png
    let base_image_url = "https://official-ongoing-1.ivalice.us/manga";

    // Build chapter path
    // Chapter 1 = 0001, Chapter 10 = 0010, Chapter 100.5 = 0100.5
    let chapter_path = format_chapter_path(chapter_str);

    let pages = [];

    for i in 1..=page_count {
        // Format page number: 001, 010, 100
        let page_str = "";
        if i < 10 {
            page_str = `00${i}`;
        } else if i < 100 {
            page_str = `0${i}`;
        } else {
            page_str = `${i}`;
        }

        let img_url = `${base_image_url}/${index_name}/${chapter_path}-${page_str}.png`;

        pages.push(#{
            index: i - 1,
            url: img_url,
            headers: #{
                "Referer": BASE_URL
            },
            referer: BASE_URL
        });
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/`;

    let html = http_get_with_headers(url, get_headers());

    // Extract latest updates JSON
    let latest = extract_vm_json(html, "LatestJSON");

    let series = [];
    let start_idx = (page - 1) * 25;
    let end_idx = start_idx + 25;
    let count = 0;

    for item in latest {
        if count >= start_idx && count < end_idx {
            let slug = item["IndexName"];
            let title = item["SeriesName"];

            series.push(#{
                id: slug,
                title: title,
                url: `${BASE_URL}/manga/${slug}`,
                cover_url: `${COVER_URL}/${slug}.jpg`,
                updated_at: item["Date"]
            });
        }
        count += 1;
    }

    let has_more = count > end_idx;

    #{ series: series, has_more: has_more }
}

/// Get popular/hot series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/`;

    let html = http_get_with_headers(url, get_headers());

    // Extract hot updates JSON
    let hot = extract_vm_json(html, "HotUpdateJSON");

    let series = [];
    let start_idx = (page - 1) * 25;
    let end_idx = start_idx + 25;
    let count = 0;

    for item in hot {
        if count >= start_idx && count < end_idx {
            let slug = item["IndexName"];
            let title = item["SeriesName"];

            series.push(#{
                id: slug,
                title: title,
                url: `${BASE_URL}/manga/${slug}`,
                cover_url: `${COVER_URL}/${slug}.jpg`
            });
        }
        count += 1;
    }

    let has_more = count > end_idx;

    #{ series: series, has_more: has_more }
}

// === Helper Functions ===

/// Decode chapter number from MangaSee format
/// Format: CCCVVVVPP where C=chapter (4 digits), V=volume, P=decimal
fn decode_chapter_number(chapter_str) {
    if chapter_str == () || chapter_str == "" {
        return "0";
    }

    // Remove leading zeros and parse
    // "100010" -> Chapter 1 (1000 + 1 = chapter 1, last digit is decimal * 0.1)
    let len = chapter_str.len();

    // Get chapter part (skip first digit which is always 1, take next 3)
    let ch_part = "";
    if len >= 4 {
        ch_part = chapter_str.sub_string(1, 4);
        // Remove leading zeros
        while ch_part.starts_with("0") && ch_part.len() > 1 {
            ch_part = ch_part.sub_string(1);
        }
    }

    // Get decimal part (last digit)
    let decimal = "0";
    if len >= 1 {
        decimal = chapter_str.sub_string(len - 1);
    }

    if decimal != "0" {
        return `${ch_part}.${decimal}`;
    }

    ch_part
}

/// Format chapter path for image URL
fn format_chapter_path(chapter_str) {
    if chapter_str == () || chapter_str == "" {
        return "0001";
    }

    // Get the raw chapter number (digits 2-5)
    let len = chapter_str.len();
    if len >= 5 {
        return chapter_str.sub_string(1, 5);
    }

    "0001"
}

/// Parse integer from string
fn parse_int(s) {
    if s == () { return 0; }
    let result = 0;
    for c in s.chars() {
        if c >= '0' && c <= '9' {
            result = result * 10 + (c.to_int() - '0'.to_int());
        }
    }
    result
}
