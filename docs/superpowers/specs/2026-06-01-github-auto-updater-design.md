# GitHub-based Lightweight Auto-Updater — Design

- Date: 2026-06-01
- Repo: yoropico/gureum (fork of gureum/gureum), macOS input method
- Status: approved (design), pending spec review

## Goal

Give the fork a self-contained auto-update path: the app checks the fork's own
GitHub Releases, and on user confirmation downloads the new build and installs
it — instead of today's "open a download page, reinstall by hand" flow that also
points at the wrong (upstream) version feed.

## Context (verified, 2026-06-01)

- `OSX/UpdateManager.swift` already does version-checking: `requestVersionInfo`
  fetches `https://gureum.io/version.json` (Stable) / `version-experimental.json`
  (Experimental) — **upstream's** feed — decodes `UpdateInfo {version, description,
  url}`, and `notifyUpdateIfNeeded()` (called on launch) compares against
  `Bundle.main.version` (= `CFBundleVersion`, via `OSXCore/BundleVersion.swift`)
  using `!=`. On a newer version it posts a `UserNotification`; the menu
  ("버전 확인", `OSX/GureumMenu.swift`) shows an alert. Both then just
  `NSWorkspace.shared.open(info.update.url)` — manual download + reinstall.
- `UpdateMode` (`OSXCore/Configuration.swift`): `.Stable` / `.Experimental`;
  `Configuration.shared.updateMode: UpdateMode?`.
- The app lives at `/Library/Input Methods/Gureum.app` (system location → writing
  needs admin), bundle id `org.youknowone.inputmethod.Gureum`, and is signed
  Apple Development, team `G7J2LY4LP9` (personal). It is an IME agent launched by
  the input system, not a normally-relaunchable app.
- The committed project signs with the upstream team `9384JEL3M9` /
  "Developer ID Application"; personal builds override signing on the command
  line (do not commit team changes).

## Decisions (locked)

- **Lightweight custom updater** (not Sparkle).
- **Feed: GitHub Releases API.** Stable → `releases/latest`; Experimental →
  `releases` (first item, prereleases included).
- **Artifact: a `.zip` of the signed `.app`** attached to the GitHub Release.
- **UX: auto-check + one-click confirmed install** (notification/menu → user
  clicks Update → download → verify → privileged install → "log out to apply").
  Not silent/background.
- **Personal build is non-sandboxed** so the one-click privileged install works;
  the install code degrades gracefully (opens the release page) when sandboxed.

## Architecture

Two units with one responsibility each:

### UpdateManager (modify `OSX/UpdateManager.swift`) — "is there an update?"
- Repoint `requestVersionInfo(mode:)` to the GitHub REST API:
  - Stable: `GET https://api.github.com/repos/yoropico/gureum/releases/latest`
  - Experimental: `GET https://api.github.com/repos/yoropico/gureum/releases`
    → take the first element.
  - Send header `Accept: application/vnd.github+json`. Keep Alamofire; keep a
    short timeout (bump from 1.0s to ~5s — the API can be slightly slower than a
    static file, and a too-short timeout would silently skip checks).
- Decode the GitHub payload with new `Decodable` structs (subset):
  `GitHubRelease { tag_name: String, body: String?, html_url: String, prerelease: Bool, assets: [GitHubAsset] }`,
  `GitHubAsset { name: String, browser_download_url: String }`.
- Map to the existing `UpdateInfo`: `version = tag_name`,
  `description = body ?? ""`, `url = <the .zip asset's browser_download_url>`.
  Add `pageURL = html_url` for the fallback "open release page" path. Pick the
  asset whose `name` ends in `.zip` (first match); if none, treat as "no
  installable asset" → fall back to opening `pageURL`.
- **Version comparison:** replace the `!=` check with a semver-aware
  `isNewer(_ remote: String, than current: String) -> Bool`:
  - Normalize: strip a leading `v`/`V`; take the substring up to the first
    character that is not a digit or `.` (so `1.16.0`, `v1.16.0`, and
    `1.16.0-rc1`'s numeric core all parse); split on `.`; compare component-wise
    as integers (missing components = 0). Pre-release suffix is ignored for the
    numeric compare; ties with one side having a suffix are treated as
    not-newer (don't nag).
  - `notifyUpdateIfNeeded()` and the menu use `isNewer` instead of `!=`.

### Updater (new `OSX/Updater.swift`) — "download + install it"
A `final class Updater { static let shared = Updater() }` with one entry point
`func performUpdate(info: UpdateManager.VersionInfo, completion: @escaping (Result<Void, UpdaterError>) -> Void)`:

1. **Download** `info.update.url` (the `.zip`) to a unique temp dir
   (`FileManager.default.temporaryDirectory`) via Alamofire `download`.
2. **Unzip** with `/usr/bin/ditto -x -k <zip> <destDir>` (Process). Locate
   `Gureum.app` in the result.
3. **Verify integrity** before trusting it:
   - `codesign --verify --strict <app>` exits 0, AND
   - the app's `TeamIdentifier` equals the running app's team (read via
     `SecCode`/`codesign -dvv` parse; expected `G7J2LY4LP9`).
   - On mismatch → `.failure(.verification)`, abort, do not install.
4. **Install** to `/Library/Input Methods/Gureum.app`:
   - Build one shell command: `rm -rf <dest> && cp -R <newApp> <dest> &&
     /bin/kill -TERM <gureum pids> ; lsregister -f <dest>` (use absolute
     `lsregister` path).
   - Run it with admin via `NSAppleScript("do shell script \"…\" with
     administrator privileges")` → single auth prompt.
   - If the AppleScript call fails because the process is sandboxed (errAEEvent
     / -1743 / sandbox denial), **fall back**: reveal the unzipped app in Finder
     and `NSWorkspace.shared.open(info.pageURL)` so the user can install
     manually; report `.failure(.sandboxed)` so the caller shows guidance.
5. On success → `.success(())`; caller shows an alert: "업데이트 완료 — 로그아웃 후
   다시 로그인하면 적용됩니다." On `.failure` → caller shows an appropriate
   message (and for `.sandboxed`, that the release page was opened).

`enum UpdaterError { case download, unzip, verification, install, sandboxed, cancelled }`.

### Wiring (modify `OSX/GureumMenu.swift`, `OSX/GureumAppDelegate.swift`)
- Menu "버전 확인" (`checkVersion`): keep the "you're up to date" / "newer
  available" alert, but the action button now calls
  `Updater.shared.performUpdate(...)` instead of `NSWorkspace.open(url)`.
  Keep a secondary "릴리스 페이지 열기" affordance using `pageURL`.
- Notification action (`gureumUpdateNotificationActionIdentifier`, handled in
  `GureumAppDelegate.userNotificationCenter(_:didReceive:)`): currently opens
  `userInfo["url"]`. Change to trigger `Updater.shared.performUpdate(...)`.
  `notifyUpdate` already sets `userInfo["url"]`; extend it to also set
  `userInfo["version"]` and `userInfo["pageURL"]`, and the action handler
  reconstructs `VersionInfo`/`UpdateInfo` from those three values (no re-query).

### Sandbox / entitlements (build-level, not committed)
- The updater's privileged install only works in a **non-sandboxed** build. For
  yoros's personal build, sign without `app-sandbox`: use a personal entitlements
  file (e.g. `OSX/Gureum-personal.entitlements` containing no sandbox, or none at
  all — IOHID/network are unrestricted when non-sandboxed) passed via
  `CODE_SIGN_ENTITLEMENTS=…` on the xcodebuild command line. No project/committed
  change; the default committed entitlements stay sandboxed.
- The Updater code is identical in both builds; sandboxed builds just hit the
  graceful fallback in step 4.

## Release process (how a build reaches users)

1. Build the signed `.app` (the established recipe: `xcodebuild … -configuration
   Release … DEVELOPMENT_TEAM=G7J2LY4LP9 CODE_SIGN_STYLE=Automatic
   CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates` plus, for
   the updater build, the non-sandbox entitlements override).
2. `ditto -c -k --keepParent <Gureum.app> Gureum-<version>.zip`.
3. `gh release create <version> Gureum-<version>.zip --title … --notes …`
   (prerelease flag for Experimental).
4. The installed app's next check sees the new `releases/latest` and offers it.
- A `tools/release.sh` wrapping steps 1–3 is **optional follow-up**, out of scope
  for the core feature.

## Error handling

- Network failure / no release / no `.zip` asset / decode failure: auto-check
  (`notifyUpdateIfNeeded`) is silent; manual check shows "확인 실패" alert.
- `codesign`/team mismatch: abort install, alert "서명 검증 실패 — 설치를 중단했습니다."
- Admin prompt cancelled: `.cancelled`, no-op, no error alert.
- Sandboxed build: fall back to opening the release page + reveal in Finder.

## Testing

- Unit tests (`GureumTests`):
  - `isNewer`: `1.16.0` > `1.15.0`; `1.15.0` not > `1.15.0`; `1.10.0` < `1.9.0`
    is false (10 > 9 numerically); `v1.16.0` parses; `1.16.0-rc1` numeric core
    compares as `1.16.0` and a bare `1.16.0` is not "newer" than `1.16.0-rc1`.
  - GitHub JSON decode: a sample `releases/latest` payload decodes to
    `GitHubRelease`; the `.zip` asset is selected; `body == nil` maps to "".
- Manual verification (network + admin + filesystem, not unit-testable):
  build a non-sandboxed signed build, publish a test GitHub release with a higher
  tag + zip, confirm the app detects it, the one-click install runs with a single
  password prompt, and Korean input still works after re-login.

## Out of scope

- Sparkle, EdDSA appcast signing, delta updates.
- CI automation of releases (the optional `tools/release.sh` aside).
- Public distribution / Developer ID + notarization (personal use only;
  revisit if sharing).
- Changing the install location to `~/Library/Input Methods`.
