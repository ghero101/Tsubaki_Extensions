// AniList Metadata Provider
// Built-in addon for Tsubaki - provides manga metadata via AniList GraphQL API

const BASE_URL = "https://graphql.anilist.co";

// Get source information
fn get_source_info() {
    #{
        id: "anilist",
        name: "AniList",
        base_url: "https://anilist.co",
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
    let graphql_query = `{
        "query": "query ($search: String, $page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { pageInfo { total currentPage lastPage hasNextPage } media(search: $search, type: MANGA) { id title { romaji english native } description(asHtml: false) coverImage { large medium } genres status isAdult startDate { year } } } }",
        "variables": {"search": "${query}", "page": ${page}, "perPage": 20}
    }`;

    let response = http_post_json(BASE_URL, graphql_query);
    let json = json_parse(response);

    let series = [];
    let page_info = json.data.Page.pageInfo;
    let media_list = json.data.Page.media;

    if media_list != () {
        for media in media_list {
            let title = "";
            if media.title.english != () && media.title.english != "" {
                title = media.title.english;
            } else if media.title.romaji != () {
                title = media.title.romaji;
            } else if media.title.native != () {
                title = media.title.native;
            }

            let alt_titles = [];
            if media.title.romaji != () && media.title.romaji != title {
                alt_titles.push(media.title.romaji);
            }
            if media.title.native != () && media.title.native != title {
                alt_titles.push(media.title.native);
            }
            if media.title.english != () && media.title.english != title {
                alt_titles.push(media.title.english);
            }

            let cover_url = "";
            if media.coverImage != () {
                if media.coverImage.large != () {
                    cover_url = media.coverImage.large;
                } else if media.coverImage.medium != () {
                    cover_url = media.coverImage.medium;
                }
            }

            let rating = "safe";
            if media.isAdult == true {
                rating = "adult";
            }

            series.push(#{
                id: `${media.id}`,
                title: title,
                alternate_titles: alt_titles,
                description: media.description,
                cover_url: cover_url,
                authors: [],
                artists: [],
                status: media.status,
                genres: media.genres,
                tags: [],
                year: media.startDate.year,
                content_rating: rating,
                url: `https://anilist.co/manga/${media.id}`
            });
        }
    }

    #{
        series: series,
        has_more: page_info.hasNextPage,
        total: page_info.total,
        current_page: page_info.currentPage
    }
}

// Get detailed series information by ID
fn get_series(id_or_url, auth) {
    // Extract ID from URL if needed
    let id = id_or_url;
    if id_or_url.contains("anilist.co/manga/") {
        let parts = id_or_url.split("/manga/");
        if parts.len() > 1 {
            id = parts[1].split("/")[0];
        }
    }

    let graphql_query = `{
        "query": "query ($id: Int) { Media(id: $id, type: MANGA) { id title { romaji english native } description(asHtml: false) coverImage { extraLarge large medium } genres tags { name } status volumes chapters isAdult startDate { year month day } staff { edges { role node { name { full } } } } } }",
        "variables": {"id": ${id}}
    }`;

    let response = http_post_json(BASE_URL, graphql_query);
    let json = json_parse(response);
    let media = json.data.Media;

    if media == () {
        return ();
    }

    let title = "";
    if media.title.english != () && media.title.english != "" {
        title = media.title.english;
    } else if media.title.romaji != () {
        title = media.title.romaji;
    } else if media.title.native != () {
        title = media.title.native;
    }

    let alt_titles = [];
    if media.title.romaji != () && media.title.romaji != title {
        alt_titles.push(media.title.romaji);
    }
    if media.title.native != () && media.title.native != title {
        alt_titles.push(media.title.native);
    }
    if media.title.english != () && media.title.english != title {
        alt_titles.push(media.title.english);
    }

    let cover_url = "";
    if media.coverImage != () {
        if media.coverImage.extraLarge != () {
            cover_url = media.coverImage.extraLarge;
        } else if media.coverImage.large != () {
            cover_url = media.coverImage.large;
        } else if media.coverImage.medium != () {
            cover_url = media.coverImage.medium;
        }
    }

    let rating = "safe";
    if media.isAdult == true {
        rating = "adult";
    }

    let tags = [];
    if media.tags != () {
        for tag in media.tags {
            tags.push(tag.name);
        }
    }

    // Extract authors and artists from staff
    let authors = [];
    let artists = [];
    if media.staff != () && media.staff.edges != () {
        for edge in media.staff.edges {
            let role = edge.role.to_lower();
            let name = edge.node.name.full;
            if role.contains("story") || role.contains("original creator") || role.contains("writer") {
                authors.push(name);
            }
            if role.contains("art") || role.contains("illustration") {
                artists.push(name);
            }
        }
    }

    #{
        id: `${media.id}`,
        title: title,
        alternate_titles: alt_titles,
        description: media.description,
        cover_url: cover_url,
        authors: authors,
        artists: artists,
        status: media.status,
        genres: media.genres,
        tags: tags,
        year: media.startDate.year,
        content_rating: rating,
        url: `https://anilist.co/manga/${media.id}`,
        extra: #{
            volumes: media.volumes,
            chapters: media.chapters,
            provider: "anilist",
            provider_id: `${media.id}`
        }
    }
}

// Get latest/trending manga (for browse)
fn get_latest_updates(page, auth) {
    let graphql_query = `{
        "query": "query ($page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { pageInfo { total currentPage lastPage hasNextPage } media(type: MANGA, sort: TRENDING_DESC) { id title { romaji english native } description(asHtml: false) coverImage { large medium } genres status isAdult startDate { year } } } }",
        "variables": {"page": ${page + 1}, "perPage": 25}
    }`;

    let response = http_post_json(BASE_URL, graphql_query);
    let json = json_parse(response);

    let series = [];

    if json == () || json["data"] == () || json["data"]["Page"] == () {
        return #{ series: [], has_more: false, total: () };
    }

    let page_info = json["data"]["Page"]["pageInfo"];
    let media_list = json["data"]["Page"]["media"];

    if media_list != () {
        for media in media_list {
            let title = "";
            if media["title"]["english"] != () && media["title"]["english"] != "" {
                title = media["title"]["english"];
            } else if media["title"]["romaji"] != () {
                title = media["title"]["romaji"];
            } else if media["title"]["native"] != () {
                title = media["title"]["native"];
            }

            let alt_titles = [];
            if media["title"]["romaji"] != () && media["title"]["romaji"] != title {
                alt_titles.push(media["title"]["romaji"]);
            }
            if media["title"]["native"] != () && media["title"]["native"] != title {
                alt_titles.push(media["title"]["native"]);
            }

            let cover_url = "";
            if media["coverImage"] != () {
                if media["coverImage"]["large"] != () {
                    cover_url = media["coverImage"]["large"];
                } else if media["coverImage"]["medium"] != () {
                    cover_url = media["coverImage"]["medium"];
                }
            }

            let rating = "safe";
            if media["isAdult"] == true {
                rating = "adult";
            }

            let genres = [];
            if media["genres"] != () {
                genres = media["genres"];
            }

            series.push(#{
                id: media["id"].to_string(),
                title: title,
                alternate_titles: alt_titles,
                description: media["description"],
                cover_url: cover_url,
                authors: [],
                artists: [],
                status: media["status"],
                genres: genres,
                tags: [],
                year: media["startDate"]["year"],
                content_rating: rating,
                url: `https://anilist.co/manga/${media["id"]}`
            });
        }
    }

    #{
        series: series,
        has_more: page_info["hasNextPage"],
        total: page_info["total"]
    }
}

// Get popular manga
fn get_popular(page, auth) {
    let graphql_query = `{
        "query": "query ($page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { pageInfo { total currentPage lastPage hasNextPage } media(type: MANGA, sort: POPULARITY_DESC) { id title { romaji english native } description(asHtml: false) coverImage { large medium } genres status isAdult startDate { year } } } }",
        "variables": {"page": ${page + 1}, "perPage": 25}
    }`;

    let response = http_post_json(BASE_URL, graphql_query);
    let json = json_parse(response);

    let series = [];

    if json == () || json["data"] == () || json["data"]["Page"] == () {
        return #{ series: [], has_more: false, total: () };
    }

    let page_info = json["data"]["Page"]["pageInfo"];
    let media_list = json["data"]["Page"]["media"];

    if media_list != () {
        for media in media_list {
            let title = "";
            if media["title"]["english"] != () && media["title"]["english"] != "" {
                title = media["title"]["english"];
            } else if media["title"]["romaji"] != () {
                title = media["title"]["romaji"];
            } else if media["title"]["native"] != () {
                title = media["title"]["native"];
            }

            let cover_url = "";
            if media["coverImage"] != () {
                if media["coverImage"]["large"] != () {
                    cover_url = media["coverImage"]["large"];
                } else if media["coverImage"]["medium"] != () {
                    cover_url = media["coverImage"]["medium"];
                }
            }

            let rating = "safe";
            if media["isAdult"] == true {
                rating = "adult";
            }

            let genres = [];
            if media["genres"] != () {
                genres = media["genres"];
            }

            series.push(#{
                id: media["id"].to_string(),
                title: title,
                alternate_titles: [],
                description: media["description"],
                cover_url: cover_url,
                authors: [],
                artists: [],
                status: media["status"],
                genres: genres,
                tags: [],
                year: media["startDate"]["year"],
                content_rating: rating,
                url: `https://anilist.co/manga/${media["id"]}`
            });
        }
    }

    #{
        series: series,
        has_more: page_info["hasNextPage"],
        total: page_info["total"]
    }
}

// Resolve manga title to AniList ID
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

    let target_norm = normalize(title);

    for q in candidates {
        let graphql_query = `{
            "query": "query ($search: String) { Media(search: $search, type: MANGA) { id title { romaji english native } isAdult } }",
            "variables": {"search": "${q}"}
        }`;

        let response = http_post_json(BASE_URL, graphql_query);
        let json = json_parse(response);

        if json.data != () && json.data.Media != () {
            let media = json.data.Media;
            let mtitle = "";
            if media.title.english != () && media.title.english != "" {
                mtitle = media.title.english;
            } else if media.title.romaji != () {
                mtitle = media.title.romaji;
            } else if media.title.native != () {
                mtitle = media.title.native;
            }

            if mtitle != "" && normalize(mtitle) == normalize(q) {
                return #{
                    provider: "anilist",
                    provider_id: `${media.id}`,
                    matched_title: mtitle
                };
            }
        }
    }

    ()
}

// ============================================================================
// TRACKING FEATURES - Requires OAuth2 Authentication
// Uses AniList GraphQL API: https://docs.anilist.co/guide/introduction
// ============================================================================

// Reading status mappings
// AniList statuses: CURRENT, PLANNING, COMPLETED, DROPPED, PAUSED, REPEATING
fn map_status_to_anilist(status) {
    switch status.to_lower() {
        "reading" | "current" => "CURRENT",
        "completed" | "finished" => "COMPLETED",
        "on_hold" | "paused" => "PAUSED",
        "dropped" => "DROPPED",
        "plan_to_read" | "planning" | "planned" => "PLANNING",
        "rereading" | "repeating" => "REPEATING",
        _ => "CURRENT"
    }
}

fn map_anilist_status(anilist_status) {
    switch anilist_status {
        "CURRENT" => "reading",
        "COMPLETED" => "completed",
        "PAUSED" => "on_hold",
        "DROPPED" => "dropped",
        "PLANNING" => "plan_to_read",
        "REPEATING" => "rereading",
        _ => "unknown"
    }
}

// Get authenticated user's info (needed for some queries)
fn get_viewer(auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    let query = `{
        "query": "query { Viewer { id name } }"
    }`;

    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`,
        "Content-Type": "application/json"
    };

    let response = http_post_json_with_headers(BASE_URL, query, headers);
    let json = json_parse(response);

    if json.errors != () {
        return #{ error: json.errors[0].message };
    }

    json.data.Viewer
}

// Get user's manga list
// status_filter: "reading", "completed", "on_hold", "dropped", "plan_to_read", "rereading", or () for all
fn get_user_list(status_filter, page, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required. Please connect your AniList account.", requires_auth: true };
    }

    let per_page = 50;

    // Build status filter
    let status_clause = "";
    if status_filter != () && status_filter != "" && status_filter != "all" {
        let al_status = map_status_to_anilist(status_filter);
        status_clause = `, status: ${al_status}`;
    }

    let query = `{
        "query": "query ($page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { pageInfo { total currentPage lastPage hasNextPage } mediaList(type: MANGA, sort: UPDATED_TIME_DESC${status_clause}) { id mediaId status score progress progressVolumes repeat startedAt { year month day } completedAt { year month day } updatedAt notes priority private media { id title { romaji english native } coverImage { large } chapters volumes status } } } }",
        "variables": {"page": ${page}, "perPage": ${per_page}}
    }`;

    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`,
        "Content-Type": "application/json"
    };

    let response = http_post_json_with_headers(BASE_URL, query, headers);
    let json = json_parse(response);

    if json.errors != () {
        return #{ error: json.errors[0].message };
    }

    let entries = [];
    let page_info = json.data.Page.pageInfo;
    let list = json.data.Page.mediaList;

    if list != () {
        for item in list {
            let media = item.media;
            let title = "";
            if media.title.english != () && media.title.english != "" {
                title = media.title.english;
            } else if media.title.romaji != () {
                title = media.title.romaji;
            } else {
                title = media.title.native;
            }

            let start_date = ();
            if item.startedAt != () && item.startedAt.year != () {
                start_date = `${item.startedAt.year}-${item.startedAt.month}-${item.startedAt.day}`;
            }

            let finish_date = ();
            if item.completedAt != () && item.completedAt.year != () {
                finish_date = `${item.completedAt.year}-${item.completedAt.month}-${item.completedAt.day}`;
            }

            entries.push(#{
                entry_id: `${item.id}`,
                manga_id: `${item.mediaId}`,
                title: title,
                cover_url: if media.coverImage != () { media.coverImage.large } else { "" },
                status: map_anilist_status(item.status),
                score: item.score,
                chapters_read: item.progress,
                volumes_read: item.progressVolumes,
                total_chapters: media.chapters,
                total_volumes: media.volumes,
                reread_count: item.repeat,
                start_date: start_date,
                finish_date: finish_date,
                updated_at: item.updatedAt,
                notes: item.notes,
                priority: item.priority,
                private: item.private
            });
        }
    }

    #{
        entries: entries,
        has_more: page_info.hasNextPage,
        total: page_info.total,
        current_page: page_info.currentPage
    }
}

// Get single manga entry from user's list
fn get_list_entry(manga_id, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    let query = `{
        "query": "query ($mediaId: Int) { MediaList(mediaId: $mediaId, type: MANGA) { id mediaId status score progress progressVolumes repeat startedAt { year month day } completedAt { year month day } updatedAt notes media { id title { romaji english } chapters volumes } } }",
        "variables": {"mediaId": ${manga_id}}
    }`;

    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`,
        "Content-Type": "application/json"
    };

    let response = http_post_json_with_headers(BASE_URL, query, headers);
    let json = json_parse(response);

    if json.errors != () {
        // Check if it's just not in list (expected error)
        if json.errors[0].message.contains("Not Found") || json.errors[0].status == 404 {
            return #{ not_in_list: true, manga_id: manga_id };
        }
        return #{ error: json.errors[0].message };
    }

    let item = json.data.MediaList;
    if item == () {
        return #{ not_in_list: true, manga_id: manga_id };
    }

    let media = item.media;
    let title = "";
    if media.title.english != () && media.title.english != "" {
        title = media.title.english;
    } else {
        title = media.title.romaji;
    }

    #{
        entry_id: `${item.id}`,
        manga_id: `${item.mediaId}`,
        title: title,
        status: map_anilist_status(item.status),
        score: item.score,
        chapters_read: item.progress,
        volumes_read: item.progressVolumes,
        total_chapters: media.chapters,
        total_volumes: media.volumes,
        reread_count: item.repeat,
        start_date: if item.startedAt != () && item.startedAt.year != () { `${item.startedAt.year}-${item.startedAt.month}-${item.startedAt.day}` } else { () },
        finish_date: if item.completedAt != () && item.completedAt.year != () { `${item.completedAt.year}-${item.completedAt.month}-${item.completedAt.day}` } else { () },
        updated_at: item.updatedAt,
        notes: item.notes
    }
}

// Update manga entry in user's list (or add if not exists)
// entry should contain: status, score, chapters_read, volumes_read, etc.
fn update_list_entry(manga_id, entry, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    // Build mutation variables
    let variables = `"mediaId": ${manga_id}`;

    if entry.status != () && entry.status != "" {
        let al_status = map_status_to_anilist(entry.status);
        variables = variables + `, "status": "${al_status}"`;
    }

    if entry.score != () {
        // AniList score can be 0-100 or 0-10 depending on user settings
        // We'll use the raw score and let AniList handle it
        variables = variables + `, "score": ${entry.score}`;
    }

    if entry.chapters_read != () {
        variables = variables + `, "progress": ${entry.chapters_read}`;
    }

    if entry.volumes_read != () {
        variables = variables + `, "progressVolumes": ${entry.volumes_read}`;
    }

    if entry.reread_count != () {
        variables = variables + `, "repeat": ${entry.reread_count}`;
    }

    if entry.notes != () {
        variables = variables + `, "notes": "${entry.notes}"`;
    }

    if entry.private != () {
        variables = variables + `, "private": ${entry.private}`;
    }

    // Handle dates - AniList uses FuzzyDateInput { year, month, day }
    if entry.start_date != () && entry.start_date != "" {
        let parts = entry.start_date.split("-");
        if parts.len() >= 3 {
            variables = variables + `, "startedAt": { "year": ${parts[0]}, "month": ${parts[1]}, "day": ${parts[2]} }`;
        }
    }

    if entry.finish_date != () && entry.finish_date != "" {
        let parts = entry.finish_date.split("-");
        if parts.len() >= 3 {
            variables = variables + `, "completedAt": { "year": ${parts[0]}, "month": ${parts[1]}, "day": ${parts[2]} }`;
        }
    }

    let query = `{
        "query": "mutation ($mediaId: Int, $status: MediaListStatus, $score: Float, $progress: Int, $progressVolumes: Int, $repeat: Int, $notes: String, $private: Boolean, $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput) { SaveMediaListEntry(mediaId: $mediaId, status: $status, score: $score, progress: $progress, progressVolumes: $progressVolumes, repeat: $repeat, notes: $notes, private: $private, startedAt: $startedAt, completedAt: $completedAt) { id mediaId status score progress progressVolumes updatedAt } }",
        "variables": {${variables}}
    }`;

    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`,
        "Content-Type": "application/json"
    };

    let response = http_post_json_with_headers(BASE_URL, query, headers);
    let json = json_parse(response);

    if json.errors != () {
        return #{ success: false, error: json.errors[0].message };
    }

    let result = json.data.SaveMediaListEntry;

    #{
        success: true,
        entry_id: `${result.id}`,
        manga_id: `${result.mediaId}`,
        status: map_anilist_status(result.status),
        score: result.score,
        chapters_read: result.progress,
        volumes_read: result.progressVolumes,
        updated_at: result.updatedAt
    }
}

// Remove manga from user's list
fn remove_list_entry(manga_id, auth) {
    if auth.access_token == () || auth.access_token == "" {
        return #{ error: "Authentication required", requires_auth: true };
    }

    // First get the entry ID
    let current = get_list_entry(manga_id, auth);
    if current.not_in_list == true {
        return #{ success: true, manga_id: manga_id, message: "Entry not in list" };
    }
    if current.error != () {
        return #{ success: false, error: current.error };
    }

    let entry_id = current.entry_id;

    let query = `{
        "query": "mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }",
        "variables": {"id": ${entry_id}}
    }`;

    let headers = #{
        "Authorization": `Bearer ${auth.access_token}`,
        "Content-Type": "application/json"
    };

    let response = http_post_json_with_headers(BASE_URL, query, headers);
    let json = json_parse(response);

    if json.errors != () {
        return #{ success: false, error: json.errors[0].message };
    }

    #{
        success: json.data.DeleteMediaListEntry.deleted,
        manga_id: manga_id,
        entry_id: entry_id
    }
}

// Sync reading progress from local to AniList
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

// Get recommendations for a series from AniList
fn get_recommendations(manga_id, auth) {
    let query = `{
        "query": "query ($id: Int) { Media(id: $id, type: MANGA) { recommendations { nodes { rating mediaRecommendation { id title { romaji english } coverImage { large } } } } } }",
        "variables": {"id": ${manga_id}}
    }`;

    let response = http_post_json(BASE_URL, query);
    let json = json_parse(response);

    let recommendations = [];

    if json.data != () && json.data.Media != () && json.data.Media.recommendations != () {
        for node in json.data.Media.recommendations.nodes {
            if node.mediaRecommendation != () {
                let media = node.mediaRecommendation;
                let title = "";
                if media.title.english != () && media.title.english != "" {
                    title = media.title.english;
                } else {
                    title = media.title.romaji;
                }

                recommendations.push(#{
                    id: `${media.id}`,
                    title: title,
                    cover_url: if media.coverImage != () { media.coverImage.large } else { "" },
                    url: `https://anilist.co/manga/${media.id}`,
                    rating: node.rating
                });
            }
        }
    }

    #{
        recommendations: recommendations,
        total: recommendations.len()
    }
}
