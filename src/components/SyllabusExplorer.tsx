import React, { useState, useMemo, useEffect } from 'react';
import {
  ChevronDown,
  ChevronRight,
  Search,
  Star,
  Clock,
  Layers,
  Plus,
  Loader2,
import { SemesterWithSubjects } from '../types/database';

interface SyllabusExplorerProps {
  syllabus: SemesterWithSubjects[];
  progressMap: Record<string, boolean>;
  savingItems: Record<string, boolean>;
  onToggleTopic: (topicId: string, isCompleted: boolean) => Promise<void>;
  onToggleSubtopic: (subtopicId: string, isCompleted: boolean) => Promise<void>;
}

export const SyllabusExplorer: React.FC<SyllabusExplorerProps> = ({
  syllabus,
  progressMap,
  savingItems,
  onToggleTopic,
  onToggleSubtopic,
}) => {
  const [selectedSemesterId, setSelectedSemesterId] = useState<string>(
    syllabus[0]?.id || ''
  );
  const [selectedSubjectId, setSelectedSubjectId] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [onlyImportant, setOnlyImportant] = useState(false);

  // Accordion state: map unitId -> boolean
  const [expandedUnits, setExpandedUnits] = useState<Record<string, boolean>>({});

  // When syllabus loads or changes, ensure selectedSemesterId is set
  useEffect(() => {
    if (!selectedSemesterId && syllabus.length > 0) {
      setSelectedSemesterId(syllabus[0].id);
    }
  }, [syllabus, selectedSemesterId]);

  // Expand first unit by default when semester changes
  useEffect(() => {
    if (syllabus.length > 0) {
      const activeSem = syllabus.find((s) => s.id === selectedSemesterId) || syllabus[0];
      const initialExpanded: Record<string, boolean> = {};
      activeSem?.subjects.forEach((sub) => {
        if (sub.units[0]) {
          initialExpanded[sub.units[0].id] = true;
        }
      });
      setExpandedUnits((prev) => (Object.keys(prev).length === 0 ? initialExpanded : prev));
    }
  }, [selectedSemesterId, syllabus]);

  const toggleUnit = (unitId: string) => {
    setExpandedUnits((prev) => ({
      ...prev,
      [unitId]: !prev[unitId],
    }));
  };

  const expandAll = () => {
    const allExpanded: Record<string, boolean> = {};
    syllabus.forEach((sem) => {
      sem.subjects.forEach((sub) => {
        sub.units.forEach((u) => {
          allExpanded[u.id] = true;
        });
      });
    });
    setExpandedUnits(allExpanded);
  };

  const collapseAll = () => {
    setExpandedUnits({});
  };

  // Find active semester
  const activeSemester =
    syllabus.find((s) => s.id === selectedSemesterId) || syllabus[0];

  // Available subjects for the active semester
  const availableSubjects = activeSemester?.subjects || [];

  // Filtered subjects and units based on search and filters
  const filteredSubjects = useMemo(() => {
    if (!activeSemester) return [];

    let subjectsToFilter = activeSemester.subjects;
    if (selectedSubjectId !== 'all') {
      subjectsToFilter = subjectsToFilter.filter((s) => s.id === selectedSubjectId);
    }

    const q = searchQuery.toLowerCase().trim();

    return subjectsToFilter
      .map((sub) => {
        const filteredUnits = sub.units
          .map((u) => {
            const filteredTopics = u.topics.filter((top) => {
              // Important filter
              if (onlyImportant && !top.is_important) return false;

              // Search query filter
              if (!q) return true;
              const matchTopic = top.title.toLowerCase().includes(q);
              const matchDesc = top.description ? top.description.toLowerCase().includes(q) : false;
              const matchSubtopics = top.subtopics?.some((st) =>
                st.title.toLowerCase().includes(q)
              );
              const matchUnit = u.title.toLowerCase().includes(q);
              const matchSubject = sub.name.toLowerCase().includes(q) || sub.code.toLowerCase().includes(q);

              return matchTopic || matchDesc || matchSubtopics || matchUnit || matchSubject;
            });

            return {
              ...u,
              topics: filteredTopics,
            };
          })
          .filter((u) => u.topics.length > 0 || !q);

        return {
          ...sub,
          units: filteredUnits,
        };
      })
      .filter((sub) => sub.units.length > 0 || !q);
  }, [activeSemester, selectedSubjectId, searchQuery, onlyImportant]);

  return (
    <div className="space-y-6 animate-fade-in pb-16">
      {/* Page Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Syllabus Explorer & Checklist
          </h1>
          <p className="text-xs text-slate-500">
            Structured hierarchy: Semester → Subject → Unit → Topic → Subtopics
          </p>
        </div>

        {/* Semester Selection Segmented Control */}
        {syllabus.length > 0 && (
          <div className="flex items-center gap-1.5 p-1 bg-slate-200/70 rounded-lg shrink-0">
            {syllabus.map((sem) => (
              <button
                key={sem.id}
                onClick={() => {
                  setSelectedSemesterId(sem.id);
                  setSelectedSubjectId('all');
                }}
                className={`px-3 py-1.5 text-xs font-semibold rounded-md transition-all cursor-pointer ${
                  selectedSemesterId === sem.id
                    ? 'bg-white text-slate-900 shadow-sm'
                    : 'text-slate-600 hover:text-slate-900'
                }`}
              >
                Semester {sem.semester_number}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Filter Toolbar */}
      <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3">
        {/* Search Input */}
        <div className="relative flex-1">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-2.5" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search subjects, units, topics, or subtopics..."
            className="w-full pl-9 pr-3 py-1.5 text-xs border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              className="absolute right-3 top-2 text-xs text-slate-400 hover:text-slate-600 cursor-pointer"
            >
              Clear
            </button>
          )}
        </div>

        {/* Filters & Toggles */}
        <div className="flex items-center gap-2 flex-wrap">
          {/* Subject Filter Dropdown */}
          <select
            value={selectedSubjectId}
            onChange={(e) => setSelectedSubjectId(e.target.value)}
            className="text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-500/20"
          >
            <option value="all">All Subjects ({availableSubjects.length})</option>
            {availableSubjects.map((s) => (
              <option key={s.id} value={s.id}>
                {s.code}: {s.name}
              </option>
            ))}
          </select>

          {/* Important Topics Toggle */}
          <button
            onClick={() => setOnlyImportant(!onlyImportant)}
            className={`px-3 py-1.5 text-xs font-medium rounded-lg flex items-center gap-1.5 transition-colors border cursor-pointer ${
              onlyImportant
                ? 'bg-amber-50 text-amber-800 border-amber-300 shadow-sm'
                : 'bg-white text-slate-600 border-slate-300 hover:bg-slate-50'
            }`}
          >
            <Star
              className={`w-3.5 h-3.5 ${
                onlyImportant ? 'text-amber-500 fill-amber-500' : 'text-slate-400'
              }`}
            />
            <span>Important Only</span>
          </button>

          {/* Expand / Collapse All */}
          <div className="flex items-center border border-slate-300 rounded-lg overflow-hidden text-xs">
            <button
              onClick={expandAll}
              className="px-2.5 py-1.5 hover:bg-slate-100 text-slate-600 transition-colors cursor-pointer"
            >
              Expand All
            </button>
            <span className="text-slate-300">|</span>
            <button
              onClick={collapseAll}
              className="px-2.5 py-1.5 hover:bg-slate-100 text-slate-600 transition-colors cursor-pointer"
            >
              Collapse
            </button>
          </div>
        </div>
      </div>

      {/* Main Syllabus Hierarchy View */}
      {filteredSubjects.length === 0 ? (
        <div className="bg-white p-12 text-center rounded-xl border border-slate-200">
          <Layers className="w-10 h-10 text-slate-300 mx-auto mb-3" />
          <h3 className="text-base font-semibold text-slate-800">No syllabus items found</h3>
          <p className="text-xs text-slate-500 mt-1 max-w-sm mx-auto">
            {searchQuery || onlyImportant
              ? 'Try adjusting your search query or disabling the Important Only filter.'
              : 'No syllabus records match this semester in your Supabase database.'}
          </p>
          {(searchQuery || onlyImportant) && (
            <button
              onClick={() => {
                setSearchQuery('');
                setOnlyImportant(false);
                setSelectedSubjectId('all');
              }}
              className="mt-4 px-3 py-1.5 text-xs font-medium text-blue-600 bg-blue-50 hover:bg-blue-100 rounded-lg transition-colors cursor-pointer"
            >
              Reset Filters
            </button>
          )}
        </div>
      ) : (
        <div className="space-y-6">
          {filteredSubjects.map((subject) => (
            <div
              key={subject.id}
              className="bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden"
            >
              {/* Subject Title Header */}
              <div
                className="px-6 py-4 flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-200 bg-slate-50/70"
              >
                <div className="flex items-center gap-3">
                  <span
                    className="text-xs font-bold font-mono px-2.5 py-1 rounded text-white shadow-xs"
                    style={{ backgroundColor: subject.color_code || '#2563EB' }}
                  >
                    {subject.code}
                  </span>
                  <div>
                    <h2 className="text-base font-bold text-slate-900">{subject.name}</h2>
                    <span className="text-xs text-slate-500">
                      {subject.credits} Academic Credits · {subject.units.length} Units
                    </span>
                  </div>
                </div>

                </div>
              </div>

              {/* Units Accordion */}
              <div className="divide-y divide-slate-200">
                {subject.units.map((unit) => {
                  const isExpanded = expandedUnits[unit.id] ?? false;
                  const totalUnitTopics = unit.topics.length;
                  const completedUnitTopics = unit.topics.filter(
                    (t) => progressMap[t.id]
                  ).length;
                  const unitPercent =
                    totalUnitTopics > 0
                      ? Math.round((completedUnitTopics / totalUnitTopics) * 100)
                      : 0;

                  return (
                    <div key={unit.id} className="transition-colors">
                      {/* Unit Header Accordion Trigger */}
                      <button
                        onClick={() => toggleUnit(unit.id)}
                        className="w-full px-6 py-3.5 flex items-center justify-between text-left hover:bg-slate-50/80 transition-colors cursor-pointer"
                      >
                        <div className="flex items-center gap-3">
                          {isExpanded ? (
                            <ChevronDown className="w-4 h-4 text-slate-500 shrink-0" />
                          ) : (
                            <ChevronRight className="w-4 h-4 text-slate-500 shrink-0" />
                          )}
                          <div>
                            <div className="text-sm font-semibold text-slate-900">
                              {unit.title}
                            </div>
                            {unit.description && (
                              <div className="text-xs text-slate-500 line-clamp-1">
                                {unit.description}
                              </div>
                            )}
                          </div>
                        </div>

                        <div className="flex items-center gap-4 shrink-0">
                          <div className="text-right hidden sm:block">
                            <span className="text-xs font-mono font-medium tabular-nums text-slate-700">
                              {completedUnitTopics} / {totalUnitTopics} Topics
                            </span>
                            <span className="text-[11px] text-slate-400 ml-1">
                              ({unitPercent}%)
                            </span>
                          </div>
                        </div>
                      </button>

                      {/* Topics List when expanded */}
                      {isExpanded && (
                        <div className="px-6 pb-4 pt-1 bg-slate-50/40">
                          {unit.topics.length === 0 ? (
                            <div className="text-xs text-slate-400 py-3 italic">
                              No topics listed in this unit yet.
                            </div>
                          ) : (
                            <div className="space-y-3">
                              {unit.topics.map((topic) => {
                                const isCompleted = Boolean(progressMap[topic.id]);
                                const isSaving = Boolean(savingItems[topic.id]);

                                return (
                                  <div
                                    key={topic.id}
                                    className={`p-3.5 rounded-lg border transition-all ${
                                      isCompleted
                                        ? 'bg-blue-50/40 border-blue-200'
                                        : 'bg-white border-slate-200 hover:border-slate-300'
                                    }`}
                                  >
                                    <div className="flex items-start justify-between gap-3">
                                      <div className="flex items-start gap-3 flex-1 min-w-0">
                                        {/* Completion Checkbox with Saving Spinner */}
                                        <div className="pt-0.5 shrink-0">
                                          {isSaving ? (
                                            <Loader2 className="w-4 h-4 text-blue-600 animate-spin" />
                                          ) : (
                                            <input
                                              type="checkbox"
                                              checked={isCompleted}
                                              onChange={(e) =>
                                                onToggleTopic(topic.id, e.target.checked)
                                              }
                                              className="w-4 h-4 text-blue-600 rounded border-slate-300 focus:ring-blue-500 cursor-pointer"
                                              id={`topic-${topic.id}`}
                                            />
                                          )}
                                        </div>

                                        <div className="flex-1 min-w-0">
                                          <div className="flex items-center gap-2 flex-wrap">
                                            <label
                                              htmlFor={`topic-${topic.id}`}
                                              className={`text-sm font-semibold cursor-pointer ${
                                                isCompleted
                                                  ? 'line-through text-slate-500'
                                                  : 'text-slate-900'
                                              }`}
                                            >
                                              {topic.title}
                                            </label>

                                            {/* Important ⭐ Badge */}
                                            {topic.is_important && (
                                              <span className="text-[11px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 px-2 py-0.5 rounded-full flex items-center gap-1 shrink-0">
                                                <Star className="w-3 h-3 fill-amber-500 text-amber-500" />
                                                <span>Important ⭐</span>
                                              </span>
                                            )}

                                            <span className="text-xs text-slate-400 flex items-center gap-1 font-mono">
                                              <Clock className="w-3 h-3" />
                                              <span>{topic.estimated_hours}h</span>
                                            </span>
                                          </div>

                                          {topic.description && (
                                            <p className="text-xs text-slate-500 mt-1">
                                              {topic.description}
                                            </p>
                                          )}

                                          {/* Nested Subtopics */}
                                          {topic.subtopics && topic.subtopics.length > 0 && (
                                            <div className="mt-3 pl-4 border-l-2 border-slate-200 space-y-2">
                                              <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">
                                                Subtopics ({topic.subtopics.length})
                                              </div>
                                              {topic.subtopics.map((st) => {
                                                const isSubCompleted = Boolean(
                                                  progressMap[st.id]
                                                );
                                                const isSubSaving = Boolean(savingItems[st.id]);

                                                return (
                                                  <div
                                                    key={st.id}
                                                    className="flex items-center gap-2 text-xs"
                                                  >
                                                    {isSubSaving ? (
                                                      <Loader2 className="w-3.5 h-3.5 text-blue-500 animate-spin" />
                                                    ) : (
                                                      <input
                                                        type="checkbox"
                                                        checked={isSubCompleted}
                                                        onChange={(e) =>
                                                          onToggleSubtopic(st.id, e.target.checked)
                                                        }
                                                        className="w-3.5 h-3.5 text-blue-600 rounded border-slate-300 focus:ring-blue-500 cursor-pointer"
                                                        id={`subtopic-${st.id}`}
                                                      />
                                                    )}
                                                    <label
                                                      htmlFor={`subtopic-${st.id}`}
                                                      className={`cursor-pointer ${
                                                        isSubCompleted
                                                          ? 'line-through text-slate-400'
                                                          : 'text-slate-700'
                                                      }`}
                                                    >
                                                      {st.title}
                                                    </label>
                                                  </div>
                                                );
                                              })}
                                            </div>
                                          )}
                                        </div>
                                      </div>

                                      {/* Admin Important Toggle Shortcut */}
                                      {currentUser.role === 'admin' && onToggleImportant && (
                                        <button
                                          onClick={() =>
                                            onToggleImportant(topic.id, !topic.is_important)
                                          }
                                          className={`p-1.5 rounded-lg border text-xs flex items-center gap-1 transition-colors cursor-pointer ${
                                            topic.is_important
                                              ? 'bg-amber-100 text-amber-800 border-amber-300'
                                              : 'bg-white text-slate-400 border-slate-200 hover:text-amber-600'
                                          }`}
                                          title={
                                            topic.is_important
                                              ? 'Remove Important examination designation'
                                              : 'Mark as Important examination topic'
                                          }
                                        >
                                          <Star
                                            className={`w-3.5 h-3.5 ${
                                              topic.is_important
                                                ? 'fill-amber-500 text-amber-500'
                                                : ''
                                            }`}
                                          />
                                        </button>
                                      )}
                                    </div>
                                  </div>
                                );
                              })}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
