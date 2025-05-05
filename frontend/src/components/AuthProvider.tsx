"use client";

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { createClient } from '@/lib/supabase/client';
import { User, Session } from '@supabase/supabase-js';
import { SupabaseClient } from '@supabase/supabase-js';

type AuthContextType = {
  supabase: SupabaseClient;
  session: Session | null;
  user: User | null;
  isLoading: boolean;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const supabase = createClient();
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const getInitialSession = async () => {
      // Check if we're in local mode
      if (process.env.NEXT_PUBLIC_ENV_MODE === 'LOCAL') {
        // Create a mock session and user for local development
        const mockUser = {
          id: 'local-user-123',
          email: 'local@example.com',
          user_metadata: {
            full_name: 'Local User',
          },
          app_metadata: {},
          aud: 'authenticated',
          created_at: new Date().toISOString(),
        } as User;
        
        const mockSession = {
          access_token: 'mock-token',
          refresh_token: 'mock-refresh-token',
          expires_in: 3600,
          expires_at: Math.floor(Date.now() / 1000) + 3600,
          token_type: 'bearer',
          user: mockUser,
        } as Session;
        
        setSession(mockSession);
        setUser(mockUser);
        setIsLoading(false);
        return;
      }
      
      // Normal authentication flow for non-local environments
      const { data: { session: currentSession } } = await supabase.auth.getSession();
      setSession(currentSession);
      setUser(currentSession?.user ?? null);
      setIsLoading(false);
    };

    getInitialSession();

    // Only set up auth listener if not in local mode
    if (process.env.NEXT_PUBLIC_ENV_MODE !== 'LOCAL') {
      const { data: authListener } = supabase.auth.onAuthStateChange(
        (_event, newSession) => {
          setSession(newSession);
          setUser(newSession?.user ?? null);
          // No need to set loading state here as initial load is done
          // and subsequent changes shouldn't show a loading state for the whole app
          if (isLoading) setIsLoading(false);
        }
      );

      return () => {
        authListener?.subscription.unsubscribe();
      };
    }
    
    return () => {}; // Empty cleanup function for local mode
  }, [supabase, isLoading]); // Added isLoading to dependencies to ensure it runs once after initial load completes

  const signOut = async () => {
    if (process.env.NEXT_PUBLIC_ENV_MODE === 'LOCAL') {
      // In local mode, just reset the state
      setSession(null);
      setUser(null);
      return;
    }
    
    await supabase.auth.signOut();
    // State updates will be handled by onAuthStateChange
  };

  const value = {
    supabase,
    session,
    user,
    isLoading,
    signOut,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = (): AuthContextType => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}; 