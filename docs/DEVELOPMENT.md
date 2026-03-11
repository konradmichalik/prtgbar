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
├── PRTGBarApp.swift          Entry point, MenuBarExtra scene
├── Models/
│   ├── AppState.swift        @MainActor observable, polling, notifications
│   └── PrtgData.swift        DTOs, TreeNode, TreeBuilder, ProblemItem
├── Services/
│   ├── PrtgClient.swift      Async v1 API client, dual SSL sessions
│   └── KeychainService.swift Thin Security framework wrapper
└── Views/
    ├── MenubarView.swift      Popover: header, status pills, toolbar, footer
    ├── ProblemsView.swift     Grouped alert list with sticky section headers
    ├── AlertRowView.swift     Individual alert row with breadcrumb, icon, progress bar
    ├── SettingsView.swift     Server, refresh, notifications, appearance, connection
    └── AboutView.swift        Version info and update checker
```

> [!NOTE]
> PRTGBar targets Swift 6 strict concurrency. All API calls run in detached tasks; UI mutations are dispatched back to `@MainActor`.
