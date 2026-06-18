# RailsSync — OpenAPI Contract Extractor for Rails

**Date:** 2026-06-18
**Status:** Approved design, pre-implementation
**Author:** dani@dutyventures.com

## Summary

RailsSync is a Ruby gem that produces and maintains a single committed
`openapi.yml` describing a Rails JSON API. It combines **static** route/param
introspection with **runtime** response observation. The generated contract is
idempotent (re-runnable without churn) and never clobbers human-written prose.

This is the first of a previously larger idea ("RailsBump"). Two adjacent
products were explicitly cut from scope:

- **Breaking-change / drift detection + CI guard** — the natural *next* product.
  The committed `openapi.yml` this gem produces is its seed, but the diff
  tooling is out of scope here.
- **OTA bundle delivery for React Native** — a 6+ month infrastructure product
  already solved by Expo EAS Update / `expo-updates`. Cut entirely. Not rebuilt.

## Goal & Non-Goals

**Goal:** A polished open-source gem with zero hosted infrastructure. Install via
`bundle add` / `gem install`, drive via a CLI / rake tasks, output to a file.
No accounts, no server. Self-serve, documentation- and utility-driven; the kind
of tool that can be launched on Hacker News / r/rails on its merits.

**Non-Goals (v1):**

- GraphQL, Grape, Sinatra (vanilla ActionController only)
- Multipart / file upload, streaming, Server-Sent Events, ActionCable / websockets
- Non-JSON content types (XML, etc.)
- Auth-flow modeling (OAuth flows, etc.)
- TypeScript client generation (downstream concern — `openapi-typescript` plus a
  future React Native library, not this gem)
- Breaking-change / contract-diff / CI checking (the next product)
- A hosted dashboard or any networked service

## Core Design Decisions

These were settled during brainstorming and are the load-bearing choices:

1. **Hybrid extraction.** Static introspection lays down the route + request-param
   skeleton with zero test dependency (the "it just worked" first run). Runtime
   observation fills in response shapes and corrects/enriches request params where
   static analysis can't see. Each method plays to its strength.

2. **Output is OpenAPI 3.1.** A strict superset of JSON Schema, so nothing is lost
   versus a custom dialect, and the entire existing ecosystem comes for free:
   `openapi-typescript`, Swagger UI, Postman import, mock servers.

3. **Runtime capture is Rack-middleware-first.** A single env-gated middleware is
   the capture engine; it works under any driver — the test suite, manual clicking
   in dev, or staging — and is not welded to a test framework. An optional thin
   RSpec metadata shim (descriptions → summaries, tags) can be layered later.
   This avoids the `rspec-openapi` trap of being coupled to one test runner.

4. **Runtime is serializer-agnostic.** Because the middleware reads the actual JSON
   response bytes, RailsSync never needs to understand AMS vs Jbuilder vs
   Blueprinter vs Alba vs `render json:`. This deliberately sidesteps the messiest
   part of the problem space.

5. **One committed `openapi.yml`, additive idempotent merge.** A single file is the
   source of truth, checked into the repo (so it shows up in PR review and seeds
   future diffing). Static writes the skeleton; runtime observations merge in
   (fill response schemas, add examples, tighten param types from observed values);
   re-running is idempotent. **Hand-edited prose (descriptions, summaries, tags) is
   preserved across regenerations** — this is the make-or-break UX detail. Stale
   paths (in the file but no longer in the static route set) are flagged, and only
   removed with an explicit `--prune` flag.

## Architecture & Components

Each unit has one responsibility and a clean interface so it can be understood
and tested independently.

| Component | Responsibility | Depends on |
|---|---|---|
| `Static::RouteExtractor` | Read `Rails.application.routes` → path templates, HTTP verbs, `controller#action`, path params | Rails routes |
| `Static::ParamsExtractor` | Parse controllers via **Prism** for `params.require(...).permit(...)` → request param names / nesting (best-effort) | Prism AST |
| `Runtime::Middleware` | Env-gated Rack middleware; record `{verb, route template, request params, request/response content-type, status, response body}` to `tmp/rails_sync/observations.jsonl` | Rack |
| `SchemaInferrer` | Pure function: observed JSON value(s) → JSON Schema. Infer types, nesting, array item schemas, nullable/optional (field sometimes absent or null); merge repeated observations by widening | none (pure) |
| `Merger` | Reconcile static skeleton + inferred schemas + the existing committed `openapi.yml`; preserve hand-edited prose; idempotent; flag stale paths | `OpenAPIDocument` |
| `OpenAPIDocument` | In-memory OpenAPI 3.1 model; serialize to YAML / JSON | none |
| CLI / Rake tasks | `rails_sync:generate` (static skeleton), `rails_sync:build` (fold observations + merge), with readable terminal output | all of the above |

### Data Flow

```
routes ───────► RouteExtractor ─┐
controllers ──► ParamsExtractor ─┤
                                 ├──► Merger ──► openapi.yml (committed)
app traffic ──► Middleware ──► observations.jsonl ──► SchemaInferrer ─┘
(tests/dev)                                                  ▲
                          existing openapi.yml (prose preserved) ┘
```

Typical loop:

1. `rails_sync:generate` writes the static skeleton.
2. Run specs (or click around in dev) with `RAILS_SYNC=1`; the middleware records
   observations to `tmp/rails_sync/observations.jsonl`.
3. `rails_sync:build` infers schemas from the observations and merges everything —
   static skeleton, inferred schemas, and existing prose — into `openapi.yml`.

## Known Limitation (by design)

`Static::ParamsExtractor` is **best-effort**. Conditional `permit`, params assembled
in helper methods, or metaprogrammed params will not be fully captured by AST
parsing. This is acceptable and intentional: the runtime layer corrects and
enriches the contract, and anything static misses simply appears the first time a
real request exercises that endpoint. Shipping an honest "skeleton + runtime
truth" beats pretending static analysis is complete.

## Testing Strategy

- Standard gem layout with a `spec/dummy` Rails app exercising the tricky cases:
  nested params, array bodies, nullable / optional fields, namespaced routes.
- TDD throughout. `SchemaInferrer` and `Merger` are pure-ish and get heavy unit
  coverage across edge cases (type widening, nullability, prose preservation,
  idempotency, stale-path flagging).
- One integration test boots the dummy app, drives traffic through the middleware,
  runs `build`, and asserts the resulting `openapi.yml`.

## Dependencies

Deliberately minimal, to keep it a clean OSS install:

- **Prism** — Ruby's parser, bundled with Ruby 3.3+ (zero extra dependency) for
  static strong-params AST parsing.
- **Rack** — already present in any Rails app, for the middleware.
- **stdlib** YAML / JSON for serialization.

No runtime service, no accounts, no network calls.

## Open Items for the Implementation Plan

- Exact CLI/rake surface and flag set (`--prune`, output path override, env gate
  name).
- Observation store format details and how route-template recovery is done from a
  concrete request path (`recognize_path` vs matched-route lookup).
- Schema-merge/widening rules precise enough to TDD (e.g. int seen then float →
  number; field absent in one observation → optional).
- Prose-preservation merge algorithm specifics (which keys are "human" and
  protected: `description`, `summary`, `tags`, `examples` added by hand).
