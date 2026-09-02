-- The local variable `code` shadowed pair_invites.code, so the uniqueness check
-- compared the variable against itself: "column reference code is ambiguous".
-- Prefixing locals with v_ is the convention everywhere else in this schema.
create or replace function public.generate_invite_code()
returns text language plpgsql security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.pair_invites pi where pi.code = v_code);
  end loop;
  return v_code;
end; $$;

revoke all on function public.generate_invite_code() from public, anon, authenticated;
