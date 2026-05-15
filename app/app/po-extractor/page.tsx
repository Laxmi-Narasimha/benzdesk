// ============================================================================
// PO Extractor Page
// Upload image/PDF → OCR via OpenAI → Review → Generate & Download PDF
// ============================================================================

'use client';

import React, { useState, useRef, useCallback } from 'react';
import {
  Camera,
  Upload,
  FileText,
  Loader2,
  Download,
  Eye,
  Save,
  ArrowLeft,
  Plus,
  Trash2,
  CheckCircle2,
  AlertCircle,
  X,
} from 'lucide-react';
import { extractPOFromFile, type POData, type POItem } from '@/lib/extractPO';
import { generatePoPdf, generatePoPdfUrl } from '@/lib/generatePoPdf';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';

// ============================================================================
// Constants
// ============================================================================

const ACCEPTED_TYPES = '.pdf,.jpg,.jpeg,.png,.webp,.heic,.xlsx,.xls,.csv';
const MAX_FILE_SIZE = 20 * 1024 * 1024; // 20MB

const EMPTY_ITEM: POItem = {
  name: '',
  description: '',
  hsn: null,
  gst_rate: 18,
  quantity: 0,
  uom: 'Pcs',
  rate: 0,
  amount: 0,
  igst: 0,
  total: 0,
};

const DEFAULT_PO: POData = {
  po_number: '',
  po_date: new Date().toISOString().split('T')[0],
  vendor_name: '',
  vendor_address: '',
  vendor_gstin: null,
  vendor_pan: null,
  freight_charges: 'Extras as actual',
  payment_terms: 'Immediate Basis',
  currency: 'INR',
  items: [{ ...EMPTY_ITEM }],
  subtotal: 0,
  igst: 0,
  round_off: 0,
  total: 0,
};

// ============================================================================
// Stage type
// ============================================================================

type Stage = 'upload' | 'extracting' | 'review' | 'result';

// ============================================================================
// Component
// ============================================================================

export default function POExtractorPage() {
  const { user } = useAuth();
  const [stage, setStage] = useState<Stage>('upload');
  const [poData, setPoData] = useState<POData>(DEFAULT_PO);
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [dragActive, setDragActive] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const cameraInputRef = useRef<HTMLInputElement>(null);

  // ==========================================================================
  // File handling
  // ==========================================================================

  const handleFile = useCallback(async (file: File) => {
    if (file.size > MAX_FILE_SIZE) {
      setError('File too large. Maximum size is 20MB.');
      return;
    }

    setError(null);
    setFileName(file.name);
    setStage('extracting');

    try {
      const apiKey = (window as any).__OPENAI_KEY__ || process.env.NEXT_PUBLIC_OPENAI_API_KEY || '';
      const extracted = await extractPOFromFile(file, apiKey);
      setPoData(extracted);
      setStage('review');
    } catch (err: any) {
      console.error('Extraction error:', err);
      setError(err.message || 'Failed to extract data from the file.');
      setStage('upload');
    }
  }, []);

  const onFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleFile(file);
  };

  const onDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragActive(false);
    const file = e.dataTransfer.files?.[0];
    if (file) handleFile(file);
  };

  const onDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setDragActive(true);
  };

  const onDragLeave = () => setDragActive(false);

  // ==========================================================================
  // Field updates
  // ==========================================================================

  const updateField = (field: keyof POData, value: any) => {
    setPoData((prev) => ({ ...prev, [field]: value }));
  };

  const updateItem = (index: number, field: keyof POItem, value: any) => {
    setPoData((prev) => {
      const items = [...prev.items];
      const item = { ...items[index], [field]: value };

      // Auto-calculate amounts
      if (['quantity', 'rate', 'gst_rate'].includes(field)) {
        item.amount = Number((item.quantity * item.rate).toFixed(2));
        item.igst = Number((item.amount * item.gst_rate / 100).toFixed(2));
        item.total = Number((item.amount + item.igst).toFixed(2));
      }

      items[index] = item;

      // Recalculate totals
      const subtotal = items.reduce((sum, it) => sum + it.amount, 0);
      const igst = items.reduce((sum, it) => sum + it.igst, 0);
      const total = subtotal + igst + (prev.round_off || 0);

      return {
        ...prev,
        items,
        subtotal: Number(subtotal.toFixed(2)),
        igst: Number(igst.toFixed(2)),
        total: Number(total.toFixed(2)),
      };
    });
  };

  const addItem = () => {
    setPoData((prev) => ({
      ...prev,
      items: [...prev.items, { ...EMPTY_ITEM }],
    }));
  };

  const removeItem = (index: number) => {
    setPoData((prev) => {
      const items = prev.items.filter((_, i) => i !== index);
      const subtotal = items.reduce((sum, it) => sum + it.amount, 0);
      const igst = items.reduce((sum, it) => sum + it.igst, 0);
      return {
        ...prev,
        items,
        subtotal: Number(subtotal.toFixed(2)),
        igst: Number(igst.toFixed(2)),
        total: Number((subtotal + igst + (prev.round_off || 0)).toFixed(2)),
      };
    });
  };

  // ==========================================================================
  // Generate PDF
  // ==========================================================================

  const handleGenerate = () => {
    try {
      const url = generatePoPdfUrl(poData);
      setPdfUrl(url);
      setStage('result');
    } catch (err: any) {
      setError('Failed to generate PDF: ' + err.message);
    }
  };

  // ==========================================================================
  // Download PDF
  // ==========================================================================

  const handleDownload = () => {
    if (!pdfUrl) return;
    const a = document.createElement('a');
    a.href = pdfUrl;
    a.download = `PO-${poData.po_number || 'draft'}.pdf`;
    a.click();
  };

  // ==========================================================================
  // Save to Supabase
  // ==========================================================================

  const handleSave = async () => {
    setSaving(true);
    try {
      const { error: dbError } = await getSupabaseClient().from('purchase_orders').insert({
        po_number: poData.po_number,
        po_date: poData.po_date || null,
        vendor_name: poData.vendor_name,
        vendor_address: poData.vendor_address,
        vendor_gstin: poData.vendor_gstin,
        vendor_pan: poData.vendor_pan,
        freight_charges: poData.freight_charges,
        payment_terms: poData.payment_terms,
        currency: poData.currency,
        items: poData.items,
        subtotal: poData.subtotal,
        igst: poData.igst,
        round_off: poData.round_off,
        total: poData.total,
        source_filename: fileName,
        created_by: user?.id || null,
      });

      if (dbError) throw dbError;
      setSaved(true);
    } catch (err: any) {
      setError('Failed to save: ' + err.message);
    } finally {
      setSaving(false);
    }
  };

  // ==========================================================================
  // Reset
  // ==========================================================================

  const handleReset = () => {
    setStage('upload');
    setPoData(DEFAULT_PO);
    setPdfUrl(null);
    setFileName('');
    setError(null);
    setSaved(false);
    if (fileInputRef.current) fileInputRef.current.value = '';
    if (cameraInputRef.current) cameraInputRef.current.value = '';
  };

  // ==========================================================================
  // Render
  // ==========================================================================

  return (
    <div className="max-w-6xl mx-auto">
      {/* Page header */}
      <div className="mb-6">
        <div className="flex items-center gap-3 mb-2">
          {stage !== 'upload' && (
            <button
              onClick={handleReset}
              className="p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <ArrowLeft className="w-5 h-5" />
            </button>
          )}
          <div>
            <h1 className="text-2xl font-bold text-gray-900">PO Extractor</h1>
            <p className="text-sm text-gray-500 mt-0.5">
              {stage === 'upload' && 'Upload a purchase order image, PDF, or Excel file to extract data'}
              {stage === 'extracting' && 'Analyzing document with AI...'}
              {stage === 'review' && 'Review and edit extracted data'}
              {stage === 'result' && 'Your purchase order is ready'}
            </p>
          </div>
        </div>

        {/* Progress steps */}
        <div className="flex items-center gap-2 mt-4">
          {['Upload', 'Extract', 'Review', 'Download'].map((step, i) => {
            const stageIdx = { upload: 0, extracting: 1, review: 2, result: 3 }[stage];
            const isActive = i === stageIdx;
            const isDone = i < stageIdx;
            return (
              <React.Fragment key={step}>
                {i > 0 && (
                  <div className={`flex-1 h-0.5 ${isDone ? 'bg-blue-500' : 'bg-gray-200'}`} />
                )}
                <div
                  className={`flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium transition-all ${
                    isActive
                      ? 'bg-blue-100 text-blue-700'
                      : isDone
                      ? 'bg-green-100 text-green-700'
                      : 'bg-gray-100 text-gray-400'
                  }`}
                >
                  {isDone ? (
                    <CheckCircle2 className="w-3.5 h-3.5" />
                  ) : (
                    <span className="w-3.5 h-3.5 flex items-center justify-center text-[10px]">
                      {i + 1}
                    </span>
                  )}
                  {step}
                </div>
              </React.Fragment>
            );
          })}
        </div>
      </div>

      {/* Error banner */}
      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg flex items-start gap-2">
          <AlertCircle className="w-5 h-5 text-red-500 mt-0.5 flex-shrink-0" />
          <div className="flex-1 text-sm text-red-700">{error}</div>
          <button onClick={() => setError(null)} className="text-red-400 hover:text-red-600">
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      {/* ================================================================ */}
      {/* STAGE: UPLOAD */}
      {/* ================================================================ */}
      {stage === 'upload' && (
        <div className="space-y-4">
          {/* Drop zone */}
          <div
            onDrop={onDrop}
            onDragOver={onDragOver}
            onDragLeave={onDragLeave}
            onClick={() => fileInputRef.current?.click()}
            className={`relative cursor-pointer border-2 border-dashed rounded-2xl p-12 text-center transition-all ${
              dragActive
                ? 'border-blue-500 bg-blue-50'
                : 'border-gray-300 hover:border-blue-400 hover:bg-gray-50'
            }`}
          >
            <div className="flex flex-col items-center gap-4">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center shadow-lg shadow-blue-500/25">
                <Upload className="w-8 h-8 text-white" />
              </div>
              <div>
                <p className="text-lg font-semibold text-gray-700">
                  Drop a file here or click to browse
                </p>
                <p className="text-sm text-gray-400 mt-1">
                  Supports PDF, Excel, CSV, JPG, PNG • Max 20MB
                </p>
              </div>
            </div>
            <input
              ref={fileInputRef}
              type="file"
              accept={ACCEPTED_TYPES}
              onChange={onFileChange}
              className="hidden"
            />
          </div>

          {/* Camera button (mobile-friendly) */}
          <button
            onClick={() => cameraInputRef.current?.click()}
            className="w-full flex items-center justify-center gap-3 py-4 px-6 bg-gradient-to-r from-blue-600 to-blue-700 text-white rounded-xl font-medium hover:from-blue-700 hover:to-blue-800 transition-all shadow-lg shadow-blue-500/25 active:scale-[0.98]"
          >
            <Camera className="w-5 h-5" />
            Take a Photo of Purchase Order
          </button>
          <input
            ref={cameraInputRef}
            type="file"
            accept="image/*"
            capture="environment"
            onChange={onFileChange}
            className="hidden"
          />
        </div>
      )}

      {/* ================================================================ */}
      {/* STAGE: EXTRACTING */}
      {/* ================================================================ */}
      {stage === 'extracting' && (
        <div className="flex flex-col items-center justify-center py-20">
          <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center shadow-xl shadow-blue-500/30 mb-6 animate-pulse">
            <Loader2 className="w-10 h-10 text-white animate-spin" />
          </div>
          <h2 className="text-xl font-bold text-gray-800 mb-2">Extracting Purchase Order Data</h2>
          <p className="text-sm text-gray-500 max-w-md text-center">
            AI is analyzing <span className="font-medium text-gray-700">{fileName}</span> and
            extracting vendor details, line items, and amounts. This may take 10-20 seconds.
          </p>
          <div className="mt-6 flex items-center gap-2 text-xs text-gray-400">
            <div className="w-2 h-2 rounded-full bg-blue-500 animate-bounce" style={{ animationDelay: '0ms' }} />
            <div className="w-2 h-2 rounded-full bg-blue-500 animate-bounce" style={{ animationDelay: '150ms' }} />
            <div className="w-2 h-2 rounded-full bg-blue-500 animate-bounce" style={{ animationDelay: '300ms' }} />
          </div>
        </div>
      )}

      {/* ================================================================ */}
      {/* STAGE: REVIEW */}
      {/* ================================================================ */}
      {stage === 'review' && (
        <div className="space-y-6">
          {/* Vendor & PO Details */}
          <div className="bg-white border border-gray-200 rounded-xl p-5 shadow-sm">
            <h3 className="text-sm font-semibold text-gray-800 mb-4 flex items-center gap-2">
              <FileText className="w-4 h-4 text-blue-500" />
              PO Details
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <InputField label="PO Number" value={poData.po_number} onChange={(v) => updateField('po_number', v)} />
              <InputField label="PO Date" type="date" value={poData.po_date} onChange={(v) => updateField('po_date', v)} />
              <InputField label="Vendor Name" value={poData.vendor_name} onChange={(v) => updateField('vendor_name', v)} />
              <InputField label="Vendor Address" value={poData.vendor_address} onChange={(v) => updateField('vendor_address', v)} className="sm:col-span-2" />
              <InputField label="Vendor GSTIN" value={poData.vendor_gstin || ''} onChange={(v) => updateField('vendor_gstin', v)} />
              <InputField label="Vendor PAN" value={poData.vendor_pan || ''} onChange={(v) => updateField('vendor_pan', v)} />
              <InputField label="Freight Charges" value={poData.freight_charges} onChange={(v) => updateField('freight_charges', v)} />
              <InputField label="Payment Terms" value={poData.payment_terms} onChange={(v) => updateField('payment_terms', v)} />
              <InputField label="Currency" value={poData.currency} onChange={(v) => updateField('currency', v)} />
            </div>
          </div>

          {/* Line Items */}
          <div className="bg-white border border-gray-200 rounded-xl p-5 shadow-sm">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-gray-800">
                Line Items ({poData.items.length})
              </h3>
              <button
                onClick={addItem}
                className="flex items-center gap-1.5 text-xs font-medium text-blue-600 hover:text-blue-700 px-3 py-1.5 bg-blue-50 rounded-lg hover:bg-blue-100 transition-colors"
              >
                <Plus className="w-3.5 h-3.5" />
                Add Item
              </button>
            </div>

            <div className="overflow-x-auto -mx-5">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 text-gray-500 text-xs uppercase">
                    <th className="px-3 py-2 text-left">#</th>
                    <th className="px-3 py-2 text-left min-w-[150px]">Item</th>
                    <th className="px-3 py-2 text-left min-w-[150px]">Description</th>
                    <th className="px-3 py-2 text-left w-20">HSN</th>
                    <th className="px-3 py-2 text-center w-16">GST%</th>
                    <th className="px-3 py-2 text-center w-16">Qty</th>
                    <th className="px-3 py-2 text-center w-16">UoM</th>
                    <th className="px-3 py-2 text-right w-24">Rate</th>
                    <th className="px-3 py-2 text-right w-24">Amount</th>
                    <th className="px-3 py-2 text-right w-24">IGST</th>
                    <th className="px-3 py-2 text-right w-24">Total</th>
                    <th className="px-3 py-2 w-10"></th>
                  </tr>
                </thead>
                <tbody>
                  {poData.items.map((item, i) => (
                    <tr key={i} className="border-t border-gray-100 hover:bg-gray-50">
                      <td className="px-3 py-2 text-gray-400">{i + 1}</td>
                      <td className="px-3 py-1">
                        <input
                          className="w-full px-2 py-1 border border-gray-200 rounded text-sm focus:outline-none focus:ring-1 focus:ring-blue-400"
                          value={item.name}
                          onChange={(e) => updateItem(i, 'name', e.target.value)}
                        />
                      </td>
                      <td className="px-3 py-1">
                        <input
                          className="w-full px-2 py-1 border border-gray-200 rounded text-sm focus:outline-none focus:ring-1 focus:ring-blue-400"
                          value={item.description}
                          onChange={(e) => updateItem(i, 'description', e.target.value)}
                        />
                      </td>
                      <td className="px-3 py-1">
                        <input
                          className="w-full px-2 py-1 border border-gray-200 rounded text-sm focus:outline-none focus:ring-1 focus:ring-blue-400"
                          value={item.hsn || ''}
                          onChange={(e) => updateItem(i, 'hsn', e.target.value || null)}
                        />
                      </td>
                      <td className="px-3 py-1">
                        <input
                          type="number"
                          className="w-full px-2 py-1 border border-gray-200 rounded text-sm text-center focus:outline-none focus:ring-1 focus:ring-blue-400"
                          value={item.gst_rate}
                          onChange={(e) => updateItem(i, 'gst_rate', Number(e.target.value))}
                        />
                      </td>
                      <td className="px-3 py-1">
                        <input
                          type="number"
                          className="w-full px-2 py-1 border border-gray-200 rounded text-sm text-center focus:outline-none focus:ring-1 focus:ring-blue-400"
                          value={item.quantity}
                          onChange={(e) => updateItem(i, 'quantity', Number(e.target.value))}
                        />
                      </td>
                      <td className="px-3 py-1">
                        <input
                          className="w-full px-2 py-1 border border-gray-200 rounded text-sm text-center focus:outline-none focus:ring-1 focus:ring-blue-400"
                          value={item.uom}
                          onChange={(e) => updateItem(i, 'uom', e.target.value)}
                        />
                      </td>
                      <td className="px-3 py-1">
                        <input
                          type="number"
                          step="0.01"
                          className="w-full px-2 py-1 border border-gray-200 rounded text-sm text-right focus:outline-none focus:ring-1 focus:ring-blue-400"
                          value={item.rate}
                          onChange={(e) => updateItem(i, 'rate', Number(e.target.value))}
                        />
                      </td>
                      <td className="px-3 py-2 text-right text-gray-600">₹{item.amount.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</td>
                      <td className="px-3 py-2 text-right text-gray-600">₹{item.igst.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</td>
                      <td className="px-3 py-2 text-right font-medium text-gray-800">₹{item.total.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</td>
                      <td className="px-3 py-2">
                        {poData.items.length > 1 && (
                          <button
                            onClick={() => removeItem(i)}
                            className="text-gray-400 hover:text-red-500 transition-colors"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Totals */}
            <div className="mt-4 pt-4 border-t border-gray-200 flex justify-end">
              <div className="w-64 space-y-2">
                <div className="flex justify-between text-sm text-gray-500">
                  <span>Subtotal</span>
                  <span>₹{poData.subtotal.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                </div>
                <div className="flex justify-between text-sm text-gray-500">
                  <span>IGST</span>
                  <span>₹{poData.igst.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                </div>
                <div className="flex justify-between text-sm text-gray-500">
                  <span>Round Off</span>
                  <input
                    type="number"
                    step="0.01"
                    className="w-28 px-2 py-0.5 border border-gray-200 rounded text-sm text-right focus:outline-none focus:ring-1 focus:ring-blue-400"
                    value={poData.round_off}
                    onChange={(e) => {
                      const ro = Number(e.target.value);
                      setPoData((prev) => ({
                        ...prev,
                        round_off: ro,
                        total: Number((prev.subtotal + prev.igst + ro).toFixed(2)),
                      }));
                    }}
                  />
                </div>
                <div className="flex justify-between text-base font-bold text-gray-900 pt-2 border-t border-gray-300">
                  <span>Total (INR)</span>
                  <span>₹{poData.total.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</span>
                </div>
              </div>
            </div>
          </div>

          {/* Generate button */}
          <div className="flex justify-end gap-3">
            <button
              onClick={handleReset}
              className="px-5 py-2.5 text-sm font-medium text-gray-600 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
            >
              Start Over
            </button>
            <button
              onClick={handleGenerate}
              className="flex items-center gap-2 px-6 py-2.5 text-sm font-medium text-white bg-gradient-to-r from-blue-600 to-blue-700 rounded-lg hover:from-blue-700 hover:to-blue-800 transition-all shadow-lg shadow-blue-500/20 active:scale-[0.98]"
            >
              <Eye className="w-4 h-4" />
              Generate Purchase Order
            </button>
          </div>
        </div>
      )}

      {/* ================================================================ */}
      {/* STAGE: RESULT */}
      {/* ================================================================ */}
      {stage === 'result' && pdfUrl && (
        <div className="space-y-4">
          {/* Action buttons */}
          <div className="flex flex-wrap gap-3">
            <button
              onClick={handleDownload}
              className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-white bg-gradient-to-r from-green-600 to-green-700 rounded-lg hover:from-green-700 hover:to-green-800 transition-all shadow-lg shadow-green-500/20"
            >
              <Download className="w-4 h-4" />
              Download PDF
            </button>
            <button
              onClick={handleSave}
              disabled={saving || saved}
              className={`flex items-center gap-2 px-5 py-2.5 text-sm font-medium rounded-lg transition-all ${
                saved
                  ? 'bg-green-100 text-green-700 cursor-default'
                  : 'text-white bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-700 hover:to-blue-800 shadow-lg shadow-blue-500/20'
              }`}
            >
              {saving ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : saved ? (
                <CheckCircle2 className="w-4 h-4" />
              ) : (
                <Save className="w-4 h-4" />
              )}
              {saved ? 'Saved to Database' : saving ? 'Saving...' : 'Save to Database'}
            </button>
            <button
              onClick={() => setStage('review')}
              className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-gray-600 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors"
            >
              <ArrowLeft className="w-4 h-4" />
              Edit Data
            </button>
            <button
              onClick={handleReset}
              className="flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-gray-600 bg-gray-100 rounded-lg hover:bg-gray-200 transition-colors ml-auto"
            >
              <Plus className="w-4 h-4" />
              New Extraction
            </button>
          </div>

          {/* PDF Preview */}
          <div className="bg-white border border-gray-200 rounded-xl overflow-hidden shadow-sm">
            <div className="bg-gray-50 px-4 py-2 border-b border-gray-200 flex items-center gap-2">
              <FileText className="w-4 h-4 text-blue-500" />
              <span className="text-sm font-medium text-gray-700">
                PO-{poData.po_number || 'draft'}.pdf
              </span>
            </div>
            <iframe
              src={pdfUrl}
              className="w-full border-0"
              style={{ height: '80vh' }}
              title="Purchase Order Preview"
            />
          </div>
        </div>
      )}
    </div>
  );
}

// ============================================================================
// Reusable Input Field Component
// ============================================================================

function InputField({
  label,
  value,
  onChange,
  type = 'text',
  className = '',
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  className?: string;
}) {
  return (
    <div className={className}>
      <label className="block text-xs font-medium text-gray-500 mb-1">{label}</label>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full px-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-400 focus:border-transparent bg-white"
      />
    </div>
  );
}
