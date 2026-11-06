# Development

## Prerequisites

| Tool | Version |
|------|---------|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 16+ |
| XcodeGen | any (`brew install xcodegen`) |

## Build

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

## Tests

```sh
xcodebuild test -scheme PRTGBar -destination 'platform=macOS'
```

The tests also run in CI on every push and pull request (`.github/workflows/test.yml`).

Run the app with `--demo` to use built-in demo data instead of a PRTG server.

## Clean

```sh
make clean
```

## Lint

```sh
make lint
```

## Project Layout

```
PRTGBar/
├── PRTGBarApp.swift              Entry point, settings scene, status item owner
├── Menu/
│   ├── StatusItemController.swift  NSStatusItem, menu actions, rebuild on open
│   ├── StatusItemState.swift       Icon and badge state from the menu model
│   ├── MenuModel.swift             Immutable snapshot the menu is built from
│   ├── MenuBuilder.swift           Native NSMenu: problems, projects, footer, lazy submenus
│   ├── MenuBuilder+Submenus.swift  Sensor, project, acknowledged and snooze submenus
│   ├── MenuHeaderViews.swift       Custom header views inside the menu
│   └── MenuText.swift              Shared menu copy and truncation
├── Notifications/
│   ├── AlertEngine.swift           Decides which alerts fire (wait, combine, flapping, reminders)
│   ├── AlertEngine+State.swift     Per-sensor tracking state
│   └── NotificationDispatcher.swift  Notification content and Acknowledge/Open in PRTG actions
├── Models/
│   ├── AppState.swift              @MainActor observable, polling, settings, actions
│   ├── AppState+Opening.swift      Opens objects in the PRTG web UI
│   ├── PrtgData.swift              DTOs, TreeNode, TreeBuilder, ProblemItem
│   ├── Project.swift               Projects, devices and subgroups from the tree
│   ├── ProblemList.swift           Sorted problems, acknowledged and paused lines
│   ├── StatusHistory.swift         Local 24 h history behind the strip, one up/down flag pair per 30 min
│   ├── SettingsMigration.swift     Migrates settings from older versions
│   └── DemoData.swift              Demo tree and history for `--demo`
├── Services/
│   ├── PrtgClient.swift            Async v1 API client, dual SSL sessions
│   ├── PrtgClient+WriteActions.swift  Acknowledge and pause
│   └── KeychainService.swift       Thin Security framework wrapper
└── Views/
    ├── SettingsView.swift          Tab container for the settings
    ├── Settings/                   General, Server and Notifications tabs
    └── AboutView.swift             Version info and update checker
```

> [!NOTE]
> PRTGBar targets Swift 6 strict concurrency. All API calls run in detached tasks; UI mutations are dispatched back to `@MainActor`.
