-- Run in Supabase SQL Editor. Never put service_role keys in the website.
create extension if not exists btree_gist;
create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 is_owner boolean not null default false
);
create table if not exists public.bookings (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id),
 guest_name text not null check (length(trim(guest_name)) between 2 and 80),
 start_date date not null,
 end_date date not null,
 status text not null default 'pending' check (status in ('pending','confirmed','cancelled')),
 created_at timestamptz not null default now(),
 constraint valid_dates check (end_date>=start_date and end_date-start_date<=364)
);
-- Block overlapping pending or confirmed requests, including concurrent submissions.
alter table public.bookings add constraint no_overlapping_active_bookings
 exclude using gist (daterange(start_date,end_date+1,'[)') with &&)
 where (status in ('pending','confirmed'));
create or replace function public.create_profile() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id) values(new.id) on conflict do nothing; return new; end $$;
drop trigger if exists create_profile_on_signup on auth.users;
create trigger create_profile_on_signup after insert on auth.users for each row execute function public.create_profile();
insert into public.profiles(id) select id from auth.users on conflict do nothing;
create or replace function public.is_chalet_owner() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_owner=true)
$$;
alter table public.profiles enable row level security;
alter table public.bookings enable row level security;
create policy "read own profile" on public.profiles for select to authenticated using(id=auth.uid());
create policy "family can view bookings" on public.bookings for select to authenticated using(true);
create policy "family can request pending booking" on public.bookings for insert to authenticated
 with check (user_id=auth.uid() and status='pending');
create policy "owner may update booking status" on public.bookings for update to authenticated
 using(public.is_chalet_owner()) with check(public.is_chalet_owner());
-- After owner signs in once, replace email and run this in SQL Editor:
-- update public.profiles set is_owner=true
-- where id=(select id from auth.users where email='OWNER_EMAIL@example.com');
