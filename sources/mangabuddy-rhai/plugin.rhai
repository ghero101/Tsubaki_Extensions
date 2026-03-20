// MangaBuddy Scraper Add-on (Rhai)
// HTTP-only scraper for mangabuddy.com (MadTheme-based platform)
//
// Website: https://mangabuddy.com
// Features: Search, Browse, Series Details, Chapters, Page Images
//
// URL Patterns:
//   Search:   /search?q={query}&page={page}
//   Browse:   /search?page={page}&sort=views (or sort=updated)
//   Series:   /{slug}
//   Chapters: /api/manga/{slug}/chapters?source=detail
//   Reader:   /{slug}/chapter-{N}
//
// MadTheme selectors:
//   Search items:  .book-detailed-item
//   Series title:  .detail h1
//   Alt title:     .detail h2
//   Cover:         #cover img (data-src attribute)
//   Description:   .summary .content
//   Authors:       .detail .meta p (containing "Author")
//   Genres:        .detail .meta p (containing "Genre")
//   Status:        .detail .meta p (containing "Status")
//   Chapter list:  li > a (from API response)
//   Chapter title: strong (inside a)
//   Page images:   var chapImages = '...' (comma-separated) + var mainServer
//   Fallback imgs: #chapter-images img, .chapter-image[data-src]
//
// Available Rhai APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   html_select(html, selector) -> array
//   html_select_first(html, selector) -> string
//   element_text(html) -> string
//   element_attr(html, attr) -> string
//   element_select(html, selector) -> array
//   element_select_first(html, selector) -> string
//   regex_find(pattern, text) -> string
//   regex_find_all(pattern, text) -> array
//   url_encode(text) -> string
//   parse_int(text) -> int

const BASE_URL = "https://mangabuddy.com";

// ============================================================================
// Helper Functions
// ============================================================================

/// Build request headers for MangaBuddy
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch HTML from a URL with error handling
fn fetch_html(url) {
    let html = "";
    try {
        html = http_get_with_headers(url, get_headers());
    } catch {
        try {
            html = http_get(url);
        } catch {
            html = "";
        }
    }
    html
}

/// Strip HTML tags from text
fn strip_html(text) {
    if text == () {
        return "";
    }

    let result = text;

    // Replace common HTML entities and tags
    result = result.replace("<p>", "");
    result = result.replace("</p>", "\n");
    result = result.replace("<br>", "\n");
    result = result.replace("<br/>", "\n");
    result = result.replace("<br />", "\n");
    result = result.replace("&nbsp;", " ");
    result = result.replace("&amp;", "&");
    result = result.replace("&lt;", "<");
    result = result.replace("&gt;", ">");
    result = result.replace("&quot;", "\"");
    result = result.replace("&#39;", "'");
    result = result.replace("&apos;", "'");

    // Remove remaining HTML tags
    loop {
        let start = result.index_of("<");
        if start == () {
            break;
        }
        let end = result.index_of(">");
        if end == () {
            break;
        }
        if end > start {
            result = result.sub_string(0, start) + result.sub_string(end + 1);
        } else {
            break;
        }
    }

    result.trim()
}

/// Parse float from string (e.g., "123.5" -> 123.5)
fn parse_float_str(s) {
    if s == () || s == "" { return 0.0; }
    let cleaned = "";
    for c in s.chars() {
        if (c >= '0' && c <= '9') || c == '.' {
            cleaned += c;
        }
    }
    if cleaned == "" { return 0.0; }

    let result = 0.0;
    let parts = cleaned.split(".");
    if parts.len() > 0 && parts[0] != "" {
        result = parse_int(parts[0]);
    }
    if parts.len() > 1 && parts[1] != "" {
        let decimal = parse_int(parts[1]);
        let divisor = 1.0;
        for i in 0..parts[1].len() {
            divisor *= 10.0;
        }
        result += decimal / divisor;
    }
    result
}

/// Extract the manga slug from a URL path
/// e.g., "/solo-leveling" -> "solo-leveling"
///       "/one-piece/chapter-1" -> "one-piece"
///       "https://mangabuddy.com/solo-leveling" -> "solo-leveling"
fn extract_slug(url) {
    let path = url;

    // Remove base URL if present
    if path.contains("mangabuddy.com") {
        let parts = path.split("mangabuddy.com");
        if parts.len() > 1 {
            path = parts[1];
        }
    }

    // Remove leading slash
    if path.starts_with("/") {
        path = path.sub_string(1);
    }

    // Remove query params
    if path.contains("?") {
        path = path.split("?")[0];
    }

    // Remove trailing slash
    if path.ends_with("/") {
        path = path.sub_string(0, path.len() - 1);
    }

    // Take only the first path segment (the series slug)
    let parts = path.split("/");
    if parts.len() > 0 && parts[0] != "" {
        return parts[0];
    }

    path
}

/// Extract chapter number from URL or title text
fn extract_chapter_number(url, title) {
    // From URL: /series-slug/chapter-123 or chapter-123.5
    let result = regex_find("chapter-(\\d+\\.?\\d*)", url);
    if result != "" {
        let num = result.replace("chapter-", "");
        if num != "" {
            return num;
        }
    }

    // From title: "Chapter 123" or "Chapter 123: Title"
    let title_lower = title.to_lower();
    if title_lower.contains("chapter") {
        let after = "";
        let parts = title_lower.split("chapter");
        if parts.len() > 1 {
            after = parts[1].trim();
        }
        let num_str = "";
        for c in after.chars() {
            if (c >= '0' && c <= '9') || c == '.' {
                num_str += c;
            } else if num_str.len() > 0 {
                break;
            }
        }
        if num_str != "" {
            return num_str;
        }
    }

    // From title: "Vol.2 Chapter 143"
    if title_lower.contains("vol") {
        let ch_match = regex_find("chapter\\s*(\\d+\\.?\\d*)", title_lower);
        if ch_match != "" {
            let num = ch_match.replace("chapter", "").trim();
            if num != "" {
                return num;
            }
        }
    }

    "0"
}

/// Extract volume number from chapter title if present
fn extract_volume(title) {
    let title_lower = title.to_lower();
    if title_lower.contains("vol") {
        let vol_match = regex_find("vol\\.?\\s*(\\d+)", title_lower);
        if vol_match != "" {
            let num = regex_find("\\d+", vol_match);
            if num != "" {
                return num;
            }
        }
    }
    ()
}

/// Extract chapter title from full chapter text
/// e.g., "Chapter 110: Season 1 Finale" -> "Season 1 Finale"
///       "Chapter 123" -> ()
fn extract_chapter_title(text) {
    if text.contains(":") {
        let parts = text.split(":");
        if parts.len() > 1 {
            // Join everything after the first colon
            let title_text = "";
            for i in 1..parts.len() {
                if title_text != "" { title_text += ":"; }
                title_text += parts[i];
            }
            title_text = title_text.trim();
            if title_text != "" && title_text.len() > 1 {
                return title_text;
            }
        }
    }
    ()
}

/// Make URL absolute
fn make_absolute_url(url) {
    if url == () || url == "" {
        return "";
    }
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

/// Map status text to standard format
fn map_status(text) {
    let lower = text.to_lower();
    if lower.contains("ongoing") || lower.contains("releasing") {
        return "Ongoing";
    }
    if lower.contains("completed") || lower.contains("complete") || lower.contains("finished") {
        return "Completed";
    }
    if lower.contains("hiatus") {
        return "Hiatus";
    }
    if lower.contains("cancelled") || lower.contains("canceled") || lower.contains("dropped") {
        return "Cancelled";
    }
    ()
}

// ============================================================================
// Required Interface Functions
// ============================================================================

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangabuddy-rhai",
        name: "MangaBuddy",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        nsfw: false,
        content_types: ["manga", "manhwa", "manhua"]
    }
}

/// Search for manga matching a query
fn search_series(query, page, auth) {
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/search?q=${encoded_query}&page=${page}`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    let seen = #{};

    // MadTheme uses .book-detailed-item for search results
    let items = html_select(html, ".book-detailed-item");

    for item in items {
        // Get the primary link from the thumbnail area
        let link = element_select_first(item, ".thumb a");
        if link == "" {
            link = element_select_first(item, "a");
        }
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || slug == "search" || slug == "az-list" {
            continue;
        }

        // Skip duplicates
        if seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        // Get title from link title attribute or text
        let title = element_attr(link, "title");
        if title == () || title == "" {
            // Try the title from a heading element
            let title_el = element_select_first(item, "h3 a, h2 a, .title a");
            if title_el != "" {
                title = element_text(title_el).trim();
            }
        }
        if title == () || title == "" {
            title = element_text(link).trim();
        }
        if title == () || title == "" {
            continue;
        }

        // Get cover image
        let cover_url = "";
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(img, "src");
            }
        }
        if cover_url == () {
            cover_url = "";
        }
        cover_url = make_absolute_url(cover_url);

        // Try to get description snippet
        let description = ();
        let desc_el = element_select_first(item, ".summary, .description, .meta .content");
        if desc_el != "" {
            description = strip_html(element_text(desc_el));
            if description == "" {
                description = ();
            }
        }

        // Get genres from meta links
        let genres = [];
        let genre_links = element_select(item, ".genres a, .meta a[href*='/genre/']");
        for g_link in genre_links {
            let genre = element_text(g_link).trim();
            if genre != "" && !genres.contains(genre) {
                genres.push(genre);
            }
        }

        series.push(#{
            id: slug,
            title: title,
            alternate_titles: [],
            description: description,
            cover_url: cover_url,
            authors: [],
            artists: [],
            status: (),
            genres: genres,
            tags: [],
            year: (),
            content_rating: "suggestive",
            url: make_absolute_url(href),
            extra: #{
                source_site: "mangabuddy",
                auto_match_metadata: true,
                source_name: "MangaBuddy"
            }
        });
    }

    // If no items found with .book-detailed-item, try regex fallback
    // This handles cases where the HTML structure varies
    if series.len() == 0 {
        // Try to find manga links with title attributes
        let all_links = html_select(html, "a[title]");
        for link in all_links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }

            // Skip non-manga links
            if href.contains("/search") || href.contains("/genre/") || href.contains("/az-list") {
                continue;
            }
            if href.contains("/chapter-") {
                continue;
            }

            let slug = extract_slug(href);
            if slug == "" || seen[slug] != () {
                continue;
            }
            seen[slug] = true;

            let title = element_attr(link, "title");
            if title == () || title == "" {
                continue;
            }
            title = title.trim();

            // Get cover from img inside the link
            let cover_url = "";
            let img = element_select_first(link, "img");
            if img != "" {
                cover_url = element_attr(img, "data-src");
                if cover_url == () || cover_url == "" {
                    cover_url = element_attr(img, "src");
                }
            }
            if cover_url == () {
                cover_url = "";
            }
            cover_url = make_absolute_url(cover_url);

            series.push(#{
                id: slug,
                title: title,
                alternate_titles: [],
                description: (),
                cover_url: cover_url,
                authors: [],
                artists: [],
                status: (),
                genres: [],
                tags: [],
                year: (),
                content_rating: "suggestive",
                url: make_absolute_url(href),
                extra: #{
                    source_site: "mangabuddy",
                    auto_match_metadata: true,
                    source_name: "MangaBuddy"
                }
            });
        }
    }

    // Check for next page
    let has_more = false;
    let next_page = page + 1;
    if html.contains(`page=${next_page}`) {
        has_more = true;
    }
    // Also check pagination elements
    let page_links = html_select(html, ".pagination a, nav a");
    for p_link in page_links {
        let p_href = element_attr(p_link, "href");
        if p_href != () && p_href.contains(`page=${next_page}`) {
            has_more = true;
            break;
        }
        let text = element_text(p_link).to_lower();
        if text.contains("next") || text == ">" || text == ">>" {
            has_more = true;
            break;
        }
    }

    #{ series: series, has_more: has_more, total: 0 }
}

/// Get detailed series information by slug or URL
fn get_series(id_or_url, auth) {
    let slug = id_or_url;
    let url = "";

    if id_or_url.starts_with("http") {
        slug = extract_slug(id_or_url);
        url = id_or_url;
    } else if id_or_url.starts_with("/") {
        slug = extract_slug(id_or_url);
        url = `${BASE_URL}${id_or_url}`;
    } else {
        url = `${BASE_URL}/${slug}`;
    }

    let html = fetch_html(url);

    if html == "" {
        throw `Failed to fetch series page: ${url}`;
    }

    // --- Title ---
    // MadTheme: .detail h1
    let title = "";
    let title_els = html_select(html, ".detail h1");
    if title_els.len() > 0 {
        title = element_text(title_els[0]).trim();
    }
    // Fallback to plain h1
    if title == "" {
        let h1_els = html_select(html, "h1");
        if h1_els.len() > 0 {
            title = element_text(h1_els[0]).trim();
        }
    }
    // Fallback to og:title meta tag
    if title == "" {
        let og_title = regex_find("og:title[\"']\\s*content=[\"']([^\"']+)", html);
        if og_title != "" {
            title = regex_find("content=[\"']([^\"']+)", og_title);
            title = title.replace("content=\"", "").replace("content='", "").replace("\"", "").replace("'", "").trim();
            // Remove " - MangaBuddy" suffix
            if title.contains(" - MangaBuddy") {
                let idx = title.index_of(" - MangaBuddy");
                if idx != () && idx > 0 {
                    title = title.sub_string(0, idx);
                }
            }
            // Remove "Read " prefix
            if title.starts_with("Read ") {
                title = title.sub_string(5);
            }
        }
    }
    if title == "" {
        title = slug.replace("-", " ");
    }

    // --- Alternate Titles ---
    // MadTheme: .detail h2
    let alt_titles = [];
    let alt_els = html_select(html, ".detail h2");
    if alt_els.len() > 0 {
        let alt_text = element_text(alt_els[0]).trim();
        if alt_text != "" && alt_text != title {
            // Split by semicolons or commas
            let separator = ";";
            if !alt_text.contains(";") && alt_text.contains(",") {
                separator = ",";
            }
            let parts = alt_text.split(separator);
            for part in parts {
                let cleaned = part.trim();
                if cleaned != "" && cleaned != title && !alt_titles.contains(cleaned) {
                    alt_titles.push(cleaned);
                }
            }
        }
    }

    // --- Cover Image ---
    // MadTheme: #cover img with data-src
    let cover_url = "";
    let cover_els = html_select(html, "#cover img");
    if cover_els.len() > 0 {
        cover_url = element_attr(cover_els[0], "data-src");
        if cover_url == () || cover_url == "" {
            cover_url = element_attr(cover_els[0], "src");
        }
    }
    // Fallback: og:image meta tag
    if cover_url == () || cover_url == "" {
        let og_img = regex_find("og:image[\"']\\s*content=[\"']([^\"']+)", html);
        if og_img != "" {
            cover_url = regex_find("content=[\"']([^\"']+)", og_img);
            cover_url = cover_url.replace("content=\"", "").replace("content='", "").replace("\"", "").replace("'", "").trim();
        }
    }
    if cover_url == () {
        cover_url = "";
    }
    cover_url = make_absolute_url(cover_url);

    // --- Description ---
    // MadTheme: .summary .content
    let description = ();
    let desc_els = html_select(html, ".summary .content");
    if desc_els.len() > 0 {
        description = strip_html(element_text(desc_els[0]));
    }
    // Fallback: .summary p
    if description == () || description == "" {
        let desc_p_els = html_select(html, ".summary p");
        let desc_parts = [];
        for p in desc_p_els {
            let text = element_text(p).trim();
            if text != "" && text.len() > 10 {
                desc_parts.push(text);
            }
        }
        if desc_parts.len() > 0 {
            description = "";
            let first = true;
            for part in desc_parts {
                if !first { description += "\n\n"; }
                description += part;
                first = false;
            }
        }
    }
    // Fallback: meta description
    if description == () || description == "" {
        let meta_desc = regex_find("name=[\"']description[\"'][^>]*content=[\"']([^\"']+)", html);
        if meta_desc != "" {
            description = regex_find("content=[\"']([^\"']+)", meta_desc);
            description = description.replace("content=\"", "").replace("content='", "").replace("\"", "").replace("'", "").trim();
        }
    }
    if description == () {
        description = ();
    }

    // --- Authors ---
    // MadTheme: .detail .meta p containing "Author" with sibling <a> tags
    let authors = [];
    let meta_ps = html_select(html, ".detail .meta p");
    for p in meta_ps {
        let p_text = element_text(p).to_lower();
        if p_text.contains("author") {
            let author_links = element_select(p, "a");
            for a_link in author_links {
                let author = element_text(a_link).trim();
                if author != "" && author != "Updating" && !authors.contains(author) {
                    authors.push(author);
                }
            }
        }
    }

    // --- Artists ---
    let artists = [];
    for p in meta_ps {
        let p_text = element_text(p).to_lower();
        if p_text.contains("artist") {
            let artist_links = element_select(p, "a");
            for a_link in artist_links {
                let artist = element_text(a_link).trim();
                if artist != "" && artist != "Updating" && !artists.contains(artist) {
                    artists.push(artist);
                }
            }
        }
    }

    // --- Genres ---
    let genres = [];
    for p in meta_ps {
        let p_text = element_text(p).to_lower();
        if p_text.contains("genre") {
            let genre_links = element_select(p, "a");
            for a_link in genre_links {
                let genre = element_text(a_link).trim();
                if genre != "" && !genres.contains(genre) {
                    genres.push(genre);
                }
            }
        }
    }
    // Fallback: look for genre links anywhere
    if genres.len() == 0 {
        let genre_links = html_select(html, "a[href*='/genre/']");
        for g_link in genre_links {
            let genre = element_text(g_link).trim();
            if genre != "" && genre.len() < 50 && !genres.contains(genre) {
                genres.push(genre);
            }
        }
    }

    // --- Status ---
    let status = ();
    for p in meta_ps {
        let p_text = element_text(p).to_lower();
        if p_text.contains("status") {
            let status_links = element_select(p, "a");
            if status_links.len() > 0 {
                status = map_status(element_text(status_links[0]));
            }
            if status == () {
                status = map_status(p_text);
            }
        }
    }

    // --- Year ---
    let year = ();
    let year_match = regex_find("(19|20)\\d{2}", html);
    if year_match != "" {
        // Only use if it looks like a publication year context
        for p in meta_ps {
            let p_text = element_text(p);
            if p_text.contains(year_match) {
                year = year_match;
                break;
            }
        }
    }

    #{
        id: slug,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: status,
        genres: genres,
        tags: [],
        year: year,
        content_rating: "suggestive",
        url: url,
        extra: #{
            source_site: "mangabuddy",
            auto_match_metadata: true,
            source_name: "MangaBuddy"
        }
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let slug = series_id;

    if series_id.starts_with("http") {
        slug = extract_slug(series_id);
    } else if series_id.starts_with("/") {
        slug = extract_slug(series_id);
    }

    // MadTheme exposes a chapters API endpoint
    let url = `${BASE_URL}/api/manga/${slug}/chapters?source=detail`;

    let html = fetch_html(url);

    if html == "" {
        // Fallback: try to get chapters from the series page itself
        let series_url = `${BASE_URL}/${slug}`;
        html = fetch_html(series_url);
    }

    if html == "" {
        return [];
    }

    let chapters = [];
    let seen = #{};

    // Parse chapter list from API response
    // Structure: <li><a href="/{slug}/chapter-{N}" title="..."><strong>Chapter N</strong>Date</a></li>
    let chapter_items = html_select(html, "li");

    for item in chapter_items {
        let link = element_select_first(item, "a");
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Skip non-chapter links
        if !href.contains(slug) {
            continue;
        }

        // Deduplicate
        if seen[href] != () {
            continue;
        }
        seen[href] = true;

        // Get chapter text from <strong> element
        let ch_text = "";
        let strong_el = element_select_first(link, "strong");
        if strong_el != "" {
            ch_text = element_text(strong_el).trim();
        }
        if ch_text == "" {
            ch_text = element_text(link).trim();
        }
        if ch_text == "" {
            continue;
        }

        // Get title attribute for full chapter name
        let link_title = element_attr(link, "title");
        if link_title == () {
            link_title = "";
        }

        // Extract chapter number from URL or text
        let chapter_num = extract_chapter_number(href, ch_text);

        // Extract volume if present
        let volume = extract_volume(ch_text);

        // Extract chapter title (after colon)
        let chapter_title = extract_chapter_title(ch_text);

        // Build display title
        let display_title = ch_text;
        if display_title == "" {
            display_title = `Chapter ${chapter_num}`;
        }

        // Build chapter URL
        let chapter_url = make_absolute_url(href);

        // Build a unique chapter ID using slug and chapter path
        let ch_path = href;
        if ch_path.starts_with("/") {
            ch_path = ch_path.sub_string(1);
        }

        chapters.push(#{
            id: ch_path,
            series_id: slug,
            number: chapter_num,
            title: display_title,
            volume: volume,
            language: "en",
            scanlator: (),
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // Fallback: if no <li> items found, try direct <a> links with chapter patterns
    if chapters.len() == 0 {
        let chapter_links = html_select(html, "a[href*='/chapter-']");

        for link in chapter_links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }

            if seen[href] != () {
                continue;
            }
            seen[href] = true;

            let ch_text = element_text(link).trim();
            if ch_text == "" {
                // Try strong element
                let strong = element_select_first(link, "strong");
                if strong != "" {
                    ch_text = element_text(strong).trim();
                }
            }

            let chapter_num = extract_chapter_number(href, ch_text);

            let ch_path = href;
            if ch_path.starts_with("/") {
                ch_path = ch_path.sub_string(1);
            }

            chapters.push(#{
                id: ch_path,
                series_id: slug,
                number: chapter_num,
                title: if ch_text != "" { ch_text } else { `Chapter ${chapter_num}` },
                volume: extract_volume(ch_text),
                language: "en",
                scanlator: (),
                url: make_absolute_url(href),
                published_at: (),
                page_count: (),
                extra: #{}
            });
        }
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}/${chapter_id}`;
    }

    let html = fetch_html(url);

    if html == "" {
        return [];
    }

    let pages = [];
    let idx = 0;

    // Method 1: Extract from JavaScript variable 'chapImages'
    // MadTheme stores page images in: var chapImages = 'url1,url2,url3'
    let chap_images_match = regex_find("chapImages\\s*=\\s*['\"]([^'\"]+)['\"]", html);
    if chap_images_match != "" {
        // Extract the value between quotes
        let images_str = regex_find("['\"]([^'\"]+)['\"]", chap_images_match);
        images_str = images_str.replace("'", "").replace("\"", "").trim();

        // Check for mainServer variable to build full URLs
        let main_server = "";
        let server_match = regex_find("mainServer\\s*=\\s*['\"]([^'\"]+)['\"]", html);
        if server_match != "" {
            main_server = regex_find("['\"]([^'\"]+)['\"]", server_match);
            main_server = main_server.replace("'", "").replace("\"", "").trim();
        }

        if images_str != "" {
            let image_urls = images_str.split(",");

            for img_url in image_urls {
                let clean_url = img_url.trim();
                if clean_url == "" {
                    continue;
                }

                // Build full URL if needed
                if !clean_url.starts_with("http") {
                    if main_server != "" {
                        clean_url = `${main_server}${clean_url}`;
                    } else {
                        clean_url = make_absolute_url(clean_url);
                    }
                }

                pages.push(#{
                    index: idx,
                    url: clean_url,
                    headers: #{
                        "Referer": url
                    },
                    referer: url
                });
                idx += 1;
            }
        }
    }

    // Method 2: Try chapImages as JSON array
    if pages.len() == 0 {
        let json_match = regex_find("chapImages\\s*=\\s*\\[([^\\]]+)\\]", html);
        if json_match != "" {
            let array_content = regex_find("\\[([^\\]]+)\\]", json_match);
            array_content = array_content.replace("[", "").replace("]", "");

            let main_server = "";
            let server_match = regex_find("mainServer\\s*=\\s*['\"]([^'\"]+)['\"]", html);
            if server_match != "" {
                main_server = regex_find("['\"]([^'\"]+)['\"]", server_match);
                main_server = main_server.replace("'", "").replace("\"", "").trim();
            }

            let image_paths = regex_find_all("\"([^\"]+)\"", array_content);

            for img_path in image_paths {
                let clean_path = img_path.replace("\"", "").trim();
                if clean_path == "" {
                    continue;
                }

                let full_url = clean_path;
                if !full_url.starts_with("http") {
                    if main_server != "" {
                        full_url = `${main_server}${clean_path}`;
                    } else {
                        full_url = make_absolute_url(clean_path);
                    }
                }

                pages.push(#{
                    index: idx,
                    url: full_url,
                    headers: #{
                        "Referer": url
                    },
                    referer: url
                });
                idx += 1;
            }
        }
    }

    // Method 3: Parse img elements from chapter reader container
    if pages.len() == 0 {
        let selectors = [
            "#chapter-images img",
            ".chapter-image img",
            ".chapter-image[data-src]",
            ".reading-content img",
            ".container-chapter-reader img",
            ".page-img img"
        ];

        for selector in selectors {
            let page_imgs = html_select(html, selector);

            for img in page_imgs {
                let img_url = element_attr(img, "data-src");
                if img_url == () || img_url == "" {
                    img_url = element_attr(img, "src");
                }
                if img_url == () || img_url == "" {
                    img_url = element_attr(img, "data-lazy");
                }

                if img_url != () && img_url != "" {
                    // Skip non-page images
                    let lower_url = img_url.to_lower();
                    if lower_url.contains("logo") || lower_url.contains("icon") ||
                       lower_url.contains("avatar") || lower_url.contains("banner") ||
                       lower_url.contains("loading") || lower_url.contains("placeholder") ||
                       lower_url.starts_with("data:") || lower_url.contains("blank.gif") {
                        continue;
                    }

                    let full_url = make_absolute_url(img_url);

                    pages.push(#{
                        index: idx,
                        url: full_url,
                        headers: #{
                            "Referer": url
                        },
                        referer: url
                    });
                    idx += 1;
                }
            }

            // If we found pages with this selector, stop trying others
            if pages.len() > 0 {
                break;
            }
        }
    }

    // Method 4: Try .chapter-image elements with data-src attribute directly
    if pages.len() == 0 {
        let ch_images = html_select(html, ".chapter-image[data-src]");
        for ch_img in ch_images {
            let img_url = element_attr(ch_img, "data-src");
            if img_url != () && img_url != "" && !img_url.starts_with("data:") {
                let full_url = make_absolute_url(img_url);
                pages.push(#{
                    index: idx,
                    url: full_url,
                    headers: #{
                        "Referer": url
                    },
                    referer: url
                });
                idx += 1;
            }
        }
    }

    pages
}

/// Get latest manga updates
fn get_latest_updates(page, auth) {
    // MadTheme latest updates: search sorted by "updated"
    let url = `${BASE_URL}/search?page=${page}&sort=updated`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    // Parse items using the same structure as search
    let items = html_select(html, ".book-detailed-item");

    for item in items {
        let link = element_select_first(item, ".thumb a");
        if link == "" {
            link = element_select_first(item, "a");
        }
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || slug == "search" || slug == "az-list" {
            continue;
        }

        if seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        let title = element_attr(link, "title");
        if title == () || title == "" {
            let title_el = element_select_first(item, "h3 a, h2 a, .title a");
            if title_el != "" {
                title = element_text(title_el).trim();
            }
        }
        if title == () || title == "" {
            title = element_text(link).trim();
        }
        if title == () || title == "" {
            continue;
        }

        let cover_url = "";
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(img, "src");
            }
        }
        if cover_url == () {
            cover_url = "";
        }
        cover_url = make_absolute_url(cover_url);

        series.push(#{
            id: slug,
            title: title,
            url: make_absolute_url(href),
            cover_url: cover_url,
            updated_at: ()
        });
    }

    // Fallback: if .book-detailed-item not found, try finding manga links directly
    if series.len() == 0 {
        let all_links = html_select(html, "a[title]");
        for link in all_links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }
            if href.contains("/search") || href.contains("/genre/") || href.contains("/chapter-") {
                continue;
            }

            let slug = extract_slug(href);
            if slug == "" || seen[slug] != () {
                continue;
            }
            seen[slug] = true;

            let title = element_attr(link, "title");
            if title == () || title == "" {
                continue;
            }

            let cover_url = "";
            let img = element_select_first(link, "img");
            if img != "" {
                cover_url = element_attr(img, "data-src");
                if cover_url == () || cover_url == "" {
                    cover_url = element_attr(img, "src");
                }
            }
            if cover_url == () {
                cover_url = "";
            }
            cover_url = make_absolute_url(cover_url);

            series.push(#{
                id: slug,
                title: title,
                url: make_absolute_url(href),
                cover_url: cover_url,
                updated_at: ()
            });
        }
    }

    // Check for next page
    let has_more = false;
    let next_page = page + 1;
    if html.contains(`page=${next_page}`) {
        has_more = true;
    }
    // Assume more if we got a decent number of results
    if !has_more && series.len() >= 20 {
        has_more = true;
    }

    #{ series: series, has_more: has_more }
}

/// Browse manga (main browse endpoint)
fn browse(page, category, auth) {
    if category == "latest" || category == "updated" || category == "new" {
        return get_latest_updates(page, auth);
    }

    // Default: browse by popularity (views)
    let url = `${BASE_URL}/search?page=${page}&sort=views`;

    let html = fetch_html(url);

    if html == "" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    let seen = #{};

    let items = html_select(html, ".book-detailed-item");

    for item in items {
        let link = element_select_first(item, ".thumb a");
        if link == "" {
            link = element_select_first(item, "a");
        }
        if link == "" {
            continue;
        }

        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        let slug = extract_slug(href);
        if slug == "" || slug == "search" || slug == "az-list" {
            continue;
        }

        if seen[slug] != () {
            continue;
        }
        seen[slug] = true;

        let title = element_attr(link, "title");
        if title == () || title == "" {
            let title_el = element_select_first(item, "h3 a, h2 a, .title a");
            if title_el != "" {
                title = element_text(title_el).trim();
            }
        }
        if title == () || title == "" {
            title = element_text(link).trim();
        }
        if title == () || title == "" {
            continue;
        }

        let cover_url = "";
        let img = element_select_first(item, "img");
        if img != "" {
            cover_url = element_attr(img, "data-src");
            if cover_url == () || cover_url == "" {
                cover_url = element_attr(img, "src");
            }
        }
        if cover_url == () {
            cover_url = "";
        }
        cover_url = make_absolute_url(cover_url);

        series.push(#{
            id: slug,
            title: title,
            url: make_absolute_url(href),
            cover_url: cover_url
        });
    }

    // Fallback for missing .book-detailed-item
    if series.len() == 0 {
        let all_links = html_select(html, "a[title]");
        for link in all_links {
            let href = element_attr(link, "href");
            if href == () || href == "" {
                continue;
            }
            if href.contains("/search") || href.contains("/genre/") || href.contains("/chapter-") {
                continue;
            }

            let slug = extract_slug(href);
            if slug == "" || seen[slug] != () {
                continue;
            }
            seen[slug] = true;

            let title = element_attr(link, "title");
            if title == () || title == "" {
                continue;
            }

            let cover_url = "";
            let img = element_select_first(link, "img");
            if img != "" {
                cover_url = element_attr(img, "data-src");
                if cover_url == () || cover_url == "" {
                    cover_url = element_attr(img, "src");
                }
            }
            if cover_url == () {
                cover_url = "";
            }
            cover_url = make_absolute_url(cover_url);

            series.push(#{
                id: slug,
                title: title,
                url: make_absolute_url(href),
                cover_url: cover_url
            });
        }
    }

    // Check for next page
    let has_more = false;
    let next_page = page + 1;
    if html.contains(`page=${next_page}`) {
        has_more = true;
    }
    if !has_more && series.len() >= 20 {
        has_more = true;
    }

    #{ series: series, has_more: has_more }
}
