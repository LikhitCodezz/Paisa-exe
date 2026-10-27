-- Run this in Supabase SQL Editor before enabling cloud accounts.
-- Each account receives one JSON document. RLS limits all operations to its owner.
create table if not exists public.paisa_user_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.paisa_user_data enable row level security;

create or replace function public.paisa_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists paisa_user_data_updated_at on public.paisa_user_data;
create trigger paisa_user_data_updated_at
  before update on public.paisa_user_data
  for each row execute function public.paisa_set_updated_at();

revoke all on public.paisa_user_data from anon;
revoke all on public.paisa_user_data from public;
grant select, insert, update, delete on public.paisa_user_data to authenticated;

drop policy if exists "Users can read their own Paisa data" on public.paisa_user_data;
create policy "Users can read their own Paisa data"
  on public.paisa_user_data for select to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Users can create their own Paisa data" on public.paisa_user_data;
create policy "Users can create their own Paisa data"
  on public.paisa_user_data for insert to authenticated
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Users can update their own Paisa data" on public.paisa_user_data;
create policy "Users can update their own Paisa data"
  on public.paisa_user_data for update to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Users can delete their own Paisa data" on public.paisa_user_data;
create policy "Users can delete their own Paisa data"
  on public.paisa_user_data for delete to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);
