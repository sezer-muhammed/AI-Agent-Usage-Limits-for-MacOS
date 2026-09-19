# Provider protocols, as verified

Section 82 of the specification requires verifying each provider's current
interface rather than assuming this document's shapes. This records what was
verified, on what versions, and where reality differs from the spec.

Verified on 2026-09-19, macOS 27.0 (Apple Silicon).

## OpenRouter — REST

Base URL `https://openrouter.ai/api/v1`.

| Endpoint | Auth | Used for |
| --- | --- | --- |
| `GET /models` | none | catalog; 447 models, 22 `:free` variants at time of writing |
| `GET /key` | bearer | spend, limit, limit remaining, free-tier flag |
| `GET /credits` | bearer | lifetime credits purchased and used |

Confirmed details:

- Catalog prices arrive as decimal **strings in USD per token**; AI Meter
  converts to per-million for display.
- `architecture.input_modalities` is the modality list to use;
  `architecture.modality` is a single combined string such as `text+image->text`.
- `top_provider.context_length` can differ from the top-level `context_length`.

Security note: `/key` returns a **truncated copy of the API key** in its `label`
field (`sk-or-v1-2a1...260`). AI Meter decodes the field but never surfaces it —
the plan label is derived from `is_free_tier` alone — so no key fragment reaches
the database, the widget snapshot or a log line. A regression test pins this.

Benchmarks: each model may carry a `benchmarks` object, and its
`artificial_analysis` member holds exactly the three dimensions the spec asks
for — `intelligence_index`, `coding_index`, `agentic_index`. 251 of 447 models
carry them, 14 of them free variants. These are measured by a third party and
passed through by OpenRouter, so AI Meter needs no scoring of its own and no
language model in the loop. Models without indices keep their catalog entry with
no scores rather than a filler number.

Limitations:

- **No availability data** from this endpoint, so the "Best Reliable Free"
  category stays empty rather than guessing at reliability.
- `/key` reports **dollars, not free-request counts**. Any "N / 50 free requests
  used" display would be fabricated, so AI Meter does not show one.

## Claude — status-line bridge

Verified against Claude Code 2.1.267 and its documented status-line schema.

AI Meter reads exactly these fields from the stdin payload:

```
model.id, model.display_name
rate_limits.five_hour.used_percentage,  rate_limits.five_hour.resets_at
rate_limits.seven_day.used_percentage,  rate_limits.seven_day.resets_at
rate_limits.spend_limit.used_percentage, rate_limits.spend_limit.resets_at
```

`resets_at` values are **Unix epoch seconds**. Nothing else in the payload is
decoded, so `cwd`, `transcript_path`, `session_id`, `cost` and the prompt-cache
statistics cannot leak into the sanitized file. No Claude credential is ever
read.

Quirks:

- `rate_limits` is absent for non-subscription accounts and until the first API
  response of a session; each window can be absent independently, and Claude
  Code drops a window once its `resets_at` passes.
- Updates are **event-driven**. The bridge writes only when Claude Code runs the
  status line, so the telemetry's `capturedAt` is meaningful and the UI shows
  freshness rather than implying live data. Thresholds: fresh < 30 min,
  slightly stale 30–120 min, stale > 120 min.

## Codex — app-server JSON-RPC

Verified against `codex-cli 0.154.0` using
`codex app-server generate-json-schema`, then probed against a running server.

Transport: `codex app-server` over stdio, newline-delimited JSON-RPC.

| Method | Auth required | Notes |
| --- | --- | --- |
| `initialize` | no | `params.clientInfo` = `{name, version}` |
| `initialized` (notification) | no | sent after the initialize response |
| `account/read` | no | returns `account: null, requiresOpenaiAuth: true` when signed out |
| `account/rateLimits/read` | yes | errors "codex account authentication required to read rate limits" |
| `account/usage/read` | yes | token usage summary and daily buckets |
| `model/list` | no | works signed out |

Differences from the specification's assumptions:

- **`params` is mandatory on every request.** Omitting it fails with
  `-32600 Invalid request: missing field 'params'`, including for methods that
  take no arguments. AI Meter always sends at least `{}`.
- **The envelope has no `jsonrpc` field.** Requests are `{id, method, params}`.
- Rate limits come in two views: `rateLimits` (single-bucket, backward
  compatible) and `rateLimitsByLimitId` (keyed by metered limit id, e.g.
  `codex`). AI Meter prefers the multi-bucket view.
- Each snapshot has `primary` and `secondary` windows described by
  `windowDurationMins` rather than by name, so window kind is derived from the
  duration (300 → 5-hour, 10080 → weekly).
- The server interleaves notifications such as `remoteControl/status/changed`
  with responses, so the client matches responses by request id.
- `credits.balance` is a **decimal string** or absent.

`requiresOpenaiAuth` is **not** a signed-out signal — a signed-in ChatGPT
account still reports it `true`, because it describes the authentication mode
rather than the session. Signed-out is `account/read` returning `account: null`,
or a read coming back unauthorized.

Behaviour on a signed-out profile: `model/list` still succeeds, so the refresh
records the models and reports the account as needing authentication instead of
failing entirely.

## Security notes from the spike

- The only stored secret is the OpenRouter API key, in the Keychain.
- Claude and Codex authentication stays inside their own systems; no token file
  is read or copied.
- The Codex server is launched with an explicit argument list and environment,
  never a shell string, so a user-configured executable path cannot become shell
  injection.
- The widget snapshot carries usage numbers and model names only.
- Spike output may contain real account data and is git-ignored.

## Status against the spec's phases

Complete: Phase 1 (core), the data half of Phases 2–6, and the Phase 86 spike.

Not started, and requiring a full Xcode installation: the Xcode app target,
MenuBarExtra UI, dashboard, WidgetKit extension and App Group entitlement
(Phases 7–12). Only the Command Line Tools are installed on this machine, so
those targets cannot be created or built here yet.

Also outstanding: an availability source, without which the reliability category
cannot be computed.
