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

Swift Testing's macro plugin ships inside the toolchain, but with only the
Command Line Tools installed it is not on the default plugin search path, and
`swift test` would fail to build the test targets. `Package.swift` detects that
situation and points the compiler at the plugin that belongs to the active
toolchain, so no flag is needed.

Once Xcode is installed the manifest adds nothing: Xcode finds its own plugin,
and a plugin from one toolchain must not be fed to another.

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

Create a key at <https://openrouter.ai/keys>. A free account is enough: the free
`:free` model variants and the usage endpoints both work without credit.

Store it once. The key goes into the macOS Keychain (service
`com.sezer-muhammed.aimeter.credentials`, account `openrouter-api-key`) — the
same place the app's Settings will use, so nothing changes when that UI lands:

```bash
swift run aimeter-spike --set-openrouter-key
```

It reads the key from stdin rather than from an argument, so the key never
reaches your shell history or the process list, and it verifies the key against
the live API before reporting success. To remove it:

```bash
swift run aimeter-spike --forget-openrouter-key
```

After that, `swift run aimeter-spike` picks the key up on its own. The
`OPENROUTER_API_KEY` environment variable still overrides the Keychain for
one-off runs and CI.

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
