# Extension API Reference

This document describes all available APIs for Tsubaki extensions.

## Table of Contents

- [Required Functions](#required-functions)
- [HTTP API](#http-api)
- [HTML Parsing API](#html-parsing-api)
- [JSON API](#json-api)
- [Browser Automation API](#browser-automation-api)
- [Data Types](#data-types)

---

## Required Functions

### All Extensions

```rhai
/// Returns metadata about the extension
fn get_source_info() -> SourceInfo
```

### Scraper Extensions

```rhai
/// Search for series matching the query
fn search_series(query: String, page: Int, auth: AuthContext) -> SearchResult

/// Get detailed information about a series
fn get_series(id_or_url: String, auth: AuthContext) -> SeriesInfo

/// Get list of chapters for a series
fn get_chapters(series_id: String, auth: AuthContext) -> Vec<ChapterInfo>

/// Get page URLs/images for a chapter
fn get_chapter_pages(chapter_id: String, auth: AuthContext) -> Vec<PageInfo>
```

### Optional Functions

```rhai
/// Browse latest/popular without search query
fn get_latest_updates(page: Int, auth: AuthContext) -> SearchResult

/// Download a page (if default handler doesn't work)
fn download_page(page: PageInfo, auth: AuthContext) -> Bytes
```

---

## HTTP API

### http_get

Performs a GET request and returns the response body.

```rhai
let html = http_get("https://example.com/page");
```

### http_get_with_headers

Performs a GET request with custom headers.

```rhai
let headers = #{
    "User-Agent": "Mozilla/5.0",
    "Referer": "https://example.com/",
    "Accept": "application/json"
};
let response = http_get_with_headers("https://api.example.com/data", headers);
```

### http_post

Performs a POST request with body and headers.

```rhai
let body = `{"query": "search term"}`;
let headers = #{
    "Content-Type": "application/json"
};
let response = http_post("https://api.example.com/search", body, headers);
```

---

## HTML Parsing API

### html_parse

Parses an HTML string into a document object.

```rhai
let html = http_get("https://example.com");
let doc = html_parse(html);
```

### html_select

Selects elements matching a CSS selector.

```rhai
let doc = html_parse(html);

// Select all elements with class "manga-item"
let items = html_select(doc, ".manga-item");

// Select within an element
let title_el = html_select(items[0], ".title");

// Complex selectors
let links = html_select(doc, "div.content > a[href*='/manga/']");
```

### element_text

Gets the text content of an element.

```rhai
let title_el = html_select(doc, ".title")[0];
let title = element_text(title_el);  // "My Manga Title"
```

### element_attr

Gets an attribute value from an element.

```rhai
let link_el = html_select(doc, "a.manga-link")[0];
let href = element_attr(link_el, "href");      // "/manga/123"
let class = element_attr(link_el, "class");    // "manga-link"
let data = element_attr(link_el, "data-id");   // "123"
```

### element_html

Gets the inner HTML of an element.

```rhai
let container = html_select(doc, ".description")[0];
let inner_html = element_html(container);  // "<p>Description...</p>"
```

---

## JSON API

### json_parse

Parses a JSON string into a dynamic object.

```rhai
let response = http_get("https://api.example.com/manga/123");
let data = json_parse(response);

// Access object properties
let title = data["title"];
let chapters = data["chapters"];

// Access nested properties
let author_name = data["author"]["name"];

// Access array elements
let first_chapter = data["chapters"][0];

// Iterate arrays
for chapter in data["chapters"] {
    let num = chapter["number"];
}
```

### Handling null/undefined

```rhai
let value = data["optional_field"];

// Check if null/undefined
if value == () {
    value = "default";
}

// Or use conditional
let cover = if data["cover"] != () { data["cover"] } else { "" };
```

---

## Browser Automation API

These functions require `capability_level: "browser_automation"` in the manifest.

### browser_is_available

Checks if browser automation is available.

```rhai
if browser_is_available() {
    // Use browser
} else {
    // Fallback to HTTP
}
```

### browser_launch

Launches a new browser instance.

```rhai
let browser_id = browser_launch();
```

### browser_goto

Navigates to a URL.

```rhai
browser_goto(browser_id, "https://example.com");
```

### browser_wait_for_cloudflare

Waits for Cloudflare challenge to complete.

```rhai
// Wait up to 15 seconds for Cloudflare
browser_wait_for_cloudflare(browser_id, 15000);
```

### browser_wait_for_selector

Waits for an element to appear.

```rhai
// Wait up to 10 seconds for content to load
browser_wait_for_selector(browser_id, "#main-content", 10000);
```

### browser_get_html

Gets the current page HTML.

```rhai
let html = browser_get_html(browser_id);
```

### browser_close

Closes the browser instance.

```rhai
browser_close(browser_id);
```

### Complete Browser Example

```rhai
fn fetch_protected_page(url) {
    if !browser_is_available() {
        return http_get(url);
    }

    let browser_id = browser_launch();

    browser_goto(browser_id, url);
    browser_wait_for_cloudflare(browser_id, 15000);
    browser_wait_for_selector(browser_id, ".manga-content", 10000);

    let html = browser_get_html(browser_id);
    browser_close(browser_id);

    html
}
```

---

## Data Types

### SourceInfo

```rhai
#{
    id: "mysource",
    name: "My Source",
    base_url: "https://example.com",
    language: "en",
    supported_languages: ["en", "es"],
    requires_authentication: false,
    capability_level: "http_only"  // or "browser_automation"
}
```

### SearchResult

```rhai
#{
    series: [SeriesInfo, ...],
    has_more: true,  // Are there more pages?
    total: 100       // Optional: total result count
}
```

### SeriesInfo

```rhai
#{
    id: "manga-123",
    title: "My Manga",
    alternate_titles: ["Alt Title 1", "Alt Title 2"],
    description: "A description of the manga...",
    cover_url: "https://cdn.example.com/covers/123.jpg",
    url: "https://example.com/manga/123",
    authors: ["Author Name"],
    artists: ["Artist Name"],
    status: "ongoing",  // ongoing, completed, hiatus, cancelled
    genres: ["Action", "Adventure"],
    tags: ["Fantasy", "Magic"],
    year: 2020,
    content_rating: "safe",  // safe, suggestive, nsfw
    extra: #{}  // Additional metadata
}
```

### ChapterInfo

```rhai
#{
    id: "chapter-456",
    series_id: "manga-123",
    number: 1.0,  // Chapter number (supports decimals like 1.5)
    title: "Chapter Title",
    volume: 1,    // Optional
    language: "en",
    scanlator: "Scan Group",
    url: "https://example.com/manga/123/chapter/456",
    published_at: "2024-01-15T12:00:00Z",
    page_count: 20,
    extra: #{
        // Store source-specific data here
        token: "abc123"
    }
}
```

### PageInfo

```rhai
#{
    index: 0,  // Page number (0-indexed)
    url: "https://cdn.example.com/pages/123/1.jpg",
    headers: #{
        "Referer": "https://example.com/"
    },
    referer: "https://example.com/"  // Shorthand for Referer header
}
```

### AuthContext

Passed to functions when user has authentication configured.

```rhai
// auth may be () if not authenticated
fn search_series(query, page, auth) {
    let headers = #{};

    if auth != () {
        headers["Authorization"] = `Bearer ${auth.token}`;
        headers["Cookie"] = auth.cookies;
    }

    // ... use headers
}
```

---

## Utility Functions

### String Operations

```rhai
// String interpolation
let url = `${BASE_URL}/manga/${id}`;

// Split string
let parts = url.split("/");

// Check contains
if url.contains("/manga/") {
    // ...
}

// Replace
let clean = text.replace("<br>", "\n");

// Trim whitespace
let trimmed = text.trim();

// Substring
let sub = text.sub_string(0, 100);

// Index of
let pos = text.index_of("chapter");
if pos != () {
    // Found at position `pos`
}

// To lowercase/uppercase
let lower = text.to_lower();
let upper = text.to_upper();
```

### Array Operations

```rhai
let arr = [];

// Push
arr.push(item);

// Length
let count = arr.len();

// Iterate
for item in arr {
    // ...
}

// Sort
arr.sort(|a, b| {
    if a.number > b.number { -1 }
    else if a.number < b.number { 1 }
    else { 0 }
});

// Filter (manual)
let filtered = [];
for item in arr {
    if item.status == "active" {
        filtered.push(item);
    }
}
```

### Type Conversion

```rhai
// Parse integer
let num = parse_int("123");  // 123

// Parse float
let dec = parse_float("1.5");  // 1.5

// To string
let str = `${number}`;
```
