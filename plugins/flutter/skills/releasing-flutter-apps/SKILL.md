---
name: releasing-flutter-apps
description: Set up or change the mobile release pipeline with fastlane — Gemfile and bundler, lanes per flavor (dev / staging / prod) that run unit tests, build the iOS IPA to TestFlight and the Android AAB to the Play internal track, build number = store latest + 1, prod version check and release-branch-only builds, prod never submitted for review or rolled out, annotated tags {stage}/{platform}/{version}+{build}, credentials only from the environment (App Store Connect .p8, Play service account), preflight checks, an outputs folder, one-time machine setup, an optional CI checklist and Firebase App Distribution lane. Use when adding fastlane, uploading a build to TestFlight or Play, changing build numbers, tags, or release credentials.
---

# Releasing Flutter apps

fastlane builds and uploads the **mobile** apps. The web build and any backend deploy through their own scripts, never through fastlane. Flavors, bundle ids, and dart-defines come from `configuring-flutter-flavors`; this skill maps them onto lanes and does not repeat them. Project specifics (flavor list, release branch, team id, tester groups): `CLAUDE.md` → Project facts.

**Ask first:** the first upload of a new app id (creates a store app), changing signing or the upload key, the release branch, giving a lane the right to submit for review or to roll out, and adding a CI provider.

## Templates

`templates/` next to this file; copy and replace the `Foo` / `com.example.foo` placeholders with the values of `configuring-flutter-flavors`:

| Template | Goes to |
| --- | --- |
| `Gemfile` | repository root (with `Gemfile.lock` committed after `bundle install`) |
| `fastlane/Fastfile` | `fastlane/Fastfile` |
| `fastlane/Pluginfile` | `fastlane/Pluginfile` |
| `fastlane/.env.example` | `fastlane/.env.example` (committed; the real `.env` is not) |
| `gitignore-lines.txt` | appended to `.gitignore` |

## Lanes

| Lane | Does |
| --- | --- |
| `ios <flavor>` / `android <flavor>` | `build_<flavor>` then `upload_<flavor>` |
| `ios build_<flavor>` | preflight → (prod: version check) → build number → tag free → `scripts/test.sh unit` → `flutter build ios --config-only` → `build_app` (gym) → `build-info.json` |
| `ios upload_<flavor>` | reads `build-info.json` → TestFlight upload → tag → after processing, What to Test and tester groups (`notes:none` skips the wait) |
| `android build_<flavor>` | preflight → signing → (prod: version check) → version code → tag free → unit tests → `flutter build appbundle` → `build-info.json` |
| `android upload_<flavor>` | reads `build-info.json` → Play `internal` track → tag |

- One `APPS` entry per flavor: `flavor`, `name`, `ios_bundle_id`, `android_package`, `tag_stage`, `dart_defines`. Lanes loop over it; a new flavor is one entry plus its native setup.
- Options: `build_number:N` (override), `notes:none`, `tests:none` (skip the unit suite; never for prod uploads in practice), `allow_dirty:true` (a local build that the upload lanes refuse), `notes:"…"`.
- Builds and uploads are separate lanes so a failed upload retries without a rebuild. The artifact and `build-info.json` (flavor, version, build number, tag, commit, clean tree, artifact path relative to the root) land in `build/fastlane/<flavor>/<platform>/`.

## Rules the lanes enforce

- **Tests before the build:** `scripts/test.sh unit` runs after the cheap checks and before the slow build (`testing` rule → Rules). Patrol is its own step, not part of a lane.
- **Build number = store latest + 1:** iOS `latest_testflight_build_number + 1`; Android the highest version code across `internal`, `alpha`, `beta`, `production` + 1 (a track that does not exist yet counts as empty). The optional Firebase lane uses the same Play number, so store builds never fall behind it. The version name comes from `pubspec.yaml`; Flutter gets `--build-number`.
- **Prod comes from the release branch only:** the commit must be on `<remote>/<release branch>`; dev and staging need the commit pushed to any remote branch. A dirty tree never uploads.
- **Prod version check:** the `pubspec.yaml` version must be greater than the version live in the store (App Store live version, the highest version in the Play production release names); before the first release there is none, and any version passes.
- **Prod never ships by itself:** TestFlight without groups or external testing, Play `internal` only. A human submits for review and rolls out in App Store Connect / Play Console.
- **Tags:** an annotated tag `{stage}/{platform}/{version}+{build}` (`prod/ios/1.4.0+57`) on the built commit, created right after the store accepts the upload. The tag must be free before the build starts; an existing tag means the build was already uploaded.
- **Release notes:** commit subjects since the previous tag of the same stage and platform (`git describe --match '{stage}/{platform}/*'`; the last 20 commits when there is none yet), or `notes:`, cut to the store limit (TestFlight 4000, Play 500).

## Credentials

Only from the environment: `fastlane/.env` locally (from `.env.example`), the CI secret store on CI. Nothing in the Fastfile, `Appfile`, or the repository.

- **App Store Connect API key** (`.p8`, role App Manager): `APP_STORE_CONNECT_API_KEY_KEY_ID`, `_ISSUER_ID`, and `_KEY_FILEPATH` locally or `_KEY_BASE64` on CI. The same key signs through `xcodebuild -allowProvisioningUpdates -authenticationKey*` (cloud-managed signing), so no certificates or `match` repository are needed.
- **Play service account JSON** with release rights for the app: `SUPPLY_JSON_KEY` (path) or `SUPPLY_JSON_KEY_DATA` (content).
- **Android upload key:** `android/key.properties` locally (git-ignored); on CI `ANDROID_KEYSTORE_BASE64` and passwords become a temporary `key.properties` and keystore, deleted in `after_all` and `error`.
- Key files live in the git-ignored `fastlane/keys/`. Logs never print key contents.

## Setup once per machine

1. Ruby 3.x with bundler; a UTF-8 locale (`export LANG=en_US.UTF-8`); `bundle install`.
2. Flutter at `.flutter-version`; on macOS Xcode, CocoaPods or Swift Package Manager as the project uses.
3. `cp fastlane/.env.example fastlane/.env`; put keys in `fastlane/keys/`; fill in the variables.
4. Git identity set (annotated tags need it); the remote reachable.
5. Dry run: `bundle exec fastlane android build_dev allow_dirty:true tests:none`.

## Steps to add fastlane

1. Copy the templates; fill `APPS` from the flavor setup; set the release branch; `IOS_TEAM_ID` and `PLAY_RELEASE_STATUS` (`draft` until the first release is published by hand) come from the environment.
2. Make sure each flavor's store app exists (TestFlight app, Play app with one manual first upload: Play's API cannot create an app).
3. Run each `build_<flavor>` locally, then `upload_dev` on both platforms; check the tag on the remote.
4. Document the commands in `README.md` (Release section) and the release branch in `CLAUDE.md` → Project facts.

## CI (optional)

When the project adds CI for releases: a macOS runner for iOS; secrets as the `*_BASE64` / `*_DATA` variables; `bundle exec fastlane <platform> <flavor>` on the release branch for prod and on a manual trigger for dev and staging; cache Ruby gems and the pub cache; keep artifacts from `build/fastlane/`; the runner needs tag push rights. A CI provider is "ask first".

## Firebase App Distribution (optional)

For tester builds outside the stores: add `fastlane-plugin-firebase_app_distribution` to the `Pluginfile`, authenticate with a service account file (never `FIREBASE_TOKEN`), and use the commented `firebase_dev` lane in the template. Dev or staging only; never prod.

## Verify

- `ruby -c fastlane/Fastfile`; `bundle exec fastlane lanes` lists every lane.
- A local `build_dev allow_dirty:true tests:none` produces the artifact and `build-info.json`; the matching upload lane refuses it.
- After a real upload: the build in TestFlight / Play internal, the tag on the remote, no temporary key files left.
