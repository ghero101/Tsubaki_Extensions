// BatCave Scraper Add-on (Rhai)
// Browser-based scraper for batcave.biz (formerly batcave.cc)
// Western comics source featuring Marvel, DC, Image, Dark Horse, and more
//
// URL Patterns:
//   Home: https://batcave.biz/
//   Comics List: /comix/ or /comix/?page={page}
//   Search: /index.php?do=search (POST) or /search/{query}/
//   Comic Page: /{id}-{slug}.html (e.g., /33758-batman-2025.html)
//   Reader: /reader/{comic-id}/{chapter-id} (e.g., /reader/11265/74861)
//
// Available APIs:
//   HTTP (fallback): http_get(url), http_get_with_headers(url, headers), http_post(url, body)
//   Browser: browser_launch(), browser_launch_stealth(), browser_goto(id, url),
//            browser_wait_for_cloudflare(id, timeout), browser_wait_for_selector(id, sel, timeout),
//            browser_get_html(id), browser_close(id), browser_is_available()
//   HTML: html_parse(html), html_select(html, selector), html_select_first(html, selector),
//         element_text(el), element_attr(el, attr)
//   JSON: json_parse(text), json_stringify(obj)
//   Regex: regex_match(pattern, text), regex_find(pattern, text), regex_find_all(pattern, text)
//   Utility: url_encode(text), url_decode(text)

const BASE_URL = "https://batcave.biz";

// ============================================================================
// Helper Functions
// ============================================================================

/// Get headers for HTTP requests (with optional mobile user-agent)
fn get_headers() {
    let use_mobile = if settings.contains("use_mobile_ua") { settings["use_mobile_ua"] } else { true };

    if use_mobile {
        #{
            "User-Agent": "Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": BASE_URL
        }
    } else {
        #{
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": BASE_URL
        }
    }
}

/// Fetch HTML using browser automation (bypasses Cloudflare)
/// Falls back to HTTP if browser not available
fn fetch_html(url) {
    if browser_is_available() {
        let browser_id = browser_launch_stealth();
        browser_goto(browser_id, url);
        browser_wait_for_cloudflare(browser_id, 15000);

        // Wait for content to render
        browser_wait_for_selector(browser_id, "body", 10000);

        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    }

    // Fallback to HTTP (may fail with Cloudflare)
    http_get_with_headers(url, get_headers())
}

/// Extract comic ID from URL
/// URL format: /{id}-{slug}.html or https://batcave.biz/{id}-{slug}.html
fn extract_comic_id(url) {
    // Pattern: /33758-batman-2025.html -> 33758
    let match = regex_find("/(\\d+)-[^/]+\\.html", url);
    if match != "" {
        let num = regex_find("\\d+", match);
        if num != "" {
            return num;
        }
    }

    // Try alternative: just find leading number
    let parts = url.split("/");
    for part in parts {
        if part.ends_with(".html") {
            let clean = part.replace(".html", "");
            let id_part = clean.split("-")[0];
            let num = regex_find("^\\d+$", id_part);
            if num != "" {
                return num;
            }
        }
    }

    url
}

/// Extract slug from comic URL
/// URL format: /{id}-{slug}.html -> {slug}
fn extract_slug(url) {
    let match = regex_find("/\\d+-([^/]+)\\.html", url);
    if match != "" {
        // Remove the leading /ID- and trailing .html
        let clean = match.split("-");
        if clean.len() > 1 {
            // Join everything after the ID
            let slug_parts = [];
            for i in 1..clean.len() {
                slug_parts.push(clean[i]);
            }
            let slug = "";
            for i in 0..slug_parts.len() {
                if i > 0 { slug += "-"; }
                slug += slug_parts[i];
            }
            return slug.replace(".html", "");
        }
    }
    ""
}

/// Build full URL from comic ID and slug
fn build_comic_url(id, slug) {
    if slug != "" {
        `${BASE_URL}/${id}-${slug}.html`
    } else {
        `${BASE_URL}/${id}.html`
    }
}

/// Extract chapter ID from reader URL
/// URL format: /reader/{comic-id}/{chapter-id}
fn extract_chapter_id(url) {
    if url.contains("/reader/") {
        let parts = url.split("/reader/");
        if parts.len() > 1 {
            let path_parts = parts[1].split("/");
            if path_parts.len() >= 2 {
                return path_parts[1].split("?")[0];
            }
        }
    }
    url
}

/// Map status text to standard format
fn map_status(status_text) {
    if status_text == () || status_text == "" { return (); }
    let lower = status_text.to_lower();
    if lower.contains("ongoing") || lower.contains("active") {
        return "Ongoing";
    } else if lower.contains("completed") || lower.contains("complete") || lower.contains("finished") {
        return "Completed";
    } else if lower.contains("hiatus") {
        return "Hiatus";
    } else if lower.contains("cancelled") || lower.contains("canceled") {
        return "Cancelled";
    }
    ()
}

/// Parse issue/chapter number from text
fn parse_chapter_number(text) {
    if text == () || text == "" { return "0"; }

    let lower = text.to_lower();

    // Try "Issue #X" or "#X" pattern
    let issue_match = regex_find("(?:issue|#)\\s*#?(\\d+(?:\\.\\d+)?)", lower);
    if issue_match != "" {
        let num = regex_find("\\d+(?:\\.\\d+)?", issue_match);
        if num != "" {
            return num;
        }
    }

    // Try "Chapter X" pattern
    let ch_match = regex_find("(?:chapter|ch\\.?)\\s*#?(\\d+(?:\\.\\d+)?)", lower);
    if ch_match != "" {
        let num = regex_find("\\d+(?:\\.\\d+)?", ch_match);
        if num != "" {
            return num;
        }
    }

    // Try to find any number
    let any_num = regex_find("\\d+(?:\\.\\d+)?", text);
    if any_num != "" {
        return any_num;
    }

    "0"
}

/// Make URL absolute if relative
fn make_absolute_url(url) {
    if url.starts_with("http") {
        return url;
    }
    if url.starts_with("//") {
        return `https:${url}`;
    }
    if url.starts_with("/") {
        return `${BASE_URL}${url}`;
    }
    `${BASE_URL}/${url}`
}

/// Check if image URL is valid (not placeholder/icon/ad)
fn is_valid_image(url) {
    if url == () || url == "" { return false; }
    let lower = url.to_lower();
    if lower.contains("placeholder") { return false; }
    if lower.contains("loading") { return false; }
    if lower.contains("spinner") { return false; }
    if lower.contains("logo") { return false; }
    if lower.contains("icon") { return false; }
    if lower.contains("avatar") { return false; }
    if lower.contains("banner") { return false; }
    if lower.contains("advertisement") { return false; }
    if lower.contains("/ads/") { return false; }
    true
}

// ============================================================================
// Required Interface Functions
// ============================================================================

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "batcave-rhai",
        name: "BatCave",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    // BatCave uses a search URL pattern: /search/{query}/page/{page}/
    // or query parameter based search
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/?do=search&subaction=search&story=${encoded_query}`;

    if page > 1 {
        url = `${BASE_URL}/?do=search&subaction=search&story=${encoded_query}&search_start=${page}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    // Try multiple selectors for search results
    // BatCave likely uses article or div elements for comic cards
    let items = html_select(doc, "article, div.short-story, div.shortstory, div.movie-item, div.item");

    // Fallback: try links to .html pages
    if items.len() == 0 {
        items = html_select(doc, "div.content a[href$='.html'], div.main a[href$='.html']");
    }

    for item in items {
        // Get the link to comic page
        let links = html_select(item, "a[href$='.html']");
        if links.len() == 0 {
            // Item might be the link itself
            let href = element_attr(item, "href");
            if href != () && href.ends_with(".html") {
                links = [item];
            } else {
                continue;
            }
        }

        let link = links[0];
        let href = element_attr(link, "href");

        if href == () || href == "" {
            continue;
        }

        // Skip non-comic pages
        if href.contains("index.php") || href.contains("register") || href.contains("login") {
            continue;
        }

        let comic_url = make_absolute_url(href);
        let id = extract_comic_id(comic_url);

        // Skip duplicates
        if seen.contains(id) {
            continue;
        }
        seen[id] = true;

        // Get title
        let title = "";
        let title_els = html_select(item, "h2, h3, h4, .title, .name, a.title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        // Fallback: use link text
        if title == "" {
            title = element_text(link).trim();
        }

        // Clean up title (remove extra info like year)
        if title != "" {
            // Keep original title with year info
            title = title.trim();
        }

        if title == "" || title.len() < 2 {
            continue;
        }

        // Get cover image
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-src");
            }
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-original");
            }
            if cover_url != () && cover_url != "" {
                cover_url = make_absolute_url(cover_url);
            }
        }

        // Get description if available
        let description = ();
        let desc_els = html_select(item, ".description, .desc, .story-desc, p");
        if desc_els.len() > 0 {
            description = element_text(desc_els[0]).trim();
            if description.len() < 20 {
                description = ();
            }
        }

        series.push(#{
            id: id,
            title: title,
            url: comic_url,
            cover_url: cover_url,
            alternate_titles: [],
            authors: [],
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: description
        });
    }

    // Check for next page
    let has_more = false;
    let pagination = html_select(doc, "div.navigation a, ul.pagination a, a.next, a.pnext");
    for pager in pagination {
        let href = element_attr(pager, "href");
        let text = element_text(pager).to_lower();
        if text.contains("next") || text.contains(">") || text == ">" {
            has_more = true;
            break;
        }
        // Check for page number links
        if href != () && (href.contains(`search_start=${page + 1}`) || href.contains(`page=${page + 1}`)) {
            has_more = true;
            break;
        }
    }

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let id = id_or_url;

    if !id_or_url.starts_with("http") {
        // ID format might be "12345" or "12345-slug"
        if id_or_url.contains("-") {
            url = `${BASE_URL}/${id_or_url}.html`;
            id = id_or_url.split("-")[0];
        } else {
            // Need to find the full URL - this is a limitation
            url = `${BASE_URL}/${id_or_url}.html`;
        }
    } else {
        id = extract_comic_id(id_or_url);
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    // Extract title
    let title = "";
    let title_els = html_select(doc, "h1, h2.title, .full-title, .movie-title, article h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // Extract cover image
    let cover_url = ();
    let cover_els = html_select(doc, ".full-left img, .movie-img img, .poster img, article img, .short-img img");
    if cover_els.len() > 0 {
        cover_url = element_attr(cover_els[0], "src");
        if cover_url == () || cover_url == "" {
            cover_url = element_attr(cover_els[0], "data-src");
        }
        if cover_url != () && cover_url != "" && is_valid_image(cover_url) {
            cover_url = make_absolute_url(cover_url);
        } else {
            cover_url = ();
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(doc, ".full-text, .full-story, .description, .movie-desc, article p");
    if desc_els.len() > 0 {
        let desc_text = "";
        for el in desc_els {
            let text = element_text(el).trim();
            if text.len() > 50 {
                if desc_text != "" {
                    desc_text += "\n\n";
                }
                desc_text += text;
            }
        }
        if desc_text != "" {
            description = desc_text;
        }
    }

    // Extract genres/categories
    let genres = [];
    let genre_els = html_select(doc, "a[href*='genre'], a[href*='category'], .categories a, .tags a");
    for el in genre_els {
        let genre = element_text(el).trim();
        if genre != "" && !genres.contains(genre) && genre.len() > 1 {
            genres.push(genre);
        }
    }

    // Extract status
    let status = ();
    let info_els = html_select(doc, ".full-info li, .movie-info li, table tr, dl dt, dl dd");
    for el in info_els {
        let text = element_text(el);
        let lower = text.to_lower();
        if lower.contains("status") {
            status = map_status(text);
            break;
        }
    }

    // Extract year
    let year = ();
    // Try from title first (e.g., "Batman (2025-)")
    let year_match = regex_find("\\((19|20)\\d{2}", title);
    if year_match != "" {
        year = regex_find("(19|20)\\d{2}", year_match);
    }
    // Fallback: search in info
    if year == () || year == "" {
        for el in info_els {
            let text = element_text(el);
            if text.to_lower().contains("year") || text.to_lower().contains("released") {
                let y = regex_find("(19|20)\\d{2}", text);
                if y != "" {
                    year = y;
                    break;
                }
            }
        }
    }

    // Extract authors/writers
    let authors = [];
    for el in info_els {
        let text = element_text(el).to_lower();
        if text.contains("writer") || text.contains("author") {
            let links = html_select(el, "a");
            for link in links {
                let author = element_text(link).trim();
                if author != "" && !authors.contains(author) {
                    authors.push(author);
                }
            }
            // If no links, try plain text
            if authors.len() == 0 {
                let full_text = element_text(el);
                // Remove label
                let clean = full_text.replace("Writer:", "").replace("Author:", "").replace("writer:", "").replace("author:", "").trim();
                let parts = clean.split(",");
                for part in parts {
                    let author = part.trim();
                    if author != "" && !authors.contains(author) {
                        authors.push(author);
                    }
                }
            }
        }
    }

    // Extract artists
    let artists = [];
    for el in info_els {
        let text = element_text(el).to_lower();
        if text.contains("artist") || text.contains("illustrator") {
            let links = html_select(el, "a");
            for link in links {
                let artist = element_text(link).trim();
                if artist != "" && !artists.contains(artist) {
                    artists.push(artist);
                }
            }
        }
    }

    // Extract publisher as tag
    let tags = [];
    for el in info_els {
        let text = element_text(el).to_lower();
        if text.contains("publisher") {
            let links = html_select(el, "a");
            for link in links {
                let publisher = element_text(link).trim();
                if publisher != "" && !tags.contains(publisher) {
                    tags.push(publisher);
                }
            }
        }
    }

    #{
        id: id,
        title: title,
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: status,
        genres: genres,
        tags: tags,
        year: year,
        content_rating: (),
        url: url,
        extra: #{}
    }
}

/// Get all chapters/issues for a series
fn get_chapters(series_id, auth) {
    let url = series_id;

    if !series_id.starts_with("http") {
        if series_id.contains("-") {
            url = `${BASE_URL}/${series_id}.html`;
        } else {
            url = `${BASE_URL}/${series_id}.html`;
        }
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    let comic_id = extract_comic_id(url);

    // Look for chapter/issue links
    // BatCave reader format: /reader/{comic-id}/{chapter-id}
    let chapter_links = html_select(doc, "a[href*='/reader/'], ul.chapters a, .chapter-list a, .issues a");

    // Fallback: look for any links with "issue" or "chapter" text
    if chapter_links.len() == 0 {
        chapter_links = html_select(doc, "a");
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Filter for reader links or issue links
        if !href.contains("/reader/") && !href.to_lower().contains("issue") && !href.to_lower().contains("chapter") {
            continue;
        }

        let chapter_url = make_absolute_url(href);

        // Extract chapter ID
        let ch_id = "";
        if href.contains("/reader/") {
            ch_id = extract_chapter_id(chapter_url);
        } else {
            ch_id = href;
        }

        // Skip duplicates
        if seen.contains(ch_id) {
            continue;
        }
        seen[ch_id] = true;

        // Get chapter title/name
        let chapter_title = element_text(link).trim();

        // Parse chapter/issue number
        let number = parse_chapter_number(chapter_title);

        // If number is 0, try extracting from URL
        if number == "0" {
            number = parse_chapter_number(href);
        }

        chapters.push(#{
            id: ch_id,
            series_id: comic_id,
            number: number,
            title: chapter_title,
            volume: (),
            language: "en",
            scanlator: (),
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // If no chapters found via links, the comic might be a single volume
    // Check for direct reader link or page images
    if chapters.len() == 0 {
        // Try to find a "Read" or "View" button
        let read_links = html_select(doc, "a.read-btn, a.read-now, a[href*='/reader/'], .read a");
        for link in read_links {
            let href = element_attr(link, "href");
            if href != () && href != "" {
                let chapter_url = make_absolute_url(href);
                chapters.push(#{
                    id: extract_chapter_id(chapter_url),
                    series_id: comic_id,
                    number: "1",
                    title: "Full Issue",
                    volume: (),
                    language: "en",
                    scanlator: (),
                    url: chapter_url,
                    published_at: (),
                    page_count: (),
                    extra: #{}
                });
                break;
            }
        }
    }

    chapters
}

/// Get page URLs for a chapter/issue
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        // Assume format: comic_id/chapter_id
        if chapter_id.contains("/") {
            url = `${BASE_URL}/reader/${chapter_id}`;
        } else {
            // Can't construct URL without more info
            throw `Invalid chapter ID format: ${chapter_id}`;
        }
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let pages = [];
    let idx = 0;
    let seen_urls = #{};

    // BatCave reader likely shows images in sequence
    // Look for page images
    let page_imgs = html_select(doc, ".reader-content img, .chapter-content img, #reader img, .page img, img.page-image");

    // Fallback: all images in main content area
    if page_imgs.len() == 0 {
        page_imgs = html_select(doc, "main img, article img, .content img, #content img");
    }

    // Fallback: any images that look like comic pages
    if page_imgs.len() == 0 {
        page_imgs = html_select(doc, "img[src*='page'], img[src*='comic'], img[data-src*='page']");
    }

    for img in page_imgs {
        let img_url = element_attr(img, "src");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-src");
        }
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-original");
        }
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-lazy-src");
        }

        if img_url == () || img_url == "" {
            continue;
        }

        // Validate image URL
        if !is_valid_image(img_url) {
            continue;
        }

        img_url = make_absolute_url(img_url);

        // Skip duplicates
        if seen_urls.contains(img_url) {
            continue;
        }
        seen_urls[img_url] = true;

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

    // Try to find embedded JSON with page list (common pattern)
    if pages.len() == 0 {
        let json_match = regex_find("(?:pages|images)\\s*[=:]\\s*(\\[.*?\\])", html);
        if json_match != "" {
            // Extract the array part
            let array_match = regex_find("\\[.*?\\]", json_match);
            if array_match != "" {
                let page_data = json_parse(array_match);
                if page_data != () {
                    for item in page_data {
                        let img_url = "";
                        if item.is_string() {
                            img_url = item;
                        } else if item.contains("url") {
                            img_url = item["url"];
                        } else if item.contains("src") {
                            img_url = item["src"];
                        } else if item.contains("image") {
                            img_url = item["image"];
                        }

                        if img_url != "" && is_valid_image(img_url) {
                            img_url = make_absolute_url(img_url);
                            if !seen_urls.contains(img_url) {
                                seen_urls[img_url] = true;
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
                    }
                }
            }
        }
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = BASE_URL;
    if page > 1 {
        url = `${BASE_URL}/page/${page}/`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    // Latest updates typically on home page
    let items = html_select(doc, "article, .short-story, .shortstory, .item, .movie-item");

    // Fallback
    if items.len() == 0 {
        items = html_select(doc, "div.content a[href$='.html']");
    }

    for item in items {
        let links = html_select(item, "a[href$='.html']");
        if links.len() == 0 {
            let href = element_attr(item, "href");
            if href != () && href.ends_with(".html") {
                links = [item];
            } else {
                continue;
            }
        }

        let link = links[0];
        let href = element_attr(link, "href");

        if href == () || href == "" {
            continue;
        }

        if href.contains("index.php") || href.contains("register") || href.contains("login") {
            continue;
        }

        let comic_url = make_absolute_url(href);
        let id = extract_comic_id(comic_url);

        if seen.contains(id) {
            continue;
        }
        seen[id] = true;

        // Get title
        let title = "";
        let title_els = html_select(item, "h2, h3, h4, .title, .name, a.title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(link).trim();
        }

        if title == "" || title.len() < 2 {
            continue;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-src");
            }
            if cover_url != () && cover_url != "" && is_valid_image(cover_url) {
                cover_url = make_absolute_url(cover_url);
            } else {
                cover_url = ();
            }
        }

        series.push(#{
            id: id,
            title: title,
            url: comic_url,
            cover_url: cover_url,
            updated_at: ()
        });
    }

    // Check for next page
    let has_more = false;
    let pagination = html_select(doc, "div.navigation a, ul.pagination a, a.next, a.pnext");
    for pager in pagination {
        let text = element_text(pager).to_lower();
        let href = element_attr(pager, "href");
        if text.contains("next") || text == ">" {
            has_more = true;
            break;
        }
        if href != () && href.contains(`/page/${page + 1}/`) {
            has_more = true;
            break;
        }
    }

    #{ series: series, has_more: has_more }
}

/// Get popular comics
fn get_popular(page, auth) {
    // Try popular or top-rated page
    let url = `${BASE_URL}/comix/`;
    if page > 1 {
        url = `${BASE_URL}/comix/?page=${page}`;
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let series = [];
    let seen = #{};

    let items = html_select(doc, "article, .short-story, .shortstory, .item, .movie-item");

    if items.len() == 0 {
        items = html_select(doc, "div.content a[href$='.html']");
    }

    for item in items {
        let links = html_select(item, "a[href$='.html']");
        if links.len() == 0 {
            let href = element_attr(item, "href");
            if href != () && href.ends_with(".html") {
                links = [item];
            } else {
                continue;
            }
        }

        let link = links[0];
        let href = element_attr(link, "href");

        if href == () || href == "" {
            continue;
        }

        if href.contains("index.php") || href.contains("register") || href.contains("login") {
            continue;
        }

        let comic_url = make_absolute_url(href);
        let id = extract_comic_id(comic_url);

        if seen.contains(id) {
            continue;
        }
        seen[id] = true;

        // Get title
        let title = "";
        let title_els = html_select(item, "h2, h3, h4, .title, .name, a.title");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }
        if title == "" {
            title = element_text(link).trim();
        }

        if title == "" || title.len() < 2 {
            continue;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(imgs[0], "data-src");
            }
            if cover_url != () && cover_url != "" && is_valid_image(cover_url) {
                cover_url = make_absolute_url(cover_url);
            } else {
                cover_url = ();
            }
        }

        // Get genres if available
        let genres = [];
        let genre_els = html_select(item, ".genre a, .category a, .tags a");
        for el in genre_els {
            let genre = element_text(el).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
            }
        }

        series.push(#{
            id: id,
            title: title,
            url: comic_url,
            cover_url: cover_url,
            genres: genres
        });
    }

    // Check for next page
    let has_more = false;
    let pagination = html_select(doc, "div.navigation a, ul.pagination a, a.next, a.pnext");
    for pager in pagination {
        let text = element_text(pager).to_lower();
        let href = element_attr(pager, "href");
        if text.contains("next") || text == ">" {
            has_more = true;
            break;
        }
        if href != () && href.contains(`page=${page + 1}`) {
            has_more = true;
            break;
        }
    }

    #{ series: series, has_more: has_more }
}
