# Extension Status Report

Last tested: 2026-01-24 (Comprehensive update - tested all framework and browser extensions)

## Summary

| Category | Working | Browser | Framework | Total |
|----------|---------|---------|-----------|-------|
| Artwork  | 8       | 0       | 0         | 8     |
| Metadata | 4       | 0       | 0         | 4     |
| Scraper  | 16      | 6       | 3         | 25    |
| **Total**| **28**  | **6**   | **3**     | **37**|

> **Note:** 3 defunct extensions (FlixScans, MyComicList, HeyToon) have been moved to `/archived`

## Working Scrapers (16/22)

These scrapers return results during browse/sync operations:

| Extension | ID | Series Count | Notes |
|-----------|-----|--------------|-------|
| Asura Scans | asurascans | ~15 | HTTP-only |
| MangaDex | mangadex-rhai | ~25 | HTTP-only, multi-language |
| MangaSee | mangasee-rhai | ~? | HTTP-only, uses embedded JSON |
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

## Browser Automation Scrapers (6/22)

These scrapers are configured for browser automation (via tsubaki-browser docker container):

| Extension | ID | Domain | HTTP Test | Status |
|-----------|-----|--------|-----------|--------|
| MangaNato | manganato-rhai | manganato.com | Connection blocked | **Browser required** |
| MangaKakalot | mangakakalot-rhai | mangakakalot.com | Connection blocked | **Browser required** |
| MangaPark | mangapark-rhai | mpark.to | 302 redirect loop | **Browser required** |
| BatoTo | batoto-rhai | mto.to | 502 Bad Gateway | **Browser required** (try wto.to) |
| BatCave | batcave-rhai | batcave.biz | 403 Cloudflare | **Browser required** |
| DemonicScans | demonicscans-rhai | demonicscans.org | 403 Cloudflare | **Browser required** |

### Browser Site Notes

All browser automation sites block non-browser HTTP requests. This is expected behavior.

**Connection Patterns Observed (2026-01-24):**
- `manganato.com`, `mangakakalot.com`: TCP connection refused (aggressive blocking)
- `mpark.to`: Infinite redirect loop to self
- `mto.to`: 502 Bad Gateway (may be down, try `wto.to`)
- `wto.to`: 403 with `cf-mitigated: challenge` header (Cloudflare)
- `batcave.biz`, `demonicscans.org`: 403 Cloudflare challenge

**To use these scrapers:**
1. Enable browser automation: `MANGA_SCRAPER_USE_BROWSER=1` in `.env`
2. Ensure tsubaki-browser container is running
3. Restart tsubaki-scraper service

## Framework Extensions (3/22 - Require Config)

| Extension | ID | Default Site | API Test | Status |
|-----------|-----|--------------|----------|--------|
| HeanCMS | heancms-rhai | omegascans.org | ✅ API returns 250 series | **Working** |
| FMReader | fmreader-rhai | rawkuma.net | ✅ Site accessible | See note below |
| FoolSlide | foolslide-rhai | None (required) | N/A | Set `base_url` in settings |

### Framework Notes

**HeanCMS (heancms-rhai)**
- API endpoint: `https://api.omegascans.org/query`
- Tested: Returns 250 series with full metadata
- Other HeanCMS sites: ReaperScans, QuantumScans, etc.

**FMReader (fmreader-rhai)**
- Default site rawkuma.net uses WordPress/Madara theme, NOT FMReader CMS
- The plugin may need adjustment for Madara-based sites
- Original FMReader sites (kissmanga.org) are down

**FoolSlide (foolslide-rhai)**
- No default site configured
- Working FoolSlide sites:
  - `reader.deathtollscans.net` ✅ (HTTP 200)
  - `reader.sensescans.com` ❌ (Connection refused)
  - `reader.kireicake.com` ❌ (Connection refused)

## Archived Extensions (Defunct)

The following extensions have been moved to `/archived` as their sites are no longer operational:

| Extension | Reason | Archived Date |
|-----------|--------|---------------|
| FlixScans | Connection refused (.net & .org) | 2026-01-24 |
| MyComicList | Domain parked (ad lander) | 2026-01-24 |
| HeyToon | HTTP 404 on all endpoints | 2026-01-24 |

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

1. **MangaPark v1.1.9**: Updated domain from `mangapark.io` to `mpark.to`
2. **FMReader v1.0.4**: Changed default from `kissmanga.org` (down) to `rawkuma.net`

### Browser Automation Updates

1. **MangaKakalot v1.0.5**: Enabled browser automation for Cloudflare bypass
2. **MangaNato v1.1.5**: Already had browser automation enabled
3. **BatoTo v1.0.3**: Already had browser automation enabled

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

### Confirmed Defunct Sites (Archived)

| Site | Evidence | Status |
|------|----------|--------|
| FlixScans | Connection refused on both .net and .org TLDs | **Archived** |
| MyComicList | Domain parked - redirects to advertising lander | **Archived** |
| HeyToon | HTTP 404 on all endpoints | **Archived** |

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
