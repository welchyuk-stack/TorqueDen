-- ============================================================================
-- TorqueDen — live database schema (public schema only), pg_dump snapshot.
-- Recreate with: psql "<conn>" -f supabase/schema.sql
--
-- Applied migrations (supabase/migrations/):
--   0001_car_location · 0002_merge_mods_into_build · 0003_post_link_to_mod
--   0004_fuzz_car_locations · 0005_clubs · 0006_club_admin · 0007_reports_blocks
--   0008_club_pins_rules_archive · 0009_club_admins_bans (mods + member bans)
--
-- Not included: table data; the auth.users trigger for handle_new_user()
-- (recreate: CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
--  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user()); storage buckets.
-- ============================================================================

--
-- PostgreSQL database dump
--

\restrict tW6HVQ982r9gvqfkPOXNRuzVGx21WjjlVnIRRO94fKgCB9KAnDvfJmmGsN2dBmx

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: handle_new_club(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_club() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.club_members (club_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (club_id, user_id) do nothing;
  return new;
end; $$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'username',''), split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end; $$;


--
-- Name: is_banned(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_banned(club uuid, usr uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from club_bans b where b.club_id = club and b.user_id = usr);
$$;


--
-- Name: is_club_mod(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_club_mod(club uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (select 1 from clubs c where c.id = club and c.owner_id = auth.uid())
      or exists (select 1 from club_members m
                 where m.club_id = club and m.user_id = auth.uid() and m.role in ('owner','admin'));
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blocker_id uuid DEFAULT auth.uid() NOT NULL,
    blocked_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: build_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.build_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    car_id uuid NOT NULL,
    title text NOT NULL,
    body text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    silent boolean DEFAULT false NOT NULL,
    category text,
    linked_build_entry_id uuid
);


--
-- Name: car_specs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.car_specs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    car_id uuid NOT NULL,
    label text NOT NULL,
    value text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cars; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cars (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid DEFAULT auth.uid() NOT NULL,
    make text NOT NULL,
    model text NOT NULL,
    year integer,
    nickname text,
    color text,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    chassis_model text,
    photo_url text,
    latitude double precision,
    longitude double precision,
    location_name text
);


--
-- Name: club_bans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.club_bans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    club_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: club_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.club_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    club_id uuid NOT NULL,
    user_id uuid DEFAULT auth.uid() NOT NULL,
    role text DEFAULT 'member'::text NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: club_replies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.club_replies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    thread_id uuid NOT NULL,
    author_id uuid DEFAULT auth.uid() NOT NULL,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: club_threads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.club_threads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    club_id uuid NOT NULL,
    author_id uuid DEFAULT auth.uid() NOT NULL,
    title text NOT NULL,
    body text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_pinned boolean DEFAULT false NOT NULL
);


--
-- Name: clubs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clubs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    avatar_url text,
    owner_id uuid DEFAULT auth.uid() NOT NULL,
    is_public boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_locked boolean DEFAULT false NOT NULL,
    rules text,
    is_archived boolean DEFAULT false NOT NULL
);


--
-- Name: follows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.follows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    follower_id uuid NOT NULL,
    car_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: mods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    car_id uuid NOT NULL,
    category text DEFAULT 'Other'::text NOT NULL,
    name text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: post_comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    build_entry_id uuid NOT NULL,
    user_id uuid NOT NULL,
    parent_id uuid,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: post_likes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_likes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    build_entry_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: post_media; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_media (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    build_entry_id uuid NOT NULL,
    car_id uuid NOT NULL,
    url text NOT NULL,
    kind text DEFAULT 'image'::text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    username text NOT NULL,
    display_name text,
    avatar_url text,
    bio text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reporter_id uuid DEFAULT auth.uid() NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    reason text NOT NULL,
    note text,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: blocks blocks_blocker_id_blocked_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_blocker_id_blocked_id_key UNIQUE (blocker_id, blocked_id);


--
-- Name: blocks blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_pkey PRIMARY KEY (id);


--
-- Name: build_entries build_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_entries
    ADD CONSTRAINT build_entries_pkey PRIMARY KEY (id);


--
-- Name: car_specs car_specs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.car_specs
    ADD CONSTRAINT car_specs_pkey PRIMARY KEY (id);


--
-- Name: cars cars_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cars
    ADD CONSTRAINT cars_pkey PRIMARY KEY (id);


--
-- Name: club_bans club_bans_club_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_bans
    ADD CONSTRAINT club_bans_club_id_user_id_key UNIQUE (club_id, user_id);


--
-- Name: club_bans club_bans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_bans
    ADD CONSTRAINT club_bans_pkey PRIMARY KEY (id);


--
-- Name: club_members club_members_club_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_members
    ADD CONSTRAINT club_members_club_id_user_id_key UNIQUE (club_id, user_id);


--
-- Name: club_members club_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_members
    ADD CONSTRAINT club_members_pkey PRIMARY KEY (id);


--
-- Name: club_replies club_replies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_replies
    ADD CONSTRAINT club_replies_pkey PRIMARY KEY (id);


--
-- Name: club_threads club_threads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_threads
    ADD CONSTRAINT club_threads_pkey PRIMARY KEY (id);


--
-- Name: clubs clubs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clubs
    ADD CONSTRAINT clubs_pkey PRIMARY KEY (id);


--
-- Name: follows follows_follower_id_car_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_follower_id_car_id_key UNIQUE (follower_id, car_id);


--
-- Name: follows follows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_pkey PRIMARY KEY (id);


--
-- Name: mods mods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mods
    ADD CONSTRAINT mods_pkey PRIMARY KEY (id);


--
-- Name: post_comments post_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT post_comments_pkey PRIMARY KEY (id);


--
-- Name: post_likes post_likes_build_entry_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT post_likes_build_entry_id_user_id_key UNIQUE (build_entry_id, user_id);


--
-- Name: post_likes post_likes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT post_likes_pkey PRIMARY KEY (id);


--
-- Name: post_media post_media_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_media
    ADD CONSTRAINT post_media_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_username_key UNIQUE (username);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: blocks_blocker_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX blocks_blocker_idx ON public.blocks USING btree (blocker_id);


--
-- Name: build_entries_car_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX build_entries_car_id_idx ON public.build_entries USING btree (car_id);


--
-- Name: car_specs_car_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX car_specs_car_id_idx ON public.car_specs USING btree (car_id);


--
-- Name: cars_lat_lng_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cars_lat_lng_idx ON public.cars USING btree (latitude, longitude);


--
-- Name: cars_owner_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cars_owner_id_idx ON public.cars USING btree (owner_id);


--
-- Name: club_bans_club_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX club_bans_club_idx ON public.club_bans USING btree (club_id);


--
-- Name: club_members_club_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX club_members_club_idx ON public.club_members USING btree (club_id);


--
-- Name: club_members_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX club_members_user_idx ON public.club_members USING btree (user_id);


--
-- Name: club_replies_thread_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX club_replies_thread_idx ON public.club_replies USING btree (thread_id, created_at);


--
-- Name: club_threads_club_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX club_threads_club_idx ON public.club_threads USING btree (club_id, created_at DESC);


--
-- Name: follows_car_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX follows_car_idx ON public.follows USING btree (car_id);


--
-- Name: follows_follower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX follows_follower_idx ON public.follows USING btree (follower_id);


--
-- Name: mods_car_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mods_car_id_idx ON public.mods USING btree (car_id);


--
-- Name: post_media_entry_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_media_entry_idx ON public.post_media USING btree (build_entry_id);


--
-- Name: clubs on_club_created; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_club_created AFTER INSERT ON public.clubs FOR EACH ROW EXECUTE FUNCTION public.handle_new_club();


--
-- Name: blocks blocks_blocked_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: blocks blocks_blocker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: build_entries build_entries_car_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_entries
    ADD CONSTRAINT build_entries_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(id) ON DELETE CASCADE;


--
-- Name: build_entries build_entries_linked_build_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.build_entries
    ADD CONSTRAINT build_entries_linked_build_entry_id_fkey FOREIGN KEY (linked_build_entry_id) REFERENCES public.build_entries(id) ON DELETE SET NULL;


--
-- Name: car_specs car_specs_car_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.car_specs
    ADD CONSTRAINT car_specs_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(id) ON DELETE CASCADE;


--
-- Name: cars cars_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cars
    ADD CONSTRAINT cars_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: club_bans club_bans_club_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_bans
    ADD CONSTRAINT club_bans_club_id_fkey FOREIGN KEY (club_id) REFERENCES public.clubs(id) ON DELETE CASCADE;


--
-- Name: club_bans club_bans_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_bans
    ADD CONSTRAINT club_bans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: club_members club_members_club_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_members
    ADD CONSTRAINT club_members_club_id_fkey FOREIGN KEY (club_id) REFERENCES public.clubs(id) ON DELETE CASCADE;


--
-- Name: club_members club_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_members
    ADD CONSTRAINT club_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: club_replies club_replies_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_replies
    ADD CONSTRAINT club_replies_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: club_replies club_replies_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_replies
    ADD CONSTRAINT club_replies_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES public.club_threads(id) ON DELETE CASCADE;


--
-- Name: club_threads club_threads_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_threads
    ADD CONSTRAINT club_threads_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: club_threads club_threads_club_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.club_threads
    ADD CONSTRAINT club_threads_club_id_fkey FOREIGN KEY (club_id) REFERENCES public.clubs(id) ON DELETE CASCADE;


--
-- Name: clubs clubs_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clubs
    ADD CONSTRAINT clubs_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: follows follows_car_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(id) ON DELETE CASCADE;


--
-- Name: follows follows_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mods mods_car_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mods
    ADD CONSTRAINT mods_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(id) ON DELETE CASCADE;


--
-- Name: post_comments post_comments_build_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT post_comments_build_entry_id_fkey FOREIGN KEY (build_entry_id) REFERENCES public.build_entries(id) ON DELETE CASCADE;


--
-- Name: post_comments post_comments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT post_comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.post_comments(id) ON DELETE CASCADE;


--
-- Name: post_comments post_comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_comments
    ADD CONSTRAINT post_comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: post_likes post_likes_build_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT post_likes_build_entry_id_fkey FOREIGN KEY (build_entry_id) REFERENCES public.build_entries(id) ON DELETE CASCADE;


--
-- Name: post_likes post_likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_likes
    ADD CONSTRAINT post_likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: post_media post_media_build_entry_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_media
    ADD CONSTRAINT post_media_build_entry_id_fkey FOREIGN KEY (build_entry_id) REFERENCES public.build_entries(id) ON DELETE CASCADE;


--
-- Name: post_media post_media_car_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_media
    ADD CONSTRAINT post_media_car_id_fkey FOREIGN KEY (car_id) REFERENCES public.cars(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: reports reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: club_replies Author or mod can delete reply; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Author or mod can delete reply" ON public.club_replies FOR DELETE USING (((author_id = auth.uid()) OR public.is_club_mod(( SELECT t.club_id
   FROM public.club_threads t
  WHERE (t.id = club_replies.thread_id)))));


--
-- Name: club_threads Author or mod can delete thread; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Author or mod can delete thread" ON public.club_threads FOR DELETE USING (((author_id = auth.uid()) OR public.is_club_mod(club_id)));


--
-- Name: club_replies Author or mod can update reply; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Author or mod can update reply" ON public.club_replies FOR UPDATE USING (((author_id = auth.uid()) OR public.is_club_mod(( SELECT t.club_id
   FROM public.club_threads t
  WHERE (t.id = club_replies.thread_id)))));


--
-- Name: club_threads Author or mod can update thread; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Author or mod can update thread" ON public.club_threads FOR UPDATE USING (((author_id = auth.uid()) OR public.is_club_mod(club_id)));


--
-- Name: cars Cars are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Cars are viewable by everyone" ON public.cars FOR SELECT USING (true);


--
-- Name: clubs Clubs are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Clubs are viewable by everyone" ON public.clubs FOR SELECT USING (true);


--
-- Name: reports File a report; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "File a report" ON public.reports FOR INSERT WITH CHECK ((reporter_id = auth.uid()));


--
-- Name: club_members Leave or mod can remove; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Leave or mod can remove" ON public.club_members FOR DELETE USING (((user_id = auth.uid()) OR public.is_club_mod(club_id)));


--
-- Name: blocks Manage own blocks (delete); Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Manage own blocks (delete)" ON public.blocks FOR DELETE USING ((blocker_id = auth.uid()));


--
-- Name: blocks Manage own blocks (insert); Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Manage own blocks (insert)" ON public.blocks FOR INSERT WITH CHECK ((blocker_id = auth.uid()));


--
-- Name: blocks Manage own blocks (select); Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Manage own blocks (select)" ON public.blocks FOR SELECT USING ((blocker_id = auth.uid()));


--
-- Name: club_members Members are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Members are viewable by everyone" ON public.club_members FOR SELECT USING (true);


--
-- Name: club_threads Members can post threads; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Members can post threads" ON public.club_threads FOR INSERT WITH CHECK (((author_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.club_members m
  WHERE ((m.club_id = club_threads.club_id) AND (m.user_id = auth.uid())))) AND (NOT public.is_banned(club_id, auth.uid())) AND (NOT (EXISTS ( SELECT 1
   FROM public.clubs c
  WHERE ((c.id = club_threads.club_id) AND c.is_archived)))) AND (public.is_club_mod(club_id) OR (NOT (EXISTS ( SELECT 1
   FROM public.clubs c
  WHERE ((c.id = club_threads.club_id) AND c.is_locked)))))));


--
-- Name: club_replies Members can reply; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Members can reply" ON public.club_replies FOR INSERT WITH CHECK (((author_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM (public.club_members m
     JOIN public.club_threads t ON ((t.club_id = m.club_id)))
  WHERE ((t.id = club_replies.thread_id) AND (m.user_id = auth.uid())))) AND (NOT public.is_banned(( SELECT t.club_id
   FROM public.club_threads t
  WHERE (t.id = club_replies.thread_id)), auth.uid())) AND (NOT (EXISTS ( SELECT 1
   FROM (public.club_threads t
     JOIN public.clubs c ON ((c.id = t.club_id)))
  WHERE ((t.id = club_replies.thread_id) AND c.is_archived)))) AND (public.is_club_mod(( SELECT t.club_id
   FROM public.club_threads t
  WHERE (t.id = club_replies.thread_id))) OR (NOT (EXISTS ( SELECT 1
   FROM (public.club_threads t
     JOIN public.clubs c ON ((c.id = t.club_id)))
  WHERE ((t.id = club_replies.thread_id) AND c.is_locked)))))));


--
-- Name: club_bans Mods add bans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Mods add bans" ON public.club_bans FOR INSERT WITH CHECK (public.is_club_mod(club_id));


--
-- Name: club_bans Mods remove bans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Mods remove bans" ON public.club_bans FOR DELETE USING (public.is_club_mod(club_id));


--
-- Name: club_bans Mods view bans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Mods view bans" ON public.club_bans FOR SELECT USING (public.is_club_mod(club_id));


--
-- Name: club_members Owner manages roles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owner manages roles" ON public.club_members FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.clubs c
  WHERE ((c.id = club_members.club_id) AND (c.owner_id = auth.uid())))));


--
-- Name: clubs Owners can delete their club; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owners can delete their club" ON public.clubs FOR DELETE USING ((owner_id = auth.uid()));


--
-- Name: cars Owners can delete their own cars; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owners can delete their own cars" ON public.cars FOR DELETE USING ((owner_id = auth.uid()));


--
-- Name: clubs Owners can update their club; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owners can update their club" ON public.clubs FOR UPDATE USING ((owner_id = auth.uid()));


--
-- Name: cars Owners can update their own cars; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owners can update their own cars" ON public.cars FOR UPDATE USING ((owner_id = auth.uid()));


--
-- Name: profiles Profiles are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);


--
-- Name: club_replies Replies are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Replies are viewable by everyone" ON public.club_replies FOR SELECT USING (true);


--
-- Name: reports See own reports; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "See own reports" ON public.reports FOR SELECT USING ((reporter_id = auth.uid()));


--
-- Name: club_threads Threads are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Threads are viewable by everyone" ON public.club_threads FOR SELECT USING (true);


--
-- Name: cars Users can add cars to their own garage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can add cars to their own garage" ON public.cars FOR INSERT WITH CHECK ((owner_id = auth.uid()));


--
-- Name: clubs Users can create clubs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can create clubs" ON public.clubs FOR INSERT WITH CHECK ((owner_id = auth.uid()));


--
-- Name: profiles Users can insert their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT WITH CHECK ((auth.uid() = id));


--
-- Name: club_members Users can join clubs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can join clubs" ON public.club_members FOR INSERT WITH CHECK (((user_id = auth.uid()) AND (NOT public.is_banned(club_id, auth.uid()))));


--
-- Name: profiles Users can update their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING ((auth.uid() = id));


--
-- Name: blocks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

--
-- Name: build_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.build_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: car_specs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.car_specs ENABLE ROW LEVEL SECURITY;

--
-- Name: cars; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cars ENABLE ROW LEVEL SECURITY;

--
-- Name: club_bans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.club_bans ENABLE ROW LEVEL SECURITY;

--
-- Name: club_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.club_members ENABLE ROW LEVEL SECURITY;

--
-- Name: club_replies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.club_replies ENABLE ROW LEVEL SECURITY;

--
-- Name: club_threads; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.club_threads ENABLE ROW LEVEL SECURITY;

--
-- Name: clubs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;

--
-- Name: follows; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

--
-- Name: post_comments manage own comments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "manage own comments" ON public.post_comments TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: follows manage own follows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "manage own follows" ON public.follows TO authenticated USING ((follower_id = auth.uid())) WITH CHECK ((follower_id = auth.uid()));


--
-- Name: post_likes manage own likes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "manage own likes" ON public.post_likes TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: mods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mods ENABLE ROW LEVEL SECURITY;

--
-- Name: build_entries owner writes build_entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner writes build_entries" ON public.build_entries TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = build_entries.car_id) AND (c.owner_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = build_entries.car_id) AND (c.owner_id = auth.uid())))));


--
-- Name: car_specs owner writes car_specs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner writes car_specs" ON public.car_specs TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = car_specs.car_id) AND (c.owner_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = car_specs.car_id) AND (c.owner_id = auth.uid())))));


--
-- Name: mods owner writes mods; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner writes mods" ON public.mods TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = mods.car_id) AND (c.owner_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = mods.car_id) AND (c.owner_id = auth.uid())))));


--
-- Name: post_media owner writes post_media; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "owner writes post_media" ON public.post_media TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = post_media.car_id) AND (c.owner_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.cars c
  WHERE ((c.id = post_media.car_id) AND (c.owner_id = auth.uid())))));


--
-- Name: post_comments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.post_comments ENABLE ROW LEVEL SECURITY;

--
-- Name: post_likes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

--
-- Name: post_media; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.post_media ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: build_entries read build_entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read build_entries" ON public.build_entries FOR SELECT USING (true);


--
-- Name: car_specs read car_specs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read car_specs" ON public.car_specs FOR SELECT USING (true);


--
-- Name: follows read follows; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read follows" ON public.follows FOR SELECT USING (true);


--
-- Name: mods read mods; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read mods" ON public.mods FOR SELECT USING (true);


--
-- Name: post_comments read post_comments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read post_comments" ON public.post_comments FOR SELECT USING (true);


--
-- Name: post_likes read post_likes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read post_likes" ON public.post_likes FOR SELECT USING (true);


--
-- Name: post_media read post_media; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "read post_media" ON public.post_media FOR SELECT USING (true);


--
-- Name: reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION handle_new_club(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_new_club() TO anon;
GRANT ALL ON FUNCTION public.handle_new_club() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_club() TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- Name: FUNCTION is_banned(club uuid, usr uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.is_banned(club uuid, usr uuid) TO anon;
GRANT ALL ON FUNCTION public.is_banned(club uuid, usr uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_banned(club uuid, usr uuid) TO service_role;


--
-- Name: FUNCTION is_club_mod(club uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.is_club_mod(club uuid) TO anon;
GRANT ALL ON FUNCTION public.is_club_mod(club uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_club_mod(club uuid) TO service_role;


--
-- Name: TABLE blocks; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.blocks TO anon;
GRANT ALL ON TABLE public.blocks TO authenticated;
GRANT ALL ON TABLE public.blocks TO service_role;


--
-- Name: TABLE build_entries; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.build_entries TO anon;
GRANT ALL ON TABLE public.build_entries TO authenticated;
GRANT ALL ON TABLE public.build_entries TO service_role;


--
-- Name: TABLE car_specs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.car_specs TO anon;
GRANT ALL ON TABLE public.car_specs TO authenticated;
GRANT ALL ON TABLE public.car_specs TO service_role;


--
-- Name: TABLE cars; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cars TO anon;
GRANT ALL ON TABLE public.cars TO authenticated;
GRANT ALL ON TABLE public.cars TO service_role;


--
-- Name: TABLE club_bans; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.club_bans TO anon;
GRANT ALL ON TABLE public.club_bans TO authenticated;
GRANT ALL ON TABLE public.club_bans TO service_role;


--
-- Name: TABLE club_members; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.club_members TO anon;
GRANT ALL ON TABLE public.club_members TO authenticated;
GRANT ALL ON TABLE public.club_members TO service_role;


--
-- Name: TABLE club_replies; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.club_replies TO anon;
GRANT ALL ON TABLE public.club_replies TO authenticated;
GRANT ALL ON TABLE public.club_replies TO service_role;


--
-- Name: TABLE club_threads; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.club_threads TO anon;
GRANT ALL ON TABLE public.club_threads TO authenticated;
GRANT ALL ON TABLE public.club_threads TO service_role;


--
-- Name: TABLE clubs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.clubs TO anon;
GRANT ALL ON TABLE public.clubs TO authenticated;
GRANT ALL ON TABLE public.clubs TO service_role;


--
-- Name: TABLE follows; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.follows TO anon;
GRANT ALL ON TABLE public.follows TO authenticated;
GRANT ALL ON TABLE public.follows TO service_role;


--
-- Name: TABLE mods; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.mods TO anon;
GRANT ALL ON TABLE public.mods TO authenticated;
GRANT ALL ON TABLE public.mods TO service_role;


--
-- Name: TABLE post_comments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.post_comments TO anon;
GRANT ALL ON TABLE public.post_comments TO authenticated;
GRANT ALL ON TABLE public.post_comments TO service_role;


--
-- Name: TABLE post_likes; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.post_likes TO anon;
GRANT ALL ON TABLE public.post_likes TO authenticated;
GRANT ALL ON TABLE public.post_likes TO service_role;


--
-- Name: TABLE post_media; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.post_media TO anon;
GRANT ALL ON TABLE public.post_media TO authenticated;
GRANT ALL ON TABLE public.post_media TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profiles TO anon;
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;


--
-- Name: TABLE reports; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reports TO anon;
GRANT ALL ON TABLE public.reports TO authenticated;
GRANT ALL ON TABLE public.reports TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict tW6HVQ982r9gvqfkPOXNRuzVGx21WjjlVnIRRO94fKgCB9KAnDvfJmmGsN2dBmx

