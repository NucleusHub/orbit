# Orbit for iPhone

The native iPhone app for Orbit, the Nucleus files and cloud storage app. It is built with SwiftUI and runs on
iOS 17 and later. Its design system is [NucleusUI](https://github.com/NucleusHub/nucleus-native-ui), the same
one Todo and Watchlist use. It is a port of the Orbit web client and talks to the same server API at
`/api/orbit`. Files stay on the person's own Nucleus server, so the app needs a Nucleus ID sign-in before it
shows anything.

This branch (`ios`) holds only the iPhone app. The web client and the server live on `main`.

## Features

- **Browsing**
  - Folders and files, shown as a grid or a list.
  - Breadcrumbs, pull to refresh, and shared group folders.
  - Badges for protected and shared items, and live progress while a file converts.
- **Search** across every folder you can see.
- **Preview**
  - Swipe left or right through the files of the folder or search you opened it from ("3 of 12").
  - Images and videos zoom: pinch, double-tap, and pan while zoomed. At normal size a swipe changes the file.
  - Videos have their own controls (play/pause, scrubber); tap to show or hide them.
  - Audio, PDFs, and text or code files.
  - Share or save any file, downloaded to disk first, which includes Save to Files and Save Image.
- **Upload**
  - Photos and videos from Photos, any files, or a whole folder; a folder's tree is recreated on the server.
  - Four uploads run at a time, with speed and time left shown for each.
- **Organize**
  - New folder, rename, move (a folder tree that won't offer a folder's own subfolders), and delete.
  - Select several items to move them, set a password on all of them, or delete them.
- **Passwords**
  - Lock a folder or a single file.
  - A protected folder asks for its password when opened. Changing a protected item asks for its password
    first.
  - Passwords are remembered until the app quits, as the web app does with sessionStorage.
- **Face ID locks** (iOS only)
  - Lock any folder or file with Face ID from its menu.
  - **Face ID or passcode** falls back to the iPhone passcode, or to the Orbit password if the item has one.
  - **Face ID only** has no fallback. If Face ID fails, it stays shut. After too many tries, iOS keeps Face ID
    locked until the phone is unlocked with its passcode.
  - A folder's lock covers everything inside it, including subfolders, search hits and thumbnails.
  - Locks stay passed until Orbit goes to the background.
  - Locks are kept per account in Orbit's settings on the server (`faceIdLocks`, set with
    `PUT/DELETE /api/orbit/settings/face-id/:itemId`), so every iPhone signed in to the account has them. The
    web ignores them: this guards against someone holding your unlocked phone, not against someone with your
    account.
- **Settings**
  - Sync now, and the account (profile, account theme, sign in on another device by QR code).
  - Appearance and grid or list view.
  - Orbit's conversion settings (videos to MP4, HEIC to JPEG, convert existing files), stored on the server
    and saved as soon as a switch changes.
  - App lock (Face ID), problem reports with shake to report, and the privacy policy.

Deep link: `com.nucleushome.orbit://open?folder=<id>&highlight=<fileId>` opens a folder and points out a file,
like the web's `?folder=&highlight=`.

## Build

```sh
brew install xcodegen          # once
xcodegen generate              # after adding or moving files
open Orbit.xcodeproj
```

From the command line without switching `xcode-select`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## Nucleus ID

The app signs in as the public OAuth client `orbit`, with redirect URI `com.nucleushome.orbit:/oauth` and scope
`profile data`. Orbit's server only accepts tokens from the client `orbit` that carry the `data` scope
(`requireAppEnabled('orbit')`). So `main`'s `nucleus.app.json` needs `"nucleusId": { "clientId": "orbit" }`, and
the client must be registered on the Nucleus ID server once:

```sh
docker compose exec api npm run client -- create orbit "Orbit" com.nucleushome.orbit:/oauth
```

There is no default server. The person types one in, or opens a setup link or file from the server's
administrator. The app reads `{server}/api/v1/oauth/metadata` (the path can be changed under Advanced), signs
in at the `authorization_endpoint` it names, then calls `{server}/api/orbit/…` with the bearer token. That
includes the `raw` streams for thumbnails, video and downloads.

**Handing out a server.** On the server, `cd server && npm run server-code -- <host> [--scheme http] [--port 8080]`
prints a setup link and a `.nucleusserver` file:

    com.nucleushome.orbit://server?scheme=http&host=nas&port=8080&code=nucleus…home

**Tailscale.** IP addresses and MagicDNS short names work over http. `*.ts.net` names work over https, or over
http through an ATS exception, since the tailnet already encrypts the traffic. Other domains need https.

The client is not registered as `--trusted`. A custom URL scheme can be claimed by another app, and the consent
screen is what would show someone that an app they don't know is asking.

Its privacy policy is at `nucleus-home.dev/privacy/orbit`.

## Layout

| Folder | What's in it |
| --- | --- |
| `Orbit/App` | App entry, `RootView` (sheets, deep links, debug launch arguments), `Navigator`, app lock, launch handover |
| `Orbit/Account` | Nucleus ID sign-in, server discovery, QR login (shared with Todo and Watchlist) |
| `Orbit/Model` | `OrbitFile`, `OrbitFolder`, `Listing`, `FileKind`, formatting |
| `Orbit/Services` | `FilesService` with `OrbitClient` (the live server) and `SampleFiles` (in memory); `OrbitAPI` JSON mapping, multipart, `UploadQueue`, thumbnails, sharing |
| `Orbit/Store` | `FilesStore` (what's loaded, plus the session's passwords), preferences, keychain |
| `Orbit/Features` | Browser, Search, Actions (rename, password, unlock, move), Preview, Upload, Settings, Welcome, Account, Report |
| `design` | `cs.py` (Czech), `render-icon.swift` (the app icon) |

## Translations

English is written in the code. Czech lives in `design/cs.py`; regenerate the catalogs with `python3 design/cs.py`.
The shared Nucleus strings follow Todo's wording, and Orbit's own follow the web app's `cs-CZ.json`.

## Icon

`swift design/render-icon.swift <out.png> light|dark|tinted|splash` draws the web app's cloud-and-arrow mark in the
Todo and Shell icon style. Put the results in `AppIcon.appiconset` (`AppIcon-light/dark/tinted.png`), and put the
splash at 120 pt into `Splash.imageset`.

## Tests

- **Unit tests** cover:
  - The shared sign-in stack.
  - JSON mapping and both server error shapes.
  - Multipart bodies, including UTF-8 file names.
  - Formatting, the sample server's rules, and `FilesStore`: password prompts, locked search hits, Sync now and
    sign-out.
  - The Move tree and the upload queue: four at a time, failures, and folder uploads.
- **UI tests**:
  - `SmokeTests` cover opening a folder and a preview, a wrong password and then the right one, multi-select,
    new folder, Sync now, and unlocking a search hit.
  - `ScreenshotTests` save every screen to `TEST_RUNNER_SHOT_DIR`, in English and Czech.

Debug launch arguments:

| Argument | What it does |
| --- | --- |
| `-sampleData` | Uses `SampleFiles` instead of a server. The Work folder's password is `orbit`. |
| `-signedIn` | Fakes an account. |
| `-resetAll` | Starts from a clean state. |
| `-skipWelcome` | Skips the welcome screen. |
| `-appLock` | Turns the app lock on. |
| `-appearance light\|dark` | Sets the appearance. |
| `-view grid\|list` | Sets the browsing view. |
| `-faceID pass\|fail` | Scripts Face ID, since the simulator has no face. |
| `-faceIDLock <folder>[:strict]` | Starts with a sample root folder locked with Face ID. |
| `-route …` | Opens a screen: `settings`, `profile`, `search`, `welcome`, `signin`, `report`, `newfolder`, `folder:<name>`, `preview:<file>`, `move:<file>` or `unlock:<folder>`. |

## Known limits

- Uploads run while the app is open, with iOS's short background grace period. Uploads that keep going after
  you leave the app, a Share Extension and a Files-app provider are planned for a later version.
- There is no offline mode; everything comes from the server.
- There is no drag and drop between folders. Use Move or multi-select instead.
- A folder password protects only that folder's own contents, as on the server. A file found by search inside a
  protected folder asks for the password when it's opened.
- Unlock tokens for files last 6 hours. Passwords are kept only until the app quits.
