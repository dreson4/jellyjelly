# JellyJelly

A Netflix-style Apple TV (tvOS) client for [Jellyfin](https://jellyfin.org) with
[Jellyseerr](https://github.com/fallenbagel/jellyseerr) request support. SwiftUI,
no third-party dependencies.

## Features

- **Ambient background** — the artwork of whatever you focus melts into a
  blurred, dimmed wash behind the whole UI, crossfading as you browse
- **Multiple servers** — add any number of Jellyfin servers (each with its own
  optional Jellyseerr). Settings is a server list; opening one gives a single
  top-to-bottom editor (Jellyfin → connect ✓, Jellyseerr → connect ✓, Save),
  which auto-verifies stored connections on open
- **Home** — rotating hero banner, Continue Watching, Next Up, and per-library
  "New in …" shelves
- **Movies / Shows** — paged poster grids with Recently Added / A–Z / Top Rated sorting
- **Detail pages** — full-bleed backdrops, seasons & episodes, resume/from-beginning,
  mark watched, favorite, a circular cast row (each headshot opens a person page
  listing everything they're in across your library), and More Like This
- **Playback** — native AVPlayerViewController; direct play when the file allows it,
  server-side HLS transcode otherwise; progress reported back to Jellyfin
  (resume positions, watched state, Next Up all stay in sync)
- **Search** — Jellyfin library search
- **Discover** (optional, needs Jellyseerr) — Trending / Popular / Coming Soon shelves,
  TMDB search, and full detail pages: backdrop hero, ratings (Rotten Tomatoes +
  TMDB), a season/episode browser for series, a circular cast row that opens
  person pages (bio + "Known For"), recommendations and similar titles. Movies
  request in one press; series open a Jellyseerr-style **Request Series** sheet
  with per-season toggles, episode counts and availability status
- **Settings** — server info, Jellyseerr connect/disconnect, sign out

## Running

1. Open `JellyJelly.xcodeproj` in Xcode 16+ and run the `JellyJelly` scheme on an
   Apple TV simulator or device (tvOS 17+).
2. On first launch, enter your Jellyfin address (e.g. `192.168.1.20:8096`) and sign in.
3. Optionally connect Jellyseerr, choosing one of three methods: **Jellyfin
   Sign-In** (reuses the same account — nothing extra to type), **Jellyseerr
   Sign-In** (email + password, for local Jellyseerr accounts), or **API Key**.
   Both sign-in methods store a session cookie; available at onboarding or in
   Settings.

Command line build:

```sh
xcodebuild -project JellyJelly.xcodeproj -scheme JellyJelly \
  -destination 'generic/platform=tvOS Simulator' build
```

Plain-HTTP servers work (ATS is relaxed in `Config/Info.plist`) — typical for
LAN self-hosted setups.

## Throwaway test servers

The app was verified against real servers in Docker:

```sh
# Jellyfin with generated sample media
docker run -d --name jellyjelly-test -p 8096:8096 \
  -v /path/to/media:/media jellyfin/jellyfin:latest

# Jellyseerr on a shared network with it
docker network create jelly-net
docker network connect jelly-net jellyjelly-test
docker run -d --name jellyseerr-test --network jelly-net -p 5055:5055 \
  fallenbagel/jellyseerr:latest
```

Tear down with `docker rm -f jellyjelly-test jellyseerr-test`.

## Structure

```
JellyJelly/
  Core/
    AppState.swift            # server profiles + active clients (UserDefaults-backed)
    Models/                   # Jellyfin + Jellyseerr DTOs
    Networking/               # thin async API clients
  UI/
    Theme.swift               # colors, gradients, card metrics
    Components/               # cards, shelves, hero banner, button styles,
                              # AmbientBackground (focus-driven blurred backdrop)
    Screens/                  # one file per screen; PlayerView owns playback reporting
Config/Info.plist             # ATS exception for plain-HTTP servers
```

Detail pages present as a full-screen cover **above** the TabView (an app-level
`Router` drives one `fullScreenCover`), so opening a title from anywhere hides
the tabs entirely and returns you — via the on-screen back button or the remote's
Menu button — to exactly the tab and scroll position you left. The cover owns its
own `NavigationStack`, so cast → person → title chains push and pop one level at a
time. (When detail pages were pushed *inside* each tab's stack instead, the tab
bar floated over them and intercepted the Menu button, making "back" unreliable.)

tvOS quirks encoded in the UI: segmented pickers change selection as focus
passes over them, so sorting uses explicit chip buttons; grids sit in their own
`focusSection` so focus can always route down from the header; library reloads
swap data atomically so re-sorting never blanks the screen or drops focus; the
TabView keeps an explicit selection binding, otherwise sheets and server edits
silently reset it to the first tab; detail pages use `defaultFocus` to land on
the primary action (Play / Request) rather than the back button.

Jellyseerr 3.x quirks encoded in the client: media status decodes leniently
(3.x added values like 6 = deleted; a strict enum fails the whole page and
blanks search), page results drop malformed entries instead of failing
wholesale, query values are strictly percent-encoded (3.x rejects unescaped
reserved characters — apostrophes in a title used to 400), and Discover
shelves load independently because the TMDB-backed endpoints 500 transiently.

Notes: credentials are stored in UserDefaults (fine for a personal test build —
move the token to Keychain before distributing). The Jellyfin access token is
scoped per generated device ID.
