# Supabase backend

**Project:** `duet-alarm` · ref `htxxjvmikxgagtuuoxkm` · region `eu-central-1`
(Frankfurt — EU data residency, see docs/07 on GDPR).

## The security model

There is no trusted application server. Phones talk to Postgres directly with a
user token, so **Row Level Security is the entire authorization model**. Every
table has RLS enabled and an explicit policy. If a policy is wrong, the app is
wrong.

Two rules do work that RLS alone cannot:

- **`act_on_partner()`** is the only route to changing another person's ring
  state. RLS on `ring_participants` permits updating *only your own row*, so
  "dismiss for both" has to go through this function — which checks the target's
  `allow_partner_dismiss` preference. That is what makes ADR-006 enforceable
  rather than advisory.
- **`redeem_pair_invite()`** is the only route into a pair. `pair_members` has
  no INSERT policy at all, so an uninvited join is impossible even for someone
  who knows the pair id.

## Before sign-in will work — two things to check in the dashboard

1. **The email template must include the code.** `signInWithOtp` +
   `verifyOTP` needs a six-digit token, but Supabase's default Magic Link
   template may only contain `{{ .ConfirmationURL }}`. Under
   *Authentication → Email Templates → Magic Link*, make sure the body
   includes `{{ .Token }}`. Without it the email arrives with a link and no
   code, and the app's code field can never be satisfied.

2. **The built-in SMTP is rate-limited to a handful of emails per hour** and is
   explicitly for testing only. That is survivable while it is just you and one
   test account; it is not survivable with twelve closed-test testers
   (docs/12 §1.3). Configure custom SMTP — Resend's free tier is the usual
   choice — *before* the beta, not during it.

## Migrations

Files here mirror what is applied to the project, in order. They are the
version-controlled copy; the deployed database is the live one. Once the Supabase
CLI is available, `supabase db pull` is the way to confirm they have not drifted.

| # | Migration | What it does |
|---|---|---|
| 1 | `0001_core_schema.sql` | Tables, indexes, constraints |
| 2 | `0002_functions_and_triggers.sql` | updated_at, profile creation, pairing, act_on_partner, account deletion |
| 3 | `0003_row_level_security.sql` | RLS enabled + every policy |
| 4 | `0004_lock_down_function_grants.sql` | Revoke EXECUTE from anon/public |
| 5 | `0005_fix_invite_code_ambiguity.sql` | Bug fix: local variable shadowed a column |
| 6 | `0006_grant_policy_helper_execute.sql` | Correction to #4 — policies DO need EXECUTE |
| 7 | `0007_reap_empty_pairs.sql` | Delete pairs once the last member leaves |

## Verifying the security model

`tests/rls_test.sql` exercises the policies as four different users, including an
outsider trying to break in. Run it against a scratch project or a branch —
**never against production**, it creates and deletes users.

Every check passed on 2026-09-02:

| Check | Result |
|---|---|
| Partner sees shared alarms and profile | ✅ |
| Partner cannot see the other's invite codes | ✅ codes are bearer tokens |
| Outsider sees no alarms, pairs, members, invites or sounds | ✅ only own profile |
| Outsider cannot join a pair, even a half-empty one with the id known | ✅ RLS |
| Outsider cannot inject an alarm into someone else's pair | ✅ RLS |
| Outsider cannot spoof an alarm as another user | ✅ RLS |
| Outsider cannot flip another user's dismiss preference | ✅ 0 rows |
| Reused / unknown invite code | ✅ refused |
| Partner writing the other's ring row directly | ✅ 0 rows |
| Partner dismissing via `act_on_partner()` | ✅ allowed |
| …with `allow_partner_dismiss = false` | ✅ "partner has turned off remote dismiss" |
| Stranger calling `act_on_partner()` | ✅ "not your partner" |
