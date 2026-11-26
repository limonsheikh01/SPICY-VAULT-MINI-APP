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


-- Public media bucket for uploaded videos and poster images (50 MB per file)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'vault-videos',
  'vault-videos',
  true,
  52428800,
  array['video/mp4','video/webm','video/quicktime','image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = true,
    file_size_limit = 52428800,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Public can view SPICY VAULT media" on storage.objects;
create policy "Public can view SPICY VAULT media"
on storage.objects for select
using (bucket_id = 'vault-videos');

drop policy if exists "SPICY admins upload media" on storage.objects;
create policy "SPICY admins upload media"
on storage.objects for insert to authenticated
with check (bucket_id = 'vault-videos' and public.is_spicy_admin());

drop policy if exists "SPICY admins update media" on storage.objects;
create policy "SPICY admins update media"
on storage.objects for update to authenticated
using (bucket_id = 'vault-videos' and public.is_spicy_admin())
with check (bucket_id = 'vault-videos' and public.is_spicy_admin());

drop policy if exists "SPICY admins delete media" on storage.objects;
create policy "SPICY admins delete media"
on storage.objects for delete to authenticated
using (bucket_id = 'vault-videos' and public.is_spicy_admin());

 
-- SPICY VAULT live presence and video-view analytics
create table if not exists public.app_presence (
  user_key text primary key,
  display_name text not null default 'Member',
  username text,
  platform text not null default 'Web',
  last_seen timestamptz not null default now()
);
create index if not exists app_presence_last_seen_idx on public.app_presence(last_seen desc);
alter table public.app_presence enable row level security;
drop policy if exists "Public can update own presence heartbeat" on public.app_presence;
drop policy if exists "Public can insert presence heartbeat" on public.app_presence;
drop policy if exists "Admins can read presence" on public.app_presence;
create policy "Public can insert presence heartbeat" on public.app_presence for insert to anon, authenticated with check (true);
create policy "Public can update own presence heartbeat" on public.app_presence for update to anon, authenticated using (true) with check (true);
create policy "Admins can read presence" on public.app_presence for select to authenticated using (public.is_spicy_admin());
grant insert, update on public.app_presence to anon, authenticated;
grant select on public.app_presence to authenticated;

create table if not exists public.video_views (
  id uuid primary key default gen_random_uuid(),
  video_id uuid references public.videos(id) on delete set null,
  viewer_key text not null,
  video_title text not null default 'Video',
  viewed_at timestamptz not null default now()
);
create index if not exists video_views_video_id_idx on public.video_views(video_id);
create index if not exists video_views_viewed_at_idx on public.video_views(viewed_at desc);
alter table public.video_views enable row level security;
drop policy if exists "Public can record video views" on public.video_views;
drop policy if exists "Admins can read video views" on public.video_views;
create policy "Public can record video views" on public.video_views for insert to anon, authenticated with check (true);
create policy "Admins can read video views" on public.video_views for select to authenticated using (public.is_spicy_admin());
grant insert on public.video_views to anon, authenticated;
grant select on public.video_views to authenticated;
