// Shared helper for the automated test cases (ATC) documented in the report's Chapter 5 (API side).
// Each case has a unique ID that is part of the test's name. When ATC_LOG names a file, every case appends one JSON line with its
// objective, input, expected result, what it actually observed and whether it matched; the report is generated from those lines.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

export const check = (ok, actual) => ({ ok: !!ok, actual });
export const same = (got, want, say) => ({ ok: JSON.stringify(got) === JSON.stringify(want), actual: say ?? JSON.stringify(got) });

export function atc(id, spec, run) {
  test(`${id} ${spec.objective}`, async () => {
    let out;
    try {
      out = await run();
    } catch (e) {
      out = { ok: false, actual: `Error: ${e.message}` };
    }
    const path = process.env.ATC_LOG;
    if (path) {
      const { req, objective, input, expected, table, conds, actions } = spec;
      fs.appendFileSync(path, JSON.stringify({ id, req, objective, input, expected, actual: out.actual, ok: out.ok, tool: 'Node test (API)', ...(table ? { table, conds, actions } : {}) }) + '\n');
    }
    assert.ok(out.ok, out.actual);
  });
}
