// HeyToon Scraper Add-on (Rhai)
// Webtoon site scraper

const BASE_URL = "https://heytoon.com";

fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Accept": "text/html,application/xhtml+xml",
        "Referer": BASE_URL
    }
}

fn fetch_html(url) {
    http_get_with_headers(url, get_headers())
}

fn get_source_info() {
    #{
        id: "heytoon-rhai",
        name: "HeyToon",
        base_url: BASE_URL,
        language: "en",
        requires_authentication: false,
        capability_level: "http_only"
    }
}

fn search_series(query, page, auth) {
    let encoded = url_encode(query);
    let url = `${BASE_URL}/search?keyword=${encoded}`;

    if page > 1 {
        url = `${BASE_URL}/search?keyword=${encoded}&page=${page}`;
    }

    let html = fetch_html(url);
    let series = [];

    let items = html_select(html, ".manga-item, .comic-item, .list-item");
    for item in items {
        let links = html_select(item, "a");
        if links.len() == 0 { continue; }

        let href = element_attr(links[0], "href");
        if href == () { continue; }
        if !href.starts_with("http") { href = `${BASE_URL}${href}`; }

        let title = "";
        let title_els = html_select(item, ".title, .name, h3, h4");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        let cover = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "data-src");
            if cover == () { cover = element_attr(imgs[0], "src"); }
        }

        if title != "" {
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

    #{ series: series, has_more: series.len() >= 20, total: series.len() }
}

fn get_series(id_or_url, auth) {
    let url = id_or_url;
    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/webtoon/${id_or_url}`;
    }

    let html = fetch_html(url);

    let title = "";
    let h1s = html_select(html, "h1, .title");
    if h1s.len() > 0 {
        title = element_text(h1s[0]).trim();
    }

    let cover = ();
    let cover_imgs = html_select(html, ".cover img, .thumbnail img");
    if cover_imgs.len() > 0 {
        cover = element_attr(cover_imgs[0], "src");
    }

    let description = ();
    let desc_els = html_select(html, ".description, .summary, .synopsis");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }

    let genres = [];
    let genre_links = html_select(html, ".genres a, .genre a");
    for link in genre_links {
        let g = element_text(link).trim();
        if g != "" { genres.push(g); }
    }

    #{
        id: url,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover,
        authors: [],
        artists: [],
        status: (),
        genres: genres,
        url: url
    }
}

fn get_chapters(series_id, auth) {
    let url = series_id;
    if !series_id.starts_with("http") {
        url = `${BASE_URL}/webtoon/${series_id}`;
    }

    let html = fetch_html(url);
    let chapters = [];

    let ch_links = html_select(html, ".chapter-list a, .chapters a, .episode-list a");
    let idx = 0;
    for link in ch_links {
        let href = element_attr(link, "href");
        if href == () { continue; }
        if !href.starts_with("http") { href = `${BASE_URL}${href}`; }

        let ch_title = element_text(link).trim();
        let ch_num = regex_find("(\\d+\\.?\\d*)", ch_title);
        if ch_num == () { ch_num = `${idx + 1}`; }

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

    let imgs = html_select(html, ".reader-content img, .chapter-images img, #chapter-container img");
    for img in imgs {
        let src = element_attr(img, "data-src");
        if src == () { src = element_attr(img, "src"); }
        if src == () || src == "" { continue; }
        if src.contains("logo") || src.contains("icon") || src.contains("banner") { continue; }

        pages.push(#{
            index: idx,
            url: src,
            headers: #{ "Referer": url }
        });
        idx += 1;
    }

    pages
}

/// Get latest updates for browsing
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/latest`;
    if page > 1 {
        url = `${BASE_URL}/latest?page=${page}`;
    }

    let html = fetch_html(url);
    let series = [];

    // Try common webtoon site selectors for latest updates
    let items = html_select(html, ".manga-item, .comic-item, .list-item, .webtoon-item");
    for item in items {
        let links = html_select(item, "a");
        if links.len() == 0 { continue; }

        let href = element_attr(links[0], "href");
        if href == () { continue; }
        if !href.starts_with("http") { href = `${BASE_URL}${href}`; }

        let title = "";
        let title_els = html_select(item, ".title, .name, h3, h4");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        let cover = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "data-src");
            if cover == () { cover = element_attr(imgs[0], "src"); }
        }

        if title != "" {
            series.push(#{
                id: href,
                title: title,
                url: href,
                cover_url: cover
            });
        }
    }

    let has_more = series.len() >= 20;
    #{ series: series, has_more: has_more }
}

/// Get popular manga
fn get_popular(page, auth) {
    let url = `${BASE_URL}/popular`;
    if page > 1 {
        url = `${BASE_URL}/popular?page=${page}`;
    }

    let html = fetch_html(url);
    let series = [];

    // Try common webtoon site selectors for popular
    let items = html_select(html, ".manga-item, .comic-item, .list-item, .webtoon-item");
    for item in items {
        let links = html_select(item, "a");
        if links.len() == 0 { continue; }

        let href = element_attr(links[0], "href");
        if href == () { continue; }
        if !href.starts_with("http") { href = `${BASE_URL}${href}`; }

        let title = "";
        let title_els = html_select(item, ".title, .name, h3, h4");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        let cover = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "data-src");
            if cover == () { cover = element_attr(imgs[0], "src"); }
        }

        if title != "" {
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
