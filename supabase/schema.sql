-- ============================================================================
-- TorqueDen — live database schema (public schema only)
--
-- Captured with `pg_dump --schema-only` from the production Supabase project
-- (Postgres 17.6). Source-of-truth snapshot of the DB structure.
--
-- To recreate on a fresh Supabase/Postgres database:
--     psql "<connection-string>" -f supabase/schema.sql
--
-- Applied migrations (see supabase/migrations/):
--   0001_car_location.sql          — latitude/longitude/location_name on cars.
--   0002_merge_mods_into_build.sql — category on build_entries; mods folded in.
--   0003_post_link_to_mod.sql      — linked_build_entry_id on build_entries so
--                                    a post can link to a mod in the build list.
--   0004_fuzz_car_locations.sql    — (data) coarsen car coords to a ~1 km grid
--                                    for privacy; new writes fuzzed client-side.
--
-- CAVEATS / not included:
--   * No data — structure only.
--   * The auth.users trigger that fires handle_new_user() is not exported here;
--     to reproduce profile auto-creation on signup, also run:
--         CREATE TRIGGER on_auth_user_created
--           AFTER INSERT ON auth.users
--           FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
--   * Storage buckets (e.g. car-photos) are dashboard config, not captured here.
-- ============================================================================

--
-- PostgreSQL database dump
--

\restrict Ohp9rotoZHqGqWJawDkPCKBPLkq6cLwsBA3QUAzk7fkW8bpYzQpm4pKzcFWgdlk

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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
-- Name: cars Cars are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Cars are viewable by everyone" ON public.cars FOR SELECT USING (true);


--
-- Name: cars Owners can delete their own cars; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owners can delete their own cars" ON public.cars FOR DELETE USING ((owner_id = auth.uid()));


--
-- Name: cars Owners can update their own cars; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Owners can update their own cars" ON public.cars FOR UPDATE USING ((owner_id = auth.uid()));


--
-- Name: profiles Profiles are viewable by everyone; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);


--
-- Name: cars Users can add cars to their own garage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can add cars to their own garage" ON public.cars FOR INSERT WITH CHECK ((owner_id = auth.uid()));


--
-- Name: profiles Users can insert their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT WITH CHECK ((auth.uid() = id));


--
-- Name: profiles Users can update their own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING ((auth.uid() = id));


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
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


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

\unrestrict Ohp9rotoZHqGqWJawDkPCKBPLkq6cLwsBA3QUAzk7fkW8bpYzQpm4pKzcFWgdlk

