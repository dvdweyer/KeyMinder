# Contributing to KeyMinder

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 16 or later

## Building

Open `KeyMinder.xcodeproj` in Xcode and press ⌘R.

**Do not build into the project folder** if it lives in iCloud Drive — build products acquire iCloud extended attributes that cause `codesign` to fail. Build to the default DerivedData location or `/tmp`.

## Installing a development build for testing

KeyMinder needs Accessibility permission to read other apps' menus. macOS TCC only registers apps that run from a stable path — copy to `/Applications` before granting:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/KeyMinder-*/Build/Products/Debug/KeyMinder.app /Applications/
xattr -cr /Applications/KeyMinder.app
open /Applications/KeyMinder.app
```

## Versioning

Every commit that changes behaviour must bump the patch number of `MARKETING_VERSION` in `KeyMinder.xcodeproj/project.pbxproj`. The version is tagged `vX.Y.Z` after each release. Check the current version with:

```bash
git tag --sort=-v:refname | head -1
```

## Submitting changes

1. Fork the repository and create a branch from `main`.
2. Make your changes with a version bump if applicable.
3. Open a pull request against `main`. The CI workflow builds and runs unit tests automatically -- that has not yet been tested well enough, be prepared for some errors there.

## Filing issues

Open an issue on [GitHub](https://github.com/dvdweyer/KeyMinder/issues). Please include your macOS version and the name of the app whose shortcuts are affected. Keep in mind I am one person doing this in my free time.
