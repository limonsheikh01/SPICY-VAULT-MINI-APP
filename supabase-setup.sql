-- SPICY VAULT database setup (Supabase SQL Editor)
-- Run this once in your Supabase project's SQL Editor.
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
alter table public.videos enable row level security;
alter table public.video_unlocks enable row level security;
-- Public can only see published catalog entries (video URLs should be protected later).
create policy "Anyone can view published videos" on public.videos
for select using (published = true);
-- Users can view their own unlocks and insert only their own user ID.
create policy "Users view own unlocks" on public.video_unlocks
for select using (auth.uid() = user_id);
create policy "Users insert own unlocks" on public.video_unlocks
for insert with check (auth.uid() = user_id);
-- Admin write policy is intentionally NOT created yet. Add only after admin login is configured.
