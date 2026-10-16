'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { onAuthStateChanged, signOut as fbSignOut } from 'firebase/auth';
import { firebaseAuth, firebaseConfigured } from './firebase';
import { api, ApiError } from './api';
import type { Me } from './types';

type State =
  | { status: 'loading' }
  | { status: 'signedOut' }
  | { status: 'denied'; message: string }
  | { status: 'error'; message: string }
  | { status: 'ready'; me: Me };

interface AuthContextValue {
  state: State;
  signOut: () => Promise<void>;
  refreshMe: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<State>({ status: 'loading' });

  const loadMe = useCallback(async () => {
    try {
      const me = await api<Me>('/me');
      setState({ status: 'ready', me });
    } catch (e) {
      if (e instanceof ApiError && e.status === 403) setState({ status: 'denied', message: e.message });
      else if (e instanceof ApiError && e.status === 401) setState({ status: 'signedOut' });
      else setState({ status: 'error', message: e instanceof Error ? e.message : 'Something went wrong.' });
    }
  }, []);

  useEffect(() => {
    if (!firebaseConfigured) {
      setState({ status: 'signedOut' });
      return;
    }
    return onAuthStateChanged(firebaseAuth(), (user) => {
      if (!user) setState({ status: 'signedOut' });
      else {
        setState({ status: 'loading' });
        void loadMe();
      }
    });
  }, [loadMe]);

  const value = useMemo<AuthContextValue>(
    () => ({
      state,
      signOut: async () => {
        await fbSignOut(firebaseAuth());
      },
      refreshMe: loadMe,
    }),
    [state, loadMe],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}

/** The signed-in specialist. Only call this inside the portal layout, which renders children only when ready. */
export function useMe(): Me {
  const { state } = useAuth();
  if (state.status !== 'ready') throw new Error('useMe called before sign-in finished');
  return state.me;
}
