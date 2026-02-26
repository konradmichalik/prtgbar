<div align="center">
  <img src="docs/images/prtg-logo-color.svg" alt="PRTGBar" width="80" height="80">

# PRTGBar

**PRTG Network Monitor in your macOS menu bar.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![Xcode 16](https://img.shields.io/badge/Xcode-16-blue?logo=xcode)](https://developer.apple.com/xcode/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

PRTGBar is a lightweight macOS menu bar agent that polls a PRTG Network Monitor instance and surfaces the full sensor hierarchy — probes, groups, devices, and sensors — directly in your menu bar. A live badge shows the count of sensors in a `down` state. Native notifications fire the moment a sensor transitions to `down`, so you know before your users do.

> [!NOTE]
> PRTGBar communicates with the **PRTG v1 REST API** (`/api/table.json`) using an API token for authentication. PRTG 22+ with API access enabled is required.

---

## ✨ Features

- **Live sensor tree** — probes → groups → devices → sensors, polled on a configurable interval (30 s – 5 min)
- **Menu bar badge** — shows the exact count of `down` sensors at a glance
- **Status summary bar** — color-coded pill counts for up / down / warning / paused sensors
- **macOS notifications** — fires when any sensor transitions to the `down` state
- **Auto-expand errors** — groups and devices with problems open automatically
- **Context menus** — jump directly to any object in the PRTG web UI with one click
- **Self-signed SSL support** — works with internal PRTG instances behind private certificates
- **Keychain storage** — the API key never touches `UserDefaults`; it lives in the system Keychain
- **Adaptive icon** — BW template image respects macOS light/dark menu bar appearance
- **No Dock icon** — pure agent app (`LSUIElement = true`), lives only in the menu bar

---

## 🔥 Installation

### Homebrew (recommended)

```sh
brew install konradmichalik/tap/prtgbar
```

> [!TIP]
> After installing via Homebrew, launch PRTGBar from Spotlight or Applications. On first launch, macOS may ask you to allow the app in **System Settings → Privacy & Security**.

### Build from source

See [Getting Started](#-getting-started) below.

---

## 🚀 Getting Started

### Prerequisites

| Tool | Version |
|------|---------|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 16+ |
| XcodeGen | any (`brew install xcodegen`) |

### Build

```sh
# 1. Clone the repo
git clone https://github.com/konradmichalik/prtgbar.git
cd prtgbar

# 2. Generate the Xcode project
make xcode

# 3. Open in Xcode and run, or build a release binary
make build
```

> [!IMPORTANT]
> Never edit `PRTGBar.xcodeproj` directly. All project configuration lives in `project.yml` (XcodeGen spec). Run `make xcode` to regenerate after any changes to that file.

---

## ⚙️ Configuration

Open the settings panel via the gear icon in the PRTGBar popover.

| Setting | Description |
|---------|-------------|
| **Server URL** | Your PRTG hostname or IP, e.g. `prtg.example.com`. HTTP/HTTPS scheme is optional — HTTPS is assumed when omitted. |
| **API Key** | A PRTG API token. Stored in the macOS Keychain, never in `UserDefaults`. |
| **Refresh Interval** | How often PRTGBar polls: 30 s, 1 min, 2 min, or 5 min. |
| **Auto-expand errors** | Automatically expand groups and devices that contain `down` sensors. |
| **Notifications** | Receive a macOS notification each time a sensor transitions to `down`. |

> [!WARNING]
> The API key requires sufficient PRTG permissions to read sensors, devices, groups, and probes across the entire object hierarchy. A read-only account with global visibility is recommended.

### Generating a PRTG API Token

1. Log in to your PRTG instance.
2. Go to **Setup → My Account → API Keys**.
3. Create a new key with **Read** access.
4. Paste the token into PRTGBar's **API Key** field.

---

## 💡 Usage

Once configured, PRTGBar polls your PRTG instance and renders the full object tree in the menu bar popover:

```
PRTGBar
├── [probe]  Core Network
│   ├── [group]   Datacenter A
│   │   ├── [device]  router-01
│   │   │   ├── ● Ping              up
│   │   │   └── ● CPU Load          warning
│   │   └── [device]  switch-01
│   │       └── ✕ Interface Eth0    down
│   └── [group]   Datacenter B
│       └── ...
└── [probe]  Remote Sites
    └── ...
```

**Context menus** on any row offer:
- **Open in PRTG** — opens the object's detail page in your browser
- **Copy Name / ID** — copies the object name or numeric PRTG ID to the clipboard

---

## 🧑‍💻 Contributing

Contributions are welcome. The project uses XcodeGen so there are no `.xcodeproj` merge conflicts.

```sh
# Run unit tests
xcodebuild test -scheme PRTGBar -destination 'platform=macOS'

# Clean all build artifacts and the generated project
make clean
```

**Project layout**

```
PRTGBar/
├── PRTGBarApp.swift          Entry point, MenuBarExtra scene
├── Models/
│   ├── AppState.swift        @MainActor observable, polling, notifications
│   └── PrtgData.swift        DTOs, TreeNode, TreeBuilder
├── Services/
│   ├── PrtgClient.swift      Async v1 API client, SSL delegate
│   └── KeychainService.swift Thin Security framework wrapper
└── Views/
    ├── MenubarView.swift      Popover: header, status pills, tree, footer
    ├── ObjectSection.swift    Recursive DisclosureGroup per object kind
    └── SettingsView.swift     Server URL, API key, interval, toggles
```

> [!NOTE]
> PRTGBar targets Swift 6 strict concurrency. All API calls run in detached tasks; UI mutations are dispatched back to `@MainActor`.

---

## 📜 License

MIT — see [LICENSE](LICENSE).
