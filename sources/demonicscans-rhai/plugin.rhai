// DemonicScans Scraper Add-on (Rhai)
// Madara-based site scraper

const BASE_URL = "https://demonicscans.org";

fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "text/html,application/xhtml+xml",
        "Referer": BASE_URL
    }
}

/// Recognise the three CF-challenge HTML shapes we've seen on demonicscans.
fn is_cloudflare_page(html) {
    if html == () || html == "" { return true; }
    if html.contains("Just a moment") && html.contains("_cf_chl_opt") { return true; }
    if html.contains("challenge-platform") && html.contains("Enable JavaScript") { return true; }
    if html.contains("Attention Required") && html.contains("Cloudflare") { return true; }
    false
}

/// Three-tier fetch: cheap plain HTTP → FlareSolverr → browser. Every tier is
/// wrapped so an exception or a CF-challenge response falls through cleanly
/// rather than aborting the whole call. Previous version only checked for
/// "Just a moment" and missed the JS-challenge / "Attention Required" variants
/// CF serves on this domain.
fn fetch_html(url) {
    // Tier 1: plain HTTP — works on quieter CF days
    let http_html = "";
    try {
        http_html = http_get_with_headers(url, get_headers());
        if http_html != "" && !is_cloudflare_page(http_html) {
            return http_html;
        }
    } catch {}

    // Tier 2: FlareSolverr — medium cost, shared service
    if flaresolverr_is_available() {
        try {
            let fs_html = flaresolverr_get(url, 30000);
            if fs_html != "" && !is_cloudflare_page(fs_html) {
                return fs_html;
            }
        } catch {}
    }

    // Tier 3: full browser — heaviest but most reliable
    if browser_is_available() {
        let browser_id = ();
        try {
            browser_id = browser_launch();
            browser_goto(browser_id, url);
            browser_wait_for_selector(browser_id, ".post-title, .c-tabs-item__content, .reading-content", 15000);
            let result = browser_get_html(browser_id);
            try { browser_close(browser_id); } catch {}
            if result != "" && !is_cloudflare_page(result) {
                return result;
            }
        } catch {
            if browser_id != () { try { browser_close(browser_id); } catch {} }
        }
    }

    // All tiers exhausted — return the original HTTP body so callers can at
    // least see the CF page rather than getting silent empty results.
    http_html
}

fn get_source_info() {
    #{
        id: "demonicscans-rhai",
        name: "DemonicScans",
        base_url: BASE_URL,
        language: "en",
        requires_authentication: false,
        capability_level: "browser_required"
    }
}

fn search_series(query, page, auth) {
    let encoded = url_encode(query);
    let url = `${BASE_URL}/?s=${encoded}&post_type=wp-manga`;

    if page > 1 {
        url = `${BASE_URL}/page/${page}/?s=${encoded}&post_type=wp-manga`;
    }

    let html = fetch_html(url);
    let series = [];

    // Madara theme search results
    let items = html_select(html, ".c-tabs-item__content");
    for item in items {
        let links = html_select(item, ".post-title a");
        if links.len() == 0 { continue; }

        let href = element_attr(links[0], "href");
        let title = element_text(links[0]).trim();

        let cover = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "data-src");
            if cover == () { cover = element_attr(imgs[0], "src"); }
        }

        if title != "" && href != () {
            series.push(#{
                id: href,
                title: title,
                url: href,
                cover_url: cover,
                alternate_titles: [],
                authors: [],
                status: (),
                genres: []
            });
        }
    }

    #{ series: series, has_more: series.len() >= 10, total: series.len() }
}

fn get_series(id_or_url, auth) {
    let url = id_or_url;
    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/manga/${id_or_url}`;
    }

    let html = fetch_html(url);

    let title = "";
    let h1s = html_select(html, ".post-title h1");
    if h1s.len() > 0 {
        title = element_text(h1s[0]).trim();
    }

    let cover = ();
    let cover_imgs = html_select(html, ".summary_image img");
    if cover_imgs.len() > 0 {
        cover = element_attr(cover_imgs[0], "data-src");
        if cover == () { cover = element_attr(cover_imgs[0], "src"); }
    }

    let description = ();
    let desc_els = html_select(html, ".summary__content p");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    let genres = [];
    let genre_links = html_select(html, ".genres-content a");
    for link in genre_links {
        let g = element_text(link).trim();
        if g != "" { genres.push(g); }
    }

    let authors = [];
    let author_links = html_select(html, ".author-content a");
    for link in author_links {
        let a = element_text(link).trim();
        if a != "" && a != "Updating" { authors.push(a); }
    }

    let artists = [];
    let artist_links = html_select(html, ".artist-content a");
    for link in artist_links {
        let a = element_text(link).trim();
        if a != "" && a != "Updating" { artists.push(a); }
    }

    let status = ();
    let status_els = html_select(html, ".post-status .summary-content");
    if status_els.len() > 0 {
        let s = element_text(status_els[0]).trim().to_lower();
        if s.contains("ongoing") { status = "Ongoing"; }
        else if s.contains("completed") { status = "Completed"; }
    }

    #{
        id: url,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover,
        authors: authors,
        artists: artists,
        status: status,
        genres: genres,
        url: url
    }
}

fn get_chapters(series_id, auth) {
    let url = series_id;
    if !series_id.starts_with("http") {
        url = `${BASE_URL}/manga/${series_id}`;
    }

    let html = fetch_html(url);
    let chapters = [];

    let ch_items = html_select(html, ".wp-manga-chapter a");
    let idx = 0;
    for link in ch_items {
        let href = element_attr(link, "href");
        if href == () { continue; }

        let ch_title = element_text(link).trim();

        // regex_find returns the *full match* (not the capture group) and an
        // empty string on no match. Previous version both compared against ()
        // (so the fallback never fired) and stored the literal "chapter 5"
        // string as the number, breaking chapter ordering.
        let ch_num = "";
        let full_match = regex_find("chapter[\\s-]*\\d+(\\.\\d+)?", ch_title.to_lower());
        if full_match != "" {
            // Strip the leading "chapter" + optional whitespace/dash, leaving the digits.
            ch_num = regex_find("\\d+(\\.\\d+)?", full_match);
        }
        if ch_num == "" {
            // Last resort: any number in the title, or fall back to position.
            ch_num = regex_find("\\d+(\\.\\d+)?", ch_title);
        }
        if ch_num == "" {
            ch_num = `${idx + 1}`;
        }

        chapters.push(#{
            id: href,
            series_id: series_id,
            number: ch_num,
            title: ch_title,
            url: href
        });
        idx += 1;
    }

    chapters
}

fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;
    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}${chapter_id}`;
    }

    let html = fetch_html(url);
    let pages = [];
    let idx = 0;

    let imgs = html_select(html, ".reading-content img");
    for img in imgs {
        let src = element_attr(img, "data-src");
        if src == () { src = element_attr(img, "src"); }
        if src == () || src == "" { continue; }

        let clean_src = src.trim();
        if clean_src.contains("logo") || clean_src.contains("icon") { continue; }

        pages.push(#{
            index: idx,
            url: clean_src,
            headers: #{ "Referer": url }
        });
        idx += 1;
    }

    pages
}

/// Get latest updates for browsing
fn get_latest_updates(page, auth) {
    let url = BASE_URL;
    if page > 1 {
        url = `${BASE_URL}/page/${page}/?m_orderby=latest`;
    } else {
        url = `${BASE_URL}/?m_orderby=latest`;
    }

    let html = fetch_html(url);
    let series = [];

    // Madara theme latest updates - try multiple selectors
    let items = html_select(html, ".page-item-detail");
    if items.len() == 0 {
        items = html_select(html, ".c-tabs-item__content");
    }

    for item in items {
        let links = html_select(item, ".post-title a, h3 a, h4 a");
        if links.len() == 0 { continue; }

        let href = element_attr(links[0], "href");
        let title = element_text(links[0]).trim();

        let cover = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "data-src");
            if cover == () { cover = element_attr(imgs[0], "src"); }
        }

        if title != "" && href != () {
            series.push(#{
                id: href,
                title: title,
                url: href,
                cover_url: cover
            });
        }
    }

    let has_more = series.len() >= 10;
    #{ series: series, has_more: has_more }
}

/// Get popular manga
fn get_popular(page, auth) {
    let url = BASE_URL;
    if page > 1 {
        url = `${BASE_URL}/page/${page}/?m_orderby=views`;
    } else {
        url = `${BASE_URL}/?m_orderby=views`;
    }

    let html = fetch_html(url);
    let series = [];

    // Madara theme popular - try multiple selectors
    let items = html_select(html, ".page-item-detail");
    if items.len() == 0 {
        items = html_select(html, ".c-tabs-item__content");
    }

    for item in items {
        let links = html_select(item, ".post-title a, h3 a, h4 a");
        if links.len() == 0 { continue; }

        let href = element_attr(links[0], "href");
        let title = element_text(links[0]).trim();

        let cover = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "data-src");
            if cover == () { cover = element_attr(imgs[0], "src"); }
        }

        if title != "" && href != () {
            series.push(#{
                id: href,
                title: title,
                url: href,
                cover_url: cover
            });
        }
    }

    series
}
