// Webtoon Scraper Add-on (Rhai)
// Official Webtoon platform scraper (webtoons.com)
// Uses HTML parsing and API endpoints
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   html_select(html, selector) -> array
//   element_text(element) -> string
//   element_attr(element, name) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const BASE_URL = "https://www.webtoons.com";
const MOBILE_URL = "https://m.webtoons.com";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "webtoon-rhai",
        name: "Webtoon",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en", "es", "fr", "de", "id", "th", "zh-hant"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Get headers for requests
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Referer": BASE_URL,
        "Accept-Language": "en-US,en;q=0.9"
    }
}

/// Get mobile headers (sometimes returns cleaner data)
fn get_mobile_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Referer": MOBILE_URL
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/en/search?keyword=${encoded_query}&page=${page}`;

    let html = http_get_with_headers(url, get_headers());

    // Check if we got blocked/redirected (more specific patterns to avoid false positives)
    if html.contains("Access Denied") || html.contains("challenge-running") || html.contains("cf-chl-widget") {
        return #{
            series: [],
            has_more: false,
            total: (),
            error: "Access blocked or captcha required"
        };
    }

    let series = [];
    let seen_ids = #{};

    // Find all card items with data-title-no attribute
    let cards = html_select(html, "a._card_item[data-title-no]");

    for card in cards {
        let title_no = element_attr(card, "data-title-no");
        if title_no == () || title_no == "" {
            continue;
        }

        // Skip duplicates
        if seen_ids[title_no] != () {
            continue;
        }
        seen_ids[title_no] = true;

        // Get URL - need the full URL with genre/slug for get_series to work
        let href = element_attr(card, "href");
        let series_url = "";
        if href != () && href != "" {
            series_url = make_full_url(href);
        }
        if series_url == "" {
            series_url = `${BASE_URL}/en/originals/series?title_no=${title_no}`;
        }

        // Get title from .title element
        let title = `Webtoon #${title_no}`;
        let title_els = html_select(card, "strong.title, .title");
        if title_els.len() > 0 {
            let t = element_text(title_els[0]);
            if t != () && t != "" {
                title = t.trim();
            }
        }

        // Get author
        let authors = [];
        let author_els = html_select(card, ".author");
        if author_els.len() > 0 {
            let a = element_text(author_els[0]);
            if a != () && a != "" {
                authors.push(a.trim());
            }
        }

        // Get cover image
        let cover_url = ();
        let img_els = html_select(card, "img");
        if img_els.len() > 0 {
            let src = element_attr(img_els[0], "src");
            if src != () && src != "" {
                cover_url = src;
            }
        }

        // Use full URL as ID - this is required for Webtoon since get_series needs the path
        let series_id = if series_url.contains("webtoons.com") { series_url } else { title_no };

        series.push(#{
            id: series_id,
            title: title,
            url: series_url,
            cover_url: cover_url,
            alternate_titles: [],
            authors: authors,
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: ()
        });
    }

    // Check for next page
    let has_more = html.contains("pg_next") || html.contains("page-next");

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let title_no = "";
    let url = "";

    // Check if we received a URL (our new ID format) or just a numeric ID
    if id_or_url.contains("webtoons.com") {
        // We have a full URL - use it directly
        url = id_or_url;
        title_no = extract_title_no(id_or_url);
    } else {
        // Just a numeric ID - need to search for the proper URL
        title_no = id_or_url;

        // Search the originals page to find the series URL
        let originals_url = `${BASE_URL}/en/originals`;
        let search_html = http_get_with_headers(originals_url, get_headers());

        // Find the card with matching data-title-no
        let cards = html_select(search_html, `a[data-title-no="${title_no}"]`);
        if cards.len() > 0 {
            let href = element_attr(cards[0], "href");
            if href != () && href != "" {
                url = make_full_url(href);
            }
        }

        // If not found in originals, try search
        if url == "" {
            let search_page = `${BASE_URL}/en/search?keyword=${title_no}&page=1`;
            let search_html2 = http_get_with_headers(search_page, get_headers());
            let cards2 = html_select(search_html2, `a._card_item[data-title-no="${title_no}"]`);
            if cards2.len() > 0 {
                let href = element_attr(cards2[0], "href");
                if href != () && href != "" {
                    url = make_full_url(href);
                }
            }
        }

        // Last resort fallback
        if url == "" {
            url = `${BASE_URL}/en/originals/series?title_no=${title_no}`;
        }
    }

    let html = http_get_with_headers(url, get_headers());

    // Extract title
    let title = "";
    let title_els = html_select(html, "h1.subj, h3.subj, .detail_header .subj");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }

    // If no title found, try og:title meta
    if title == "" {
        let meta_els = html_select(html, "meta[property='og:title']");
        if meta_els.len() > 0 {
            title = element_attr(meta_els[0], "content");
            if title != () {
                title = title.trim();
            }
        }
    }

    // Extract cover
    let cover_url = ();
    let cover_els = html_select(html, ".detail_body .thmb img, .detail_header img, meta[property='og:image']");
    for el in cover_els {
        let src = element_attr(el, "src");
        if src == () {
            src = element_attr(el, "content");
        }
        if src != () && src != "" {
            cover_url = src;
            break;
        }
    }

    // Extract description
    let description = ();
    let desc_els = html_select(html, "p.summary, .detail_body .summary, meta[property='og:description']");
    for el in desc_els {
        let text = element_text(el);
        if text == () || text == "" {
            text = element_attr(el, "content");
        }
        if text != () && text != "" {
            description = text.trim();
            break;
        }
    }

    // Extract author
    let authors = [];
    let author_els = html_select(html, "a.author, .info .author_area a, .detail_header .author");
    for el in author_els {
        let author = element_text(el).trim();
        if author != "" && !authors.contains(author) {
            authors.push(author);
        }
    }

    // Extract genre
    let genres = [];
    let genre_els = html_select(html, "h2.genre, .info .genre, .detail_header .genre");
    for el in genre_els {
        let genre = element_text(el).trim();
        if genre != "" && !genres.contains(genre) {
            genres.push(genre);
        }
    }

    // Determine status
    let status = "Ongoing";
    let html_lower = html.to_lower();
    if html_lower.contains("completed") || html_lower.contains("complete") {
        status = "Completed";
    }

    #{
        id: title_no,
        title: if title != () && title != "" { title } else { `Webtoon #${title_no}` },
        alternate_titles: [],
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: [],
        status: status,
        genres: genres,
        tags: ["webtoon"],
        year: (),
        content_rating: "safe",
        url: url,
        extra: #{
            title_no: title_no
        }
    }
}

/// Get all chapters (episodes) for a series
fn get_chapters(series_id, auth) {
    let title_no = "";
    let base_list_url = "";

    // Check if we received a URL or just a numeric ID
    if series_id.contains("webtoons.com") {
        title_no = extract_title_no(series_id);
        // Build the list URL from the provided URL
        // URLs look like: https://www.webtoons.com/en/action/teenage-mercenary/list?title_no=2677
        if series_id.contains("/list") {
            // Already a list URL, extract base
            base_list_url = series_id.split("?")[0];
        } else {
            // Not a list URL, but same pattern - just append /list if needed
            // Or use as-is
            let url_base = series_id.split("?")[0];
            if url_base.ends_with("/list") {
                base_list_url = url_base;
            } else {
                // Need to add /list - check if URL has trailing slug
                // e.g., /en/action/teenage-mercenary -> /en/action/teenage-mercenary/list
                base_list_url = url_base + "/list";
            }
        }
    } else {
        // Just a numeric ID - need to find the proper URL first
        title_no = series_id;

        // Try originals page first
        let originals_url = `${BASE_URL}/en/originals`;
        let search_html = http_get_with_headers(originals_url, get_headers());
        let cards = html_select(search_html, `a[data-title-no="${title_no}"]`);
        if cards.len() > 0 {
            let href = element_attr(cards[0], "href");
            if href != () && href != "" {
                let full_url = make_full_url(href);
                let url_base = full_url.split("?")[0];
                if url_base.ends_with("/list") {
                    base_list_url = url_base;
                } else {
                    base_list_url = url_base + "/list";
                }
            }
        }
    }

    let chapters = [];
    let page = 1;

    loop {
        // Build episode list URL
        let url = "";
        if base_list_url != "" {
            url = `${base_list_url}?title_no=${title_no}&page=${page}`;
        } else {
            // Fallback - unlikely to work but try anyway
            url = `${BASE_URL}/en/originals/series/list?title_no=${title_no}&page=${page}`;
        }

        let html = http_get_with_headers(url, get_headers());

        // Find episode items
        let episode_items = html_select(html, "#_listUl li a, ul._episodeList li a, .episode_lst li a");

        if episode_items.len() == 0 {
            break;
        }

        for item in episode_items {
            let href = element_attr(item, "href");
            if href == () || href == "" {
                continue;
            }

            // Extract episode number
            let episode_no = extract_episode_no(href);
            if episode_no == "" {
                continue;
            }

            // Get episode title
            let title = ();
            let title_els = html_select(item, ".subj span, .episode_title, .sub_title");
            if title_els.len() > 0 {
                title = element_text(title_els[0]).trim();
            }

            // Get episode number display
            let ep_num = "";
            let num_els = html_select(item, ".tx, .num, .episode_num");
            if num_els.len() > 0 {
                ep_num = element_text(num_els[0]).trim();
                // Extract just the number
                ep_num = extract_number_from_text(ep_num);
            }

            if ep_num == "" {
                ep_num = episode_no;
            }

            // Get date
            let date = ();
            let date_els = html_select(item, ".date, .update_date");
            if date_els.len() > 0 {
                date = element_text(date_els[0]).trim();
            }

            // Get thumbnail
            let thumb = ();
            let thumb_els = html_select(item, "img");
            if thumb_els.len() > 0 {
                thumb = element_attr(thumb_els[0], "src");
                if thumb == () {
                    thumb = element_attr(thumb_els[0], "data-src");
                }
            }

            // Use full viewer URL as chapter ID - Webtoon requires the path with slug
            let chapter_url = make_full_url(href);

            chapters.push(#{
                id: chapter_url,
                series_id: title_no,
                number: ep_num,
                title: title,
                volume: (),
                language: "en",
                scanlator: "Webtoon",
                url: chapter_url,
                published_at: date,
                page_count: (),
                extra: #{
                    episode_no: episode_no,
                    thumbnail: thumb
                }
            });
        }

        // Check for next page
        let next_links = html_select(html, "a.pg_next:not(.disabled), .paginate a.on + a");
        if next_links.len() == 0 {
            break;
        }

        page += 1;

        // Safety limit - prevent runaway loops
        if page > 20 {
            break;
        }

        // Also limit total chapters to prevent Rhai operation limit
        if chapters.len() > 500 {
            break;
        }
    }

    // Webtoon shows newest first, reverse for chronological order
    chapters.reverse();

    chapters
}

/// Get page URLs for an episode
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    // Chapter ID should now be the full viewer URL
    // Handle legacy composite ID format just in case
    if chapter_id.contains("_") && !chapter_id.contains("webtoons.com") && !chapter_id.contains("/") {
        let parts = chapter_id.split("_");
        if parts.len() >= 2 {
            let title_no = parts[0];
            let episode_no = parts[1];
            // This fallback URL likely won't work without the proper path
            url = `${BASE_URL}/en/originals/viewer?title_no=${title_no}&episode_no=${episode_no}`;
        }
    }

    // Make sure URL is absolute
    url = make_full_url(url);

    let html = http_get_with_headers(url, get_headers());

    let pages = [];
    let idx = 0;

    // Find all content images
    let img_container = html_select(html, "#_imageList img, .viewer_lst img, #content img._images");

    for img in img_container {
        let img_url = element_attr(img, "data-url");
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "src");
        }
        if img_url == () || img_url == "" {
            img_url = element_attr(img, "data-src");
        }

        if img_url != () && img_url != "" && img_url.contains("http") {
            // Skip thumbnails, icons, etc.
            if img_url.contains("thumb") || img_url.contains("icon") || img_url.contains("banner") {
                continue;
            }

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
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    // Webtoon updates are on the main originals page
    let url = `${BASE_URL}/en/originals`;

    let html = http_get_with_headers(url, get_headers());

    let series = [];
    let seen_ids = #{};

    // Get originals title cards - use the same selector pattern as search
    let cards = html_select(html, "a._originals_title_a[data-title-no], a._card_item[data-title-no]");

    for card in cards {
        let title_no = element_attr(card, "data-title-no");
        if title_no == () || title_no == "" {
            continue;
        }

        // Skip duplicates
        if seen_ids[title_no] != () {
            continue;
        }
        seen_ids[title_no] = true;

        let href = element_attr(card, "href");

        // Make full URL - this is critical for get_series/get_chapters to work
        let full_url = "";
        if href != () && href != "" {
            full_url = make_full_url(href);
        }

        // Get title
        let title = "";
        let title_els = html_select(card, "strong.title, p.subj, .info .subj");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        if title == "" {
            title = `Webtoon #${title_no}`;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(card, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }

        // Get genre
        let genres = [];
        let genre_els = html_select(card, "div.genre, .genre");
        if genre_els.len() > 0 {
            let genre = element_text(genre_els[0]).trim();
            if genre != "" {
                genres.push(genre);
            }
        }

        // Extract genre from URL path (e.g., /en/action/teenage-mercenary/)
        if genres.len() == 0 && href != () {
            let url_parts = href.split("/");
            for i in 0..url_parts.len() {
                if url_parts[i] == "en" && i + 1 < url_parts.len() {
                    let genre_slug = url_parts[i + 1];
                    // Capitalize first letter
                    if genre_slug != "" && genre_slug != "originals" {
                        let first_char = genre_slug.sub_string(0, 1).to_upper();
                        let rest = genre_slug.sub_string(1);
                        genres.push(first_char + rest);
                    }
                    break;
                }
            }
        }

        // Check content rating from data attribute
        let content_rating = "safe";
        let image_wrap = html_select(card, ".image_wrap");
        if image_wrap.len() > 0 {
            let unsuitable = element_attr(image_wrap[0], "data-title-unsuitable-for-children");
            if unsuitable == "true" {
                content_rating = "suggestive";
            }
        }

        // Use full URL as the ID so get_series/get_chapters can work properly
        // Webtoon requires the full path with genre/slug to fetch series data
        let series_id = if full_url != "" { full_url } else { title_no };

        series.push(#{
            id: series_id,
            title: title,
            url: if full_url != "" { full_url } else { `${BASE_URL}/en/originals/series?title_no=${title_no}` },
            cover_url: cover_url,
            authors: [],
            artists: [],
            genres: genres,
            tags: ["webtoon", "originals"],
            status: "Ongoing",
            content_rating: content_rating,
            updated_at: ()
        });
    }

    // Webtoon doesn't really paginate latest, limit pages
    let has_more = page < 1;

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/en/top`;

    let html = http_get_with_headers(url, get_headers());

    let series = [];

    // Get top ranking cards
    let cards = html_select(html, ".lst_area li a, .top_lst li a, .ranking_lst li a");

    for card in cards {
        let href = element_attr(card, "href");
        if href == () || href == "" {
            continue;
        }

        let title_no = extract_title_no(href);
        if title_no == "" {
            continue;
        }

        // Get title
        let title = "";
        let title_els = html_select(card, "p.subj, .info .subj");
        if title_els.len() > 0 {
            title = element_text(title_els[0]).trim();
        }

        if title == "" {
            continue;
        }

        // Get cover
        let cover_url = ();
        let imgs = html_select(card, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            if cover_url == () {
                cover_url = element_attr(imgs[0], "data-src");
            }
        }

        series.push(#{
            id: title_no,
            title: title,
            url: make_full_url(href),
            cover_url: cover_url
        });
    }

    let has_more = page < 1;

    #{ series: series, has_more: has_more }
}

// === Helper Functions ===

/// Extract title_no from Webtoon URL
fn extract_title_no(url) {
    // Pattern: title_no=12345
    if url.contains("title_no=") {
        let parts = url.split("title_no=");
        if parts.len() > 1 {
            let num = parts[1].split("&")[0];
            return num;
        }
    }

    // Pattern: /title/12345/
    if url.contains("/title/") {
        let parts = url.split("/title/");
        if parts.len() > 1 {
            let segment = parts[1].split("/")[0];
            return segment;
        }
    }

    ""
}

/// Extract episode_no from Webtoon URL
fn extract_episode_no(url) {
    // Pattern: episode_no=12345
    if url.contains("episode_no=") {
        let parts = url.split("episode_no=");
        if parts.len() > 1 {
            let num = parts[1].split("&")[0];
            return num;
        }
    }

    // Pattern: /episode/12345/
    if url.contains("/episode/") {
        let parts = url.split("/episode/");
        if parts.len() > 1 {
            let segment = parts[1].split("/")[0];
            return segment;
        }
    }

    ""
}

/// Extract just numbers from text like "Ep. 123" -> "123"
fn extract_number_from_text(text) {
    let num = "";
    let found_num = false;

    for c in text.chars() {
        if c >= '0' && c <= '9' {
            num += c;
            found_num = true;
        } else if found_num && c != '.' {
            // Stop at first non-digit after finding numbers (except decimal)
            break;
        } else if c == '.' && found_num {
            num += c;
        }
    }

    num
}

/// Make URL absolute if relative
fn make_full_url(url) {
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
