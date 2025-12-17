"""
MangaDex Scraper Add-on (Python)
Uses the official MangaDex API v5

Available APIs (injected by host):
    http_get(url: str) -> str
    http_get_with_headers(url: str, headers: dict) -> str
    http_post(url: str, body: dict) -> str
    json_parse(text: str) -> dict
    json_stringify(value: Any) -> str
"""

from typing import Any, Dict, List, Optional
from urllib.parse import quote

BASE_URL = "https://api.mangadex.org"
COVERS_URL = "https://uploads.mangadex.org/covers"


class MangaDexSource:
    """MangaDex manga source implementation."""

    def __init__(self, http_client=None):
        """Initialize with injected HTTP client."""
        self._http = http_client

    def get_source_info(self) -> Dict[str, Any]:
        """Returns metadata about this source."""
        return {
            "id": "mangadex-python",
            "name": "MangaDex (Python)",
            "base_url": BASE_URL,
            "language": "en",
            "supported_languages": ["en", "ja", "ko", "zh", "es", "fr", "de", "it", "pt-br", "ru"],
            "requires_authentication": False,
            "capability_level": "http_only"
        }

    def _extract_title(self, title_obj: Optional[Dict], preferred_lang: str = "en") -> str:
        """Extract title from MangaDex title object, preferring specified language."""
        if not title_obj:
            return ""
        # Try preferred language first
        if preferred_lang in title_obj:
            return title_obj[preferred_lang]
        # Fall back to English
        if "en" in title_obj:
            return title_obj["en"]
        # Fall back to Japanese
        if "ja" in title_obj:
            return title_obj["ja"]
        # Return first available
        for v in title_obj.values():
            return v
        return ""

    def _extract_cover_url(self, manga_id: str, relationships: Optional[List]) -> Optional[str]:
        """Extract cover URL from relationships."""
        if not relationships:
            return None
        for rel in relationships:
            if rel.get("type") == "cover_art":
                attrs = rel.get("attributes", {})
                if attrs.get("fileName"):
                    return f"{COVERS_URL}/{manga_id}/{attrs['fileName']}"
        return None

    def _extract_authors(self, relationships: Optional[List]) -> List[str]:
        """Extract authors from relationships."""
        authors = []
        seen = set()
        if not relationships:
            return authors
        for rel in relationships:
            if rel.get("type") in ("author", "artist"):
                attrs = rel.get("attributes", {})
                name = attrs.get("name")
                if name and name not in seen:
                    authors.append(name)
                    seen.add(name)
        return authors

    def _extract_tags(self, tags: Optional[List], lang: str = "en") -> List[str]:
        """Extract tags from manga data."""
        result = []
        if not tags:
            return result
        for tag in tags:
            attrs = tag.get("attributes", {})
            name_obj = attrs.get("name", {})
            tag_name = self._extract_title(name_obj, lang)
            if tag_name:
                result.append(tag_name)
        return result

    def _map_status(self, status: Optional[str]) -> str:
        """Map status string to standard format."""
        status_map = {
            "ongoing": "Ongoing",
            "completed": "Completed",
            "hiatus": "Hiatus",
            "cancelled": "Cancelled"
        }
        return status_map.get(status, status or "Unknown")

    def _http_get(self, url: str) -> str:
        """Make HTTP GET request using injected client or global function."""
        if self._http:
            return self._http.get(url)
        # Fall back to global function (injected by host)
        return http_get(url)

    def search_series(self, query: str, page: int = 1, auth: Optional[Dict] = None) -> Dict[str, Any]:
        """Search for series matching query."""
        offset = (page - 1) * 25
        encoded_query = quote(query)
        url = f"{BASE_URL}/manga?title={encoded_query}&limit=25&offset={offset}&includes[]=cover_art&includes[]=author&includes[]=artist"

        response_text = self._http_get(url)
        response = json_parse(response_text)

        if response.get("result") != "ok":
            return {"series": [], "has_more": False, "total": 0}

        data = response.get("data", [])
        total = response.get("total", 0)
        series = []

        for manga in data:
            manga_id = manga.get("id")
            attrs = manga.get("attributes", {})
            rels = manga.get("relationships", [])

            # Extract title
            title = self._extract_title(attrs.get("title"), "en")

            # Extract alternate titles
            alt_titles = []
            for alt in attrs.get("altTitles", []):
                for alt_title in alt.values():
                    if alt_title != title and alt_title not in alt_titles:
                        alt_titles.append(alt_title)

            # Extract description
            description = None
            desc_obj = attrs.get("description", {})
            if isinstance(desc_obj, dict) and "en" in desc_obj:
                description = desc_obj["en"]

            series.append({
                "id": manga_id,
                "title": title,
                "url": f"https://mangadex.org/title/{manga_id}",
                "cover_url": self._extract_cover_url(manga_id, rels),
                "alternate_titles": alt_titles,
                "authors": self._extract_authors(rels),
                "artists": [],
                "status": self._map_status(attrs.get("status")),
                "genres": self._extract_tags(attrs.get("tags"), "en"),
                "tags": [],
                "description": description
            })

        has_more = offset + 25 < total

        return {"series": series, "has_more": has_more, "total": total}

    def get_series(self, id_or_url: str, auth: Optional[Dict] = None) -> Dict[str, Any]:
        """Get detailed series information."""
        # Extract ID from URL if needed
        manga_id = id_or_url
        if "mangadex.org" in id_or_url:
            parts = id_or_url.split("/")
            for i, part in enumerate(parts):
                if part == "title" and i + 1 < len(parts):
                    manga_id = parts[i + 1]
                    break

        url = f"{BASE_URL}/manga/{manga_id}?includes[]=cover_art&includes[]=author&includes[]=artist"

        response_text = self._http_get(url)
        response = json_parse(response_text)

        if response.get("result") != "ok":
            return {
                "id": manga_id,
                "title": "",
                "error": "Failed to fetch manga"
            }

        manga = response.get("data", {})
        attrs = manga.get("attributes", {})
        rels = manga.get("relationships", [])

        title = self._extract_title(attrs.get("title"), "en")

        # Extract alternate titles
        alt_titles = []
        for alt in attrs.get("altTitles", []):
            for alt_title in alt.values():
                if alt_title != title and alt_title not in alt_titles:
                    alt_titles.append(alt_title)

        # Extract description
        description = None
        desc_obj = attrs.get("description", {})
        if isinstance(desc_obj, dict) and "en" in desc_obj:
            description = desc_obj["en"]

        return {
            "id": manga_id,
            "title": title,
            "alternate_titles": alt_titles,
            "description": description,
            "cover_url": self._extract_cover_url(manga_id, rels),
            "authors": self._extract_authors(rels),
            "artists": [],
            "status": self._map_status(attrs.get("status")),
            "genres": self._extract_tags(attrs.get("tags"), "en"),
            "tags": [],
            "year": attrs.get("year"),
            "content_rating": attrs.get("contentRating"),
            "url": f"https://mangadex.org/title/{manga_id}",
            "extra": {
                "original_language": attrs.get("originalLanguage"),
                "last_chapter": attrs.get("lastChapter"),
                "last_volume": attrs.get("lastVolume"),
                "demographic": attrs.get("publicationDemographic")
            }
        }

    def get_chapters(self, series_id: str, auth: Optional[Dict] = None) -> List[Dict[str, Any]]:
        """Get all chapters for a series."""
        chapters = []
        offset = 0
        limit = 100

        while True:
            url = f"{BASE_URL}/manga/{series_id}/feed?limit={limit}&offset={offset}&translatedLanguage[]=en&order[chapter]=desc&includes[]=scanlation_group"

            response_text = self._http_get(url)
            response = json_parse(response_text)

            if response.get("result") != "ok":
                break

            data = response.get("data", [])
            if not data:
                break

            for chapter in data:
                chapter_id = chapter.get("id")
                attrs = chapter.get("attributes", {})
                rels = chapter.get("relationships", [])

                # Extract scanlation group
                scanlator = None
                for rel in rels:
                    if rel.get("type") == "scanlation_group":
                        rel_attrs = rel.get("attributes", {})
                        scanlator = rel_attrs.get("name")
                        if scanlator:
                            break

                chapters.append({
                    "id": chapter_id,
                    "series_id": series_id,
                    "number": attrs.get("chapter"),
                    "title": attrs.get("title"),
                    "volume": attrs.get("volume"),
                    "language": attrs.get("translatedLanguage"),
                    "scanlator": scanlator,
                    "url": f"https://mangadex.org/chapter/{chapter_id}",
                    "published_at": attrs.get("publishAt"),
                    "page_count": attrs.get("pages"),
                    "extra": {
                        "external_url": attrs.get("externalUrl")
                    }
                })

            offset += limit

            # Prevent infinite loops
            if offset >= 10000:
                break

        return chapters

    def get_chapter_pages(self, chapter_id: str, auth: Optional[Dict] = None) -> List[Dict[str, Any]]:
        """Get page URLs for a chapter."""
        url = f"{BASE_URL}/at-home/server/{chapter_id}"

        response_text = self._http_get(url)
        response = json_parse(response_text)

        if response.get("result") != "ok":
            return []

        base_url = response.get("baseUrl")
        chapter_data = response.get("chapter", {})
        hash_val = chapter_data.get("hash")
        data_pages = chapter_data.get("data", [])

        pages = []
        for idx, filename in enumerate(data_pages):
            pages.append({
                "index": idx,
                "url": f"{base_url}/data/{hash_val}/{filename}",
                "headers": {},
                "referer": "https://mangadex.org/"
            })

        return pages

    def get_latest_updates(self, page: int = 1, auth: Optional[Dict] = None) -> Dict[str, Any]:
        """Get latest updates."""
        offset = (page - 1) * 25
        url = f"{BASE_URL}/manga?limit=25&offset={offset}&includes[]=cover_art&order[updatedAt]=desc"

        response_text = self._http_get(url)
        response = json_parse(response_text)

        if response.get("result") != "ok":
            return {"series": [], "has_more": False}

        data = response.get("data", [])
        total = response.get("total", 0)
        series = []

        for manga in data:
            manga_id = manga.get("id")
            attrs = manga.get("attributes", {})
            rels = manga.get("relationships", [])

            series.append({
                "id": manga_id,
                "title": self._extract_title(attrs.get("title"), "en"),
                "url": f"https://mangadex.org/title/{manga_id}",
                "cover_url": self._extract_cover_url(manga_id, rels),
                "updated_at": attrs.get("updatedAt")
            })

        return {"series": series, "has_more": offset + 25 < total}


# Export functions for direct invocation (when not using class)
_instance = None

def _get_instance():
    global _instance
    if _instance is None:
        _instance = MangaDexSource()
    return _instance

def get_source_info():
    return _get_instance().get_source_info()

def search_series(query, page=1, auth=None):
    return _get_instance().search_series(query, page, auth)

def get_series(id_or_url, auth=None):
    return _get_instance().get_series(id_or_url, auth)

def get_chapters(series_id, auth=None):
    return _get_instance().get_chapters(series_id, auth)

def get_chapter_pages(chapter_id, auth=None):
    return _get_instance().get_chapter_pages(chapter_id, auth)

def get_latest_updates(page=1, auth=None):
    return _get_instance().get_latest_updates(page, auth)
