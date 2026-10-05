# Shelf

Shelf is a native SwiftUI iPhone app for a self-hosted [Kavita](https://www.kavitareader.com) server. It signs in with Kavita's account login, browses libraries, and reads comics, EPUBs, and PDFs. Reading position is written through the same KOReader progress API that KOReader on a Kindle uses, so the page stays in sync.

The client was checked against Kavita's OpenAPI document on the `develop` branch (reported as 0.9.1.10) and the matching server controllers. Routes are the documented ones, not guesses.

## What works

- Sign in with server URL, username, and password (`POST /api/Account/login`). Kavita identifies the account by username.
- JWT and refresh token (`POST /api/Account/refresh-token`), refreshed on a 401 and about every 10 minutes while the app is open, matching the web client.
- API key from the login payload (`apiKey` / the `opds` auth key). If Kavita does not return one, Shelf creates one with `POST /api/Account/create-auth-key`.
- Server URL, username, password, JWT, refresh token, API key, and a device id live in the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). They are not written to UserDefaults or other files.
- Libraries (`GET /api/Library/libraries`), series in a library (`POST /api/Series/v2` with a Libraries filter), volumes and chapters (`GET /api/Series/volumes`).
- Cover images from `GET /api/Image/series-cover` and `GET /api/Image/library-cover`, authenticated with the API key.
- Continue Reading / On Deck (`POST /api/Series/on-deck`) and resume (`GET /api/Reader/continue-point`).
- Search (`GET /api/Search/search`).
- Comic and image archives: `GET /api/Reader/chapter-info` then `GET /api/Reader/image`, swipe paging, pinch zoom, double-tap zoom, and a left-to-right or right-to-left option.
- EPUB via Kavita's book reader (see below).
- PDF via PDFKit from `GET /api/Reader/pdf`.
- Progress sync back to Kavita, and resume at the saved page.
- System light and dark mode. The comic and PDF viewers use a black page background.

## EPUB

Shelf uses Kavita's book reader API instead of bundling a second EPUB engine.

`GET /api/Book/{chapterId}/book-info` and `GET /api/Book/{chapterId}/book-page` return one spine document at a time, already rewritten so images and CSS point at `GET /api/Book/{chapterId}/book-resources`. Shelf shows that HTML in a `WKWebView`. The table of contents comes from `GET /api/Book/{chapterId}/chapters`, and in-book links that Kavita tags with `kavita-page` jump to that spine item.

That page index is the same `DocFragment` index Kavita converts to and from KOReader's XPath (`/body/DocFragment[n]`). A separate Swift EPUB renderer (Readium, for example) would paginate differently and would not land on the page KOReader saved.

Within a spine document, KOReader can also store a finer XPath. Shelf scrolls to that XPath when it opens the page. It does not invent a new XPath while you scroll inside the page. Turning the page writes a new `DocFragment` position, which is the position Kavita's own reader and KOReader both understand.

## Progress sync

KOReader on a Kindle is pointed at `{server}/api/koreader/{apiKey}` and reads `GET /api/Koreader/{apiKey}/syncs/progress/{ebookHash}`. Shelf uses that same pair of routes:

- The hash is `koreaderHash` on the chapter file (`MangaFileDto`), which Kavita computes during a library scan.
- Archives and PDFs use a 1-based page number. Kavita stores `pageNum` as that number minus one.
- EPUBs use `/body/DocFragment[n].0` or `/body/DocFragment[n]/body/…`, which Kavita maps onto `pageNum` and `bookScrollId`.
- `PUT /api/Koreader/{apiKey}/syncs/progress` also calls Kavita's normal progress save, so On Deck and the web reader move too.

If a file has no `koreaderHash` (the library has not had the forced scan Kavita needs for KOReader hashes), Shelf falls back to `POST /api/Reader/progress` so Kavita still records the page. Run a forced scan on the library once so Kindle sync can see those books.

The last page is stored one past the end, which is how Kavita's web reader marks a chapter finished.

## Build

Requirements:

- macOS with Xcode beta (or a current Xcode that can open the project)
- iOS 17 or later. A device on iOS 27 is fine; the deployment target is 17.0
- A Kavita server you can reach from the phone

Steps:

1. Open `Shelf.xcodeproj`.
2. Select the Shelf target → Signing & Capabilities, and set your Development Team. `DEVELOPMENT_TEAM` is intentionally empty in the committed project so it can be filled in locally.
3. Choose an iPhone simulator or your phone and run the Shelf scheme.
4. On the sign-in screen, enter the server (placeholder `https://kavita.example`), your Kavita username, and password. Include a path if Kavita is hosted under one, for example `https://example.com/kavita`. For a self-signed certificate, turn on **Allow untrusted certificates**. Plain `http://` is allowed for a server on your network.

Unit tests for API decoding, the KOReader position codec, and the HTTP client live in the `ShelfCore` package. From the repo root:

```sh
cd ShelfCore
swift test
```

In Xcode, Product → Test runs the ShelfTests target, which compiles those same tests.

## Project layout

- `Shelf/` — SwiftUI app: sign-in, library browsing, readers, Keychain.
- `ShelfCore/` — URL, JSON models, Kavita client, and KOReader progress mapping. No UIKit, so the tests run with the Swift toolchain.
- Bundle id: `com.kiefermenard.shelf`.

## Not in this version

- OPDS browsing, bookmarks, annotations, and reading lists
- Offline downloads
- Generating KOReader XPath from an arbitrary scroll position inside an EPUB spine item
- A bundled EPUB renderer

## Verification

API behavior was taken from Kavita's published OpenAPI spec and the `Account`, `Series`, `Reader`, `Book`, `Image`, and `Koreader` controllers on `develop` (spec version 0.9.1.10).

`swift test` in `ShelfCore` passed on Swift 6.2 for Linux (decoding, server URL normalization, KOReader position mapping, the HTTP client, and synchronous cover/reader URL building). Cover, library, page, and PDF URLs are nonisolated methods of `KavitaClient`: they use the immutable server address plus an API key argument, so SwiftUI can build them from a synchronous closure. `ShelfModel` reads the untrusted-certificate default into a local during `init` and applies that local to both the property and the URL session delegate, because an `@Observable` property read counts as using `self` before `urlSession` exists. This environment has no Xcode and no iOS Simulator, so the Shelf app target was not compiled, signed, or run here. Signing, the Keychain, and the comic, EPUB, and PDF views still need a Mac with Xcode.
