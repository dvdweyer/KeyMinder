# KeyMinder Backlog

## App Icons

- **macOS 26 (Tahoe) adaptive icon support** — macOS 26 auto-generates acceptable layered "Liquid Glass" versions from the existing flat icons (solid blue gradient + white symbol), so no action needed now. Proper support requires creating a `.icon` layered file per icon variant using Icon Composer (bundled with Xcode 26), producing a compiled `Assets.car` alongside the existing `.icns`. A ~30-min design-tool job when the time is right. All three variants (AppIcon, AppIconOption, AppIconControl) need the same treatment.

## Updater

- **Bring app to front when update result window appears** — branch `not-working-updater-window-frontmost` has a WIP implementation (`feat: activate app when manual update check surfaces result window`, v1.0.127). Parked because it wasn't working correctly. Revisit before next stable release.
