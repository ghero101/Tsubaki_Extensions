// Kagane Scraper Add-on (Rhai)
// Hybrid scraper for kagane.org — Yuzuki API + FlareSolverr + Browser rendering
//
// Architecture:
//   - Series metadata & chapters: Direct Yuzuki API (https://yuzuki.kagane.org/api/v2/)
//   - Browse/homepage: FlareSolverr renders the Cloudflare-protected page
//   - Search: Direct Yuzuki API (POST /search/series)
//   - Chapter pages: Browser with Widevine DRM → extract CDN URLs from performance log
//
// URL Patterns:
//   Homepage:  /
//   Series:    /series/{UUID}
//   Reader:    /series/{SERIES_UUID}/reader/{BOOK_UUID}
//   Search:    /search?q={query}
//
// IDs are UUIDs (e.g., 019c4756-d998-787a-bf75-9f095ea56701)
// Cover images: https://yuzuki.kagane.org/api/v2/image/{UUID}/compressed

const BASE_URL = "https://kagane.org";
const API_BASE = "https://yuzuki.kagane.org/api/v2";

// ============================================================================
// API Helpers
// ============================================================================

fn api_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Origin": "https://kagane.org",
        "Referer": "https://kagane.org/"
    }
}

/// GET from Yuzuki API (no Cloudflare protection).
fn api_get(path) {
    let url = `${API_BASE}${path}`;
    let body = http_get_with_headers(url, api_headers());
    json_parse(body)
}

/// POST JSON to Yuzuki API.
fn api_post(path, json_body) {
    let url = `${API_BASE}${path}`;
    let body = http_post_json_with_headers(url, json_body, api_headers());
    json_parse(body)
}

// ============================================================================
// Content Validation
// ============================================================================

/// Check if HTML contains real rendered content (not just the Next.js shell).
fn has_real_content(html) {
    html.len() > 60000 && (
        html.contains("data-slot=\"carousel-item\"") ||
        html.contains("/series/019") ||
        html.contains("yuzuki.kagane.org") ||
        html.contains("font-bold") && html.contains("/series/")
    )
}

// ============================================================================
// Fetch Helpers — Hybrid: FlareSolverr cookies + Browser rendering
// ============================================================================

/// Launch browser, inject Cloudflare cookies + user-agent, navigate, and wait.
fn browser_with_cookies(url, wait_selector, cookies, user_agent) {
    let browser_id = browser_launch_stealth();

    if user_agent != "" {
        try { browser_set_user_agent(browser_id, user_agent); } catch {}
    }

    browser_set_cookies(browser_id, cookies);
    browser_goto(browser_id, url);

    try {
        browser_wait_for_selector(browser_id, wait_selector, 30000);
    } catch {
        try { browser_wait_for_selector(browser_id, "h3, a[href*='/series/']", 15000); } catch {}
    }

    let html = browser_get_html(browser_id);
    #{ browser_id: browser_id, html: html }
}

/// Fetch a page using FlareSolverr or hybrid browser approach.
fn fetch_page(url, wait_selector) {
    // Method 1: Hybrid — FlareSolverr cookies + Browser rendering
    if browser_is_available() && flaresolverr_is_available() {
        try {
            let solver = flaresolverr_get_cookies(url, 60000);
            let cookies = solver.cookies;
            let fs_html = solver.html;
            let user_agent = solver.user_agent;

            if fs_html != "" && has_real_content(fs_html) {
                return fs_html;
            }

            if cookies.len() > 0 {
                let result = browser_with_cookies(url, wait_selector, cookies, user_agent);
                let html = result.html;
                try { browser_close(result.browser_id); } catch {}
                if html != "" && html.len() > 60000 {
                    return html;
                }
            }
        } catch {}
    }

    // Method 2: FlareSolverr-only
    if flaresolverr_is_available() {
        try {
            let html = flaresolverr_get(url, 60000);
            if html != "" && html.len() > 60000 {
                return html;
            }
        } catch {}
    }

    // Method 3: Browser-only
    if browser_is_available() {
        try {
            let browser_id = browser_launch_stealth();
            browser_goto(browser_id, url);
            browser_wait_for_cloudflare(browser_id, 35000);
            try { browser_wait_for_selector(browser_id, wait_selector, 25000); } catch {}
            let html = browser_get_html(browser_id);
            browser_close(browser_id);
            if html != "" && html.len() > 60000 {
                return html;
            }
        } catch {}
    }

    // Method 4: HTTP fallback
    try {
        let headers = #{
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml",
            "Referer": BASE_URL
        };
        return http_get_with_headers(url, headers);
    } catch {
        return "";
    }
}

// ============================================================================
// ID Extraction Helpers
// ============================================================================

/// Extract series UUID from a URL path.
fn extract_series_id(url) {
    let result = regex_find("/series/([0-9a-f-]{36})", url);
    if result != "" {
        return result.replace("/series/", "");
    }
    let old = regex_find("/series/([A-Za-z0-9]{20,})", url);
    if old != "" {
        return old.replace("/series/", "");
    }
    ""
}

/// Map status text to standard format.
fn map_status(status) {
    let s = status.to_upper().trim();
    if s.contains("ONGOING") { return "Ongoing"; }
    if s.contains("COMPLETED") { return "Completed"; }
    if s.contains("HIATUS") { return "Hiatus"; }
    if s.contains("CANCELLED") || s.contains("CANCELED") { return "Cancelled"; }
    if s.contains("DROPPED") { return "Cancelled"; }
    status
}

// ============================================================================
// Series List Extraction (for browse/homepage)
// ============================================================================

/// Parse series entries from rendered HTML.
fn extract_series_list(html) {
    let series = [];
    let seen = #{};

    let all_links = html_select(html, "a[href]");

    for link in all_links {
        let href = element_attr(link, "href");
        if href == () || href == "" || !href.contains("/series/") {
            continue;
        }
        if href.contains("/chapter/") || href.contains("/reader/") {
            continue;
        }

        let sid = extract_series_id(href);
        if sid == "" || seen[sid] != () {
            continue;
        }
        seen[sid] = true;

        let title = "";
        try {
            let h3_els = html_select(element_inner_html(link), "h3");
            if h3_els.len() > 0 {
                title = element_text(h3_els[0]).trim();
            }
        } catch {}

        if title == "" {
            try {
                let imgs = html_select(element_inner_html(link), "img[alt]");
                if imgs.len() > 0 {
                    title = element_attr(imgs[0], "alt");
                    if title == () { title = ""; }
                }
            } catch {}
        }

        if title == "" || title.len() < 2 {
            continue;
        }

        let cover = "";
        try {
            let imgs = html_select(element_inner_html(link), "img[src]");
            if imgs.len() > 0 {
                let src = element_attr(imgs[0], "src");
                if src != () && src.starts_with("http") {
                    cover = src;
                }
            }
        } catch {}

        series.push(#{
            id: sid,
            title: title,
            url: `${BASE_URL}/series/${sid}`,
            cover_url: cover,
            alternate_titles: [],
            authors: [],
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: ()
        });
    }

    // Regex fallback
    if series.len() == 0 {
        let pairs = regex_find_all("href=\"/series/([0-9a-f-]{36})\"", html);
        let titles = regex_find_all("<h3[^>]*>([^<]+)</h3>", html);
        let covers = regex_find_all("src=\"(https://yuzuki[^\"]+)\"", html);

        let unique_sids = [];
        for p in pairs {
            let sid = p.replace("href=\"/series/", "").replace("\"", "");
            if sid.len() >= 30 && seen[sid] == () {
                seen[sid] = true;
                unique_sids.push(sid);
            }
        }

        let title_list = [];
        for t in titles {
            let clean = t.replace(regex_find("<h3[^>]*>", t), "").replace("</h3>", "").trim();
            if clean != "" && clean.len() >= 2 {
                title_list.push(clean);
            }
        }

        let cover_list = [];
        for c in covers {
            let url = c.replace("src=\"", "").replace("\"", "");
            cover_list.push(url);
        }

        let i = 0;
        for sid in unique_sids {
            let title = if i < title_list.len() { title_list[i] } else { `Series ${sid.sub_string(0, 8)}` };
            let cover = if i < cover_list.len() { cover_list[i] } else { "" };
            series.push(#{
                id: sid,
                title: title,
                url: `${BASE_URL}/series/${sid}`,
                cover_url: cover,
                alternate_titles: [],
                authors: [],
                artists: [],
                status: (),
                genres: [],
                tags: [],
                description: ()
            });
            i += 1;
        }
    }

    series
}

// ============================================================================
// Required Interface Functions
// ============================================================================

fn get_source_info() {
    #{
        id: "kagane-rhai",
        name: "Kagane",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

fn browse(page, filters, auth) {
    get_latest_updates(page, auth)
}

/// Get latest updates from homepage (FlareSolverr renders the page).
fn get_latest_updates(page, auth) {
    let url = BASE_URL;
    if page > 1 {
        url = `${BASE_URL}/?page=${page}`;
    }

    let html = fetch_page(url, "a[href*='/series/']");
    if html == "" || !has_real_content(html) {
        return #{ series: [], has_more: false };
    }

    let series = extract_series_list(html);
    #{ series: series, has_more: series.len() > 0 && page < 20 }
}

/// Search for manga via Yuzuki API.
fn search_series(query, page, auth) {
    let api_page = page - 1;
    if api_page < 0 { api_page = 0; }

    let body = `{"title":"${query}","page":${api_page},"size":20}`;
    let data = ();
    try {
        data = api_post("/search/series", body);
    } catch {
        return #{ series: [], has_more: false, total: 0 };
    }

    if data == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let content = data["content"];
    if content == () || type_of(content) != "array" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let total = data["total_elements"];
    let is_last = data["last"];

    let series = [];
    for item in content {
        let sid = item["series_id"];
        if sid == () || sid == "" { continue; }

        let title = "";
        let raw_title = item["title"];
        if raw_title != () && raw_title != "" {
            title = raw_title;
        } else {
            title = `Series ${sid.sub_string(0, 8)}`;
        }

        let cover = "";
        let cover_id = item["cover_image_id"];
        if cover_id != () && cover_id != "" {
            cover = `${API_BASE}/image/${cover_id}/compressed`;
        }

        let status = ();
        let pub_status = item["publication_status"];
        if pub_status != () && pub_status != "" {
            status = map_status(pub_status);
        }

        let alt_titles = [];
        let alts = item["alternate_titles"];
        if alts != () && type_of(alts) == "array" {
            for a in alts {
                if a != () && a != "" {
                    alt_titles.push(a);
                }
            }
        }

        series.push(#{
            id: sid,
            title: title,
            url: `${BASE_URL}/series/${sid}`,
            cover_url: cover,
            alternate_titles: alt_titles,
            authors: [],
            artists: [],
            status: status,
            genres: [],
            tags: [],
            description: ()
        });
    }

    let has_more = if is_last != () { !is_last } else { series.len() >= 20 };

    #{ series: series, has_more: has_more, total: total }
}

/// Get detailed series information via Yuzuki API.
fn get_series(id_or_url, auth) {
    let sid = id_or_url;
    if id_or_url.starts_with("http") {
        sid = extract_series_id(id_or_url);
    } else if id_or_url.starts_with("/series/") {
        sid = id_or_url.replace("/series/", "");
    }
    if sid == "" {
        throw `Invalid series ID: ${id_or_url}`;
    }

    let data = ();
    try {
        data = api_get(`/series/${sid}`);
    } catch {
        throw `Failed to fetch series from API: ${sid}`;
    }

    if data == () {
        throw `Empty API response for series: ${sid}`;
    }

    // Title
    let title = "";
    let raw_title = data["title"];
    if raw_title != () && raw_title != "" {
        title = raw_title;
    }

    // Alt titles
    let alternate_titles = [];
    let alt_list = data["series_alternate_titles"];
    if alt_list != () && type_of(alt_list) == "array" {
        for alt in alt_list {
            let alt_title = alt["title"];
            if alt_title != () && alt_title != "" {
                alternate_titles.push(alt_title);
                if title == "" {
                    title = alt_title;
                }
            }
        }
    }

    if title == "" {
        title = `Series ${sid.sub_string(0, 8)}`;
    }

    // Description
    let description = ();
    let raw_desc = data["description"];
    if raw_desc != () && raw_desc != "" {
        description = raw_desc;
    }

    // Status
    let status = ();
    let pub_status = data["publication_status"];
    if pub_status != () && pub_status != "" {
        status = map_status(pub_status);
    }

    // Genres
    let genres = [];
    let genre_list = data["genres"];
    if genre_list != () && type_of(genre_list) == "array" {
        for g in genre_list {
            let genre_name = g["genre_name"];
            if genre_name != () && genre_name != "" {
                genres.push(genre_name);
            }
        }
    }

    // Cover image — check cover_image_id first, then series_covers array
    let cover = "";
    let cover_id = data["cover_image_id"];
    if cover_id != () && cover_id != "" {
        cover = `${API_BASE}/image/${cover_id}/compressed`;
    }
    if cover == "" {
        let covers = data["series_covers"];
        if covers != () && type_of(covers) == "array" && covers.len() > 0 {
            let img_id = covers[0]["image_id"];
            if img_id != () && img_id != "" {
                cover = `${API_BASE}/image/${img_id}/compressed`;
            }
        }
    }

    // Content rating
    let content_rating = "nsfw";
    let cr = data["content_rating"];
    if cr != () {
        let cr_lower = cr.to_lower();
        if cr_lower == "safe" || cr_lower == "everyone" {
            content_rating = "safe";
        } else if cr_lower == "suggestive" {
            content_rating = "suggestive";
        }
    }

    // Year
    let year = ();
    let start_year = data["start_year"];
    if start_year != () && start_year != "" {
        year = start_year;
    }

    #{
        id: sid,
        title: title,
        alternate_titles: alternate_titles,
        description: description,
        cover_url: cover,
        authors: [],
        artists: [],
        status: status,
        genres: genres,
        tags: [],
        year: year,
        content_rating: content_rating,
        url: `${BASE_URL}/series/${sid}`,
        extra: #{}
    }
}

/// Get all chapters for a series via Yuzuki API.
fn get_chapters(series_id, auth) {
    let sid = series_id;
    if series_id.starts_with("http") {
        sid = extract_series_id(series_id);
    } else if series_id.starts_with("/series/") {
        sid = series_id.replace("/series/", "");
    }

    let data = ();
    try {
        data = api_get(`/series/${sid}`);
    } catch {
        return [];
    }

    if data == () {
        return [];
    }

    let books = data["series_books"];
    if books == () || type_of(books) != "array" {
        return [];
    }

    let chapters = [];

    for book in books {
        let book_id = book["book_id"];
        if book_id == () || book_id == "" {
            continue;
        }

        let ch_num = "0";
        let raw_num = book["chapter_no"];
        if raw_num != () && raw_num != "" {
            ch_num = `${raw_num}`;
        } else {
            let sort = book["sort_no"];
            if sort != () {
                ch_num = `${sort}`;
            }
        }

        let title = "";
        let raw_title = book["title"];
        if raw_title != () && raw_title != "" {
            title = raw_title;
        } else {
            title = `Chapter ${ch_num}`;
        }

        let volume = ();
        let vol = book["volume_no"];
        if vol != () && vol != "" {
            volume = `${vol}`;
        }

        let page_count = ();
        let pc = book["page_count"];
        if pc != () {
            page_count = pc;
        }

        let scanlator = ();
        let groups = book["groups"];
        if groups != () && type_of(groups) == "array" && groups.len() > 0 {
            let group_name = groups[0]["title"];
            if group_name != () && group_name != "" {
                scanlator = group_name;
            }
        }

        let published_at = ();
        let created = book["created_at"];
        if created != () && created != "" {
            published_at = created;
        }

        let reader_url = `${BASE_URL}/series/${sid}/reader/${book_id}`;

        chapters.push(#{
            id: `${sid}/${book_id}`,
            series_id: sid,
            number: ch_num,
            title: title,
            volume: volume,
            language: "en",
            scanlator: scanlator,
            url: reader_url,
            published_at: published_at,
            page_count: page_count,
            extra: #{ book_id: book_id }
        });
    }

    chapters
}

/// Get page URLs for a chapter.
/// Uses browser with Widevine DRM to trigger the token exchange flow,
/// then extracts CDN image URLs from the performance resource log.
/// Requires: browserless Chrome with Widevine CDM + FlareSolverr for CF bypass.
fn get_chapter_pages(chapter_id, auth) {
    // Parse "{series_id}/{book_id}"
    let parts = chapter_id.split("/");
    if parts.len() < 2 { return []; }
    let series_id = parts[0];
    let book_id = parts[1];

    // Use the puppeteer-based extraction service running in the browser container.
    // Direct headless_chrome CDP automation doesn't work because Cloudflare Rocket Loader
    // intercepts and blocks script execution, preventing Next.js from hydrating and
    // the Widevine DRM flow from starting. Puppeteer (running locally in the browser
    // container) handles this correctly.
    let reader_url = `${BASE_URL}/series/${series_id}/reader/${book_id}`;
    let extract_url = "http://tsubaki-browser:3001/extract-pages";

    let body = `{"reader_url":"${reader_url}","book_id":"${book_id}"}`;
    let response = http_post(extract_url, body);

    if response == "" || response == "()" {
        throw "Empty response from page extraction service";
    }

    let result = json_parse(response);

    if result == () || type_of(result) != "map" {
        throw `Invalid response from extraction service: ${response}`;
    }

    // Check for errors
    if result.contains("error") {
        throw `Extraction service error: ${result.error}`;
    }

    let urls = result.urls;
    if urls == () || type_of(urls) != "array" || urls.len() == 0 {
        throw "No CDN URLs returned from extraction service";
    }

    // Build page list
    let pages = [];
    let i = 0;
    for url in urls {
        pages.push(#{
            url: url,
            index: i
        });
        i += 1;
    }

    pages
}
