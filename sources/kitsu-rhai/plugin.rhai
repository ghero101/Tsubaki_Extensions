// Kitsu Metadata Provider (Rhai)
// JSON:API based metadata provider for kitsu.io
// Provides manga metadata, ratings, and social features
//
// API Docs: https://kitsu.docs.apiary.io/
//
// Available APIs:
//   http_get(url) -> string
//   json_parse(text) -> Dynamic
//   url_encode(text) -> string

const API_BASE = "https://kitsu.io/api/edge";

/// Returns metadata about this source
fn get_source_info() {
    #{
        id: "kitsu-rhai",
        name: "Kitsu",
        base_url: API_BASE,
        language: "en",
        supported_languages: ["en", "ja"],
        requires_authentication: false,
        capability_level: "http_only",
        addon_type: "metadata"
    }
}

/// Get headers for Kitsu API
fn get_headers() {
    #{
        "Accept": "application/vnd.api+json",
        "Content-Type": "application/vnd.api+json"
    }
}

/// Search for series matching query
fn search_series(query, page, auth) {
    let encoded_query = url_encode(query);
    let offset = (page - 1) * 20;
    let url = `${API_BASE}/manga?filter[text]=${encoded_query}&page[limit]=20&page[offset]=${offset}`;

    let response = http_get_with_headers(url, get_headers());
    let data = json_parse(response);

    let series = [];

    if data == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    let results = data["data"];
    if results == () {
        return #{ series: [], has_more: false, total: 0 };
    }

    for item in results {
        let id = item["id"];
        let attributes = item["attributes"];

        if attributes == () {
            continue;
        }

        // Get titles
        let titles = attributes["titles"];
        let title = attributes["canonicalTitle"];
        if title == () && titles != () {
            title = titles["en"];
            if title == () {
                title = titles["en_jp"];
            }
            if title == () {
                title = titles["ja_jp"];
            }
        }

        if title == () || title == "" {
            continue;
        }

        // Get alternate titles
        let alt_titles = [];
        if titles != () {
            for key in titles.keys() {
                let alt = titles[key];
                if alt != () && alt != title && !alt_titles.contains(alt) {
                    alt_titles.push(alt);
                }
            }
        }

        // Get cover image
        let cover_url = ();
        let poster = attributes["posterImage"];
        if poster != () {
            cover_url = poster["large"];
            if cover_url == () {
                cover_url = poster["medium"];
            }
            if cover_url == () {
                cover_url = poster["original"];
            }
        }

        // Get description
        let description = attributes["synopsis"];

        // Get status
        let status = attributes["status"];
        if status == "current" {
            status = "Ongoing";
        } else if status == "finished" {
            status = "Completed";
        } else if status == "tba" {
            status = "TBA";
        } else if status == "unreleased" {
            status = "Unreleased";
        } else if status == "upcoming" {
            status = "Upcoming";
        }

        // Get year
        let year = ();
        let start_date = attributes["startDate"];
        if start_date != () && start_date.len() >= 4 {
            year = start_date.sub_string(0, 4);
        }

        // Get rating
        let rating = attributes["averageRating"];

        // Get manga subtype
        let subtype = attributes["subtype"];

        series.push(#{
            id: id,
            title: title,
            url: `https://kitsu.io/manga/${attributes["slug"]}`,
            cover_url: cover_url,
            alternate_titles: alt_titles,
            authors: [],
            artists: [],
            status: status,
            genres: [],
            tags: [],
            description: description,
            year: year,
            extra: #{
                kitsu_id: id,
                rating: rating,
                subtype: subtype
            }
        });
    }

    // Check pagination
    let meta = data["meta"];
    let total = 0;
    if meta != () {
        let count = meta["count"];
        if count != () {
            total = count;
        }
    }

    let has_more = results.len() >= 20 && offset + 20 < total;

    #{ series: series, has_more: has_more, total: total }
}

/// Get detailed series information
fn get_series(id_or_url, auth) {
    let manga_id = id_or_url;

    // Extract ID from URL if needed
    if id_or_url.contains("kitsu.io") {
        // URL format: https://kitsu.io/manga/slug
        let parts = id_or_url.split("/manga/");
        if parts.len() > 1 {
            let slug = parts[1].split("/")[0].split("?")[0];
            // Need to search by slug
            let search_url = `${API_BASE}/manga?filter[slug]=${slug}`;
            let search_resp = http_get_with_headers(search_url, get_headers());
            let search_data = json_parse(search_resp);
            if search_data != () {
                let search_results = search_data["data"];
                if search_results != () && search_results.len() > 0 {
                    manga_id = search_results[0]["id"];
                }
            }
        }
    }

    // Fetch manga with relationships
    let url = `${API_BASE}/manga/${manga_id}?include=genres,categories,staff,staff.person`;
    let response = http_get_with_headers(url, get_headers());
    let data = json_parse(response);

    if data == () {
        return #{
            id: manga_id,
            title: "",
            error: "Series not found"
        };
    }

    let manga = data["data"];
    if manga == () {
        return #{
            id: manga_id,
            title: "",
            error: "Series not found"
        };
    }

    let attributes = manga["attributes"];
    if attributes == () {
        return #{
            id: manga_id,
            title: "",
            error: "Invalid data"
        };
    }

    // Get titles
    let titles = attributes["titles"];
    let title = attributes["canonicalTitle"];
    if title == () && titles != () {
        title = titles["en"];
        if title == () {
            title = titles["en_jp"];
        }
    }

    // Get alternate titles
    let alt_titles = [];
    if titles != () {
        for key in titles.keys() {
            let alt = titles[key];
            if alt != () && alt != title && !alt_titles.contains(alt) {
                alt_titles.push(alt);
            }
        }
    }

    // Add abbreviated titles
    let abbrev_titles = attributes["abbreviatedTitles"];
    if abbrev_titles != () {
        for abbrev in abbrev_titles {
            if abbrev != () && abbrev != title && !alt_titles.contains(abbrev) {
                alt_titles.push(abbrev);
            }
        }
    }

    // Get cover image
    let cover_url = ();
    let poster = attributes["posterImage"];
    if poster != () {
        cover_url = poster["large"];
        if cover_url == () {
            cover_url = poster["original"];
        }
    }

    // Get description
    let description = attributes["synopsis"];

    // Get status
    let status = attributes["status"];
    if status == "current" {
        status = "Ongoing";
    } else if status == "finished" {
        status = "Completed";
    } else if status == "tba" {
        status = "TBA";
    }

    // Get year
    let year = ();
    let start_date = attributes["startDate"];
    if start_date != () && start_date.len() >= 4 {
        year = start_date.sub_string(0, 4);
    }

    // Get rating
    let rating = attributes["averageRating"];

    // Get manga subtype
    let subtype = attributes["subtype"];

    // Get chapter/volume count
    let chapter_count = attributes["chapterCount"];
    let volume_count = attributes["volumeCount"];

    // Get age rating
    let age_rating = attributes["ageRating"];
    let age_rating_guide = attributes["ageRatingGuide"];

    // Process included relationships for genres and staff
    let genres = [];
    let tags = [];
    let authors = [];
    let artists = [];

    let included = data["included"];
    if included != () {
        for inc in included {
            let inc_type = inc["type"];
            let inc_attrs = inc["attributes"];

            if inc_type == "genres" && inc_attrs != () {
                let genre_name = inc_attrs["name"];
                if genre_name != () {
                    genres.push(genre_name);
                }
            } else if inc_type == "categories" && inc_attrs != () {
                let cat_name = inc_attrs["title"];
                if cat_name != () {
                    tags.push(cat_name);
                }
            }
        }
    }

    // Determine content rating
    let content_rating = "safe";
    if age_rating == "R" || age_rating == "R18" {
        content_rating = "explicit";
    } else if age_rating == "PG" || age_rating == "PG-13" {
        content_rating = "suggestive";
    }

    #{
        id: manga_id,
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
        content_rating: content_rating,
        url: `https://kitsu.io/manga/${attributes["slug"]}`,
        extra: #{
            kitsu_id: manga_id,
            rating: rating,
            subtype: subtype,
            chapter_count: chapter_count,
            volume_count: volume_count,
            age_rating: age_rating,
            age_rating_guide: age_rating_guide
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

/// Get latest updates - returns trending manga
fn get_latest_updates(page, auth) {
    // Use updatedAt sort for latest updates (trending only returns ~10 items)
    let offset = (page - 1) * 20;
    let url = `${API_BASE}/manga?sort=-updatedAt&page[limit]=20&page[offset]=${offset}`;

    let response = http_get_with_headers(url, get_headers());
    let data = json_parse(response);

    let series = [];

    if data == () {
        return #{ series: [], has_more: false };
    }

    let results = data["data"];
    if results == () {
        return #{ series: [], has_more: false };
    }

    for item in results {
        let id = item["id"];
        let attributes = item["attributes"];

        if attributes == () {
            continue;
        }

        let title = attributes["canonicalTitle"];
        let slug = attributes["slug"];

        // Get cover
        let cover_url = ();
        let poster = attributes["posterImage"];
        if poster != () {
            cover_url = poster["medium"];
            if cover_url == () {
                cover_url = poster["original"];
            }
        }

        if title != () {
            series.push(#{
                id: id,
                title: title,
                url: `https://kitsu.io/manga/${slug}`,
                cover_url: cover_url,
                updated_at: ()
            });
        }
    }

    let has_more = results.len() >= 20;

    #{ series: series, has_more: has_more }
}

/// Get popular series
fn get_popular(page, auth) {
    let offset = (page - 1) * 20;
    let url = `${API_BASE}/manga?sort=-userCount&page[limit]=20&page[offset]=${offset}`;

    let response = http_get_with_headers(url, get_headers());
    let data = json_parse(response);

    let series = [];

    if data == () {
        return #{ series: [], has_more: false };
    }

    let results = data["data"];
    if results == () {
        return #{ series: [], has_more: false };
    }

    for item in results {
        let id = item["id"];
        let attributes = item["attributes"];

        if attributes == () {
            continue;
        }

        let title = attributes["canonicalTitle"];
        let slug = attributes["slug"];

        // Get cover
        let cover_url = ();
        let poster = attributes["posterImage"];
        if poster != () {
            cover_url = poster["medium"];
        }

        if title != () {
            series.push(#{
                id: id,
                title: title,
                url: `https://kitsu.io/manga/${slug}`,
                cover_url: cover_url
            });
        }
    }

    let has_more = results.len() >= 20;

    #{ series: series, has_more: has_more }
}
