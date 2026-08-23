-- TravelMap schema.
--
-- Run this once against a fresh Supabase project (SQL Editor, or `supabase db push`).
-- Every table in here is final as of V1 even though only `profiles` and `visits` have
-- UI yet: regions are V2 and friends/comments are V3, and the schema shouldn't have to
-- be redesigned to get there.
--
-- Auth users live in `auth.users`; `profiles` is the app-visible extension of them.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  friend_code text unique not null,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  country_code text not null,          -- ISO 3166-1 alpha-2, e.g. 'ES'
  visited_at date,
  note text,
  -- Object paths in the private `visit-photos` bucket, at most four. Paths rather than
  -- URLs because the bucket is private and links have to be signed at read time.
  photo_urls text[],
  created_at timestamptz not null default now(),
  constraint visits_country_code_format check (country_code ~ '^[A-Z]{2}$'),
  constraint visits_photo_limit check (photo_urls is null or array_length(photo_urls, 1) <= 4)
);

create table if not exists public.region_visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  country_code text not null,
  region_code text not null,           -- ISO 3166-2 where Natural Earth has it
  visited_at date,
  note text,
  photo_urls text[],
  created_at timestamptz not null default now(),
  constraint region_visits_country_code_format check (country_code ~ '^[A-Z]{2}$'),
  constraint region_visits_photo_limit check (photo_urls is null or array_length(photo_urls, 1) <= 4)
);

create table if not exists public.friendships (
  user_id uuid not null references public.profiles (id) on delete cascade,
  friend_id uuid not null references public.profiles (id) on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  constraint friendships_no_self check (user_id <> friend_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  target_user_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('country', 'region')),
  target_code text not null,
  text text not null check (length(text) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists visits_user_id_idx on public.visits (user_id);
create index if not exists visits_user_country_idx on public.visits (user_id, country_code);
create index if not exists region_visits_user_id_idx on public.region_visits (user_id);
create index if not exists region_visits_user_country_idx on public.region_visits (user_id, country_code);
create index if not exists friendships_friend_id_idx on public.friendships (friend_id);
create index if not exists comments_target_idx on public.comments (target_user_id, target_type, target_code);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Friendship is stored as one directed row per accepted pair, in whichever direction the
-- request was made, so "are these two friends" has to check both.
--
-- SECURITY DEFINER matters here: the visits policies call this, and without it the check
-- would re-enter the friendships policies and recurse.
create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.user_id = a and f.friend_id = b) or (f.user_id = b and f.friend_id = a))
  );
$$;

-- Eight characters from an unambiguous alphabet (no O/0, I/1) so a code can be read
-- aloud or typed off a screen without a second guess.
create or replace function public.generate_friend_code()
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
begin
  loop
    candidate := '';
    for _ in 1..8 loop
      candidate := candidate || substr(alphabet, floor(random() * length(alphabet))::int + 1, 1);
    end loop;
    exit when not exists (select 1 from public.profiles where friend_code = candidate);
  end loop;
  return candidate;
end;
$$;

-- Every auth user gets a profile the moment they sign up, so the client never has to
-- create one (and never has to handle the window where it doesn't exist yet).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, friend_code)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1)),
    public.generate_friend_code()
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Deletes the calling user's account and everything attached to it.
--
-- Any app that can create an account has to be able to delete one (App Review
-- Guideline 5.1.1(v)), and removing a row from auth.users is past what a client key can
-- do. SECURITY DEFINER puts the deletion behind a function the caller can only invoke
-- for themselves: auth.uid() is read inside, so there is no argument to tamper with.
--
-- The profile cascade takes visits, region_visits, friendships, and comments with it;
-- storage objects have no foreign key, so they are removed explicitly first.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'delete_account requires an authenticated caller';
  end if;

  delete from storage.objects
  where bucket_id = 'visit-photos'
    and lower((storage.foldername(name))[1]) = caller::text;

  delete from auth.users where id = caller;
end;
$$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.visits enable row level security;
alter table public.region_visits enable row level security;
alter table public.friendships enable row level security;
alter table public.comments enable row level security;

-- Profiles: yours, plus anyone you're actually friends with.
drop policy if exists "profiles readable by self and friends" on public.profiles;
create policy "profiles readable by self and friends" on public.profiles
  for select using (id = (select auth.uid()) or public.are_friends(id, (select auth.uid())));

drop policy if exists "profiles updatable by owner" on public.profiles;
create policy "profiles updatable by owner" on public.profiles
  for update using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Visits: read your own or an accepted friend's; only ever write your own.
drop policy if exists "visits readable by owner and friends" on public.visits;
create policy "visits readable by owner and friends" on public.visits
  for select using (user_id = (select auth.uid()) or public.are_friends(user_id, (select auth.uid())));

drop policy if exists "visits insertable by owner" on public.visits;
create policy "visits insertable by owner" on public.visits
  for insert with check (user_id = (select auth.uid()));

drop policy if exists "visits updatable by owner" on public.visits;
create policy "visits updatable by owner" on public.visits
  for update using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "visits deletable by owner" on public.visits;
create policy "visits deletable by owner" on public.visits
  for delete using (user_id = (select auth.uid()));

drop policy if exists "region visits readable by owner and friends" on public.region_visits;
create policy "region visits readable by owner and friends" on public.region_visits
  for select using (user_id = (select auth.uid()) or public.are_friends(user_id, (select auth.uid())));

drop policy if exists "region visits insertable by owner" on public.region_visits;
create policy "region visits insertable by owner" on public.region_visits
  for insert with check (user_id = (select auth.uid()));

drop policy if exists "region visits updatable by owner" on public.region_visits;
create policy "region visits updatable by owner" on public.region_visits
  for update using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "region visits deletable by owner" on public.region_visits;
create policy "region visits deletable by owner" on public.region_visits
  for delete using (user_id = (select auth.uid()));

-- Friendships: visible and editable only to the two people in the row. Requests are
-- always sent as yourself, and either side can accept, decline, or unfriend.
drop policy if exists "friendships visible to both parties" on public.friendships;
create policy "friendships visible to both parties" on public.friendships
  for select using ((select auth.uid()) in (user_id, friend_id));

drop policy if exists "friendships requestable by sender" on public.friendships;
create policy "friendships requestable by sender" on public.friendships
  for insert with check (user_id = (select auth.uid()));

drop policy if exists "friendships updatable by both parties" on public.friendships;
create policy "friendships updatable by both parties" on public.friendships
  for update using ((select auth.uid()) in (user_id, friend_id))
  with check ((select auth.uid()) in (user_id, friend_id));

drop policy if exists "friendships deletable by both parties" on public.friendships;
create policy "friendships deletable by both parties" on public.friendships
  for delete using ((select auth.uid()) in (user_id, friend_id));

-- Comments: a guestbook on someone's map, so the author and the map's owner can read
-- them, and you can only post to a friend's map (or your own).
drop policy if exists "comments readable by author and target" on public.comments;
create policy "comments readable by author and target" on public.comments
  for select using ((select auth.uid()) in (author_id, target_user_id));

drop policy if exists "comments writable by friends" on public.comments;
create policy "comments writable by friends" on public.comments
  for insert with check (
    author_id = (select auth.uid())
    and (target_user_id = (select auth.uid()) or public.are_friends(target_user_id, (select auth.uid())))
  );

drop policy if exists "comments deletable by author or target" on public.comments;
create policy "comments deletable by author or target" on public.comments
  for delete using ((select auth.uid()) in (author_id, target_user_id));

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------

-- Private bucket. The app writes to '<user_id>/<visit_id>/<n>.jpg' and reads back
-- through signed URLs, so the first path segment is what ownership is checked against.
--
-- The comparisons below lower() that segment. Postgres renders auth.uid()::text in
-- lowercase while some clients render a UUID in uppercase (Swift's UUID.uuidString
-- does), and a case mismatch here fails as an opaque "violates row-level security
-- policy" a long way from its cause.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('visit-photos', 'visit-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "visit photos readable by owner and friends" on storage.objects;
create policy "visit photos readable by owner and friends" on storage.objects
  for select using (
    bucket_id = 'visit-photos'
    and (
      lower((storage.foldername(name))[1]) = (select auth.uid())::text
      or public.are_friends(((storage.foldername(name))[1])::uuid, (select auth.uid()))
    )
  );

drop policy if exists "visit photos writable by owner" on storage.objects;
create policy "visit photos writable by owner" on storage.objects
  for insert with check (
    bucket_id = 'visit-photos' and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

drop policy if exists "visit photos updatable by owner" on storage.objects;
create policy "visit photos updatable by owner" on storage.objects
  for update using (
    bucket_id = 'visit-photos' and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

drop policy if exists "visit photos deletable by owner" on storage.objects;
create policy "visit photos deletable by owner" on storage.objects
  for delete using (
    bucket_id = 'visit-photos' and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );
