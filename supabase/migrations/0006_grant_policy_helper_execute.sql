-- Correction to 0004.
--
-- That migration claimed RLS policy evaluation does not require the caller to
-- hold EXECUTE on functions used in the policy. That is false: policy
-- expressions run as the calling role, so revoking EXECUTE from `authenticated`
-- broke every policy that calls these, with:
--
--   ERROR: 42501: permission denied for function is_pair_member
--
-- Both must stay SECURITY DEFINER (is_pair_member reads pair_members, which is
-- itself protected by a policy that calls is_pair_member -- invoker rights would
-- recurse), so the grant is required.
--
-- The exposure is small and bounded: both answer only questions about the
-- CALLER. is_pair_member(p) says whether the caller is in pair p;
-- shares_pair_with(u) says whether the caller shares a pair with u. Neither
-- reveals anything about other people's pairs.
grant execute on function public.is_pair_member(uuid)   to authenticated;
grant execute on function public.shares_pair_with(uuid) to authenticated;
