-- Campaign pictures (Fiona, 2026-11-24): the hero image in a promotion email is fetched by the recipient's email
-- client, so it needs a public address. One public bucket, written only by the service role (no policy for anyone
-- else), read by anyone. The same picture for every recipient: no per-person URL, so no tracking pixel.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('marketing', 'marketing', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
