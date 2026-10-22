'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { onAuthStateChanged, signOut as fbSignOut } from 'firebase/auth';
import { firebaseAuth, firebaseConfigured } from './firebase';
import { api, ApiError, UNAUTHORIZED_EVENT } from './api';
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

const EXPIRED_KEY = 'baymax:session-expired';

/** True once if the person was just signed out because their session ended; the sign-in page then says why. */
export function takeSessionExpired(): boolean {
  try {
    const yes = sessionStorage.getItem(EXPIRED_KEY) === '1';
    sessionStorage.removeItem(EXPIRED_KEY);
    return yes;
  } catch {
    return false;
  }
}

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

  // The API refused our token in the middle of a session (it expired or the account was closed): go back to the sign-in page.
  useEffect(() => {
    const onUnauthorized = () => {
      try {
        sessionStorage.setItem(EXPIRED_KEY, '1');
      } catch {
        // private browsing may refuse storage; the redirect still happens
      }
      setState({ status: 'signedOut' });
      if (firebaseConfigured) void fbSignOut(firebaseAuth());
    };
    window.addEventListener(UNAUTHORIZED_EVENT, onUnauthorized);
    return () => window.removeEventListener(UNAUTHORIZED_EVENT, onUnauthorized);
  }, []);

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
