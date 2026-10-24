/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useCallback } from 'react';
import { Navbar } from './components/Navbar';
import { StudentDashboard } from './components/StudentDashboard';
import { SyllabusExplorer } from './components/SyllabusExplorer';
import { ImportantTopicsView } from './components/ImportantTopicsView';
import { SharedResourcesView } from './components/SharedResourcesView';
import { AdminPanel } from './components/AdminPanel';
import { LoginModal } from './components/LoginModal';
import { AddResourceModal } from './components/AddResourceModal';
import { DataService } from './services/dataService';
import { isSupabaseConfigured } from './lib/supabase';
import {
  Profile,
  SemesterWithSubjects,
  StudyResource,
  ProgressSummary,
} from './types/database';
import { AlertCircle, CheckCircle2, Loader2, RotateCcw } from 'lucide-react';

export default function App() {
  const [currentTab, setCurrentTab] = useState<
    'dashboard' | 'syllabus' | 'important' | 'resources' | 'admin'
  >('dashboard');

  const [currentUser, setCurrentUser] = useState<Profile | null>(null);
  const [isAuthChecking, setIsAuthChecking] = useState(true);

  const [syllabus, setSyllabus] = useState<SemesterWithSubjects[]>([]);
  const [resources, setResources] = useState<StudyResource[]>([]);
  const [progressMap, setProgressMap] = useState<Record<string, boolean>>({});
  const [savingItems, setSavingItems] = useState<Record<string, boolean>>({});

  // Loading & Error States
  const [isLoadingSyllabus, setIsLoadingSyllabus] = useState(true);
  const [syllabusError, setSyllabusError] = useState<string | null>(null);
  const [isLoadingResources, setIsLoadingResources] = useState(true);
  const [resourcesError, setResourcesError] = useState<string | null>(null);

  // Modals
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);
  const [isAddResourceOpen, setIsAddResourceOpen] = useState(false);

  // Notifications
  const [toast, setToast] = useState<{ type: 'success' | 'error'; message: string } | null>(null);

  const showToast = (type: 'success' | 'error', message: string) => {
    setToast({ type, message });
    setTimeout(() => {
      setToast(null);
    }, 3500);
  };

  // 1. Initialize Real Supabase Session & Listen to Auth changes
  useEffect(() => {
    let isMounted = true;

    async function initUser() {
      if (!isSupabaseConfigured()) {
        setIsAuthChecking(false);
        return;
      }

      try {
        const profile = await DataService.getAuthenticatedProfile();
        if (isMounted) {
          setCurrentUser(profile);
        }
      } catch (err) {
        console.warn('Session initialization:', err);
      } finally {
        if (isMounted) {
          setIsAuthChecking(false);
        }
      }
    }

    initUser();

    // Listen to Supabase Auth state changes
    const unsubscribe = DataService.onAuthStateChange((user) => {
      if (isMounted) {
        setCurrentUser(user);
      }
    });

    return () => {
      isMounted = false;
      unsubscribe();
    };
  }, []);

  // 2. Load syllabus hierarchy directly from Supabase
  const loadSyllabus = useCallback(async () => {
    if (!isSupabaseConfigured()) {
      setIsLoadingSyllabus(false);
      setSyllabus([]);
      setSyllabusError(
        'Supabase is not configured. Please define VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in your environment configuration (.env).'
      );
      return;
    }

    setIsLoadingSyllabus(true);
    setSyllabusError(null);
    try {
      const data = await DataService.getSyllabusTree();
      setSyllabus(data);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to query syllabus from Supabase.';
      setSyllabusError(msg);
      console.warn('Could not load syllabus:', err);
    } finally {
      setIsLoadingSyllabus(false);
    }
  }, []);

  // 3. Load resources directly from Supabase
  const loadResources = useCallback(async () => {
    if (!isSupabaseConfigured()) {
      setIsLoadingResources(false);
      setResources([]);
      return;
    }

    setIsLoadingResources(true);
    setResourcesError(null);
    try {
      const data = await DataService.getResources({ user: currentUser });
      setResources(data);
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to query resources from Supabase.';
      setResourcesError(msg);
      console.warn('Could not load resources:', err);
    } finally {
      setIsLoadingResources(false);
    }
  }, [currentUser]);

  // 4. Load real student progress from topic_progress (Strict user_id isolation)
  const loadProgress = useCallback(async (userId: string) => {
    if (!isSupabaseConfigured() || !userId) {
      setProgressMap({});
      return;
    }

    try {
      const map = await DataService.getUserProgress(userId);
      setProgressMap(map);
    } catch (err) {
      console.warn('Could not load user progress:', err);
      setProgressMap({});
    }
  }, []);

  // Initial data load
  useEffect(() => {
    loadSyllabus();
  }, [loadSyllabus]);

  useEffect(() => {
    loadResources();
  }, [loadResources]);

  // When current user changes, reload their private progress
  useEffect(() => {
    if (currentUser) {
      loadProgress(currentUser.id);
    } else {
      setProgressMap({});
    }
  }, [currentUser, loadProgress]);

  // Calculate overall & subject-wise progress summary from real data
  const progressSummary: ProgressSummary = DataService.calculateProgressSummary(
    syllabus,
    progressMap
  );

  // Toggle Topic Progress Checkbox
  const handleToggleTopic = async (topicId: string, isCompleted: boolean) => {
    if (!currentUser) {
      setIsAuthModalOpen(true);
      return;
    }

    // Optimistic UI update
    setProgressMap((prev) => ({
      ...prev,
      [topicId]: isCompleted,
    }));
    setSavingItems((prev) => ({ ...prev, [topicId]: true }));

    try {
      const res = await DataService.toggleProgress(currentUser.id, topicId, 'topic', isCompleted);
      if (!res.success) {
        // Revert on error
        setProgressMap((prev) => ({
          ...prev,
          [topicId]: !isCompleted,
        }));
        showToast('error', res.error || 'Failed to save progress to Supabase.');
      }
    } catch {
      setProgressMap((prev) => ({
        ...prev,
        [topicId]: !isCompleted,
      }));
      showToast('error', 'Network error. Failed to persist progress to database.');
    } finally {
      setSavingItems((prev) => {
        const next = { ...prev };
        delete next[topicId];
        return next;
      });
    }
  };

  // Toggle Subtopic Progress Checkbox
  const handleToggleSubtopic = async (subtopicId: string, isCompleted: boolean) => {
    if (!currentUser) {
      setIsAuthModalOpen(true);
      return;
    }

    setProgressMap((prev) => ({
      ...prev,
      [subtopicId]: isCompleted,
    }));
    setSavingItems((prev) => ({ ...prev, [subtopicId]: true }));

    try {
      const res = await DataService.toggleProgress(currentUser.id, subtopicId, 'subtopic', isCompleted);
      if (!res.success) {
        setProgressMap((prev) => ({
          ...prev,
          [subtopicId]: !isCompleted,
        }));
        showToast('error', res.error || 'Failed to update subtopic');
      }
    } catch {
      setProgressMap((prev) => ({
        ...prev,
        [subtopicId]: !isCompleted,
      }));
      showToast('error', 'Failed to update subtopic');
    } finally {
      setSavingItems((prev) => {
        const next = { ...prev };
        delete next[subtopicId];
        return next;
      });
    }
  };

  // Toggle Important Status (Admin role required!)
  const handleToggleImportant = async (topicId: string, isImportant: boolean) => {
    if (!currentUser || currentUser.role !== 'admin') {
      showToast('error', 'RLS Denied: Only faculty administrators can mark examination topics as important.');
      return;
    }

    const res = await DataService.toggleTopicImportantStatus(topicId, isImportant, currentUser);
    if (res.success) {
      showToast('success', `Topic updated: ${isImportant ? 'Important ⭐' : 'Regular'}`);
      loadSyllabus();
    } else {
      showToast('error', res.error || 'Failed to update topic importance');
    }
  };

  // Logout
  const handleLogout = async () => {
    await DataService.logout();
    setCurrentUser(null);
    setProgressMap({});
    showToast('success', 'Logged out successfully.');
  };

  return (
    <div className="min-h-screen flex flex-col bg-slate-50 text-slate-900 font-sans selection:bg-blue-100 selection:text-blue-900">
      {/* Toast Notification */}
      {toast && (
        <div className="fixed bottom-5 right-5 z-50 animate-bounce-subtle">
          <div
            className={`px-4 py-3 rounded-xl shadow-lg border text-xs font-semibold flex items-center gap-2 max-w-md ${
              toast.type === 'success'
                ? 'bg-slate-900 text-white border-slate-700'
                : 'bg-red-600 text-white border-red-700'
            }`}
          >
            {toast.type === 'success' ? (
              <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
            ) : (
              <AlertCircle className="w-4 h-4 text-white shrink-0" />
            )}
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      {/* Navigation */}
      <Navbar
        currentTab={currentTab}
        setCurrentTab={setCurrentTab}
        currentUser={currentUser}
        onLogout={handleLogout}
        onOpenAuth={() => setIsAuthModalOpen(true)}
      />

      {/* Main Viewport */}
      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 pt-6">
        {/* Loading Spinner for Syllabus */}
        {isLoadingSyllabus && (
          <div className="flex flex-col items-center justify-center p-16 text-slate-500">
            <Loader2 className="w-8 h-8 text-blue-600 animate-spin mb-3" />
            <p className="text-sm font-semibold text-slate-800">Fetching syllabus from Supabase...</p>
            <p className="text-xs text-slate-400 mt-1">Reading subjects, units, topics, and subtopics</p>
          </div>
        )}

        {/* Database Connection Required or Query Error with Retry */}
        {!isLoadingSyllabus && syllabusError && (
          <div className="bg-white border border-slate-200 rounded-2xl p-8 text-center max-w-xl mx-auto my-12 shadow-sm animate-fade-in">
            <div className="w-12 h-12 bg-amber-50 text-amber-600 rounded-xl flex items-center justify-center mx-auto mb-4 border border-amber-200">
              <AlertCircle className="w-6 h-6" />
            </div>
            <h3 className="text-base font-bold text-slate-900 mb-1">
              {!isSupabaseConfigured() ? 'Supabase Connection Required' : 'Database Query Notice'}
            </h3>
            <p className="text-xs text-slate-600 mb-5 max-w-md mx-auto leading-relaxed">
              {syllabusError}
            </p>

            <div className="flex items-center justify-center gap-3">
              <button
                onClick={() => {
                  loadSyllabus();
                  loadResources();
                }}
                className="px-5 py-2.5 bg-blue-600 hover:bg-blue-700 text-white font-semibold text-xs rounded-lg transition-colors flex items-center gap-2 cursor-pointer shadow-xs"
              >
                <RotateCcw className="w-3.5 h-3.5" />
                <span>Retry Connection</span>
              </button>
            </div>

            {!isSupabaseConfigured() && (
              <div className="mt-6 p-4 bg-slate-50 border border-slate-200 rounded-xl text-left text-xs text-slate-600">
                <p className="font-semibold text-slate-800 mb-2">How to configure your database connection:</p>
                <ol className="list-decimal list-inside space-y-1.5 text-[11px] text-slate-500">
                  <li>
                    Define <code className="font-mono text-slate-700 bg-slate-200/60 px-1 py-0.5 rounded">VITE_SUPABASE_URL</code> and <code className="font-mono text-slate-700 bg-slate-200/60 px-1 py-0.5 rounded">VITE_SUPABASE_ANON_KEY</code> in your environment (.env).
                  </li>
                  <li>
                    Execute the migration script in <code className="font-mono text-slate-700 bg-slate-200/60 px-1 py-0.5 rounded">supabase/migrations/</code> on your Supabase project.
                  </li>
                  <li>
                    Click <span className="font-medium text-slate-700">Retry Connection</span> above to load your live syllabus data.
                  </li>
                </ol>
              </div>
            )}
          </div>
        )}

        {/* Main Tabs when Syllabus is Loaded */}
        {!isLoadingSyllabus && !syllabusError && (
          <>
            {currentTab === 'dashboard' && currentUser && (
              <StudentDashboard
                currentUser={currentUser}
                syllabus={syllabus}
                progressSummary={progressSummary}
                progressMap={progressMap}
                resources={resources}
                onNavigateTab={setCurrentTab}
                onToggleTopic={handleToggleTopic}
                onOpenAddResource={() => setIsAddResourceOpen(true)}
              />
            )}

            {currentTab === 'dashboard' && !currentUser && (
              <div className="bg-white rounded-2xl border border-slate-200 p-12 text-center max-w-md mx-auto my-12 shadow-sm">
                <h2 className="text-xl font-bold text-slate-900 mb-2">Student Session Required</h2>
                <p className="text-xs text-slate-500 mb-6 leading-relaxed">
                  Sign in or create an account with your college roll number to view and track your private semester syllabus progress.
                </p>
                <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
                  <button
                    onClick={() => setIsAuthModalOpen(true)}
                    className="w-full sm:w-auto px-6 py-2.5 bg-blue-600 text-white rounded-lg text-xs font-semibold hover:bg-blue-700 shadow-sm transition-colors cursor-pointer"
                  >
                    Sign In / Register
                  </button>
                  <button
                    onClick={() => setCurrentTab('syllabus')}
                    className="w-full sm:w-auto px-6 py-2.5 bg-slate-100 text-slate-700 rounded-lg text-xs font-semibold hover:bg-slate-200 transition-colors cursor-pointer"
                  >
                    Browse Syllabus First
                  </button>
                </div>
              </div>
            )}

            {currentTab === 'syllabus' && (
              <SyllabusExplorer
                syllabus={syllabus}
                currentUser={currentUser || ({} as Profile)}
                progressMap={progressMap}
                savingItems={savingItems}
                onToggleTopic={handleToggleTopic}
                onToggleSubtopic={handleToggleSubtopic}
                onToggleImportant={handleToggleImportant}
                onOpenAddModal={() => setCurrentTab('admin')}
              />
            )}

            {currentTab === 'important' && (
              <ImportantTopicsView
                syllabus={syllabus}
                currentUser={currentUser || ({} as Profile)}
                progressMap={progressMap}
                savingItems={savingItems}
                onToggleTopic={handleToggleTopic}
                onToggleImportant={handleToggleImportant}
              />
            )}

            {currentTab === 'resources' && (
              <SharedResourcesView
                resources={resources}
                syllabus={syllabus}
                currentUser={currentUser || ({} as Profile)}
                onOpenAddModal={() => setIsAddResourceOpen(true)}
                onRefreshResources={loadResources}
              />
            )}

            {currentTab === 'admin' && currentUser && (
              <AdminPanel
                currentUser={currentUser}
                syllabus={syllabus}
                resources={resources}
                onRefreshSyllabus={loadSyllabus}
                onRefreshResources={loadResources}
              />
            )}
          </>
        )}
      </main>

      {/* Modals */}
      <LoginModal
        isOpen={isAuthModalOpen}
        onClose={() => setIsAuthModalOpen(false)}
        onLoginSuccess={(user) => {
          setCurrentUser(user);
          showToast('success', `Welcome, ${user.display_name}! Session connected.`);
        }}
      />

      {currentUser && (
        <AddResourceModal
          isOpen={isAddResourceOpen}
          onClose={() => setIsAddResourceOpen(false)}
          syllabus={syllabus}
          currentUser={currentUser}
          onResourceAdded={() => {
            loadResources();
            showToast('success', 'Study material successfully shared!');
          }}
        />
      )}

      {/* Footer */}
      <footer className="mt-auto border-t border-slate-200 bg-white py-6 text-xs text-slate-500">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div>
            <span className="font-semibold text-slate-800">Smart Study Tracker</span>
            <span className="mx-2">·</span>
            <span>Academic Syllabus & Record-Isolated Progress System</span>
          </div>

          <div className="flex items-center gap-4 text-[11px] text-slate-400">
            <span>PostgreSQL Row Level Security</span>
            <span>·</span>
            <span>Supabase Storage</span>
            <span>·</span>
            <span>Live Database Records</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
