# Duet — Multiplayer Alarm Clock

> **Duet** is a placeholder codename. See `docs/07-store-launch.md` for naming/trademark work before launch.

An alarm clock for two people. You and your partner share alarms. When one goes off,
**both phones ring**. Either person can snooze or dismiss it — for themselves, or for
both of you. You pick the sound the other person wakes up to.

## Documentation

| Doc | What's in it |
|---|---|
| [01 — Product Spec](docs/01-product-spec.md) | What the app does, screen by screen. Read this first. |
| [02 — Architecture](docs/02-architecture.md) | How the pieces fit. The local-first alarm rule. |
| [03 — Data Model](docs/03-data-model.md) | Postgres schema, RLS, sync protocol. |
| [04 — Alarm Engine](docs/04-alarm-engine.md) | The hard part. Android + iOS native specifics. |
| [05 — Monetization](docs/05-monetization.md) | Free vs. paid, pricing, IAP mechanics. |
| [06 — Shipping iOS Without a Mac](docs/06-ios-without-a-mac.md) | Your situation specifically. |
| [07 — Store Launch](docs/07-store-launch.md) | Accounts, review, checklists, timelines, costs. |
| [08 — Roadmap](docs/08-roadmap.md) | Build order, milestones, what to cut. |
| [09 — Decision Log](docs/09-decisions.md) | Every choice made and why. Amend, don't delete. |
| [10 — Zero-Budget Path](docs/10-zero-budget-path.md) | **Current plan.** Build it all for €0, Android-only. |
| [11 — Market](docs/11-market.md) | Competitors, growth mechanics, risks, free validation plan. |
| [12 — Roadblocks](docs/12-roadblocks.md) | What will block you, when, and what to prepare now. |
| [13 — Milestone 0](docs/13-milestone-0.md) | **Start here to build.** Setup, layout, and the test plan. |
| [design/DESIGN-PROMPT.md](design/DESIGN-PROMPT.md) | Brief for generating the app mockups. |

## Status

**Milestone 0** — alarm proven on hardware: rings 1.45 s late across a reboot,
before first unlock. Tests 1, 2, 3, 9, 10 pass; 4–8 and 11–14 outstanding.

**Milestone 2 in progress** — Supabase backend live (schema, RLS, verified
against an attacker), Flutter wired to it: email sign-in, invite/redeem pairing,
account deletion.

Budget: €0 (doc 10). Android-only; iOS deferred until there is revenue.

```bash
source tool/env.sh && cd app && flutter run
```

## The one thing to remember

**Alarms are scheduled locally on every device that will ring.** The network syncs
alarm *definitions*, never alarm *triggers*. If the server is down, the phone in
airplane mode, or the push dropped — the alarm still rings. This constraint drives
the entire architecture.
