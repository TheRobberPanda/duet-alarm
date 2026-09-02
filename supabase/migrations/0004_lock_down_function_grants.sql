-- Postgres grants EXECUTE on new functions to PUBLIC by default, and PostgREST
-- exposes anything the anon/authenticated roles can execute at /rest/v1/rpc/*.
-- That means every trigger and helper function in 0002 was callable over HTTP.
--
-- Revoke everything, then grant back only the four functions that are genuinely
-- part of the app's API, and only to signed-in users.
--
-- NOTE: this migration went too far. See 0006 -- RLS policy evaluation DOES
-- require the calling role to hold EXECUTE on functions used in the policy, so
-- is_pair_member and shares_pair_with had to be granted back.

revoke all on function public.set_updated_at()          from public, anon, authenticated;
revoke all on function public.handle_new_user()         from public, anon, authenticated;
revoke all on function public.enforce_one_active_pair() from public, anon, authenticated;
revoke all on function public.enforce_pair_size()       from public, anon, authenticated;

revoke all on function public.is_pair_member(uuid)      from public, anon, authenticated;
revoke all on function public.shares_pair_with(uuid)    from public, anon, authenticated;
-- generate_invite_code must not be callable: it would let anyone enumerate
-- unused codes.
revoke all on function public.generate_invite_code()    from public, anon, authenticated;

revoke all on function public.create_pair_invite()             from public, anon;
revoke all on function public.redeem_pair_invite(text)         from public, anon;
revoke all on function public.act_on_partner(uuid, uuid, text) from public, anon;
revoke all on function public.delete_my_account()              from public, anon;

grant execute on function public.create_pair_invite()             to authenticated;
grant execute on function public.redeem_pair_invite(text)         to authenticated;
grant execute on function public.act_on_partner(uuid, uuid, text) to authenticated;
grant execute on function public.delete_my_account()              to authenticated;
