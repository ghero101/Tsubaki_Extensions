# Extension Status Report

Last tested: 2026-01-01

## Summary

| Category | Working | Requires Browser | Total |
|----------|---------|------------------|-------|
| Artwork  | 8       | 0                | 8     |
| Metadata | 4       | 0                | 4     |
| Scraper  | 8       | 10               | 18    |
| **Total**| **20**  | **10**           | **30**|

## Working Extensions (HTTP Only)

These extensions work with `MANGA_SCRAPER_USE_BROWSER=0`:

### Artwork Extensions (8/8)
| Extension | ID | Status |
|-----------|-----|--------|
| Konachan | konachan-rhai | Working |
| RealBooru | realbooru-rhai | Working |
| Safebooru | safebooru-rhai | Working |
| Rule34 | rule34-rhai | Working |
| Danbooru | danbooru-rhai | Working |
| Gelbooru | gelbooru-rhai | Working |
| HypnoHub | hypnohub-rhai | Working |
| XBooru | xbooru-rhai | Working |

### Metadata Extensions (4/4)
| Extension | ID | Status |
|-----------|-----|--------|
| AniList | anilist | Working |
| Kitsu | kitsu-rhai | Working |
| MangaUpdates | mangaupdates-rhai | Working |
| MyAnimeList | myanimelist | Working |

### Scraper Extensions - HTTP Only (8/18)
| Extension | ID | Status |
|-----------|-----|--------|
| MangaDex | mangadex-rhai | Working |
| ComicK | comick-rhai | Working |
| MangaGeko | mangageko-rhai | Working |
| MangaPark | mangapark-rhai | Working |
| nhentai | nhentai-rhai | Working |
| Reaper Scans | reaperscans-rhai | Working |
| MangaNato | manganato-rhai | Working |
| Webtoon | webtoon-rhai | Working |

## Extensions Requiring Browser Automation

These extensions require `MANGA_SCRAPER_USE_BROWSER=1` to function properly.
They use headless Chrome for JavaScript rendering and Cloudflare bypass.

### Scraper Extensions - Browser Required (10/18)
| Extension | ID | Reason |
|-----------|-----|--------|
| Asura Scans | asurascans-rhai | JavaScript rendering, Cloudflare |
| BatoTo | batoto-rhai | Vue.js SPA, requires JS |
| Dynasty Scans | dynastyscans-rhai | JavaScript rendering |
| Flame Comics | flamecomics-rhai | Cloudflare protection |
| Flix Scans | flixscans-rhai | JavaScript rendering |
| MangaOwl | mangaowl-rhai | Cloudflare protection |
| MangaPill | mangapill-rhai | JavaScript rendering |
| MangaTown | mangatown-rhai | JavaScript rendering |
| VyManga | vymanga-rhai | JavaScript rendering |
| WeebCentral | weebcentral-rhai | JavaScript rendering |

## Configuration

### Enable Browser Automation

Add to your `.env` file:
```
MANGA_SCRAPER_USE_BROWSER=1
```

Then restart the scraper container:
```bash
docker-compose restart tsubaki-scraper
```

### Browser Requirements

When browser automation is enabled, the scraper will:
- Launch headless Chrome instances as needed
- Handle Cloudflare challenges automatically
- Execute JavaScript for SPA sites
- Manage browser sessions with automatic cleanup

**Note:** Browser automation increases resource usage (memory/CPU).

## Extension Capabilities

### Capability Levels
- `http_only` - Uses standard HTTP requests only
- `browser_automation` - Requires headless browser for JavaScript/Cloudflare

### Feature Support by Extension Type

| Feature | Scraper | Metadata | Artwork |
|---------|---------|----------|---------|
| search | Yes | Yes | Yes |
| browse | Yes | Yes | Yes |
| get_series | Yes | Yes | - |
| get_chapters | Yes | - | - |
| get_pages | Yes | - | - |
| download | Yes | - | Yes |
| get_metadata | Yes | Yes | - |
| get_covers | Yes | Yes | - |
| tracking | - | Some | - |
| login | Some | Some | - |

## Troubleshooting

### Extension Times Out
1. Check if extension requires browser automation
2. Verify `MANGA_SCRAPER_USE_BROWSER=1` is set
3. Check scraper logs: `docker logs tsubaki-scraper`

### Cloudflare Block
1. Enable browser automation
2. Extension will use stealth mode automatically
3. Some sites may still block after multiple requests

### Memory Issues
- Browser automation uses more RAM
- Consider limiting concurrent browser sessions
- Monitor with `docker stats tsubaki-scraper`
