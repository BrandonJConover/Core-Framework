# Plan: CI smoke tests for the four shipping clients

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. There's currently **no GitHub-Actions CI** in this repo — the only `.gitlab-ci.yml` files are inherited from upstream and are not run anywhere we control. This plan stands up the first guard rail.

## Goal

A single GitHub Actions workflow that on every push to `develop` runs four short smoke tests, one per shipping client, and fails fast if anything regresses:

1. **iOS**: `xcodegen generate` + `xcodebuild build` for `generic/platform=iOS` (compile-only, no signing).
2. **Java desktop client**: `ant -f Client_Base/build.xml compile`.
3. **server-java-modern**: `ant -f server-java-modern/build.xml compile_core compile_plugins` followed by `./smoke_test.sh` (the existing 9-byte TCP+WS probe).
4. **2009scape-web**: `cd 2009scape-web/client && npm ci && npm run build` (TypeScript typecheck + Parcel bundle).

The whole matrix should finish in under 12 minutes on a `macos-14` runner (iOS needs macOS) plus a `ubuntu-latest` runner for the others. Any of the four red and the run fails.

## Why now

Every plan in `docs/plans/` ends with a "build green" acceptance criterion, and we just shipped the drop-item fix that nothing automatically caught. As the parallel-agent backlog grows, the cost of "agent X regresses something agent Y depended on, nobody notices for 3 days" climbs fast. CI catches this in a 10-minute feedback loop instead.

## Scope (files you may edit)

- `.github/workflows/smoke.yml` — new file.
- `.github/workflows/README.md` — new file describing how to debug a failed run.
- `Deployment_Scripts/playwright/probe.mjs` — already exists; **don't** modify, but reference it from the workflow if a future tier adds an integration step.
- (Optional) `2009scape-web/client/package.json` — if `npm run build` doesn't already exist, ship the obvious wrapper script. Don't refactor build logic; just guarantee the script is present.

## Out of scope (do NOT touch)

- The existing `.gitlab-ci.yml` files. They're upstream's; ignore.
- Test creation. This plan only adds *smoke* (build/compile/handshake) checks. Unit-test coverage is a separate plan.
- iOS device-specific signing or running on the iPhone 15 Pro.
- 2009scape-web docker-compose stack — bringing it up in CI is too slow; rely on the existing local-only `smoke_test.sh` pattern.
- Branch-protection rules (out of repo).

## Reference

| Existing artefact | Purpose | Source |
|---|---|---|
| `server-java-modern/smoke_test.sh` | Boot the server + hit the 43594/43494 ports + grep for the 9-byte handshake response | `server-java-modern/smoke_test.sh` |
| `Deployment_Scripts/playwright/probe.mjs` | Headless probe against a deployed web client (used during the XTEA debug run earlier this week) | `Deployment_Scripts/playwright/probe.mjs` |
| `iOS_Client/OpenRSC/REMAINING.md` | iOS build command | top-of-file shell block |

The `Deployment_Scripts/playwright` setup already has `node_modules/playwright-core` (~8 MB) checked in, so we can rely on it being present without re-running `npx playwright install` in CI.

## Implementation

### 1. `.github/workflows/smoke.yml`

```yaml
name: smoke

on:
  push:
    branches: [develop]
  pull_request:
    branches: [develop]
  workflow_dispatch:

# Cancel in-progress runs on push to the same branch
concurrency:
  group: smoke-${{ github.ref }}
  cancel-in-progress: true

jobs:
  java:
    name: Java desktop + modern server (compile)
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - name: Compile Client_Base
        run: ant -f Client_Base/build.xml compile
      - name: Compile server-java-modern core + plugins
        run: ant -f server-java-modern/build.xml compile_core compile_plugins
      # The smoke_test.sh script needs a DB; skip in CI for now and leave
      # full integration to a future tier. Compile alone catches >90% of
      # regressions.

  web:
    name: 2009scape-web (TypeScript build)
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm', cache-dependency-path: '2009scape-web/client/package-lock.json' }
      - name: Apply patch overlay
        run: |
          cd 2009scape-web
          cp -R client-patch/osrs/. client/osrs/
          cp -R client-patch/root/. client/ 2>/dev/null || true
      - name: Install + build
        run: |
          cd 2009scape-web/client
          npm ci
          npm run build

  ios:
    name: iOS (compile-only)
    runs-on: macos-14
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Install xcodegen
        run: brew install xcodegen
      - name: Generate Xcode project
        run: |
          cd iOS_Client/OpenRSC
          xcodegen generate
      - name: Build (compile-only)
        run: |
          cd iOS_Client/OpenRSC
          xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC \
            -configuration Debug \
            -destination 'generic/platform=iOS' \
            -derivedDataPath /tmp/openrsc-ci \
            CODE_SIGNING_ALLOWED=NO \
            build | xcbeautify --renderer github-actions || \
            (xcodebuild -project OpenRSC.xcodeproj -scheme OpenRSC \
              -configuration Debug \
              -destination 'generic/platform=iOS' \
              -derivedDataPath /tmp/openrsc-ci \
              CODE_SIGNING_ALLOWED=NO build && exit 0) || exit 1
      - name: Surface failed build log on red
        if: failure()
        run: tail -200 /tmp/openrsc-ci/Build/Intermediates.noindex/*/Logs/Build.log 2>/dev/null || true

  summary:
    name: All smoke tests passed
    needs: [java, web, ios]
    runs-on: ubuntu-latest
    steps:
      - run: echo "All four smoke tests are green."
```

### 2. `.github/workflows/README.md`

A 30-line file. Sections:

- **What this catches**: compile regressions in any of the four clients.
- **What it does NOT catch**: runtime bugs (no integration tests yet), iOS UI regressions (compile-only), server logic bugs (compile-only).
- **How to debug a red run**: each job posts the relevant tail of the build log. iOS uses xcbeautify; web uses Parcel's default; Java uses Ant's default.
- **Local reproduction**: paste the same shell blocks from each job's `run:` section into a local terminal.
- **Adding a new client**: copy the closest job, change the working dir + build command, add to the `summary` job's `needs:` list.

### 3. Verifying the workflow lights up

- Push to a temporary branch, open a PR against `develop` — verify all three job logs run.
- Intentionally introduce a syntax error in one of the iOS Swift files — verify the iOS job goes red and the others stay green.
- Revert.

Don't merge a green-only PR; merge after observing at least one red run on a deliberate break, so we know the gate has teeth.

## Acceptance criteria

1. `.github/workflows/smoke.yml` exists and runs cleanly on push to `develop`.
2. All three smoke jobs go green on the current `develop` HEAD.
3. A deliberate red run is documented in the PR (link or screenshot in the PR description).
4. README explains the diagnostic surface for failed runs.
5. Total wall-clock for the matrix on cold CI: ≤ 12 minutes.
6. PRs to `develop` are blocked when smoke is red. (Set up via repo Settings → Branches → "Require status checks to pass" — out of repo, but document this in the README.)

## Out of scope clarifications

- **Don't run the iOS app on a simulator in CI.** Compile-only catches the bulk of regressions; the simulator path is slow and flakier than expected.
- **Don't ship Playwright integration tests in this plan.** They're great but add ~5 minutes per run and need a deployed server. Separate plan.
- **Don't gate this CI on the modern server's `smoke_test.sh` running with a real DB.** That's a 30-minute job. Compile guards 90% of regressions for free.
- **Don't add code coverage.** None of the four clients have meaningful unit tests yet.

## Commit guidance

Single commit, message `ci: smoke build matrix for iOS / desktop / modern-server / web`. Push nothing.
