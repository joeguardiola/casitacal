# 🏡 CasitaCal

A personal, Skylight-style family calendar for a kitchen iPad.

- **Events** sync two-way with a shared Google Calendar (phones keep using the Google Calendar app).
- **Family members** each own a Google event color, so events tagged on a phone show up with the right person.
- **Chores, lists and meals** sync through iCloud (CloudKit sharing) — coming soon.
- **Kiosk extras:** big clock, weather, sleep mode, photo slideshow — coming soon.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open CasitaCal.xcodeproj
```

Tests:

```sh
xcodebuild test -scheme CasitaCal -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
```

Inspired by [Skylight](https://www.skylightframe.com/) and [Kinboard](https://github.com/svenger87/kinboard).
