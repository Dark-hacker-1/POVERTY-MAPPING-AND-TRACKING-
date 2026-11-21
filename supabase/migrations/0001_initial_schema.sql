-- Poverty Mapping & Tracking: initial schema
create extension if not exists pgcrypto;
create extension if not exists postgis;

create type public.account_role as enum ('citizen','volunteer');
create type public.issue_status as enum ('OPEN','CLAIMED','IN_PROGRESS','AWAITING_CITIZEN_CONFIRMATION','RESOLVED','DISPUTED','REOPENED');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null check (length(trim(full_name)) between 1 and 100),
 role public.account_role not null,
 avatar_url text,
 preferred_radius_km integer not null default 5 check (preferred_radius_km in (1,3,5,10,20)),
 preferred_lat double precision,
 preferred_lng double precision,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check ((preferred_lat is null and preferred_lng is null) or (preferred_lat between -90 and 90 and preferred_lng between -180 and 180))
);

create table public.issues (
 id uuid primary key default gen_random_uuid(),
 issue_code text not null unique default ('PMT-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 reporter_id uuid not null references public.profiles(id),
 title text not null check(length(trim(title)) between 5 and 140),
 category text not null check(category in ('Roads','Drainage','Garbage','Water supply','Streetlights','Sanitation','Public facilities','Public safety','Other')),
 description text not null check(length(trim(description)) between 15 and 5000),
 state text not null, district text not null, city text not null, locality text not null, address text,
 latitude double precision not null check(latitude between -90 and 90), longitude double precision not null check(longitude between -180 and 180),
 location geography(point,4326) generated always as (st_setsrid(st_makepoint(longitude,latitude),4326)::geography) stored,
 urgency text not null default 'MEDIUM' check(urgency in ('LOW','MEDIUM','HIGH','URGENT')),
 status public.issue_status not null default 'OPEN', original_photo_path text not null, original_photo_url text not null,
 public_consent boolean not null default false check(public_consent),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index issues_location_gix on public.issues using gist(location);
create index issues_status_idx on public.issues(status);
create index issues_created_idx on public.issues(created_at desc);

create table public.issue_volunteers (
 id uuid primary key default gen_random_uuid(), issue_id uuid not null references public.issues(id) on delete cascade,
 volunteer_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(), left_at timestamptz,
 unique(issue_id,volunteer_id)
);
create index issue_volunteers_issue_idx on public.issue_volunteers(issue_id) where left_at is null;

create table public.issue_evidence (
 id uuid primary key default gen_random_uuid(), issue_id uuid not null references public.issues(id) on delete cascade,
 uploaded_by uuid not null references public.profiles(id), file_path text not null, file_url text not null,
 evidence_type text not null check(evidence_type in ('BEFORE','AFTER')), created_at timestamptz not null default now()
);
create table public.issue_comments (
 id uuid primary key default gen_random_uuid(), issue_id uuid not null references public.issues(id) on delete cascade,
 user_id uuid not null references public.profiles(id), body text not null check(length(trim(body)) between 1 and 2000), created_at timestamptz not null default now()
);
create table public.issue_supports (
 id uuid primary key default gen_random_uuid(), issue_id uuid not null references public.issues(id) on delete cascade,
 user_id uuid not null references public.profiles(id), created_at timestamptz not null default now(), unique(issue_id,user_id)
);
create table public.issue_status_history (
 id uuid primary key default gen_random_uuid(), issue_id uuid not null references public.issues(id) on delete cascade,
 old_status public.issue_status, new_status public.issue_status not null, changed_by uuid references public.profiles(id), note text,
 created_at timestamptz not null default now()
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 issue_id uuid references public.issues(id) on delete cascade, title text not null, body text not null,
 read_at timestamptz, created_at timestamptz not null default now()
);

create or replace function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create trigger profiles_updated before update on public.profiles for each row execute function public.set_updated_at();
create trigger issues_updated before update on public.issues for each row execute function public.set_updated_at();

-- Profile role is selected at signup and cannot be changed by the account owner later.
create or replace function public.protect_profile_role() returns trigger language plpgsql as $$
begin
 if new.role is distinct from old.role and auth.uid() is not null then raise exception 'Account role cannot be changed'; end if;
 return new;
end $$;
create trigger profiles_role_guard before update on public.profiles for each row execute function public.protect_profile_role();

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare chosen_role public.account_role;
begin
 chosen_role := case when new.raw_user_meta_data->>'role' = 'volunteer' then 'volunteer'::public.account_role else 'citizen'::public.account_role end;
 insert into public.profiles(id,full_name,role) values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),'Community member'),chosen_role);
 return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Public view intentionally omits reporter identity and exact street address.
create or replace view public.public_issues as
 select i.id,i.issue_code,i.title,i.category,i.description,i.state,i.district,i.city,i.locality,
 i.latitude,i.longitude,i.urgency,i.status,i.created_at,i.original_photo_url,
 (select count(*)::integer from public.issue_volunteers v where v.issue_id=i.id and v.left_at is null) as volunteer_count
 from public.issues i where i.public_consent=true;

create or replace function public.nearby_open_issues(p_lat double precision,p_lng double precision,p_radius_km integer default 5)
returns table(id uuid,issue_code text,title text,category text,description text,locality text,city text,latitude double precision,longitude double precision,urgency text,status public.issue_status,created_at timestamptz,distance_km double precision,volunteer_count bigint)
language sql stable security invoker set search_path=public as $$
 select i.id,i.issue_code,i.title,i.category,i.description,i.locality,i.city,i.latitude,i.longitude,i.urgency,i.status,i.created_at,
 st_distance(i.location,st_setsrid(st_makepoint(p_lng,p_lat),4326)::geography)/1000 as distance_km,
 (select count(*) from public.issue_volunteers v where v.issue_id=i.id and v.left_at is null) as volunteer_count
 from public.issues i where i.public_consent and i.status in ('OPEN','REOPENED')
 and st_dwithin(i.location,st_setsrid(st_makepoint(p_lng,p_lat),4326)::geography,greatest(1,least(p_radius_km,20))*1000)
 order by distance_km;
$$;

create or replace function public.join_issue(p_issue_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare new_id uuid;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and role='volunteer') then raise exception 'Volunteer account required'; end if;
 if not exists(select 1 from public.issues where id=p_issue_id and status in ('OPEN','CLAIMED','IN_PROGRESS','REOPENED')) then raise exception 'Issue is not accepting volunteers'; end if;
 insert into public.issue_volunteers(issue_id,volunteer_id) values(p_issue_id,auth.uid()) returning id into new_id;
 update public.issues set status=case when status='OPEN' or status='REOPENED' then 'CLAIMED'::public.issue_status else status end where id=p_issue_id;
 return new_id;
end $$;

create or replace function public.citizen_review_resolution(p_issue_id uuid,p_approved boolean) returns void language plpgsql security definer set search_path=public as $$
declare reporter uuid;
begin
 select reporter_id into reporter from public.issues where id=p_issue_id for update;
 if reporter is null or reporter <> auth.uid() then raise exception 'Only the reporting citizen can review this resolution'; end if;
 if not exists(select 1 from public.issues where id=p_issue_id and status='AWAITING_CITIZEN_CONFIRMATION') then raise exception 'Issue is not awaiting citizen confirmation'; end if;
 update public.issues set status=case when p_approved then 'RESOLVED'::public.issue_status else 'DISPUTED'::public.issue_status end where id=p_issue_id;
 insert into public.issue_status_history(issue_id,old_status,new_status,changed_by) values(p_issue_id,'AWAITING_CITIZEN_CONFIRMATION',case when p_approved then 'RESOLVED'::public.issue_status else 'DISPUTED'::public.issue_status end,auth.uid());
end $$;

alter table public.profiles enable row level security;
alter table public.issues enable row level security;
alter table public.issue_volunteers enable row level security;
alter table public.issue_evidence enable row level security;
alter table public.issue_comments enable row level security;
alter table public.issue_supports enable row level security;
alter table public.issue_status_history enable row level security;
alter table public.notifications enable row level security;

create policy "Profiles are viewable by owner" on public.profiles for select to authenticated using(id=auth.uid());
create policy "Users can update own non-role profile" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy "Public can read consented issues" on public.issues for select to anon,authenticated using(public_consent=true);
create policy "Citizens can create own reports" on public.issues for insert to authenticated with check(reporter_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='citizen'));
create policy "Volunteers can view public assignments" on public.issue_volunteers for select to anon,authenticated using(exists(select 1 from public.issues i where i.id=issue_id and i.public_consent));
create policy "Volunteer can join own assignment" on public.issue_volunteers for insert to authenticated with check(volunteer_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='volunteer'));
create policy "Volunteer can leave own assignment" on public.issue_volunteers for update to authenticated using(volunteer_id=auth.uid()) with check(volunteer_id=auth.uid());
create policy "Public can view issue evidence" on public.issue_evidence for select to anon,authenticated using(exists(select 1 from public.issues i where i.id=issue_id and i.public_consent));
create policy "Assigned volunteers can submit evidence" on public.issue_evidence for insert to authenticated with check(uploaded_by=auth.uid() and exists(select 1 from public.issue_volunteers v where v.issue_id=issue_id and v.volunteer_id=auth.uid() and v.left_at is null));
create policy "Public can read comments" on public.issue_comments for select to anon,authenticated using(exists(select 1 from public.issues i where i.id=issue_id and i.public_consent));
create policy "Authenticated users can comment as self" on public.issue_comments for insert to authenticated with check(user_id=auth.uid());
create policy "Public can read support totals" on public.issue_supports for select to anon,authenticated using(true);
create policy "Authenticated users can support once" on public.issue_supports for insert to authenticated with check(user_id=auth.uid());
create policy "Public can read status timeline" on public.issue_status_history for select to anon,authenticated using(exists(select 1 from public.issues i where i.id=issue_id and i.public_consent));
create policy "Users read own notifications" on public.notifications for select to authenticated using(user_id=auth.uid());
create policy "Users update own notifications" on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

revoke all on public.issues from anon;
grant select on public.issues to authenticated;
grant select on public.public_issues to anon,authenticated;
grant execute on function public.nearby_open_issues(double precision,double precision,integer) to authenticated;
grant execute on function public.join_issue(uuid) to authenticated;
grant execute on function public.citizen_review_resolution(uuid,boolean) to authenticated;

-- Storage buckets; uploaded public evidence is visible only because reporters consent on submission.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('problem-evidence','problem-evidence',true,8388608,array['image/jpeg','image/png','image/webp']),
 ('resolution-evidence','resolution-evidence',true,8388608,array['image/jpeg','image/png','image/webp']),
 ('profile-avatars','profile-avatars',true,2097152,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy "Public can view public evidence files" on storage.objects for select to anon,authenticated using(bucket_id in ('problem-evidence','resolution-evidence','profile-avatars'));
create policy "Users upload into own evidence folder" on storage.objects for insert to authenticated with check(bucket_id in ('problem-evidence','resolution-evidence') and (storage.foldername(name))[1]=auth.uid()::text);
create policy "Users upload own avatar" on storage.objects for insert to authenticated with check(bucket_id='profile-avatars' and (storage.foldername(name))[1]=auth.uid()::text);

-- Every status transition is recorded; completion evidence moves the issue to citizen review.
create or replace function public.record_issue_status() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status is distinct from old.status then
  insert into public.issue_status_history(issue_id,old_status,new_status,changed_by) values(new.id,old.status,new.status,auth.uid());
 end if;
 return new;
end $$;
create trigger issue_status_audit after update of status on public.issues for each row execute function public.record_issue_status();

create or replace function public.submit_resolution_evidence(p_issue_id uuid,p_file_path text,p_file_url text) returns uuid
language plpgsql security definer set search_path=public as $$
declare new_evidence uuid;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if not exists(select 1 from public.issue_volunteers v where v.issue_id=p_issue_id and v.volunteer_id=auth.uid() and v.left_at is null) then raise exception 'You must be an active volunteer on this issue'; end if;
 if not exists(select 1 from public.issues where id=p_issue_id and status in ('CLAIMED','IN_PROGRESS','DISPUTED','REOPENED')) then raise exception 'Issue is not accepting completion evidence'; end if;
 insert into public.issue_evidence(issue_id,uploaded_by,file_path,file_url,evidence_type) values(p_issue_id,auth.uid(),p_file_path,p_file_url,'AFTER') returning id into new_evidence;
 update public.issues set status='AWAITING_CITIZEN_CONFIRMATION' where id=p_issue_id;
 return new_evidence;
end $$;
grant execute on function public.submit_resolution_evidence(uuid,text,text) to authenticated;
