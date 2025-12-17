//! MangaDex Scraper Add-on (WASM)
//! Uses the official MangaDex API v5
//!
//! This addon is compiled to WebAssembly for high-performance execution.
//! Host provides: http_get, json_parse, json_stringify functions

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

const BASE_URL: &str = "https://api.mangadex.org";
const COVERS_URL: &str = "https://uploads.mangadex.org/covers";

// External functions provided by the host
extern "C" {
    fn host_http_get(url_ptr: *const u8, url_len: usize) -> *mut u8;
    fn host_free(ptr: *mut u8);
}

// Wrapper for safe HTTP calls
fn http_get(url: &str) -> String {
    unsafe {
        let result_ptr = host_http_get(url.as_ptr(), url.len());
        if result_ptr.is_null() {
            return String::new();
        }
        // Read length from first 4 bytes
        let len = *(result_ptr as *const u32) as usize;
        let data_ptr = result_ptr.add(4);
        let slice = std::slice::from_raw_parts(data_ptr, len);
        let result = String::from_utf8_lossy(slice).to_string();
        host_free(result_ptr);
        result
    }
}

// Data structures for MangaDex API responses
#[derive(Deserialize)]
struct MangaListResponse {
    result: String,
    data: Vec<MangaData>,
    #[serde(default)]
    total: i32,
}

#[derive(Deserialize)]
struct MangaResponse {
    result: String,
    data: MangaData,
}

#[derive(Deserialize)]
struct MangaData {
    id: String,
    attributes: MangaAttributes,
    relationships: Vec<Relationship>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MangaAttributes {
    title: HashMap<String, String>,
    #[serde(default)]
    alt_titles: Vec<HashMap<String, String>>,
    #[serde(default)]
    description: HashMap<String, String>,
    status: Option<String>,
    year: Option<i32>,
    content_rating: Option<String>,
    #[serde(default)]
    tags: Vec<Tag>,
    original_language: Option<String>,
    last_chapter: Option<String>,
    last_volume: Option<String>,
    publication_demographic: Option<String>,
    updated_at: Option<String>,
}

#[derive(Deserialize)]
struct Tag {
    attributes: TagAttributes,
}

#[derive(Deserialize)]
struct TagAttributes {
    name: HashMap<String, String>,
}

#[derive(Deserialize)]
struct Relationship {
    id: String,
    #[serde(rename = "type")]
    rel_type: String,
    #[serde(default)]
    attributes: Option<serde_json::Value>,
}

#[derive(Deserialize)]
struct ChapterFeedResponse {
    result: String,
    data: Vec<ChapterData>,
}

#[derive(Deserialize)]
struct ChapterData {
    id: String,
    attributes: ChapterAttributes,
    relationships: Vec<Relationship>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ChapterAttributes {
    chapter: Option<String>,
    title: Option<String>,
    volume: Option<String>,
    translated_language: Option<String>,
    publish_at: Option<String>,
    pages: Option<i32>,
    external_url: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AtHomeResponse {
    result: String,
    base_url: String,
    chapter: AtHomeChapter,
}

#[derive(Deserialize)]
struct AtHomeChapter {
    hash: String,
    data: Vec<String>,
}

// Output structures
#[derive(Serialize)]
struct SourceInfo {
    id: &'static str,
    name: &'static str,
    base_url: &'static str,
    language: &'static str,
    supported_languages: Vec<&'static str>,
    requires_authentication: bool,
    capability_level: &'static str,
}

#[derive(Serialize)]
struct SeriesResult {
    id: String,
    title: String,
    url: String,
    cover_url: Option<String>,
    alternate_titles: Vec<String>,
    authors: Vec<String>,
    artists: Vec<String>,
    status: String,
    genres: Vec<String>,
    tags: Vec<String>,
    description: Option<String>,
}

#[derive(Serialize)]
struct SearchResult {
    series: Vec<SeriesResult>,
    has_more: bool,
    total: i32,
}

#[derive(Serialize)]
struct SeriesDetail {
    id: String,
    title: String,
    alternate_titles: Vec<String>,
    description: Option<String>,
    cover_url: Option<String>,
    authors: Vec<String>,
    artists: Vec<String>,
    status: String,
    genres: Vec<String>,
    tags: Vec<String>,
    year: Option<i32>,
    content_rating: Option<String>,
    url: String,
    extra: SeriesExtra,
}

#[derive(Serialize)]
struct SeriesExtra {
    original_language: Option<String>,
    last_chapter: Option<String>,
    last_volume: Option<String>,
    demographic: Option<String>,
}

#[derive(Serialize)]
struct ChapterResult {
    id: String,
    series_id: String,
    number: Option<String>,
    title: Option<String>,
    volume: Option<String>,
    language: Option<String>,
    scanlator: Option<String>,
    url: String,
    published_at: Option<String>,
    page_count: Option<i32>,
}

#[derive(Serialize)]
struct PageResult {
    index: usize,
    url: String,
    headers: HashMap<String, String>,
    referer: &'static str,
}

// Helper functions
fn extract_title(title_obj: &HashMap<String, String>, preferred_lang: &str) -> String {
    title_obj.get(preferred_lang)
        .or_else(|| title_obj.get("en"))
        .or_else(|| title_obj.get("ja"))
        .or_else(|| title_obj.values().next())
        .cloned()
        .unwrap_or_default()
}

fn extract_cover_url(manga_id: &str, relationships: &[Relationship]) -> Option<String> {
    for rel in relationships {
        if rel.rel_type == "cover_art" {
            if let Some(attrs) = &rel.attributes {
                if let Some(filename) = attrs.get("fileName").and_then(|f| f.as_str()) {
                    return Some(format!("{}/{}/{}", COVERS_URL, manga_id, filename));
                }
            }
        }
    }
    None
}

fn extract_authors(relationships: &[Relationship]) -> Vec<String> {
    let mut authors = Vec::new();
    for rel in relationships {
        if rel.rel_type == "author" || rel.rel_type == "artist" {
            if let Some(attrs) = &rel.attributes {
                if let Some(name) = attrs.get("name").and_then(|n| n.as_str()) {
                    if !authors.contains(&name.to_string()) {
                        authors.push(name.to_string());
                    }
                }
            }
        }
    }
    authors
}

fn extract_tags(tags: &[Tag], lang: &str) -> Vec<String> {
    tags.iter()
        .filter_map(|tag| {
            let name = extract_title(&tag.attributes.name, lang);
            if name.is_empty() { None } else { Some(name) }
        })
        .collect()
}

fn map_status(status: Option<&str>) -> String {
    match status {
        Some("ongoing") => "Ongoing".to_string(),
        Some("completed") => "Completed".to_string(),
        Some("hiatus") => "Hiatus".to_string(),
        Some("cancelled") => "Cancelled".to_string(),
        Some(s) => s.to_string(),
        None => "Unknown".to_string(),
    }
}

// Exported functions
#[no_mangle]
pub extern "C" fn get_source_info() -> *mut u8 {
    let info = SourceInfo {
        id: "mangadex-wasm",
        name: "MangaDex (WASM)",
        base_url: BASE_URL,
        language: "en",
        supported_languages: vec!["en", "ja", "ko", "zh", "es", "fr", "de", "it", "pt-br", "ru"],
        requires_authentication: false,
        capability_level: "http_only",
    };

    let json = serde_json::to_string(&info).unwrap_or_default();
    alloc_string(&json)
}

#[no_mangle]
pub extern "C" fn search_series(query_ptr: *const u8, query_len: usize, page: i32) -> *mut u8 {
    let query = unsafe {
        let slice = std::slice::from_raw_parts(query_ptr, query_len);
        String::from_utf8_lossy(slice).to_string()
    };

    let offset = (page - 1) * 25;
    let url = format!(
        "{}/manga?title={}&limit=25&offset={}&includes[]=cover_art&includes[]=author&includes[]=artist",
        BASE_URL, urlencoding::encode(&query), offset
    );

    let response_text = http_get(&url);
    let response: MangaListResponse = match serde_json::from_str(&response_text) {
        Ok(r) => r,
        Err(_) => return alloc_string(r#"{"series":[],"has_more":false,"total":0}"#),
    };

    if response.result != "ok" {
        return alloc_string(r#"{"series":[],"has_more":false,"total":0}"#);
    }

    let series: Vec<SeriesResult> = response.data.iter().map(|manga| {
        let title = extract_title(&manga.attributes.title, "en");

        let mut alt_titles = Vec::new();
        for alt in &manga.attributes.alt_titles {
            for alt_title in alt.values() {
                if alt_title != &title && !alt_titles.contains(alt_title) {
                    alt_titles.push(alt_title.clone());
                }
            }
        }

        SeriesResult {
            id: manga.id.clone(),
            title: title.clone(),
            url: format!("https://mangadex.org/title/{}", manga.id),
            cover_url: extract_cover_url(&manga.id, &manga.relationships),
            alternate_titles: alt_titles,
            authors: extract_authors(&manga.relationships),
            artists: Vec::new(),
            status: map_status(manga.attributes.status.as_deref()),
            genres: extract_tags(&manga.attributes.tags, "en"),
            tags: Vec::new(),
            description: manga.attributes.description.get("en").cloned(),
        }
    }).collect();

    let result = SearchResult {
        series,
        has_more: offset + 25 < response.total,
        total: response.total,
    };

    let json = serde_json::to_string(&result).unwrap_or_default();
    alloc_string(&json)
}

#[no_mangle]
pub extern "C" fn get_series_detail(id_ptr: *const u8, id_len: usize) -> *mut u8 {
    let id_or_url = unsafe {
        let slice = std::slice::from_raw_parts(id_ptr, id_len);
        String::from_utf8_lossy(slice).to_string()
    };

    let manga_id = if id_or_url.contains("mangadex.org") {
        id_or_url.split("/title/")
            .nth(1)
            .and_then(|s| s.split('/').next())
            .unwrap_or(&id_or_url)
            .to_string()
    } else {
        id_or_url
    };

    let url = format!(
        "{}/manga/{}?includes[]=cover_art&includes[]=author&includes[]=artist",
        BASE_URL, manga_id
    );

    let response_text = http_get(&url);
    let response: MangaResponse = match serde_json::from_str(&response_text) {
        Ok(r) => r,
        Err(_) => return alloc_string(r#"{"error":"Failed to fetch manga"}"#),
    };

    if response.result != "ok" {
        return alloc_string(r#"{"error":"Failed to fetch manga"}"#);
    }

    let manga = response.data;
    let title = extract_title(&manga.attributes.title, "en");

    let mut alt_titles = Vec::new();
    for alt in &manga.attributes.alt_titles {
        for alt_title in alt.values() {
            if alt_title != &title && !alt_titles.contains(alt_title) {
                alt_titles.push(alt_title.clone());
            }
        }
    }

    let result = SeriesDetail {
        id: manga.id.clone(),
        title,
        alternate_titles: alt_titles,
        description: manga.attributes.description.get("en").cloned(),
        cover_url: extract_cover_url(&manga.id, &manga.relationships),
        authors: extract_authors(&manga.relationships),
        artists: Vec::new(),
        status: map_status(manga.attributes.status.as_deref()),
        genres: extract_tags(&manga.attributes.tags, "en"),
        tags: Vec::new(),
        year: manga.attributes.year,
        content_rating: manga.attributes.content_rating.clone(),
        url: format!("https://mangadex.org/title/{}", manga.id),
        extra: SeriesExtra {
            original_language: manga.attributes.original_language.clone(),
            last_chapter: manga.attributes.last_chapter.clone(),
            last_volume: manga.attributes.last_volume.clone(),
            demographic: manga.attributes.publication_demographic.clone(),
        },
    };

    let json = serde_json::to_string(&result).unwrap_or_default();
    alloc_string(&json)
}

#[no_mangle]
pub extern "C" fn get_chapters(series_id_ptr: *const u8, series_id_len: usize) -> *mut u8 {
    let series_id = unsafe {
        let slice = std::slice::from_raw_parts(series_id_ptr, series_id_len);
        String::from_utf8_lossy(slice).to_string()
    };

    let mut chapters = Vec::new();
    let mut offset = 0;
    let limit = 100;

    loop {
        let url = format!(
            "{}/manga/{}/feed?limit={}&offset={}&translatedLanguage[]=en&order[chapter]=desc&includes[]=scanlation_group",
            BASE_URL, series_id, limit, offset
        );

        let response_text = http_get(&url);
        let response: ChapterFeedResponse = match serde_json::from_str(&response_text) {
            Ok(r) => r,
            Err(_) => break,
        };

        if response.result != "ok" || response.data.is_empty() {
            break;
        }

        for chapter in &response.data {
            let scanlator = chapter.relationships.iter()
                .find(|r| r.rel_type == "scanlation_group")
                .and_then(|r| r.attributes.as_ref())
                .and_then(|a| a.get("name"))
                .and_then(|n| n.as_str())
                .map(|s| s.to_string());

            chapters.push(ChapterResult {
                id: chapter.id.clone(),
                series_id: series_id.clone(),
                number: chapter.attributes.chapter.clone(),
                title: chapter.attributes.title.clone(),
                volume: chapter.attributes.volume.clone(),
                language: chapter.attributes.translated_language.clone(),
                scanlator,
                url: format!("https://mangadex.org/chapter/{}", chapter.id),
                published_at: chapter.attributes.publish_at.clone(),
                page_count: chapter.attributes.pages,
            });
        }

        offset += limit;
        if offset >= 10000 {
            break;
        }
    }

    let json = serde_json::to_string(&chapters).unwrap_or_default();
    alloc_string(&json)
}

#[no_mangle]
pub extern "C" fn get_chapter_pages(chapter_id_ptr: *const u8, chapter_id_len: usize) -> *mut u8 {
    let chapter_id = unsafe {
        let slice = std::slice::from_raw_parts(chapter_id_ptr, chapter_id_len);
        String::from_utf8_lossy(slice).to_string()
    };

    let url = format!("{}/at-home/server/{}", BASE_URL, chapter_id);

    let response_text = http_get(&url);
    let response: AtHomeResponse = match serde_json::from_str(&response_text) {
        Ok(r) => r,
        Err(_) => return alloc_string("[]"),
    };

    if response.result != "ok" {
        return alloc_string("[]");
    }

    let pages: Vec<PageResult> = response.chapter.data.iter()
        .enumerate()
        .map(|(idx, filename)| PageResult {
            index: idx,
            url: format!("{}/data/{}/{}", response.base_url, response.chapter.hash, filename),
            headers: HashMap::new(),
            referer: "https://mangadex.org/",
        })
        .collect();

    let json = serde_json::to_string(&pages).unwrap_or_default();
    alloc_string(&json)
}

// Memory allocation helper
fn alloc_string(s: &str) -> *mut u8 {
    let bytes = s.as_bytes();
    let len = bytes.len();
    let total = 4 + len;

    let layout = std::alloc::Layout::from_size_align(total, 1).unwrap();
    let ptr = unsafe { std::alloc::alloc(layout) };

    if ptr.is_null() {
        return std::ptr::null_mut();
    }

    unsafe {
        *(ptr as *mut u32) = len as u32;
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr.add(4), len);
    }

    ptr
}

#[no_mangle]
pub extern "C" fn alloc(size: usize) -> *mut u8 {
    let layout = std::alloc::Layout::from_size_align(size, 1).unwrap();
    unsafe { std::alloc::alloc(layout) }
}

#[no_mangle]
pub extern "C" fn dealloc(ptr: *mut u8, size: usize) {
    let layout = std::alloc::Layout::from_size_align(size, 1).unwrap();
    unsafe { std::alloc::dealloc(ptr, layout) }
}

// URL encoding module (minimal implementation)
mod urlencoding {
    pub fn encode(s: &str) -> String {
        let mut result = String::new();
        for c in s.chars() {
            match c {
                'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => {
                    result.push(c);
                }
                ' ' => result.push_str("%20"),
                _ => {
                    for b in c.to_string().bytes() {
                        result.push_str(&format!("%{:02X}", b));
                    }
                }
            }
        }
        result
    }
}
