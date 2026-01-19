# Extension Status Report

Last tested: 2026-01-19 (Updated)

## Summary

| Category | Working | Fixable | Down | Total |
|----------|---------|---------|------|-------|
| Artwork  | 8       | 0       | 0    | 8     |
| Metadata | 4       | 0       | 0    | 4     |
| Scraper  | 15      | 5       | 5    | 25    |
| **Total**| **27**  | **5**   | **5**| **37**|

## Working Scrapers (15/25)

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
| MangaGeko | mangageko-rhai | ~? | HTTP-only (mgeko.cc works) |
| MangaTown | mangatown-rhai | ~? | HTTP-only, **verified working** |

## Fixable Scrapers - Need Browser Automation (5/25)

These sites are **ONLINE** but require browser automation to bypass anti-bot protection:

| Extension | ID | Domain Status | Protection Type |
|-----------|-----|---------------|-----------------|
| MangaNato | manganato-rhai | Online | Blocks non-browser requests |
| MangaKakalot | mangakakalot-rhai | Online | Blocks non-browser requests |
| MangaPark | mangapark-rhai | mpark.to (redirect chain) | Heavy anti-bot, needs browser |
| BatoTo | batoto-rhai | wto.to | Cloudflare challenge (403 cf-mitigated) |
| HeyToon | heytoon-rhai | Online | HTTP 404 - endpoint changed |

## Sites DOWN or Defunct (5/25)

These sites are **no longer operational**:

| Extension | ID | Evidence | Status |
|-----------|-----|----------|--------|
| FlixScans | flixscans-rhai | Connection refused (.net & .org) | **DEFUNCT** |
| MyComicList | mycomiclist-rhai | Domain parked (ad lander) | **DEFUNCT** |
| FMReader | fmreader-rhai | Template, no default site | Needs user config |
| FoolSlide | foolslide-rhai | Template, no default site | Needs user config |
| HeanCMS | heancms-rhai | Template, no default site | Needs user config |

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

---

## Domain Investigation (2026-01-19)

### Confirmed Working Domains

| Site | Working Domain | HTTP Status | Notes |
|------|----------------|-------------|-------|
| MangaTown | www.mangatown.com | 200 | **Fully working**, manga links verified |
| MangaGeko | www.mgeko.cc | 200 | Already configured in extension |
| HeyToon | heytoon.com | 302→404 | Site structure changed, needs investigation |

### Domain Changes Detected

| Site | Old Domain | New Domain | Redirect Chain |
|------|------------|------------|----------------|
| MangaPark | mangapark.io | mpark.to | mangapark.to → comicpark.org → ... → mpark.to (20+ redirects) |
| MangaGeko | mangageko.com | mgeko.com | mangageko.com → mgeko.com (anti-bot page) |

### Cloudflare Protected Sites

| Site | Domain | Protection Evidence |
|------|--------|---------------------|
| BatoTo | wto.to | `cf-mitigated: challenge` header, HTTP 403 |
| mgeko.com | mgeko.com | JS redirect anti-bot page |
| MangaNato | manganato.com | Connection refused for non-browser |
| MangaKakalot | mangakakalot.com | Connection refused for non-browser |

### Confirmed Defunct Sites

| Site | Evidence |
|------|----------|
| FlixScans | Connection refused on both .net and .org TLDs |
| MyComicList | Domain parked - redirects to advertising lander |

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
