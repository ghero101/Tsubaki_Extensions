// RoliaScan Scraper Add-on (Rhai)
// Manga scanlation site scraper (HTTP-only, no browser automation required)
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   JSON: json_parse(text)
//   Utility: url_encode(text), regex_match(pattern, text), regex_find(pattern, text)

const BASE_URL = "https://roliascann.com";

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
        id: "roliascan-rhai",
        name: "RoliaScan",
        base_url: BASE_URL,
        language: "en",
        requires_authentication: false,
        capability_level: "http_only"
    }
}

fn search_series(query, page, auth) {
    let encoded = url_encode(query);
    // Use the filter endpoint which supports keyword search
    let url = `${BASE_URL}/filter?keyword=${encoded}`;

    if page > 1 {
        url = `${BASE_URL}/filter?keyword=${encoded}&page=${page}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);
    let series = [];

    // Search for manga links
    let items = html_select(doc, "a[href*='/manga/']");
    let seen = #{};

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" { continue; }
        if seen.contains(href) { continue; }
        if href.contains("/chapter") { continue; }

        seen[href] = true;

        // Get cover image first (we need it to extract alt text for title)
        let cover = ();
        let img_alt = "";
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "src");
            if cover == () || cover == "" {
                cover = element_attr(imgs[0], "data-src");
            }
            // Get alt text as fallback for title
            img_alt = element_attr(imgs[0], "alt");
            if img_alt == () { img_alt = ""; }
        }

        let title = "";
        let title_els = html_select(item, "h3, h4, .title, .tt");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(item).trim();
            if title.len() > 100 { title = ""; }
        }
        if title == "" && img_alt != "" {
            // Extract title from img alt attribute (format: "Title manga cover")
            title = img_alt;
            if title.ends_with(" manga cover") {
                title = title.sub_string(0, title.len() - 12);
            }
            title = title.trim();
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

    #{ series: series, has_more: series.len() >= 10, total: series.len() }
}

fn get_series(id_or_url, auth) {
    let url = id_or_url;
    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/manga/${id_or_url}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Get title from h1
    let title = "";
    let h1s = html_select(doc, "h1");
    if h1s.len() > 0 {
        title = element_text(h1s[0]).trim();
    }

    // Get cover image
    let cover = ();
    let cover_imgs = html_select(doc, "img.poster, img.coverimage, .thumb img");
    if cover_imgs.len() > 0 {
        cover = element_attr(cover_imgs[0], "src");
    }
    if cover == () {
        // Fallback - find first image in the page that looks like a cover
        let all_imgs = html_select(doc, "img");
        for img in all_imgs {
            let src = element_attr(img, "src");
            if src != () && src.contains("cdn2.fandommanga.xyz") {
                cover = src;
                break;
            }
        }
    }

    // Get description
    let description = ();
    let desc_els = html_select(doc, "p");
    for el in desc_els {
        let text = element_text(el).trim();
        if text.len() > 50 && !text.contains("©") && !text.contains("roliascan") {
            description = text;
            break;
        }
    }

    // Get genres from links
    let genres = [];
    let genre_links = html_select(doc, "a[href*='/genre/'], a[href*='/tag/']");
    for link in genre_links {
        let g = element_text(link).trim();
        if g != "" && !genres.contains(g) { genres.push(g); }
    }

    // Get authors
    let authors = [];
    let author_links = html_select(doc, "a[href*='/author/']");
    for link in author_links {
        let a = element_text(link).trim();
        if a != "" && !authors.contains(a) { authors.push(a); }
    }

    // Get status
    let status = ();
    let status_links = html_select(doc, "a[href*='/status/']");
    if status_links.len() > 0 {
        let s = element_text(status_links[0]).trim().to_lower();
        if s.contains("ongoing") { status = "Ongoing"; }
        else if s.contains("completed") { status = "Completed"; }
        else if s.contains("hiatus") { status = "Hiatus"; }
    }

    #{
        id: url,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover,
        authors: authors,
        artists: [],
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
    let doc = html_parse(html);
    let chapters = [];

    // Find chapter links
    let ch_links = html_select(doc, "a[href*='/chapter']");
    let seen = #{};
    let idx = 0;

    for link in ch_links {
        let href = element_attr(link, "href");
        if href == () || href == "" { continue; }
        if seen.contains(href) { continue; }

        seen[href] = true;

        let ch_title = element_text(link).trim();
        if ch_title == "" { continue; }

        // Extract chapter number
        let ch_num = `${idx + 1}`;
        let num_match = regex_find("(?i)chapter[\\s.-]*(\\d+\\.?\\d*)", ch_title);
        if num_match != () && num_match != "" {
            ch_num = num_match;
        } else {
            let num_match2 = regex_find("(\\d+\\.?\\d*)", ch_title);
            if num_match2 != () && num_match2 != "" {
                ch_num = num_match2;
            }
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
    let doc = html_parse(html);
    let pages = [];
    let idx = 0;

    // Find all images that are manga pages
    let imgs = html_select(doc, "img");
    for img in imgs {
        let src = element_attr(img, "src");
        if src == () || src == "" {
            src = element_attr(img, "data-src");
        }
        if src == () || src == "" { continue; }

        // Skip non-manga images
        let src_lower = src.to_lower();
        if src_lower.contains("logo") || src_lower.contains("icon") || src_lower.contains("avatar") {
            continue;
        }

        // Only include CDN images (actual manga pages)
        if src.contains("cdn2.fandommanga.xyz") || src.contains("/chapters/") || src.contains("/manga/") {
            pages.push(#{
                index: idx,
                url: src,
                headers: #{ "Referer": url }
            });
            idx += 1;
        }
    }

    pages
}

/// Get latest updates for browsing
fn get_latest_updates(page, auth) {
    // RoliaScan uses /manga?page=X for pagination (up to 30 pages)
    let url = `${BASE_URL}/manga`;
    if page > 1 {
        url = `${BASE_URL}/manga?page=${page}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);
    let series = [];

    // RoliaScan uses simple a > img + h3/h4 structure
    let items = html_select(doc, "a[href*='/manga/']");
    let seen = #{};

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" { continue; }

        // Skip duplicates and non-series links
        if seen.contains(href) { continue; }
        if !href.contains("/manga/") { continue; }
        // Skip chapter links
        if href.contains("/chapter") { continue; }
        if href.contains("/read/") { continue; }

        seen[href] = true;

        // Get cover image first (we need it to extract alt text for title)
        let cover = ();
        let img_alt = "";
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "src");
            if cover == () || cover == "" {
                cover = element_attr(imgs[0], "data-src");
            }
            // Get alt text as fallback for title
            img_alt = element_attr(imgs[0], "alt");
            if img_alt == () { img_alt = ""; }
        }

        // Get title from h3, h4, .title, or text content
        let title = "";
        let title_els = html_select(item, "h3, h4, .title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            // Try getting text after the image
            title = element_text(item).trim();
            // Clean up - remove extra whitespace
            if title.len() > 100 {
                title = "";
            }
        }
        if title == "" && img_alt != "" {
            // Extract title from img alt attribute (format: "Title manga cover")
            title = img_alt;
            if title.ends_with(" manga cover") {
                title = title.sub_string(0, title.len() - 12);
            }
            title = title.trim();
        }

        if title != "" && cover != () {
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

    // RoliaScan has up to 30 pages of manga
    let has_more = page < 30 && series.len() > 0;
    #{ series: series, has_more: has_more }
}

/// Get popular manga (uses manga listing with pagination)
fn get_popular(page, auth) {
    // RoliaScan uses /manga?page=X for pagination
    let url = `${BASE_URL}/manga`;
    if page > 1 {
        url = `${BASE_URL}/manga?page=${page}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);
    let series = [];

    let items = html_select(doc, "a[href*='/manga/']");
    let seen = #{};

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" { continue; }
        if seen.contains(href) { continue; }
        if href.contains("/chapter") { continue; }
        if href.contains("/read/") { continue; }

        seen[href] = true;

        // Get cover image first (we need it to extract alt text for title)
        let cover = ();
        let img_alt = "";
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "src");
            if cover == () || cover == "" {
                cover = element_attr(imgs[0], "data-src");
            }
            // Get alt text as fallback for title
            img_alt = element_attr(imgs[0], "alt");
            if img_alt == () { img_alt = ""; }
        }

        let title = "";
        let title_els = html_select(item, "h3, h4, .title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(item).trim();
            if title.len() > 100 { title = ""; }
        }
        if title == "" && img_alt != "" {
            // Extract title from img alt attribute (format: "Title manga cover")
            title = img_alt;
            if title.ends_with(" manga cover") {
                title = title.sub_string(0, title.len() - 12);
            }
            title = title.trim();
        }

        if title != "" && cover != () {
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

    series
}
