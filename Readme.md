# Meridian

A macOS menu bar world clock. Track time across zones for your team, friends, and family.

## Features

- **Menu bar native** — lives in your macOS menu bar, one click away
- **Multiple time zones** — add as many locations as you need
- **Time scrubbing** — slide to see what time it will be elsewhere
- **Calendar integration** — see upcoming events alongside your clocks
- **Sunrise/sunset** — know when the sun rises and sets in each zone
- **17+ languages** — localized for a global audience
- **Dark mode** — follows your system appearance
- **Compact & standard** — choose your preferred menu bar display
- **Keyboard shortcuts** — global hotkey to toggle the panel
- **Ad-free & open source**

## Install

Download the latest release from [GitHub Releases](https://github.com/tpak/meridian/releases).

## Build from Source

```bash
# Clone and set up API keys
git clone https://github.com/tpak/meridian.git
cd meridian
cp Clocker/Config/Keys.xcconfig.example Clocker/Config/Keys.xcconfig

# Build
xcodebuild -project Clocker/Clocker.xcodeproj -scheme Meridian -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=
```

Requires Xcode 15+ and macOS 13 (Ventura) or later.

## Contributing

Meridian is open for pull requests. If you'd like to help translate, [join the Crowdin project](https://crwd.in/clocker).

## Acknowledgments

Meridian is forked from [Clocker](https://github.com/n0shake/Clocker) by [Abhishek Banthia](https://github.com/n0shake), originally released under the MIT License. We're grateful for the foundation that made this project possible.

## License

Copyright (c) 2024 Chris Pak. Copyright (c) 2022 Abhishek Banthia. Released under the MIT License.
