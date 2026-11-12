# 🎵 FreeTune — free, ad-free iPhone music app

An Apple Music-style music player for iPhone built with **SwiftUI**, powered by the
**Jamendo public API** (from the public-apis list). 100% free, no ads, no tracking.

## Features

**Discover**
- Two catalogs: **Audius** (millions of tracks, no API key needed) + **Jamendo** (Creative Commons, legal downloads)
- **Fresh channels**: live trending for This Week / This Month / This Year (Audius)
- Instant keyword channels: Malayalam, Kerala, Devotional, Tamil
- "Listen Now" home with Featured hero card
- Trending tracks (weekly popularity) + 12 genre channels
- Apple Music-style gradient genre tiles in Search
- Debounced search (songs / artists / albums) with recent searches
- Infinite scroll pagination + pull-to-refresh

**Sound (the "aggressive" part)**
- **Hi-Res FLAC streaming + downloads** when the artist allows it (auto-fallback to MP3)
- **5-band equalizer** (60/230/910/3.6k/14k Hz) with presets — Flat, Bass Boost, Vocal, Bright, Warm
- **Bass Boost** slider + **Immersive Sound** (real-time reverb widener)
- Real-time **AVAudioEngine DSP chain** for downloaded songs
- Animated visualizer, haptic feedback

**Player**
- Floating glass mini-player above the tab bar (tap → fullscreen)
- Fullscreen Now Playing: blurred-artwork immersive backdrop, huge artwork with shadow
- Queue sheet ("Up Next"), shuffle, repeat, seek, haptics
- Lock-screen controls + artwork (MPNowPlayingInfoCenter / MPRemoteCommandCenter)
- Background audio (`UIBackgroundModes: audio`), interruption handling (phone calls)

**Offline**
- One-tap downloads (MP3 or FLAC) with live progress rings
- Downloads persist across launches; play without internet
- Delete single downloads (swipe) or all (Settings)

**Library**
- Favorites (heart) persisted locally
- Downloads with quality badge (FLAC Hi-Res / MP3) and file size

## Project structure

```
freetune/
├── FreeTune.xcodeproj/
├── Info.plist                  # background audio + launch config
├── .github/workflows/build-ipa.yml   # builds unsigned IPA on GitHub's macOS CI
├── BUILD-STEPS.md              # ← how to get it onto your iPhone
├── API-NOTES.md                # endpoints + licensing
├── tools/make_icon.py          # regenerates the app icon
└── FreeTune/                   # all Swift source (auto-synced by Xcode)
    ├── FreeTuneApp.swift       # app entry + root tabs + mini player
    ├── Models.swift            # Track / DownloadedTrack
    ├── Services/
    │   ├── JamendoAPI.swift    # public music API client
    │   ├── PlayerManager.swift # playback brain (AVPlayer + DSP routing)
    │   ├── SoundEngine.swift   # AVAudioEngine EQ/immersive chain
    │   ├── SoundSettings.swift # EQ/bass/spatial/hi-fi prefs
    │   ├── DownloadManager.swift
    │   ├── FavoritesManager.swift
    │   └── TracksViewModel.swift
    └── Views/                  # Home, Search, Library, Settings,
                                # TrackRow, TracksList, NowPlaying*, Common
```

## One thing you must do

Jamendo requires a **free client ID**. Get one at https://dev.jamendo.com and either:
- paste it in the app's **Settings tab** (first launch shows an onboarding card), or
- hardcode it into `FreeTune/Services/JamendoAPI.swift` (`bundledClientID`) before building.

See **BUILD-STEPS.md** for the full build + install guide.
