// Tsubaki Scraper Add-on Template (Rhai)
//
// This template provides the required functions for a scraper add-on.
// Implement each function to scrape your target source.
//
// Available APIs:
//   http_get(url) -> string           - Fetch URL content
//   http_get_with_headers(url, headers) -> string
//   http_post(url, body) -> string    - POST request
//   html_parse(html) -> Document      - Parse HTML
//   json_parse(text) -> Dynamic       - Parse JSON
//   json_stringify(value) -> string   - Serialize to JSON
//
// Document methods:
//   doc.select(selector) -> [Element]
//   doc.select_one(selector) -> Element | ()
//
// Element methods:
//   el.text() -> string
//   el.html() -> string
//   el.attr(name) -> string | ()
//   el.select(selector) -> [Element]
//   el.select_one(selector) -> Element | ()

// Source base URL
const BASE_URL = "https://yoursource.com";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "your-source-id",
        name: "Your Source Name",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Search for series matching query
/// Returns: #{ series: [...], has_more: bool, total: int | () }
fn search_series(query, page, auth) {
    // Build search URL
    let url = `${BASE_URL}/search?q=${query}&page=${page}`;

    // Fetch and parse
    let html = http_get(url);
    let doc = html_parse(html);

    // Extract series
    let series = [];
    for item in doc.select("div.series-item") {
        let link = item.select_one("a.title");
        let img = item.select_one("img");

        if link != () {
            series.push(#{
                id: link.attr("href"),
                title: link.text(),
                url: link.attr("href"),
                cover_url: if img != () { img.attr("src") } else { () },
                alternate_titles: [],
                authors: [],
                artists: [],
                status: (),
                genres: [],
                tags: [],
                description: ()
            });
        }
    }

    // Check for next page
    let has_more = doc.select_one("a.next-page") != ();

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
/// Returns: SeriesInfo
fn get_series(id_or_url, auth) {
    let url = if id_or_url.starts_with("http") { id_or_url } else { `${BASE_URL}${id_or_url}` };

    let html = http_get(url);
    let doc = html_parse(html);

    // Extract series details
    let title = doc.select_one("h1.title");
    let desc = doc.select_one("div.description");
    let cover = doc.select_one("img.cover");
    let status = doc.select_one("span.status");

    // Extract authors
    let authors = [];
    for author in doc.select("a.author") {
        authors.push(author.text());
    }

    // Extract genres
    let genres = [];
    for genre in doc.select("a.genre") {
        genres.push(genre.text());
    }

    #{
        id: url,
        title: if title != () { title.text() } else { "" },
        alternate_titles: [],
        description: if desc != () { desc.text() } else { () },
        cover_url: if cover != () { cover.attr("src") } else { () },
        authors: authors,
        artists: [],
        status: if status != () { status.text() } else { () },
        genres: genres,
        tags: [],
        year: (),
        content_rating: (),
        url: url,
        extra: #{}
    }
}

/// Get all chapters for a series
/// Returns: [ChapterInfo]
fn get_chapters(series_id, auth) {
    let url = if series_id.starts_with("http") { series_id } else { `${BASE_URL}${series_id}` };

    let html = http_get(url);
    let doc = html_parse(html);

    let chapters = [];
    for item in doc.select("li.chapter-item a") {
        let chapter_url = item.attr("href");
        let chapter_text = item.text();

        // Extract chapter number from text (adjust regex as needed)
        let number = chapter_text.replace("Chapter ", "").trim();

        chapters.push(#{
            id: chapter_url,
            series_id: series_id,
            number: number,
            title: (),
            volume: (),
            language: "en",
            scanlator: (),
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    chapters
}

/// Get page URLs for a chapter
/// Returns: [PageInfo]
fn get_chapter_pages(chapter_id, auth) {
    let url = if chapter_id.starts_with("http") { chapter_id } else { `${BASE_URL}${chapter_id}` };

    let html = http_get(url);
    let doc = html_parse(html);

    let pages = [];
    let idx = 0;

    for img in doc.select("div.reader-content img") {
        let img_url = img.attr("src");
        if img_url == () {
            img_url = img.attr("data-src");
        }

        if img_url != () {
            pages.push(#{
                index: idx,
                url: img_url,
                headers: #{},
                referer: url
            });
            idx += 1;
        }
    }

    pages
}

// Optional: Custom login handler
// fn login(credentials) {
//     let username = credentials["username"];
//     let password = credentials["password"];
//
//     let response = http_post(`${BASE_URL}/login`, #{
//         username: username,
//         password: password
//     });
//
//     // Return updated auth context with session info
//     #{
//         credentials: credentials,
//         cookies: [],
//         session_token: ()
//     }
// }

// Optional: Get latest updates
// fn get_latest_updates(page, auth) {
//     let url = `${BASE_URL}/latest?page=${page}`;
//     let html = http_get(url);
//     // ... parse and return series list
//     []
// }
