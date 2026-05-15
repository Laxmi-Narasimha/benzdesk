import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import type { POData } from './extractPO';
import { BENZ_LOGO_BASE64 } from './logoBase64';

// ============================================================================
// BENZ Company Details (hardcoded — always the "Order By" party)
// ============================================================================

const BENZ_DETAILS = {
  name: 'BENZ Packaging Solutions Pvt Ltd',
  address: '83, Sector-5, IMT Manesar, Gurgaon,\nHaryana, India - 122050',
  gstin: '06AAECB8381Q1Z0',
  pan: 'AAECB8381Q',
  email: 'ccare2@benz-packaging.com',
  phone: '+919990744477',
};

// ============================================================================
// Standard Terms & Conditions
// ============================================================================

const TERMS = [
  'Show this PO on all invoices and correspondence.',
  'Pre Dispatch Inspection Report must be sent with each consignment.',
  'Material should be supplied strictly as per our supply schedule which will be sent to you every month.',
  'Rejection will be replaced at vendors cost.',
  'This supersedes all our previous purchase order for all items mentioned in the purchase order.',
  'Please send all supplies with material test certificate.',
];

// ============================================================================
// Format currency
// ============================================================================

function formatCurrency(val: number): string {
  return 'Rs. ' + val.toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatDate(dateStr: string): string {
  if (!dateStr) return '';
  try {
    const d = new Date(dateStr + 'T00:00:00');
    return d.toLocaleDateString('en-IN', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    }).replace(/,/g, ''); // E.g. Mar 30 2026
  } catch {
    return dateStr;
  }
}

// ============================================================================
// Generate Purchase Order PDF
// ============================================================================

export function generatePoPdf(data: POData): Blob {
  const doc = new jsPDF('p', 'mm', 'a4');
  const pageWidth = doc.internal.pageSize.getWidth();
  const margin = 14;
  let y = margin;

  // ---- Colors ----
  const primaryColor: [number, number, number] = [0, 114, 188]; // BENZ blue
  const darkText: [number, number, number] = [33, 33, 33];
  const lightGray: [number, number, number] = [100, 100, 100];
  const tableHeadBg: [number, number, number] = [242, 242, 242];

  // ============================================================
  // HEADER
  // ============================================================
  
  // Logo
  try {
    doc.addImage(BENZ_LOGO_BASE64, 'PNG', margin, y, 42, 14);
  } catch (e) {
    console.warn('Failed to embed logo', e);
  }

  // Title
  doc.setTextColor(...darkText);
  doc.setFontSize(22);
  doc.setFont('helvetica', 'normal');
  doc.text('Purchase Order', pageWidth - margin, y + 10, { align: 'right' });

  y += 24;

  // ============================================================
  // COLUMNS: Order By | Order To | Details
  // ============================================================
  const col1X = margin;
  const col2X = margin + 62;
  const col3X = pageWidth - margin - 65; 

  doc.setFontSize(8);
  doc.setFont('helvetica', 'normal');
  doc.setTextColor(...darkText);

  // -- Column 1: Order By --
  doc.text('Order By', col1X, y);
  doc.setFontSize(10);
  doc.setFont('helvetica', 'bold');
  doc.text(BENZ_DETAILS.name, col1X, y + 5);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  const benzAddr = doc.splitTextToSize(BENZ_DETAILS.address, 55);
  doc.text(benzAddr, col1X, y + 10);
  
  doc.setTextColor(...lightGray);
  doc.text(`GSTIN: `, col1X, y + 20);
  doc.setTextColor(...darkText);
  doc.text(BENZ_DETAILS.gstin, col1X + 11, y + 20);
  
  doc.setTextColor(...lightGray);
  doc.text(`PAN: `, col1X, y + 26);
  doc.setTextColor(...darkText);
  doc.text(BENZ_DETAILS.pan, col1X + 8, y + 26);
  
  doc.setTextColor(...lightGray);
  doc.text(`Email: `, col1X, y + 32);
  doc.setTextColor(...darkText);
  doc.text(BENZ_DETAILS.email, col1X + 9, y + 32);
  
  doc.setTextColor(...lightGray);
  doc.text(`Phone: `, col1X, y + 38);
  doc.setTextColor(...darkText);
  doc.text(BENZ_DETAILS.phone, col1X + 10, y + 38);

  // -- Column 2: Order To --
  doc.setTextColor(...darkText);
  doc.setFontSize(8);
  doc.text('Order To', col2X, y);
  doc.setFontSize(10);
  doc.setFont('helvetica', 'bold');
  const vendName = doc.splitTextToSize(data.vendor_name || 'N/A', 55);
  doc.text(vendName, col2X, y + 5);
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8);
  const vendorYOffset = vendName.length > 1 ? 4 + (vendName.length - 1) * 4 : 0;
  const vendAddr = doc.splitTextToSize(data.vendor_address || '', 55);
  doc.text(vendAddr, col2X, y + 10 + vendorYOffset);
  
  if (data.vendor_gstin) {
    doc.setTextColor(...lightGray);
    doc.text(`GSTIN: `, col2X, y + 20 + vendorYOffset);
    doc.setTextColor(...darkText);
    doc.text(data.vendor_gstin, col2X + 11, y + 20 + vendorYOffset);
  }
  if (data.vendor_pan) {
    doc.setTextColor(...lightGray);
    doc.text(`PAN: `, col2X, y + 26 + vendorYOffset);
    doc.setTextColor(...darkText);
    doc.text(data.vendor_pan, col2X + 8, y + 26 + vendorYOffset);
  }

  // -- Column 3: Details --
  doc.setTextColor(...darkText);
  doc.setFontSize(8);
  doc.text('Details', col3X, y);
  
  const labelX = col3X;
  const valueX = col3X + 28;
  
  doc.setTextColor(...lightGray);
  doc.text('Purchase Order No #', labelX, y + 5);
  doc.setTextColor(...darkText);
  doc.text(data.po_number || 'N/A', valueX, y + 5);

  doc.setTextColor(...lightGray);
  doc.text('Purchase Order Date', labelX, y + 10);
  doc.setTextColor(...darkText);
  doc.text(formatDate(data.po_date), valueX, y + 10);

  doc.setTextColor(...lightGray);
  doc.text('Currency', labelX, y + 15);
  doc.setTextColor(...darkText);
  doc.text(data.currency || 'INR', valueX, y + 15);

  doc.setTextColor(...lightGray);
  doc.text('Freight Charges', labelX, y + 20);
  doc.setTextColor(...darkText);
  doc.text(data.freight_charges || 'N/A', valueX, y + 20);

  doc.setTextColor(...lightGray);
  doc.text('Payment Terms', labelX, y + 25);
  doc.setTextColor(...darkText);
  
  // Handing multi-line payment terms to not overflow the right margin
  const ptText = doc.splitTextToSize(data.payment_terms || 'N/A', pageWidth - margin - valueX);
  doc.text(ptText, valueX, y + 25);

  y += 50; // Space before table

  // ============================================================
  // LINE ITEMS TABLE
  // ============================================================
  const tableHeaders = [
    'Item',
    'HSN/SAC',
    'GST\nRate',
    'Quantity',
    'UoM',
    'Rate',
    'Amount',
    'IGST',
    'Total',
  ];

  const tableBody = (data.items || []).map((item, idx) => [
    `${idx + 1}.  ${item.name}\n\n${item.description || ''}`,
    item.hsn || '-',
    `${item.gst_rate}%`,
    String(item.quantity),
    item.uom || 'Pcs',
    `Rs. ${item.rate.toLocaleString('en-IN')}`,
    formatCurrency(item.amount),
    formatCurrency(item.igst),
    formatCurrency(item.total),
  ]);

  autoTable(doc, {
    startY: y,
    head: [tableHeaders],
    body: tableBody,
    margin: { left: margin, right: margin },
    theme: 'plain',
    headStyles: {
      fillColor: tableHeadBg,
      textColor: darkText,
      fontSize: 8,
      fontStyle: 'normal',
      halign: 'center',
      valign: 'middle',
      cellPadding: 3,
    },
    bodyStyles: {
      fontSize: 8,
      cellPadding: { top: 4, right: 2, bottom: 4, left: 2 },
      textColor: darkText,
    },
    columnStyles: {
      0: { cellWidth: 'auto', halign: 'left' },
      1: { cellWidth: 16, halign: 'center' },
      2: { cellWidth: 12, halign: 'center' },
      3: { cellWidth: 14, halign: 'center' },
      4: { cellWidth: 12, halign: 'center' },
      5: { cellWidth: 20, halign: 'right' },
      6: { cellWidth: 20, halign: 'right' },
      7: { cellWidth: 18, halign: 'right' },
      8: { cellWidth: 22, halign: 'right' },
    },
    willDrawCell: (data) => {
      // Top and bottom borders for the table body to mimic the simple visual separator
      if (data.section === 'body' && data.row.index === (data.table.body.length - 1)) {
        doc.setDrawColor(220, 220, 220);
        doc.setLineWidth(0.2);
        doc.line(data.cell.x, data.cell.y + data.cell.height, data.cell.x + data.cell.width, data.cell.y + data.cell.height);
      }
    },
  });

  y = (doc as any).lastAutoTable?.finalY || y + 40;
  y += 10;

  if (y > doc.internal.pageSize.getHeight() - 60) {
    doc.addPage();
    y = margin;
  }

  // ============================================================
  // TOTALS & TERMS
  // ============================================================
  
  // Terms & Conditions (Left side)
  const termsWidth = (pageWidth - (margin * 2)) * 0.55;
  doc.setTextColor(...darkText);
  doc.setFontSize(8.5);
  doc.setFont('helvetica', 'normal');
  doc.text('Terms and Conditions', margin, y + 2);

  doc.setFontSize(8);
  TERMS.forEach((term, i) => {
    const lines = doc.splitTextToSize(term, termsWidth);
    doc.text(lines, margin, y + 8 + (i * 6));
  });

  // Totals Panel (Right side)
  const totalsWidth = 70;
  const totalsX = pageWidth - margin - totalsWidth;
  
  const totalsData = [
    { label: 'Amount', value: formatCurrency(data.subtotal) },
    { label: 'IGST', value: formatCurrency(data.igst) },
    { label: 'Round on', value: formatCurrency(data.round_off) },
  ];

  doc.setFontSize(8);
  doc.setTextColor(...lightGray);
  let totalY = y + 2;
  totalsData.forEach((row) => {
    doc.text(row.label, totalsX, totalY);
    doc.setTextColor(...darkText);
    doc.text(row.value, totalsX + totalsWidth, totalY, { align: 'right' });
    doc.setTextColor(...lightGray);
    totalY += 6;
  });

  totalY += 2; // small gap for blue block

  // Total (INR) Blue Block
  doc.setFillColor(...primaryColor);
  doc.rect(totalsX - 4, totalY, totalsWidth + 4, 11, 'F');
  
  doc.setFontSize(10);
  doc.setTextColor(255, 255, 255);
  doc.text('Total (INR)', totalsX, totalY + 7);
  doc.setFont('helvetica', 'bold');
  doc.text(formatCurrency(data.total), totalsX + totalsWidth - 2, totalY + 7, { align: 'right' });

  // Return generated blob url
  return doc.output('blob');
}

// ============================================================================
// Generate blob URL for preview
// ============================================================================

export function generatePoPdfUrl(data: POData): string {
  const blob = generatePoPdf(data);
  return URL.createObjectURL(blob);
}
