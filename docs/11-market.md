# 11 — Market

> ⚠️ **Read this caveat first.** The competitor names and structural analysis below
> are from general knowledge, not from live store data. Specific download counts,
> revenue figures, and rankings are **not** stated here because I cannot verify them,
> and unverified numbers in a business plan are worse than no numbers. Doc section
> "Validate it yourself, for free" tells you how to get real figures at zero cost.
> Do that before making decisions based on this.

## The two categories you sit between

**1. Alarm / sleep utilities.** A large, mature, and genuinely lucrative category.
People pay for alarm apps — reliably, and more than you'd expect for something the
OS gives away. The flagship is **Alarmy**, which built a substantial business on
one idea: making it hard to turn the alarm off. Others: **Sleep as Android**,
**Sleep Cycle**, **Alarm Clock Xtreme**. Evidence that the category monetizes: it
supports multiple companies with paid tiers.

**2. Couples apps.** Also real and also monetizing — **Paired** (subscription,
venture-funded), **Between**, **Lovewick**, **Agapé**. These prove the thing that
matters most to you: **two people will pay for software whose entire purpose is
that they are two people.** The couples-app market has a well-established
willingness to subscribe.

Your app is the intersection. That intersection is not crowded.

## The competitor you must take seriously

**Galarm.** It already does shared and group alarms — you set an alarm, other people
get it, participants can respond. It is the closest existing thing to your idea and
it has meaningful adoption.

Do not let this discourage you, but do not pretend it isn't there. Install it. Use
it with a friend for a week. Read its one- and two-star reviews specifically —
that list is your product roadmap.

My read on where Galarm leaves room, to be confirmed by actually using it:

- It is positioned as a **group/reminder/coordination** tool — teams, families,
  event reminders. Broad and utilitarian.
- It is not built around **the emotional story of two people who share a bed or a
  timezone**. That framing, the visual design that goes with it, and the couples
  ASO keywords are unoccupied.
- **Per-listener sounds** — choosing what your partner wakes up to, and recording
  your own voice for it — is a distinctly couples-shaped feature that a
  group-coordination app has no reason to build.
- **Live awareness during the ring** ("Sam snoozed, 4:51 left") is a delight
  feature that reads as intimate for two people and as noise for eight.

**The strategic point:** you are unlikely to win by building a better general
shared-alarm utility. You win, if you win, by building the *couples* one — narrower
audience, much sharper positioning, and a category (couples apps) that already
subscribes.

## Why the growth mechanics are unusually good

This is the strongest thing about the idea, and it's structural rather than
speculative:

**Every single user must recruit a second person for the app to work at all.**

That is a built-in viral coefficient that most apps spend enormous money trying to
manufacture. It also means:
- Retention is socially enforced — leaving means breaking something shared
- Conversion is easier — "I'll pay for it" is a normal thing to say to a partner
- Your acquisition cost is halved by definition

The flip side: **your onboarding is your entire growth engine.** If the invite flow
has any friction, the app is dead. Budget disproportionate effort there — it
matters more than the alarm screen's design.

## Honest risks

| Risk | Severity | Notes |
|---|---|---|
| **It's a feature, not a product** | High | The most likely failure mode. People may not want a *separate* alarm app for this. Mitigated only by making the shared experience genuinely delightful, not merely functional. |
| Reliability is existential | High | A social alarm that fails once loses the couple, not the user. Doc 04's test plan is the whole defense. |
| Galarm / an incumbent adds couples framing | Medium | You're faster and more focused. Ship before they notice. |
| OS vendors ship it natively | Low-Medium | Apple/Google could add shared alarms. They've had years and haven't. |
| Small addressable market | Medium | "Couples who need synchronized wake-ups" is narrower than "people who use alarms." Narrow is fine if conversion is high — but it caps the ceiling. |
| Solo dev, no budget, no iOS | Medium | Real, but doc 10 is a workable path. |

## Realistic outcome framing

Don't plan for this to be a company. Plan for it to be:

- **Base case:** a few thousand users, a few hundred euros a month, a genuinely
  good portfolio piece and a real education in shipping. This is the *likely* outcome
  and it is a good one.
- **Good case:** it finds the couples niche, organic sharing does its work, and it
  becomes meaningful side income.
- **Great case:** a small, sustainable business. Possible. Not the plan.

The single best reason to build it: the growth mechanics are genuinely favorable,
the technical moat (a *reliable* alarm across hostile Android OEMs) is real and
most competitors do it badly, and your entry cost is $25.

## Validate it yourself, for free — do this before Milestone 0

A weekend of this is worth more than any analysis I can give you:

**Get real numbers (free):**
- Search "shared alarm", "couple alarm", "group alarm", "partner alarm" on the
  Play Store. Note install counts (Play shows them publicly) and rating counts.
- **Google Play Console has a free keyword/market insights section** once you have
  an account — but even without it, `AppBrain` and the free tiers of
  Sensor Tower / data.ai / AppFigures give ballpark download and revenue estimates.
- Google Trends for those search terms.

**Read the demand in people's own words (free):**
- One- and two-star reviews of **Galarm** and **Alarmy** — the gap list
- `r/LongDistance`, `r/AndroidApps`, `r/SomebodyMakeThis` — search for people
  asking for exactly this. If nobody has ever asked, that is a signal.

**Test the pitch before you build (free, one evening):**
- A single landing page on **GitHub Pages** with the one-line pitch from doc 01,
  three mockup images, and an email field (Tally or Google Forms, free).
- Post it to `r/AndroidApps`, `r/SideProject`, and a TikTok/Reels clip of the
  concept. The couples angle is inherently shareable video content.
- **If 100 people sign up, build it. If 3 do, change the pitch, not the code.**

That last test costs one evening and zero euros, and it is the highest-value thing
you can do this week — higher than any line of code in doc 08's Milestone 0.
