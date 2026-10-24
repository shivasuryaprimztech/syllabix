import { isSupabaseConfigured, getSupabaseClient } from '../lib/supabase';
import { SupabaseClient } from '@supabase/supabase-js';
import {
  Profile,
  Semester,
  Subject,
  Unit,
  Topic,
  Subtopic,
  StudyResource,
  SemesterWithSubjects,
  ProgressSummary,
  ResourceStatus,
  ResourceType,
} from '../types/database';

export class DataService {
  private static cachedUser: Profile | null = null;

  private static getClient(): SupabaseClient {
    const client = getSupabaseClient();
    if (!client) {
      throw new Error(
        'Supabase is not configured. Please define VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in your environment (.env).'
      );
    }
    return client;
  }

  // --------------------------------------------------------------------------
  // BROWSER-LOCAL STUDY PROGRESS (Safe, No Authentication Required)
  // --------------------------------------------------------------------------
  private static readonly STORAGE_PROGRESS_KEY = 'smart_study_tracker_progress';

  /**
   * Retrieve current user checklist progress from browser localStorage
   */
  static getLocalProgress(): Record<string, boolean> {
    try {
      const data = localStorage.getItem(this.STORAGE_PROGRESS_KEY);
      return data ? JSON.parse(data) : {};
    } catch {
      return {};
    }
  }

  /**
   * Save entire checklist progress to browser localStorage
   */
  static saveLocalProgress(progress: Record<string, boolean>): void {
    try {
      localStorage.setItem(this.STORAGE_PROGRESS_KEY, JSON.stringify(progress));
    } catch (err) {
      console.warn('Failed to save progress to localStorage:', err);
    }
  }

  /**
   * Toggle completion of a topic or subtopic in browser localStorage
   */
  static toggleLocalProgress(
    itemId: string,
    isCompleted: boolean
  ): { success: boolean; progressMap: Record<string, boolean> } {
    const current = this.getLocalProgress();
    if (isCompleted) {
      current[itemId] = true;
    } else {
      delete current[itemId];
    }
    this.saveLocalProgress(current);
    return { success: true, progressMap: current };
  }

  /**
   * Clear all local progress
   */
  static clearLocalProgress(): void {
    try {
      localStorage.removeItem(this.STORAGE_PROGRESS_KEY);
    } catch (err) {
      console.warn('Failed to clear local progress:', err);
    }
  }

  // --------------------------------------------------------------------------
  // SYLLABUS HIERARCHY (Real Supabase Tables)
  // --------------------------------------------------------------------------

  static async getSemesters(): Promise<Semester[]> {
    if (!isSupabaseConfigured()) {
      return [];
    }
    const client = this.getClient();
    const { data, error } = await client
      .from('semesters')
      .select('*')
      .order('display_order', { ascending: true });

    if (error) {
      throw new Error(`Failed to load semesters: ${error.message}`);
    }

    return data || [];
  }

  static async getSyllabusTree(semesterId?: string): Promise<SemesterWithSubjects[]> {
    if (!isSupabaseConfigured()) {
      return [];
    }
    const client = this.getClient();

    // Query all hierarchy tables from Supabase
    const [semRes, subRes, unitRes, topRes, subTopRes] = await Promise.all([
      client.from('semesters').select('*').order('display_order', { ascending: true }),
      client.from('subjects').select('*').order('display_order', { ascending: true }),
      client.from('units').select('*').order('display_order', { ascending: true }),
      client.from('topics').select('*').order('display_order', { ascending: true }),
      client.from('subtopics').select('*').order('display_order', { ascending: true }),
    ]);

    if (semRes.error) throw new Error(`Failed to load semesters: ${semRes.error.message}`);
    if (subRes.error) throw new Error(`Failed to load subjects: ${subRes.error.message}`);
    if (unitRes.error) throw new Error(`Failed to load units: ${unitRes.error.message}`);
    if (topRes.error) throw new Error(`Failed to load topics: ${topRes.error.message}`);
    if (subTopRes.error) throw new Error(`Failed to load subtopics: ${subTopRes.error.message}`);

    const semesters: Semester[] = semRes.data || [];
    const subjects: Subject[] = subRes.data || [];
    const units: Unit[] = unitRes.data || [];
    const topics: Topic[] = topRes.data || [];
    const subtopics: Subtopic[] = subTopRes.data || [];

    const activeSemesters = semesterId
      ? semesters.filter((s) => s.id === semesterId)
      : semesters;

    return activeSemesters.map((sem) => {
      const semSubjects = subjects
        .filter((sub) => sub.semester_id === sem.id)
        .map((sub) => {
          const subUnits = units
            .filter((u) => u.subject_id === sub.id)
            .map((u) => {
              const uTopics = topics
                .filter((t) => t.unit_id === u.id)
                .map((t) => {
                  const tSubtopics = subtopics.filter((st) => st.topic_id === t.id);
                  return {
                    ...t,
                    subtopics: tSubtopics,
                  };
                });
              return {
                ...u,
                topics: uTopics,
              };
            });
          return {
            ...sub,
            units: subUnits,
          };
        });

      return {
        ...sem,
        subjects: semSubjects,
      };
    });
  }

  // --------------------------------------------------------------------------
  // STUDENT PROGRESS (Browser-Local Storage without requiring Auth)
  // --------------------------------------------------------------------------

  static async getUserProgress(_userId?: string): Promise<Record<string, boolean>> {
    return this.getLocalProgress();
  }

  static async toggleProgress(
    _userId: string,
    itemId: string,
    _itemType: 'topic' | 'subtopic',
    isCompleted: boolean
  ): Promise<{ success: boolean; error?: string }> {
    this.toggleLocalProgress(itemId, isCompleted);
    return { success: true };
  }

  static calculateProgressSummary(
    syllabus: SemesterWithSubjects[],
    progressMap: Record<string, boolean>
  ): ProgressSummary {
    let totalTopics = 0;
    let completedTopics = 0;
    let totalSubtopics = 0;
    let completedSubtopics = 0;
    let importantTotal = 0;
    let importantCompleted = 0;

    const subjectProgress: ProgressSummary['subjectProgress'] = [];

    syllabus.forEach((sem) => {
      sem.subjects.forEach((sub) => {
        let subTotalTopics = 0;
        let subCompletedTopics = 0;

        sub.units.forEach((u) => {
          u.topics.forEach((top) => {
            totalTopics++;
            subTotalTopics++;

            if (top.is_important) {
              importantTotal++;
            }

            if (progressMap[top.id]) {
              completedTopics++;
              subCompletedTopics++;
              if (top.is_important) {
                importantCompleted++;
              }
            }

            top.subtopics?.forEach((st) => {
              totalSubtopics++;
              if (progressMap[st.id]) {
                completedSubtopics++;
              }
            });
          });
        });

        const percentage =
          subTotalTopics > 0 ? Math.round((subCompletedTopics / subTotalTopics) * 100) : 0;

        subjectProgress.push({
          subjectId: sub.id,
          subjectCode: sub.code,
          subjectName: sub.name,
          colorCode: sub.color_code,
          total: subTotalTopics,
          completed: subCompletedTopics,
          percentage,
        });
      });
    });

    const overallPercentage =
      totalTopics > 0 ? Math.round((completedTopics / totalTopics) * 100) : 0;

    return {
      totalTopics,
      completedTopics,
      totalSubtopics,
      completedSubtopics,
      overallPercentage,
      importantTotal,
      importantCompleted,
      subjectProgress,
    };
  }

  // --------------------------------------------------------------------------
  // IMPORTANT EXAMINATION TOPICS (Admin Privileged)
  // --------------------------------------------------------------------------

  static async toggleTopicImportantStatus(
    topicId: string,
    isImportant: boolean,
    user: Profile
  ): Promise<{ success: boolean; error?: string }> {
    if (user.role !== 'admin') {
      return {
        success: false,
        error: 'Authorization Denied: Only faculty administrators can mark examination topics as important (RLS violation).',
      };
    }

    const client = this.getClient();
    try {
      const { error } = await client
        .from('topics')
        .update({ is_important: isImportant })
        .eq('id', topicId);

      if (error) {
        return { success: false, error: error.message };
      }
      return { success: true };
    } catch (e) {
      return {
        success: false,
        error: e instanceof Error ? e.message : 'Failed to update topic importance',
      };
    }
  }

  // --------------------------------------------------------------------------
  // ADMIN SYLLABUS MANAGEMENT (Real Supabase CRUD)
  // --------------------------------------------------------------------------

  static async addSubject(
    subjectData: Omit<Subject, 'id'>,
    user: Profile
  ): Promise<{ success: boolean; subject?: Subject; error?: string }> {
    if (user.role !== 'admin') {
      return { success: false, error: 'Admin permission required.' };
    }
    const client = this.getClient();

    try {
      const { data, error } = await client
        .from('subjects')
        .insert(subjectData)
        .select()
        .single();

      if (error) return { success: false, error: error.message };
      return { success: true, subject: data };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : 'Database error adding subject',
      };
    }
  }

  static async addUnit(
    unitData: Omit<Unit, 'id'>,
    user: Profile
  ): Promise<{ success: boolean; unit?: Unit; error?: string }> {
    if (user.role !== 'admin') {
      return { success: false, error: 'Admin permission required.' };
    }
    const client = this.getClient();

    try {
      const { data, error } = await client
        .from('units')
        .insert(unitData)
        .select()
        .single();

      if (error) return { success: false, error: error.message };
      return { success: true, unit: data };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : 'Database error adding unit',
      };
    }
  }

  static async addTopic(
    topicData: Omit<Topic, 'id'>,
    user: Profile
  ): Promise<{ success: boolean; topic?: Topic; error?: string }> {
    if (user.role !== 'admin') {
      return { success: false, error: 'Admin permission required.' };
    }
    const client = this.getClient();

    try {
      const { data, error } = await client
        .from('topics')
        .insert(topicData)
        .select()
        .single();

      if (error) return { success: false, error: error.message };
      return { success: true, topic: data };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : 'Database error adding topic',
      };
    }
  }

  static async addSubtopic(
    subtopicData: Omit<Subtopic, 'id'>,
    user: Profile
  ): Promise<{ success: boolean; subtopic?: Subtopic; error?: string }> {
    if (user.role !== 'admin') {
      return { success: false, error: 'Admin permission required.' };
    }
    const client = this.getClient();

    try {
      const { data, error } = await client
        .from('subtopics')
        .insert(subtopicData)
        .select()
        .single();

      if (error) return { success: false, error: error.message };
      return { success: true, subtopic: data };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : 'Database error adding subtopic',
      };
    }
  }

  static async deleteSyllabusItem(
    type: 'subject' | 'unit' | 'topic' | 'subtopic',
    id: string,
    user: Profile
  ): Promise<{ success: boolean; error?: string }> {
    if (user.role !== 'admin') {
      return { success: false, error: 'Admin permission required (RLS protected).' };
    }
    const client = this.getClient();

    try {
      const table =
        type === 'subject'
          ? 'subjects'
          : type === 'unit'
          ? 'units'
          : type === 'topic'
          ? 'topics'
          : 'subtopics';
      const { error } = await client.from(table).delete().eq('id', id);
      if (error) return { success: false, error: error.message };
      return { success: true };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : 'Deletion failed',
      };
    }
  }

  // --------------------------------------------------------------------------
  // SHARED STUDY RESOURCES (Real Supabase Storage & Table)
  // --------------------------------------------------------------------------

  static async getResources(filters?: {
    subjectId?: string;
    resourceType?: ResourceType | 'all';
    searchQuery?: string;
    examPrepOnly?: boolean;
    statusFilter?: ResourceStatus | 'all';
    user?: Profile | null;
  }): Promise<StudyResource[]> {
    if (!isSupabaseConfigured()) {
      return [];
    }
    const client = this.getClient();

    let query = client.from('resources').select('*').order('created_at', { ascending: false });

    if (filters?.subjectId && filters.subjectId !== 'all') {
      query = query.eq('subject_id', filters.subjectId);
    }
    if (filters?.resourceType && filters.resourceType !== 'all') {
      query = query.eq('resource_type', filters.resourceType);
    }
    if (filters?.examPrepOnly) {
      query = query.eq('is_exam_prep', true);
    }
    if (filters?.statusFilter && filters.statusFilter !== 'all') {
      query = query.eq('status', filters.statusFilter);
    }

    const { data, error } = await query;
    if (error) {
      throw new Error(`Failed to load resources: ${error.message}`);
    }

    const resources: StudyResource[] = data || [];

    // Filter by visibility rules and search query
    return resources.filter((res) => {
      const isVisible =
        res.status === 'approved' ||
        (filters?.user && (filters.user.role === 'admin' || filters.user.id === res.uploader_id));

      if (!isVisible) return false;

      if (filters?.searchQuery) {
        const q = filters.searchQuery.toLowerCase().trim();
        const matchTitle = res.title?.toLowerCase().includes(q);
        const matchDesc = res.description ? res.description.toLowerCase().includes(q) : false;
        const matchUploader = res.uploader_name?.toLowerCase().includes(q);
        if (!matchTitle && !matchDesc && !matchUploader) return false;
      }

      return true;
    });
  }

  static async addResource(
    resourceData: {
      title: string;
      description?: string;
      resource_type: ResourceType;
      semester_id: string;
      subject_id: string;
      unit_id?: string;
      topic_id?: string;
      external_url?: string;
      file?: File;
      is_exam_prep?: boolean;
      uploaderName?: string;
    },
    currentUser?: Profile | null
  ): Promise<{ success: boolean; resource?: StudyResource; error?: string }> {
    if (!resourceData.title || resourceData.title.trim().length < 3) {
      return { success: false, error: 'Resource title must be at least 3 characters.' };
    }

    if (['youtube', 'url'].includes(resourceData.resource_type)) {
      if (!resourceData.external_url || !resourceData.external_url.startsWith('http')) {
        return { success: false, error: 'Please enter a valid educational URL starting with https://' };
      }
    }

    if (!isSupabaseConfigured()) {
      return { success: false, error: 'Supabase database is not configured.' };
    }

    const client = this.getClient();
    let filePath: string | null = null;
    let fileSize: number | null = null;
    let mimeType: string | null = null;

    if (resourceData.file) {
      if (resourceData.file.size > 25 * 1024 * 1024) {
        return { success: false, error: 'File size exceeds maximum limit of 25MB.' };
      }
      fileSize = resourceData.file.size;
      mimeType = resourceData.file.type;
      const uploaderId = currentUser?.id || 'community';
      filePath = `${uploaderId}/${Date.now()}_${resourceData.file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;

      try {
        const { error: uploadError } = await client.storage
          .from('study-materials')
          .upload(filePath, resourceData.file);

        if (uploadError) {
          return { success: false, error: `File upload error: ${uploadError.message}` };
        }
      } catch (e) {
        return {
          success: false,
          error: e instanceof Error ? e.message : 'Storage upload failed',
        };
      }
    }

    const uploaderName = resourceData.uploaderName?.trim() || currentUser?.display_name || 'Student Contributor';

    const newResource = {
      title: resourceData.title.trim(),
      description: resourceData.description?.trim() || null,
      resource_type: resourceData.resource_type,
      semester_id: resourceData.semester_id,
      subject_id: resourceData.subject_id,
      unit_id: resourceData.unit_id || null,
      topic_id: resourceData.topic_id || null,
      uploader_id: currentUser?.id || '00000000-0000-0000-0000-000000000000',
      uploader_name: uploaderName,
      uploader_roll: currentUser?.roll_number || 'STUDENT',
      file_path: filePath,
      file_size_bytes: fileSize,
      file_mime_type: mimeType,
      external_url: resourceData.external_url?.trim() || null,
      status: 'approved' as ResourceStatus,
      is_exam_prep: Boolean(resourceData.is_exam_prep),
    };

    try {
      const { data, error } = await client
        .from('resources')
        .insert(newResource)
        .select()
        .single();

      if (error) return { success: false, error: error.message };
      return { success: true, resource: data };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : 'Database error saving resource',
      };
    }
  }

  static async deleteResource(
    resourceId: string,
    _currentUser?: Profile | null
  ): Promise<{ success: boolean; error?: string }> {
    if (!isSupabaseConfigured()) return { success: false, error: 'Database not connected' };
    const client = this.getClient();

    try {
      const { error } = await client.from('resources').delete().eq('id', resourceId);
      if (error) return { success: false, error: error.message };
      return { success: true };
    } catch (err) {
      return {
        success: false,
        error: err instanceof Error ? err.message : 'Delete failed',
      };
    }
  }

  static getResourcePublicUrl(filePath: string): string | null {
    if (!filePath || !isSupabaseConfigured()) return null;
    const client = getSupabaseClient();
    if (!client) return null;
    const { data } = client.storage.from('study-materials').getPublicUrl(filePath);
    return data.publicUrl;
  }

  // --------------------------------------------------------------------------
  // ADMIN ROSTER & VERIFICATION (Real Database Data)
  // --------------------------------------------------------------------------

  static async getStudentRoster(): Promise<Array<{
    id: string;
    name: string;
    roll: string;
    dept: string;
    role: string;
    completedTopicsCount: number;
  }>> {
    if (!isSupabaseConfigured()) {
      return [];
    }
    const client = this.getClient();

    const [profilesRes, progressRes, rolesRes] = await Promise.all([
      client.from('profiles').select('*').order('created_at', { ascending: true }),
      client.from('topic_progress').select('user_id').eq('is_completed', true),
      client.from('user_roles').select('*'),
    ]);

    if (profilesRes.error) {
      throw new Error(`Failed to load student roster: ${profilesRes.error.message}`);
    }

    const profiles = profilesRes.data || [];
    const progressList = progressRes.data || [];
    const rolesList = rolesRes.data || [];

    const rolesMap = new Map<string, string>();
    rolesList.forEach((r) => rolesMap.set(r.user_id, r.role));

    const progressCountMap = new Map<string, number>();
    progressList.forEach((p) => {
      progressCountMap.set(p.user_id, (progressCountMap.get(p.user_id) || 0) + 1);
    });

    return profiles.map((p) => {
      const role = rolesMap.get(p.id) || p.role || 'student';
      return {
        id: p.id,
        name: p.display_name,
        roll: p.roll_number,
        dept: p.department || 'Computer Science & Engineering',
        role,
        completedTopicsCount: progressCountMap.get(p.id) || 0,
      };
    });
  }
}
