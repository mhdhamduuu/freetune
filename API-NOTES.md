# 🔌 API notes — Jamendo (from the public-apis list)

Source list: the **public-apis** project (zip found in Downloads and extracted
to `C:\Users\hamda\API mhdhamduuu\public-apis-master\`). FreeTune uses the
**Music → Jamendo** entry — a free public API hosting 600k+ Creative Commons
tracks with legal streaming **and** downloads.

## Base URL

```
https://api.jamendo.com/v3.0
```

## Endpoints used

`GET /tracks` with parameters:

| Param         | Used for                                    |
|---------------|---------------------------------------------|
| `client_id`   | your free key (dev.jamendo.com)             |
| `format`      | `json`                                      |
| `limit` / `offset` | pagination (30 per page, infinite scroll) |
| `order`       | `popularity_week` (trending), `popularity_total` (genre) |
| `search`      | free-text search (name/artist/album)        |
| `tags`        | genre filter (`pop`, `rock`, `hiphop`, …)   |
| `id`          | re-fetch one track (Hi-Fi quality fallback) |
| `audioformat` | `flac` for Hi-Res mode (omit = MP3)         |

## Track fields consumed

`id, name, duration, artist_name, album_name, image, album_image, audio,
audiodownload, audiodownload_allowed, license_ccurl`

- `audio` → stream URL (FLAC or MP3 depending on `audioformat`)
- `audiodownload` → legal download URL (MP3/FLAC)
- `audiodownload_allowed` → the app hides its download button when `false`,
  so every download respects the artist's choice.

## Legal design

- Only **Creative Commons** music is served — Jamendo is built for it.
- Downloads happen only where the artist explicitly allows them.
- The app never rips YouTube/Spotify — those would be piracy tools.

## Other sources

- **Audius** ✅ ACTIVE — decentralized streaming, **no key needed**, millions of
  artist-uploaded full tracks. Trending, genre filters and search. Streaming
  only (no official download API — the download button is hidden for Audius).
  Endpoints: `api.audius.co` → discovery node, then `/v1/tracks/trending`,
  `/v1/tracks/search?query=`, `/v1/tracks/{id}/stream?app_name=FreeTune`.
- **Deezer / Last.fm** — metadata + 30s previews only (no full downloads)
- **MusicBrainz** — metadata enrichment
- **Internet Archive** — huge public-domain catalog (vintage/classical),
  legal downloads — good future addition

## Search merges both catalogs

`TracksViewModel.searchBoth` queries Jamendo and Audius in parallel and
combines results, so search works even before you add a Jamendo key.
