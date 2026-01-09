// VioletScans Scraper Add-on (Rhai)
// Custom MangaReader WordPress theme (NOT Madara)
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   JSON: json_parse(text)
//   Utility: url_encode(text), regex_match(pattern, text), regex_find(pattern, text)

const BASE_URL = "https://violetscans.org";

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
        id: "violetscans-rhai",
        name: "VioletScans",
        base_url: BASE_URL,
        language: "en",
        requires_authentication: false,
        capability_level: "http_only"
    }
}

fn search_series(query, page, auth) {
    let encoded = url_encode(query);
    let url = `${BASE_URL}/?s=${encoded}`;

    if page > 1 {
        url = `${BASE_URL}/page/${page}/?s=${encoded}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);
    let series = [];
    let seen = #{};

    // VioletScans search results use anchor tags with h2 titles
    let items = html_select(doc, "a[href*='/comics/']");

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" { continue; }

        // Skip chapter links and duplicates
        if href.contains("/chapter") { continue; }
        if seen.contains(href) { continue; }
        seen[href] = true;

        // Get title from h2 inside the anchor
        let title = "";
        let h2_els = html_select(item, "h2");
        if h2_els.len() > 0 {
            title = element_text(h2_els[0]).trim();
        }
        if title == "" {
            let h3_els = html_select(item, "h3");
            if h3_els.len() > 0 {
                title = element_text(h3_els[0]).trim();
            }
        }
        if title == "" {
            let tt_els = html_select(item, ".tt");
            if tt_els.len() > 0 {
                title = element_text(tt_els[0]).trim();
            }
        }

        // Get cover from img.ts-post-image or any img
        let cover = ();
        let imgs = html_select(item, "img.ts-post-image");
        if imgs.len() == 0 {
            imgs = html_select(item, "img");
        }
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "src");
            if cover == () || cover == "" {
                cover = element_attr(imgs[0], "data-src");
            }
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
        url = `${BASE_URL}/comics/${id_or_url}/`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Get title from h1 or .entry-title
    let title = "";
    let h1s = html_select(doc, "h1.entry-title");
    if h1s.len() > 0 {
        title = element_text(h1s[0]).trim();
    }
    if title == "" {
        let h1_all = html_select(doc, "h1");
        if h1_all.len() > 0 {
            title = element_text(h1_all[0]).trim();
        }
    }

    // Get cover from .thumb img or .summary_image img
    let cover = ();
    let cover_imgs = html_select(doc, ".thumb img");
    if cover_imgs.len() > 0 {
        cover = element_attr(cover_imgs[0], "src");
    }
    if cover == () {
        let sum_imgs = html_select(doc, ".summary_image img");
        if sum_imgs.len() > 0 {
            cover = element_attr(sum_imgs[0], "src");
            if cover == () {
                cover = element_attr(sum_imgs[0], "data-src");
            }
        }
    }

    // Get description from .entry-content p or .summary__content p
    let description = ();
    let desc_els = html_select(doc, ".entry-content p");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }
    if description == () || description == "" {
        let sum_els = html_select(doc, ".summary__content p");
        if sum_els.len() > 0 {
            description = element_text(sum_els[0]).trim();
        }
    }

    // Get genres
    let genres = [];
    let genre_links = html_select(doc, ".mgen a");
    if genre_links.len() == 0 {
        genre_links = html_select(doc, ".genres-content a");
    }
    for link in genre_links {
        let g = element_text(link).trim();
        if g != "" { genres.push(g); }
    }

    // Get authors
    let authors = [];
    let author_links = html_select(doc, ".author-content a");
    if author_links.len() == 0 {
        author_links = html_select(doc, ".fmed a[href*='author']");
    }
    for link in author_links {
        let a = element_text(link).trim();
        if a != "" { authors.push(a); }
    }

    // Get status
    let status = ();
    let status_els = html_select(doc, ".imptdt i");
    if status_els.len() > 0 {
        let s = element_text(status_els[0]).trim().to_lower();
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
        url = `${BASE_URL}/comics/${series_id}/`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);
    let chapters = [];
    let seen = #{};

    // VioletScans MangaReader theme - chapters are in .bixbox.epcheck container
    // Structure: <a href="...chapter..."><div class="chbox">...</div></a>
    // The anchor wraps the chbox, so we need to select anchors containing "chapter" in href
    let ch_links = html_select(doc, ".bixbox a[href*='chapter']");
    if ch_links.len() == 0 {
        // Fallback: try all chapter links in the page
        ch_links = html_select(doc, "a[href*='-chapter-']");
    }

    let idx = 0;
    for link in ch_links {
        let href = element_attr(link, "href");
        if href == () || href == "" { continue; }

        // Skip duplicates
        if seen.contains(href) { continue; }
        seen[href] = true;

        // Get chapter title from .chapternum span or link text
        let ch_title = "";
        let ch_spans = html_select(link, ".chapternum");
        if ch_spans.len() > 0 {
            ch_title = element_text(ch_spans[0]).trim();
        }
        if ch_title == "" {
            ch_title = element_text(link).trim();
        }

        // Extract chapter number from URL (format: series-name-chapter-108)
        // Note: regex_find returns the full match, so we extract just the number
        let ch_num = `${idx + 1}`;
        let num_match = regex_find("chapter-(\\d+\\.?\\d*)", href);
        if num_match != () && num_match != "" {
            // Extract just the number part after "chapter-"
            let parts = num_match.split("-");
            if parts.len() >= 2 {
                ch_num = parts[1];
            }
        }
        if ch_num == `${idx + 1}` {
            // Fallback: Try extracting number directly from URL
            let direct_num = regex_find("-(\\d+)/?$", href);
            if direct_num != () && direct_num != "" {
                // Remove leading dash
                ch_num = direct_num.replace("-", "").replace("/", "");
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
    let pages = [];
    let idx = 0;

    // VioletScans uses ts_reader.run() JavaScript to load images
    // Extract image URLs directly using regex to find the images array
    // Pattern: "images":["url1","url2",...]
    let images_match = regex_find("\"images\":\\[([^\\]]+)\\]", html);
    if images_match != () && images_match != "" {
        // Extract URLs from the matched string
        // The match is like: "images":["url1","url2"...]
        // Find all URLs that look like chapter images
        let url_pattern = "https:\\\\/\\\\/[^\"]+\\.webp|https:\\\\/\\\\/[^\"]+\\.jpg|https:\\\\/\\\\/[^\"]+\\.png|https:\\\\/\\\\/[^\"]+\\.jpeg";
        let all_urls = regex_find_all(url_pattern, images_match);
        if all_urls != () && all_urls.len() > 0 {
            for img_url in all_urls {
                // Clean up escaped URLs
                let clean_url = img_url.replace("\\/", "/");
                pages.push(#{
                    index: idx,
                    url: clean_url,
                    headers: #{ "Referer": url }
                });
                idx += 1;
            }
        }
    }

    // Fallback: try traditional image selectors if ts_reader not found
    if pages.len() == 0 {
        let doc = html_parse(html);
        let imgs = html_select(doc, "#readerarea img");
        if imgs.len() == 0 {
            imgs = html_select(doc, ".reading-content img");
        }
        if imgs.len() == 0 {
            imgs = html_select(doc, ".page-break img");
        }

        for img in imgs {
            let src = element_attr(img, "src");
            if src == () || src == "" {
                src = element_attr(img, "data-src");
            }
            if src == () || src == "" { continue; }

            // Skip logos and icons
            let src_lower = src.to_lower();
            if src_lower.contains("logo") || src_lower.contains("icon") || src_lower.contains("avatar") {
                continue;
            }

            pages.push(#{
                index: idx,
                url: src.trim(),
                headers: #{ "Referer": url }
            });
            idx += 1;
        }
    }

    pages
}

/// Get latest updates for browsing
fn get_latest_updates(page, auth) {
    // VioletScans uses /comics for manga listing
    let url = `${BASE_URL}/comics/`;
    if page > 1 {
        url = `${BASE_URL}/comics/page/${page}/`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);
    let series = [];
    let seen = #{};

    // VioletScans uses anchor tags with h2 for title and img.ts-post-image for covers
    let items = html_select(doc, "a[href*='/comics/']");

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" { continue; }

        // Skip chapter links and duplicates
        if href.contains("/chapter") { continue; }
        if seen.contains(href) { continue; }
        seen[href] = true;

        // Get title from h2 inside the anchor
        let title = "";
        let h2_els = html_select(item, "h2");
        if h2_els.len() > 0 {
            title = element_text(h2_els[0]).trim();
        }
        if title == "" {
            let h3_els = html_select(item, "h3");
            if h3_els.len() > 0 {
                title = element_text(h3_els[0]).trim();
            }
        }
        if title == "" {
            let tt_els = html_select(item, ".tt");
            if tt_els.len() > 0 {
                title = element_text(tt_els[0]).trim();
            }
        }

        // Get cover from img.ts-post-image or any img
        let cover = ();
        let imgs = html_select(item, "img.ts-post-image");
        if imgs.len() == 0 {
            imgs = html_select(item, "img");
        }
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "src");
            if cover == () || cover == "" {
                cover = element_attr(imgs[0], "data-src");
            }
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

    #{ series: series, has_more: series.len() >= 10 }
}

/// Get popular manga
fn get_popular(page, auth) {
    // VioletScans doesn't have separate popular view, use main listing
    let url = `${BASE_URL}/comics/`;
    if page > 1 {
        url = `${BASE_URL}/comics/page/${page}/`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);
    let series = [];
    let seen = #{};

    // VioletScans uses anchor tags with h2 for title
    let items = html_select(doc, "a[href*='/comics/']");

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" { continue; }

        // Skip chapter links and duplicates
        if href.contains("/chapter") { continue; }
        if seen.contains(href) { continue; }
        seen[href] = true;

        let title = "";
        let h2_els = html_select(item, "h2");
        if h2_els.len() > 0 {
            title = element_text(h2_els[0]).trim();
        }
        if title == "" {
            let h3_els = html_select(item, "h3");
            if h3_els.len() > 0 {
                title = element_text(h3_els[0]).trim();
            }
        }

        let cover = ();
        let imgs = html_select(item, "img.ts-post-image");
        if imgs.len() == 0 {
            imgs = html_select(item, "img");
        }
        if imgs.len() > 0 {
            cover = element_attr(imgs[0], "src");
            if cover == () || cover == "" {
                cover = element_attr(imgs[0], "data-src");
            }
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

    series
}
