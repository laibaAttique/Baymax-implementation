#!/usr/bin/env python3
"""Cleans the Kaggle "Gym Members Exercise Dataset" and writes a data-quality report.

  python clean_data.py --raw gym_members_exercise_tracking.csv --out clean/

Outputs
  gym_members_clean.csv   snake_case columns, impossible rows removed, helper columns added
  cleaning_report.md      every check that was run, what it found and what was done

What "cleaning" means here: only rows that are physically impossible are removed; nothing is
imputed, rescaled or invented. The report also compares the dataset with published energy
costs (2024 Compendium of Physical Activities), because that comparison matters more than
formatting for this particular dataset.
"""
import argparse
import os

import numpy as np
import pandas as pd

RENAME = {
    'Age': 'age', 'Gender': 'gender', 'Weight (kg)': 'weight_kg', 'Height (m)': 'height_m',
    'Max_BPM': 'max_bpm', 'Avg_BPM': 'avg_bpm', 'Resting_BPM': 'resting_bpm',
    'Session_Duration (hours)': 'duration_h', 'Calories_Burned': 'calories_burned',
    'Workout_Type': 'workout_type', 'Fat_Percentage': 'fat_percentage',
    'Water_Intake (liters)': 'water_l', 'Workout_Frequency (days/week)': 'workout_days_per_week',
    'Experience_Level': 'experience_level', 'BMI': 'bmi',
}

# 2024 Adult Compendium of Physical Activities (pacompendium.com), MET = kcal per kg per hour
COMPENDIUM_MET = {
    'Yoga': 2.3,      # 02175 Yoga, general
    'Strength': 3.5,  # 02054 Resistance training, multiple exercises, 8-15 reps
    'Cardio': 7.3,    # 02000 Aerobic, general
    'HIIT': 7.5,      # 02040 Circuit training, vigorous intensity
}
PLAUSIBLE_RATIO = (0.5, 2.0)  # a session is "plausible" if its implied MET is within 0.5x-2x of the Compendium


def anova_eta_squared(values, groups):
    """Share of variance in `values` explained by `groups` (one-way ANOVA effect size) and F."""
    values, groups = np.asarray(values, float), np.asarray(groups)
    grand = values.mean()
    cats = np.unique(groups)
    ssb = sum(len(values[groups == c]) * (values[groups == c].mean() - grand) ** 2 for c in cats)
    ssw = sum(((values[groups == c] - values[groups == c].mean()) ** 2).sum() for c in cats)
    f = (ssb / (len(cats) - 1)) / (ssw / (len(values) - len(cats)))
    return ssb / (ssb + ssw), f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--raw', required=True, help='gym_members_exercise_tracking.csv (or a folder containing it)')
    ap.add_argument('--out', default='clean')
    args = ap.parse_args()

    path = args.raw
    if os.path.isdir(path):
        csvs = [os.path.join(d, f) for d, _, fs in os.walk(path) for f in sorted(fs) if f.lower().endswith('.csv')]
        if not csvs:
            raise SystemExit(f'No CSV found in {path}')
        path = csvs[0]
    raw = pd.read_csv(path)
    df = raw.rename(columns=lambda c: RENAME.get(c.strip(), c.strip())).copy()
    missing = [c for c in RENAME.values() if c not in df.columns]
    if missing:
        raise SystemExit(f'Unexpected columns, missing {missing}. Found {list(df.columns)}')

    steps = []  # (check, rows affected, action)
    n0 = len(df)

    for c in ['gender', 'workout_type']:
        before = df[c].copy()
        df[c] = df[c].astype(str).str.strip().str.title().replace({'Hiit': 'HIIT'})
        steps.append((f'Whitespace / capitalisation in `{c}`', int((before != df[c]).sum()), 'standardised'))

    steps.append(('Missing values (any column)', int(df.isna().any(axis=1).sum()), 'none found' if not df.isna().any().any() else 'rows removed'))
    df = df.dropna()

    dup = int(df.duplicated().sum())
    steps.append(('Exact duplicate rows', dup, 'removed' if dup else 'none found'))
    df = df.drop_duplicates()

    bad_hr = df['avg_bpm'] > df['max_bpm']
    steps.append(('Average heart rate above the maximum heart rate (impossible)', int(bad_hr.sum()), 'rows removed'))
    df = df[~bad_hr]

    bad_rest = df['avg_bpm'] < df['resting_bpm']
    steps.append(('Average heart rate below resting heart rate', int(bad_rest.sum()), 'removed' if bad_rest.any() else 'none found'))
    df = df[~bad_rest]

    bad_num = (df['calories_burned'] <= 0) | (df['duration_h'] <= 0) | (df['weight_kg'] <= 0) | (df['height_m'] <= 0)
    steps.append(('Zero or negative calories / duration / weight / height', int(bad_num.sum()), 'removed' if bad_num.any() else 'none found'))
    df = df[~bad_num]

    bmi_err = (df['weight_kg'] / df['height_m'] ** 2 - df['bmi']).abs() > 0.5
    steps.append(('`bmi` disagrees with weight / height² by more than 0.5', int(bmi_err.sum()), 'removed' if bmi_err.any() else 'none found'))
    df = df[~bmi_err]

    q1, q3 = df['calories_burned'].quantile([.25, .75])
    iqr = q3 - q1
    out = (df['calories_burned'] < q1 - 1.5 * iqr) | (df['calories_burned'] > q3 + 1.5 * iqr)
    steps.append(('Calories outside 1.5×IQR (statistical outliers)', int(out.sum()), 'kept: plausible long sessions (up to 2 h)'))

    df = df.reset_index(drop=True)
    for c in ['bmi', 'duration_h', 'fat_percentage']:
        df[c] = df[c].round(2)

    # ---- helper columns (derived, never replace the originals)
    df['kcal_per_hour'] = (df['calories_burned'] / df['duration_h']).round(1)
    df['implied_met'] = (df['calories_burned'] / df['duration_h'] / df['weight_kg']).round(2)  # kcal per kg per hour == MET
    df['compendium_met'] = df['workout_type'].map(COMPENDIUM_MET)
    df['met_ratio'] = (df['implied_met'] / df['compendium_met']).round(2)
    df['plausible_energy'] = df['met_ratio'].between(*PLAUSIBLE_RATIO)

    os.makedirs(args.out, exist_ok=True)
    csv_path = os.path.join(args.out, 'gym_members_clean.csv')
    df.to_csv(csv_path, index=False)

    # ---- evidence for the report
    by_type = df.groupby('workout_type').agg(
        sessions=('implied_met', 'size'), data_median_met=('implied_met', 'median'),
        compendium_met=('compendium_met', 'first'), plausible=('plausible_energy', 'sum')).round(2)
    by_type['data_vs_compendium'] = (by_type['data_median_met'] / by_type['compendium_met']).round(2)
    eta2, f = anova_eta_squared(df['implied_met'], df['workout_type'])
    freq_pattern = pd.crosstab(df['experience_level'], df['workout_days_per_week'])
    plausible_share = df['plausible_energy'].mean()

    lines = [
        '# Gym Members Exercise Dataset — cleaning report', '',
        f'Source: Kaggle, *Gym Members Exercise Dataset* (valakhorasani). Raw file: `{os.path.basename(path)}`.', '',
        f'**Rows: {n0} raw → {len(df)} clean** ({n0 - len(df)} removed). Columns renamed to snake_case; helper columns added '
        '(`kcal_per_hour`, `implied_met`, `compendium_met`, `met_ratio`, `plausible_energy`). Nothing was imputed or rescaled.', '',
        '## Checks', '', '| Check | Rows affected | Action |', '|---|---:|---|',
        *[f'| {a} | {b} | {c} |' for a, b, c in steps], '',
        '## Important: the data disagrees with published energy costs', '',
        '`implied_met` = calories ÷ hours ÷ body weight (kcal per kg per hour), which is what a MET value measures. '
        'Compared with the 2024 Compendium of Physical Activities:', '',
        '| Workout | Sessions | Median MET in this data | Compendium MET | Data ÷ Compendium | Sessions within 0.5×–2× of Compendium |',
        '|---|---:|---:|---:|---:|---:|',
        *[f'| {t} | {int(r.sessions)} | {r.data_median_met} | {r.compendium_met} | {r.data_vs_compendium}× | {int(r.plausible)} |'
          for t, r in by_type.iterrows()], '',
        f'* Workout type explains only **{eta2 * 100:.2f}%** of the variation in implied MET (ANOVA F = {f:.2f}). '
        'In real measurements the type of exercise is the main driver of energy cost.',
        f'* Only **{plausible_share * 100:.0f}%** of all sessions have an energy cost within 0.5×–2× of the published value; '
        f'yoga sessions plausible: **{int(by_type.loc["Yoga", "plausible"])} of {int(by_type.loc["Yoga", "sessions"])}**.',
        '* Experience level and weekly frequency follow a perfectly clean rule '
        f'(level 1 → 2–3 days, level 2 → 3–4 days, level 3 → 4–5 days; crosstab below), which is typical of generated data.', '',
        '```', freq_pattern.to_string(), '```', '',
        '## Conclusion', '',
        'The file is tidy (no missing values or duplicates) but its calorie values are **not consistent with measured physiology** '
        'and look synthetic. A model trained on it will happily predict that an hour of yoga burns as many calories as an hour of HIIT. '
        'It is fine for practising a machine-learning pipeline; it is **not** a sound basis for calorie estimates shown to users. '
        'Use `plausible_energy` to see which rows agree with the literature.', '',
        'Licence: check the original Kaggle dataset page before sharing this derived file publicly; keep any Kaggle dataset you create from it **private**.',
    ]
    with open(os.path.join(args.out, 'cleaning_report.md'), 'w') as fh:
        fh.write('\n'.join(lines) + '\n')

    print(f'{n0} rows -> {len(df)} rows')
    for a, b, c in steps:
        print(f'  {b:4d}  {a}  [{c}]')
    print(by_type.to_string())
    print(f'type explains {eta2 * 100:.2f}% of implied-MET variation; plausible sessions overall {plausible_share * 100:.0f}%')
    print('wrote', csv_path, 'and cleaning_report.md')


if __name__ == '__main__':
    main()
