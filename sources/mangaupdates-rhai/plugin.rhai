// MangaUpdates Metadata Provider (Rhai)
// API-based metadata provider for mangaupdates.com
// Provides detailed series information, reviews, and release tracking
//
// API Docs: https://api.mangaupdates.com/
//
// Available APIs:
//   http_get(url) -> string
//   http_post_json(url, body) -> string
//   json_parse(text) -> Dynamic
//   json_stringify(value) -> string
//   url_encode(text) -> string

const API_BASE = "https://api.mangaupdates.com/v1";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "mangaupdates-rhai",
        name: "MangaUpdates",
        base_url: API_BASE,
        language: "en",
        supported_languages: ["en"],
        requires_authentication: false,
        capability_level: "http_only",
        addon_type: "metadata"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let url = `${API_BASE}/series/search`;

    // MangaUpdates uses POST for search
    let body = #{
        search: query,
        page: page,
        perpage: 25
    };

    let response = http_post_json(url, json_stringify(body));
    let data = json_parse(response);

    let series = [];

    if data == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let results = data["results"];
    if results == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    for item in results {
        let record = item["record"];
        if record == () {
            continue;
        }

        let series_id = record["series_id"];
        let title = record["title"];
        let url = record["url"];
        let description = record["description"];
        let image = record["image"];
        let year = record["year"];
        let bayesian_rating = record["bayesian_rating"];

        // Extract cover URL - API returns image.url.original or image.url.thumb
        let cover_url = ();
        if image != () {
            let url_obj = image["url"];
            if url_obj != () {
                // url_obj is an object with original/thumb
                if type_of(url_obj) == "map" {
                    cover_url = url_obj["original"];
                    if cover_url == () {
                        cover_url = url_obj["thumb"];
                    }
                } else {
                    // Fallback if it's just a string
                    cover_url = url_obj;
                }
            }
        }

        // Extract genres
        let genres = [];
        let genre_list = record["genres"];
        if genre_list != () {
            for g in genre_list {
                let genre_name = g["genre"];
                if genre_name != () {
                    genres.push(genre_name);
                }
            }
        }

        // Extract authors
        let authors = [];
        let author_list = record["authors"];
        if author_list != () {
            for a in author_list {
                let author_name = a["name"];
                if author_name != () {
                    authors.push(author_name);
                }
            }
        }

        // Extract status
        let status = ();
        let status_val = record["status"];
        if status_val != () {
            status = status_val;
        }

        series.push(#{
            id: `${series_id}`,
            title: title,
            url: url,
            cover_url: cover_url,
            alternate_titles: [],
            authors: authors,
            artists: [],
            status: status,
            genres: genres,
            tags: [],
            description: description,
            year: year,
            rating: bayesian_rating,
            extra: #{
                mangaupdates_id: series_id
            }
        });
    }

    // Check pagination
    let total_hits = data["total_hits"];
    let has_more = results.len() >= 25 && (page * 25) < total_hits;

    #{ series: series, has_more: has_more, total: total_hits }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let series_id = id_or_url;

    // Extract ID from URL if needed
    if id_or_url.contains("mangaupdates.com") {
        // URL format: https://www.mangaupdates.com/series/xxxxx/series-name
        let parts = id_or_url.split("/series/");
        if parts.len() > 1 {
            let id_part = parts[1].split("/")[0];
            series_id = id_part;
        }
    }

    let url = `${API_BASE}/series/${series_id}`;
    let response = http_get(url);
    let data = json_parse(response);

    if data == () {
        return #{
            id: series_id,
            title: "",
            error: "Series not found"
        };
    }

    let title = data["title"];
    let description = data["description"];
    let url_link = data["url"];
    let year = data["year"];
    let bayesian_rating = data["bayesian_rating"];
    let status_in_country = data["status"];
    let licensed = data["licensed"];
    let completed = data["completed"];

    // Extract cover - API returns image.url.original or image.url.thumb
    let cover_url = ();
    let image = data["image"];
    if image != () {
        let url_obj = image["url"];
        if url_obj != () {
            if type_of(url_obj) == "map" {
                cover_url = url_obj["original"];
                if cover_url == () {
                    cover_url = url_obj["thumb"];
                }
            } else {
                cover_url = url_obj;
            }
        }
    }

    // Extract alternate titles
    let alt_titles = [];
    let associated = data["associated"];
    if associated != () {
        for a in associated {
            let alt_title = a["title"];
            if alt_title != () && alt_title != title {
                alt_titles.push(alt_title);
            }
        }
    }

    // Extract authors
    let authors = [];
    let author_list = data["authors"];
    if author_list != () {
        for a in author_list {
            let author_name = a["name"];
            let author_type = a["type"];
            if author_name != () && (author_type == () || author_type == "Author") {
                authors.push(author_name);
            }
        }
    }

    // Extract artists
    let artists = [];
    if author_list != () {
        for a in author_list {
            let artist_name = a["name"];
            let artist_type = a["type"];
            if artist_name != () && artist_type == "Artist" {
                artists.push(artist_name);
            }
        }
    }

    // Extract genres
    let genres = [];
    let genre_list = data["genres"];
    if genre_list != () {
        for g in genre_list {
            let genre_name = g["genre"];
            if genre_name != () {
                genres.push(genre_name);
            }
        }
    }

    // Extract categories/tags
    let tags = [];
    let categories = data["categories"];
    if categories != () {
        for c in categories {
            let cat_name = c["category"];
            if cat_name != () {
                tags.push(cat_name);
            }
        }
    }

    // Determine status
    let status = ();
    if completed == true {
        status = "Completed";
    } else if status_in_country != () {
        status = status_in_country;
    }

    // Extract type (manga, manhwa, etc.)
    let series_type = data["type"];

    // Extract publishers
    let publishers = [];
    let pub_list = data["publishers"];
    if pub_list != () {
        for p in pub_list {
            let pub_name = p["publisher_name"];
            if pub_name != () {
                publishers.push(pub_name);
            }
        }
    }

    #{
        id: series_id,
        title: title,
        alternate_titles: alt_titles,
        description: description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: status,
        genres: genres,
        tags: tags,
        year: year,
        content_rating: (),
        url: url_link,
        extra: #{
            mangaupdates_id: series_id,
            rating: bayesian_rating,
            type: series_type,
            licensed: licensed,
            publishers: publishers
        }
    }
}

/// Get chapters - not applicable for metadata-only source
fn get_chapters(series_id, auth) {
    []
}

/// Get chapter pages - not applicable for metadata-only source
fn get_chapter_pages(chapter_id, auth) {
    []
}

/// Get latest updates - returns popular series via search
/// MangaUpdates API releases endpoint has complex response format,
/// so we use search with "manga" to get popular/browseable results
fn get_latest_updates(page, auth) {
    // Use search_series which has correct parsing for MangaUpdates API
    search_series("manga", page, auth)
}

/// Browse popular/trending series
/// MangaUpdates API requires a search term, so we use common letter patterns
/// to get a broad selection of popular series sorted by score
fn browse(page, filters, auth) {
    // Reuse search_series with a common search term to get popular results
    // This is the cleanest way since search already handles parsing correctly
    search_series("manga", page, auth)
}

/// Get extended metadata for a series
fn get_metadata(series_id, auth) {
    // Reuse get_series since it already fetches full metadata
    get_series(series_id, auth)
}
