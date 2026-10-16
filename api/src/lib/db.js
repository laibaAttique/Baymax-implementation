// A small interface over the Realtime Database so the routes can be tested without Firebase.
//   get(path) -> value | null          update(multiPathUpdates) -> void (null deletes)
//   byChild(path, child, value) -> { id: record }      newKey(path) -> string

/** The real database, through the Firebase Admin SDK (which bypasses the security rules; the routes do their own checks). */
export function adminDb(database) {
  return {
    async get(path) {
      const snap = await database.ref(path).get();
      return snap.exists() ? snap.val() : null;
    },
    async update(updates) {
      await database.ref().update(updates);
    },
    async byChild(path, child, value) {
      const snap = await database.ref(path).orderByChild(child).equalTo(value).get();
      return snap.exists() ? snap.val() : {};
    },
    newKey(path) {
      return database.ref(path).push().key;
    },
  };
}

/** An in-memory database for tests. */
export function memoryDb(initial = {}) {
  const root = structuredClone(initial);
  let counter = 0;
  const walk = (path, create = false) => {
    const parts = path.split('/').filter(Boolean);
    let node = root;
    for (const p of parts) {
      if (node == null || typeof node !== 'object') return undefined;
      if (!(p in node)) {
        if (!create) return undefined;
        node[p] = {};
      }
      node = node[p];
    }
    return node;
  };
  const setAt = (path, value) => {
    const parts = path.split('/').filter(Boolean);
    const last = parts.pop();
    const parent = parts.length ? walk(parts.join('/'), true) : root;
    if (value === null) {
      delete parent[last];
      // prune empty parents like the real database does
      for (let i = parts.length; i > 0; i--) {
        const node = walk(parts.slice(0, i).join('/'));
        if (node && Object.keys(node).length === 0) {
          const up = i > 1 ? walk(parts.slice(0, i - 1).join('/')) : root;
          delete up[parts[i - 1]];
        } else break;
      }
    } else {
      parent[last] = structuredClone(value);
    }
  };
  return {
    root,
    async get(path) {
      const v = walk(path);
      return v === undefined ? null : structuredClone(v);
    },
    async update(updates) {
      // The real database refuses undefined anywhere in a write; do the same here so such mistakes show up in tests.
      const bad = (v, at) => {
        if (v === undefined) throw new Error(`update failed: values argument contains undefined in property '${at}'`);
        if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) bad(x, `${at}.${k}`);
      };
      for (const [path, value] of Object.entries(updates)) bad(value, path.replaceAll('/', '.'));
      for (const [path, value] of Object.entries(updates)) setAt(path, value);
    },
    async byChild(path, child, value) {
      const node = walk(path) ?? {};
      return structuredClone(Object.fromEntries(Object.entries(node).filter(([, v]) => v && v[child] === value)));
    },
    newKey() {
      return `-test${String(++counter).padStart(4, '0')}`;
    },
  };
}
