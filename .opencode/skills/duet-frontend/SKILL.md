---
name: duet-frontend
description: Use when touching any Duet UI — Flutter screens in app/lib/, theme.dart, app/pubspec.yaml fonts, design/ canvases, or the native Kotlin ringing screen RingingActivity.kt. Encodes the Plum Velvet design language, the skin-sync rule chain, and the device verification loop. Trigger on words like redesign, pretty, theme, screen, design, font, ring, ringing screen.
---

# Duet frontend — the Plum Velvet design language

Duet is a shared alarm clock for couples. Two people, each with an accent colour.
Every shared element shows both. A user must tell "me" from "them" at a glance.
That is the signature — never decoration.

## Binding rules (from docs/14-handoff.md — violating these breaks shipped bug fixes)

1. **The ringing screen (`RingingActivity.kt`) has no Flutter engine.** It cannot
   call Dart, read Dart state, or use any Dart package. Anything it needs must be
   pushed to native storage in advance via `AuthStore.kt` (skin colours already
   flow this way: `settings_screen._setAccent` → `AlarmEngine.setSkinColors` →
   `AuthStore` → `RingingActivity` reads with fallbacks).
2. **An alarm never depends on the network** (ADR-001). UI changes must not make
   ringing conditional on connectivity.
3. **Comments explain why, not what.** Several encode a bug that already
   happened. Never strip them.
4. **docs/09-decisions.md is an append-only ADR log.** Append when making a
   reversible decision (palette changes, new deps, fonts).
5. **`reconcile()` re-arms unconditionally** — never "optimise" it away.
6. **Never commit personal files** (`ID docs/`, images).

## Palette — plum, pink + lavender (keep these names; ~41 call sites)

Defined in `app/lib/theme.dart` `DuetColors`. Canonical values:

| token | hex | role |
|---|---|---|
| bgDeep / bg | #150F14 / #1A1218 | page gradient (top→bottom) |
| surface / surfaceRaised | #251A22 / #33232D | cards; raised elements |
| line | #402C38 | hairlines, dim tracks |
| text / muted / dim / faint | #F9EBF3 / #CBA8BE / #937284 / #5F4555 | text hierarchy |
| amber (misnamed) | #F0A8C8 | partner-pink accent fallback |
| teal (misnamed) | #C9AEE8 | your lavender accent fallback |
| danger | #E87DA0 | destructive/semantic warnings ONLY — never use skin accent for warnings |

**No hard-coded Color() literals in screens.** Everything routes through
`DuetColors`, `SkinColors`, or a new theme token. Historical drift bug: two
screens shipped different hard-coded switch-inactive colours.

### Skins (do not break)
`duetSkins` in theme.dart; `SkinColors` is a global ChangeNotifier; anything
painting in the live accent listens via `SkinBuilder`. `SkinColors.wash` is the
pair gradient used on filled surfaces. Adding a skin = adding to `duetSkins`
only; it must keep a distinct `id` stored in `profiles.accent`.

## Typography

| face | use |
|---|---|
| Hanken Grotesk (300–700) | all UI text, humanist, `fontFamily: 'Duet UI'` |
| Duet Display = Montserrat ExtraBold | ONLY large time displays (counters rhyme with the ring) |
| Instrument Serif (regular + italic) | celebratory headlines (wake receipt), one per screen max |

Time is the hero element: large, light-to-extrabold by context, **tabular
figures** (`FontFeature.tabularFigures`), generous tracking. Serene, not
digital-alarm aggressive.

## Component inventory (use these; do not hand-roll alternatives)

All in `theme.dart` (+ `widgets.dart` if split): `PairRing` (two-tone ring w/
dashed partner-off arc, breathing), `DuetCard` (gradient fill + hairline border
+ top edge highlight), `DuetButton` (gradient pill, press-scale), `HaloGlow`
(radial glow behind hero elements), `DuetPill` (status pills), `DuetDialog` /
`DuetSnackBar` (never stock AlertDialog/SnackBar), `Skeleton` (never bare
spinners), `WaveformBars`, `PressAndHoldButton` (destructive "for both of us"
actions), `AvatarBadge`, `FadeSlideIn` (entrance, stagger lists 40–70ms),
`DuetPageRoute` (fade+lift; never MaterialPageRoute), `SectionLabel`.

Motion rules: slow and breathing by default (3s+ loops), springy presses
(90–120ms), entrance fades with lift. Nothing bounces or spins aggressively —
this is looked at half-asleep at 06:00.

## Verification loop (every UI change)

```bash
source tool/env.sh        # pins JDK; system Java has no compiler
cd app
flutter analyze lib/
flutter test
./tool/install.sh debug --dart-define=DUET_BACKEND=true   # flag is REQUIRED for backend features
```

Device gotchas: `adb install` fails on this HyperOS phone (install.sh pushes to
`/data/local/tmp` + `pm install -r -t`); never mix release/debug builds on the
device; screenshots render at 900w for a 1080w screen → multiply tap coords by
1.2; `uiautomator dump` goes stale when layout shifts — dump and tap in one
shell invocation. Test the native ringing screen via the diagnostics screen's
Test ring button, not by waiting for 06:00.

## Design canvases

`design/*.dc.html` + `canvas.json` specify artboards (warm-brown palette was
superseded by Plum Velvet, but layout/technique ideas remain canonical):
gradient cards, radial halos, dashed arcs, partner awareness strip, press-and-
hold hierarchy on ringing ("stops your phone only" caption), waveforms,
two-tone streak dots.
