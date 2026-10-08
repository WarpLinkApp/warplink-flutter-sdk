# Releasing

Releases publish to pub.dev from a version tag through GitHub Actions
(`.github/workflows/release.yml`). The workflow uses OIDC, so no pub.dev token
is stored in the repository.

## First publish (one time)

pub.dev does not accept the first version of a package from automated
publishing. Do these steps once, before you push the first tag:

1. Create a verified publisher on pub.dev for the WarpLink domain.
2. From a clean checkout at the release commit, run `flutter pub publish --dry-run`. It must report 0 warnings.
3. Run `flutter pub publish` and publish version 1.1.0 by hand.
4. Move the package to the verified publisher on its admin page.
5. On the package admin page, open Automated publishing and enable publishing from GitHub Actions. Set the repository, and set the tag pattern to `v{{version}}`.

## First GitHub Release for v1.1.0

The manual publish creates no GitHub Release. A tag push would run the publish step again, and pub.dev rejects a version that exists. Create the first Release with the release-only path:

1. Make sure the `v1.1.0` tag exists on the release commit. If a tag push already started the workflow, its publish step fails because 1.1.0 is already on pub.dev. That is expected.
2. In GitHub, open Actions, select the release workflow, and click Run workflow.
3. Enter `v1.1.0` in the `tag` input and run it.

This is the `workflow_dispatch` path. It runs the tag, analyze, and test checks, creates the GitHub Release, and never publishes to pub.dev.

## Later releases

1. Set the same version in `pubspec.yaml`, `lib/src/version.dart`, `CHANGELOG.md`, the Android pin in `android/build.gradle.kts`, and the iOS floor in `ios/warplink_flutter/Package.swift`.
2. Push the tag `v<version>`.

The workflow refuses a tag that does not match those files, runs `flutter analyze` and `flutter test`, then publishes and creates the GitHub Release.

Run the workflow by hand (`workflow_dispatch`) only to create a GitHub Release for an existing `v*` tag. It runs the same checks and never publishes to pub.dev.
