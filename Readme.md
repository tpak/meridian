# Meridian

A macOS menu bar world clock. Track time across zones for your team, friends, and family.

## Features

- **Menu bar native** — lives in your macOS menu bar, one click away
- **Multiple time zones** — add as many locations as you need
- **3 display modes** — icon only, standard text, or compact view
- **Time scrubbing** — slide to see what time it will be elsewhere
- **Sunrise/sunset** — know when the sun rises and sets in each zone
- **Keyboard shortcuts** — global hotkey to toggle the panel
- **Start at login** — launches automatically with your Mac
- **Ad-free & open source**

## Install

Download the latest release from [GitHub Releases](https://github.com/tpak/meridian/releases).

Requires macOS 13 (Ventura) or later.

## Build from Source

```bash
git clone https://github.com/tpak/meridian.git
cd meridian

xcodebuild -project Clocker/Clocker.xcodeproj -scheme Meridian -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=
```

Requires Xcode 15+.

## Contributing

Pull requests welcome. Please open an issue first to discuss larger changes.

## Origin

Meridian began as a fork of [Clocker](https://github.com/n0shake/Clocker) by [Abhishek Banthia](https://github.com/n0shake). Since forking, it has diverged significantly — Firebase removal, async/await migration, feature simplification, full rebrand to 100% Swift — and is now maintained independently.

Thank you to Abhishek for creating the original Clocker and releasing it under the MIT License.

## License

MIT License. See [LICENSE](LICENSE) for the full text.
