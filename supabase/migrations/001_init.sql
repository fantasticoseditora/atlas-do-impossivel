-- Atlas do Impossível — esquema público reproduzível
-- Não contém manuscritos, e-mails, pedidos ou credenciais.
create extension if not exists pgcrypto;

create table if not exists public.authors (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  legal_name text,
  created_at timestamptz not null default now()
);
create table if not exists public.works (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.authors(id),
  title text not null,
  created_at timestamptz not null default now(),
  unique(author_id,title)
);
create table if not exists public.editions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  season text not null,
  publication_status text not null default 'production'
    check (publication_status in ('production','published','archived')),
  published_at timestamptz
);
create table if not exists public.portals (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.editions(id),
  work_id uuid not null references public.works(id),
  portal_number smallint not null check (portal_number > 0),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  symbol text not null,
  invitation text not null,
  public_status text not null default 'production'
    check (public_status in ('production','open','closed')),
  unique(edition_id,portal_number)
);
create table if not exists public.reader_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  public_name text,
  consent_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.reader_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','revoked')),
  order_reference_hash text,
  evidence_path text,
  decided_by uuid references auth.users(id),
  decision_reason text,
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  unique(user_id)
);
create table if not exists public.votes (
  id uuid primary key default gen_random_uuid(),
  reader_id uuid not null references auth.users(id) on delete cascade,
  portal_id uuid not null references public.portals(id) on delete cascade,
  score smallint not null check (score between 1 and 5),
  status text not null default 'valid'
    check (status in ('valid','quarantined','invalidated')),
  first_cast_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(reader_id,portal_id)
);
create table if not exists public.vote_history (
  id uuid primary key default gen_random_uuid(),
  vote_id uuid not null references public.votes(id) on delete cascade,
  reader_id uuid not null references auth.users(id) on delete cascade,
  portal_id uuid not null references public.portals(id) on delete cascade,
  previous_score smallint,
  new_score smallint not null check (new_score between 1 and 5),
  event_id uuid not null unique,
  ip_hash text,
  user_agent_hash text,
  created_at timestamptz not null default now()
);
create table if not exists public.testimonials (
  id uuid primary key default gen_random_uuid(),
  reader_id uuid not null references auth.users(id) on delete cascade,
  portal_id uuid not null references public.portals(id) on delete cascade,
  body text not null check (char_length(body) between 10 and 1200),
  moderation_status text not null default 'pending'
    check (moderation_status in ('pending','published','hidden','rejected')),
  moderator_id uuid references auth.users(id),
  moderation_reason text,
  created_at timestamptz not null default now(),
  moderated_at timestamptz
);
create table if not exists public.partners (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete set null,
  display_name text not null,
  status text not null default 'active' check (status in ('active','suspended','inactive'))
);
create table if not exists public.partner_scores (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id),
  portal_id uuid not null references public.portals(id),
  score numeric(4,2) not null check (score between 0 and 5),
  submitted_at timestamptz not null default now(),
  unique(partner_id,portal_id)
);
create table if not exists public.editorial_scores (
  id uuid primary key default gen_random_uuid(),
  evaluator_id uuid not null references auth.users(id),
  portal_id uuid not null references public.portals(id),
  narrative_structure numeric(4,2) not null check (narrative_structure between 0 and 8),
  technical_mastery numeric(4,2) not null check (technical_mastery between 0 and 6),
  originality_identity numeric(4,2) not null check (originality_identity between 0 and 6),
  world_coherence numeric(4,2) not null check (world_coherence between 0 and 5),
  characters_emotion numeric(4,2) not null check (characters_emotion between 0 and 5),
  reading_impact numeric(4,2) not null check (reading_impact between 0 and 5),
  submitted_at timestamptz not null default now(),
  unique(evaluator_id,portal_id),
  check (narrative_structure+technical_mastery+originality_identity+world_coherence+characters_emotion+reading_impact <= 35)
);
create table if not exists public.moderator_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('moderator','editor','admin')),
  created_at timestamptz not null default now()
);
create table if not exists public.security_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  risk_level text not null default 'info' check (risk_level in ('info','low','medium','high')),
  ip_hash text,
  user_agent_hash text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists votes_portal_status_idx on public.votes(portal_id,status);
create index if not exists security_events_actor_time_idx on public.security_events(actor_id,created_at desc);
create index if not exists testimonials_moderation_idx on public.testimonials(portal_id,moderation_status);

alter table public.authors enable row level security;
alter table public.works enable row level security;
alter table public.editions enable row level security;
alter table public.portals enable row level security;
alter table public.reader_profiles enable row level security;
alter table public.reader_verifications enable row level security;
alter table public.votes enable row level security;
alter table public.vote_history enable row level security;
alter table public.testimonials enable row level security;
alter table public.partners enable row level security;
alter table public.partner_scores enable row level security;
alter table public.editorial_scores enable row level security;
alter table public.moderator_roles enable row level security;
alter table public.security_events enable row level security;

create policy "public authors" on public.authors for select using (true);
create policy "public works" on public.works for select using (true);
create policy "public published editions" on public.editions for select using (publication_status='published');
create policy "public open portals" on public.portals for select using (public_status in ('open','closed'));
create policy "own profile read" on public.reader_profiles for select using (auth.uid()=user_id);
create policy "own profile update" on public.reader_profiles for update using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "own verification read" on public.reader_verifications for select using (auth.uid()=user_id);
create policy "own votes read" on public.votes for select using (auth.uid()=reader_id);
create policy "published testimonials read" on public.testimonials for select using (moderation_status='published');

create or replace function public.is_staff(uid uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from moderator_roles where user_id=uid); $$;
revoke all on function public.is_staff(uuid) from public;
grant execute on function public.is_staff(uuid) to authenticated, service_role;

create policy "staff verification access" on public.reader_verifications for all
using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));
create policy "staff moderation access" on public.testimonials for all
using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));
create policy "staff vote access" on public.votes for all
using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));
create policy "staff history read" on public.vote_history for select using (public.is_staff(auth.uid()));
create policy "staff security read" on public.security_events for select using (public.is_staff(auth.uid()));
create policy "staff editorial access" on public.editorial_scores for all
using (public.is_staff(auth.uid())) with check (public.is_staff(auth.uid()));

create or replace function public.consume_rate_limit(
  p_actor uuid, p_ip_hash text, p_user_agent_hash text, p_event text,
  p_window_seconds int default 600, p_limit int default 12
) returns boolean
language plpgsql security definer set search_path=public
as $$
declare recent_count int;
begin
  perform pg_advisory_xact_lock(hashtext(coalesce(p_actor::text,'')||coalesce(p_ip_hash,'')||p_event));
  select count(*) into recent_count from security_events
    where event_type=p_event
      and created_at > now() - make_interval(secs=>p_window_seconds)
      and (actor_id=p_actor or (p_ip_hash is not null and ip_hash=p_ip_hash));
  insert into security_events(actor_id,event_type,risk_level,ip_hash,user_agent_hash,payload)
    values(p_actor,p_event,case when recent_count>=p_limit then 'medium' else 'info' end,p_ip_hash,p_user_agent_hash,jsonb_build_object('allowed',recent_count<p_limit));
  return recent_count < p_limit;
end $$;
revoke all on function public.consume_rate_limit(uuid,text,text,text,int,int) from public, anon, authenticated;
grant execute on function public.consume_rate_limit(uuid,text,text,text,int,int) to service_role;

create or replace function public.cast_verified_vote(
  p_reader uuid, p_portal uuid, p_score smallint, p_event_id uuid,
  p_ip_hash text, p_user_agent_hash text
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_vote votes; v_previous smallint;
begin
  if p_score not between 1 and 5 then raise exception 'invalid_score'; end if;
  if not exists(select 1 from reader_verifications where user_id=p_reader and status='approved')
    then raise exception 'reader_not_verified'; end if;
  if not exists(select 1 from portals where id=p_portal and public_status='open')
    then raise exception 'portal_not_open'; end if;
  select score into v_previous from votes where reader_id=p_reader and portal_id=p_portal for update;
  insert into votes(reader_id,portal_id,score)
    values(p_reader,p_portal,p_score)
    on conflict(reader_id,portal_id) do update set score=excluded.score,updated_at=now()
    returning * into v_vote;
  insert into vote_history(vote_id,reader_id,portal_id,previous_score,new_score,event_id,ip_hash,user_agent_hash)
    values(v_vote.id,p_reader,p_portal,v_previous,p_score,p_event_id,p_ip_hash,p_user_agent_hash);
  return v_vote.id;
end $$;
revoke all on function public.cast_verified_vote(uuid,uuid,smallint,uuid,text,text) from public, anon, authenticated;
grant execute on function public.cast_verified_vote(uuid,uuid,smallint,uuid,text,text) to service_role;
