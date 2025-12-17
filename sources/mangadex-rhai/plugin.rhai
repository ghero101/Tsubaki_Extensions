// MangaDex Scraper Add-on (Rhai)
// Uses the official MangaDex API v5
//
// Available APIs:
//   http_get(url) -> string
//   http_get_with_headers(url, headers) -> string
//   json_parse(text) -> Dynamic
//   json_stringify(value) -> string

const BASE_URL = "https://api.mangadex.org";
const COVERS_URL = "https://uploads.mangadex.org/covers";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangadex-rhai",
        name: "MangaDex (Rhai)",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en", "ja", "ko", "zh", "es", "fr", "de", "it", "pt-br", "ru"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Extract title from MangaDex title object, preferring specified language
fn extract_title(title_obj, preferred_lang) {
    // Try preferred language first
    if title_obj.contains(preferred_lang) {
        return title_obj[preferred_lang];
    }
    // Fall back to English
    if title_obj.contains("en") {
        return title_obj["en"];
    }
    // Fall back to Japanese
    if title_obj.contains("ja") {
        return title_obj["ja"];
    }
    // Return first available
    for key in title_obj.keys() {
        return title_obj[key];
    }
    ""
}

/// Extract cover URL from relationships
fn extract_cover_url(manga_id, relationships) {
    for rel in relationships {
        if rel["type"] == "cover_art" {
            let attrs = rel["attributes"];
            if attrs != () && attrs.contains("fileName") {
                return `${COVERS_URL}/${manga_id}/${attrs["fileName"]}`;
            }
        }
    }
    ()
}

/// Extract authors from relationships
fn extract_authors(relationships) {
    let authors = [];
    for rel in relationships {
        if rel["type"] == "author" || rel["type"] == "artist" {
            let attrs = rel["attributes"];
            if attrs != () && attrs.contains("name") {
                let name = attrs["name"];
                if !authors.contains(name) {
                    authors.push(name);
                }
            }
        }
    }
    authors
}

/// Extract tags from manga data
fn extract_tags(tags, lang) {
    let result = [];
    for tag in tags {
        let attrs = tag["attributes"];
        if attrs != () && attrs.contains("name") {
            let name_obj = attrs["name"];
            let tag_name = extract_title(name_obj, lang);
            if tag_name != "" {
                result.push(tag_name);
            }
        }
    }
    result
}

/// Map status string to standard format
fn map_status(status) {
    switch status {
        "ongoing" => "Ongoing",
        "completed" => "Completed",
        "hiatus" => "Hiatus",
        "cancelled" => "Cancelled",
        _ => status
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let offset = (page - 1) * 25;
    let url = `${BASE_URL}/manga?title=${query}&limit=25&offset=${offset}&includes[]=cover_art&includes[]=author&includes[]=artist`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response["result"] != "ok" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let data = response["data"];
    let total = response["total"];
    let series = [];

    for manga in data {
        let id = manga["id"];
        let attrs = manga["attributes"];
        let rels = manga["relationships"];

        // Extract title
        let title = extract_title(attrs["title"], "en");

        // Extract alternate titles
        let alt_titles = [];
        for alt in attrs["altTitles"] {
            for lang in alt.keys() {
                let alt_title = alt[lang];
                if alt_title != title && !alt_titles.contains(alt_title) {
                    alt_titles.push(alt_title);
                }
            }
        }

        // Extract description
        let description = ();
        if attrs.contains("description") && attrs["description"].contains("en") {
            description = attrs["description"]["en"];
        }

        series.push(#{
            id: id,
            title: title,
            url: `https://mangadex.org/title/${id}`,
            cover_url: extract_cover_url(id, rels),
            alternate_titles: alt_titles,
            authors: extract_authors(rels),
            artists: [],
            status: map_status(attrs["status"]),
            genres: extract_tags(attrs["tags"], "en"),
            tags: [],
            description: description
        });
    }

    let has_more = offset + 25 < total;

    #{ series: series, has_more: has_more, total: total }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    // Extract ID from URL if needed
    let id = id_or_url;
    if id_or_url.contains("mangadex.org") {
        let parts = id_or_url.split("/");
        for i in 0..parts.len() {
            if parts[i] == "title" && i + 1 < parts.len() {
                id = parts[i + 1];
                break;
            }
        }
    }

    let url = `${BASE_URL}/manga/${id}?includes[]=cover_art&includes[]=author&includes[]=artist`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response["result"] != "ok" {
        return #{
            id: id,
            title: "",
            error: "Failed to fetch manga"
        };
    }

    let manga = response["data"];
    let attrs = manga["attributes"];
    let rels = manga["relationships"];

    let title = extract_title(attrs["title"], "en");

    // Extract alternate titles
    let alt_titles = [];
    for alt in attrs["altTitles"] {
        for lang in alt.keys() {
            let alt_title = alt[lang];
            if alt_title != title && !alt_titles.contains(alt_title) {
                alt_titles.push(alt_title);
            }
        }
    }

    // Extract description
    let description = ();
    if attrs.contains("description") && attrs["description"].contains("en") {
        description = attrs["description"]["en"];
    }

    #{
        id: id,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: extract_cover_url(id, rels),
        authors: extract_authors(rels),
        artists: [],
        status: map_status(attrs["status"]),
        genres: extract_tags(attrs["tags"], "en"),
        tags: [],
        year: attrs["year"],
        content_rating: attrs["contentRating"],
        url: `https://mangadex.org/title/${id}`,
        extra: #{
            original_language: attrs["originalLanguage"],
            last_chapter: attrs["lastChapter"],
            last_volume: attrs["lastVolume"],
            demographic: attrs["publicationDemographic"]
        }
    }
}

/// Get all chapters for a series
fn get_chapters(series_id, auth) {
    let chapters = [];
    let offset = 0;
    let limit = 100;

    loop {
        let url = `${BASE_URL}/manga/${series_id}/feed?limit=${limit}&offset=${offset}&translatedLanguage[]=en&order[chapter]=desc&includes[]=scanlation_group`;

        let response_text = http_get(url);
        let response = json_parse(response_text);

        if response["result"] != "ok" {
            break;
        }

        let data = response["data"];
        if data.len() == 0 {
            break;
        }

        for chapter in data {
            let id = chapter["id"];
            let attrs = chapter["attributes"];
            let rels = chapter["relationships"];

            // Extract scanlation group
            let scanlator = ();
            for rel in rels {
                if rel["type"] == "scanlation_group" {
                    let rel_attrs = rel["attributes"];
                    if rel_attrs != () && rel_attrs.contains("name") {
                        scanlator = rel_attrs["name"];
                        break;
                    }
                }
            }

            chapters.push(#{
                id: id,
                series_id: series_id,
                number: attrs["chapter"],
                title: attrs["title"],
                volume: attrs["volume"],
                language: attrs["translatedLanguage"],
                scanlator: scanlator,
                url: `https://mangadex.org/chapter/${id}`,
                published_at: attrs["publishAt"],
                page_count: attrs["pages"],
                extra: #{
                    external_url: attrs["externalUrl"]
                }
            });
        }

        offset += limit;

        // Prevent infinite loops
        if offset >= 10000 {
            break;
        }
    }

    chapters
}

/// Get page URLs for a chapter
fn get_chapter_pages(chapter_id, auth) {
    let url = `${BASE_URL}/at-home/server/${chapter_id}`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response["result"] != "ok" {
        return [];
    }

    let base_url = response["baseUrl"];
    let chapter_data = response["chapter"];
    let hash = chapter_data["hash"];
    let data_pages = chapter_data["data"];

    let pages = [];
    let idx = 0;

    for filename in data_pages {
        pages.push(#{
            index: idx,
            url: `${base_url}/data/${hash}/${filename}`,
            headers: #{},
            referer: "https://mangadex.org/"
        });
        idx += 1;
    }

    pages
}

/// Get latest updates
fn get_latest_updates(page, auth) {
    let offset = (page - 1) * 25;
    let url = `${BASE_URL}/manga?limit=25&offset=${offset}&includes[]=cover_art&order[updatedAt]=desc`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response["result"] != "ok" {
        return #{ series: [], has_more: false };
    }

    let data = response["data"];
    let total = response["total"];
    let series = [];

    for manga in data {
        let id = manga["id"];
        let attrs = manga["attributes"];
        let rels = manga["relationships"];

        series.push(#{
            id: id,
            title: extract_title(attrs["title"], "en"),
            url: `https://mangadex.org/title/${id}`,
            cover_url: extract_cover_url(id, rels),
            updated_at: attrs["updatedAt"]
        });
    }

    #{ series: series, has_more: offset + 25 < total }
}
