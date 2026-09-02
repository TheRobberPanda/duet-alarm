# 05 — Monetization

> Rewritten. The original subscription plan is superseded by ADR-012 in doc 09.
> The reasoning that led here is preserved in that ADR.

## The model: free tier, then a one-time unlock

**People do not want a subscription for an alarm clock.** Alarmy sustains one on
brand and scale; an unknown solo developer does not have that credit. Subscription
resistance shows up as one-star reviews, and for an app whose growth is entirely
organic, the review section *is* the marketing budget.

So: a genuinely useful free tier, one one-time purchase that unlocks the product
for **both** members of the pair, and small cosmetic packs after that.

**The line that sells it:**

> One purchase. Covers both of you. Forever.

That sentence only works because of the pair structure — every user brings a second
person, so "covers both of you" is not a discount, it is the product.

## Tiers

### Free

- Pairing with one partner
- **2 shared alarms**
- Both phones ring; snooze/dismiss for self and for both
- 4 built-in sounds
- 3 themes (Ember, Mono, Harbour)
- Basic streak counter

The free tier has to be good enough that people keep the app installed. An alarm
app that nags at 6am gets deleted at 6:01.

### Duet Full — **$9.99 one-time, pair-wide**

| Feature | Why it converts |
|---|---|
| **Unlimited alarms** | The most common upgrade trigger |
| **Voice recordings as alarm sounds** | The emotional hook. Record your voice; they wake to it. Capped at 5 clips per person — the only genuinely metered cost in the app. |
| **Full sound library + device tones** | Table stakes |
| **Wake-up missions** (math, shake, photo) | Converts the "my partner won't get up" crowd |
| **Wake history & detailed stats** | Retention feature, cheap to build |
| **Custom snooze policies** | Power users |

### Theme packs — **$3.99 one-time**

Six themes: Blush, Orchid, Sage, Terracotta, Neon, Daylight. A theme sets **both**
accent colours, and each partner picks their own independently.

This is the repeatable revenue line: zero server cost, pure impulse purchase, no
subscription resentment, and it can be extended indefinitely with new packs.
Personalization converts broadly — market it as personalization, never as a
gendered feature.

Sound packs ($2.99) are the same pattern and are the obvious second SKU. Keep the
total SKU count low.

## Why one-time survives the server costs

The standard argument for subscriptions is recurring infrastructure cost. Ours is
negligible: Supabase's free tier, then $25/month, covers thousands of pairs. The
only metered resource is voice-clip storage, and the 5-clip cap bounds it.

If the app ever grows past the point where that stops being true, that is a very
good problem, and a paid major version (Duet 2.0) is the honest way to solve it.

## Where the paywall appears

1. After the **second** successful shared wake-up — not on first launch. Let the
   product prove itself. This single choice matters more than any pricing tweak.
2. When adding a 3rd alarm
3. When tapping "Record your voice"
4. In the Theme screen, for the pack
5. A permanent, non-nagging row in Settings

## Implementation: RevenueCat

Still the right call, even without subscriptions — it handles Play Billing,
receipt validation, entitlement state, and the webhook, and it is free at your
scale.

- **Non-consumable** products: `duet_full`, `theme_pack_1`
- **Restore Purchases is mandatory**, not optional — with a one-time purchase,
  a user who switches phones and loses their unlock will leave a one-star review.
  Test this path deliberately.
- **Pair-wide entitlement:** RevenueCat grants to the purchasing account; the
  webhook writes `pair.plan = 'full'` so both members read paid status from your
  own database. Handle pair dissolution — the entitlement follows the payer.
- **Play auto-refunds any purchase within 48 hours.** Don't count revenue until
  that window closes.

## Store rules you cannot negotiate

- **Digital goods must use Play Billing.** No Stripe, no external payment links.
- Google takes 15% on the first $1M/year (enroll immediately); Apple's Small
  Business Program is the equivalent for when iOS arrives.
- Price, product name, and what you get must be shown **on the paywall itself**,
  with Terms and Privacy links.
- Do not gate the core alarm in a way that reads as bait-and-switch. The free tier
  above is safe.
- **Regional pricing:** use the store's automatic price tiers, or you price
  yourself out of India, Brazil, and SE Asia.

## No advertising. Ever.

An alarm clock shows its screen at 6am to someone who did not choose to look at
it. Ads there are hostile, they poison the shared-ritual brand, and the eCPM on 30
seconds of groggy attention is negligible.

## Realistic expectations — and the honest downside

Assume roughly a third of installs complete pairing, and ~6% of pairs buy.

| Installs | ~Pairs | Buyers | Unlock revenue (net 15%) | + theme packs | Total |
|---|---|---|---|---|---|
| 10,000 | 1,500 | 90 | ~$765 | ~$90 | **~$855** |
| 100,000 | 15,000 | 900 | ~$7,640 | ~$915 | **~$8,555** |
| 500,000 | 75,000 | 4,500 | ~$38,200 | ~$4,600 | **~$42,800** |

**The structural downside, stated plainly:** one-time revenue is earned per cohort.
It scales with *new installs*, not with accumulated users. A subscription business
banks last year's customers again this year; this one does not. If the app stops
growing, revenue goes to roughly zero.

That is a real cost, and it is the right trade anyway at this stage: you are
optimizing for adoption, reviews, and word-of-mouth, because with no marketing
budget those are the only growth you have. Revisit the model once you know whether
people actually keep using it — the entitlement design above leaves that door open.
