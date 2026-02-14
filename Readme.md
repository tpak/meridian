# Meridian

A macOS menu bar world clock. Track time across zones for your team, friends, and family.

## Features

- **Menu bar native** — lives in your macOS menu bar, one click away
- **Multiple time zones** — add as many locations as you need
- **3 display modes** — icon only, standard text, or compact view
- **Time scrubbing** — slide to see what time it will be elsewhere
- **Calendar integration** — see upcoming events alongside your clocks
- **Reminders** — set reminders in any timezone
- **Sunrise/sunset** — know when the sun rises and sets in each zone
- **iCloud sync** — keep timezones in sync across your Macs
- **5 themes** — light, dark, system, solarized light, solarized dark
- **17+ languages** — localized for a global audience
- **Keyboard shortcuts** — global hotkey to toggle the panel
- **Ad-free & open source**

## Install

Download the latest release from [GitHub Releases](https://github.com/tpak/meridian/releases).

Requires macOS 13 (Ventura) or later.

## Build from Source

```bash
git clone https://github.com/tpak/meridian.git
cd meridian
cp Clocker/Config/Keys.xcconfig.example Clocker/Config/Keys.xcconfig
# Edit Keys.xcconfig to add your Google Geocoding API key (optional — search still works without it)

xcodebuild -project Clocker/Clocker.xcodeproj -scheme Meridian -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=
```

Requires Xcode 15+.

## Contributing

Pull requests welcome. If you'd like to help translate Meridian, [join the Crowdin project](https://crwd.in/clocker).

## Origin

Meridian began as a fork of [Clocker](https://github.com/n0shake/Clocker) by [Abhishek Banthia](https://github.com/n0shake). Since forking, it has diverged significantly — security hardening, Firebase removal, async/await migration, SwiftUI adoption, full rebrand — and is now maintained independently. This is **not** an upstream-compatible fork; please do not open PRs against the original project expecting compatibility.

Thank you to Abhishek for creating the original Clocker and releasing it under the MIT License.

## License

MIT License. Copyright (c) 2024 Chris Pak. Copyright (c) 2022 Abhishek Banthia.

See [LICENSE](LICENSE) for the full text.
