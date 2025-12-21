// MyAnimeList Metadata Provider
// Built-in addon for Tsubaki - provides manga metadata via Jikan API (unofficial MAL API)

const BASE_URL = "https://api.jikan.moe/v4";

// Get source information
fn get_source_info() {
    #{
        id: "myanimelist",
        name: "MyAnimeList",
        base_url: "https://myanimelist.net",
        language: "en",
        supported_languages: ["en", "ja"],
        requires_authentication: false,
        is_metadata_provider: true
    }
}

// Normalize string for comparison (lowercase, alphanumeric only)
fn normalize(s) {
    let result = "";
    for ch in s.to_lower().chars() {
        if ch.is_alphanumeric() {
            result += ch;
        }
    }
    result
}

// Search for manga series
fn search_series(query, page, auth) {
    let url = `${BASE_URL}/manga?q=${url_encode(query)}&page=${page}&limit=20`;
    let response = http_get(url);
    let json = json_parse(response);

    let series = [];

    if json.data != () {
        for item in json.data {
            let alt_titles = [];
            if item.title_english != () && item.title_english != item.title {
                alt_titles.push(item.title_english);
            }
            if item.title_japanese != () {
                alt_titles.push(item.title_japanese);
            }

            let cover_url = "";
            if item.images != () && item.images.jpg != () {
                if item.images.jpg.large_image_url != () {
                    cover_url = item.images.jpg.large_image_url;
                } else if item.images.jpg.image_url != () {
                    cover_url = item.images.jpg.image_url;
                }
            }

            // Extract genres
            let genres = [];
            if item.genres != () {
                for g in item.genres {
                    genres.push(g.name);
                }
            }

            // Map MAL rating to standard format
            let rating = "safe";
            if item.rating != () {
                let mal_rating = item.rating.to_lower();
                if mal_rating.contains("rx") || mal_rating.contains("hentai") {
                    rating = "adult";
                } else if mal_rating.contains("r+") || mal_rating.contains("r -") {
                    rating = "mature";
                } else if mal_rating.contains("pg-13") {
                    rating = "suggestive";
                }
            }

            // Extract authors
            let authors = [];
            if item.authors != () {
                for a in item.authors {
                    authors.push(a.name);
                }
            }

            series.push(#{
                id: `${item.mal_id}`,
                title: item.title,
                alternate_titles: alt_titles,
                description: item.synopsis,
                cover_url: cover_url,
                authors: authors,
                artists: [],
                status: item.status,
                genres: genres,
                tags: [],
                year: item.published.prop.from.year,
                content_rating: rating,
                url: item.url
            });
        }
    }

    let has_more = false;
    if json.pagination != () {
        has_more = json.pagination.has_next_page;
    }

    #{
        series: series,
        has_more: has_more,
        total: if json.pagination != () { json.pagination.items.total } else { 0 },
        current_page: page
    }
}

// Get detailed series information by ID
fn get_series(id_or_url, auth) {
    // Extract ID from URL if needed
    let id = id_or_url;
    if id_or_url.contains("myanimelist.net/manga/") {
        let parts = id_or_url.split("/manga/");
        if parts.len() > 1 {
            id = parts[1].split("/")[0];
        }
    }

    let url = `${BASE_URL}/manga/${id}/full`;
    let response = http_get(url);
    let json = json_parse(response);

    if json.data == () {
        return ();
    }

    let item = json.data;

    let alt_titles = [];
    if item.title_english != () && item.title_english != item.title {
        alt_titles.push(item.title_english);
    }
    if item.title_japanese != () {
        alt_titles.push(item.title_japanese);
    }
    // Add title synonyms
    if item.title_synonyms != () {
        for syn in item.title_synonyms {
            alt_titles.push(syn);
        }
    }

    let cover_url = "";
    if item.images != () && item.images.jpg != () {
        if item.images.jpg.large_image_url != () {
            cover_url = item.images.jpg.large_image_url;
        } else if item.images.jpg.image_url != () {
            cover_url = item.images.jpg.image_url;
        }
    }

    // Extract genres
    let genres = [];
    if item.genres != () {
        for g in item.genres {
            genres.push(g.name);
        }
    }

    // Extract themes as tags
    let tags = [];
    if item.themes != () {
        for t in item.themes {
            tags.push(t.name);
        }
    }
    if item.demographics != () {
        for d in item.demographics {
            tags.push(d.name);
        }
    }

    // Map MAL rating to standard format
    let rating = "safe";
    if item.rating != () {
        let mal_rating = item.rating.to_lower();
        if mal_rating.contains("rx") || mal_rating.contains("hentai") {
            rating = "adult";
        } else if mal_rating.contains("r+") || mal_rating.contains("r -") {
            rating = "mature";
        } else if mal_rating.contains("pg-13") {
            rating = "suggestive";
        }
    }

    // Extract authors and artists
    let authors = [];
    let artists = [];
    if item.authors != () {
        for a in item.authors {
            authors.push(a.name);
        }
    }

    // Get publication year
    let year = ();
    if item.published != () && item.published.prop != () && item.published.prop.from != () {
        year = item.published.prop.from.year;
    }

    #{
        id: `${item.mal_id}`,
        title: item.title,
        alternate_titles: alt_titles,
        description: item.synopsis,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: item.status,
        genres: genres,
        tags: tags,
        year: year,
        content_rating: rating,
        url: item.url,
        extra: #{
            volumes: item.volumes,
            chapters: item.chapters,
            score: item.score,
            scored_by: item.scored_by,
            rank: item.rank,
            popularity: item.popularity,
            provider: "mal",
            provider_id: `${item.mal_id}`
        }
    }
}

// Get latest/trending manga (for browse)
fn get_latest_updates(page, auth) {
    // Jikan API: order by start_date descending for recent manga
    let url = `${BASE_URL}/manga?order_by=start_date&sort=desc&page=${page + 1}&limit=25`;

    let response = http_get(url);
    let json = json_parse(response);

    let series = [];

    if json == () || json["data"] == () {
        return #{ series: [], has_more: false, total: () };
    }

    let data = json["data"];

    for item in data {
        let alt_titles = [];
        if item["title_english"] != () && item["title_english"] != item["title"] {
            alt_titles.push(item["title_english"]);
        }
        if item["title_japanese"] != () {
            alt_titles.push(item["title_japanese"]);
        }

        let cover_url = "";
        if item["images"] != () && item["images"]["jpg"] != () {
            if item["images"]["jpg"]["large_image_url"] != () {
                cover_url = item["images"]["jpg"]["large_image_url"];
            } else if item["images"]["jpg"]["image_url"] != () {
                cover_url = item["images"]["jpg"]["image_url"];
            }
        }

        // Extract genres
        let genres = [];
        if item["genres"] != () {
            for g in item["genres"] {
                genres.push(g["name"]);
            }
        }

        // Map MAL rating to standard format
        let rating = "safe";
        if item["rating"] != () {
            let mal_rating = item["rating"].to_lower();
            if mal_rating.contains("rx") || mal_rating.contains("hentai") {
                rating = "adult";
            } else if mal_rating.contains("r+") || mal_rating.contains("r -") {
                rating = "mature";
            } else if mal_rating.contains("pg-13") {
                rating = "suggestive";
            }
        }

        // Extract authors
        let authors = [];
        if item["authors"] != () {
            for a in item["authors"] {
                authors.push(a["name"]);
            }
        }

        // Get publication year
        let year = ();
        if item["published"] != () && item["published"]["prop"] != () && item["published"]["prop"]["from"] != () {
            year = item["published"]["prop"]["from"]["year"];
        }

        series.push(#{
            id: item["mal_id"].to_string(),
            title: item["title"],
            alternate_titles: alt_titles,
            description: item["synopsis"],
            cover_url: cover_url,
            authors: authors,
            artists: [],
            status: item["status"],
            genres: genres,
            tags: [],
            year: year,
            content_rating: rating,
            url: item["url"]
        });
    }

    let has_more = false;
    if json["pagination"] != () {
        has_more = json["pagination"]["has_next_page"];
    }

    #{
        series: series,
        has_more: has_more,
        total: if json["pagination"] != () { json["pagination"]["items"]["total"] } else { () }
    }
}

// Get popular manga
fn get_popular(page, auth) {
    // Jikan API: order by score descending for top rated manga
    let url = `${BASE_URL}/manga?order_by=score&sort=desc&page=${page + 1}&limit=25&min_score=1`;

    let response = http_get(url);
    let json = json_parse(response);

    let series = [];

    if json == () || json["data"] == () {
        return #{ series: [], has_more: false, total: () };
    }

    let data = json["data"];

    for item in data {
        let alt_titles = [];
        if item["title_english"] != () && item["title_english"] != item["title"] {
            alt_titles.push(item["title_english"]);
        }
        if item["title_japanese"] != () {
            alt_titles.push(item["title_japanese"]);
        }

        let cover_url = "";
        if item["images"] != () && item["images"]["jpg"] != () {
            if item["images"]["jpg"]["large_image_url"] != () {
                cover_url = item["images"]["jpg"]["large_image_url"];
            } else if item["images"]["jpg"]["image_url"] != () {
                cover_url = item["images"]["jpg"]["image_url"];
            }
        }

        // Extract genres
        let genres = [];
        if item["genres"] != () {
            for g in item["genres"] {
                genres.push(g["name"]);
            }
        }

        // Map MAL rating to standard format
        let rating = "safe";
        if item["rating"] != () {
            let mal_rating = item["rating"].to_lower();
            if mal_rating.contains("rx") || mal_rating.contains("hentai") {
                rating = "adult";
            } else if mal_rating.contains("r+") || mal_rating.contains("r -") {
                rating = "mature";
            } else if mal_rating.contains("pg-13") {
                rating = "suggestive";
            }
        }

        // Extract authors
        let authors = [];
        if item["authors"] != () {
            for a in item["authors"] {
                authors.push(a["name"]);
            }
        }

        // Get publication year
        let year = ();
        if item["published"] != () && item["published"]["prop"] != () && item["published"]["prop"]["from"] != () {
            year = item["published"]["prop"]["from"]["year"];
        }

        series.push(#{
            id: item["mal_id"].to_string(),
            title: item["title"],
            alternate_titles: alt_titles,
            description: item["synopsis"],
            cover_url: cover_url,
            authors: authors,
            artists: [],
            status: item["status"],
            genres: genres,
            tags: [],
            year: year,
            content_rating: rating,
            url: item["url"]
        });
    }

    let has_more = false;
    if json["pagination"] != () {
        has_more = json["pagination"]["has_next_page"];
    }

    #{
        series: series,
        has_more: has_more,
        total: if json["pagination"] != () { json["pagination"]["items"]["total"] } else { () }
    }
}

// Resolve manga title to MAL ID
fn resolve_id(title, alt_titles) {
    // Build list of candidate titles to search
    let candidates = [title];
    if alt_titles != () && alt_titles != "" {
        for alt in alt_titles.split(", ") {
            let trimmed = alt.trim();
            if trimmed != "" {
                candidates.push(trimmed);
            }
        }
    }

    for q in candidates {
        let url = `${BASE_URL}/manga?q=${url_encode(q)}&limit=5`;
        let response = http_get(url);
        let json = json_parse(response);

        if json.data != () {
            let target_norm = normalize(q);
            for item in json.data {
                let item_title = item.title;
                let mal_id = item.mal_id;

                if mal_id > 0 && item_title != "" && normalize(item_title) == target_norm {
                    return #{
                        provider: "mal",
                        provider_id: `${mal_id}`,
                        matched_title: item_title
                    };
                }
            }
        }
    }

    ()
}

// ============================================================================
// TRACKING FEATURES - Requires OAuth2 Authentication
// Uses official MAL API v2: https://myanimelist.net/apiconfig/references/api/v2
// ============================================================================

const MAL_API_URL = "https://api.myanimelist.net/v2";

// Reading status mappings
// MAL statuses: reading, completed, on_hold, dropped, plan_to_read
fn map_status_to_mal(status) {
    switch status.to_lower() {
        "reading" | "current" => "reading",
        "completed" | "finished" => "completed",
        "on_hold" | "paused" => "on_hold",
        "dropped" => "dropped",
        "plan_to_read" | "planning" | "planned" => "plan_to_read",
        _ => "reading"
    }
}

fn map_mal_status(mal_status) {
    switch mal_status {
        "reading" => "reading",
        "completed" => "completed",
        "on_hold" => "on_hold",
        "dropped" => "dropped",
        "plan_to_read" => "plan_to_read",
        _ => "unknown"
    }
}

// Get user's manga list
// auth.access_token is required (OAuth2 token)
// status_filter: "reading", "completed", "on_hold", "dropped", "plan_to_read", or () for all
fn get_user_list(status_filter, page, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required. Please connect your MyAnimeList account.", requires_auth: true };
    }

    let limit = 50;
    let offset = (page - 1) * limit;
    let url = `${MAL_API_URL}/users/@me/mangalist?fields=list_status,num_chapters,num_volumes&limit=${limit}&offset=${offset}`;

    if status_filter != () && status_filter != "" && status_filter != "all" {
        url = url + `&status=${map_status_to_mal(status_filter)}`;
    }

    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`
    };

    let response = http_get_with_headers(url, headers);
    let json = json_parse(response);

    if json.error != () {
        return #{ error: json.error, message: json.message };
    }

    let entries = [];
    if json.data != () {
        for item in json.data {
            let node = item.node;
            let list_status = item.list_status;

            entries.push(#{
                manga_id: `${node.id}`,
                title: node.title,
                cover_url: if node.main_picture != () { node.main_picture.large } else { "" },
                status: map_mal_status(list_status.status),
                score: list_status.score,
                chapters_read: list_status.num_chapters_read,
                volumes_read: list_status.num_volumes_read,
                total_chapters: node.num_chapters,
                total_volumes: node.num_volumes,
                is_rereading: list_status.is_rereading,
                reread_count: list_status.num_times_reread,
                start_date: list_status.start_date,
                finish_date: list_status.finish_date,
                updated_at: list_status.updated_at,
                notes: list_status.comments,
                priority: list_status.priority,
                tags: list_status.tags
            });
        }
    }

    let has_next = json.paging != () && json.paging.next != ();

    #{
        entries: entries,
        has_more: has_next,
        total: entries.len(),  // MAL doesn't return total count easily
        current_page: page
    }
}

// Get single manga entry from user's list
fn get_list_entry(manga_id, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    let url = `${MAL_API_URL}/manga/${manga_id}?fields=my_list_status,num_chapters,num_volumes`;
    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`
    };

    let response = http_get_with_headers(url, headers);
    let json = json_parse(response);

    if json.error != () {
        return #{ error: json.error, not_in_list: true };
    }

    let list_status = json.my_list_status;
    if list_status == () {
        return #{ not_in_list: true, manga_id: manga_id };
    }

    #{
        manga_id: `${json.id}`,
        title: json.title,
        status: map_mal_status(list_status.status),
        score: list_status.score,
        chapters_read: list_status.num_chapters_read,
        volumes_read: list_status.num_volumes_read,
        total_chapters: json.num_chapters,
        total_volumes: json.num_volumes,
        is_rereading: list_status.is_rereading,
        reread_count: list_status.num_times_reread,
        start_date: list_status.start_date,
        finish_date: list_status.finish_date,
        updated_at: list_status.updated_at,
        notes: list_status.comments
    }
}

// Update manga entry in user's list
// entry should contain: status, score, chapters_read, volumes_read, etc.
fn update_list_entry(manga_id, entry, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    let url = `${MAL_API_URL}/manga/${manga_id}/my_list_status`;
    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`,
        "Content-Type": "application/x-www-form-urlencoded"
    };

    // Build form data
    let form_data = [];

    if entry.status != () && entry.status != "" {
        form_data.push(`status=${map_status_to_mal(entry.status)}`);
    }

    if entry.score != () {
        // MAL score is 0-10
        let score = entry.score;
        if score < 0 { score = 0; }
        if score > 10 { score = 10; }
        form_data.push(`score=${score}`);
    }

    if entry.chapters_read != () {
        form_data.push(`num_chapters_read=${entry.chapters_read}`);
    }

    if entry.volumes_read != () {
        form_data.push(`num_volumes_read=${entry.volumes_read}`);
    }

    if entry.is_rereading != () {
        form_data.push(`is_rereading=${entry.is_rereading}`);
    }

    if entry.reread_count != () {
        form_data.push(`num_times_reread=${entry.reread_count}`);
    }

    if entry.start_date != () && entry.start_date != "" {
        form_data.push(`start_date=${entry.start_date}`);
    }

    if entry.finish_date != () && entry.finish_date != "" {
        form_data.push(`finish_date=${entry.finish_date}`);
    }

    if entry.notes != () {
        form_data.push(`comments=${url_encode(entry.notes)}`);
    }

    if entry.priority != () {
        // 0 = Low, 1 = Medium, 2 = High
        form_data.push(`priority=${entry.priority}`);
    }

    let body = form_data.join("&");

    let response = http_patch_form(url, body, headers);
    let json = json_parse(response);

    if json.error != () {
        return #{ success: false, error: json.error, message: json.message };
    }

    #{
        success: true,
        manga_id: manga_id,
        status: map_mal_status(json.status),
        score: json.score,
        chapters_read: json.num_chapters_read,
        volumes_read: json.num_volumes_read,
        updated_at: json.updated_at
    }
}

// Remove manga from user's list
fn remove_list_entry(manga_id, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    let url = `${MAL_API_URL}/manga/${manga_id}/my_list_status`;
    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`
    };

    let response = http_delete_with_headers(url, headers);

    // MAL returns 200 on success, 404 if not in list
    if response.status_code == 200 || response.status_code == 204 {
        return #{ success: true, manga_id: manga_id };
    }

    let json = json_parse(response);
    if json.error != () {
        return #{ success: false, error: json.error };
    }

    #{ success: true, manga_id: manga_id }
}

// Sync reading progress from local to MAL
// progress should contain: manga_id, chapters_read, volumes_read, status (optional)
fn sync_progress(manga_id, progress, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    // First get current entry to compare
    let current = get_list_entry(manga_id, auth);

    let entry = #{
        chapters_read: progress.chapters_read,
        volumes_read: progress.volumes_read
    };

    // Auto-set status based on progress if not specified
    if progress.status != () {
        entry.status = progress.status;
    } else if current.not_in_list == true {
        // New entry - set to reading
        entry.status = "reading";
    } else if progress.chapters_read != () && current.total_chapters != () && progress.chapters_read >= current.total_chapters {
        // Completed all chapters
        entry.status = "completed";
    }

    // Auto-set start date if newly reading
    if current.not_in_list == true && entry.status == "reading" {
        let today = get_current_date();
        entry.start_date = today;
    }

    // Auto-set finish date if completed
    if entry.status == "completed" && (current.status != "completed" || current.not_in_list == true) {
        let today = get_current_date();
        entry.finish_date = today;
    }

    update_list_entry(manga_id, entry, auth)
}

// Get recommendations for a series from MAL
fn get_recommendations(manga_id, auth) {
    // Using Jikan API for recommendations (doesn't require auth)
    let url = `${BASE_URL}/manga/${manga_id}/recommendations`;
    let response = http_get(url);
    let json = json_parse(response);

    let recommendations = [];

    if json.data != () {
        for item in json.data {
            let entry = item.entry;
            let cover_url = "";
            if entry.images != () && entry.images.jpg != () {
                cover_url = entry.images.jpg.large_image_url;
                if cover_url == () {
                    cover_url = entry.images.jpg.image_url;
                }
            }

            recommendations.push(#{
                id: `${entry.mal_id}`,
                title: entry.title,
                cover_url: cover_url,
                url: entry.url,
                votes: item.votes
            });
        }
    }

    #{
        recommendations: recommendations,
        total: recommendations.len()
    }
}
