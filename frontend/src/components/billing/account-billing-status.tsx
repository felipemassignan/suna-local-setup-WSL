'use client';

import { useEffect, useState } from 'react';
import { Button } from "@/components/ui/button";
import { PricingSection } from "@/components/home/sections/pricing-section";
import { isLocalMode } from "@/lib/config";
import { getSubscription, createPortalSession, SubscriptionStatus } from "@/lib/api";
import { useAuth } from "@/components/AuthProvider";
import { Skeleton } from "@/components/ui/skeleton";

type Props = {
    accountId: string;
    returnUrl: string;
}

export default function AccountBillingStatus({ accountId, returnUrl }: Props) {
    const { session, isLoading: authLoading } = useAuth();
    const [subscriptionData, setSubscriptionData] = useState<SubscriptionStatus | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [isManaging, setIsManaging] = useState(false);

    useEffect(() => {
        async function fetchSubscription() {
            if (authLoading || !session) return;
            
            try {
                const data = await getSubscription();
                setSubscriptionData(data);
                setError(null);
            } catch (err) {
                console.error('Failed to get subscription:', err);
                setError(err instanceof Error ? err.message : 'Failed to load subscription data');
            } finally {
                setIsLoading(false);
            }
        }

        fetchSubscription();
    }, [session, authLoading]);

    const handleManageSubscription = async () => {
        try {
            setIsManaging(true);
            const { url } = await createPortalSession({ return_url: returnUrl });
            window.location.href = url;
        } catch (err) {
            console.error('Failed to create portal session:', err);
            setError(err instanceof Error ? err.message : 'Failed to create portal session');
        } finally {
            setIsManaging(false);
        }
    };

    // In local development mode, show a simplified component
    if (isLocalMode()) {
        return (
            <div className="rounded-xl border shadow-sm bg-card p-6">
                <h2 className="text-xl font-semibold mb-4">Billing Status</h2>
                <div className="p-4 mb-4 bg-muted/30 border border-border rounded-lg text-center">
                    <p className="text-sm text-muted-foreground">
                        Running in local development mode - billing features are disabled
                    </p>
                    <p className="text-xs text-muted-foreground mt-2">
                        Agent usage limits are not enforced in this environment
                    </p>
                </div>
            </div>
        );
    }

    // Show loading state
    if (isLoading || authLoading) {
        return (
            <div className="rounded-xl border shadow-sm bg-card p-6">
                <h2 className="text-xl font-semibold mb-4">Billing Status</h2>
                <div className="space-y-4">
                    <Skeleton className="h-20 w-full" />
                    <Skeleton className="h-40 w-full" />
                    <Skeleton className="h-10 w-full" />
                </div>
            </div>
        );
    }

    // Show error state
    if (error) {
        return (
            <div className="rounded-xl border shadow-sm bg-card p-6">
                <h2 className="text-xl font-semibold mb-4">Billing Status</h2>
                <div className="p-4 mb-4 bg-destructive/10 border border-destructive/20 rounded-lg text-center">
                    <p className="text-sm text-destructive">
                        Error loading billing status: {error}
                    </p>
                </div>
            </div>
        );
    }

    const isPlan = (planId?: string) => {
        return subscriptionData?.plan_name === planId;
    };
    
    const planName = isPlan('free') 
        ? "Free" 
        : isPlan('base')
            ? "Pro"
            : isPlan('extra')
                ? "Enterprise"
                : "Unknown";

    return (
        <div className="rounded-xl border shadow-sm bg-card p-6">
            <h2 className="text-xl font-semibold mb-4">Billing Status</h2>
            
            {subscriptionData ? (
                <>
                    <div className="mb-6">
                        <div className="rounded-lg border bg-background p-4 grid grid-cols-1 md:grid-cols-2 gap-4">                            
                            <div className="flex justify-between items-center">
                                <span className="text-sm font-medium text-foreground/90">Agent Usage This Month</span>
                                <span className="text-sm font-medium text-card-title">
                                    {subscriptionData.current_usage?.toFixed(2) || '0'} / {subscriptionData.minutes_limit || '0'} minutes
                                </span>
                            </div>
                        </div>
                    </div>

                    {/* Plans Comparison */}
                    <PricingSection
                        returnUrl={returnUrl}
                        showTitleAndTabs={false}
                    />

                    {/* Manage Subscription Button */}
                    <Button
                        onClick={handleManageSubscription}
                        disabled={isManaging}
                        className="w-full bg-primary text-white hover:bg-primary/90 shadow-md hover:shadow-lg transition-all"
                    >
                        {isManaging ? "Loading..." : "Manage Subscription"}
                    </Button>
                </>
            ) : (
                <>
                    <div className="mb-6">
                        <div className="rounded-lg border bg-background p-4 gap-4">
                            <div className="flex justify-between items-center">
                                <span className="text-sm font-medium text-foreground/90">Current Plan</span>
                                <span className="text-sm font-medium text-card-title">Free</span>
                            </div>
                            
                            <div className="flex justify-between items-center">
                                <span className="text-sm font-medium text-foreground/90">Agent Usage This Month</span>
                                <span className="text-sm font-medium text-card-title">
                                    {subscriptionData?.current_usage?.toFixed(2) || '0'} / {subscriptionData?.minutes_limit || '0'} minutes
                                </span>
                            </div>
                        </div>
                    </div>

                    {/* Plans Comparison */}
                    <PricingSection
                        returnUrl={returnUrl}
                        showTitleAndTabs={false}
                    />

                    {/* Manage Subscription Button */}
                    <Button
                        onClick={handleManageSubscription}
                        disabled={isManaging}
                        className="w-full bg-primary text-white hover:bg-primary/90 shadow-md hover:shadow-lg transition-all"
                    >
                        {isManaging ? "Loading..." : "Manage Subscription"}
                    </Button>
                </>
            )}
        </div>
    );
}