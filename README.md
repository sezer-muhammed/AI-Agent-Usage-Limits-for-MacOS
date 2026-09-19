# AI-Agent-Usage-Limits-for-MacOS

# AI Meter — Native macOS AI Usage & Model Intelligence Dashboard

## 0. Mission

Build a polished, lightweight, native macOS application called **AI Meter**.

The app should give the user a single place to monitor:

- OpenRouter usage and limits
- The best currently available free OpenRouter models
- Model intelligence / coding / agentic benchmark data
- Claude subscription usage limits
- Codex usage limits
- Two separate Codex accounts
- Models available to each account
- Historical usage
- Desktop widgets
- Menu bar status

The application must feel like a first-party macOS utility:

- Native Swift / SwiftUI
- Fast startup
- Cached-first rendering
- Extremely low idle CPU usage
- Extremely low battery impact
- No Electron
- No browser/webview UI
- No continuous polling
- No cloud backend
- No unnecessary LLM calls
- No scheduled Codex/Claude agents for routine data gathering

The main principle is:

> Use official machine-readable provider interfaces whenever possible, cache locally, and render instantly from local state.

---

# 1. Product Goals

The user should be able to glance at the menu bar or desktop widget and immediately answer:

1. What is the smartest free model available on OpenRouter right now?
2. What is the strongest free model for coding?
3. What is the strongest free model for agentic/tool use?
4. Which free models are actually reliable/available?
5. How much of my OpenRouter account/key allowance have I consumed?
6. How much Claude usage do I have left?
7. When do my Claude limits reset?
8. How much Codex quota remains on account A?
9. How much Codex quota remains on account B?
10. When do those Codex limits reset?
11. Which models are available on each account?
12. How has my usage changed over time?
13. Have any interesting new free models appeared?

The application should prioritize information density without appearing cluttered.

---

# 2. Non-Goals for V1

Do not build these in V1:

- Cloud backend
- User accounts for AI Meter
- Cross-device sync
- iOS app
- Electron/Tauri application
- Generic chat interface
- LLM prompt execution
- Automatic model routing
- Automated purchasing
- Automated API-key rotation
- Scraping provider dashboards where an official interface is available
- Reading Claude OAuth tokens
- Reading Codex OAuth tokens directly
- Uploading private usage data anywhere
- Background polling every few minutes
- App Store distribution

Architect things cleanly enough that some of these could be added later.

---

# 3. Target Platform

Target:

- macOS current stable release
- Apple Silicon first
- Swift latest stable supported by Xcode
- SwiftUI
- AppKit only where SwiftUI is insufficient

Distribution for V1:

- Direct macOS application
- Developer ID signing later
- Notarization later
- Do not design around Mac App Store sandbox restrictions yet

Use a deployment target that supports:

- `MenuBarExtra`
- WidgetKit
- `SMAppService`
- modern Swift concurrency

---

# 4. High-Level Architecture

Use this architecture:

```text
┌──────────────────────────────────────────┐
│                AI Meter                  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ MenuBarExtra / Dashboard / Settings│  │
│  └──────────────────┬─────────────────┘  │
│                     │                    │
│               AppState / Store            │
│                     │                    │
│          Provider Repository Layer        │
│                     │                    │
│    ┌────────────┬───┴─────┬──────────┐   │
│    │            │         │          │   │
│ OpenRouter   Claude    Codex A    Codex B │
│ Adapter      Adapter   Adapter     Adapter │
│    │            │         │          │   │
│  REST       Bridge     AppServer  AppServer│
│                     │                    │
│            Persistence Layer             │
│                     │                    │
│      ┌──────────────┴────────────┐        │
│      │ SQLite/SwiftData history │        │
│      │ App Group snapshot.json  │        │
│      └──────────────┬────────────┘        │
└─────────────────────┼─────────────────────┘
                      │
                 WidgetKit
```

The UI must never communicate directly with provider APIs.

Everything should go through provider adapters and repositories.

---

# 5. Repository / Xcode Structure

Recommended project structure:

```text
AIMeter/
├── AIMeter.xcodeproj
├── App/
│   ├── AIMeterApp.swift
│   ├── AppDelegate.swift
│   ├── AppState.swift
│   └── AppEnvironment.swift
│
├── Core/
│   ├── Models/
│   │   ├── Provider.swift
│   │   ├── ProviderAccount.swift
│   │   ├── UsageSnapshot.swift
│   │   ├── RateLimitWindow.swift
│   │   ├── AIModel.swift
│   │   ├── ModelBenchmark.swift
│   │   ├── ModelAvailability.swift
│   │   └── DashboardSnapshot.swift
│   │
│   ├── Protocols/
│   │   ├── UsageProvider.swift
│   │   ├── ModelCatalogProvider.swift
│   │   ├── BenchmarkProvider.swift
│   │   └── SnapshotRepository.swift
│   │
│   ├── Networking/
│   │   ├── HTTPClient.swift
│   │   └── APIError.swift
│   │
│   ├── Persistence/
│   │   ├── Database.swift
│   │   ├── UsageSnapshotRepository.swift
│   │   ├── ModelSnapshotRepository.swift
│   │   └── WidgetSnapshotWriter.swift
│   │
│   ├── Security/
│   │   └── KeychainStore.swift
│   │
│   ├── Scheduling/
│   │   └── RefreshCoordinator.swift
│   │
│   └── Utilities/
│       ├── DateFormatting.swift
│       ├── AtomicFileWriter.swift
│       └── Logger.swift
│
├── Providers/
│   ├── OpenRouter/
│   │   ├── OpenRouterClient.swift
│   │   ├── OpenRouterUsageAdapter.swift
│   │   ├── OpenRouterModelsAdapter.swift
│   │   └── OpenRouterDTO.swift
│   │
│   ├── Claude/
│   │   ├── ClaudeStatusAdapter.swift
│   │   ├── ClaudeBridgeReader.swift
│   │   └── ClaudeDTO.swift
│   │
│   └── Codex/
│       ├── CodexAppServerClient.swift
│       ├── CodexAccountAdapter.swift
│       ├── CodexProcessController.swift
│       └── CodexDTO.swift
│
├── Features/
│   ├── MenuBar/
│   ├── Dashboard/
│   ├── Models/
│   ├── Usage/
│   ├── Settings/
│   └── Onboarding/
│
├── Shared/
│   ├── Components/
│   ├── Theme/
│   └── Formatting/
│
├── Widget/
│   ├── AIMeterWidget.swift
│   ├── AIMeterWidgetProvider.swift
│   └── WidgetViews/
│
├── Helpers/
│   └── ClaudeBridge/
│
└── Tests/
```

Keep provider-specific DTOs out of Core.

Core should contain normalized application models only.

---

# 6. Core Provider Abstractions

Define normalized protocols.

Example:

```swift
protocol UsageProvider: Sendable {
    var providerID: Provider.ID { get }

    func fetchUsage() async throws -> UsageSnapshot
}

protocol ModelCatalogProvider: Sendable {
    func fetchModels() async throws -> [AIModel]
}
```

Codex accounts must each be separate provider instances.

For example:

```swift
CodexAccountAdapter(
    accountID: "codex-personal",
    codexHome: ~/.codex-personal
)

CodexAccountAdapter(
    accountID: "codex-secondary",
    codexHome: ~/.codex-secondary
)
```

Do not special-case UI logic for providers.

Normalize first.

---

# 7. Normalized Usage Model

Use a representation approximately like:

```swift
struct UsageSnapshot: Codable, Sendable {
    let provider: Provider
    let accountID: String
    let capturedAt: Date

    let windows: [RateLimitWindow]

    let spendTodayUSD: Decimal?
    let spendWeekUSD: Decimal?
    let spendMonthUSD: Decimal?

    let creditsRemainingUSD: Decimal?

    let activeModelID: String?
}
```

Rate limit:

```swift
struct RateLimitWindow: Codable, Sendable, Identifiable {
    enum Kind: String, Codable {
        case session
        case fiveHour
        case daily
        case weekly
        case monthly
        case custom
    }

    let id: String
    let kind: Kind

    let usedFraction: Double?
    let remainingFraction: Double?

    let resetsAt: Date?

    let durationMinutes: Int?
    let label: String
}
```

Never assume all providers expose equivalent limits.

Missing values should remain `nil`.

Do not fabricate estimates unless explicitly labeled as estimates.

---

# 8. OpenRouter Integration

## 8.1 Authentication

User supplies an OpenRouter API key through Settings.

Store it exclusively in macOS Keychain.

Never:

- save in UserDefaults
- save in SQLite
- save in JSON
- print in logs
- commit into project
- expose to Widget extension

Keychain service example:

```text
com.aimeter.credentials
```

account:

```text
openrouter-api-key
```

---

# 9. OpenRouter Usage

Use official OpenRouter APIs.

Retrieve key/account usage information.

Normalize available values including, when exposed:

```text
usage
usage_daily
usage_weekly
usage_monthly
limit
limit_remaining
limit_reset
is_free_tier
```

Important:

Do not incorrectly interpret dollar spend as free-request count.

If the API does not expose exact number of free requests consumed:

DO NOT show:

```text
37 / 50 free requests used
```

unless that number is genuinely available.

Instead show truthful information such as:

```text
Free tier
Daily allowance: 50 requests
Spend today: $0
Key limit remaining: ...
```

The UI should distinguish:

```text
Allowance
Usage
Spend
Credits
```

These are not interchangeable.

---

# 10. OpenRouter Model Catalog

Retrieve the official OpenRouter model catalog.

Normalize:

```swift
struct AIModel: Codable, Sendable, Identifiable {
    let id: String
    let displayName: String

    let provider: String
    let contextLength: Int?

    let inputPricePerMillion: Decimal?
    let outputPricePerMillion: Decimal?

    let isFreeVariant: Bool

    let supportedModalities: [String]

    let benchmark: ModelBenchmark?
    let availability: ModelAvailability?
}
```

Detect free variants primarily through actual OpenRouter free variants such as:

```text
:free
```

Do not classify every zero-priced endpoint as equivalent without validation.

---

# 11. Model Benchmark Layer

The app should maintain multiple benchmark dimensions.

Do NOT produce one unexplained artificial score.

Model benchmark:

```swift
struct ModelBenchmark: Codable, Sendable {
    let intelligence: Double?
    let coding: Double?
    let agentic: Double?

    let source: BenchmarkSource
    let capturedAt: Date
}
```

UI examples:

```text
Intelligence    34.5
Coding          69.1
Agentic         41.7
Context         1M
Availability    99.6%
```

Support:

```text
Best General Free
Best Coding Free
Best Agentic Free
Best Reliable Free
```

These should be computed independently.

Do not imply that one model is universally "best."

---

# 12. Model Ranking Engine

Create:

```swift
struct ModelRankingEngine
```

Functions approximately:

```swift
func bestGeneralFree(...)
func bestCodingFree(...)
func bestAgenticFree(...)
func bestReliableFree(...)
```

For ranking, use the relevant benchmark directly.

Examples:

```text
General:
sort by intelligence descending

Coding:
sort by coding descending

Agentic:
sort by agentic descending
```

Reliability should account for availability when availability data exists.

Do not silently combine arbitrary metrics.

If implementing a composite ranking later, expose the formula explicitly.

---

# 13. Availability

Track endpoint/model availability separately from intelligence.

Possible normalized structure:

```swift
struct ModelAvailability: Codable, Sendable {
    let percentage: Double?
    let capturedAt: Date
    let sampleWindowDescription: String?
}
```

A very strong model with poor availability should visually show both facts.

Example:

```text
Qwen ...
Intelligence 33.9
Availability 72%
```

Do not hide reliability problems by ranking only benchmarks.

---

# 14. Model History

Store model snapshots.

This enables:

```text
NEW
↑ 2
↓ 1
Removed
Availability ↓
Benchmark changed
```

Do not only store the current catalog.

Suggested tables:

```text
model_snapshots
model_rank_snapshots
```

History does not need every raw payload.

Store normalized values.

---

# 15. Claude Integration

Claude subscription limits should NOT be implemented through an Anthropic API key.

Claude Pro/Max subscription usage and Anthropic API billing are different systems.

Use Claude Code's official status-line telemetry.

---

# 16. Claude Status-Line Bridge

Claude Code status-line telemetry can expose information such as:

```text
model
context usage
session information

rate_limits.five_hour.used_percentage
rate_limits.five_hour.resets_at

rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
```

Build a tiny helper executable:

```text
aimeter-claude-bridge
```

Its only job:

1. Accept/read Claude status-line JSON.
2. Extract allowed telemetry.
3. Normalize it.
4. Atomically write sanitized output.
5. Optionally forward/chains to user's existing status-line script.

Never capture or copy Claude authentication tokens.

---

# 17. Claude Bridge Output

Example sanitized representation:

```json
{
  "schemaVersion": 1,
  "capturedAt": "2026-09-19T12:00:00Z",
  "model": {
    "id": "claude-opus",
    "displayName": "Claude Opus"
  },
  "rateLimits": {
    "fiveHour": {
      "usedPercentage": 72.3,
      "resetsAt": "2026-09-19T15:30:00Z"
    },
    "sevenDay": {
      "usedPercentage": 38.1,
      "resetsAt": "2026-09-23T00:00:00Z"
    }
  }
}
```

Only sanitized usage metadata.

---

# 18. Existing Claude Status Line

The user may already use a status-line command.

Do not blindly overwrite it.

Implement detection.

During setup:

```text
Existing Claude status line detected.

[ Integrate with existing ]
[ Replace ]
[ Cancel ]
```

Preferred behavior is chaining/teeing.

Preserve the user's existing behavior whenever technically possible.

Before modifying any user configuration:

- show exactly what will change
- make a backup
- make the operation reversible

---

# 19. Claude Freshness

Claude usage telemetry may be event-driven.

Therefore the UI must expose freshness:

```text
Claude
5h 72%
7d 38%

Updated 18m ago
```

If older than a threshold:

```text
Stale
```

Do not pretend it is real-time when it is not.

Suggested thresholds:

```text
< 30 min      normal
30–120 min    slightly stale
> 120 min     stale indicator
```

Make thresholds configurable internally.

---

# 20. Codex Integration

Use Codex's official App Server interface.

Do not scrape UI.

Do not parse auth tokens.

Do not copy token files.

Use the supported RPC methods exposed by the installed Codex version.

At minimum investigate/use:

```text
account/read
account/rateLimits/read
account/usage/read
model/list
```

Also listen for relevant update notifications when supported.

Important:

Before implementing RPC calls, inspect the currently installed Codex version and verify the exact current schema/method names against official documentation.

Do not hard-code assumptions without validation.

---

# 21. Two Codex Accounts

Support two independent accounts.

Use isolated `CODEX_HOME` directories:

```text
~/.codex-aimeter-personal
~/.codex-aimeter-secondary
```

Each directory should be logged in independently.

Never accomplish multi-account by copying an existing `auth.json`.

Avoid token-copying because refresh-token rotation can make duplicated credentials unreliable.

Provide setup flow:

```text
Codex Account 1
[ Sign in ]

Codex Account 2
[ Sign in ]
```

Launch Codex process with:

```text
CODEX_HOME=<profile-directory>
```

---

# 22. Codex Process Management

Create:

```swift
actor CodexProcessController
```

Responsibilities:

- launch app-server
- set `CODEX_HOME`
- establish IPC/RPC transport
- monitor process termination
- restart if needed during an active refresh
- enforce timeout
- shut process down after work is complete

Do not leave two permanent Codex processes running unnecessarily.

Preferred sequence:

```text
refresh requested
      ↓
launch Codex app-server
      ↓
read limits
read usage
read models
      ↓
persist snapshot
      ↓
terminate process
```

If maintaining the process has a major measurable performance benefit, benchmark before changing this.

Battery efficiency takes priority.

---

# 23. Codex Account Data

Normalize information such as:

```text
plan type
used percentage
reset timestamp
window duration
credits
rate-limit status
usage history
available models
```

Example card:

```text
Codex — Personal

Weekly
███████░░░ 68%

Reset
Tuesday 3:00 PM

Models
GPT-...
GPT-...
```

---

# 24. Current Model Intelligence

Model availability and model intelligence are different concepts.

For each user account, obtain:

```text
Models accessible to account
```

Then join with benchmark catalog using canonical model IDs.

Example:

```text
Claude
✓ Opus
✓ Sonnet

Codex Personal
✓ GPT-X
✓ GPT-Y

OpenRouter Free
✓ DeepSeek ...
✓ Qwen ...
```

Then benchmark information can be displayed consistently.

Implement a model canonicalization layer.

---

# 25. Model Canonicalization

Provider model identifiers will differ.

Create:

```swift
struct CanonicalModelID: Hashable, Codable
```

and mapping infrastructure.

Example conceptually:

```text
openrouter/provider/foo
provider/foo-version
foo-version-date
```

may map to:

```text
canonical: foo-version
```

Do not rely purely on display-name string matching.

Mapping may require:

- exact IDs
- aliases
- provider
- release/version metadata

Unknown models must remain visible even when no benchmark match exists.

Show:

```text
Benchmark unavailable
```

rather than dropping them.

---

# 26. Persistence

Use a real local persistence layer for historical data.

Preferred options:

1. SQLite via GRDB
2. SwiftData if it cleanly satisfies all requirements

GRDB is preferred if predictable migrations and explicit SQL are desired.

The widget should NOT directly query the main historical database.

---

# 27. Suggested Database Schema

Example:

```sql
accounts
--------
id
provider
display_name
profile_path
created_at
updated_at


usage_snapshots
---------------
id
account_id
provider
captured_at
spend_today
spend_week
spend_month
credits_remaining
active_model_id


rate_limit_snapshots
--------------------
id
usage_snapshot_id
kind
label
used_fraction
remaining_fraction
resets_at
duration_minutes


models
------
canonical_id
provider_model_id
provider
display_name
context_length
is_free
first_seen_at
last_seen_at


model_benchmark_snapshots
-------------------------
id
canonical_model_id
captured_at
intelligence
coding
agentic
source


model_availability_snapshots
----------------------------
id
canonical_model_id
captured_at
availability_percentage
window_description


model_rank_snapshots
--------------------
id
captured_at
category
canonical_model_id
rank
```

Add indexes where needed.

---

# 28. Data Retention

Do not let the database grow forever.

Recommended:

Usage snapshots:

```text
raw:
30 days

hourly/downsampled:
180 days

daily:
indefinite or 1 year
```

Model benchmark changes are relatively infrequent and can be retained much longer.

Implement cleanup as a cheap deferred operation.

---

# 29. Widget Snapshot

Widget reads a tiny JSON snapshot through App Group.

Example:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-09-19T13:00:00Z",

  "bestFree": {
    "general": {
      "name": "DeepSeek ...",
      "score": 34.5
    },
    "coding": {
      "name": "Model ...",
      "score": 69.1
    },
    "agentic": {
      "name": "Model ...",
      "score": 46.5
    }
  },

  "accounts": [
    {
      "id": "claude",
      "displayName": "Claude",
      "primaryUsage": 0.72,
      "resetsAt": "..."
    },
    {
      "id": "codex-personal",
      "displayName": "Codex Personal",
      "primaryUsage": 0.58,
      "resetsAt": "..."
    }
  ]
}
```

Widget snapshot must contain no secret credentials.

---

# 30. Widget Snapshot Writing

Always use atomic writes.

Sequence:

```text
encode temporary file
fsync if appropriate
atomic replace
notify WidgetKit
```

Widget must never read a partially written JSON file.

Use versioned schema:

```text
schemaVersion
```

so future app versions can migrate safely.

---

# 31. App Group

Configure an App Group such as:

```text
group.com.<developer>.aimeter
```

Use this only for data that must be shared with WidgetKit.

Do not put provider credentials there.

---

# 32. Keychain

Implement:

```swift
actor KeychainStore
```

Public API roughly:

```swift
func setSecret(_ value: String, for key: CredentialKey) throws
func secret(for key: CredentialKey) throws -> String?
func deleteSecret(for key: CredentialKey) throws
```

Credentials:

```text
OpenRouter API key
```

Potential future API credentials can use same abstraction.

Claude/Codex authentication should remain under their own official authentication systems.

---

# 33. Refresh Architecture

Create:

```swift
actor RefreshCoordinator
```

Responsibilities:

- determine whether cached data is fresh
- schedule provider refreshes
- prevent duplicate concurrent requests
- manage provider-specific throttling
- persist successful results
- preserve previous snapshot on failure
- expose refresh state to UI

---

# 34. Suggested Refresh Policy

OpenRouter account usage:

```text
On app launch
On menu opening if cache > 15 min old
Background approximately every 30–60 min
Manual refresh
```

OpenRouter model catalog:

```text
Every 6 hours
Manual refresh
```

Benchmarks:

```text
Every 6–12 hours
```

Claude:

```text
Event-driven through bridge
No polling required
```

Codex:

```text
On app launch if stale
When menu opens if > 30–60 min old
Approximately hourly deferred refresh if app is active
Manual refresh
```

Widget:

```text
Updated after main app produces a new snapshot
```

These are guidelines.

Prefer system-coordinated/deferred execution.

---

# 35. Energy Rules

These rules are mandatory.

Do not:

```text
while true
Timer every minute
network polling every minute
permanent subprocesses without reason
WebViews
Electron
background animation
continuous SQLite writes
```

Prefer:

```text
NSBackgroundActivityScheduler
BG/system scheduling where applicable
async/await
event-driven updates
cache freshness checks
coalesced refreshes
atomic snapshots
```

When app is idle, expected CPU should be effectively zero.

---

# 36. Cached-First Rendering

The application should NEVER wait for networking before showing the UI.

Startup:

```text
read local cache
      ↓
render immediately
      ↓
start async refresh
      ↓
merge updates
      ↓
animate changed values
```

The dashboard should feel instant even offline.

No full-screen loading spinner after first setup.

---

# 37. Menu Bar Application

Use SwiftUI:

```swift
MenuBarExtra
```

Prefer window/popover-style content.

Suggested menu bar icon:

```text
gauge
waveform-like AI indicator
brain/head profile only if visually clean
```

Use SF Symbols where possible.

Avoid custom raster icons unless necessary.

---

# 38. Menu Bar Main View

Suggested layout:

```text
┌─────────────────────────────────────┐
│ AI Meter                     ↻      │
│ Updated 3m ago                      │
│                                     │
│ BEST FREE                           │
│ DeepSeek V4 Flash                   │
│ Intel 34.5 · Code 69.1 · 99.6%    │
│                                     │
│ OpenRouter                          │
│ Free tier                           │
│ Today $0.00                         │
│                                     │
│ Claude                              │
│ 5h   ███████░░ 72%      1h 42m    │
│ 7d   ███░░░░░░ 31%      Tue       │
│                                     │
│ Codex · Personal                    │
│ Weekly █████░░░░ 58%     Tue       │
│                                     │
│ Codex · Account 2                   │
│ Weekly ██░░░░░░░ 24%     Thu      │
│                                     │
│ [Open Dashboard]      [Settings]    │
└─────────────────────────────────────┘
```

Do not overload the menu bar popover with charts.

Charts belong in Dashboard.

---

# 39. Menu Bar Icon State

Potential state awareness:

Normal:

```text
standard monochrome icon
```

When one critical limit is nearly consumed:

```text
do not use annoying flashing
possibly add subtle badge/state change
```

Thresholds:

```text
>= 80% warning
>= 95% critical
```

Use semantic color only inside views where appropriate.

macOS menu bar icon should respect template rendering.

---

# 40. Main Dashboard

Open a normal resizable macOS window.

Suggested navigation:

```text
Overview
Models
Usage
History
Settings
```

A sidebar works well on macOS.

---

# 41. Overview Screen

Display:

```text
Best Free Models
Account Usage
Upcoming Resets
Recent Changes
Provider Health
```

Cards should use native material sparingly.

Avoid giant rounded mobile-style cards everywhere.

Respect desktop information density.

---

# 42. Models Screen

Table columns:

```text
Model
Provider
Free
Intelligence
Coding
Agentic
Context
Availability
Change
```

Features:

```text
search
sort
filter
```

Filters:

```text
Free only
Available to me
OpenRouter
Claude
Codex
High availability
```

Sorting:

```text
Intelligence
Coding
Agentic
Context
Availability
```

Use `Table` where native SwiftUI table behavior is suitable.

---

# 43. Model Detail

Selecting a model can show:

```text
Model name
Canonical ID
Provider IDs
Benchmarks
Availability
Context
Pricing
Modalities
First seen
Last updated
Rank history
Availability history
Accounts where accessible
```

Do not build an excessive detail screen for V1.

Focus on useful metrics.

---

# 44. Usage Screen

Group by provider/account.

Example:

```text
Claude

5-hour window
██████████████░░░░░ 72%
Resets in 1h 42m

7-day window
██████░░░░░░░░░░░░ 31%
Resets Tuesday


Codex Personal

Weekly
███████████░░░░░░░ 58%
Reset Tuesday
```

Display percentage labels explicitly.

Do not rely only on color.

---

# 45. History Screen

Initial chart support:

```text
Claude 5h usage over time
Claude weekly usage
Codex usage
OpenRouter spend
Model benchmark/rank changes
```

Keep charts minimal and native.

Avoid expensive live chart animations.

---

# 46. Settings

Sections:

```text
General
OpenRouter
Claude
Codex Accounts
Refresh
Privacy
About
```

---

# 47. General Settings

Options:

```text
Launch AI Meter at login
Show Dock icon
Open dashboard at launch
Menu bar display preference
```

Use:

```text
SMAppService
```

for login-at-startup.

---

# 48. OpenRouter Settings

Fields:

```text
API key
Connection status
Account/free-tier state
Last successful refresh
```

API key should be presented as secure text field.

Buttons:

```text
Test Connection
Remove Key
Refresh
```

Never reveal complete stored key after saving.

---

# 49. Claude Settings

Show:

```text
Claude Code detected: Yes/No
Bridge installed: Yes/No
Existing status line: Detected/None
Last telemetry update
```

Actions:

```text
Install Integration
Repair Integration
Remove Integration
```

Make integration reversible.

Store backups when modifying config.

---

# 50. Codex Settings

Account card:

```text
Codex Personal
Profile:
~/.codex-aimeter-personal

Status:
Connected

[Refresh]
[Reauthenticate]
[Remove]
```

Second account same.

Do not display tokens.

---

# 51. Onboarding

First launch onboarding:

## Screen 1

```text
AI Meter

Your AI usage and model intelligence,
in one native macOS dashboard.
```

## Screen 2 — OpenRouter

```text
Connect OpenRouter

API Key: [.................]

[Test Connection]
```

Allow skip.

## Screen 3 — Claude

Detect Claude Code.

If installed:

```text
Connect Claude Usage

AI Meter can read sanitized usage telemetry
from Claude Code's status-line output.

[Install Integration]
[Skip]
```

## Screen 4 — Codex

```text
Codex Accounts

[Connect Personal]
[Connect Second Account]
```

## Screen 5

```text
Ready
```

Do not force every provider to be configured.

---

# 52. Native Design Language

The app must look like a macOS utility, not a web dashboard inside a window.

Use:

- SwiftUI
- SF Symbols
- system typography
- semantic colors
- vibrancy/material only where appropriate
- native toolbar
- native sidebar
- standard keyboard shortcuts
- standard controls

Avoid:

- giant gradients
- excessive glass effects
- neon AI aesthetic
- huge mobile buttons
- browser dashboard appearance
- unnecessary shadows
- excessive corner radius

---

# 53. Animation

Animations should be subtle.

Examples:

```text
number transitions
progress bar changes
row insertion for NEW models
refresh icon
```

Do not animate continuously.

Respect:

```text
Reduce Motion
```

Use native animation APIs.

---

# 54. Accessibility

Support:

```text
VoiceOver
keyboard navigation
Increase Contrast
Reduce Motion
Dynamic Type where applicable
```

Usage progress must have accessible labels such as:

```text
Claude five-hour usage, 72 percent used, resets in one hour forty-two minutes.
```

Do not encode state purely in color.

---

# 55. WidgetKit

Implement at least:

```text
systemSmall
systemMedium
```

Optional:

```text
systemLarge
```

---

# 56. Small Widget

Suggested:

```text
┌─────────────────────┐
│ AI METER            │
│                     │
│ BEST FREE           │
│ DeepSeek V4         │
│ Intel 34.5          │
│                     │
│ Claude 72%          │
│ Codex  58%          │
│                     │
│ 9:03                 │
└─────────────────────┘
```

---

# 57. Medium Widget

Suggested:

```text
┌─────────────────────────────────────┐
│ AI METER                    Sep 19  │
│                                     │
│ FREE MODELS                         │
│ General   DeepSeek V4     34.5      │
│ Coding    Model X         69.1      │
│ Agentic   Qwen ...        46.5      │
│                                     │
│ Claude        72%   reset 1h 42m   │
│ Codex A       58%   reset Tue      │
│ Codex B       24%   reset Thu      │
└─────────────────────────────────────┘
```

Widget networking:

```text
NONE
```

Widget reads App Group snapshot only.

---

# 58. Freshness

Every provider card should have freshness metadata.

Example:

```text
Updated 4m ago
```

If provider data is stale:

```text
Updated 4h ago · Stale
```

If failed:

```text
Last successful update 4h ago
Refresh failed
```

Never replace useful cached data with empty error UI.

---

# 59. Error Handling

Provider failures must be isolated.

Example:

```text
OpenRouter ✓
Claude ✓
Codex Personal ✕
Codex Work ✓
```

One provider failure must not break the entire dashboard.

Use typed errors.

Example categories:

```swift
enum ProviderError: Error {
    case unauthorized
    case unavailable
    case malformedResponse
    case executableNotFound
    case processFailed
    case timeout
    case configurationMissing
}
```

Provide actionable UI messages.

---

# 60. Logging

Use Apple's unified logging.

Never log:

```text
API keys
OAuth tokens
authorization headers
full sensitive payloads
```

Use subsystem:

```text
com.<developer>.aimeter
```

Categories:

```text
network
openrouter
claude
codex
storage
widget
refresh
```

---

# 61. Network Layer

Use:

```text
URLSession
async/await
```

Avoid third-party networking libraries unless justified.

Support:

```text
reasonable timeout
HTTP status handling
JSON decoding
rate-limit handling
retry where safe
```

Retry strategy:

```text
retry transient server/network failures
maximum 1–2 retries
exponential backoff
```

Do not aggressively retry authorization failures.

---

# 62. Concurrency

Use Swift Concurrency.

Prefer:

```text
actors
async/await
TaskGroup where useful
```

The refresh coordinator should be an actor to prevent duplicate work.

Example:

```swift
await withTaskGroup(of: Void.self) { group in
    group.addTask { await refreshOpenRouter() }
    group.addTask { await refreshClaudeCache() }
    group.addTask { await refreshCodexPersonal() }
    group.addTask { await refreshCodexSecondary() }
}
```

Respect provider concurrency constraints.

---

# 63. Snapshot Consistency

When multiple refreshes finish:

1. Persist provider-specific state.
2. Recompute dashboard state.
3. Generate one coherent widget snapshot.
4. Atomically replace widget snapshot.
5. Ask WidgetKit to refresh.

Avoid widget state that mixes partially updated objects inconsistently.

---

# 64. Model Change Detection

After catalog refresh compare old/new state.

Generate normalized events:

```swift
enum ModelChange {
    case appeared
    case disappeared
    case rankChanged(from: Int, to: Int)
    case benchmarkChanged
    case availabilityChanged
}
```

Show recent meaningful changes:

```text
NEW  Model X entered OpenRouter Free
↑2   Qwen moved to #2 Agentic
↓    Model Y availability dropped to 71%
```

Avoid noisy insignificant updates.

---

# 65. Notifications

Do NOT overbuild notifications in initial milestone.

Architecture should allow future notifications for:

```text
usage >= 80%
usage >= 95%
new #1 free coding model
model availability recovered
```

If notifications are implemented:

opt-in only.

---

# 66. Menu Bar Automatic Text

V1 should probably use icon-only menu bar.

Do not permanently show:

```text
72%
```

unless user enables it.

Optional future menu bar mode:

```text
Claude 72%
```

or:

```text
58%
```

based on selected primary account.

---

# 67. Launch at Login

Use native:

```text
SMAppService.mainApp
```

Do not install custom LaunchAgents unless technically required.

---

# 68. CLI Detection

Detect executables robustly.

Claude:

```text
claude
```

Codex:

```text
codex
```

Do not assume GUI-launched applications inherit the user's interactive shell PATH.

Implement executable search across common locations:

```text
/usr/local/bin
/opt/homebrew/bin
~/.local/bin
user-configured path
```

Allow user to select executable path manually.

---

# 69. Shell Safety

Do not construct unescaped shell strings.

Prefer:

```swift
Process
executableURL
arguments
environment
```

Never:

```swift
/bin/sh -c "\(userInput)"
```

unless absolutely necessary.

---

# 70. Provider Feature Detection

Providers evolve.

On startup/integration:

- determine installed Claude/Codex version
- determine available capabilities
- gracefully disable unsupported functionality

Example:

```text
Codex usage details unavailable in this installed version.
Rate-limit information is still available.
```

Do not crash due to schema mismatch.

---

# 71. Versioning Provider Schemas

Keep provider DTOs isolated.

For unstable interfaces:

```text
CodexV1DTO
CodexV2DTO
```

if necessary.

Normalize both into the same Core model.

---

# 72. Privacy

Create a Privacy page explaining locally:

```text
OpenRouter API key:
stored in macOS Keychain.

Claude credentials:
never read by AI Meter.

Codex credentials:
never copied by AI Meter.

Usage history:
stored only on this Mac.

Widget:
receives sanitized local snapshot only.
```

No telemetry in V1 unless explicitly added later.

---

# 73. No Analytics by Default

Do not add:

```text
Google Analytics
Mixpanel
Amplitude
Sentry
PostHog
```

in V1.

If crash reporting becomes useful later, it should be opt-in or privacy-reviewed.

---

# 74. Testing Strategy

Implement unit tests for:

```text
OpenRouter decoding
Claude telemetry decoding
Codex RPC decoding
canonical model mapping
ranking engine
availability ranking
snapshot generation
freshness logic
change detection
Keychain wrapper abstraction
database migrations
```

---

# 75. Provider Fixture Tests

Create sanitized JSON fixtures.

Examples:

```text
Tests/Fixtures/OpenRouter/
Tests/Fixtures/Claude/
Tests/Fixtures/Codex/
```

Tests must run without real provider credentials.

Never commit real account payloads.

---

# 76. Integration Tests

Manual/integration test cases:

### OpenRouter

```text
valid API key
invalid API key
free account
paid account
network offline
rate limited
empty model result
```

### Claude

```text
Claude not installed
Claude installed
no status line configured
existing status line configured
fresh telemetry
stale telemetry
malformed bridge JSON
```

### Codex

```text
Codex not installed
one account
two accounts
expired login
process crash
RPC timeout
model list empty
rate limit available
usage unavailable
```

---

# 77. Energy Testing

Use Instruments.

Check:

```text
Energy Log
CPU
Wakeups
Network
File activity
```

Test:

1. App idle for at least 15 minutes.
2. Menu closed.
3. Widget present.
4. Background refresh configured.

Expected:

```text
near-zero CPU when idle
no recurring minute-level wakeups
no unnecessary subprocess
no repeated disk writes
```

If periodic wakeups appear, investigate them.

---

# 78. Performance Targets

Targets:

Cold launch to cached UI:

```text
< 500 ms perceived
```

Menu bar popover:

```text
effectively immediate
```

Scrolling:

```text
60/120Hz smooth as hardware permits
```

Idle CPU:

```text
approximately 0%
```

Widget:

```text
no network requests
```

Database:

```text
no expensive work on main actor
```

---

# 79. Security Acceptance Criteria

Before V1 is considered complete:

- OpenRouter key exists only in Keychain.
- No secret is present in widget snapshot.
- No Claude OAuth token is accessed.
- No Codex OAuth token is copied.
- No credentials are printed into logs.
- Shell injection is not possible through configured paths.
- Config modifications have backup/recovery.
- API responses containing secrets are not persisted unnecessarily.

---

# 80. UX Acceptance Criteria

The product should:

- launch instantly from cache
- work offline using last known data
- clearly show stale data
- support dark/light mode
- feel native
- support keyboard navigation
- allow individual providers to fail independently
- never block UI on network
- never require all providers to be configured

---

# 81. Recommended Implementation Order

Do not start by polishing UI.

Follow this exact sequence.

---

## Phase 1 — Repository and Core

Implement:

```text
Xcode project
Core models
provider protocols
logging
HTTP client
KeychainStore
persistence
basic tests
```

Deliverable:

Core project compiles with test coverage.

---

## Phase 2 — OpenRouter Spike

Implement only enough UI to inspect output.

Requirements:

- accept API key
- save to Keychain
- verify connection
- fetch account/key usage
- fetch model catalog
- identify free models
- attach benchmark metadata where available
- rank free models
- persist snapshots

Output debugging screen:

```text
OpenRouter connected
N models
N free models
Best general: ...
Best coding: ...
Best agentic: ...
```

Do not proceed until real-world API data is validated.

---

## Phase 3 — Claude Spike

Implement:

```text
Claude detection
status-line telemetry investigation
bridge executable
sanitized telemetry file
existing status-line preservation
freshness tracking
```

Verify with real Claude usage.

Do not proceed until:

```text
five-hour usage
seven-day usage
reset times
```

are correctly represented when available.

---

## Phase 4 — Codex Spike

First account only.

Implement:

```text
isolated CODEX_HOME
app-server process
RPC client
account/read
account/rateLimits/read
account/usage/read
model/list
```

Verify exact current Codex protocol against installed version and current official documentation.

Do not assume method schema based only on this specification.

Document discovered protocol differences.

---

## Phase 5 — Two Codex Accounts

Add:

```text
personal CODEX_HOME
secondary CODEX_HOME
```

Verify:

- independent login
- independent usage
- independent model catalog
- refresh sequentially or efficiently
- no auth file copying

---

## Phase 6 — Unified Repository

Normalize all provider outputs.

Implement:

```text
DashboardSnapshot
RefreshCoordinator
provider freshness
error isolation
change detection
```

At this point the business/data layer should work without final UI.

---

## Phase 7 — Native Menu Bar UI

Implement:

```text
MenuBarExtra
cached-first data
usage cards
best-free summary
refresh button
settings entry
dashboard entry
```

Polish enough to feel native.

---

## Phase 8 — Main Dashboard

Implement:

```text
sidebar
Overview
Models
Usage
History
Settings
```

Add sorting/filtering.

---

## Phase 9 — WidgetKit

Implement:

```text
App Group
atomic snapshot writer
small widget
medium widget
```

No networking in widget.

---

## Phase 10 — Historical Analytics

Implement:

```text
usage charts
model rank history
availability history
recent changes
```

Only after core provider integrations are stable.

---

## Phase 11 — Native Polish

Review:

```text
spacing
typography
toolbar behavior
keyboard shortcuts
animations
light/dark mode
accessibility
window sizing
materials
empty states
errors
```

---

## Phase 12 — Energy / Security Audit

Run:

```text
Instruments
network inspection
filesystem inspection
logs inspection
credential audit
```

Fix problems before declaring V1 complete.

---

# 82. Agent Working Rules

The implementation agent should follow these rules.

## Rule 1

Before implementing an external provider integration, verify the current official API/protocol documentation.

Interfaces may have changed since this specification was written.

## Rule 2

Prefer official documented interfaces over scraping.

## Rule 3

Do not introduce a cloud backend.

## Rule 4

Do not introduce Electron/Tauri.

## Rule 5

Do not introduce continuous polling.

## Rule 6

Do not read/copy Claude or Codex auth tokens unless the official integration explicitly requires it, which should be avoided.

## Rule 7

Do not make assumptions silently.

If a provider exposes less information than desired:

- represent the missing information as unavailable
- document the limitation
- continue implementing the rest

## Rule 8

Never fabricate quota information.

## Rule 9

Keep provider DTOs separate from Core models.

## Rule 10

Every provider must have fixture-based decoder tests.

## Rule 11

Do not optimize UI before provider integrations have been proven.

## Rule 12

Prefer system frameworks over new dependencies.

---

# 83. Important Technical Decision: No Scheduled LLM Research

Do NOT use a scheduled Codex task to research models every day as the primary architecture.

Instead:

```text
official APIs
+
official model metadata
+
benchmark feeds/catalog
+
local normalization
```

should drive the product.

LLM-based research could later exist as an optional enhancement for things such as:

```text
"Why did this model move up?"
"Summarize today's model changes."
```

but it should not be needed for basic data correctness.

---

# 84. Future V2 Ideas

Do not implement these unless V1 is complete.

Possible future features:

```text
model release notifications
quota threshold notifications
cost projections
usage forecasting
provider outage detection
recommended model based on task type
OpenRouter latency statistics
API provider routing
menu-bar quota text
iCloud sync
iPhone companion
global hotkey
Command Palette
JSON/CSV export
Prometheus endpoint
Raycast extension
```

---

# 85. Final V1 Definition

V1 is complete when the following works reliably:

```text
✓ Native macOS application
✓ Menu bar interface
✓ Main dashboard
✓ OpenRouter API-key connection
✓ OpenRouter account usage
✓ OpenRouter free-model discovery
✓ Intelligence benchmark display
✓ Coding benchmark display
✓ Agentic benchmark display
✓ Availability display
✓ Best-free lists per category

✓ Claude usage integration
✓ Claude five-hour usage
✓ Claude weekly usage
✓ Claude reset timestamps
✓ Claude telemetry freshness

✓ Codex account #1
✓ Codex account #1 rate limits
✓ Codex account #1 usage
✓ Codex account #1 model catalog

✓ Codex account #2
✓ Codex account #2 rate limits
✓ Codex account #2 usage
✓ Codex account #2 model catalog

✓ Historical local storage
✓ Model/rank change detection
✓ WidgetKit small widget
✓ WidgetKit medium widget
✓ App Group snapshot

✓ OpenRouter key stored in Keychain
✓ No Claude token copying
✓ No Codex token copying

✓ Cached-first UI
✓ Offline behavior
✓ Stale-data indicators
✓ Independent provider error states

✓ Launch at login option
✓ Light/dark mode
✓ Native keyboard behavior
✓ Accessibility basics

✓ Near-zero idle CPU
✓ No continuous polling
✓ No permanent unnecessary subprocesses
✓ No Electron
✓ No cloud backend
```

---

# 86. First Task for the Agent

Start with an **integration feasibility spike**, not the final UI.

Produce a working CLI/debug harness proving these four flows:

```text
1. OpenRouter
   API key
   → account usage
   → free model catalog
   → benchmark/ranking output

2. Claude
   Claude Code status telemetry
   → sanitized bridge output
   → five-hour / weekly limits

3. Codex Account A
   isolated CODEX_HOME
   → app-server
   → account
   → rate limits
   → usage
   → models

4. Codex Account B
   second isolated CODEX_HOME
   → same output independently
```

Output one normalized debug JSON:

```json
{
  "openrouter": {},
  "claude": {},
  "codexPersonal": {},
  "codexSecondary": {},
  "bestFreeModels": {}
}
```

Then document:

```text
- exact APIs/protocols used
- installed provider versions tested
- unsupported fields
- provider quirks
- security concerns
- freshness behavior
- sample sanitized responses
```

Only after this spike passes should development move into the final native UI.

---

# 87. Quality Bar

Do not treat this as a weekend dashboard.

Treat it as a polished macOS utility that a technical user would be comfortable running continuously.

The standard should be:

```text
native
predictable
private
low-power
fast
accurate
maintainable
```

When forced to choose between cleverness and reliability, choose reliability.

When forced to choose between real-time polling and battery efficiency, choose battery efficiency.

When forced to choose between displaying an estimated quota and admitting that the provider does not expose it, display the limitation.

When forced to choose between custom UI and a good native macOS control, use the native control.

The user should eventually be able to install AI Meter, configure OpenRouter + Claude + two Codex accounts once, place the widget on the desktop, and largely forget the application exists until they need the information.
