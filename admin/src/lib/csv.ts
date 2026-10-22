// Saving a table as a CSV file. A cell that starts with = + - @ (or a tab or return) would be run as a formula by a spreadsheet, so it is
// prefixed with an apostrophe; numbers are written as they are.
export type Cell = string | number | null | undefined;

export function csvCell(v: Cell): string {
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : '';
  let s = String(v ?? '');
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export const toCsv = (rows: Cell[][]): string => `${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n`;

export function downloadCsv(filename: string, rows: Cell[][]): void {
  // The byte-order mark makes Excel read the file as UTF-8, so names with accents survive.
  const blob = new Blob([`﻿${toCsv(rows)}`], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
