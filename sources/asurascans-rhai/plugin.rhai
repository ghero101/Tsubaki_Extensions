// Asura Scans Scraper Add-on (Rhai)
// Browser automation scraper for asuracomic.net (Next.js SPA with client-side pagination)
//
// Available APIs:
//   HTTP: http_get(url), http_get_with_headers(url, headers)
//   HTML: html_parse(html), html_select(html, selector), element_text(el), element_attr(el, attr)
//   Regex: regex_match(pattern, text), regex_find(pattern, text)
//   Browser: browser_launch_stealth(), browser_goto(), browser_scroll_to_bottom(),
//            browser_click(), browser_get_html(), browser_close()

const BASE_URL = "https://asurascans.com";

/// Get standard headers for requests
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": BASE_URL
    }
}

/// Fetch HTML, with TLS-impersonation client first and a plain-client retry
/// for the Next.js error pages that the impersonation client provokes.
///
/// Both calls are individually try/catch'd so a network exception in tier 1
/// doesn't abort the function before tier 2 runs. Previous version threw all
/// the way up to callers, which then died with no fallback.
fn fetch_html(url) {
    let html = "";
    try {
        html = http_get_with_headers(url, get_headers());
    } catch {}

    let looks_broken = html == () || html.len() == 0
        || html.contains("__next_error__") || html.contains("\"FATAL\"")
        || html.contains("NEXT_NOT_FOUND") || html.contains("Internal Server Error");

    if looks_broken {
        try {
            return http_get_plain(url, get_headers());
        } catch {
            return "";
        }
    }
    html
}

/// Guard against accepting a rating ("9.7", "10", "4.5") as a series title.
/// The current Asura card layout renders the rating in a `span.block.font-bold`
/// — the exact selector that used to hold the title — so every title candidate
/// must be screened through this before being accepted.
fn looks_like_rating(s) {
    if s == () || s == "" {
        return false;
    }
    let t = s.trim();
    if t == "" {
        return false;
    }
    // Pure number, optionally with a single decimal part (e.g. "9", "9.7", "10.0").
    if regex_match("^[0-9]+(\\.[0-9]+)?$", t) {
        return true;
    }
    false
}

/// Convert an Asura slug (minus its trailing build hash) into a readable title.
fn slug_to_title(slug) {
    let parts = slug.split("-");
    let words = [];
    for i in 0..parts.len() {
        let w = parts[i];
        // Drop a trailing hex build hash (e.g. "46f09241").
        if i == parts.len() - 1 && w.len() >= 6 && regex_match("^[0-9a-f]+$", w) {
            continue;
        }
        if w.len() > 0 {
            let first = w.sub_string(0, 1).to_upper();
            let rest = if w.len() > 1 { w.sub_string(1, w.len()) } else { "" };
            words.push(first + rest);
        }
    }
    if words.len() > 0 {
        return words.reduce(|a, b| a + " " + b);
    }
    slug.replace("-", " ")
}

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "asurascans",
        name: "Asura Scans",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "browser_automation"
    }
}

/// Extract series from HTML document
fn extract_series_from_html(html, query, seen) {
    let series = [];
    let query_lower = if query != () { query.to_lower() } else { "" };

    let doc = html_parse(html);

    // Series cards are anchor tags with href containing "comics/" (Asura moved
    // from /series/{slug} to /comics/{slug}-{hash} in 2026).
    let items = html_select(doc, "a[href*='comics/']");

    for item in items {
        let href = element_attr(item, "href");
        if href == () || href == "" {
            continue;
        }

        // Skip chapter links — we only want series cards here.
        if href.contains("/chapter/") {
            continue;
        }

        // Extract slug from href (format: "comics/slug-hash" or full URL)
        let slug = "";
        if href.contains("/comics/") {
            let parts = href.split("/comics/");
            if parts.len() > 1 {
                slug = parts[1].split("/")[0].split("?")[0];
            }
        } else if href.starts_with("comics/") {
            slug = href.sub_string(7, href.len()).split("/")[0].split("?")[0];
        }

        // Validate slug
        if slug == "" || slug.len() > 100 {
            continue;
        }

        // Skip duplicates
        if seen.contains(slug) {
            continue;
        }
        seen[slug] = true;

        // Get cover image up front — its `alt` is the most reliable title source
        // on the current layout (the old span.block.font-bold holds the RATING).
        let cover_url = ();
        let img_alt = "";
        let imgs = html_select(item, "img");
        if imgs.len() > 0 {
            cover_url = element_attr(imgs[0], "src");
            let alt = element_attr(imgs[0], "alt");
            if alt != () { img_alt = alt.trim(); }
        }

        // Title resolution, in order of preference. Every candidate is screened
        // through looks_like_rating() so a "9.7" rating is never accepted.
        let title = "";

        // 1. The card link's `title` attribute (most explicit when present).
        let link_title = element_attr(item, "title");
        if link_title != () {
            let lt = link_title.trim();
            if lt != "" && lt != "MANHWA" && lt != "MANGA" && !looks_like_rating(lt) {
                title = lt;
            }
        }

        // 2. The cover img `alt` text.
        if title == "" && img_alt != "" && img_alt != "MANHWA" && img_alt != "MANGA"
            && !looks_like_rating(img_alt) {
            title = img_alt;
        }

        // 3. A derived, readable name from the href slug.
        if title == "" {
            let derived = slug_to_title(slug);
            if derived != "" && !looks_like_rating(derived) {
                title = derived;
            }
        }

        // 4. Last-resort text-span scan — REJECT numeric/rating candidates so a
        //    "9.7" can never slip through. (This was the original bug.)
        if title == "" {
            let span_els = html_select(item, "span");
            for span_el in span_els {
                let span_text = element_text(span_el).trim();
                if span_text != "" && span_text.len() < 80 && span_text != "MANHWA" && span_text != "MANGA"
                    && !span_text.starts_with("Chapter") && !span_text.contains("<!--")
                    && !looks_like_rating(span_text) {
                    title = span_text;
                    break;
                }
            }
        }
        if title == "" {
            let div_els = html_select(item, "div");
            for div_el in div_els {
                let div_text = element_text(div_el).trim();
                if div_text != "" && div_text.len() < 80 && div_text != "MANHWA" && div_text != "MANGA"
                    && !div_text.starts_with("Chapter") && !div_text.contains("<!--")
                    && !looks_like_rating(div_text) {
                    title = div_text;
                    break;
                }
            }
        }

        // Absolute fallback: slug with hyphens replaced (never empty).
        if title == "" {
            title = slug_to_title(slug);
        }

        // Filter by query if provided
        if query != "" && query_lower != "" && !title.to_lower().contains(query_lower) {
            continue;
        }

        series.push(#{
            id: slug,
            title: title,
            url: `${BASE_URL}/comics/${slug}`,
            cover_url: cover_url,
            alternate_titles: [],
            authors: [],
            artists: [],
            status: (),
            genres: [],
            tags: [],
            description: ()
        });
    }

    series
}

/// Search for series matching query (HTTP with browser fallback)
fn search_series(query, page, auth) {
    // Asura's /browse listing ignores ?name= (search is client-side in the SPA),
    // so we fetch the browse page and filter titles client-side. Empty query =
    // latest/all on that page. The `&name=` is still sent in case a future build
    // honors it server-side — harmless if ignored.
    let url = if query != "" {
        `${BASE_URL}/browse?page=${page}&name=${url_encode(query)}`
    } else {
        `${BASE_URL}/browse?page=${page}`
    };

    // Try HTTP first
    let html = fetch_html(url);
    let seen = #{};
    let series = extract_series_from_html(html, query, seen);  // client-side title filter
    if series.len() > 0 {
        let has_more = series.len() >= 15;
        return #{ series: series, has_more: has_more, total: () };
    }

    // Browser fallback if HTTP returned no results
    if browser_is_available() {
        let session_id = ();
        try {
            session_id = browser_launch_stealth();
            browser_goto(session_id, url);
            try { browser_wait_for_selector(session_id, "a[href*='comics/']", 15000); } catch {}
            let html = browser_get_html(session_id);
            try { browser_close(session_id); } catch {}

            let seen = #{};
            let series = extract_series_from_html(html, query, seen);
            if series.len() > 0 {
                let has_more = series.len() >= 15;
                return #{ series: series, has_more: has_more, total: () };
            }
        } catch {
            if session_id != () { try { browser_close(session_id); } catch {} }
        }
    }

    #{ series: [], has_more: false, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let url = id_or_url;
    let slug = id_or_url;

    if !id_or_url.starts_with("http") {
        url = `${BASE_URL}/comics/${id_or_url}`;
    } else {
        // Extract slug from URL
        let parts = id_or_url.split("/comics/");
        if parts.len() > 1 {
            slug = parts[1].split("/")[0].split("?")[0];
        }
    }

    let html = fetch_html(url);

    let doc = html_parse(html);

    // Extract title — the <title> tag is the most reliable source now
    // ("Name | Asura Scans"); the old span.text-xl.font-bold selector matches
    // the rating ("9.7") on the current layout, so use it only as a fallback.
    let title = "";
    {
        let title_match = regex_find("<title>([^<]+)</title>", html);
        if title_match != "" {
            title = title_match.replace("<title>", "").replace("</title>", "").trim();
            // Current title format is "Name | Asura Scans"; older was "Name - Asura".
            if title.contains(" | Asura") {
                title = title.split(" | Asura")[0].trim();
            } else if title.contains(" - Asura") {
                title = title.split(" - Asura")[0].trim();
            }
        }
    }
    // Last resort: derive a readable title from the slug (minus the trailing hash).
    if title == "" {
        let parts = slug.split("-");
        let words = [];
        for i in 0..parts.len() {
            let w = parts[i];
            // drop the trailing build hash (e.g. "46f09241")
            if i == parts.len() - 1 && w.len() >= 6 && regex_match("^[0-9a-f]+$", w) { continue; }
            if w.len() > 0 {
                let first = w.sub_string(0, 1).to_upper();
                let rest = if w.len() > 1 { w.sub_string(1, w.len()) } else { "" };
                words.push(first + rest);
            }
        }
        if words.len() > 0 { title = words.reduce(|a, b| a + " " + b); }
    }

    // Extract cover from poster image
    let cover_url = ();
    let cover_els = html_select(doc, "img[alt='poster']");
    if cover_els.len() > 0 {
        cover_url = element_attr(cover_els[0], "src");
    }
    if cover_url == () || cover_url == "" {
        // Regex fallback: img with alt="poster"
        let cover_match = regex_find("alt=\"poster\"[^>]*src=\"([^\"]+)\"", html);
        if cover_match == "" {
            cover_match = regex_find("src=\"([^\"]+)\"[^>]*alt=\"poster\"", html);
        }
        if cover_match != "" {
            cover_url = regex_find("src=\"([^\"]+)\"", cover_match);
            if cover_url.starts_with("src=\"") {
                cover_url = cover_url.replace("src=\"", "").replace("\"", "");
            }
        }
    }
    if cover_url == () || cover_url == "" {
        // Current cover host: cdn.asurascans.com/asura-images/covers/{slug}.{hash}.webp
        let img_match = regex_find("https://[a-z0-9.]+/asura-images/covers/[^\"\\s]+\\.(?:webp|jpg|jpeg|png)", html);
        if img_match == "" {
            // Legacy fallback: gg.asura* storage conversions
            img_match = regex_find("https://gg\\.asura(?:comic\\.net|scans\\.com)/storage/media/\\d+/conversions/[A-Za-z0-9]+-optimized\\.webp", html);
        }
        if img_match != "" {
            cover_url = img_match;
        }
    }

    // Extract description — try multiple selectors then regex
    let description = ();
    let desc_els = html_select(doc, "span.font-medium.text-sm");
    if desc_els.len() > 0 {
        description = element_text(desc_els[0]).trim();
    }
    if description == () || description == "" {
        // Regex: text after "Synopsis" heading
        let synopsis_match = regex_find("Synopsis[^<]*</[^>]+>\\s*<[^>]+>([^<]{20,})", html);
        if synopsis_match != "" {
            // Extract just the text content
            description = regex_find(">([^<]{20,})", synopsis_match);
            if description.starts_with(">") {
                description = description.sub_string(1, description.len()).trim();
            }
        }
    }

    // Extract status. Current layout renders it as a bold, capitalized span
    // (e.g. <span class="... capitalize"> ongoing </span>) next to the "Status"
    // label; the old span.status selector no longer exists.
    let status = ();
    let status_els = html_select(doc, "span.status, span.capitalize");
    for el in status_els {
        let text = element_text(el).trim().to_lower();
        if text == "ongoing" { status = "Ongoing"; break; }
        if text == "completed" { status = "Completed"; break; }
        if text == "hiatus" { status = "Hiatus"; break; }
        if text == "dropped" || text == "cancelled" { status = "Cancelled"; break; }
        if text == "season end" || text == "coming soon" { status = "Hiatus"; break; }
    }
    if status == () {
        // Regex fallback: <span class="status ...">Ongoing</span>
        let status_match = regex_find("class=\"status[^\"]*\">([^<]+)<", html);
        if status_match != "" {
            let s = status_match.split(">")[1].split("<")[0].trim().to_lower();
            if s == "ongoing" { status = "Ongoing"; }
            if s == "completed" { status = "Completed"; }
            if s == "hiatus" { status = "Hiatus"; }
        }
    }

    // Extract genres from genre links
    let genres = [];
    for link in html_select(doc, "a[href*='genres=']") {
        let genre = element_text(link).trim();
        // Strip trailing commas and extra whitespace (Next.js RSC includes commas as child nodes)
        genre = genre.replace(",", "").trim();
        if genre != "" && genre.len() < 30 && !genres.contains(genre) {
            genres.push(genre);
        }
    }
    if genres.len() == 0 {
        // Regex fallback: genre links
        let genre_matches = regex_find_all("genres=\\d+\"[^>]*>\\s*([^<]+)<", html);
        for g in genre_matches {
            let genre = g.split(">")[1].split("<")[0].replace(",", "").trim();
            if genre != "" && genre.len() < 30 && !genres.contains(genre) {
                genres.push(genre);
            }
        }
    }

    // Extract authors and artists from detail section
    let authors = [];
    let artists = [];

    // Current layout links author/artist to filtered browse pages:
    // <a href="/browse?author=...">Name</a> / <a href="/browse?artist=...">Name</a>.
    for a in html_select(doc, "a[href*='author=']") {
        let n = element_text(a).replace(",", "").trim();
        if n != "" && n != "-" && n != "_" && n.to_lower() != "updating" && !authors.contains(n) { authors.push(n); }
    }
    for a in html_select(doc, "a[href*='artist=']") {
        let n = element_text(a).replace(",", "").trim();
        if n != "" && n != "-" && n != "_" && n.to_lower() != "updating" && !artists.contains(n) { artists.push(n); }
    }

    // Legacy fallback: <h3>Author</h3><h3>value</h3> key-value pairs.
    let author_match = if authors.len() == 0 { regex_find("(?i)Author\\s*</h3>\\s*<h3[^>]*>([^<]+)<", html) } else { "" };
    if author_match != "" {
        let author_text = author_match.split(">");
        if author_text.len() > 1 {
            let name = author_text[author_text.len() - 1].split("<")[0].trim();
            if name != "" && name != "-" && name != "_" && name.to_lower() != "updating" {
                authors.push(name);
            }
        }
    }
    if authors.len() == 0 {
        // Fallback: look for Author label in spans
        let auth_match = regex_find("(?i)>\\s*Author\\s*<[^>]*>\\s*<[^>]*>([^<]+)<", html);
        if auth_match != "" {
            let name = auth_match.split(">");
            if name.len() > 1 {
                let n = name[name.len() - 1].split("<")[0].trim();
                if n != "" && n != "-" && n != "_" && n.to_lower() != "updating" {
                    authors.push(n);
                }
            }
        }
    }

    let artist_match = if artists.len() == 0 { regex_find("(?i)Artist\\s*</h3>\\s*<h3[^>]*>([^<]+)<", html) } else { "" };
    if artist_match != "" {
        let artist_text = artist_match.split(">");
        if artist_text.len() > 1 {
            let name = artist_text[artist_text.len() - 1].split("<")[0].trim();
            if name != "" && name != "-" && name != "_" && name.to_lower() != "updating" {
                artists.push(name);
            }
        }
    }

    // Extract alternative titles
    let alternate_titles = [];
    let alt_match = regex_find("(?i)Alternative\\s*(?:Titles?)?\\s*</h3>\\s*<h3[^>]*>([^<]+)<", html);
    if alt_match != "" {
        let alt_text = alt_match.split(">");
        if alt_text.len() > 1 {
            let alts = alt_text[alt_text.len() - 1].split("<")[0].trim();
            if alts != "" && alts != "-" {
                // May be comma or semicolon separated
                let parts = alts.split(",");
                if parts.len() == 1 { parts = alts.split(";"); }
                for p in parts {
                    let t = p.trim();
                    if t != "" && t != title {
                        alternate_titles.push(t);
                    }
                }
            }
        }
    }

    // Extract type tag (Manhwa, Manga, Manhua)
    let type_match = regex_find("(?i)Type\\s*</h3>\\s*<h3[^>]*>([^<]+)<", html);
    let tags = [];
    if type_match != "" {
        let type_text = type_match.split(">");
        if type_text.len() > 1 {
            let t = type_text[type_text.len() - 1].split("<")[0].trim();
            if t != "" && t != "-" {
                tags.push(t);
            }
        }
    }

    #{
        id: slug,
        title: title,
        alternate_titles: alternate_titles,
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: status,
        genres: genres,
        tags: tags,
        year: (),
        content_rating: "suggestive",
        url: url,
        extra: #{
            source_name: "Asura Scans",
            auto_match_metadata: true
        }
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let url = series_id;
    let slug = series_id;

    if !series_id.starts_with("http") {
        url = `${BASE_URL}/comics/${series_id}`;
    } else {
        // Extract slug from URL
        let parts = series_id.split("/comics/");
        if parts.len() > 1 {
            slug = parts[1].split("/")[0].split("?")[0];
        }
    }

    let html = fetch_html(url);
    let doc = html_parse(html);

    let chapters = [];
    let seen = #{};

    // Find all chapter links via CSS selector
    let chapter_links = html_select(doc, "a[href*='chapter/']");

    // Fallback: regex extraction if CSS selector yields nothing
    if chapter_links.len() == 0 {
        let href_matches = regex_find_all("href=\"([^\"]*chapter/[^\"]+)\"", html);
        for href in href_matches {
            let clean_href = href.replace("href=\"", "").replace("\"", "");
            // Wrap in a minimal <a> tag so the loop below can process it
            chapter_links.push(`<a href="${clean_href}"></a>`);
        }
    }

    for link in chapter_links {
        let href = element_attr(link, "href");
        if href == () || href == "" {
            continue;
        }

        // Extract chapter number from URL
        let chapter_num = "";
        let parts = href.split("/chapter/");
        if parts.len() > 1 {
            chapter_num = parts[1].split("/")[0].split("?")[0];
        } else {
            let parts2 = href.split("chapter/");
            if parts2.len() > 1 {
                chapter_num = parts2[1].split("/")[0].split("?")[0];
            }
        }

        if chapter_num == "" { continue; }
        if seen.contains(chapter_num) { continue; }
        seen[chapter_num] = true;

        // Build full URL
        let chapter_url = href;
        if !href.starts_with("http") {
            if href.starts_with("/") {
                chapter_url = `${BASE_URL}${href}`;
            } else if href.contains("chapter/") {
                chapter_url = `${BASE_URL}/comics/${href}`;
            } else {
                chapter_url = `${BASE_URL}/${href}`;
            }
        }

        chapters.push(#{
            id: chapter_url,
            series_id: series_id,
            number: chapter_num,
            title: (),
            volume: (),
            language: "en",
            scanlator: "Asura Scans",
            url: chapter_url,
            published_at: (),
            page_count: (),
            extra: #{}
        });
    }

    // Sort chapters by number (descending - newest first is default, but we want ascending)
    chapters.sort(|a, b| {
        let num_a = parse_float(a.number);
        let num_b = parse_float(b.number);
        if num_a < num_b { -1 } else if num_a > num_b { 1 } else { 0 }
    });

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = chapter_id;

    if !chapter_id.starts_with("http") {
        url = `${BASE_URL}/comics/${chapter_id}`;
    }

    let html = fetch_html(url);

    let pages = [];
    let idx = 0;
    let seen = #{};

    // Current page images live at
    //   https://cdn.asurascans.com/asura-images/chapters/{slug}/{ch}/NNN.webp
    // (plain <img> in the chapter HTML — no JS render needed). Only match the
    // /chapters/ path so we don't pick up /covers/ or logos.
    let matches = regex_find_all("https://[a-z0-9.]+/asura-images/chapters/[^\"\\s]+\\.(?:webp|jpg|jpeg|png)", html);

    // Fallback 1: protocol-relative form (//cdn.../asura-images/chapters/...)
    if matches.len() == 0 {
        let rel = regex_find_all("//[a-z0-9.]+/asura-images/chapters/[^\"\\s]+\\.(?:webp|jpg|jpeg|png)", html);
        for m in rel { matches.push(`https:${m}`); }
    }

    // Fallback 2: legacy Next.js storage/conversions pattern
    if matches.len() == 0 {
        matches = regex_find_all("https://[^\"\\s]+/storage/media/\\d+/conversions/[A-Za-z0-9]+-optimized\\.webp", html);
    }

    for img_url in matches {
        // Skip duplicates
        if seen.contains(img_url) {
            continue;
        }
        seen[img_url] = true;

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

    pages
}

/// Get latest updates - reuses search_series logic for home page
fn get_latest_updates(page, auth) {
    // The home page and series page have similar structure
    // Use search_series with empty query to get latest
    let result = search_series("", page, auth);

    // Convert to latest updates format
    let series = [];
    for s in result.series {
        series.push(#{
            id: s.id,
            title: s.title,
            url: s.url,
            cover_url: s.cover_url,
            updated_at: ()
        });
    }

    #{ series: series, has_more: result.has_more }
}

