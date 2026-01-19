# Extension Status Report

Last tested: 2026-01-19

## Summary

| Category | Working | Not Working | Total |
|----------|---------|-------------|-------|
| Artwork  | 8       | 0           | 8     |
| Metadata | 4       | 0           | 4     |
| Scraper  | 13      | 12          | 25    |
| **Total**| **25**  | **12**      | **37**|

## Working Scrapers (13/25)

These scrapers return results during browse/sync operations:

| Extension | ID | Series Count | Notes |
|-----------|-----|--------------|-------|
| Asura Scans | asurascans | ~15 | HTTP-only |
| MangaDex | mangadex-rhai | ~25 | HTTP-only, multi-language |
| MangaPill | mangapill-rhai | ~50 | HTTP-only, **pagination fixed v1.0.6** |
| WeebCentral | weebcentral-rhai | ~32 | HTTP-only, **pagination fixed v1.0.7** |
| Flame Comics | flamecomics | ~145 | Uses /api/series, **fixed v1.1.7** |
| VyManga | vymanga-rhai | ~3 | Browser, **pagination fixed v1.0.4** |
| VioletScans | violetscans-rhai | ~30 | HTTP-only, **URL fixed v1.1.0** |
| MangaOwl | mangaowl-rhai | ~10 | Browser automation |
| Dynasty Scans | dynastyscans-rhai | ~22 | HTTP-only |
| RoliaScan | roliascan-rhai | ~12 | HTTP-only |
| Guya | guya-rhai | ~6 | HTTP-only |
| Webtoon | webtoon-rhai | ~128 | HTTP-only |
| nhentai | nhentai-rhai | ~25 | HTTP-only, NSFW |

## Non-Working Scrapers (12/25)

### Sites Blocking HTTP Requests (Require Browser)

These sites block non-browser requests or require heavy JavaScript rendering:

| Extension | ID | Issue | Potential Fix |
|-----------|-----|-------|---------------|
| MangaNato | manganato-rhai | Site blocks requests | Needs browser automation |
| MangaKakalot | mangakakalot-rhai | Site blocks requests | Needs browser automation |
| MangaTown | mangatown-rhai | Site blocks requests | Needs browser automation |
| MangaGeko | mangageko-rhai | Site blocks requests | Needs browser automation |
| MangaPark | mangapark-rhai | Qwik JS framework | Domain updated v1.1.8, needs JS rendering |
| BatoTo | batoto-rhai | Vue.js SPA, times out | Needs better browser handling |
| HeyToon | heytoon-rhai | Site times out | Site may be down or blocking |
| FlixScans | flixscans-rhai | Site unreachable | Site appears to be down |
| MyComicList | mycomiclist-rhai | Site unreachable | Site appears to be down |

### Framework Scrapers (Require User Configuration)

These are template scrapers that require the user to configure a base URL:

| Extension | ID | Default URL | Configuration Required |
|-----------|-----|-------------|----------------------|
| FMReader | fmreader-rhai | kissmanga.org | Set `base_url` in settings |
| FoolSlide | foolslide-rhai | (none) | Set `base_url` to a FoolSlide instance |
| HeanCMS | heancms-rhai | omegascans.org | Set `base_url` in settings |

## Artwork Extensions (8/8 Working)

| Extension | ID | Status |
|-----------|-----|--------|
| Konachan | konachan-rhai | Working |
| RealBooru | realbooru-rhai | Working |
| Safebooru | safebooru-rhai | Working |
| Rule34 | rule34-rhai | Working (requires API key) |
| Danbooru | danbooru-rhai | Working |
| Gelbooru | gelbooru-rhai | Working (requires API key) |
| HypnoHub | hypnohub-rhai | Working |
| XBooru | xbooru-rhai | Working |

## Metadata Extensions (4/4 Working)

| Extension | ID | Status |
|-----------|-----|--------|
| AniList | anilist | Working |
| Kitsu | kitsu-rhai | Working |
| MangaUpdates | mangaupdates-rhai | Working |
| MyAnimeList | myanimelist | Working |

## Recent Fixes (2026-01-19)

### Pagination Fixes

Several scrapers had broken pagination where the website ignored page parameters:

1. **MangaPill v1.0.6**: Changed from `/mangas/new?page=X` to `/search?type=manga&page=X`
2. **WeebCentral v1.0.7**: Changed from `/hot-updates?page=X` to `/latest-updates/{page}` (path-based)
3. **FlameComics v1.1.7**: Added `/api/series` endpoint that returns all 145 series at once
4. **VyManga v1.0.4**: Changed from `/?page=X` to `/search?page=X`
5. **VioletScans v1.1.0**: Added trailing slash `/comics/?page=X` (WordPress redirect fix)

### Domain Updates

1. **MangaPark v1.1.8**: Updated domain from `mangapark.me` to `mangapark.io`

## Configuration

### Enable Browser Automation

Some scrapers require browser automation. Add to your `.env` file:
```
MANGA_SCRAPER_USE_BROWSER=1
```

Then restart the scraper:
```bash
docker-compose restart tsubaki-scraper
```

### Capability Levels

- `http_only` - Uses standard HTTP requests only
- `browser_automation` - Requires headless browser for JavaScript/Cloudflare

## Troubleshooting

### Extension Returns 0 Results

1. Check if the site requires browser automation
2. Verify `MANGA_SCRAPER_USE_BROWSER=1` is set
3. Check scraper logs: `docker logs tsubaki-scraper`
4. Site may be blocking or down - test manually in browser

### Extension Times Out

1. Site may be protected by Cloudflare
2. Browser automation may not be working
3. Network issues or site is down

### Pagination Issues

If syncing always returns the same items:
- The site may ignore page parameters
- Check if a pagination fix is available
- Report the issue for investigation
