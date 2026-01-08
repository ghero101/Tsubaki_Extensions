# Tsubaki Extensions

Official extensions repository for Tsubaki manga reader. Contains source connectors, metadata providers, and artwork sources.

## Quick Start

### Installing Extensions

Extensions are installed through the Tsubaki web UI:
1. Go to **Settings > Extensions**
2. Browse the marketplace
3. Click **Install** on desired extensions

### For Developers

```bash
# Clone the repository
git clone https://github.com/ghero101/Tsubaki_Extensions.git
cd Tsubaki_Extensions

# Build all extensions (Linux/macOS)
./build.sh

# Build all extensions (Windows PowerShell)
.\build.ps1

# Build a single extension
./build.sh --single mangadex-rhai
```

## Repository Structure

```
Tsubaki_Extensions/
├── sources/                    # Extension source code
│   └── {extension-id}/
│       ├── manifest.json       # Extension metadata
│       ├── plugin.rhai         # Main script (or .lua, .py)
│       └── icon.png            # Extension icon (128x128)
├── dist/                       # Built extensions (auto-generated)
│   └── {extension-id}/
│       ├── {ext}_1-2-3.zip     # Versioned release
│       └── {ext}_latest.zip    # Latest version
├── index.json                  # Extension registry
├── build.sh                    # Linux/macOS build script
├── build.ps1                   # Windows build script
└── .github/workflows/          # CI/CD automation
```

## Extension Types

| Type | Description | Examples |
|------|-------------|----------|
| `scraper` | Full source connector - search, browse, download chapters | MangaDex, MangaPill, Webtoon |
| `metadata` | Metadata provider - series info, tracking | AniList, MyAnimeList, Kitsu |
| `artwork` | Artwork/image provider - tag-based search | Danbooru, Gelbooru, Rule34 |

## Supported Technologies

| Priority | Technology | Extension | Description |
|----------|------------|-----------|-------------|
| 1 | Rhai | `.rhai` | Rust-native scripting, fastest, type-safe |
| 2 | Lua | `.lua` | Lightweight scripting |
| 3 | WASM | `.wasm` | WebAssembly modules |
| 4 | Python | `.py` | Python scripts (requires Python runtime) |

## Build System

### Build Scripts

**Linux/macOS (`build.sh`):**
```bash
./build.sh                      # Build all extensions
./build.sh --clean              # Clean rebuild
./build.sh --single NAME        # Build single extension
./build.sh --help               # Show help
```

**Windows (`build.ps1`):**
```powershell
.\build.ps1                     # Build all extensions
.\build.ps1 -Clean              # Clean rebuild
.\build.ps1 -Single "NAME"      # Build single extension
.\build.ps1 -Help               # Show help
```

### What the Build Does

1. Reads `manifest.json` from each extension
2. Extracts version and metadata
3. Creates versioned zip: `{extension}_{version}.zip` (e.g., `mangadex-rhai_1-6-2.zip`)
4. Creates `{extension}_latest.zip` for convenience
5. Updates `index.json` with versions and download URLs
6. Organizes output in `dist/{extension}/` folders

### CI/CD Automation

The repository includes GitHub Actions workflow that:
- **Runs nightly** at 2:00 AM UTC
- **Triggers on push** to `sources/` directory
- **Validates** all manifests and index.json
- **Auto-commits** and pushes built extensions

Manual triggers available at: **Actions > Build Extensions > Run workflow**

## Creating an Extension

### 1. Create Extension Folder

```bash
mkdir sources/myextension-rhai
cd sources/myextension-rhai
```

### 2. Create manifest.json

```json
{
  "manifest_version": 1,
  "id": "myextension",
  "name": "My Extension",
  "version": "1.0.0",
  "description": "Description of your extension",
  "author": {
    "name": "Your Name",
    "url": "https://github.com/yourusername"
  },
  "license": "MIT",
  "addon_type": "scraper",
  "technology": "rhai",
  "entry_point": {
    "file": "plugin.rhai"
  },
  "capabilities": {
    "level": "http_only",
    "allowed_domains": ["example.com", "cdn.example.com"]
  },
  "features": {
    "search": true,
    "browse": true,
    "get_series": true,
    "get_chapters": true,
    "get_pages": true
  },
  "source_info": {
    "base_url": "https://example.com",
    "language": "en"
  }
}
```

### 3. Implement Required Functions

**Scraper Extensions:**
```rhai
fn get_source_info() -> SourceInfo
fn search_series(query, page, auth) -> SearchResult
fn get_series(id_or_url, auth) -> SeriesInfo
fn get_chapters(series_id, auth) -> Vec<ChapterInfo>
fn get_chapter_pages(chapter_id, auth) -> Vec<PageInfo>
```

**Metadata Extensions:**
```rhai
fn get_source_info() -> SourceInfo
fn search_series(query, page, auth) -> SearchResult
fn get_series(id_or_url, auth) -> SeriesInfo
```

**Artwork Extensions:**
```rhai
fn get_source_info() -> SourceInfo
fn search_series(query, page, auth) -> SearchResult  // Tag-based search
fn get_series(id_or_url, auth) -> SeriesInfo         // Image details
fn tag_autocomplete(query, limit, auth) -> Vec<TagInfo>  // Optional
```

### 4. Add Icon

Add a `icon.png` file (128x128 pixels recommended).

### 5. Test & Build

```bash
# Build your extension
./build.sh --single myextension-rhai

# Test in Tsubaki (mount the dist folder)
```

### 6. Version & Release

When updating your extension:
1. **Bump version** in `manifest.json`
2. **Run build** script
3. **Commit & push** (or let CI/CD handle it)

## Capability Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| `http_only` | Standard HTTP requests only | Most sites |
| `browser_automation` | Headless browser with Cloudflare bypass | Sites with heavy protection |

Browser automation extensions require admin approval in Tsubaki.

## Available APIs (Rhai)

```rhai
// HTTP
http_get(url) -> string
http_get_with_headers(url, headers) -> string
http_post(url, body, headers) -> string

// HTML Parsing
html_parse(html) -> Document
html_select(doc, selector) -> Vec<Element>
element_text(el) -> string
element_attr(el, attr) -> string

// JSON
json_parse(text) -> Dynamic

// Browser (requires browser_automation capability)
browser_launch() -> BrowserId
browser_goto(id, url)
browser_wait_for_cloudflare(id, timeout_ms)
browser_wait_for_selector(id, selector, timeout_ms)
browser_get_html(id) -> string
browser_close(id)
```

## Contributing

1. Fork this repository
2. Create your extension in `sources/`
3. Test thoroughly with build scripts
4. Submit a pull request

Pull requests trigger CI validation automatically.

## License

MIT License - See [LICENSE](LICENSE) file
