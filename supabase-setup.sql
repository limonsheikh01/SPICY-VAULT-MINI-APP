-- SPICY VAULT: Supabase schema + secure admin policies
create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'New',
  poster_url text,
  video_url text not null,
  published boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.video_unlocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  unique(user_id, video_id)
);
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.videos enable row level security;
alter table public.video_unlocks enable row level security;
alter table public.admins enable row level security;
create or replace function public.is_spicy_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.admins where user_id=auth.uid()) $$;
drop policy if exists "Anyone can view published videos" on public.videos;
drop policy if exists "Published videos or admin read" on public.videos;
drop policy if exists "Admin insert videos" on public.videos;
drop policy if exists "Admin update videos" on public.videos;
drop policy if exists "Admin delete videos" on public.videos;
create policy "Published videos or admin read" on public.videos for select using (published=true or public.is_spicy_admin());
create policy "Admin insert videos" on public.videos for insert with check (public.is_spicy_admin());
create policy "Admin update videos" on public.videos for update using (public.is_spicy_admin()) with check (public.is_spicy_admin());
create policy "Admin delete videos" on public.videos for delete using (public.is_spicy_admin());
drop policy if exists "Users view own unlocks" on public.video_unlocks;
drop policy if exists "Users insert own unlocks" on public.video_unlocks;
create policy "Users view own unlocks" on public.video_unlocks for select using (auth.uid()=user_id);
create policy "Users insert own unlocks" on public.video_unlocks for insert with check (auth.uid()=user_id);
drop policy if exists "Admins read own admin row" on public.admins;
create policy "Admins read own admin row" on public.admins for select using (auth.uid()=user_id);

-- Required SQL privileges (RLS policies above still control row access)
grant usage on schema public to anon, authenticated;
grant select on public.videos to anon, authenticated;
grant insert, update, delete on public.videos to authenticated;
grant select, insert on public.video_unlocks to authenticated;
grant select on public.admins to authenticated;
