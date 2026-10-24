import React, { useState } from 'react';
import { X, Upload, Link, Youtube, FileText, AlertCircle, CheckCircle2, ShieldCheck } from 'lucide-react';
import { SemesterWithSubjects, Profile, ResourceType } from '../types/database';
import { DataService } from '../services/dataService';

interface AddResourceModalProps {
  isOpen: boolean;
  onClose: () => void;
  syllabus: SemesterWithSubjects[];
  currentUser: Profile;
  onResourceAdded: () => void;
}

export const AddResourceModal: React.FC<AddResourceModalProps> = ({
  isOpen,
  onClose,
  syllabus,
  currentUser,
  onResourceAdded,
}) => {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [resourceType, setResourceType] = useState<ResourceType>('pdf');
  const [selectedSemesterId, setSelectedSemesterId] = useState<string>(syllabus[0]?.id || 'sem-4');
  const [selectedSubjectId, setSelectedSubjectId] = useState<string>('');
  const [selectedUnitId, setSelectedUnitId] = useState<string>('');
  const [externalUrl, setExternalUrl] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [isExamPrep, setIsExamPrep] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  // Derive subjects for selected semester
  const activeSemester = syllabus.find((s) => s.id === selectedSemesterId) || syllabus[0];
  const availableSubjects = activeSemester?.subjects || [];
  const currentSubject = availableSubjects.find((s) => s.id === selectedSubjectId) || availableSubjects[0];
  const availableUnits = currentSubject?.units || [];

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      const selectedFile = e.target.files[0];
      if (selectedFile.size > 25 * 1024 * 1024) {
        setError('File size exceeds the 25MB limit.');
        return;
      }
      setError(null);
      setFile(selectedFile);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const subjectIdToUse = selectedSubjectId || availableSubjects[0]?.id;
    if (!subjectIdToUse) {
      setError('Please select an active subject for this resource.');
      return;
    }

    if (['youtube', 'url'].includes(resourceType)) {
      if (!externalUrl.startsWith('http')) {
        setError('Please provide a valid URL starting with https:// or http://');
        return;
      }
    } else if (!file && !externalUrl) {
      setError('Please select a file to upload or enter an access URL.');
      return;
    }

    setLoading(true);

    try {
      const res = await DataService.addResource(
        {
          title,
          description,
          resource_type: resourceType,
          semester_id: selectedSemesterId,
          subject_id: subjectIdToUse,
          unit_id: selectedUnitId || undefined,
          external_url: externalUrl || undefined,
          file: file || undefined,
          is_exam_prep: isExamPrep,
        },
        currentUser
      );

      if (res.success) {
        onResourceAdded();
        onClose();
      } else {
        setError(res.error || 'Failed to save resource.');
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fade-in">
      <div className="bg-white rounded-2xl shadow-2xl max-w-lg w-full border border-slate-200 overflow-hidden max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50">
          <div>
            <h3 className="text-base font-bold text-slate-900">Share Study Material</h3>
            <p className="text-xs text-slate-500">
              Contribute notes, lecture links, or practice papers
            </p>
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-600 p-1 rounded-md transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Scrollable Form */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4 overflow-y-auto flex-1">
          {error && (
            <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-xs text-red-700 flex items-start gap-2">
              <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          {/* Moderation Notice */}
          <div className="p-3 bg-blue-50 border border-blue-200 rounded-lg text-xs text-blue-800 flex items-start gap-2">
            <ShieldCheck className="w-4 h-4 shrink-0 mt-0.5 text-blue-600" />
            <div>
              {currentUser.role === 'admin' ? (
                <span>Faculty verified: Your shared materials are auto-approved.</span>
              ) : (
                <span>
                  Student submissions will be queued for faculty review before appearing publicly.
                </span>
              )}
            </div>
          </div>

          {/* Resource Title */}
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">
              Resource Title *
            </label>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="e.g. Normalization 1NF-BCNF Solved Exercises PDF"
              className="w-full px-3 py-2 text-xs border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
            />
          </div>

          {/* Description */}
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">
              Description (Optional)
            </label>
            <textarea
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Key contents, topics covered, or source..."
              className="w-full px-3 py-2 text-xs border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
            />
          </div>

          {/* Resource Type Selector */}
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1.5">
              Material Format *
            </label>
            <div className="grid grid-cols-4 gap-2">
              {[
                { type: 'pdf', label: 'PDF Notes', icon: FileText },
                { type: 'document', label: 'Word/Doc', icon: FileText },
                { type: 'youtube', label: 'Video', icon: Youtube },
                { type: 'url', label: 'Web Link', icon: Link },
              ].map((fmt) => {
                const Icon = fmt.icon;
                return (
                  <button
                    key={fmt.type}
                    type="button"
                    onClick={() => {
                      setResourceType(fmt.type as ResourceType);
                      setError(null);
                    }}
                    className={`p-2.5 rounded-lg border text-center transition-colors flex flex-col items-center gap-1 ${
                      resourceType === fmt.type
                        ? 'border-blue-600 bg-blue-50 text-blue-700 font-semibold'
                        : 'border-slate-200 text-slate-600 hover:bg-slate-50'
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                    <span className="text-[11px]">{fmt.label}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Semester & Subject Selection */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">Semester</label>
              <select
                value={selectedSemesterId}
                onChange={(e) => setSelectedSemesterId(e.target.value)}
                className="w-full px-2.5 py-1.5 text-xs border border-slate-300 rounded-lg bg-white"
              >
                {syllabus.map((s) => (
                  <option key={s.id} value={s.id}>
                    Semester {s.semester_number}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">Subject *</label>
              <select
                value={selectedSubjectId}
                onChange={(e) => setSelectedSubjectId(e.target.value)}
                className="w-full px-2.5 py-1.5 text-xs border border-slate-300 rounded-lg bg-white"
              >
                {availableSubjects.map((sub) => (
                  <option key={sub.id} value={sub.id}>
                    {sub.code}: {sub.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Optional Unit Selection */}
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">
              Associated Unit (Optional)
            </label>
            <select
              value={selectedUnitId}
              onChange={(e) => setSelectedUnitId(e.target.value)}
              className="w-full px-2.5 py-1.5 text-xs border border-slate-300 rounded-lg bg-white"
            >
              <option value="">General Subject Material</option>
              {availableUnits.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.title}
                </option>
              ))}
            </select>
          </div>

          {/* Conditional Input: File vs URL */}
          {['pdf', 'document'].includes(resourceType) ? (
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Upload Document (Max 25MB)
              </label>
              <div className="border-2 border-dashed border-slate-300 rounded-xl p-4 text-center hover:bg-slate-50 transition-colors">
                <input
                  type="file"
                  id="resource-file-upload"
                  accept=".pdf,.doc,.docx,.txt"
                  onChange={handleFileChange}
                  className="hidden"
                />
                <label
                  htmlFor="resource-file-upload"
                  className="cursor-pointer flex flex-col items-center gap-1.5"
                >
                  <Upload className="w-6 h-6 text-slate-400" />
                  <span className="text-xs font-medium text-blue-600 hover:underline">
                    {file ? file.name : 'Click to select PDF or Document'}
                  </span>
                  <span className="text-[10px] text-slate-400">
                    PDF, DOC, DOCX up to 25MB
                  </span>
                </label>
              </div>

              {/* Or external direct mirror */}
              <div className="mt-2">
                <label className="block text-[11px] text-slate-500 mb-1">
                  Or provide external file mirror link:
                </label>
                <input
                  type="url"
                  value={externalUrl}
                  onChange={(e) => setExternalUrl(e.target.value)}
                  placeholder="https://drive.google.com/... or direct link"
                  className="w-full px-3 py-1.5 text-xs border border-slate-300 rounded-lg"
                />
              </div>
            </div>
          ) : (
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Educational Video or Link URL *
              </label>
              <input
                type="url"
                required
                value={externalUrl}
                onChange={(e) => setExternalUrl(e.target.value)}
                placeholder={
                  resourceType === 'youtube'
                    ? 'https://www.youtube.com/watch?v=...'
                    : 'https://ocw.mit.edu/...'
                }
                className="w-full px-3 py-2 text-xs border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500"
              />
            </div>
          )}

          {/* Exam Prep Checkbox */}
          <div className="flex items-center gap-2 pt-2">
            <input
              type="checkbox"
              id="isExamPrep"
              checked={isExamPrep}
              onChange={(e) => setIsExamPrep(e.target.checked)}
              className="w-4 h-4 text-blue-600 rounded border-slate-300 cursor-pointer"
            />
            <label htmlFor="isExamPrep" className="text-xs text-slate-700 cursor-pointer">
              Mark as high-yield Examination Revision Material ⭐
            </label>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full py-2.5 px-4 text-xs font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors flex items-center justify-center gap-2"
          >
            {loading ? 'Submitting to Repository...' : 'Publish Study Resource'}
          </button>
        </form>
      </div>
    </div>
  );
};
