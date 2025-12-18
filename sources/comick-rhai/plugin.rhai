// ComicK Scraper Add-on (Rhai)
// Uses the ComicK API (api.comick.io)
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const BASE_URL = "https://api.comick.io";
const SITE_URL = "https://comick.io";
const CDN_URL = "https://meo.comick.pictures";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "comick-rhai",
        name: "ComicK",
        base_url: SITE_URL,
        language: "en",
        supported_languages: ["en", "ja", "ko", "zh", "es", "fr", "de", "it", "pt-br", "ru", "vi", "id", "th"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Get headers for API requests
fn get_headers() {
    #{
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": SITE_URL
    }
}

/// Map status to standard format
fn map_status(status) {
    if status == () { return (); }
    switch status {
        1 => "Ongoing",
        2 => "Completed",
        3 => "Cancelled",
        4 => "Hiatus",
        _ => ()
    }
}

/// Get cover URL from cover object
fn get_cover_url(comic) {
    if comic.contains("md_covers") {
        let covers = comic["md_covers"];
        if covers.len() > 0 {
            let cover = covers[0];
            if cover.contains("b2key") {
                return `${CDN_URL}/${cover["b2key"]}`;
            }
        }
    }
    ()
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let encoded_query = url_encode(query);
    let url = `${BASE_URL}/v1.0/search?q=${encoded_query}&page=${page}&limit=25&tachiyomi=true`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    let series = [];

    if response == () || !response.is_array() {
        return #{ series: [], has_more: false, total: 0 };
    }

    for comic in response {
        let id = comic["hid"];
        let slug = comic["slug"];

        // Get title (prefer English)
        let title = comic["title"];
        if title == () || title == "" {
            if comic.contains("md_titles") {
                for t in comic["md_titles"] {
                    if t["lang"] == "en" {
                        title = t["title"];
                        break;
                    }
                }
            }
        }

        // Get alternate titles
        let alt_titles = [];
        if comic.contains("md_titles") {
            for t in comic["md_titles"] {
                let alt = t["title"];
                if alt != () && alt != title && !alt_titles.contains(alt) {
                    alt_titles.push(alt);
                }
            }
        }

        // Get genres/tags
        let genres = [];
        if comic.contains("md_genres") {
            for g in comic["md_genres"] {
                if g.contains("name") {
                    genres.push(g["name"]);
                }
            }
        }

        series.push(#{
            id: id,
            title: title,
            url: `${SITE_URL}/comic/${slug}`,
            cover_url: get_cover_url(comic),
            alternate_titles: alt_titles,
            authors: [],
            artists: [],
            status: map_status(comic["status"]),
            genres: genres,
            tags: [],
            description: comic["desc"]
        });
    }

    // ComicK returns empty array when no more pages
    let has_more = response.len() >= 25;

    #{ series: series, has_more: has_more, total: () }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let slug = id_or_url;

    // Extract slug from URL if needed
    if id_or_url.contains("comick.io") {
        let parts = id_or_url.split("/comic/");
        if parts.len() > 1 {
            slug = parts[1].split("/")[0].split("?")[0];
        }
    }

    let url = `${BASE_URL}/comic/${slug}?tachiyomi=true`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    if response == () || !response.contains("comic") {
        return #{
            id: slug,
            title: "",
            error: "Failed to fetch comic"
        };
    }

    let comic = response["comic"];
    let id = comic["hid"];

    // Get title
    let title = comic["title"];

    // Get alternate titles
    let alt_titles = [];
    if comic.contains("md_titles") {
        for t in comic["md_titles"] {
            let alt = t["title"];
            if alt != () && alt != title && !alt_titles.contains(alt) {
                alt_titles.push(alt);
            }
        }
    }

    // Get description
    let description = comic["desc"];
    if description == () && comic.contains("parsed") {
        description = comic["parsed"];
    }

    // Get authors/artists
    let authors = [];
    let artists = [];
    if response.contains("artists") {
        for artist in response["artists"] {
            if artist.contains("name") {
                artists.push(artist["name"]);
            }
        }
    }
    if response.contains("authors") {
        for author in response["authors"] {
            if author.contains("name") {
                authors.push(author["name"]);
            }
        }
    }

    // Get genres
    let genres = [];
    if comic.contains("md_genres") {
        for g in comic["md_genres"] {
            if g.contains("name") {
                genres.push(g["name"]);
            }
        }
    }

    // Get content rating
    let content_rating = "safe";
    if comic.contains("content_rating") {
        let rating = comic["content_rating"];
        if rating == "erotica" || rating == "pornographic" {
            content_rating = "adult";
        } else if rating == "suggestive" {
            content_rating = "suggestive";
        }
    }

    #{
        id: id,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: get_cover_url(comic),
        authors: authors,
        artists: artists,
        status: map_status(comic["status"]),
        genres: genres,
        tags: [],
        year: comic["year"],
        content_rating: content_rating,
        url: `${SITE_URL}/comic/${slug}`,
        extra: #{
            slug: slug,
            country: comic["country"],
            demographic: comic["demographic"]
        }
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let chapters = [];
    let page = 1;
    let limit = 100;

    // First, we need to get the hid if we have a slug
    let hid = series_id;
    if !series_id.starts_with("http") && series_id.len() > 10 {
        // Likely a slug, need to fetch the comic first
        let comic_url = `${BASE_URL}/comic/${series_id}?tachiyomi=true`;
        let comic_response = http_get_with_headers(comic_url, get_headers());
        let comic_data = json_parse(comic_response);
        if comic_data != () && comic_data.contains("comic") {
            hid = comic_data["comic"]["hid"];
        }
    }

    loop {
        let url = `${BASE_URL}/comic/${hid}/chapters?lang=en&page=${page}&limit=${limit}&tachiyomi=true`;

        let response_text = http_get_with_headers(url, get_headers());
        let response = json_parse(response_text);

        if response == () || !response.contains("chapters") {
            break;
        }

        let chapter_list = response["chapters"];
        if chapter_list.len() == 0 {
            break;
        }

        for chapter in chapter_list {
            let ch_hid = chapter["hid"];

            // Build chapter number string
            let ch_num = "";
            if chapter.contains("chap") && chapter["chap"] != () {
                ch_num = chapter["chap"];
            }

            // Get title
            let title = chapter["title"];

            // Get volume
            let volume = ();
            if chapter.contains("vol") && chapter["vol"] != () {
                volume = chapter["vol"];
            }

            // Get scanlator
            let scanlator = ();
            if chapter.contains("group_name") {
                let groups = chapter["group_name"];
                if groups.is_array() && groups.len() > 0 {
                    scanlator = groups[0];
                }
            }

            // Get upload date (unix timestamp)
            let published_at = ();
            if chapter.contains("created_at") {
                published_at = chapter["created_at"];
            }

            chapters.push(#{
                id: ch_hid,
                series_id: series_id,
                number: ch_num,
                title: title,
                volume: volume,
                language: chapter["lang"],
                scanlator: scanlator,
                url: `${SITE_URL}/comic/${series_id}/${ch_hid}`,
                published_at: published_at,
                page_count: (),
                extra: #{}
            });
        }

        // Check if there are more pages
        if chapter_list.len() < limit {
            break;
        }

        page += 1;

        // Safety limit
        if page > 100 {
            break;
        }
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = `${BASE_URL}/chapter/${chapter_id}?tachiyomi=true`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    if response == () || !response.contains("chapter") {
        return [];
    }

    let chapter = response["chapter"];
    let pages = [];
    let idx = 0;

    if chapter.contains("md_images") {
        for img in chapter["md_images"] {
            let img_url = "";
            if img.contains("b2key") {
                img_url = `${CDN_URL}/${img["b2key"]}`;
            }

            if img_url != "" {
                pages.push(#{
                    index: idx,
                    url: img_url,
                    headers: #{
                        "Referer": SITE_URL
                    },
                    referer: SITE_URL
                });
                idx += 1;
            }
        }
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let url = `${BASE_URL}/v1.0/search?sort=uploaded&page=${page}&limit=25&tachiyomi=true`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    let series = [];

    if response == () || !response.is_array() {
        return #{ series: [], has_more: false };
    }

    for comic in response {
        let id = comic["hid"];
        let slug = comic["slug"];
        let title = comic["title"];

        series.push(#{
            id: id,
            title: title,
            url: `${SITE_URL}/comic/${slug}`,
            cover_url: get_cover_url(comic),
            updated_at: comic["updated_at"]
        });
    }

    let has_more = response.len() >= 25;

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    let url = `${BASE_URL}/v1.0/search?sort=follow&page=${page}&limit=25&tachiyomi=true`;

    let response_text = http_get_with_headers(url, get_headers());
    let response = json_parse(response_text);

    let series = [];

    if response == () || !response.is_array() {
        return #{ series: [], has_more: false };
    }

    for comic in response {
        let id = comic["hid"];
        let slug = comic["slug"];
        let title = comic["title"];

        series.push(#{
            id: id,
            title: title,
            url: `${SITE_URL}/comic/${slug}`,
            cover_url: get_cover_url(comic),
            follow_count: comic["follow_count"]
        });
    }

    let has_more = response.len() >= 25;

    #{ series: series, has_more: has_more }
}
