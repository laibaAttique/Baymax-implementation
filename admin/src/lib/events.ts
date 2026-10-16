/** Tells the menu to re-count right away (a request was answered), instead of waiting for its next 30-second check. */
export const SUMMARY_EVENT = 'baymax:refresh-summary';
export const refreshSummary = () => {
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(SUMMARY_EVENT));
};
