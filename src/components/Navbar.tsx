import React from 'react';
import { BookOpen, Star, FolderGit2, HardDrive } from 'lucide-react';

interface NavbarProps {
  currentTab: 'dashboard' | 'syllabus' | 'important' | 'resources';
  setCurrentTab: (tab: 'dashboard' | 'syllabus' | 'important' | 'resources') => void;
  progressCount?: number;
  totalTopicsCount?: number;
}

export const Navbar: React.FC<NavbarProps> = ({
  currentTab,
  setCurrentTab,
  progressCount,
  totalTopicsCount,
}) => {
  return (
    <header className="sticky top-0 z-40 bg-white/95 backdrop-blur-md border-b border-slate-200">
      {/* Top Bar: Zone 1 (Brand) — Zone 2 (Nav Links) — Zone 3 (Local Storage Status) */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-8">
        {/* Zone 1: Brand Wordmark */}
        <button
          onClick={() => setCurrentTab('dashboard')}
          className="flex items-center gap-2.5 text-left text-slate-900 group whitespace-nowrap shrink-0 cursor-pointer"
        >
          <div className="w-9 h-9 rounded-lg bg-blue-600 flex items-center justify-center text-white font-bold shadow-sm">
            <BookOpen className="w-5 h-5" />
          </div>
          <div>
            <span className="text-base font-bold tracking-tight text-slate-900">
              Smart Study Tracker
            </span>
            <span className="block text-[11px] text-slate-500 font-medium">
              Academic Syllabus & Progress
            </span>
          </div>
        </button>

        {/* Zone 2: Navigation Links */}
        <nav className="hidden lg:flex items-center gap-7 text-sm font-medium text-slate-600">
          <button
            onClick={() => setCurrentTab('dashboard')}
            className={`whitespace-nowrap shrink-0 transition-colors py-1 cursor-pointer ${
              currentTab === 'dashboard'
                ? 'text-blue-600 font-semibold border-b-2 border-blue-600'
                : 'hover:text-slate-900'
            }`}
          >
            Dashboard
          </button>

          <button
            onClick={() => setCurrentTab('syllabus')}
            className={`whitespace-nowrap shrink-0 transition-colors py-1 cursor-pointer ${
              currentTab === 'syllabus'
                ? 'text-blue-600 font-semibold border-b-2 border-blue-600'
                : 'hover:text-slate-900'
            }`}
          >
            Syllabus Explorer
          </button>

          <button
            onClick={() => setCurrentTab('important')}
            className={`flex items-center gap-1.5 whitespace-nowrap shrink-0 transition-colors py-1 cursor-pointer ${
              currentTab === 'important'
                ? 'text-blue-600 font-semibold border-b-2 border-blue-600'
                : 'hover:text-slate-900'
            }`}
          >
            <Star className="w-4 h-4 text-amber-500 fill-amber-500" />
            <span>Important Topics</span>
          </button>

          <button
            onClick={() => setCurrentTab('resources')}
            className={`flex items-center gap-1.5 whitespace-nowrap shrink-0 transition-colors py-1 cursor-pointer ${
              currentTab === 'resources'
                ? 'text-blue-600 font-semibold border-b-2 border-blue-600'
                : 'hover:text-slate-900'
            }`}
          >
            <FolderGit2 className="w-4 h-4" />
            <span>Shared Resources</span>
          </button>
        </nav>

        {/* Zone 3: Storage & Access Badge */}
        <div className="flex items-center gap-3 shrink-0">
          <div
            className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs font-medium"
            title="Your checklist progress is stored locally in your browser. No sign-in required."
          >
            <HardDrive className="w-3.5 h-3.5 text-emerald-600" />
            <span className="hidden sm:inline">Browser-Local Storage</span>
            {typeof progressCount === 'number' && typeof totalTopicsCount === 'number' && totalTopicsCount > 0 && (
              <span className="font-mono text-emerald-700 font-semibold pl-1 border-l border-emerald-300">
                {progressCount}/{totalTopicsCount}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Mobile Sub-Navigation Bar */}
      <div className="lg:hidden flex items-center justify-around border-t border-slate-200 bg-slate-50 px-2 py-2 text-xs font-medium text-slate-600">
        <button
          onClick={() => setCurrentTab('dashboard')}
          className={`px-2.5 py-1.5 rounded-md ${currentTab === 'dashboard' ? 'bg-white text-blue-600 shadow-sm' : ''}`}
        >
          Dashboard
        </button>
        <button
          onClick={() => setCurrentTab('syllabus')}
          className={`px-2.5 py-1.5 rounded-md ${currentTab === 'syllabus' ? 'bg-white text-blue-600 shadow-sm' : ''}`}
        >
          Syllabus
        </button>
        <button
          onClick={() => setCurrentTab('important')}
          className={`px-2.5 py-1.5 rounded-md flex items-center gap-1 ${currentTab === 'important' ? 'bg-white text-blue-600 shadow-sm' : ''}`}
        >
          <Star className="w-3.5 h-3.5 text-amber-500 fill-amber-500" />
          <span>Exam Prep</span>
        </button>
        <button
          onClick={() => setCurrentTab('resources')}
          className={`px-2.5 py-1.5 rounded-md ${currentTab === 'resources' ? 'bg-white text-blue-600 shadow-sm' : ''}`}
        >
          Resources
        </button>
      </div>
    </header>
  );
};
