# Smart Study Tracker — Supabase Setup & Deployment Guide

This guide walks through configuring Supabase for the **Smart Study Tracker** application.

---

## 1. Supabase Project Setup

1. Go to [https://supabase.com](https://supabase.com) and create a new project.
2. Choose your preferred region and a strong database password.
3. Wait for the project initialization to complete.

---

## 2. Running Database Migrations

1. Open your Supabase Dashboard.
2. In the left navigation, click **SQL Editor**.
3. Click **New query**.
4. Copy and paste the entire contents of `supabase/migrations/20261023_smart_study_tracker_schema.sql`.
5. Click **Run** (or press Ctrl+Enter).
6. Verify that all tables (`profiles`, `user_roles`, `semesters`, `subjects`, `units`, `topics`, `subtopics`, `topic_progress`, `resources`) are created.

---

## 3. Storage Bucket Configuration

1. In the Supabase Dashboard, click **Storage**.
2. If `study-materials` is not already created by the SQL script, click **Create new bucket**:
   - Bucket name: `study-materials`
   - Public bucket: **Enabled** (for sharing learning materials)
   - Allowed MIME types: `application/pdf, application/msword, application/vnd.openxmlformats-officedocument.wordprocessingml.document, text/plain`
   - Max file size: `25MB`

---

## 4. Initial Administrator Provisioning

To securely designate your first administrator:

1. Sign up a user in the application or in the **Authentication -> Users** panel in the Supabase Dashboard (e.g. `admin@college.edu`).
2. Copy the user's UUID from the **Users** table.
3. Go to the **SQL Editor** and run:

```sql
-- Insert into user_roles with admin role
INSERT INTO public.user_roles (user_id, role)
VALUES ('YOUR_USER_UUID_HERE', 'admin')
ON CONFLICT (user_id) 
DO UPDATE SET role = 'admin';

-- Update profile role status
UPDATE public.profiles
SET role = 'admin'
WHERE id = 'YOUR_USER_UUID_HERE';
```

4. Now this administrator has verified privileges to create, edit, reorder, delete syllabus items, mark/unmark ⭐ Important topics, and moderate resources.

---

## 5. Frontend Environment Variables

Create `.env` in the root folder with:

```env
VITE_SUPABASE_URL="https://your-project-id.supabase.co"
VITE_SUPABASE_ANON_KEY="your-anon-key-here"
```

Restart the development server (`npm run dev`). The app will detect the live Supabase credentials and connect immediately.

---

## 6. Row Level Security (RLS) Verification

- **Progress Isolation**: Student A's query to `topic_progress` only returns rows where `auth.uid() = user_id`. Attempting to read another student's progress returns 0 rows.
- **Admin-Only Syllabus Editing**: Any direct attempt by a student to INSERT, UPDATE, or DELETE from `semesters`, `subjects`, `units`, or `topics` will be rejected by PostgreSQL with an RLS policy violation.
- **Important Badge Protection**: Only users where `is_admin(auth.uid()) = true` can alter `topics.is_important`.
