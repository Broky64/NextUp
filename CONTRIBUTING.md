# Contributing to NextUp

Thanks for contributing to NextUp. This document defines the expected workflow and engineering standards for pull requests.

## Development Environment

Required:

- macOS (current major release recommended)
- Xcode 15+
- Swift 5.9+
- Git

Optional but recommended:

- [SwiftLint](https://github.com/realm/SwiftLint) for style and static checks

## Project Setup

1. Fork this repository.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/<your-username>/NextUp.git
   cd NextUp
   ```
3. Open `NextUp.xcodeproj` in Xcode.
4. Select the `NextUp` scheme and run (`⌘R`).
5. Grant Calendar permission when prompted.

## Branching and Commits

- Create focused branches from `main`.
- Use clear branch names, for example: `feature/calendar-search` or `fix/menu-title-truncation`.
- Keep commits atomic and descriptive.
- Prefer imperative commit subjects (example: `Fix menu title fallback for active events`).

## Coding Standards

- Follow Swift API Design Guidelines.
- Keep MVVM boundaries explicit:
  - `EventManager.swift`: state, permissions, EventKit coordination (ViewModel).
  - `ContentView.swift` / `SettingsView.swift`: rendering and user interaction (View).
- Avoid force-unwrapping unless there is a strict invariant with justification.
- Prefer small, testable methods and deterministic state transitions.
- Add or update DocC comments (`///`) for public and internal symbols when behavior changes.

## Linting

Install SwiftLint (optional but strongly recommended):

```bash
brew install swiftlint
```

Run lint checks from repository root:

```bash
swiftlint
```

If no custom `.swiftlint.yml` is present, SwiftLint default rules apply.

## Validation Before Opening a PR

At minimum:

1. Build the app in Xcode with no errors.
2. Manually verify permission flow:
   - first launch permission prompt
   - denied permission state
   - reopening settings from the app
3. Verify menu bar updates:
   - current/upcoming mode changes
   - countdown updates each minute
   - calendar filtering behavior
4. Re-run lint checks if SwiftLint is installed.

## Pull Request Expectations

Include the following in your PR description:

- Problem statement
- Scope of changes
- Manual verification steps
- Screenshots or short recordings for UI changes
- Related issue (if applicable)

Small, focused pull requests are reviewed faster than large mixed changes.

## Reporting Bugs and Feature Requests

- Bugs: open an issue with reproduction steps, expected behavior, and actual behavior.
- Features: open an issue describing the use case and proposed UX.

Use GitHub Issues: [https://github.com/Broky64/NextUp/issues](https://github.com/Broky64/NextUp/issues)
