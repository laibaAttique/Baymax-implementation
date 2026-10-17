/** A small bar chart with no chart library. Every bar is labelled in text below, so it reads without colour or sight. */
export function Bars({
  title,
  data,
  unit,
  height = 120,
}: {
  title: string;
  data: { label: string; value: number }[];
  unit: string;
  height?: number;
}) {
  const max = Math.max(1, ...data.map((d) => d.value));
  const summary = data.map((d) => `${d.label}: ${d.value} ${unit}`).join('; ');
  return (
    <figure className="bars" aria-label={`${title}. ${summary}`}>
      <div className="bars-plot" style={{ height }} aria-hidden>
        {data.map((d) => (
          <div key={d.label} className="bars-col" title={`${d.label}: ${d.value} ${unit}`}>
            <div className="bars-bar" style={{ height: `${Math.max(d.value > 0 ? 4 : 0, (d.value / max) * 100)}%` }} />
          </div>
        ))}
      </div>
      <div className="bars-labels" aria-hidden>
        {data.map((d) => <span key={d.label}>{d.label}</span>)}
      </div>
      <figcaption className="muted small">{title}. Tallest bar: {max} {unit}.</figcaption>
    </figure>
  );
}
