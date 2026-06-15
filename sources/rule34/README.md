# Adult Content Provider Addon

**WARNING: This addon provides access to explicit adult content. You must be 18 years or older to use this addon.**

## Overview

This addon provides integration with Rule34 and Gelbooru for searching fan-made adult content related to your manga/comic series. It also enables the fan art gallery feature for saving and organizing content.

## Features

- **Rule34 Search**: Search Rule34.xxx for content by tags
- **Gelbooru Search**: Alternative source with similar content
- **Fan Art Gallery**: Save images to a local gallery for each series
- **Safe Mode**: Optional filtering of extreme content tags
- **Video Support**: Toggle to include/exclude animated content

## Installation

1. Download the `adult-content-rhai.zip` from the releases
2. Go to Settings > Addons in Tsubaki
3. Click "Install from file" and select the zip
4. Enable the addon
5. Enable adult content in your user settings

## Configuration

### Settings Schema

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `default_limit` | number | 40 | Results per page (10-100) |
| `safe_mode` | boolean | true | Filter extreme content tags |
| `video_enabled` | boolean | true | Include video/animated content |

### User Permissions

Users must have the following permissions enabled to use this addon:

- `rule34_enabled`: Access to Rule34 search
- `fanart_enabled`: Access to fan art gallery

Admins can enable these permissions per-user in the user management panel.

## API Endpoints

Once installed, the following API endpoints become available:

### Rule34 Search
```
GET /api/v1/comics/series/{series_id}/rule34/
  ?tags=search_tags
  &page=0
  &limit=40
```

### Fan Art Gallery
```
GET /api/v1/comics/series/{series_id}/fanart/
POST /api/v1/comics/series/{series_id}/fanart/
DELETE /api/v1/comics/series/{series_id}/fanart/{id}/
GET /api/v1/comics/series/{series_id}/fanart/{id}/file/
GET /api/v1/comics/series/{series_id}/fanart/{id}/thumbnail/
GET /api/v1/comics/series/{series_id}/fanart/{id}/download/
```

## Plugin Functions

The Rhai plugin exposes the following functions:

- `search_rule34(tags, page, limit, settings)` - Search Rule34
- `search_gelbooru(tags, page, limit, settings)` - Search Gelbooru
- `get_post_details(post_id, source_site, settings)` - Get image details
- `search_series_content(series_name, page, limit, settings)` - Search by series name
- `get_popular_tags(limit, settings)` - Get popular tags

## Legal Notice

This addon is provided for educational and personal use only. Users are responsible for ensuring they comply with all applicable laws in their jurisdiction regarding adult content. The developers of Tsubaki do not host, store, or distribute any adult content - this addon merely provides a search interface to third-party services.

By installing this addon, you confirm:
1. You are 18 years of age or older
2. It is legal to view adult content in your jurisdiction
3. You accept responsibility for your use of this addon

## License

MIT License - See LICENSE file
