const dateFmt = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short' });
const timeFmt = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
const dateTimeFmt = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });

export const fmtDate = (ms: number) => dateFmt.format(ms);
export const fmtTime = (ms: number) => timeFmt.format(ms);
export const fmtDateTime = (ms: number) => dateTimeFmt.format(ms);
export const pkr = (n: number) => `PKR ${n.toLocaleString('en-US')}`;

export const statusLabel = (s: string) =>
  ({ requested: 'Requested', confirmed: 'Confirmed', completed: 'Completed', cancelled: 'Cancelled', no_show: 'Missed', declined: 'Declined' })[s] ?? s;

/** Only a plain https address becomes a link; anything else is shown as text. */
export function safeHttps(url: string): string | null {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' ? u.toString() : null;
  } catch {
    return null;
  }
}

/** Local midnight of the day [daysFromToday] from now, in ms. */
export function dayStart(daysFromToday = 0): number {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + daysFromToday);
  return d.getTime();
}

/** yyyy-mm-dd for an <input type="date">, in local time. */
export const toInputDate = (ms: number) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

export const fromInputDate = (v: string): number | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  return m ? new Date(+m[1], +m[2] - 1, +m[3]).getTime() : null;
};
