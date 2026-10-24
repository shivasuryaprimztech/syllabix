/**
 * Database and Domain Types for Smart Study Tracker
 */

export type UserRole = 'student' | 'admin';

export interface Profile {
  id: string;
  student_id: string;
  display_name: string;
  roll_number: string;
  department: string;
  semester_enrolled: number;
  account_status: 'active' | 'suspended' | 'pending';
  role: UserRole;
  created_at?: string;
  updated_at?: string;
}

export interface Semester {
  id: string;
  semester_number: number;
  title: string;
  academic_year: string;
  display_order: number;
  is_active: boolean;
  created_at?: string;
}

export interface Subject {
  id: string;
  semester_id: string;
  code: string;
  name: string;
  credits: number;
  color_code: string;
  display_order: number;
  created_at?: string;
}

export interface Unit {
  id: string;
  subject_id: string;
  unit_number: number;
  title: string;
  description: string | null;
  display_order: number;
  created_at?: string;
}

export interface Topic {
  id: string;
  unit_id: string;
  title: string;
  description: string | null;
  is_important: boolean;
  estimated_hours: number;
  display_order: number;
  created_at?: string;
}

export interface Subtopic {
  id: string;
  topic_id: string;
  title: string;
  display_order: number;
  created_at?: string;
}

export interface TopicProgress {
  id: string;
  user_id: string;
  item_id: string;
  item_type: 'topic' | 'subtopic';
  is_completed: boolean;
  completed_at: string;
}

export type ResourceType = 'pdf' | 'document' | 'youtube' | 'url';
export type ResourceStatus = 'pending' | 'approved' | 'rejected';

export interface StudyResource {
  id: string;
  title: string;
  description: string | null;
  resource_type: ResourceType;
  semester_id: string;
  subject_id: string;
  unit_id: string | null;
  topic_id: string | null;
  uploader_id: string;
  uploader_name: string;
  uploader_roll: string;
  file_path: string | null;
  file_size_bytes: number | null;
  file_mime_type: string | null;
  external_url: string | null;
  status: ResourceStatus;
  is_exam_prep: boolean;
  created_at: string;
  updated_at?: string;
}

// Tree view hierarchy interfaces
export interface TopicWithSubtopics extends Topic {
  subtopics: Subtopic[];
}

export interface UnitWithTopics extends Unit {
  topics: TopicWithSubtopics[];
}

export interface SubjectWithUnits extends Subject {
  units: UnitWithTopics[];
}

export interface SemesterWithSubjects extends Semester {
  subjects: SubjectWithUnits[];
}

export interface ProgressSummary {
  totalTopics: number;
  completedTopics: number;
  totalSubtopics: number;
  completedSubtopics: number;
  overallPercentage: number;
  importantTotal: number;
  importantCompleted: number;
  subjectProgress: {
    subjectId: string;
    subjectCode: string;
    subjectName: string;
    colorCode: string;
    total: number;
    completed: number;
    percentage: number;
  }[];
}
