"use client";

import React, { useState, Suspense, useEffect, useRef } from 'react';
import { Skeleton } from "@/components/ui/skeleton";
import { useRouter } from 'next/navigation';
import { Menu } from "lucide-react";
import { ChatInput, ChatInputHandles } from '@/components/thread/chat-input';
import { initiateAgent, createThread, addUserMessage, startAgent, createProject, BillingError } from "@/lib/api";
import { generateThreadName } from "@/lib/actions/threads";
import { useIsMobile } from "@/hooks/use-mobile";
import { useSidebar } from "@/components/ui/sidebar";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { useBillingError } from "@/hooks/useBillingError";
import { BillingErrorAlert } from "@/components/billing/usage-limit-alert";
import { useAccounts } from "@/hooks/use-accounts";
import { isLocalMode, config } from "@/lib/config";
import { toast } from "sonner";

// Constant for localStorage key to ensure consistency
const PENDING_PROMPT_KEY = 'pendingAgentPrompt';

function DashboardContent() {
  const [inputValue, setInputValue] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [autoSubmit, setAutoSubmit] = useState(false);
  const { billingError, handleBillingError, clearBillingError } = useBillingError();
  const router = useRouter();
  const isMobile = useIsMobile();
  const { setOpenMobile } = useSidebar();
  const { data: accounts } = useAccounts();
  const personalAccount = accounts?.find(account => account.personal_account);
  const chatInputRef = useRef<ChatInputHandles>(null);

  const handleSubmit = async (message: string, options?: { model_name?: string; enable_thinking?: boolean; reasoning_effort?: string; stream?: boolean; enable_context_manager?: boolean }) => {
    if ((!message.trim() && !(chatInputRef.current?.getPendingFiles().length)) || isSubmitting) return;

    setIsSubmitting(true);

    try {
      const files = chatInputRef.current?.getPendingFiles() || [];
      localStorage.removeItem(PENDING_PROMPT_KEY);

      if (files.length > 0) {
        // ---- Handle submission WITH files ----
        console.log(`Submitting with message: "${message}" and ${files.length} files.`);
        const formData = new FormData();

        // Use 'prompt' key instead of 'message'
        formData.append('prompt', message);

        // Append files
        files.forEach((file, index) => {
          formData.append('files', file, file.name);
        });

        // Append options individually instead of bundled 'options' field
        if (options?.model_name) formData.append('model_name', options.model_name);
        // Default values from backend signature if not provided in options:
        formData.append('enable_thinking', String(options?.enable_thinking ?? false));
        formData.append('reasoning_effort', options?.reasoning_effort ?? 'low');
        formData.append('stream', String(options?.stream ?? true));
        formData.append('enable_context_manager', String(options?.enable_context_manager ?? false));

        console.log('FormData content:', Array.from(formData.entries()));

        const result = await initiateAgent(formData);
        console.log('Agent initiated with files:', result);

        if (result.thread_id) {
          router.push(`/agents/${result.thread_id}`);
        } else {
          throw new Error("Agent initiation did not return a thread_id.");
        }
        chatInputRef.current?.clearPendingFiles();

      } else {
        // ---- Handle text-only messages (NO CHANGES NEEDED HERE) ----
        console.log(`Submitting text-only message: "${message}"`);
        const projectName = await generateThreadName(message);
        const newProject = await createProject({ name: projectName, description: "" });
        const thread = await createThread(newProject.id);
        await addUserMessage(thread.thread_id, message);
        await startAgent(thread.thread_id, options); // Pass original options here
        router.push(`/agents/${thread.thread_id}`);
      }
    } catch (error: any) {
        console.error('Error during submission process:', error);
        if (error instanceof BillingError) {
             // Delegate billing error handling
             console.log("Handling BillingError:", error.detail);
             handleBillingError({
                message: error.detail.message || 'Monthly usage limit reached. Please upgrade your plan.',
                currentUsage: error.detail.currentUsage as number | undefined,
                limit: error.detail.limit as number | undefined,
                subscription: error.detail.subscription || {
                    price_id: config.SUBSCRIPTION_TIERS.FREE.priceId,
                    plan_name: "Free"
                }
             });
             setIsSubmitting(false);
             return; // Stop further processing for billing errors
        }

        // Handle other errors
        const isConnectionError = error instanceof TypeError && error.message.includes('Failed to fetch');
        if (!isLocalMode() || isConnectionError) {
           toast.error(error.message || "An unexpected error occurred");
        }
        setIsSubmitting(false); // Reset submitting state on all errors
    }
  };

  // Check for pending prompt in localStorage on mount
  useEffect(() => {
    // Use a small delay to ensure we're fully mounted
    const timer = setTimeout(() => {
      const pendingPrompt = localStorage.getItem(PENDING_PROMPT_KEY);
      
      if (pendingPrompt) {
        setInputValue(pendingPrompt);
        setAutoSubmit(true); // Flag to auto-submit after mounting
      }
    }, 200);
    
    return () => clearTimeout(timer);
  }, []);

  // Auto-submit the form if we have a pending prompt
  useEffect(() => {
    if (autoSubmit && inputValue && !isSubmitting) {
      const timer = setTimeout(() => {
        handleSubmit(inputValue);
        setAutoSubmit(false);
      }, 500);
      
      return () => clearTimeout(timer);
    }
  }, [autoSubmit, inputValue, isSubmitting]);

  return (
    <div className="flex flex-col items-center justify-center h-full w-full">
      {isMobile && (
        <div className="absolute top-4 left-4 z-10">
          <Tooltip>
            <TooltipTrigger asChild>
              <Button 
                variant="ghost" 
                size="icon"
                className="h-8 w-8" 
                onClick={() => setOpenMobile(true)}
              >
                <Menu className="h-4 w-4" />
                <span className="sr-only">Open menu</span>
              </Button>
            </TooltipTrigger>
            <TooltipContent>Open menu</TooltipContent>
          </Tooltip>
        </div>
      )}

      <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-[560px] max-w-[90%]">
        <div className="text-center mb-10">
          <h1 className="text-4xl font-medium text-foreground mb-2">Hey </h1>
          <h2 className="text-2xl text-muted-foreground">What would you like Suna to do today?</h2>
        </div>
        
        <ChatInput 
          ref={chatInputRef}
          onSubmit={handleSubmit} 
          loading={isSubmitting}
          placeholder="Describe what you need help with..."
          value={inputValue}
          onChange={setInputValue}
          hideAttachments={false}
        />
      </div>
      
      {/* Billing Error Alert */}
      <BillingErrorAlert
        message={billingError?.message}
        currentUsage={billingError?.currentUsage}
        limit={billingError?.limit}
        accountId={personalAccount?.account_id}
        onDismiss={clearBillingError}
        isOpen={!!billingError}
      />
    </div>
  );
}

export default function DashboardPage() {
  return (
    <Suspense fallback={
      <div className="flex flex-col items-center justify-center h-full w-full">
        <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-[560px] max-w-[90%]">
          <div className="flex flex-col items-center text-center mb-10">
            <Skeleton className="h-10 w-40 mb-2" />
            <Skeleton className="h-7 w-56" />
          </div>
          
          <Skeleton className="w-full h-[100px] rounded-xl" />
          <div className="flex justify-center mt-3">
            <Skeleton className="h-5 w-16" />
          </div>
        </div>
      </div>
    }>
      <DashboardContent />
    </Suspense>
  );
}
