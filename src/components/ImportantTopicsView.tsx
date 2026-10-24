import { SemesterWithSubjects } from '../types/database';

interface ImportantTopicsViewProps {
  syllabus: SemesterWithSubjects[];
  progressMap: Record<string, boolean>;
  savingItems: Record<string, boolean>;
  onToggleTopic: (topicId: string, isCompleted: boolean) => Promise<void>;
}

export const ImportantTopicsView: React.FC<ImportantTopicsViewProps> = ({
  syllabus,
  progressMap,
  savingItems,
  onToggleTopic,
}) => {
  const [selectedSubjectId, setSelectedSubjectId] = useState<string>('all');

  // Extract all important topics grouped by subject
  const importantBySubject: {
    subjectId: string;
    subjectName: string;
    subjectCode: string;
    colorCode: string;
    topics: {
      id: string;
      unitTitle: string;
      title: string;
      description: string | null;
      estimatedHours: number;
      isCompleted: boolean;
      subtopicsCount: number;
    }[];
  }[] = [];

  let grandTotalImportant = 0;
  let grandCompletedImportant = 0;
  let totalEstimatedHours = 0;

  syllabus.forEach((sem) => {
    sem.subjects.forEach((sub) => {
      const subjectTopics: {
        id: string;
        unitTitle: string;
        title: string;
        description: string | null;
        estimatedHours: number;
        isCompleted: boolean;
        subtopicsCount: number;
      }[] = [];

      sub.units.forEach((u) => {
        u.topics.forEach((t) => {
          if (t.is_important) {
            grandTotalImportant++;
            totalEstimatedHours += Number(t.estimated_hours || 0);

            const isDone = Boolean(progressMap[t.id]);
            if (isDone) grandCompletedImportant++;

            subjectTopics.push({
              id: t.id,
              unitTitle: u.title,
              title: t.title,
              description: t.description,
              estimatedHours: t.estimated_hours,
              isCompleted: isDone,
              subtopicsCount: t.subtopics?.length || 0,
            });
          }
        });
      });

      if (subjectTopics.length > 0) {
        importantBySubject.push({
          subjectId: sub.id,
          subjectName: sub.name,
          subjectCode: sub.code,
          colorCode: sub.color_code,
          topics: subjectTopics,
        });
      }
    });
  });

  const filteredGroups =
    selectedSubjectId === 'all'
      ? importantBySubject
      : importantBySubject.filter((g) => g.subjectId === selectedSubjectId);

  const completionRate =
    grandTotalImportant > 0
      ? Math.round((grandCompletedImportant / grandTotalImportant) * 100)
      : 0;

  return (
    <div className="space-y-6 animate-fade-in pb-16">
      {/* Header Banner */}
      <div className="bg-gradient-to-r from-amber-500/10 via-amber-400/5 to-transparent border border-amber-200/80 rounded-2xl p-6 sm:p-8">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div>
            <div className="flex items-center gap-2 text-xs font-semibold text-amber-800 uppercase tracking-wider mb-2">
              <Star className="w-4 h-4 fill-amber-500 text-amber-500" />
              <span>Faculty Examination Priorities</span>
            </div>
            <h1 className="text-2xl font-bold tracking-tight text-slate-900 mb-1">
              Important Examination Topics ⭐
            </h1>
            <p className="text-xs sm:text-sm text-slate-600 max-w-xl">
              High-frequency, core examination concepts curated directly by academic faculty. Check off topics as you revise them.
            </p>
          </div>

          {/* Quick Metrics */}
          <div className="flex items-center gap-4 bg-white/90 backdrop-blur-sm border border-amber-200 p-4 rounded-xl shadow-xs shrink-0">
            <div className="text-center px-2">
              <div className="text-2xl font-bold font-mono text-amber-700 tabular-nums">
                {grandCompletedImportant}/{grandTotalImportant}
              </div>
              <div className="text-[11px] text-slate-500 font-medium">Mastered</div>
            </div>
            <div className="w-px h-8 bg-slate-200"></div>
            <div className="text-center px-2">
              <div className="text-2xl font-bold font-mono text-slate-800 tabular-nums">
                {completionRate}%
              </div>
              <div className="text-[11px] text-slate-500 font-medium">Exam Ready</div>
            </div>
            <div className="w-px h-8 bg-slate-200"></div>
            <div className="text-center px-2">
              <div className="text-2xl font-bold font-mono text-slate-800 tabular-nums">
                {totalEstimatedHours}h
              </div>
              <div className="text-[11px] text-slate-500 font-medium">Prep Time</div>
            </div>
          </div>
        </div>
      </div>

      {/* Subject Filter Bar */}
      <div className="flex items-center justify-between gap-4 flex-wrap bg-white p-3 rounded-xl border border-slate-200 shadow-sm">
        <div className="flex items-center gap-1.5 overflow-x-auto py-1">
          <button
            onClick={() => setSelectedSubjectId('all')}
            className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors whitespace-nowrap ${
              selectedSubjectId === 'all'
                ? 'bg-slate-900 text-white'
                : 'text-slate-600 hover:bg-slate-100'
            }`}
          >
            All Subjects ({grandTotalImportant})
          </button>
          {importantBySubject.map((sub) => (
            <button
              key={sub.subjectId}
              onClick={() => setSelectedSubjectId(sub.subjectId)}
              className={`px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors whitespace-nowrap ${
                selectedSubjectId === sub.subjectId
                  ? 'bg-slate-900 text-white'
                  : 'text-slate-600 hover:bg-slate-100'
              }`}
            >
              {sub.subjectCode} ({sub.topics.length})
            </button>
          ))}
        </div>

        {currentUser.role === 'admin' && (
          <div className="text-xs text-purple-700 bg-purple-50 px-2.5 py-1 rounded-md font-medium flex items-center gap-1">
            <ShieldCheck className="w-3.5 h-3.5" />
            <span>Admin Mode: You can toggle Important status</span>
          </div>
        )}
      </div>

      {/* Topics Content */}
      {filteredGroups.length === 0 ? (
        <div className="bg-white p-12 text-center rounded-xl border border-slate-200">
          <Star className="w-10 h-10 text-slate-300 mx-auto mb-2" />
          <h3 className="text-sm font-semibold text-slate-700">No Important Topics designated</h3>
          <p className="text-xs text-slate-500 mt-1">
            Faculty members can mark high-priority syllabus topics with the ⭐ badge.
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          {filteredGroups.map((group) => {
            const groupCompleted = group.topics.filter((t) => t.isCompleted).length;
            const groupPercent = Math.round((groupCompleted / group.topics.length) * 100);

            return (
              <div
                key={group.subjectId}
                className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden"
              >
                {/* Group Header */}
                <div className="px-6 py-4 bg-slate-50/70 border-b border-slate-200 flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <span
                      className="text-xs font-bold font-mono px-2.5 py-1 rounded text-white"
                      style={{ backgroundColor: group.colorCode }}
                    >
                      {group.subjectCode}
                    </span>
                    <h2 className="text-base font-bold text-slate-900">{group.subjectName}</h2>
                  </div>

                  <div className="text-xs font-mono font-medium text-slate-600 tabular-nums">
                    {groupCompleted} / {group.topics.length} Mastered ({groupPercent}%)
                  </div>
                </div>

                {/* Topics List */}
                <div className="divide-y divide-slate-100">
                  {group.topics.map((t) => {
                    const isSaving = Boolean(savingItems[t.id]);

                    return (
                      <div
                        key={t.id}
                        className={`p-4 flex items-start justify-between gap-4 transition-colors ${
                          t.isCompleted ? 'bg-amber-50/30' : 'hover:bg-slate-50/80'
                        }`}
                      >
                        <div className="flex items-start gap-3 flex-1 min-w-0">
                          <input
                            type="checkbox"
                            checked={t.isCompleted}
                            onChange={(e) => onToggleTopic(t.id, e.target.checked)}
                            className="mt-1 w-4 h-4 text-blue-600 rounded border-slate-300 focus:ring-blue-500 cursor-pointer"
                            id={`imp-${t.id}`}
                          />
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2 flex-wrap">
                              <label
                                htmlFor={`imp-${t.id}`}
                                className={`text-sm font-semibold cursor-pointer ${
                                  t.isCompleted ? 'line-through text-slate-400' : 'text-slate-900'
                                }`}
                              >
                                {t.title}
                              </label>

                              <span className="text-[11px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 px-2 py-0.5 rounded-full flex items-center gap-1 shrink-0">
                                <Star className="w-3 h-3 fill-amber-500 text-amber-500" />
                                <span>Exam Question Probable</span>
                              </span>

                              <span className="text-xs text-slate-400 flex items-center gap-1 font-mono">
                                <Clock className="w-3 h-3" />
                                <span>{t.estimatedHours}h</span>
                              </span>
                            </div>

                            <div className="text-xs text-slate-500 mt-1">
                              {t.unitTitle}
                              {t.description && ` · ${t.description}`}
                            </div>
                          </div>
                        </div>

                        {currentUser.role === 'admin' && onToggleImportant && (
                          <button
                            onClick={() => onToggleImportant(t.id, false)}
                            className="text-xs text-red-600 hover:text-red-700 font-medium px-2 py-1 rounded hover:bg-red-50 transition-colors shrink-0"
                            title="Unmark from Important examination topics"
                          >
                            Remove ⭐
                          </button>
                        )}
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
