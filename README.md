# SPICY VAULT Mini App

Telegram Mini App project.

## Live app
https://limonsheikh01.github.io/SPICY-VAULT-MINI-APP/

## Admin prototype
https://limonsheikh01.github.io/SPICY-VAULT-MINI-APP/admin.html

Admin currently stores entries in browser-local storage only. It is a UI prototype and does not publish to the public app yet.

## Database foundation
Starter Supabase schema is in `supabase-setup.sql`. It creates:
- `videos` catalog
- `video_unlocks` table for per-user unlock records
- Row Level Security (RLS) enabled
- Public read policy only for published videos
- Users can only read/insert their own unlock rows
- Admin write policy is intentionally omitted until authentication/admin identity is configured

### Next setup needed
Create a free Supabase project, run `supabase-setup.sql` in SQL Editor, and share only the project's public URL and anon key (never service-role key). After that, frontend/database integration and admin authentication can be completed.
