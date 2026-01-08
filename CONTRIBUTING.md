# Contributing to Tsubaki Extensions

Thank you for your interest in contributing! This guide will help you create and submit extensions.

## Getting Started

### Prerequisites

- Git
- Basic understanding of Rhai scripting (similar to Rust/JavaScript)
- Familiarity with web scraping concepts
- For Linux/macOS: `jq` and `zip` installed
- For Windows: PowerShell 5.1+

### Setting Up Development Environment

```bash
# Clone the repository
git clone https://github.com/ghero101/Tsubaki_Extensions.git
cd Tsubaki_Extensions

# Make build script executable (Linux/macOS)
chmod +x build.sh
```

## Creating a New Extension

### Step 1: Choose Extension Type

| Type | Purpose | Examples |
|------|---------|----------|
| `scraper` | Download manga/comics from a source | MangaDex, MangaPill |
| `metadata` | Fetch series information and tracking | AniList, MyAnimeList |
| `artwork` | Browse artwork with tag support | Danbooru, Gelbooru |

### Step 2: Create Extension Folder

Use the naming convention: `{source-name}-rhai`

```bash
mkdir sources/mysource-rhai
```

### Step 3: Create manifest.json

See [docs/MANIFEST_SCHEMA.md](docs/MANIFEST_SCHEMA.md) for complete schema.

Minimal example:
```json
{
  "manifest_version": 1,
  "id": "mysource",
  "name": "My Source",
  "version": "1.0.0",
  "addon_type": "scraper",
  "technology": "rhai",
  "entry_point": { "file": "plugin.rhai" },
  "capabilities": {
    "level": "http_only",
    "allowed_domains": ["mysource.com"]
  }
}
```

### Step 4: Implement the Plugin

See [docs/EXTENSION_API.md](docs/EXTENSION_API.md) for complete API reference.

### Step 5: Test Your Extension

```bash
# Build your extension
./build.sh --single mysource-rhai

# The zip will be in dist/mysource-rhai/
```

To test in Tsubaki:
1. Copy the zip to Tsubaki's extensions folder
2. Restart Tsubaki or refresh extensions
3. Enable your extension in Settings > Extensions

### Step 6: Submit a Pull Request

1. Fork this repository
2. Create a feature branch: `git checkout -b add-mysource`
3. Commit your changes: `git commit -am 'Add mysource extension'`
4. Push to your fork: `git push origin add-mysource`
5. Open a Pull Request

## Code Style Guidelines

### Rhai Best Practices

```rhai
// Use descriptive variable names
let series_title = manga["title"];

// Handle null/undefined values
let cover = manga["cover"];
if cover == () {
    cover = "";
}

// Use helper functions for repeated logic
fn strip_html(text) {
    if text == () { return ""; }
    // ... implementation
}

// Return proper data structures
fn search_series(query, page, auth) {
    let results = [];
    // ... populate results

    #{
        series: results,
        has_more: results.len() >= 20,
        total: results.len()
    }
}
```

### Manifest Guidelines

- **id**: Use lowercase, no spaces (e.g., `mangadex`, `myanimelist`)
- **version**: Use semantic versioning (MAJOR.MINOR.PATCH)
- **allowed_domains**: Include all domains the extension accesses (main site + CDN)

## Common Patterns

### Parsing HTML

```rhai
fn search_series(query, page, auth) {
    let url = `${BASE_URL}/search?q=${query}&page=${page}`;
    let html = http_get(url);
    let doc = html_parse(html);

    let results = [];
    let items = html_select(doc, ".manga-item");

    for item in items {
        let title = element_text(html_select(item, ".title")[0]);
        let link = element_attr(html_select(item, "a")[0], "href");
        let cover = element_attr(html_select(item, "img")[0], "src");

        results.push(#{
            id: extract_id(link),
            title: title,
            cover_url: cover,
            url: link
        });
    }

    #{ series: results, has_more: items.len() >= 20 }
}
```

### Parsing JSON APIs

```rhai
fn search_series(query, page, auth) {
    let url = `${BASE_URL}/api/search?q=${query}&page=${page}`;
    let response = http_get(url);
    let data = json_parse(response);

    let results = [];
    for item in data["results"] {
        results.push(#{
            id: `${item["id"]}`,
            title: item["title"],
            cover_url: item["cover"],
            description: item["synopsis"]
        });
    }

    #{
        series: results,
        has_more: data["has_next_page"],
        total: data["total"]
    }
}
```

### Browser Automation (Cloudflare bypass)

```rhai
fn fetch_with_browser(url) {
    if browser_is_available() {
        let browser_id = browser_launch();
        browser_goto(browser_id, url);
        browser_wait_for_cloudflare(browser_id, 15000);
        browser_wait_for_selector(browser_id, "#content", 10000);
        let html = browser_get_html(browser_id);
        browser_close(browser_id);
        return html;
    }
    // Fallback to HTTP
    http_get(url)
}
```

## Testing Checklist

Before submitting, verify:

- [ ] Extension builds without errors
- [ ] Search returns results
- [ ] Series details load correctly
- [ ] Chapters list properly
- [ ] Chapter pages load and display
- [ ] Covers/images load (check allowed_domains)
- [ ] No hardcoded credentials or API keys
- [ ] manifest.json is valid JSON
- [ ] Version number is appropriate

## Getting Help

- Open an issue for bugs or questions
- Check existing extensions for examples
- Review the [API documentation](docs/EXTENSION_API.md)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
