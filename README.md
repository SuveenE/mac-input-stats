<div align="center">
  <img src="MacInputStats/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" alt="Mac Input Stats" width="100" height="100">
  <h3 align="center">Mac Input Stats</h3>
  <p align="center">
    A macOS menu bar app that helps you understand how you use your Mac
    <br />
    through <b>typing</b>, <b>clicks</b>, <b>scrolling</b>, and <b>voice input</b>.
    <br />
    <br />
    <a href="https://github.com/SuveenE/mac-input-stats/releases/latest">
      <img src="https://img.shields.io/github/v/release/SuveenE/mac-input-stats?style=rounded&color=orange&labelColor=000000&label=release" alt="Release Version" />
    </a>
    <a href="LICENSE">
      <img src="https://img.shields.io/badge/license-MIT-green?labelColor=000000" alt="MIT License" />
    </a>
    <img src="https://img.shields.io/badge/macOS-14.0%2B-f7a41d?labelColor=000000" alt="macOS 14.0+" />
  </p>
  <br />
  <img src="assets/menubar-widget.png" alt="Menu bar widget" width="600">
</div>

## Install

1. Download `MacInputStats-x.x.x.dmg` from the [latest GitHub Release](https://github.com/SuveenE/mac-input-stats/releases/latest)
2. Open the DMG and drag **Mac Input Stats** to Applications
3. Launch **Mac Input Stats** and grant **Input Monitoring** when prompted

   <img src="assets/Input-monitoring-permissions.png" alt="Input Monitoring permission" width="480">

## Features

- **Menu bar widget** with a floating panel for quick-glance daily stats
- **Per-app breakdown** of keystrokes, clicks, scrolls, screen time, and talk time
- **Talk time detection** using CoreAudio microphone activity monitoring
- **Trend charts** with interactive 1d / 7d / 14d / 30d range picker
- **Daily persistence** with a rolling 7-day history

## Data Storage

All data is stored locally in `UserDefaults` — nothing is sent to any server. The plist file lives at:

```
~/Library/Preferences/com.suveene.MacInputStats.plist
```

## License

MIT License. See [LICENSE](LICENSE) for details.
