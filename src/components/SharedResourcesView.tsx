import React, { useState } from 'react';
import {
  Search,
  FileText,
  Youtube,
  Link,
  Plus,
  Download,
  ExternalLink,
  Trash2,
  Star,
  Layers,
} from 'lucide-react';
import { StudyResource, SemesterWithSubjects, Profile, ResourceType } from '../types/database';
import { DataService } from '../services/dataService';

interface SharedResourcesViewProps {
  resources: StudyResource[];
  syllabus: SemesterWithSubjects[];
  currentUser: Profile;
  onOpenAddModal: () => void;
  onRefreshResources: () => void;
}

export const SharedResourcesView: React.FC<SharedResourcesViewProps> = ({
  resources,
  syllabus,
  currentUser,
  onOpenAddModal,
  onRefreshResources,
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedType, setSelectedType] = useState<ResourceType | 'all'>('all');
  const [selectedSubjectId, setSelectedSubjectId] = useState<string>('all');
  const [examPrepOnly, setExamPrepOnly] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  // Collect all subjects for dropdown filter
  const allSubjects = syllabus.flatMap((s) => s.subjects);

  // Filter resources
  const filteredResources = resources.filter((res) => {
    // Visibility: approved resources are public. Pending/rejected are visible to uploader or admin only!
    const isVisible =
      res.status === 'approved' ||
      currentUser.role === 'admin' ||
      currentUser.id === res.uploader_id;

    if (!isVisible) return false;

    if (selectedType !== 'all' && res.resource_type !== selectedType) return false;
    if (selectedSubjectId !== 'all' && res.subject_id !== selectedSubjectId) return false;
    if (examPrepOnly && !res.is_exam_prep) return false;

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      const matchTitle = res.title.toLowerCase().includes(q);
      const matchDesc = res.description ? res.description.toLowerCase().includes(q) : false;
      const matchUploader = res.uploader_name.toLowerCase().includes(q);
      if (!matchTitle && !matchDesc && !matchUploader) return false;
    }

    return true;
  });

  const handleDelete = async (resourceId: string) => {
    if (!confirm('Are you sure you want to remove this study resource?')) return;
    setDeletingId(resourceId);
    try {
      const res = await DataService.deleteResource(resourceId, currentUser);
      if (res.success) {
        onRefreshResources();
      }
    } finally {
      setDeletingId(null);
    }
  };

  const getFormatIcon = (type: ResourceType) => {
    switch (type) {
      case 'pdf':
        return <FileText className="w-4 h-4 text-rose-600" />;
      case 'youtube':
        return <Youtube className="w-4 h-4 text-red-600" />;
      case 'url':
        return <Link className="w-4 h-4 text-blue-600" />;
      case 'document':
        return <FileText className="w-4 h-4 text-indigo-600" />;
    }
  };

  return (
    <div className="space-y-6 animate-fade-in pb-16">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Shared Learning Materials
          </h1>
          <p className="text-xs text-slate-500">
            Collaborative lecture notes, question banks, and curated educational links
          </p>
        </div>

        <button
          onClick={onOpenAddModal}
          className="px-4 py-2 text-xs font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-lg shadow-sm transition-colors flex items-center gap-1.5 self-start sm:self-auto shrink-0 cursor-pointer"
        >
          <Plus className="w-4 h-4" />
          <span>Share Study Material</span>
        </button>
      </div>

      {/* Filter and Search Bar */}
      <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm space-y-3">
        <div className="flex flex-col md:flex-row items-stretch md:items-center justify-between gap-3">
          {/* Search */}
          <div className="relative flex-1">
            <Search className="w-4 h-4 text-slate-400 absolute left-3 top-2.5" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search resource title, notes description, or uploader..."
              className="w-full pl-9 pr-3 py-1.5 text-xs border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500/20"
            />
          </div>

          {/* Subject Filter */}
          <select
            value={selectedSubjectId}
            onChange={(e) => setSelectedSubjectId(e.target.value)}
            className="text-xs border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white text-slate-700 focus:outline-none"
          >
            <option value="all">All Subjects</option>
            {allSubjects.map((s) => (
              <option key={s.id} value={s.id}>
                {s.code}: {s.name}
              </option>
            ))}
          </select>

          {/* Exam Prep Toggle */}
          <button
            onClick={() => setExamPrepOnly(!examPrepOnly)}
            className={`px-3 py-1.5 text-xs font-medium rounded-lg flex items-center gap-1.5 transition-colors border shrink-0 cursor-pointer ${
              examPrepOnly
                ? 'bg-amber-50 text-amber-800 border-amber-300 shadow-sm'
                : 'bg-white text-slate-600 border-slate-300 hover:bg-slate-50'
            }`}
          >
            <Star
              className={`w-3.5 h-3.5 ${
                examPrepOnly ? 'text-amber-500 fill-amber-500' : 'text-slate-400'
              }`}
            />
            <span>Exam Focus Only</span>
          </button>
        </div>

        {/* Format Segmented Filter */}
        <div className="flex items-center gap-1.5 overflow-x-auto pt-1">
          {[
            { id: 'all', label: 'All Formats' },
            { id: 'pdf', label: 'PDF Notes' },
            { id: 'document', label: 'Documents' },
            { id: 'youtube', label: 'Video Lectures' },
            { id: 'url', label: 'Educational Links' },
          ].map((fmt) => (
            <button
              key={fmt.id}
              onClick={() => setSelectedType(fmt.id as ResourceType | 'all')}
              className={`px-2.5 py-1 text-xs font-medium rounded-md transition-colors whitespace-nowrap cursor-pointer ${
                selectedType === fmt.id
                  ? 'bg-slate-900 text-white'
                  : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
              }`}
            >
              {fmt.label}
            </button>
          ))}
        </div>
      </div>

      {/* Resource Grid */}
      {filteredResources.length === 0 ? (
        <div className="bg-white p-12 text-center rounded-xl border border-slate-200">
          <Layers className="w-10 h-10 text-slate-300 mx-auto mb-3" />
          <h3 className="text-base font-semibold text-slate-800">No resources found</h3>
          <p className="text-xs text-slate-500 mt-1 max-w-sm mx-auto">
            {resources.length === 0
              ? 'No study materials have been shared in the database yet. Be the first to upload lecture notes or reference documents.'
              : 'No resources match your active search filters.'}
          </p>
          <button
            onClick={onOpenAddModal}
            className="mt-4 px-4 py-2 text-xs font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors cursor-pointer"
          >
            Upload Study Material
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredResources.map((res) => {
            const subject = allSubjects.find((s) => s.id === res.subject_id);
            const canDelete =
              currentUser.role === 'admin' || currentUser.id === res.uploader_id;
            const publicFileUrl = res.file_path ? DataService.getResourcePublicUrl(res.file_path) : null;
            const resourceUrl = res.external_url || publicFileUrl;

            return (
              <div
                key={res.id}
                className="bg-white rounded-xl border border-slate-200 p-5 shadow-sm hover:border-slate-300 transition-all flex flex-col justify-between"
              >
                <div>
                  {/* Top Bar with Subject & Status */}
                  <div className="flex items-center justify-between gap-2 mb-2">
                    <span
                      className="text-[11px] font-bold font-mono px-2 py-0.5 rounded text-white"
                      style={{ backgroundColor: subject?.color_code || '#2563EB' }}
                    >
                      {subject?.code || 'GEN'}
                    </span>

                    <div className="flex items-center gap-1.5">
                      {res.is_exam_prep && (
                        <span className="text-[10px] font-semibold text-amber-700 bg-amber-50 border border-amber-200 px-1.5 py-0.5 rounded flex items-center gap-0.5">
                          <Star className="w-2.5 h-2.5 fill-amber-500 text-amber-500" />
                          <span>Exam</span>
                        </span>
                      )}

                      {/* Moderation Status */}
                      {res.status === 'pending' && (
                        <span className="text-[10px] font-semibold text-amber-800 bg-amber-100 px-2 py-0.5 rounded">
                          Pending Review
                        </span>
                      )}
                      {res.status === 'rejected' && (
                        <span className="text-[10px] font-semibold text-red-800 bg-red-100 px-2 py-0.5 rounded">
                          Rejected
                        </span>
                      )}
                    </div>
                  </div>

                  {/* Title & Description */}
                  <div className="flex items-start gap-2.5 my-2">
                    <div className="p-2 rounded-lg bg-slate-100 shrink-0 mt-0.5">
                      {getFormatIcon(res.resource_type)}
                    </div>
                    <div>
                      <h3 className="text-sm font-semibold text-slate-900 line-clamp-2">
                        {res.title}
                      </h3>
                      {res.description && (
                        <p className="text-xs text-slate-500 line-clamp-3 mt-1 leading-relaxed">
                          {res.description}
                        </p>
                      )}
                    </div>
                  </div>
                </div>

                {/* Footer with Uploader & Action Button */}
                <div className="mt-4 pt-3 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
                  <div>
                    <span className="block font-medium text-slate-700 truncate max-w-[140px]">
                      {res.uploader_name}
                    </span>
                    <span className="text-[10px] text-slate-400 font-mono">
                      {res.uploader_roll}
                    </span>
                  </div>

                  <div className="flex items-center gap-2">
                    {resourceUrl ? (
                      <a
                        href={resourceUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="px-3 py-1.5 bg-blue-50 text-blue-600 hover:bg-blue-100 rounded-lg font-medium text-xs flex items-center gap-1 transition-colors"
                      >
                        {res.file_path ? (
                          <>
                            <span>Download</span>
                            <Download className="w-3 h-3" />
                          </>
                        ) : (
                          <>
                            <span>Open</span>
                            <ExternalLink className="w-3 h-3" />
                          </>
                        )}
                      </a>
                    ) : (
                      <span className="text-slate-400 text-[11px]">No link</span>
                    )}

                    {canDelete && (
                      <button
                        onClick={() => handleDelete(res.id)}
                        disabled={deletingId === res.id}
                        className="p-1.5 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded-md transition-colors cursor-pointer"
                        title="Delete resource"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
