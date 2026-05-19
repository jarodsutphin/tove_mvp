-- ============================================================
-- STORAGE — guest-photos bucket
-- Private bucket: all access via signed URLs only (never public URLs).
-- Path format: guest-photos/{guest_id}/profile.jpg
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'guest-photos',
  'guest-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
);


-- ============================================================
-- STORAGE RLS POLICIES
--
-- Scenario A (SHOULD SUCCEED):
--   A business user authenticated as a business that has at least one
--   booking in status confirmed/arrived/seated/checked_in/completed
--   for the guest whose folder is being accessed.
--   → exists() subquery returns true → policy grants access.
--
-- Scenario B (SHOULD FAIL):
--   A business user with no booking history for this guest.
--   → exists() subquery returns false → policy denies access.
--   No other policy matches → storage returns 403.
--
-- Scenario C (SHOULD SUCCEED):
--   The authenticated guest reading their own photo.
--   → path's first folder segment matches auth_guest_id() → policy grants access.
-- ============================================================

-- Scenario A: business reads guest photo (requires confirmed booking history)
create policy "business_reads_guest_photo"
  on storage.objects for select
  using (
    bucket_id = 'guest-photos'
    and exists (
      select 1
      from guests g
      join bookings b on b.guest_id = g.id
      where g.id::text = (storage.foldername(name))[1]
        and b.business_id = auth_business_id()
        and b.status in ('confirmed','arrived','seated','checked_in','completed')
    )
  );

-- Scenario B: no matching policy → implicit deny (no separate policy needed)

-- Scenario C: guest reads their own photo
create policy "guest_reads_own_photo"
  on storage.objects for select
  using (
    bucket_id = 'guest-photos'
    and (storage.foldername(name))[1] = auth_guest_id()::text
  );

-- Guest writes (upload) their own photo
create policy "guest_writes_own_photo"
  on storage.objects for insert
  with check (
    bucket_id = 'guest-photos'
    and (storage.foldername(name))[1] = auth_guest_id()::text
  );

-- Guest deletes their own photo
create policy "guest_deletes_own_photo"
  on storage.objects for delete
  using (
    bucket_id = 'guest-photos'
    and (storage.foldername(name))[1] = auth_guest_id()::text
  );
