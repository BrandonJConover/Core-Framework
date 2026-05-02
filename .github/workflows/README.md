# GitHub Actions smoke tests

`smoke.yml` is the repo's fast compile/build gate. It runs on pushes and pull
requests targeting `develop`, plus manual `workflow_dispatch` runs.

## What It Catches

- Desktop Java client compile breaks via `Client_Base/build.xml`.
- `server-java-modern` core/plugin compile breaks via its Ant targets.
- 2009scape web-client patch-overlay or Parcel bundle breaks via
  `2009scape-web/setup.sh`.
- iOS compile breaks via `xcodegen generate` plus a generic iOS `xcodebuild`
  build with signing disabled.

## What It Does Not Catch

- Runtime gameplay regressions.
- iOS simulator/device UI behavior.
- Database-backed server logic bugs.
- Browser Playwright scenarios. Those belong in the follow-up integration
  workflow plan.

## Debugging A Red Run

- **Java job:** rerun the failed `ant` command locally from repo root. Modern
  server failures usually name the plugin or source file in the Ant log.
- **Web job:** rerun `cd 2009scape-web && ./setup.sh`. The workflow clones the
  ignored base client just like a fresh machine, then applies `client-patch/`.
- **iOS job:** rerun:

  ```bash
  cd iOS_Client/OpenRSC
  xcodegen generate
  xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath /tmp/openrsc-ci \
    CODE_SIGNING_ALLOWED=NO build
  ```

## Branch Protection

After the first green run, configure GitHub branch protection for `develop` to
require the `smoke / All smoke tests passed` status check before merging.

## Adding Another Smoke Target

Add a new job to `smoke.yml`, then add its job id to the `summary.needs` list.
Keep this workflow compile/build-only; runtime browser scenarios should live in
the separate Playwright integration workflow.
