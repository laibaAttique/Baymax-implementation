const dateTimeFmt = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
export const fmtDateTime = (ms: number) => dateTimeFmt.format(ms);
export const pkr = (n: number) => `PKR ${n.toLocaleString('en-US')}`;
