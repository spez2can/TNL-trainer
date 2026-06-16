-- ════════════════════════════════════════════════════
-- TNL Pitch Trainer — Supabase Database Setup
-- Paste this entire file into the Supabase SQL Editor
-- and click Run.
-- ════════════════════════════════════════════════════

-- 1. PROFILES TABLE (one row per user)
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  name text not null,
  email text,
  role text not null default 'singer'  -- 'singer' or 'admin'
);

-- 2. EXERCISES TABLE (created by director)
create table public.exercises (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now(),
  created_by uuid references public.profiles(id) on delete set null,
  name text not null,
  voice_part text not null default 'All',
  channel text not null default 'mix',  -- 'mix', 'left', or 'right'
  notes text,
  audio_url text not null,
  segments jsonb not null default '[]'  -- array of segment objects
);

-- 3. ATTEMPTS TABLE (one row per singer practice session)
create table public.attempts (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  exercise_id uuid references public.exercises(id) on delete cascade not null,
  segment_id text not null,            -- matches segment id from exercises.segments
  overall integer not null,
  pitch_acc integer not null,
  rhythm_score integer,
  avg_timing_ms integer,
  timing_devs jsonb                    -- array of per-note timing deviations
);

-- ── SECURITY (Row Level Security) ────────────────────────────
-- This makes sure singers can only see their own data,
-- and only admins can create exercises.

alter table public.profiles enable row level security;
alter table public.exercises enable row level security;
alter table public.attempts enable row level security;

-- Profiles: users can read/update their own profile
create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

create policy "Profiles are insertable by owner"
  on public.profiles for insert with check (auth.uid() = id);

-- Exercises: everyone logged in can read; only admins can write
create policy "Anyone logged in can view exercises"
  on public.exercises for select using (auth.role() = 'authenticated');

create policy "Only admins can insert exercises"
  on public.exercises for insert with check (
    (select role from public.profiles where id = auth.uid()) = 'admin'
  );

create policy "Only admins can delete exercises"
  on public.exercises for delete using (
    (select role from public.profiles where id = auth.uid()) = 'admin'
  );

-- Attempts: singers see own; admins see all
create policy "Singers see own attempts"
  on public.attempts for select using (
    auth.uid() = user_id
    or (select role from public.profiles where id = auth.uid()) = 'admin'
  );

create policy "Anyone logged in can insert attempts"
  on public.attempts for insert with check (auth.uid() = user_id);

-- ── STORAGE BUCKET ───────────────────────────────────────────
-- Creates the storage bucket for audio files.
insert into storage.buckets (id, name, public)
  values ('audio', 'audio', true);

create policy "Anyone logged in can upload audio"
  on storage.objects for insert with check (
    bucket_id = 'audio' and auth.role() = 'authenticated'
  );

create policy "Audio files are publicly readable"
  on storage.objects for select using (bucket_id = 'audio');

create policy "Admins can delete audio"
  on storage.objects for delete using (
    bucket_id = 'audio'
    and (select role from public.profiles where id = auth.uid()) = 'admin'
  );
