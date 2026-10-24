import React from 'react';
import {
  CheckCircle2,
  Star,
  BookOpen,
  ArrowRight,
  TrendingUp,
  Award,
  FileText,
  ExternalLink,
import { HardDrive, RotateCcw } from 'lucide-react';
import { SemesterWithSubjects, ProgressSummary, StudyResource } from '../types/database';

interface StudentDashboardProps {
  syllabus: SemesterWithSubjects[];
  progressSummary: ProgressSummary;
  progressMap: Record<string, boolean>;
  resources: StudyResource[];
  onNavigateTab: (tab: 'dashboard' | 'syllabus' | 'important' | 'resources') => void;
  onToggleTopic: (topicId: string, isCompleted: boolean) => void;
  onOpenAddResource: () => void;
  onResetProgress?: () => void;
}

export const StudentDashboard: React.FC<StudentDashboardProps> = ({
  syllabus,
  progressSummary,
  progressMap,
  resources,
  onNavigateTab,
  onToggleTopic,
  onOpenAddResource,
  onResetProgress,
}) => {
  // Collect all important topics and check which ones are pending
  const importantTopics: {
    id: string;
    title: string;
    subjectName: string;
    subjectCode: string;
    colorCode: string;
    estimatedHours: number;
    isCompleted: boolean;
  }[] = [];

  syllabus.forEach((sem) => {
    sem.subjects.forEach((sub) => {
      sub.units.forEach((u) => {
        u.topics.forEach((t) => {
          if (t.is_important) {
            importantTopics.push({
              id: t.id,
              title: t.title,
              subjectName: sub.name,
              subjectCode: sub.code,
              colorCode: sub.color_code,
              estimatedHours: t.estimated_hours,
              isCompleted: Boolean(progressMap[t.id]),
            });
          }
        });
      });
    });
  });

  const pendingImportant = importantTopics.filter((t) => !t.isCompleted);
  const recentResources = resources.slice(0, 3);

  return (
    <div className="space-y-8 animate-fade-in pb-12">
      {/* Hero Welcome Banner */}
      <div className="relative rounded-2xl overflow-hidden bg-slate-900 border border-slate-800 text-white shadow-md">
        <div className="absolute inset-0 z-0 opacity-25">
          <img
            src="/src/assets/images/study_dashboard_hero_1792755615081.jpg"
            alt="Study Workspace"
            className="w-full h-full object-cover"
            referrerPolicy="no-referrer"
          />
        </div>
        <div className="relative z-10 p-6 sm:p-8 lg:p-10 flex flex-col md:flex-row items-start md:items-center justify-between gap-6">
          <div className="max-w-2xl">
            <div className="flex items-center gap-2 text-xs text-blue-400 font-mono mb-2">
              <span>Smart Study Tracker</span>
              <span>·</span>
              <span>Academic Syllabus Dashboard</span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white mb-2">
              Semester Study Dashboard
            </h1>
            <p className="text-slate-300 text-sm leading-relaxed">
              Track your syllabus coverage, check off high-yield examination topics, and organize your academic semester.
            </p>
          </div>

          <div className="bg-slate-800/80 backdrop-blur-sm border border-slate-700/80 rounded-xl p-4 shrink-0 flex items-center gap-4">
            <div className="relative w-16 h-16 flex items-center justify-center">
              <svg className="w-full h-full transform -rotate-90" viewBox="0 0 36 36">
                <path
                  className="text-slate-700"
                  strokeWidth="3.5"
                  stroke="currentColor"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                />
                <path
                  className="text-blue-500 transition-all duration-700 ease-out"
                  strokeDasharray={`${progressSummary.overallPercentage}, 100`}
                  strokeWidth="3.5"
                  strokeLinecap="round"
                  stroke="currentColor"
                  fill="none"
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                />
              </svg>
              <span className="absolute text-sm font-bold font-mono tabular-nums text-white">
                {progressSummary.overallPercentage}%
              </span>
            </div>
            <div>
              <div className="text-xs text-slate-400 font-medium">Overall Progress</div>
              <div className="text-sm font-semibold text-white font-mono tabular-nums">
                {progressSummary.completedTopics} of {progressSummary.totalTopics} Topics
              </div>
              <div className="text-[11px] text-slate-400">
                {progressSummary.completedSubtopics} subtopics completed
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Local Storage Clarification Banner */}
      <div className="bg-blue-50 border border-blue-200 rounded-xl p-4 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 text-xs text-blue-900 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-blue-100 flex items-center justify-center text-blue-700 shrink-0">
            <HardDrive className="w-4 h-4" />
          </div>
          <div>
            <span className="font-semibold text-blue-950">Local Browser Progress Active:</span>{' '}
            <span className="text-blue-800">
              Your completion checkboxes and study metrics are saved safely in your browser (no login required). Academic syllabus is loaded live from Supabase.
            </span>
          </div>
        </div>
        {onResetProgress && (
          <button
            onClick={onResetProgress}
            className="flex items-center gap-1.5 text-xs font-semibold text-blue-700 hover:text-blue-800 bg-white border border-blue-200 hover:border-blue-300 px-3 py-1.5 rounded-lg shadow-xs transition-colors shrink-0 cursor-pointer"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            <span>Reset Progress</span>
          </button>
        )}
      </div>

      {/* KPI Quantitative Metrics Grid */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm flex items-start justify-between">
          <div>
            <div className="text-xs font-medium text-slate-500 mb-1">Total Topics Mastered</div>
            <div className="text-2xl font-bold text-slate-900 font-mono tabular-nums">
              {progressSummary.completedTopics}
              <span className="text-xs font-normal text-slate-400 ml-1">/ {progressSummary.totalTopics}</span>
            </div>
            <div className="text-xs text-slate-500 mt-1 flex items-center gap-1">
              <TrendingUp className="w-3.5 h-3.5 text-emerald-600" />
              <span>Independent Student Record</span>
            </div>
          </div>
          <div className="w-10 h-10 rounded-lg bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
            <CheckCircle2 className="w-5 h-5" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm flex items-start justify-between">
          <div>
            <div className="text-xs font-medium text-slate-500 mb-1">Important Exam Topics</div>
            <div className="text-2xl font-bold text-amber-600 font-mono tabular-nums">
              {progressSummary.importantCompleted}
              <span className="text-xs font-normal text-slate-400 ml-1">/ {progressSummary.importantTotal}</span>
            </div>
            <div className="text-xs text-slate-500 mt-1 flex items-center gap-1">
              <Star className="w-3.5 h-3.5 text-amber-500 fill-amber-500" />
              <span>Faculty High-Yield Marker</span>
            </div>
          </div>
          <div className="w-10 h-10 rounded-lg bg-amber-50 text-amber-600 flex items-center justify-center shrink-0">
            <Award className="w-5 h-5" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm flex items-start justify-between">
          <div>
            <div className="text-xs font-medium text-slate-500 mb-1">Active Subjects</div>
            <div className="text-2xl font-bold text-slate-900 font-mono tabular-nums">
              {progressSummary.subjectProgress.length}
            </div>
            <div className="text-xs text-slate-500 mt-1">
              Enrolled Curriculum
            </div>
          </div>
          <div className="w-10 h-10 rounded-lg bg-indigo-50 text-indigo-600 flex items-center justify-center shrink-0">
            <BookOpen className="w-5 h-5" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm flex items-start justify-between">
          <div>
            <div className="text-xs font-medium text-slate-500 mb-1">Shared Resources</div>
            <div className="text-2xl font-bold text-slate-900 font-mono tabular-nums">
              {resources.length}
            </div>
            <div className="text-xs text-slate-500 mt-1">
              PDFs, Lectures & Links
            </div>
          </div>
          <div className="w-10 h-10 rounded-lg bg-emerald-50 text-emerald-600 flex items-center justify-center shrink-0">
            <FileText className="w-5 h-5" />
          </div>
        </div>
      </div>

      {/* Subject-Wise Progress Cards */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-lg font-bold text-slate-900">Subject-Wise Completion</h2>
            <p className="text-xs text-slate-500">Real-time status based on your authenticated database records</p>
          </div>
          <button
            onClick={() => onNavigateTab('syllabus')}
            className="text-xs font-semibold text-blue-600 hover:text-blue-700 flex items-center gap-1 group cursor-pointer"
          >
            <span>Explore Full Syllabus</span>
            <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-0.5 transition-transform" />
          </button>
        </div>

        {progressSummary.subjectProgress.length === 0 ? (
          <div className="bg-white p-8 rounded-xl border border-slate-200 text-center text-xs text-slate-500">
            No subjects loaded. Please ensure syllabus data has been populated.
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {progressSummary.subjectProgress.map((sub) => (
              <div
                key={sub.subjectId}
                className="bg-white p-5 rounded-xl border border-slate-200 shadow-sm hover:border-slate-300 transition-colors"
              >
                <div className="flex items-center justify-between mb-3">
                  <span
                    className="text-xs font-bold font-mono px-2 py-0.5 rounded text-white"
                    style={{ backgroundColor: sub.colorCode }}
                  >
                    {sub.subjectCode}
                  </span>
                  <span className="text-sm font-bold font-mono tabular-nums text-slate-900">
                    {sub.percentage}%
                  </span>
                </div>

                <h3 className="text-sm font-semibold text-slate-900 mb-3 line-clamp-1">
                  {sub.subjectName}
                </h3>

                {/* Progress Bar */}
                <div className="w-full bg-slate-100 rounded-full h-2 mb-2 overflow-hidden">
                  <div
                    className="h-full rounded-full transition-all duration-500"
                    style={{
                      width: `${sub.percentage}%`,
                      backgroundColor: sub.colorCode,
                    }}
                  />
                </div>

                <div className="flex items-center justify-between text-xs text-slate-500 font-mono tabular-nums">
                  <span>{sub.completed} completed</span>
                  <span>{sub.total} total</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Two Column Section: Priority Exam Topics + Recent Resources */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
        {/* Left Column (7 cols): High-Yield Exam Topics Pending */}
        <div className="lg:col-span-7 bg-white rounded-xl border border-slate-200 p-6 shadow-sm">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Star className="w-5 h-5 text-amber-500 fill-amber-500" />
              <div>
                <h2 className="text-base font-bold text-slate-900">Important Topics to Revise</h2>
                <p className="text-xs text-slate-500">Designated by faculty for upcoming examinations</p>
              </div>
            </div>
            <button
              onClick={() => onNavigateTab('important')}
              className="text-xs font-semibold text-blue-600 hover:text-blue-700 cursor-pointer"
            >
              View All ({importantTopics.length})
            </button>
          </div>

          {importantTopics.length === 0 ? (
            <div className="py-8 text-center bg-slate-50 rounded-lg border border-slate-100">
              <Star className="w-8 h-8 text-slate-300 mx-auto mb-2" />
              <p className="text-sm font-semibold text-slate-700">No Important Topics designated yet</p>
              <p className="text-xs text-slate-500 mt-1">
                Faculty can mark key exam questions in the Syllabus or Admin console.
              </p>
            </div>
          ) : pendingImportant.length === 0 ? (
            <div className="py-8 text-center bg-slate-50 rounded-lg border border-slate-100">
              <Award className="w-8 h-8 text-emerald-500 mx-auto mb-2" />
              <p className="text-sm font-semibold text-slate-800">All Important Topics Mastered!</p>
              <p className="text-xs text-slate-500 mt-1">
                You have completed all {importantTopics.length} high-yield examination topics.
              </p>
            </div>
          ) : (
            <div className="divide-y divide-slate-100">
              {pendingImportant.slice(0, 5).map((topic) => (
                <div
                  key={topic.id}
                  className="py-3 flex items-center justify-between gap-4 group hover:bg-slate-50/80 px-2 rounded-lg transition-colors"
                >
                  <div className="flex items-start gap-3 min-w-0">
                    <input
                      type="checkbox"
                      checked={topic.isCompleted}
                      onChange={(e) => onToggleTopic(topic.id, e.target.checked)}
                      className="mt-1 w-4 h-4 text-blue-600 rounded border-slate-300 focus:ring-blue-500 cursor-pointer"
                      id={`dash-topic-${topic.id}`}
                    />
                    <label
                      htmlFor={`dash-topic-${topic.id}`}
                      className="text-sm font-medium text-slate-800 group-hover:text-blue-600 cursor-pointer truncate"
                    >
                      {topic.title}
                      <span className="block text-xs text-slate-400 font-normal">
                        {topic.subjectCode} · {topic.estimatedHours} hrs estimated
                      </span>
                    </label>
                  </div>

                  <span className="shrink-0 text-[11px] font-medium text-amber-700 bg-amber-50 border border-amber-200 px-2 py-0.5 rounded-full flex items-center gap-1">
                    <Star className="w-3 h-3 fill-amber-500 text-amber-500" />
                    <span>Important</span>
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Right Column (5 cols): Shared Resources & Session Info */}
        <div className="lg:col-span-5 space-y-6">
          <div className="bg-white rounded-xl border border-slate-200 p-6 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h2 className="text-base font-bold text-slate-900">Recent Study Resources</h2>
                <p className="text-xs text-slate-500">Shared by faculty & peers</p>
              </div>
              <button
                onClick={onOpenAddResource}
                className="text-xs font-semibold px-2.5 py-1 bg-blue-50 text-blue-600 hover:bg-blue-100 rounded-lg transition-colors cursor-pointer"
              >
                + Share Material
              </button>
            </div>

            {recentResources.length === 0 ? (
              <div className="p-6 text-center bg-slate-50 rounded-lg border border-slate-100">
                <FileText className="w-6 h-6 text-slate-300 mx-auto mb-2" />
                <p className="text-xs font-semibold text-slate-700">No resources shared yet</p>
                <p className="text-[11px] text-slate-400 mt-0.5">
                  Be the first to share study notes or reference documents.
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                {recentResources.map((res) => (
                  <div
                    key={res.id}
                    className="p-3 border border-slate-100 rounded-lg hover:border-slate-200 bg-slate-50/50 hover:bg-slate-50 transition-colors"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="text-xs font-semibold text-slate-900 line-clamp-1">
                        {res.title}
                      </h3>
                      <span className="text-[10px] font-bold uppercase text-slate-600 font-mono">
                        {res.resource_type}
                      </span>
                    </div>
                    <p className="text-[11px] text-slate-500 line-clamp-2 mt-1">
                      {res.description || 'Shared study material for semester revision.'}
                    </p>
                    <div className="flex items-center justify-between mt-2 pt-2 border-t border-slate-200/60 text-[10px] text-slate-500">
                      <span>By {res.uploader_name}</span>
                      {res.external_url ? (
                        <a
                          href={res.external_url}
                          target="_blank"
                          rel="noreferrer"
                          className="text-blue-600 hover:underline flex items-center gap-0.5"
                        >
                          <span>Open</span>
                          <ExternalLink className="w-3 h-3" />
                        </a>
                      ) : (
                        <span className="text-slate-400">Document</span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}

            <button
              onClick={() => onNavigateTab('resources')}
              className="w-full mt-4 py-2 text-xs font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors text-center cursor-pointer"
            >
              Browse All Shared Resources →
            </button>
          </div>

          {/* Storage & Privacy Info Card */}
          <div className="bg-slate-50 rounded-xl border border-slate-200 p-4 text-xs text-slate-600">
            <div className="font-semibold text-slate-800 mb-1 flex items-center gap-1.5">
              <HardDrive className="w-3.5 h-3.5 text-blue-600" />
              <span>Storage & Privacy</span>
            </div>
            <p className="text-[11px] text-slate-500 leading-relaxed mb-2">
              All checklist selections are stored privately in your browser's local storage. No sign-in or tracking cookies required.
            </p>
            <div className="space-y-1 font-mono text-[11px] text-slate-500">
              <div>Mode: <span className="text-emerald-600 font-semibold">Browser-Local Storage</span></div>
              <div>Database: <span className="text-blue-600 font-semibold">Live Supabase Syllabus</span></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
