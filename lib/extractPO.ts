// ============================================================================
// OpenAI PO Extraction Helper
// Client-side helper to call OpenAI GPT-4o for PO data extraction
// ============================================================================

// ============================================================================
// Types
// ============================================================================
import * as XLSX from 'xlsx';

export interface POItem {
  name: string;
  description: string;
  hsn: string | null;
  gst_rate: number;
  quantity: number;
  uom: string;
  rate: number;
  amount: number;
  igst: number;
  total: number;
}

export interface POData {
  po_number: string;
  po_date: string;
  vendor_name: string;
  vendor_address: string;
  vendor_gstin: string | null;
  vendor_pan: string | null;
  freight_charges: string;
  payment_terms: string;
  currency: string;
  items: POItem[];
  subtotal: number;
  igst: number;
  round_off: number;
  total: number;
}

// ============================================================================
// Extraction Prompt
// ============================================================================

const EXTRACTION_PROMPT = `You are an expert purchase order and material requisition data extraction assistant. You handle ALL types of documents — printed POs, handwritten material requisition slips, informal purchase notes, scanned receipts, and any other procurement document.

CRITICAL INSTRUCTIONS FOR HANDWRITTEN DOCUMENTS:
- Many documents will be HANDWRITTEN in pen/ink on preprinted forms. Read the handwriting with EXTREME care.
- For numbers: distinguish carefully between 0/6, 1/7, 3/8, 5/6. Look at context (total should equal sum of items).
- For prices: a trailing "/-" or "/" means the number before it is the price. E.g. "1700/-" means 1700. "320/-" means 320.
- For crossed-out text: ignore struck-through or crossed-out values; use the corrected value written nearby.
- If the document says "Aproximate Price" or "Approx Price", that IS the rate/price column.
- For quantities: "02" means 2, "04" means 4, etc.

DOCUMENT TYPE HANDLING:
- If the document is a "Material Requisition Slip" or an internal company slip (from BENZ Packaging), set vendor_name to "" (empty string) and vendor_address to "" — these are internal procurement documents, not external vendor POs.
- If the document is titled "Purchase Order" from an external company, extract the vendor/supplier details normally.
- For internal slips: use the "Requested By" or "Department" field value as a note in the description of the first item.
- For payment_terms: if there is a "Payment Mode" field showing "CASH" or "CREDIT", use that. Otherwise use "N/A".

Return ONLY valid JSON, no markdown fences, no explanation.

The JSON must follow this exact schema:
{
  "po_number": "string (use any reference number, slip number, or date as fallback)",
  "po_date": "YYYY-MM-DD",
  "vendor_name": "string (empty string for internal slips)",
  "vendor_address": "string (empty string if not available)",
  "vendor_gstin": "string or null",
  "vendor_pan": "string or null",
  "freight_charges": "string (e.g. 'Inclusive', 'Extras as actual', or 'N/A')",
  "payment_terms": "string (e.g. '30 Days', 'Cash', 'Credit', 'N/A')",
  "currency": "INR",
  "items": [
    {
      "name": "string (item name — read handwriting carefully)",
      "description": "string (any additional specs, size, or notes)",
      "hsn": "string or null",
      "gst_rate": 0,
      "quantity": number,
      "uom": "string (Pcs, KG, Nos, etc.)",
      "rate": number,
      "amount": number,
      "igst": 0,
      "total": number
    }
  ],
  "subtotal": number,
  "igst": 0,
  "round_off": 0,
  "total": number
}

Rules:
- All monetary values must be numbers (not strings). Remove commas, currency symbols, "/-", "Rs", "Rs." etc.
- If a field is not found, use "" for strings and 0 for numbers.
- Extract ALL line items, not just the first one.
- For items: amount = quantity * rate. If GST is not mentioned, set gst_rate and igst to 0.
- total for each item = amount + igst.
- subtotal = sum of all item amounts. total = subtotal + igst + round_off.
- The "name" should be the product/material name as written.
- The "description" should include size/spec details, or "" if none.
- po_date must be in YYYY-MM-DD format. If the date is like "7/4/26" interpret as 2026-04-07.
- VERIFY: the total should approximately match the sum of individual item amounts. If it doesn't, re-read the prices.`;

// ============================================================================
// The API key — stored as env var, injected at build time
// For internal-only apps behind auth this is acceptable
// ============================================================================
const OPENAI_API_KEY = process.env.NEXT_PUBLIC_OPENAI_API_KEY || '';

// ============================================================================
// Extract PO data from a file
// ============================================================================

export async function extractPOFromFile(
  file: File,
  apiKey?: string
): Promise<POData> {
  const key = apiKey || OPENAI_API_KEY;
  if (!key) {
    throw new Error('OpenAI API key is not configured');
  }

  const base64 = await fileToBase64(file);
  const mimeType = file.type || 'application/octet-stream';
  const isImage = mimeType.startsWith('image/');

  const isExcel = file.name.match(/\.(xlsx|xls|csv)$/i);

  // Build the user message content
  const userContent: any[] = [
    {
      type: 'text',
      text: 'Extract all purchase order data from this document.',
    },
  ];

  if (isExcel) {
    // For Excel/CSV files, read and parse the content directly client-side
    const arrayBuffer = await file.arrayBuffer();
    const workbook = XLSX.read(arrayBuffer, { type: 'array' });
    const firstSheetName = workbook.SheetNames[0];
    const worksheet = workbook.Sheets[firstSheetName];
    const csvContent = XLSX.utils.sheet_to_csv(worksheet);

    userContent.push({
      type: 'text',
      text: `\nHere is the raw data extracted from the purchase order spreadsheet:\n\n${csvContent}`,
    });
  } else if (isImage) {
    userContent.push({
      type: 'image_url',
      image_url: {
        url: `data:${mimeType};base64,${base64}`,
        detail: 'high',
      },
    });
  } else {
    // For PDFs, send as file
    userContent.push({
      type: 'file',
      file: {
        filename: file.name,
        file_data: `data:${mimeType};base64,${base64}`,
      },
    });
  }

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: 'gpt-4o',
      messages: [
        { role: 'system', content: EXTRACTION_PROMPT },
        { role: 'user', content: userContent },
      ],
      max_tokens: 4096,
      temperature: 0.1,
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    console.error('OpenAI error:', response.status, errText);
    throw new Error(`OpenAI API error (${response.status}). Please try again.`);
  }

  const data = await response.json();
  const content = data.choices?.[0]?.message?.content;

  if (!content) {
    throw new Error('No response content from OpenAI');
  }

  // Parse JSON — strip markdown fences if present
  let cleaned = content
    .replace(/```json\s*/g, '')
    .replace(/```\s*/g, '')
    .trim();

  // Sometimes GPT wraps in extra text — find the JSON object
  const jsonStart = cleaned.indexOf('{');
  const jsonEnd = cleaned.lastIndexOf('}');
  if (jsonStart !== -1 && jsonEnd !== -1 && jsonEnd > jsonStart) {
    cleaned = cleaned.substring(jsonStart, jsonEnd + 1);
  }

  try {
    const raw = JSON.parse(cleaned);
    return sanitizePOData(raw);
  } catch {
    console.error('Failed to parse:', cleaned);
    throw new Error('Failed to parse extracted data. Please try with a clearer image or document.');
  }
}

// ============================================================================
// Sanitize extracted data — fill missing fields with safe defaults
// ============================================================================

function sanitizePOData(raw: any): POData {
  const items: POItem[] = (Array.isArray(raw.items) ? raw.items : []).map((item: any) => {
    const quantity = toNum(item?.quantity);
    const rate = toNum(item?.rate);
    const amount = toNum(item?.amount) || Number((quantity * rate).toFixed(2));
    const gst_rate = toNum(item?.gst_rate);
    const igst = toNum(item?.igst) || Number((amount * gst_rate / 100).toFixed(2));
    const total = toNum(item?.total) || Number((amount + igst).toFixed(2));

    return {
      name: toStr(item?.name),
      description: toStr(item?.description),
      hsn: item?.hsn || null,
      gst_rate,
      quantity,
      uom: toStr(item?.uom) || 'Pcs',
      rate,
      amount,
      igst,
      total,
    };
  });

  const subtotal = toNum(raw.subtotal) || items.reduce((s, i) => s + i.amount, 0);
  const igst = toNum(raw.igst) || items.reduce((s, i) => s + i.igst, 0);
  const round_off = toNum(raw.round_off);
  const total = toNum(raw.total) || Number((subtotal + igst + round_off).toFixed(2));

  return {
    po_number: toStr(raw.po_number),
    po_date: toStr(raw.po_date) || new Date().toISOString().split('T')[0],
    vendor_name: toStr(raw.vendor_name),
    vendor_address: toStr(raw.vendor_address),
    vendor_gstin: raw.vendor_gstin || null,
    vendor_pan: raw.vendor_pan || null,
    freight_charges: toStr(raw.freight_charges) || 'N/A',
    payment_terms: toStr(raw.payment_terms) || 'N/A',
    currency: toStr(raw.currency) || 'INR',
    items: items.length > 0 ? items : [{ name: '', description: '', hsn: null, gst_rate: 0, quantity: 0, uom: 'Pcs', rate: 0, amount: 0, igst: 0, total: 0 }],
    subtotal: Number(subtotal.toFixed(2)),
    igst: Number(igst.toFixed(2)),
    round_off: Number(round_off.toFixed(2)),
    total: Number(total.toFixed(2)),
  };
}

function toNum(v: any): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const cleaned = v.replace(/[^0-9.\-]/g, '');
    const n = parseFloat(cleaned);
    return isNaN(n) ? 0 : n;
  }
  return 0;
}

function toStr(v: any): string {
  if (typeof v === 'string') return v;
  if (v === null || v === undefined) return '';
  return String(v);
}

// ============================================================================
// Helpers
// ============================================================================

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      // Remove the data URL prefix to get raw base64
      const base64 = result.split(',')[1];
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
