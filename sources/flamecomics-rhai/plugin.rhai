// Flame Comics Scraper Add-on (Rhai)
// Next.js based site with __NEXT_DATA__ JSON
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   html_parse(html) -> Document
//   json_parse(text) -> Dynamic
//   regex_find(pattern, text) -> string | ()

const BASE_URL = "https://flamecomics.xyz";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "flamecomics",
        name: "Flame Comics",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Extract __NEXT_DATA__ JSON from Next.js HTML
fn extract_next_data(html) {
    // Find the __NEXT_DATA__ script tag
    let start_marker = `<script id="__NEXT_DATA__" type="application/json">`;
    let end_marker = `</script>`;

    let start = html.index_of(start_marker);
    if start == () {
        return ();
    }

    let json_start = start + start_marker.len();
    let rest = html.sub_string(json_start);
    let end = rest.index_of(end_marker);

    if end == () {
        return ();
    }

    let json_str = rest.sub_string(0, end);
    json_parse(json_str)
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let url = BASE_URL;

    let html = http_get(url);
    let next_data = extract_next_data(html);

    if next_data == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let query_lower = query.to_lower();

    // Extract series from latestEntries blocks
    let props = next_data["props"];
    if props == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let page_props = props["pageProps"];
    if page_props == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let latest_entries = page_props["latestEntries"];
    if latest_entries != () {
        let blocks = latest_entries["blocks"];
        if blocks != () {
            for block in blocks {
                let block_series = block["series"];
                if block_series != () {
                    for s in block_series {
                        let title = s["title"];
                        if title == () {
                            continue;
                        }

                        // Filter by query if provided
                        if query != "" && !title.to_lower().contains(query_lower) {
                            continue;
                        }

                        let series_id = s["series_id"];
                        let cover = s["cover"];
                        let description = s["description"];
                        let alt_titles = s["altTitles"];
                        let authors = s["author"];
                        let artists = s["artist"];
                        let tags = s["tags"];

                        series.push(#{
                            id: `${series_id}`,
                            title: title,
                            url: `${BASE_URL}/series/${series_id}`,
                            cover_url: cover,
                            alternate_titles: if alt_titles != () { alt_titles } else { [] },
                            authors: if authors != () { authors } else { [] },
                            artists: if artists != () { artists } else { [] },
                            status: (),
                            genres: if tags != () { tags } else { [] },
                            tags: [],
                            description: description
                        });
                    }
                }
            }
        }
    }

    #{ series: series, has_more: false, total: series.len() }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let series_id = id_or_url;

    if id_or_url.contains("/series/") {
        let parts = id_or_url.split("/series/");
        if parts.len() > 1 {
            series_id = parts[1].split("/")[0];
        }
    }

    let url = `${BASE_URL}/series/${series_id}`;
    let html = http_get(url);
    let next_data = extract_next_data(html);

    if next_data == () {
        return #{
            id: series_id,
            title: "",
            error: "Failed to extract data"
        };
    }

    let props = next_data["props"];
    let page_props = props["pageProps"];
    let series_data = page_props["series"];

    if series_data == () {
        return #{
            id: series_id,
            title: "",
            error: "Series not found"
        };
    }

    let title = series_data["title"];
    let cover = series_data["cover"];
    let description = series_data["description"];
    let alt_titles = series_data["altTitles"];
    let authors = series_data["author"];
    let artists = series_data["artist"];
    let tags = series_data["tags"];

    #{
        id: series_id,
        title: if title != () { title } else { "" },
        alternate_titles: if alt_titles != () { alt_titles } else { [] },
        description: description,
        cover_url: cover,
        authors: if authors != () { authors } else { [] },
        artists: if artists != () { artists } else { [] },
        status: (),
        genres: if tags != () { tags } else { [] },
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
    } else {
        // Extract series_id from URL
        let parts = series_id.split("/series/");
        if parts.len() > 1 {
            series_id = parts[1].split("/")[0];
        }
    }

    let html = http_get(url);
    let next_data = extract_next_data(html);

    if next_data == () {
        return [];
    }

    let props = next_data["props"];
    let page_props = props["pageProps"];
    let chapters_data = page_props["chapters"];

    if chapters_data == () {
        return [];
    }

    let chapters = [];

    for ch in chapters_data {
        let chapter_id = ch["chapter_id"];
        let chapter_num = ch["chapter"];
        let title = ch["title"];

        chapters.push(#{
            id: `${chapter_id}`,
            series_id: series_id,
            number: chapter_num,
            title: title,
            volume: (),
            language: "en",
            scanlator: "Flame Comics",
            url: `${BASE_URL}/read/${chapter_id}`,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // Sort by chapter number (descending - newest first)
    chapters.sort(|a, b| {
        let num_a = parse_float(a.number);
        let num_b = parse_float(b.number);
        if num_a > num_b { -1 } else if num_a < num_b { 1 } else { 0 }
    });

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}/read/${chapter_id}`;
    }

    let html = http_get(url);
    let next_data = extract_next_data(html);

    if next_data == () {
        return [];
    }

    let props = next_data["props"];
    let page_props = props["pageProps"];
    let images = page_props["images"];

    if images == () {
        return [];
    }

    let pages = [];
    let idx = 0;

    for img_url in images {
        pages.push(#{
            index: idx,
            url: img_url,
            headers: #{
                "Referer": BASE_URL
            },
            referer: BASE_URL
        });
        idx += 1;
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    // Use the same logic as search but without query filter
    search_series("", page, auth)
}

/// Helper: Parse float from string
fn parse_float(s) {
    if s == () { return 0.0; }
    let result = 0.0;
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
