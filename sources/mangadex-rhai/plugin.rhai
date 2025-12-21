// MangaDex Scraper Add-on (Rhai)
// Uses the official MangaDex API v5

const BASE_URL = "https://api.mangadex.org";
const COVERS_URL = "https://uploads.mangadex.org/covers";

// --- Helper Functions ---

/// Checks if an array contains a given value.
fn array_contains(array, value) {
    for item in array {
        if item == value {
            return true;
        }
    }
    return false;
}

/// Extract title from MangaDex title object, preferring specified language.
fn extract_title(title_obj, preferred_lang) {
    if title_obj == () { return ""; }
    // Try preferred language first
    if title_obj.contains(preferred_lang) { return title_obj[preferred_lang]; }
    // Fall back to English
    if title_obj.contains("en") { return title_obj["en"]; }
    // Fall back to Japanese
    if title_obj.contains("ja") { return title_obj["ja"]; }
    // Return first available by iterating over keys
    let keys = title_obj.keys();
    if keys.len() > 0 { return title_obj[keys[0]]; }
    return "";
}

/// Extract cover URL from relationships.
fn extract_cover_url(manga_id, relationships) {
    if relationships == () { return ""; }
    for rel in relationships {
        if rel.type == "cover_art" {
            let attrs = rel.attributes;
            if attrs != () && attrs.fileName != () {
                return `${COVERS_URL}/${manga_id}/${attrs.fileName}`;
            }
        }
    }
    return "";
}

/// Extract authors and artists from relationships.
fn extract_people(relationships) {
    let people = [];
    let seen = [];
    if relationships == () { return people; }
    for rel in relationships {
        if rel.type == "author" || rel.type == "artist" {
            let attrs = rel.attributes;
            if attrs != () && attrs.name != () {
                if !array_contains(seen, attrs.name) {
                    people.push(attrs.name);
                    seen.push(attrs.name);
                }
            }
        }
    }
    return people;
}

/// Extract tags from manga data.
fn extract_tags(tags, lang) {
    let result = [];
    if tags == () { return result; }
    for tag in tags {
        let attrs = tag.attributes;
        if attrs != () && attrs.name != () {
            let tag_name = extract_title(attrs.name, lang);
            if tag_name != "" {
                result.push(tag_name);
            }
        }
    }
    return result;
}

/// Map status string to standard format.
fn map_status(status) {
    let status_map = #{
        "ongoing": "Ongoing",
        "completed": "Completed",
        "hiatus": "Hiatus",
        "cancelled": "Cancelled"
    };
    if status_map.contains(status) {
        return status_map[status];
    }
    return status;
}

/// Builds a series object from MangaDex manga data.
fn build_series_result(manga, preferred_lang) {
    let id = manga.id;
    let attrs = manga.attributes;
    let rels = manga.relationships;
    let title = extract_title(attrs.title, preferred_lang);

    // Extract alternate titles
    let alt_titles = [];
    if attrs.altTitles != () {
        for alt in attrs.altTitles {
            for key in alt.keys() {
                let alt_title = alt[key];
                if alt_title != title && !array_contains(alt_titles, alt_title) {
                    alt_titles.push(alt_title);
                }
            }
        }
    }

    // Extract description
    let description = "";
    if attrs.description != () {
        description = extract_title(attrs.description, preferred_lang);
    }
    
    return #{
        id: id,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: extract_cover_url(id, rels),
        authors: extract_people(rels),
        artists: [], // MangaDex API combines authors and artists
        status: map_status(attrs.status),
        genres: extract_tags(attrs.tags, preferred_lang),
        tags: [],
        year: attrs.year,
        content_rating: attrs.contentRating,
        url: `https://mangadex.org/title/${id}`,
        extra: #{
            original_language: attrs.originalLanguage,
            last_chapter: attrs.lastChapter,
            last_volume: attrs.lastVolume,
            demographic: attrs.publicationDemographic
        }
    };
}


// --- Addon Interface Functions ---

/// Returns metadata about this source.
fn get_source_info() {
    #{
        id: "mangadex-rhai",
        name: "MangaDex",
        base_url: BASE_URL,
        language: "en",
        supported_languages: ["en", "ja", "ko", "zh", "es", "fr", "de", "it", "pt-br", "ru"],
        requires_authentication: false,
        capability_level: "http_only"
    }
}

/// Search for series matching a query.
/// Note: 'settings' is injected as a scope variable by the host
fn search_series(query, page, auth) {
    let offset = (page - 1) * 25;
    let preferred_lang = if settings.preferred_language != () { settings.preferred_language } else { "en" };
    let rating = if settings.content_rating != () { settings.content_rating } else { "safe" };

    let url = `${BASE_URL}/manga?title=${url_encode(query)}&limit=25&offset=${offset}&includes[]=cover_art&includes[]=author&includes[]=artist&contentRating[]=${rating}`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response.result != "ok" {
        return #{ series: [], has_more: false, total: 0 };
    }

    let series = [];
    for manga in response.data {
        series.push(build_series_result(manga, preferred_lang));
    }

    let total = response.total;
    let has_more = offset + 25 < total;

    return #{ series: series, has_more: has_more, total: total };
}

/// Get detailed series information.
fn get_series_details(id_or_url, auth) {
    let id = id_or_url;
    // Basic URL extraction
    if id_or_url.contains("mangadex.org/title/") {
        id = id_or_url.split("/")[4];
    }

    let preferred_lang = if settings.preferred_language != () { settings.preferred_language } else { "en" };
    let url = `${BASE_URL}/manga/${id}?includes[]=cover_art&includes[]=author&includes[]=artist`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response.result != "ok" {
        throw `Failed to fetch manga with ID: ${id}`;
    }

    return build_series_result(response.data, preferred_lang);
}

/// Get all chapters for a series.
fn get_chapters(series_id, auth) {
    let chapters = [];
    let offset = 0;
    let limit = 500; // Max limit for this endpoint
    let lang = if settings.preferred_language != () { settings.preferred_language } else { "en" };

    while true {
        let url = `${BASE_URL}/manga/${series_id}/feed?limit=${limit}&offset=${offset}&translatedLanguage[]=${lang}&order[chapter]=desc&includes[]=scanlation_group`;

        let response_text = http_get(url);
        let response = json_parse(response_text);

        if response.result != "ok" || response.data.len() == 0 {
            break;
        }

        for chapter_data in response.data {
            let attrs = chapter_data.attributes;
            let rels = chapter_data.relationships;

            let scanlator = "";
            if rels != () {
                for rel in rels {
                    if rel.type == "scanlation_group" {
                        if rel.attributes != () && rel.attributes.name != () {
                            scanlator = rel.attributes.name;
                            break;
                        }
                    }
                }
            }

            chapters.push(#{
                id: chapter_data.id,
                series_id: series_id,
                number: attrs.chapter,
                title: attrs.title,
                volume: attrs.volume,
                language: attrs.translatedLanguage,
                scanlator: scanlator,
                url: `https://mangadex.org/chapter/${chapter_data.id}`,
                published_at: attrs.publishAt,
                page_count: attrs.pages,
                extra: #{
                    external_url: attrs.externalUrl
                }
            });
        }

        offset += limit;
        if offset >= response.total {
            break;
        }
        // Safety break for unexpected API behavior
        if offset >= 10000 { 
            break; 
        }
    }
    return chapters;
}

/// Get page URLs for a chapter.
fn get_chapter_pages(chapter_id, auth) {
    let url = `${BASE_URL}/at-home/server/${chapter_id}`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response.result != "ok" {
        return [];
    }

    let server_base_url = response.baseUrl;
    let chapter_data = response.chapter;
    let hash = chapter_data.hash;
    
    let pages = [];
    let i = 0;
    for filename in chapter_data.data {
        pages.push(#{
            index: i,
            url: `${server_base_url}/data/${hash}/${filename}`,
            headers: #{},
            referer: "https://mangadex.org/"
        });
        i += 1;
    }
    return pages;
}

/// Get latest updates (for browse).
fn get_latest_updates(page, auth) {
    let offset = (page - 1) * 25;
    let preferred_lang = if settings.preferred_language != () { settings.preferred_language } else { "en" };
    let rating = if settings.content_rating != () { settings.content_rating } else { "safe" };

    let url = `${BASE_URL}/manga?limit=25&offset=${offset}&includes[]=cover_art&includes[]=author&includes[]=artist&order[updatedAt]=desc&contentRating[]=${rating}`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response.result != "ok" {
        return #{ series: [], has_more: false };
    }

    let series = [];
    for manga in response.data {
        series.push(build_series_result(manga, preferred_lang));
    }

    let has_more = offset + 25 < response.total;
    return #{ series: series, has_more: has_more, total: response.total };
}

/// Get popular manga (alternative browse).
fn get_popular(page, auth) {
    let offset = (page - 1) * 25;
    let preferred_lang = if settings.preferred_language != () { settings.preferred_language } else { "en" };
    let rating = if settings.content_rating != () { settings.content_rating } else { "safe" };

    let url = `${BASE_URL}/manga?limit=25&offset=${offset}&includes[]=cover_art&includes[]=author&includes[]=artist&order[followedCount]=desc&contentRating[]=${rating}`;

    let response_text = http_get(url);
    let response = json_parse(response_text);

    if response.result != "ok" {
        return [];
    }

    let series = [];
    for manga in response.data {
        series.push(build_series_result(manga, preferred_lang));
    }

    return series;
}