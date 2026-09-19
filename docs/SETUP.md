# Setup

## Requirements

- macOS 14 or later (developed and tested on macOS 27, Apple Silicon)
- Swift 6.0+ toolchain
- Xcode for the app, widget and test targets — see *Toolchain note* below
- Optional, per provider: an OpenRouter API key, Claude Code, the Codex CLI

## Build

```bash
swift build
```

## Test

```bash
swift test
```

### Toolchain note

With only the Command Line Tools installed, the swift-testing macro plugin is
not on the default plugin search path and `swift test` fails to build. Point it
at the plugin that ships with the tools:

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

A full Xcode installation does not need the flag.

## Run the feasibility spike

The spike exercises all four provider flows and prints one normalized JSON
document. Its output can contain real account data, so it goes to stdout and
`.gitignore` keeps spike output files out of the repository.

```bash
OPENROUTER_API_KEY=sk-or-... swift run aimeter-spike
```

Without a key it still reads the public model catalog. Optional flags:

```bash
swift run aimeter-spike \
  --codex-home-a ~/.codex-aimeter-personal \
  --codex-home-b ~/.codex-aimeter-secondary \
  --claude-telemetry ~/Library/Application\ Support/AIMeter/claude-telemetry.json
```

## Provider setup

### OpenRouter

Supply the API key through the app's Settings once the UI exists; it is stored
only in the macOS Keychain (service `com.sezer-muhammed.aimeter.credentials`,
account `openrouter-api-key`). The `OPENROUTER_API_KEY` environment variable is
a convenience for the spike harness only.

### Claude

Claude subscription usage comes from Claude Code's status-line telemetry, not
from an Anthropic API key — they are different systems. Build the bridge and
point Claude Code's status line at it:

```bash
swift build -c release
```

Then in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "'/path/to/aimeter-claude-bridge' --out '/Users/you/Library/Application Support/AIMeter/claude-telemetry.json'"
  }
}
```

`ClaudeIntegrationInstaller` automates this, including backing up the file and
chaining to an existing status line with `--forward '<previous command>'`.

`rate_limits` appears only for Claude Pro/Max subscribers and only after the
first API response in a session, so the file may exist with no windows in it
for a while. That is reported as "partial", not as an error.

### Codex

Each account gets its own isolated profile directory, signed in separately:

```bash
CODEX_HOME=~/.codex-aimeter-personal codex login
CODEX_HOME=~/.codex-aimeter-secondary codex login
```

Never copy `auth.json` between profiles — refresh-token rotation makes a copied
credential unreliable.
