# Tsubaki Add-ons

Official add-ons repository for Tsubaki manga scraper. Contains source connectors and metadata providers.

## Structure

```
tsubaki-addons/
├── scrapers/           # Content scraper add-ons
│   └── {addon-id}/
│       ├── manifest.json
│       ├── plugin.rhai (or .lua, .py, .wasm)
│       └── icon.png
├── metadata/           # Metadata-only add-ons
│   └── {addon-id}/
│       └── ...
└── templates/          # Templates for creating new add-ons
```

## Add-on Types

| Type | Description |
|------|-------------|
| `scraper` | Full source connector - search, browse, download chapters |
| `metadata` | Metadata provider only - search, get series info (no downloads) |

## Supported Technologies

| Priority | Technology | File Extension | Description |
|----------|------------|----------------|-------------|
| 1 | Rhai | `.rhai` | Rust-native scripting, type-safe |
| 2 | Lua | `.lua` | Well-known scripting language |
| 3 | WASM | `.wasm` | WebAssembly, cross-platform |
| 4 | Native | `.dll`/`.so` | Compiled Rust plugins |
| 5 | Python | `.py` | Embedded Python |

## Creating an Add-on

1. Copy a template from `templates/`
2. Edit `manifest.json` with your source info
3. Implement required functions in your script
4. Add an icon (128x128 PNG recommended)
5. Test locally
6. Submit a pull request

## Required Functions

### Scraper Add-ons

```rhai
fn get_source_info() -> SourceInfo
fn search_series(query, page, auth) -> SearchResult
fn get_series(id_or_url, auth) -> SeriesInfo
fn get_chapters(series_id, auth) -> Vec<ChapterInfo>
fn get_chapter_pages(chapter_id, auth) -> Vec<PageInfo>
fn download_page(page, auth) -> bytes  // Optional, host handles by default
```

### Metadata Add-ons

```rhai
fn get_source_info() -> SourceInfo
fn search_series(query, page, auth) -> SearchResult
fn get_series(id_or_url, auth) -> SeriesInfo
```

## Manifest Schema

See `templates/` for full examples. Key fields:

```json
{
  "manifest_version": 1,
  "id": "unique-id",
  "name": "Display Name",
  "version": "1.0.0",
  "addon_type": "scraper|metadata",
  "icon_path": "icon.png",
  "technology": "rhai|lua|wasm|native|python",
  "entry_point": { "file": "plugin.rhai" },
  "capabilities": {
    "level": "http_only|browser_automation",
    "allowed_domains": ["example.com"]
  },
  "dependencies": {
    "addons": [],
    "libraries": { "python": [], "lua": [] }
  }
}
```

## Contributing

1. Fork this repository
2. Create your add-on in the appropriate folder
3. Test thoroughly
4. Submit a pull request

## License

MIT License - See LICENSE file
