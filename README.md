# Smart Study Tracker — Production Web Application

**Smart Study Tracker** is a full-stack academic web application designed for college students to organize their semester syllabus, track individual study progress, share collaborative learning materials, and identify high-yield examination topics.

Built with **React 19, TypeScript, Tailwind CSS, Supabase PostgreSQL with Row Level Security (RLS), and Supabase Storage**.

---

## 🌟 Key Features

1. **Student Login & Identity Verification**:
   - Clean, student-friendly sign-in with Student Name, College Roll Number, and Security Passcode.
   - Roll numbers are normalized (e.g. `CS2026-001`) and bound to a unique, stable Student ID (`STU-CS2026-001`).
   - Strict student record isolation: Student A can never view or modify Student B's progress.

2. **Hierarchical Semester & Syllabus Explorer**:
   - Structured academic hierarchy: `Semester → Subject → Unit → Topic → Subtopic`.
   - Collapsible unit accordions with instant search across subjects, units, topics, and subtopics.
   - Live completion checkboxes with optimistic UI response and saving feedback.
   - Parent topics and subtopics have defined progress contributions to prevent double-counting.

3. **Important Examination Topics ⭐**:
   - High-yield examination topics marked by academic faculty with the ⭐ badge.
   - Dedicated filter and focused revision dashboard.
   - Database-enforced authorization: Only faculty administrators can assign or revoke important status.

4. **Shared Learning Resources & Storage**:
   - Share lecture PDFs, Word documents, YouTube video lectures, and educational reference URLs.
   - Integrated with Supabase Storage (`study-materials` bucket) with 25MB file limits and MIME type enforcement.
   - Two-tier moderation workflow: Faculty uploads are auto-approved; student submissions go through a pending review queue.

5. **Protected Faculty / Admin Console**:
   - Role-based authorization enforced by PostgreSQL RLS (`public.is_admin(auth.uid())`).
   - Create, edit, and delete syllabus entities (Subjects, Units, Topics).
   - 1-click Important ⭐ topic marker.
   - Review and moderate student-submitted study resources.
   - Student cohort roster showing completion rates across students.

6. **Interactive Test Switcher & Database Inspector**:
   - Top banner with 1-click role switcher to evaluate Student A (Alex Sharma, 45%), Student B (Bhavna Patel, 20%), and Admin (Dr. Eleanor Vance).
   - Modal showing live Supabase connection status, 1-click copy of the full SQL migration script, and an interactive RLS test suite.

---

## 🗄️ Database Architecture & Schema

The application is backed by a normalized PostgreSQL schema located at:
`supabase/migrations/20261023_smart_study_tracker_schema.sql`

### Tables:
1. `profiles` — Authenticated user ID, stable `student_id`, display name, normalized `roll_number`, department, enrolled semester.
2. `user_roles` — Role mapping (`student`, `admin`) with a `SECURITY DEFINER` function `is_admin(user_uuid)`.
3. `semesters` — Semester number, title, academic year, display order.
4. `subjects` — Subject code, name, credits, color code, foreign key to semester.
5. `units` — Unit number, title, description, foreign key to subject.
6. `topics` — Topic title, description, `is_important` (⭐ flag), estimated hours, foreign key to unit.
7. `subtopics` — Subtopic title, display order, foreign key to topic.
8. `topic_progress` — Student `user_id`, `item_id`, `item_type`, `is_completed`, `completed_at` with a unique constraint `UNIQUE (user_id, item_id, item_type)`.
9. `resources` — Resource metadata, format (`pdf`, `youtube`, `url`, `document`), storage `file_path`, moderation `status` (`pending`, `approved`, `rejected`), uploader info.

---

## 🔒 Security & Row Level Security (RLS)

All tables have RLS enabled with strict policies:

- **Student Isolation**:
  ```sql
  CREATE POLICY "Students can only access their own progress"
      ON public.topic_progress FOR ALL
      TO authenticated
      USING (auth.uid() = user_id OR public.is_admin(auth.uid()))
      WITH CHECK (auth.uid() = user_id);
  ```
- **Admin-Only Syllabus Management**:
  ```sql
  CREATE POLICY "Admins can manage topics"
      ON public.topics FOR ALL
      TO authenticated
      USING (public.is_admin(auth.uid()));
  ```
- **Resource Visibility**:
  ```sql
  CREATE POLICY "Anyone can read approved resources"
      ON public.resources FOR SELECT
      TO authenticated
      USING (status = 'approved' OR auth.uid() = uploader_id OR public.is_admin(auth.uid()));
  ```

---

## 🚀 Setup & Deployment

### 1. Configure Supabase
1. Create a project at [supabase.com](https://supabase.com).
2. Open **SQL Editor** and execute `supabase/migrations/20261023_smart_study_tracker_schema.sql`.
3. Create the `study-materials` bucket in **Storage** (Public enabled, 25MB max file size).
4. Copy your Project URL and Anon Public Key from **Project Settings → API**.

### 2. Configure Environment Variables
Create a `.env` file in the project root:
```env
VITE_SUPABASE_URL="https://your-project-id.supabase.co"
VITE_SUPABASE_ANON_KEY="your-anon-public-key"
```

### 3. Local Development
```bash
npm install
npm run dev
```
Open [http://localhost:3000](http://localhost:3000) in your browser.

### 4. Deploy to Vercel
1. Push repository to GitHub:
   ```bash
   git add .
   git commit -m "feat: complete Smart Study Tracker application"
   git push origin main
   ```
2. Import repository in [Vercel](https://vercel.com).
3. Set environment variables `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the Vercel project settings.
4. Deploy!
