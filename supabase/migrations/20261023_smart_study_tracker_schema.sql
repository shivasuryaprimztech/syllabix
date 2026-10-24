-- ============================================================================
-- SMART STUDY TRACKER — SUPABASE POSTGRESQL MIGRATION SCRIPT
-- ============================================================================
-- This script sets up:
-- 1. Profiles & Role Management (with Security Definer function is_admin)
-- 2. Semester, Subject, Unit, Topic, Subtopic Hierarchy
-- 3. Individual Student Progress Tracking (with uniqueness constraints)
-- 4. Shared Study Resources & Moderation
-- 5. Row Level Security (RLS) policies enforcing student isolation & admin privilege
-- 6. Supabase Storage Bucket setup for 'study-materials'
-- 7. Synthetic Seed Data for 2 full Semesters, Subjects, Units & Topics
-- ============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------------------
-- 1. PROFILES & ROLES
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    student_id TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    roll_number TEXT UNIQUE NOT NULL,
    department TEXT NOT NULL DEFAULT 'Computer Science & Engineering',
    semester_enrolled INTEGER NOT NULL DEFAULT 4,
    account_status TEXT NOT NULL DEFAULT 'active' CHECK (account_status IN ('active', 'suspended', 'pending')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW())
);

CREATE TABLE IF NOT EXISTS public.user_roles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'admin')),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW())
);

-- Index for fast roll number lookups
CREATE INDEX IF NOT EXISTS idx_profiles_roll_number ON public.profiles(roll_number);

-- Security Definer function to check if current user is an admin without RLS recursion
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.user_roles 
        WHERE user_id = user_uuid AND role = 'admin'
    );
$$;

-- ----------------------------------------------------------------------------
-- 2. SYLLABUS HIERARCHY
-- ----------------------------------------------------------------------------

-- Semesters
CREATE TABLE IF NOT EXISTS public.semesters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    semester_number INTEGER UNIQUE NOT NULL,
    title TEXT NOT NULL,
    academic_year TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW())
);

-- Subjects
CREATE TABLE IF NOT EXISTS public.subjects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    semester_id UUID NOT NULL REFERENCES public.semesters(id) ON DELETE CASCADE,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    credits INTEGER NOT NULL DEFAULT 4,
    color_code TEXT NOT NULL DEFAULT '#3B82F6',
    display_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW())
);
CREATE INDEX IF NOT EXISTS idx_subjects_semester_id ON public.subjects(semester_id);

-- Units
CREATE TABLE IF NOT EXISTS public.units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
    unit_number INTEGER NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW()),
    CONSTRAINT unique_subject_unit UNIQUE(subject_id, unit_number)
);
CREATE INDEX IF NOT EXISTS idx_units_subject_id ON public.units(subject_id);

-- Topics
CREATE TABLE IF NOT EXISTS public.topics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_id UUID NOT NULL REFERENCES public.units(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    is_important BOOLEAN NOT NULL DEFAULT FALSE,
    estimated_hours NUMERIC(4,1) NOT NULL DEFAULT 2.0,
    display_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW())
);
CREATE INDEX IF NOT EXISTS idx_topics_unit_id ON public.topics(unit_id);
CREATE INDEX IF NOT EXISTS idx_topics_is_important ON public.topics(is_important);

-- Subtopics
CREATE TABLE IF NOT EXISTS public.subtopics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic_id UUID NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW())
);
CREATE INDEX IF NOT EXISTS idx_subtopics_topic_id ON public.subtopics(topic_id);

-- ----------------------------------------------------------------------------
-- 3. INDIVIDUAL STUDENT PROGRESS TRACKER
-- ----------------------------------------------------------------------------
-- Tracks checked state per student per topic / subtopic
-- Unique constraint guarantees no duplicates per student per item
CREATE TABLE IF NOT EXISTS public.topic_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    item_id UUID NOT NULL,
    item_type TEXT NOT NULL CHECK (item_type IN ('topic', 'subtopic')),
    is_completed BOOLEAN NOT NULL DEFAULT TRUE,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW()),
    CONSTRAINT unique_user_item UNIQUE (user_id, item_id, item_type)
);
CREATE INDEX IF NOT EXISTS idx_progress_user ON public.topic_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_progress_item ON public.topic_progress(item_id, item_type);

-- ----------------------------------------------------------------------------
-- 4. SHARED STUDY RESOURCES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    resource_type TEXT NOT NULL CHECK (resource_type IN ('pdf', 'document', 'youtube', 'url')),
    semester_id UUID NOT NULL REFERENCES public.semesters(id) ON DELETE CASCADE,
    subject_id UUID NOT NULL REFERENCES public.subjects(id) ON DELETE CASCADE,
    unit_id UUID REFERENCES public.units(id) ON DELETE SET NULL,
    topic_id UUID REFERENCES public.topics(id) ON DELETE SET NULL,
    uploader_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    uploader_name TEXT NOT NULL,
    uploader_roll TEXT NOT NULL,
    file_path TEXT,
    file_size_bytes BIGINT,
    file_mime_type TEXT,
    external_url TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    is_exam_prep BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT TIMEZONE('utc', NOW())
);
CREATE INDEX IF NOT EXISTS idx_resources_subject ON public.resources(subject_id);
CREATE INDEX IF NOT EXISTS idx_resources_status ON public.resources(status);
CREATE INDEX IF NOT EXISTS idx_resources_uploader ON public.resources(uploader_id);

-- ----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.semesters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subtopics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topic_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER helper: keep search_path fixed and prevent public execution.
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.user_roles
        WHERE user_id = user_uuid
          AND role = 'admin'
    );
$$;
REVOKE ALL ON FUNCTION public.is_admin(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin(UUID) TO authenticated;

-- Profiles: authenticated users may read the directory; users can insert/update
-- only their own profile. Do not allow clients to change id to another user.
DROP POLICY IF EXISTS "Authenticated users can read all student directory profiles" ON public.profiles;
CREATE POLICY "Authenticated users can read student directory profiles"
ON public.profiles FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
ON public.profiles FOR INSERT TO authenticated
WITH CHECK ((SELECT auth.uid()) = id);

DROP POLICY IF EXISTS "Users can update only their own profile" ON public.profiles;
CREATE POLICY "Users can update only their own profile"
ON public.profiles FOR UPDATE TO authenticated
USING ((SELECT auth.uid()) = id)
WITH CHECK ((SELECT auth.uid()) = id);

-- Roles: users can read their own role; only an existing admin can manage roles.
-- Bootstrap the first admin only through the Supabase SQL Editor / trusted admin process.
DROP POLICY IF EXISTS "Users can read their own role" ON public.user_roles;
CREATE POLICY "Users can read their own role"
ON public.user_roles FOR SELECT TO authenticated
USING ((SELECT auth.uid()) = user_id OR public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Only admins can insert or update user roles" ON public.user_roles;
DROP POLICY IF EXISTS "Admins can insert roles" ON public.user_roles;
CREATE POLICY "Admins can insert roles"
ON public.user_roles FOR INSERT TO authenticated
WITH CHECK (public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Admins can update roles" ON public.user_roles;
CREATE POLICY "Admins can update roles"
ON public.user_roles FOR UPDATE TO authenticated
USING (public.is_admin((SELECT auth.uid())))
WITH CHECK (public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Admins can delete roles" ON public.user_roles;
CREATE POLICY "Admins can delete roles"
ON public.user_roles FOR DELETE TO authenticated
USING (public.is_admin((SELECT auth.uid())));

-- Shared syllabus: authenticated read, admins write.
DROP POLICY IF EXISTS "Anyone can read semesters" ON public.semesters;
CREATE POLICY "Authenticated users can read semesters"
ON public.semesters FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admins can manage semesters" ON public.semesters;
CREATE POLICY "Admins can manage semesters"
ON public.semesters FOR ALL TO authenticated
USING (public.is_admin((SELECT auth.uid())))
WITH CHECK (public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Anyone can read subjects" ON public.subjects;
CREATE POLICY "Authenticated users can read subjects"
ON public.subjects FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admins can manage subjects" ON public.subjects;
CREATE POLICY "Admins can manage subjects"
ON public.subjects FOR ALL TO authenticated
USING (public.is_admin((SELECT auth.uid())))
WITH CHECK (public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Anyone can read units" ON public.units;
CREATE POLICY "Authenticated users can read units"
ON public.units FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admins can manage units" ON public.units;
CREATE POLICY "Admins can manage units"
ON public.units FOR ALL TO authenticated
USING (public.is_admin((SELECT auth.uid())))
WITH CHECK (public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Anyone can read topics" ON public.topics;
CREATE POLICY "Authenticated users can read topics"
ON public.topics FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admins can manage topics" ON public.topics;
CREATE POLICY "Admins can manage topics"
ON public.topics FOR ALL TO authenticated
USING (public.is_admin((SELECT auth.uid())))
WITH CHECK (public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Anyone can read subtopics" ON public.subtopics;
CREATE POLICY "Authenticated users can read subtopics"
ON public.subtopics FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admins can manage subtopics" ON public.subtopics;
CREATE POLICY "Admins can manage subtopics"
ON public.subtopics FOR ALL TO authenticated
USING (public.is_admin((SELECT auth.uid())))
WITH CHECK (public.is_admin((SELECT auth.uid())));

-- Student progress: users may access only their own rows.
DROP POLICY IF EXISTS "Students can only read their own progress" ON public.topic_progress;
CREATE POLICY "Students can only read their own progress"
ON public.topic_progress FOR SELECT TO authenticated
USING ((SELECT auth.uid()) = user_id OR public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Students can insert only their own progress" ON public.topic_progress;
CREATE POLICY "Students can insert only their own progress"
ON public.topic_progress FOR INSERT TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Students can update only their own progress" ON public.topic_progress;
CREATE POLICY "Students can update only their own progress"
ON public.topic_progress FOR UPDATE TO authenticated
USING ((SELECT auth.uid()) = user_id)
WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Students can delete only their own progress" ON public.topic_progress;
CREATE POLICY "Students can delete only their own progress"
ON public.topic_progress FOR DELETE TO authenticated
USING ((SELECT auth.uid()) = user_id);

-- Resources: students submit pending resources; only admins can approve/reject.
DROP POLICY IF EXISTS "Anyone can read approved resources" ON public.resources;
CREATE POLICY "Read approved resources or own submissions"
ON public.resources FOR SELECT TO authenticated
USING (status = 'approved' OR (SELECT auth.uid()) = uploader_id OR public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Students can insert their own resources" ON public.resources;
CREATE POLICY "Students can insert their own resources"
ON public.resources FOR INSERT TO authenticated
WITH CHECK (
    (SELECT auth.uid()) = uploader_id
    AND status = 'pending'
);

DROP POLICY IF EXISTS "Students can edit pending resources; Admins can edit any" ON public.resources;
CREATE POLICY "Owners can edit pending resources; admins can manage resources"
ON public.resources FOR UPDATE TO authenticated
USING (((SELECT auth.uid()) = uploader_id AND status = 'pending') OR public.is_admin((SELECT auth.uid())))
WITH CHECK (((SELECT auth.uid()) = uploader_id AND status = 'pending') OR public.is_admin((SELECT auth.uid())));

DROP POLICY IF EXISTS "Students can delete own resources; Admins can delete any" ON public.resources;
CREATE POLICY "Owners or admins can delete resources"
ON public.resources FOR DELETE TO authenticated
USING ((SELECT auth.uid()) = uploader_id OR public.is_admin((SELECT auth.uid())));

-- ----------------------------------------------------------------------------
-- 6. STORAGE BUCKET CONFIGURATION
-- ----------------------------------------------------------------------------
-- Private bucket: files require authorized access. Use authenticated users and
-- per-user folder paths such as <auth.uid()>/filename.pdf in the app.
INSERT INTO storage.buckets (id, name, public)
VALUES ('study-materials', 'study-materials', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Public read study materials" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users upload study materials" ON storage.objects;
DROP POLICY IF EXISTS "Owners or Admin delete study materials" ON storage.objects;
DROP POLICY IF EXISTS "Users read study materials" ON storage.objects;
DROP POLICY IF EXISTS "Users upload own study materials" ON storage.objects;
DROP POLICY IF EXISTS "Users update own study materials" ON storage.objects;
DROP POLICY IF EXISTS "Users delete own study materials" ON storage.objects;

CREATE POLICY "Users read study materials"
ON storage.objects FOR SELECT TO authenticated
USING (
    bucket_id = 'study-materials'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR public.is_admin((SELECT auth.uid()))
    )
);

CREATE POLICY "Users upload own study materials"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'study-materials'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

CREATE POLICY "Users update own study materials"
ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id = 'study-materials'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR public.is_admin((SELECT auth.uid()))
    )
)
WITH CHECK (
    bucket_id = 'study-materials'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR public.is_admin((SELECT auth.uid()))
    )
);

CREATE POLICY "Users delete own study materials"
ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'study-materials'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR public.is_admin((SELECT auth.uid()))
    )
);

-- ----------------------------------------------------------------------------
-- 7. SYLLABUS SEED DATA — generated from the supplied academics JSON
-- Hierarchy: subject -> chapter (stored as unit) -> topic -> subtopic
-- Stable UUIDs make this seed section safe to re-run.
-- ----------------------------------------------------------------------------

INSERT INTO public.semesters (id, semester_number, title, academic_year, display_order, is_active)
VALUES ('4d9dfbc8-7a8b-5ae2-8657-492113d879c8', 1, 'Academic Syllabus', '2026-2027', 1, TRUE)
ON CONFLICT (id) DO NOTHING;

-- Subject: Java Programming
INSERT INTO public.subjects (id, semester_id, code, name, credits, color_code, display_order)
VALUES ('1ec14423-0d19-5c80-b449-4ecdc4ff2595', '4d9dfbc8-7a8b-5ae2-8657-492113d879c8', 'JAVA', 'Java Programming', 4, '#2563EB', 1)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Foundations of OOP and Java
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('e67e66e2-ca0b-5125-92c4-1d512e234222', '1ec14423-0d19-5c80-b449-4ecdc4ff2595', 1, 'Foundations of OOP and Java', 'Object-oriented principles and Java language foundations.', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('d3500677-a016-5dcf-9ed4-ee48b57af8ae', 'e67e66e2-ca0b-5125-92c4-1d512e234222', 'Principles of OOP', 'Core object-oriented programming principles.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('c371e4c7-07df-55c5-ac75-0d3c334d7310', 'd3500677-a016-5dcf-9ed4-ee48b57af8ae', 'Principles of OOP', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('07227fbb-78a9-53ee-8a9e-a6289a68d04b', 'e67e66e2-ca0b-5125-92c4-1d512e234222', 'Java Fundamentals', 'Development kit, types, operators, and control flow.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('611fe3bb-e3af-5263-bc67-e662be98cbb7', '07227fbb-78a9-53ee-8a9e-a6289a68d04b', 'Java Development Kit (JDK)', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0720244a-5997-5161-87b5-1f23b7b64504', '07227fbb-78a9-53ee-8a9e-a6289a68d04b', 'Data Types', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('eafcd162-12e1-56fd-b644-3d52fed0f2a4', '07227fbb-78a9-53ee-8a9e-a6289a68d04b', 'Variables', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('644324fc-b1b9-5731-a039-962bbe0e40d7', '07227fbb-78a9-53ee-8a9e-a6289a68d04b', 'Arrays', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('06c8aa08-ad58-57aa-b1a1-ec85ee61a93a', '07227fbb-78a9-53ee-8a9e-a6289a68d04b', 'Operators', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('97177e00-0d1e-5dd8-bcad-6c973501be9e', '07227fbb-78a9-53ee-8a9e-a6289a68d04b', 'Control Statements', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('3ec0bb60-bc2f-5d94-a4b8-634ddaec335a', 'e67e66e2-ca0b-5125-92c4-1d512e234222', 'Classes, Objects and Inheritance', 'Class-based programming and inheritance.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e09fb277-8e3f-56de-bf46-ec2003c827eb', '3ec0bb60-bc2f-5d94-a4b8-634ddaec335a', 'Classes and Objects', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d5a82682-503d-5fdc-8f0c-0623edddaf12', '3ec0bb60-bc2f-5d94-a4b8-634ddaec335a', 'Constructors', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('aa3b16ae-fe2f-54da-a1b8-c9f8436bddc4', '3ec0bb60-bc2f-5d94-a4b8-634ddaec335a', 'Method Overriding', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4a7c3c47-c124-552d-9720-1b895f0c6697', '3ec0bb60-bc2f-5d94-a4b8-634ddaec335a', 'Access Specifiers', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0a5390eb-337d-5dac-a239-33885c6f4e0e', '3ec0bb60-bc2f-5d94-a4b8-634ddaec335a', 'Static Members', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6805a4df-609e-5ab2-80f4-1731394cf87c', '3ec0bb60-bc2f-5d94-a4b8-634ddaec335a', 'Inheritance', 6)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Java Conceptual Foundations and Capabilities
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('2f3bf6e4-3eb0-5764-9058-94b20b877860', '1ec14423-0d19-5c80-b449-4ecdc4ff2595', 2, 'Java Conceptual Foundations and Capabilities', 'Language features for modularity, error handling, concurrency, and modern Java constructs.', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('777e337f-8a9e-546b-ba50-3ebea0b019a2', '2f3bf6e4-3eb0-5764-9058-94b20b877860', 'Packages and Interfaces', 'Organizing code and defining interfaces.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('3a3573e3-cfbc-5e50-973b-d473e2f9fd96', '777e337f-8a9e-546b-ba50-3ebea0b019a2', 'Packages', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('70e1285f-921f-50e8-8749-140765f7eb9c', '777e337f-8a9e-546b-ba50-3ebea0b019a2', 'Interfaces', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('aa00d109-7b9e-5a61-8ad7-10598d449b44', '2f3bf6e4-3eb0-5764-9058-94b20b877860', 'Exception Handling', 'Handling exceptional program conditions.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9f6fbe4a-f5ea-53c1-b675-c3d39dfa16b1', 'aa00d109-7b9e-5a61-8ad7-10598d449b44', 'Exception Handling', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ece3120b-a8d4-5cf9-8763-77380fdae082', 'aa00d109-7b9e-5a61-8ad7-10598d449b44', 'Creation of User-Defined Exceptions', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('021f6e4a-0745-56ca-923d-122d071be82f', '2f3bf6e4-3eb0-5764-9058-94b20b877860', 'Multithreaded Programming', 'Concurrent execution with threads.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5536b72a-4f96-5ab2-bd67-9afb24f8a9ad', '021f6e4a-0745-56ca-923d-122d071be82f', 'Multithreaded Programming', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f87980fe-05f1-52ce-87eb-0a5e721b1848', '021f6e4a-0745-56ca-923d-122d071be82f', 'Multiple Threads', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('47031dbd-b1de-587f-bf0f-afdb57264b89', '2f3bf6e4-3eb0-5764-9058-94b20b877860', 'Advanced Language Features', 'Additional Java language capabilities.', FALSE, 2.0, 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('91a9fdc6-f527-5c5d-a23f-e2508d22d64a', '47031dbd-b1de-587f-bf0f-afdb57264b89', 'Enumerations', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('2ce38574-1c3d-5d5f-8d84-12a8c379e46d', '47031dbd-b1de-587f-bf0f-afdb57264b89', 'Autoboxing', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('62c7ea57-87cf-5086-8231-ce009ed8e301', '47031dbd-b1de-587f-bf0f-afdb57264b89', 'Annotations', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7dc67c0f-1115-553a-aee4-13a26a35d7f0', '47031dbd-b1de-587f-bf0f-afdb57264b89', 'Generics', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9fc6d894-9b67-5818-ac39-7ed0f4b7ef9c', '47031dbd-b1de-587f-bf0f-afdb57264b89', 'Lambda Expressions', 5)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Java Core Libraries
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('deaeb495-92d4-54ae-9d90-5a7ecd7eabf7', '1ec14423-0d19-5c80-b449-4ecdc4ff2595', 3, 'Java Core Libraries', 'String processing, standard libraries, event handling, and AWT.', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('f9d4d077-5474-52f3-8100-1fbc8678eea4', 'deaeb495-92d4-54ae-9d90-5a7ecd7eabf7', 'String Handling', 'Working with strings.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('047651d5-bcd2-5288-b965-6ad5bd28cf1b', 'f9d4d077-5474-52f3-8100-1fbc8678eea4', 'String Handling', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('03464414-fb4f-5efb-a537-9d1805a40a89', 'deaeb495-92d4-54ae-9d90-5a7ecd7eabf7', 'Core Packages and Utility Classes', 'Core Java packages and utilities.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ca16de20-bd69-559d-95c8-e905beff13f0', '03464414-fb4f-5efb-a537-9d1805a40a89', 'java.lang', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('00a28766-fc0c-5c1b-bafd-c73c84221ecf', '03464414-fb4f-5efb-a537-9d1805a40a89', 'Utility Classes', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f77b806a-d285-50d9-99cb-270d1eefca47', '03464414-fb4f-5efb-a537-9d1805a40a89', 'java.io', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('abb27b11-00d0-5d09-8c16-ae46a156595d', 'deaeb495-92d4-54ae-9d90-5a7ecd7eabf7', 'Event Handling and AWT', 'Event handling and AWT user-interface controls.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('718d7020-f29b-5333-a367-b43ebd0fe26f', 'abb27b11-00d0-5d09-8c16-ae46a156595d', 'Event Handling', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e4bd28fe-0ce1-5d3b-ab99-f4e9c712dd13', 'abb27b11-00d0-5d09-8c16-ae46a156595d', 'Working with AWT Controls', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9ca5c065-1945-54f8-bc43-2ce15ecd6ac8', 'abb27b11-00d0-5d09-8c16-ae46a156595d', 'Layout Managers', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: I/O and GUI Programming in Java
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('2333c134-7291-5931-b960-8c897664fcb0', '1ec14423-0d19-5c80-b449-4ecdc4ff2595', 4, 'I/O and GUI Programming in Java', 'Console input/output, file operations, and Swing interfaces.', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('672e8c39-21fd-5456-b08d-c51972f865a2', '2333c134-7291-5931-b960-8c897664fcb0', 'Console and File I/O', 'Reading and writing console input/output and files.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('a0475cfc-5291-5f6b-8676-fdbad9e4c26d', '672e8c39-21fd-5456-b08d-c51972f865a2', 'Reading and Writing Console I/O', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('471ee8d0-e805-52a7-953f-df167e1c5b43', '672e8c39-21fd-5456-b08d-c51972f865a2', 'Files', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('a870b528-5ad0-5e4d-b76f-e8571d493387', '672e8c39-21fd-5456-b08d-c51972f865a2', 'File I/O', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('21355e9f-d505-56e9-9f98-2f07daca9818', '2333c134-7291-5931-b960-8c897664fcb0', 'Swing and Menus', 'GUI programming using Swing and menus.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('53c5f784-b07a-54d9-99c5-70c43f1810f2', '21355e9f-d505-56e9-9f98-2f07daca9818', 'Swing', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d0c2148e-1004-5425-861f-5ef1df3d14ae', '21355e9f-d505-56e9-9f98-2f07daca9818', 'Menus', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4a2bd65b-07e0-5902-908b-5dfe5647debb', '21355e9f-d505-56e9-9f98-2f07daca9818', 'Swing Application', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Database Connectivity Using Java
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('202a8e51-03e9-5542-ac61-5653d1c268e0', '1ec14423-0d19-5c80-b449-4ecdc4ff2595', 5, 'Database Connectivity Using Java', 'Connecting Java applications to databases through JDBC.', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('c9065103-6bfc-5d6d-8417-102d0d59f01b', '202a8e51-03e9-5542-ac61-5653d1c268e0', 'JDBC', 'JDBC drivers, APIs, and database operations.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0ab70206-f3bf-5e6f-85a8-a145c6aab2eb', 'c9065103-6bfc-5d6d-8417-102d0d59f01b', 'JDBC', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f4c54b6d-1262-5710-9e61-e15aa597d56d', 'c9065103-6bfc-5d6d-8417-102d0d59f01b', 'Types of JDBC Drivers', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('16b3ae47-cb2e-5973-9520-f4952f9fe578', 'c9065103-6bfc-5d6d-8417-102d0d59f01b', 'JDBC Packages', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7d316043-e6e0-5dc4-9b68-1140caa14ea4', 'c9065103-6bfc-5d6d-8417-102d0d59f01b', 'JDBC API and Driver', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('8fd4b455-d853-5986-9f5d-613071d0684e', 'c9065103-6bfc-5d6d-8417-102d0d59f01b', 'Associating the JDBC/ODBC Bridge with the Database', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e2501f4a-aadf-5858-8a47-d72ceca0b09d', 'c9065103-6bfc-5d6d-8417-102d0d59f01b', 'Database Connections', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('407eee7a-33f2-530e-95eb-266cc2ee42db', 'c9065103-6bfc-5d6d-8417-102d0d59f01b', 'Database Operations', 7)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Java Collection Framework
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('7335aeb4-024c-513f-a0b0-c585fff06bab', '1ec14423-0d19-5c80-b449-4ecdc4ff2595', 6, 'Java Collection Framework', 'Collections, regular expressions, maps, iterators, and generics.', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('3959a290-9a20-5eb8-a732-c2c53080a5f5', '7335aeb4-024c-513f-a0b0-c585fff06bab', 'Collections and Utilities', 'Java collection APIs and utility package.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('3574e2b4-be89-59f8-a4f9-d018f3a7e522', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'Collection Framework', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('da5116d5-e304-593f-9b8f-c705a39c909f', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'Regular Expressions (Regex)', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('df493168-489a-5cb6-b214-c18c38a07ec6', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'java.util Package', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('205688b5-f81d-5aab-82d2-845dddbd2567', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'Arrays and Collections', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('32e8a6c6-490e-579a-8195-512bccf2419c', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'Map Interfaces', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6d784e39-159e-5d13-911c-490f55299130', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'Iterators', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1c3fd334-f7d6-55b8-98f6-91dcf784bb81', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'Generics', 7)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('470af614-ed91-54b8-8a68-44b4fa5bfee8', '3959a290-9a20-5eb8-a732-c2c53080a5f5', 'ArrayList', 8)
ON CONFLICT (id) DO NOTHING;

-- Subject: Operating Systems
INSERT INTO public.subjects (id, semester_id, code, name, credits, color_code, display_order)
VALUES ('8ab461c7-7283-5341-ba28-7f45ec26fe53', '4d9dfbc8-7a8b-5ae2-8657-492113d879c8', 'OPERATING_SYSTEMS', 'Operating Systems', 4, '#7C3AED', 2)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Basics of Operating Systems
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('75909337-3703-5b5c-b152-4432bf528646', '8ab461c7-7283-5341-ba28-7f45ec26fe53', 1, 'Basics of Operating Systems', 'Operating-system history, types, structures, functions, and Unix/Linux.', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('6d72121f-3b41-5fc2-8fc7-c9c8f254ef09', '75909337-3703-5b5c-b152-4432bf528646', 'Operating-System Fundamentals', 'History, evolution, and core functions of operating systems.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('89366143-cc95-5459-b676-e17d2556a4f6', '6d72121f-3b41-5fc2-8fc7-c9c8f254ef09', 'History and Evolution of Operating Systems', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('3fca71f0-883f-53eb-b4ca-4ecd283674ef', '6d72121f-3b41-5fc2-8fc7-c9c8f254ef09', 'Types of Operating Systems', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('df227fea-b3e3-57ba-a8e4-8934b41546cb', '6d72121f-3b41-5fc2-8fc7-c9c8f254ef09', 'Operating-System Structures', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('83255dba-cf25-5b24-a58e-e2ba4227edc9', '6d72121f-3b41-5fc2-8fc7-c9c8f254ef09', 'Functions of Operating Systems', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4513c3f1-c022-5bac-88b6-7fa148828c96', '6d72121f-3b41-5fc2-8fc7-c9c8f254ef09', 'Challenges of Operating Systems', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('373966e5-16f7-53d1-ae7a-c815113c0384', '75909337-3703-5b5c-b152-4432bf528646', 'Unix and Linux Operating Systems', 'Introduction to Unix/Linux and basic practical work.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6419eeba-43d5-51ea-9f20-0a3cb1084dee', '373966e5-16f7-53d1-ae7a-c815113c0384', 'Unix and Linux Operating Systems', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('336db067-d5f3-5fc3-9e9a-5f178a5e0539', '373966e5-16f7-53d1-ae7a-c815113c0384', 'Installation of a Linux OS', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5f6cda1a-cf6c-511b-b267-f76c7ea73471', '373966e5-16f7-53d1-ae7a-c815113c0384', 'Linux Commands', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('8fda37e4-6af9-51bd-b9ae-f7dcc493cabf', '373966e5-16f7-53d1-ae7a-c815113c0384', 'Shell Scripting', 4)
ON CONFLICT (id) DO NOTHING;

-- Chapter: System Calls and Process Management
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('80657717-4c7d-5f09-957b-bd88155d7cb0', '8ab461c7-7283-5341-ba28-7f45ec26fe53', 2, 'System Calls and Process Management', 'System calls, process lifecycle, threads, and process control.', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('af3ba5b5-e424-5fc4-bbba-ff2a0d87bd72', '80657717-4c7d-5f09-957b-bd88155d7cb0', 'System Calls', 'System calls and their role in operating systems.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('165e1542-b500-52a6-8f1e-8a6def0bb4b7', 'af3ba5b5-e424-5fc4-bbba-ff2a0d87bd72', 'System Calls', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('7e0d4501-4e77-57cd-84d7-48cf5e183ff6', '80657717-4c7d-5f09-957b-bd88155d7cb0', 'Process Concepts and Lifecycle', 'Process representation, transitions, and context switching.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('2ae3ade4-6625-5f1f-a3f5-13ced212424e', '7e0d4501-4e77-57cd-84d7-48cf5e183ff6', 'Process Concepts and Lifecycle', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('92e31d6f-2224-518c-8831-5c235f7615ec', '7e0d4501-4e77-57cd-84d7-48cf5e183ff6', 'Process Control Block (PCB)', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1010b77d-66ba-5dbc-ba7c-eec1964d000b', '7e0d4501-4e77-57cd-84d7-48cf5e183ff6', 'Context Switching', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9f4b39d7-07d3-5418-98c6-90eaac9ef3e6', '7e0d4501-4e77-57cd-84d7-48cf5e183ff6', 'Process Creation', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f7428da5-c0a4-575a-ae1c-2ad8d7608956', '7e0d4501-4e77-57cd-84d7-48cf5e183ff6', 'Process Termination', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('add89e99-abca-5c96-a1e9-b419d4f107c5', '7e0d4501-4e77-57cd-84d7-48cf5e183ff6', 'Process Creation Using fork(), exec(), wait()', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('406c4c5e-2aa2-5bb4-b36d-4501dcf08848', '80657717-4c7d-5f09-957b-bd88155d7cb0', 'Threads', 'Thread models and the differences between processes and threads.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1120dcf8-a6ca-5fd4-abaa-c4df29ecede2', '406c4c5e-2aa2-5bb4-b36d-4501dcf08848', 'Threading Models', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('a731f1c1-7383-5fe7-b5f9-c1da3b9b74f1', '406c4c5e-2aa2-5bb4-b36d-4501dcf08848', 'Process vs. Thread', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('87e52b59-56d4-5710-9261-aca5fedb2f4f', '406c4c5e-2aa2-5bb4-b36d-4501dcf08848', 'Multithreading Using POSIX Threads', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: CPU Scheduling
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('5aceb9c2-9819-53a4-8c20-730381f9b7af', '8ab461c7-7283-5341-ba28-7f45ec26fe53', 3, 'CPU Scheduling', 'Scheduling goals, criteria, and preemptive/non-preemptive algorithms.', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('161a90ba-4b64-5928-89db-b030ed53ec7c', '5aceb9c2-9819-53a4-8c20-730381f9b7af', 'Scheduling Principles', 'Criteria and objectives for CPU scheduling.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('78921b00-c646-57e9-abd7-a8e03360827c', '161a90ba-4b64-5928-89db-b030ed53ec7c', 'Scheduling Criteria', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d72e44f5-eb4f-5ea3-a515-ce646e375eb6', '161a90ba-4b64-5928-89db-b030ed53ec7c', 'Scheduling Objectives', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('46ff690c-4006-5efc-8564-7169b2c935ab', '5aceb9c2-9819-53a4-8c20-730381f9b7af', 'Scheduling Algorithms', 'Scheduling methods and Gantt-chart generation.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ac5303a3-f45e-5c21-9544-18d54850be48', '46ff690c-4006-5efc-8564-7169b2c935ab', 'Preemptive Scheduling', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ec445735-cc34-53f2-914b-00ab0abb7f8c', '46ff690c-4006-5efc-8564-7169b2c935ab', 'Non-Preemptive Scheduling', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1b398a05-6c44-5791-abd3-757e61214f4d', '46ff690c-4006-5efc-8564-7169b2c935ab', 'First-Come, First-Served (FCFS)', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5e426ec6-0f66-5e23-b31b-e716dcb63c77', '46ff690c-4006-5efc-8564-7169b2c935ab', 'Shortest Job First (SJF)', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('3ae9b435-bef3-5236-986f-e07a49f5741b', '46ff690c-4006-5efc-8564-7169b2c935ab', 'Round Robin', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('932e9c90-e171-5082-8691-1b2df4781332', '46ff690c-4006-5efc-8564-7169b2c935ab', 'Priority Scheduling', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('67299873-36db-516d-bf1d-0ea3ff94b914', '46ff690c-4006-5efc-8564-7169b2c935ab', 'Multilevel Queue', 7)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('40aa9161-81d8-5299-8a70-d1ffd145c675', '46ff690c-4006-5efc-8564-7169b2c935ab', 'Gantt Chart Generation', 8)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Synchronization and Deadlocks
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('83dbadc6-f1a8-529a-a414-f32220163414', '8ab461c7-7283-5341-ba28-7f45ec26fe53', 4, 'Synchronization and Deadlocks', 'Concurrency, critical sections, synchronization tools, and deadlock handling.', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('109e56d0-0f93-58b0-ad11-912b5be685ac', '83dbadc6-f1a8-529a-a414-f32220163414', 'Concurrency and Critical Sections', 'Concurrency issues and critical-section problems.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('8557087a-ac22-5bee-bc23-fb1e81e8bf74', '109e56d0-0f93-58b0-ad11-912b5be685ac', 'Concurrency Issues', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('226471d8-7506-5e36-9462-0c24b55e8e49', '109e56d0-0f93-58b0-ad11-912b5be685ac', 'Critical Section Problem', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('acc62ea1-77b3-5455-aacc-909a78c5412c', '83dbadc6-f1a8-529a-a414-f32220163414', 'Synchronization Tools', 'Tools used to coordinate concurrent processes.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('01f17ca1-2c40-54da-ace2-3e29069929f5', 'acc62ea1-77b3-5455-aacc-909a78c5412c', 'Mutex', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('2a9b1e40-34c9-5cf2-9a9d-e4d489640842', 'acc62ea1-77b3-5455-aacc-909a78c5412c', 'Semaphores', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1b08be59-c9d9-59ab-88da-8871410a9683', 'acc62ea1-77b3-5455-aacc-909a78c5412c', 'Producer-Consumer Problem', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('929aac70-3fd8-5048-959f-49bafdf32347', 'acc62ea1-77b3-5455-aacc-909a78c5412c', 'Readers-Writers Problem', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('f179b75a-c1ca-5ae2-a40f-afc3f9e3968e', '83dbadc6-f1a8-529a-a414-f32220163414', 'Deadlocks', 'Conditions and methods for deadlock management.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('253f5326-ab04-5a46-980a-3f3bbf20d2cc', 'f179b75a-c1ca-5ae2-a40f-afc3f9e3968e', 'Necessary Conditions', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('732310e1-ea30-59ab-bc43-f86d3b8aea37', 'f179b75a-c1ca-5ae2-a40f-afc3f9e3968e', 'Deadlock Prevention', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9313785d-95e5-58cc-9681-a39f3c2ce85c', 'f179b75a-c1ca-5ae2-a40f-afc3f9e3968e', 'Deadlock Avoidance', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('cc8bff4b-cef5-507d-87be-5fc43c21f983', 'f179b75a-c1ca-5ae2-a40f-afc3f9e3968e', 'Deadlock Detection', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('aecadf33-1403-57ee-9991-47a42cd738b3', 'f179b75a-c1ca-5ae2-a40f-afc3f9e3968e', 'Deadlock Recovery', 5)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Memory Management
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('d31a9964-ef49-52d8-8230-bea9e8277dc1', '8ab461c7-7283-5341-ba28-7f45ec26fe53', 5, 'Memory Management', 'Memory allocation, paging, segmentation, virtual memory, and page replacement.', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('85d5bba6-4e81-5819-ac1c-1d499f926d6a', 'd31a9964-ef49-52d8-8230-bea9e8277dc1', 'Memory Allocation', 'Contiguous and non-contiguous memory allocation.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1a23e172-5167-512f-ac6f-f78529e8b148', '85d5bba6-4e81-5819-ac1c-1d499f926d6a', 'Contiguous Allocation', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('32a8b1e1-7726-5151-914d-1374958ca418', '85d5bba6-4e81-5819-ac1c-1d499f926d6a', 'Paging', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('42926ef8-dc4a-5531-8706-8cf19f27f565', '85d5bba6-4e81-5819-ac1c-1d499f926d6a', 'Segmentation', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e28b499c-a9db-52a1-8564-dd08e81fcce9', '85d5bba6-4e81-5819-ac1c-1d499f926d6a', 'Dynamic Memory Allocation and Deallocation', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('9e1b22b9-e7cf-5a6c-9891-127dea3a12b6', 'd31a9964-ef49-52d8-8230-bea9e8277dc1', 'Virtual Memory', 'Virtual memory and demand paging.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e5a14d02-54ba-59ea-ae4f-654b84169519', '9e1b22b9-e7cf-5a6c-9891-127dea3a12b6', 'Virtual Memory', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('154a198b-b14d-5f1b-8acd-1b4c65b90bb4', '9e1b22b9-e7cf-5a6c-9891-127dea3a12b6', 'Demand Paging', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('a55a26dc-fae5-55dd-9677-4aca5cae6e2b', 'd31a9964-ef49-52d8-8230-bea9e8277dc1', 'Page Replacement Algorithms', 'Algorithms for replacing memory pages.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('53012762-2533-59cb-994c-dde6ef2f85ad', 'a55a26dc-fae5-55dd-9677-4aca5cae6e2b', 'FIFO Page Replacement', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7ab1c041-963c-532a-abd8-e59775069122', 'a55a26dc-fae5-55dd-9677-4aca5cae6e2b', 'LRU Page Replacement', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('49f0e3d5-7053-599f-938b-8962dc5269da', 'a55a26dc-fae5-55dd-9677-4aca5cae6e2b', 'Optimal Page Replacement', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: File Systems and I/O Management
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('2a1b43f1-648e-5f04-96d3-a0c9cfce3659', '8ab461c7-7283-5341-ba28-7f45ec26fe53', 6, 'File Systems and I/O Management', 'File-system concepts, access control, I/O, buffering, caching, and disk scheduling.', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('503ec869-5751-541f-8bad-c4805fbf52ca', '2a1b43f1-648e-5f04-96d3-a0c9cfce3659', 'File-System Concepts', 'File and directory organization and access control.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('17d8d04b-e4f5-51d4-bd69-e2cfc2f20c48', '503ec869-5751-541f-8bad-c4805fbf52ca', 'File-System Concepts', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('452cc948-c7dc-5aa7-abee-86b2fedff436', '503ec869-5751-541f-8bad-c4805fbf52ca', 'Directories', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('fc5c1a48-0f6c-5047-b04a-b6b2c0439472', '503ec869-5751-541f-8bad-c4805fbf52ca', 'File Access Control', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4bd999fc-bd37-589c-a2f2-1a5ae5af6e66', '503ec869-5751-541f-8bad-c4805fbf52ca', 'File Operations', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0ff8a6e0-dd39-554e-bbb2-0b07dabddb89', '503ec869-5751-541f-8bad-c4805fbf52ca', 'File Buffering', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('27e6060e-1216-5c8d-9270-fa28222f9589', '2a1b43f1-648e-5f04-96d3-a0c9cfce3659', 'I/O Management', 'Input/output management techniques.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('64db6c03-e643-5c1a-bc43-5e261fe4eaf9', '27e6060e-1216-5c8d-9270-fa28222f9589', 'I/O Management', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('776c75b7-9d35-5582-9ada-1a236478715e', '27e6060e-1216-5c8d-9270-fa28222f9589', 'Buffering', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('42ec0269-80b0-56d3-a4e2-43ea4758c191', '27e6060e-1216-5c8d-9270-fa28222f9589', 'Caching', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('033cb8c2-840f-5e8d-b7b7-584189d6038a', '2a1b43f1-648e-5f04-96d3-a0c9cfce3659', 'Disk Scheduling', 'Disk scheduling algorithms and related practical work.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('090a98e0-ab0e-5862-af0c-d92cf173100e', '033cb8c2-840f-5e8d-b7b7-584189d6038a', 'Disk Scheduling Algorithms', 1)
ON CONFLICT (id) DO NOTHING;

-- Subject: Discrete Mathematics
INSERT INTO public.subjects (id, semester_id, code, name, credits, color_code, display_order)
VALUES ('1bcd3764-5034-5fdb-bf21-3e789e971450', '4d9dfbc8-7a8b-5ae2-8657-492113d879c8', 'DISCRETE_MATHEMATICS', 'Discrete Mathematics', 4, '#0D9488', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Set Theory, Relations and Functions
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('29a1d69c-601f-5e64-afd0-99b8feeefa84', '1bcd3764-5034-5fdb-bf21-3e789e971450', 1, 'Set Theory, Relations and Functions', 'Sets, relations, functions, and recurrence relations.', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('41d1f1b6-7f5d-50fc-b3b2-0b9e86f581f8', '29a1d69c-601f-5e64-afd0-99b8feeefa84', 'Set Theory', 'Set definitions and mathematical induction.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f27a9ff3-2b3d-5e8a-aac1-7b6145ddaa73', '41d1f1b6-7f5d-50fc-b3b2-0b9e86f581f8', 'Inductive Definition of Sets', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('c4be0113-6124-595e-8c1c-ae1193d03d66', '41d1f1b6-7f5d-50fc-b3b2-0b9e86f581f8', 'Proof by Induction', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('34f6f29e-a37c-54b1-abe4-e6aaf0e167e5', '41d1f1b6-7f5d-50fc-b3b2-0b9e86f581f8', 'Peano Postulates', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('98e514c7-0dad-5249-95aa-0626001f1b78', '29a1d69c-601f-5e64-afd0-99b8feeefa84', 'Relations', 'Relations, equivalence relations, and partitions.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f334e6a8-233a-5d90-8f9e-4fd764c58a88', '98e514c7-0dad-5249-95aa-0626001f1b78', 'Equivalence Relations', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('413404e0-95fb-561d-bdbd-0abe94326387', '98e514c7-0dad-5249-95aa-0626001f1b78', 'Partitions', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('21803485-c690-596a-86be-91d5fa7eed51', '29a1d69c-601f-5e64-afd0-99b8feeefa84', 'Functions', 'Types and composition of functions.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('da6545bd-28e3-5690-b23b-c4c779a45836', '21803485-c690-596a-86be-91d5fa7eed51', 'Injective Functions', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('95c390ad-a88c-592a-88fa-f5ed0da87a33', '21803485-c690-596a-86be-91d5fa7eed51', 'Surjective Functions', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1e35896a-7765-5e34-be76-1a93e0531832', '21803485-c690-596a-86be-91d5fa7eed51', 'Bijective Functions', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('82a567b1-186c-5a70-adb9-6d9d1bdc0cd8', '21803485-c690-596a-86be-91d5fa7eed51', 'Composition of Functions', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('c4df28e6-2446-5bd2-9d6d-009a97c53739', '21803485-c690-596a-86be-91d5fa7eed51', 'Inverse Functions', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d3669e95-d747-5d96-80e8-7caaafa46c6e', '21803485-c690-596a-86be-91d5fa7eed51', 'Permutation Functions', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('fdd9fd2b-5dfb-56d6-bd05-f58514f6de6e', '29a1d69c-601f-5e64-afd0-99b8feeefa84', 'Recurrence Relations', 'Recurrence relations and their solutions.', FALSE, 2.0, 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('db9039cf-123a-5207-90da-916d53a6165a', 'fdd9fd2b-5dfb-56d6-bd05-f58514f6de6e', 'Solving Linear Recurrence Relations', 1)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Logic
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('531be26a-2a09-5c21-9bdb-4176e559d9f8', '1bcd3764-5034-5fdb-bf21-3e789e971450', 2, 'Logic', 'Propositional and predicate logic, proofs, and validity of arguments.', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('10b55291-de8f-5425-969d-1ae081980807', '531be26a-2a09-5c21-9bdb-4176e559d9f8', 'Propositions and Logical Operators', 'Propositions and operations on logical statements.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('236e5c49-eb3d-53c6-99ef-bd801859e837', '10b55291-de8f-5425-969d-1ae081980807', 'Propositions', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4b86697f-b105-51ec-a95b-98dbe86e9079', '10b55291-de8f-5425-969d-1ae081980807', 'Logical Operators', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7a9708f6-cc4d-5ab5-90c2-ff5a17b315d4', '10b55291-de8f-5425-969d-1ae081980807', 'Normal Forms', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('cfc94639-f438-5a9b-9553-a4f9c70690c7', '10b55291-de8f-5425-969d-1ae081980807', 'Rules of Inference', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f80b5fcc-7476-5012-94f5-6eaba81eb524', '10b55291-de8f-5425-969d-1ae081980807', 'Consistency and Inconsistency', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('a83fca3c-a9af-5000-9670-c5970c944ad2', '531be26a-2a09-5c21-9bdb-4176e559d9f8', 'Propositional Logic and Proofs', 'Proofs and logical reasoning.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f35ff438-c6b1-51ba-a0dc-a82f83dc7ce8', 'a83fca3c-a9af-5000-9670-c5970c944ad2', 'Propositional Logic', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d3f385ea-28a4-5827-aedd-2c72ae51a40f', 'a83fca3c-a9af-5000-9670-c5970c944ad2', 'Proofs', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('822b2be8-0815-5606-9cc5-4e3dccf8e1b5', 'a83fca3c-a9af-5000-9670-c5970c944ad2', 'Logical Equivalences', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b35f7cd0-c085-5764-84d4-f11c8a881de8', 'a83fca3c-a9af-5000-9670-c5970c944ad2', 'Implications', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('25723ec8-b70e-5687-aa1a-4d5d162a6796', '531be26a-2a09-5c21-9bdb-4176e559d9f8', 'Predicates and Quantifiers', 'Quantified statements and rules for reasoning.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('059b3430-7a44-533a-87e8-ae8e28226fed', '25723ec8-b70e-5687-aa1a-4d5d162a6796', 'Predicates', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e5c88c3b-8508-5499-86a7-3258f40329e7', '25723ec8-b70e-5687-aa1a-4d5d162a6796', 'Quantifiers', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('2b941796-0bea-5a52-8322-7094d149c2bf', '25723ec8-b70e-5687-aa1a-4d5d162a6796', 'Universe of Discourse', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6a55404d-bcc6-5622-a386-44ec45201c5f', '25723ec8-b70e-5687-aa1a-4d5d162a6796', 'Rules of Specification', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('edfea8a7-2030-5081-99d8-d6f3b742485c', '25723ec8-b70e-5687-aa1a-4d5d162a6796', 'Rules of Generalization', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('01b52ad8-ee7d-5727-ae28-6ad9b5e2d751', '25723ec8-b70e-5687-aa1a-4d5d162a6796', 'Validity of Arguments', 6)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Boolean Algebra and Lattice Theory
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('1d58c55f-dd30-5ccd-a900-e372d8b96e69', '1bcd3764-5034-5fdb-bf21-3e789e971450', 3, 'Boolean Algebra and Lattice Theory', 'Partial orders, lattices, and Boolean algebraic structures.', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('af12de58-e75c-5270-bc05-5f78e76b110a', '1d58c55f-dd30-5ccd-a900-e372d8b96e69', 'Partial Ordering and Posets', 'Partial orders and partially ordered sets.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b21e8d56-774a-550f-a818-caf1d763b618', 'af12de58-e75c-5270-bc05-5f78e76b110a', 'Partial Ordering', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ec3b527e-8edc-5882-933e-1d8f5ba20c71', 'af12de58-e75c-5270-bc05-5f78e76b110a', 'Posets', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('db0e9644-57a6-53b7-9c05-74cd2582856c', '1d58c55f-dd30-5ccd-a900-e372d8b96e69', 'Lattices', 'Lattices as partially ordered sets and algebraic systems.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('30419de2-1404-5b6f-912a-8680d549b8ae', 'db0e9644-57a6-53b7-9c05-74cd2582856c', 'Lattices as Posets', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('80030770-61bc-5ee1-a16e-dcdeab3f59ec', 'db0e9644-57a6-53b7-9c05-74cd2582856c', 'Properties of Lattices', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('cd407e56-f792-515f-99c3-f7520ced0508', 'db0e9644-57a6-53b7-9c05-74cd2582856c', 'Lattices as Algebraic Systems', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('78191d72-a5e4-5892-a281-739fef4bb8f3', 'db0e9644-57a6-53b7-9c05-74cd2582856c', 'Sublattices', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('30e25f43-87a4-58ac-b53f-10f87531c670', 'db0e9644-57a6-53b7-9c05-74cd2582856c', 'Direct Product', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7ef0eca7-c7de-55bf-a7ed-18cbfd59e60e', 'db0e9644-57a6-53b7-9c05-74cd2582856c', 'Homomorphism', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('43f288d0-fc75-5852-8dbb-d24e5c8c8660', 'db0e9644-57a6-53b7-9c05-74cd2582856c', 'Some Special Lattices', 7)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('b38b81ae-b52c-55de-8966-357d708634e5', '1d58c55f-dd30-5ccd-a900-e372d8b96e69', 'Boolean Algebra', 'Boolean algebra and related structures.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9021fb7b-e73e-5f57-92d3-b6e8b8bd587b', 'b38b81ae-b52c-55de-8966-357d708634e5', 'Boolean Algebra', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('72c75c67-4310-5aec-b46c-25892a202302', 'b38b81ae-b52c-55de-8966-357d708634e5', 'Sub Boolean Algebra', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9bc0b06e-2c79-5808-a7ad-dca092cd38cf', 'b38b81ae-b52c-55de-8966-357d708634e5', 'Boolean Homomorphism', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Graph Theory
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('f41b8097-ccf8-521f-adae-071dd31d28a3', '1bcd3764-5034-5fdb-bf21-3e789e971450', 4, 'Graph Theory', 'Graph representations, graph properties, and shortest paths.', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('2be5c8bb-0c5e-5051-b30b-c26427e49634', 'f41b8097-ccf8-521f-adae-071dd31d28a3', 'Graphs and Types of Graphs', 'Graph types and matrix representations.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('548d96f8-9898-50d2-be50-4797f5cf9e86', '2be5c8bb-0c5e-5051-b30b-c26427e49634', 'Types of Graphs', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('c328bee0-e1b6-5c29-b072-30260044bc66', '2be5c8bb-0c5e-5051-b30b-c26427e49634', 'Matrix Representation of Graphs', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('a7f5981b-2984-5e20-95df-0b42c2605377', '2be5c8bb-0c5e-5051-b30b-c26427e49634', 'Graph Isomorphism', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('6e2f6159-8fd4-5083-9798-ca81038baa62', 'f41b8097-ccf8-521f-adae-071dd31d28a3', 'Walks, Paths and Cycles', 'Ways of traversing graphs.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b04a983a-90b0-5674-9dd7-099bd2510c61', '6e2f6159-8fd4-5083-9798-ca81038baa62', 'Walks', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6de593cd-7491-573a-928d-581d76679a9e', '6e2f6159-8fd4-5083-9798-ca81038baa62', 'Paths', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('76c19f09-15e7-5421-bf33-5b4d41e8563c', '6e2f6159-8fd4-5083-9798-ca81038baa62', 'Cycles', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('70843596-fe7f-5440-b7ce-7bc5f670e8ca', 'f41b8097-ccf8-521f-adae-071dd31d28a3', 'Special Graphs', 'Eulerian, Hamiltonian, and planar graphs.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('88aa1f0d-4060-5ecc-a88e-dcbf9c62c14d', '70843596-fe7f-5440-b7ce-7bc5f670e8ca', 'Eulerian Graphs', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('99fe40b0-9a30-5fe6-86ca-df88003d41d1', '70843596-fe7f-5440-b7ce-7bc5f670e8ca', 'Hamiltonian Graphs', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('17fcc350-3904-5f11-8f57-ec43675c53ae', '70843596-fe7f-5440-b7ce-7bc5f670e8ca', 'Planar Graphs', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('739b040e-d8a0-57fd-9df0-db298b8e2418', '70843596-fe7f-5440-b7ce-7bc5f670e8ca', 'Euler Formula', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('3d393cc3-1dda-5b13-a5c8-850a0c4447eb', 'f41b8097-ccf8-521f-adae-071dd31d28a3', 'Shortest Path Algorithms', 'Finding shortest paths in weighted graphs.', FALSE, 2.0, 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4116739a-d88d-5338-ac96-fb98e9d46836', '3d393cc3-1dda-5b13-a5c8-850a0c4447eb', 'Dijkstra''s Algorithm', 1)
ON CONFLICT (id) DO NOTHING;

-- Subject: Exploratory Data Analysis
INSERT INTO public.subjects (id, semester_id, code, name, credits, color_code, display_order)
VALUES ('162c3644-00e5-58c8-8ad6-94926d1fcfa9', '4d9dfbc8-7a8b-5ae2-8657-492113d879c8', 'EXPLORATORY_DATA_ANALYSIS', 'Exploratory Data Analysis', 4, '#EA580C', 4)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Introduction
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('6016db91-43d6-5c81-baad-a4af852be9d2', '162c3644-00e5-58c8-8ad6-94926d1fcfa9', 1, 'Introduction', 'Purpose, mindset, data quality, approaches, tools, and initial visual exploration.', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('16b4bde9-f1e3-56a6-b420-cb8bba558277', '6016db91-43d6-5c81-baad-a4af852be9d2', 'EDA Fundamentals', 'Purpose and role of exploratory data analysis.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e7777f43-9b3f-52b0-9d62-e90022ad3ef0', '16b4bde9-f1e3-56a6-b420-cb8bba558277', 'Purpose and Goals of EDA', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ff4aaf30-3cfc-5c46-8a39-74ad977cb2b5', '16b4bde9-f1e3-56a6-b420-cb8bba558277', 'Mindset for Effective Data Exploration', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f87516d1-f915-54c4-b298-96250d74aabe', '16b4bde9-f1e3-56a6-b420-cb8bba558277', 'Significance in the Data Science Lifecycle', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('651d0f72-76ab-5625-8082-3b6d6e7fb480', '6016db91-43d6-5c81-baad-a4af852be9d2', 'Data Types and Quality', 'Types of data and common quality issues.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('3779f9e4-c845-5499-a099-a008ced5ddd9', '651d0f72-76ab-5625-8082-3b6d6e7fb480', 'Types of Data', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('64d75cbf-f3e6-53ed-bc08-79f8145c7c5c', '651d0f72-76ab-5625-8082-3b6d6e7fb480', 'Data Quality Issues', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('a2379cc3-c786-5075-a882-031916bcdfbd', '6016db91-43d6-5c81-baad-a4af852be9d2', 'EDA Approaches and Tools', 'Comparing approaches and selecting tools.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e347f85d-efb8-5648-ba18-6be6c70242dc', 'a2379cc3-c786-5075-a882-031916bcdfbd', 'EDA vs. Classical Approaches', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0a0d38c9-608d-5755-9113-f795234753fa', 'a2379cc3-c786-5075-a882-031916bcdfbd', 'EDA vs. Bayesian Approaches', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9d860661-412a-5bfe-ad9e-3575c8e91059', 'a2379cc3-c786-5075-a882-031916bcdfbd', 'Tools and Libraries for EDA', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('8fb9ff79-118b-5e57-a357-21f8433c7c37', 'a2379cc3-c786-5075-a882-031916bcdfbd', 'Visual Techniques for Initial Insights', 4)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Data Wrangling
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('c8a5a610-042d-5ccc-aa5c-57c3127ed0ed', '162c3644-00e5-58c8-8ad6-94926d1fcfa9', 2, 'Data Wrangling', 'Importing, cleaning, reshaping, and preparing datasets.', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('66b4948a-ae55-528b-ad57-7d174fd46c7b', 'c8a5a610-042d-5ccc-aa5c-57c3127ed0ed', 'Loading and Cleaning Data', 'Importing data and resolving common quality problems.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('745e4786-38fa-5ec7-84a9-adfb5f110b0e', '66b4948a-ae55-528b-ad57-7d174fd46c7b', 'Importing Datasets', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6757e514-07f4-5637-bb82-8385b9914c90', '66b4948a-ae55-528b-ad57-7d174fd46c7b', 'Loading Datasets', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1b8bf47f-ffa3-5bc3-b85d-a44490e4c66c', '66b4948a-ae55-528b-ad57-7d174fd46c7b', 'Handling Missing Values', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('667c71c8-466c-54aa-8f65-4f1f6520e9c3', '66b4948a-ae55-528b-ad57-7d174fd46c7b', 'Handling Outliers', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5fde3bd8-32f5-52eb-aa55-9d8deac8656b', '66b4948a-ae55-528b-ad57-7d174fd46c7b', 'Deduplication', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('3df711ee-f806-5a41-a5fc-752973fbfbad', '66b4948a-ae55-528b-ad57-7d174fd46c7b', 'Correcting Data Types', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('f9b7387b-a1c1-5755-83da-765ff344c9a1', 'c8a5a610-042d-5ccc-aa5c-57c3127ed0ed', 'Reshaping and Transformations', 'Changing dataset structure and variable representation.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('bf6079c1-cf05-5803-aa2e-bbe6234effaf', 'f9b7387b-a1c1-5755-83da-765ff344c9a1', 'Merging Datasets', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('37099bab-4fc7-5608-a844-8f226a2813f4', 'f9b7387b-a1c1-5755-83da-765ff344c9a1', 'Reshaping Data', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4c0cff5b-1da2-5da4-9a23-56124ceceaba', 'f9b7387b-a1c1-5755-83da-765ff344c9a1', 'Pivoting Data', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f5d0893d-a2b1-565a-9940-f6b941257ff6', 'f9b7387b-a1c1-5755-83da-765ff344c9a1', 'Renaming Columns', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('11fea054-83ee-5d21-9e71-520a060e8b93', 'f9b7387b-a1c1-5755-83da-765ff344c9a1', 'Discretization', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4041b223-613a-5c12-bf78-cf922a7c0702', 'f9b7387b-a1c1-5755-83da-765ff344c9a1', 'Binning', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('c0653088-b785-5b44-8011-2c5224a9778e', 'c8a5a610-042d-5ccc-aa5c-57c3127ed0ed', 'Sampling and Preprocessing', 'Sampling methods and real-world preprocessing challenges.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('3b485ec3-412e-5cd1-8102-e4210852a32f', 'c0653088-b785-5b44-8011-2c5224a9778e', 'Permutation', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7b42b629-cde5-5520-a70f-179f49ec4e71', 'c0653088-b785-5b44-8011-2c5224a9778e', 'Random Sampling', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7421e1bc-bbbb-5570-aa02-ca52c93c34d1', 'c0653088-b785-5b44-8011-2c5224a9778e', 'Challenges in Real-World Data Preprocessing', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Multivariate Analysis, Relationship Exploration and Causal Inference
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('5e08d14b-9f56-5459-93df-24d7079fc173', '162c3644-00e5-58c8-8ad6-94926d1fcfa9', 3, 'Multivariate Analysis, Relationship Exploration and Causal Inference', 'Explore variable relationships, correlation, confounding, and causal interpretation.', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('38a44488-25ba-5398-b32c-9ad0c865ceb4', '5e08d14b-9f56-5459-93df-24d7079fc173', 'Univariate, Bivariate and Multivariate Analysis', 'Analyze one or multiple variables and their relationships.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5a5fd27e-f399-54e3-a39d-97f3284b8b07', '38a44488-25ba-5398-b32c-9ad0c865ceb4', 'Univariate Analysis', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('22775f96-47f7-57d0-83d5-f5926bc730d3', '38a44488-25ba-5398-b32c-9ad0c865ceb4', 'Bivariate Analysis', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('bfdde974-f19f-5cda-83e9-562f425e5fee', '38a44488-25ba-5398-b32c-9ad0c865ceb4', 'Multivariate Analysis', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('a680367d-fa22-5a53-b4d8-2ed2be1e15cc', '5e08d14b-9f56-5459-93df-24d7079fc173', 'Relationship Interpretation', 'Interpret relationships and common correlation pitfalls.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('c15b23d1-fb70-5c39-b8c4-996ee95e122d', 'a680367d-fa22-5a53-b4d8-2ed2be1e15cc', 'Simpson''s Paradox', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('fdf26db0-8341-5852-8a12-6a3c1e0d3260', 'a680367d-fa22-5a53-b4d8-2ed2be1e15cc', 'Multicollinearity', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7e15d328-6e70-5509-b5ff-e3a2beca14a1', 'a680367d-fa22-5a53-b4d8-2ed2be1e15cc', 'Correlation Pitfalls', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5fc07e0a-aa46-542f-8f38-769f4d0ee3e1', 'a680367d-fa22-5a53-b4d8-2ed2be1e15cc', 'Correlation Matrix', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('6851494b-5d91-5f29-ae43-20b29ddd9168', '5e08d14b-9f56-5459-93df-24d7079fc173', 'Multivariate Visualization', 'Visualize patterns across variables.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('dbeae403-16d0-5b3d-bc1b-67f019084b14', '6851494b-5d91-5f29-ae43-20b29ddd9168', 'Pair Plots', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b32f9980-96fe-513b-a498-fe9131f8fd7a', '6851494b-5d91-5f29-ae43-20b29ddd9168', 'Heatmaps', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('dcd6928e-d876-52c9-a3d4-378153e1a051', '5e08d14b-9f56-5459-93df-24d7079fc173', 'Causal Inference', 'Distinguish association from causation.', FALSE, 2.0, 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b39b8132-142c-51ca-92e3-6e287a235b9c', 'dcd6928e-d876-52c9-a3d4-378153e1a051', 'Correlation vs. Causation', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('82811497-a7ec-578c-839f-d1c724cb5c95', 'dcd6928e-d876-52c9-a3d4-378153e1a051', 'Confounding Variables', 2)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Time-Oriented Data Exploration
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('83f1c1dd-7b46-5d5a-8a5f-10330e088b6f', '162c3644-00e5-58c8-8ad6-94926d1fcfa9', 4, 'Time-Oriented Data Exploration', 'Explore time-series patterns, resampling, rolling statistics, and anomalies.', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('ce45d666-e3fa-5a6c-aa6d-75ec726e2f9d', '83f1c1dd-7b46-5d5a-8a5f-10330e088b6f', 'Time-Series Fundamentals', 'Time-series data and time-aware indexing.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e2ca0f5b-4c23-5fc3-8847-bacc8c19af04', 'ce45d666-e3fa-5a6c-aa6d-75ec726e2f9d', 'Time-Series Data', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('fb3f96c4-4965-5daa-9538-084c1b6a5c3c', 'ce45d666-e3fa-5a6c-aa6d-75ec726e2f9d', 'Time-Based Indexing', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7ae86eb6-70f5-5710-8b48-fa47a9c9a1e2', 'ce45d666-e3fa-5a6c-aa6d-75ec726e2f9d', 'DateTime Conversion in Pandas', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('a47556a2-5f4f-5b18-be94-e037f410c684', '83f1c1dd-7b46-5d5a-8a5f-10330e088b6f', 'Temporal Aggregation', 'Resampling and aggregation across time intervals.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0d64ba60-fff0-5067-af9d-4885290ff8fe', 'a47556a2-5f4f-5b18-be94-e037f410c684', 'Seasonal Patterns', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('656d64d9-008e-5d1f-a013-06c63c1a657a', 'a47556a2-5f4f-5b18-be94-e037f410c684', 'Down-Sampling', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b21e72ef-5085-58dc-a508-ffcbd52391a3', 'a47556a2-5f4f-5b18-be94-e037f410c684', 'Up-Sampling', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('61877939-6ad4-5458-99f4-ed0f8078a201', 'a47556a2-5f4f-5b18-be94-e037f410c684', 'Aggregations', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('f4194f82-507d-5ac6-8fd9-b8489fc6b2ce', '83f1c1dd-7b46-5d5a-8a5f-10330e088b6f', 'Rolling Statistics and Anomalies', 'Use time-based summaries to identify trends and unusual values.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('a2d61add-00f1-5ec1-9fa2-ecbb383463f6', 'f4194f82-507d-5ac6-8fd9-b8489fc6b2ce', 'Line Plots', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('93684b93-04cb-5fbb-9e0b-bed250d31fdc', 'f4194f82-507d-5ac6-8fd9-b8489fc6b2ce', 'Rolling Statistics', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('2a0ebd71-5bac-5484-a094-f34d0b5958ae', 'f4194f82-507d-5ac6-8fd9-b8489fc6b2ce', 'Anomaly Spotting', 3)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Statistical Testing for Insights
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('6533841c-39bb-5b4d-a23e-bc2b42b90991', '162c3644-00e5-58c8-8ad6-94926d1fcfa9', 5, 'Statistical Testing for Insights', 'Hypothesis testing and interpretation of statistical tests.', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('75a2d680-b696-5cdb-8e76-bc6fd011c70a', '6533841c-39bb-5b4d-a23e-bc2b42b90991', 'Hypothesis Testing', 'Formulate hypotheses and understand testing errors.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('72f7c240-0821-5519-bdb0-98d1ea9aa7fb', '75a2d680-b696-5cdb-8e76-bc6fd011c70a', 'Null Hypothesis', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('51c00769-39ba-5389-97e8-ef1320583fc7', '75a2d680-b696-5cdb-8e76-bc6fd011c70a', 'Alternative Hypothesis', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('961a2131-0cf6-5b0f-9dea-a2607110a51a', '75a2d680-b696-5cdb-8e76-bc6fd011c70a', 'Type I Errors', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e90a2444-45bb-52cb-a722-d8cee29d8bea', '75a2d680-b696-5cdb-8e76-bc6fd011c70a', 'Type II Errors', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('627ebf10-92a7-5a6c-9baa-56d999fefd9a', '6533841c-39bb-5b4d-a23e-bc2b42b90991', 'Statistical Tests', 'Apply statistical tests and interpret their outputs.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('115e0241-bb36-5998-960b-b53c4aedfd55', '627ebf10-92a7-5a6c-9baa-56d999fefd9a', 'T-Tests', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e5943a00-b8f5-5fc3-b37d-687a053b8307', '627ebf10-92a7-5a6c-9baa-56d999fefd9a', 'P-Values', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1709b1ac-3dde-553f-9710-ff996db82bb7', '627ebf10-92a7-5a6c-9baa-56d999fefd9a', 'Using SciPy and Statsmodels', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e1929a0a-1889-5734-80d2-c0e1a2be8f61', '627ebf10-92a7-5a6c-9baa-56d999fefd9a', 'Significance Level', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0cf09254-059a-57a3-ac1f-f11934c78476', '627ebf10-92a7-5a6c-9baa-56d999fefd9a', 'Interpreting Test Results for Decision-Making', 5)
ON CONFLICT (id) DO NOTHING;

-- Chapter: From EDA to Model Deployment
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('c1a0006f-50e9-5cd4-a304-f88c79613395', '162c3644-00e5-58c8-8ad6-94926d1fcfa9', 6, 'From EDA to Model Deployment', 'Prepare, evaluate, save, and locally deploy predictive models.', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('8ad8c088-d349-520b-a26d-6ce2e446b7f2', 'c1a0006f-50e9-5cd4-a304-f88c79613395', 'Model Types and Regression', 'Supervised and unsupervised learning and linear regression.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('faf77c61-ed80-54dc-9fbf-9ed302c29b56', '8ad8c088-d349-520b-a26d-6ce2e446b7f2', 'Supervised Models', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ee5d35f9-ca10-50c1-b6d6-64fadd7c265f', '8ad8c088-d349-520b-a26d-6ce2e446b7f2', 'Unsupervised Models', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f59d5fd7-0921-5dfc-9d42-002eb1d9934b', '8ad8c088-d349-520b-a26d-6ce2e446b7f2', 'Simple Linear Regression', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('54e11af0-3f53-5ed6-93bd-da040acb74c3', '8ad8c088-d349-520b-a26d-6ce2e446b7f2', 'Multiple Linear Regression', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('875c0c11-73d3-5523-bf8b-f2f6c701777c', 'c1a0006f-50e9-5cd4-a304-f88c79613395', 'Training and Evaluation', 'Split data and evaluate model performance.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0332057c-2183-50b9-959b-de0a49e8c6fe', '875c0c11-73d3-5523-bf8b-f2f6c701777c', 'Train/Test Split', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9e707f09-3027-5e99-91c8-7d039feb63c6', '875c0c11-73d3-5523-bf8b-f2f6c701777c', 'Cross-Validation', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('76bcf15a-6af0-5940-ad6c-10b0352ef970', '875c0c11-73d3-5523-bf8b-f2f6c701777c', 'Mean Absolute Error (MAE)', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0e8d0559-5160-5f0a-869c-a2a8ab09d0db', '875c0c11-73d3-5523-bf8b-f2f6c701777c', 'Root Mean Squared Error (RMSE)', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1be5afeb-4156-56af-9aa1-0894756a3c58', '875c0c11-73d3-5523-bf8b-f2f6c701777c', 'R²', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0d71e812-28fd-5029-9bf4-04411ec69c83', '875c0c11-73d3-5523-bf8b-f2f6c701777c', 'Accuracy', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('caa2f867-cf50-59d8-878c-427a0a30df16', '875c0c11-73d3-5523-bf8b-f2f6c701777c', 'F1-Score', 7)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('b998bafa-f8a0-52ae-ab40-b2a097ef77c8', 'c1a0006f-50e9-5cd4-a304-f88c79613395', 'Model Saving and Deployment', 'Save models and expose local predictions.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('cd84a622-aef9-5cf9-aaf5-1b6ea7a51206', 'b998bafa-f8a0-52ae-ab40-b2a097ef77c8', 'Saving Models Using Pickle', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('2e0c98de-395e-5b29-8e0c-6f90892e685e', 'b998bafa-f8a0-52ae-ab40-b2a097ef77c8', 'Saving Models Using Joblib', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('fb17570b-0568-5247-aeae-765e952c899f', 'b998bafa-f8a0-52ae-ab40-b2a097ef77c8', 'Basic Deployment Using Flask', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('74ec6532-0ec2-5b62-b201-0266d33ee2d6', 'b998bafa-f8a0-52ae-ab40-b2a097ef77c8', 'Local Predictions Through a /predict Route', 4)
ON CONFLICT (id) DO NOTHING;

-- Subject: Data Structures
INSERT INTO public.subjects (id, semester_id, code, name, credits, color_code, display_order)
VALUES ('7df2d908-dc07-59e5-a275-4104e122e238', '4d9dfbc8-7a8b-5ae2-8657-492113d879c8', 'DATA_STRUCTURES', 'Data Structures', 4, '#0284C7', 5)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Linear Data Structures
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('043488dc-bfd6-54a7-a1a6-4138de1198b4', '7df2d908-dc07-59e5-a275-4104e122e238', 1, 'Linear Data Structures', 'Arrays, lists, and abstract data types.', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('27ca9036-f140-5571-8289-66f1509c9b83', '043488dc-bfd6-54a7-a1a6-4138de1198b4', 'Abstract Data Types', 'Abstract data types and internal representation.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b9fc144d-f375-517d-ba85-5818f907add7', '27ca9036-f140-5571-8289-66f1509c9b83', 'Abstract Data Types', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b8dd1da1-7721-5628-b5f9-07d5145c7718', '27ca9036-f140-5571-8289-66f1509c9b83', 'Internal Representation of Primitive Data Structures', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('487aa77a-2ef9-57a5-80fd-6163e0163e51', '043488dc-bfd6-54a7-a1a6-4138de1198b4', 'Arrays', 'One-dimensional and multidimensional arrays.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('fddb0b91-7f0a-5f53-9521-d1dfccb04679', '487aa77a-2ef9-57a5-80fd-6163e0163e51', 'One Dimensional Arrays', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('bef496c4-3880-5ff5-9988-dd848d26e718', '487aa77a-2ef9-57a5-80fd-6163e0163e51', 'Multi-Dimensional Arrays', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('89b3e57e-acc9-5e4d-b0a6-bbbefc098288', '043488dc-bfd6-54a7-a1a6-4138de1198b4', 'Linear Lists', 'Linked-list forms and applications.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('695acc66-e6ac-5e92-bb9a-59946f9d72ba', '89b3e57e-acc9-5e4d-b0a6-bbbefc098288', 'Singly Linked Lists', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b621cd14-fc57-50af-8c2e-7e453965e57e', '89b3e57e-acc9-5e4d-b0a6-bbbefc098288', 'Doubly Linked Lists', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('605a5656-fa7e-5b2d-939b-e51383f2a3a6', '89b3e57e-acc9-5e4d-b0a6-bbbefc098288', 'Circular Linked Lists', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ccd10167-24c5-575b-835c-de0571729502', '89b3e57e-acc9-5e4d-b0a6-bbbefc098288', 'Applications', 4)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Stacks and Queues
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('a76781a4-5ade-5efb-9bcd-d1e3239f00a1', '7df2d908-dc07-59e5-a275-4104e122e238', 2, 'Stacks and Queues', 'Representations, operations, implementations, and applications.', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('2dc8147e-f243-5c57-924e-47e474075524', 'a76781a4-5ade-5efb-9bcd-d1e3239f00a1', 'Stacks', 'Stack representations and operations.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('0b05f38d-d473-5489-90b6-01ab2f4c8953', '2dc8147e-f243-5c57-924e-47e474075524', 'Representations', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('30068aa4-e190-5ea5-80c4-3109527b9c09', '2dc8147e-f243-5c57-924e-47e474075524', 'Operations', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b3a04c98-6852-54a6-a4ec-16244f289b97', '2dc8147e-f243-5c57-924e-47e474075524', 'Implementations', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('405082ef-cca2-55d4-8efe-a1c518b52710', '2dc8147e-f243-5c57-924e-47e474075524', 'Applications', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('80218f9c-824b-5d49-9647-240ee2e1829f', '2dc8147e-f243-5c57-924e-47e474075524', 'String Reverse Operations', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b2d29571-203f-54da-8829-a98d2c949641', '2dc8147e-f243-5c57-924e-47e474075524', 'Expression Evaluation', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'a76781a4-5ade-5efb-9bcd-d1e3239f00a1', 'Queues', 'Queue representations, operations, and types.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('dc6a4a6d-82f3-5aa5-93b6-a51e4807a81d', '5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'Representations', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('4728c73a-0d9c-5c0d-978a-0e9fabee47b6', '5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'Operations', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7134a801-9ecd-560a-be2f-71995f7aae82', '5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'Implementations', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('cf7b0c2b-2257-56ab-8caf-6b310ee471d2', '5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'Types of Queues', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7fc0d704-9ddb-5239-8946-4c6f81700ca6', '5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'Applications', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('8bc7a37e-ad40-5f71-a6a3-ffdad41de00d', '5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'Circular Queue', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ba37fbf5-af5f-557a-a8b5-2ddca0b6c67f', '5e11e3b7-16e8-5a89-a94a-1cf009d0aeda', 'Priority Queue', 7)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Trees
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('772a0aee-fd28-58b7-889a-957bccc6538b', '7df2d908-dc07-59e5-a275-4104e122e238', 3, 'Trees', 'Tree representations, balanced trees, and tree operations.', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('210ef156-536c-5bd2-9430-358fba79e394', '772a0aee-fd28-58b7-889a-957bccc6538b', 'Tree Types and Representations', 'Representations and types of trees.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f63c3618-a098-5980-a450-670218b1ecb8', '210ef156-536c-5bd2-9430-358fba79e394', 'Representations', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('ea2fe1d2-2521-5448-bb64-877215459a41', '210ef156-536c-5bd2-9430-358fba79e394', 'Types', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('312c58c4-104e-599d-8831-a581321f1c8c', '210ef156-536c-5bd2-9430-358fba79e394', 'Binary Search Trees (BSTs)', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('0c8a114b-bd66-5de4-9cf0-a55e13baf641', '772a0aee-fd28-58b7-889a-957bccc6538b', 'Balanced Search Trees', 'Operations and balancing in search trees.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f1c8c2b5-dfc6-5065-ac1c-c806045eaefa', '0c8a114b-bd66-5de4-9cf0-a55e13baf641', 'AVL Trees', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('497c0690-7423-5125-acbc-af6c66992ecb', '0c8a114b-bd66-5de4-9cf0-a55e13baf641', 'Search', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('e72d0784-7935-5f2f-877d-da342417fbdf', '0c8a114b-bd66-5de4-9cf0-a55e13baf641', 'Traversals', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('09bcef86-655b-555d-9919-d9aff596a292', '0c8a114b-bd66-5de4-9cf0-a55e13baf641', 'Rotations', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6465fac0-f185-5e28-bc85-3566eb230a77', '0c8a114b-bd66-5de4-9cf0-a55e13baf641', 'Balanced BSTs', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('c08fc326-4631-570a-ace2-c612275ec9c5', '0c8a114b-bd66-5de4-9cf0-a55e13baf641', 'Splay Trees', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d3c41a3f-1d4a-55c1-b1bd-58ad5d85ff8b', '0c8a114b-bd66-5de4-9cf0-a55e13baf641', 'B-Trees', 7)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('78172de1-263e-5940-9097-2ccce1e7457a', '772a0aee-fd28-58b7-889a-957bccc6538b', 'Binary Heaps', 'Binary heap structures.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d65e536f-a5ae-5c30-989d-62084d3f391b', '78172de1-263e-5940-9097-2ccce1e7457a', 'Binary Heaps', 1)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Sorting, Searching and Hashing Techniques
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('7f466629-3179-532f-b088-e5ee6e23a35a', '7df2d908-dc07-59e5-a275-4104e122e238', 4, 'Sorting, Searching and Hashing Techniques', 'Searching, sorting, dictionaries, hash functions, and collision handling.', 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('baf8623a-f073-580a-810f-286c7657e631', '7f466629-3179-532f-b088-e5ee6e23a35a', 'Searching', 'Linear and binary search techniques.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('7bd9dd3e-eaae-5718-a0e7-9d7f3a3f2224', 'baf8623a-f073-580a-810f-286c7657e631', 'Linear Search', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('fece3dae-b0b3-58ae-868d-5705f8738329', 'baf8623a-f073-580a-810f-286c7657e631', 'Binary Search', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('ef7b36f6-71e4-5e82-bc45-72b04525ba41', '7f466629-3179-532f-b088-e5ee6e23a35a', 'Sorting', 'Comparison and non-comparison sorting methods.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('83e1e13a-aad7-5f31-8fe8-8a98d73df115', 'ef7b36f6-71e4-5e82-bc45-72b04525ba41', 'Bubble Sort', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('9eaf2d40-deee-5cd3-845a-b33df700ba65', 'ef7b36f6-71e4-5e82-bc45-72b04525ba41', 'Insertion Sort', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('96dc5797-2571-5040-9466-15d76ae1a334', 'ef7b36f6-71e4-5e82-bc45-72b04525ba41', 'Merge Sort', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5882207f-3f84-5542-964f-9d8c2aad68b9', 'ef7b36f6-71e4-5e82-bc45-72b04525ba41', 'Bucket Sort', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('1ee30683-6d30-5afb-bc91-36b45e2f630b', 'ef7b36f6-71e4-5e82-bc45-72b04525ba41', 'Quick Sort', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('75b76410-45f6-5c01-9517-df9aa76559c1', 'ef7b36f6-71e4-5e82-bc45-72b04525ba41', 'Heap Sort', 6)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('e9f7937d-e0a3-5992-b5fb-156196add76a', '7f466629-3179-532f-b088-e5ee6e23a35a', 'Hashing Techniques', 'Hash functions, dictionaries, and collision resolution.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('8d5995ab-389c-5d3a-923b-b2f780142ff4', 'e9f7937d-e0a3-5992-b5fb-156196add76a', 'Dictionaries', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('d06a8193-6977-56ed-8072-e6c0ef0e3387', 'e9f7937d-e0a3-5992-b5fb-156196add76a', 'Hash Functions', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('8b79ae42-e5b4-55f7-a806-f9f5eaa9aeea', 'e9f7937d-e0a3-5992-b5fb-156196add76a', 'Collisions', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5fe88d40-af03-570c-bd74-34389c6e465f', 'e9f7937d-e0a3-5992-b5fb-156196add76a', 'Separate Chaining', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('14ea6987-99cf-5b37-a044-416477c1bdba', 'e9f7937d-e0a3-5992-b5fb-156196add76a', 'Open Addressing', 5)
ON CONFLICT (id) DO NOTHING;

-- Chapter: Graphs
INSERT INTO public.units (id, subject_id, unit_number, title, description, display_order)
VALUES ('44e5e8d1-ff04-576d-a819-ebbbf15cfab6', '7df2d908-dc07-59e5-a275-4104e122e238', 5, 'Graphs', 'Graph representations, traversal, connectivity, and graph algorithms.', 5)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('87a2a201-aba6-5e13-8284-0f7a04a721f5', '44e5e8d1-ff04-576d-a819-ebbbf15cfab6', 'Graph Representation and Types', 'Representations, types, and operations on graphs.', FALSE, 2.0, 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6b8cad5f-f679-5e1a-81f5-fd02dd0955dd', '87a2a201-aba6-5e13-8284-0f7a04a721f5', 'Graph Representation', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('864878f6-b302-576f-9f16-6c86b6a68847', '87a2a201-aba6-5e13-8284-0f7a04a721f5', 'Types of Graphs', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('957ce62f-c124-5ca8-a697-0b12c505fde1', '87a2a201-aba6-5e13-8284-0f7a04a721f5', 'Graph Operations', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('c9327c48-0fb5-53ed-87c0-efe1427ba66d', '44e5e8d1-ff04-576d-a819-ebbbf15cfab6', 'Graph Algorithms', 'Graph traversal, spanning tree, and shortest-path algorithms.', FALSE, 2.0, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('2ec35f16-31e3-514c-8c3b-e588a8c4be14', 'c9327c48-0fb5-53ed-87c0-efe1427ba66d', 'Prim''s Algorithm', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('53d0f35a-87c5-5b07-ae52-7d02da7c2bee', 'c9327c48-0fb5-53ed-87c0-efe1427ba66d', 'Kruskal''s Algorithm', 2)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('63404c43-8c39-5cc7-bf8d-ea3f6bff7eec', 'c9327c48-0fb5-53ed-87c0-efe1427ba66d', 'Dijkstra''s Algorithm', 3)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('f6351bf5-9843-57a9-9f00-0e42b4535ec5', 'c9327c48-0fb5-53ed-87c0-efe1427ba66d', 'BFS Algorithm', 4)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5f7af3dd-3424-5123-ae5b-b190bfb45e96', 'c9327c48-0fb5-53ed-87c0-efe1427ba66d', 'DFS Algorithm', 5)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('5aff597b-80a7-559d-af55-0411b4b1f48d', 'c9327c48-0fb5-53ed-87c0-efe1427ba66d', 'Minimum Spanning Tree', 6)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('07870d5b-11c4-59db-8887-ae87714c9ab7', 'c9327c48-0fb5-53ed-87c0-efe1427ba66d', 'Shortest Path Algorithms', 7)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.topics (id, unit_id, title, description, is_important, estimated_hours, display_order)
VALUES ('497a6b68-1a0d-598b-9910-f21eb47932dd', '44e5e8d1-ff04-576d-a819-ebbbf15cfab6', 'Graph Connectivity', 'Connected and biconnected components.', FALSE, 2.0, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('b9929e7c-e5b4-507d-930f-f0112816bb94', '497a6b68-1a0d-598b-9910-f21eb47932dd', 'Connected Components', 1)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.subtopics (id, topic_id, title, display_order)
VALUES ('6bc6586a-c5a0-5063-b55b-8641d5ef268c', '497a6b68-1a0d-598b-9910-f21eb47932dd', 'Biconnected Components', 2)
ON CONFLICT (id) DO NOTHING;

-- End of JSON-derived syllabus seed data.
-- The supplied JSON contains 5 subjects, 27 chapters, 76 topics, and 286 subtopics.
