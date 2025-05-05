"""
Stripe Billing API implementation for Suna on top of Basejump. ONLY HAS SUPPOT FOR USER ACCOUNTS – no team accounts. As we are using the user_id as account_id as is the case with personal accounts. In personal accounts, the account_id equals the user_id. In team accounts, the account_id is unique.

stripe listen --forward-to localhost:8000/api/billing/webhook
"""

from fastapi import APIRouter, HTTPException, Depends, Request
from typing import Optional, Dict, Any, List, Tuple
import stripe
from datetime import datetime, timezone
from utils.logger import logger
from utils.config import config, EnvMode
from services.supabase import DBConnection
from utils.auth_utils import get_current_user_id_from_jwt
from pydantic import BaseModel, Field

# Initialize Stripe
stripe.api_key = config.STRIPE_SECRET_KEY

# Initialize router
router = APIRouter(prefix="/billing", tags=["billing"])

SUBSCRIPTION_TIERS = {
    config.STRIPE_FREE_TIER_ID: {'name': 'free', 'minutes': 10},
    config.STRIPE_TIER_2_20_ID: {'name': 'tier_2_20', 'minutes': 120},  # 2 hours
    config.STRIPE_TIER_6_50_ID: {'name': 'tier_6_50', 'minutes': 360},  # 6 hours
    config.STRIPE_TIER_12_100_ID: {'name': 'tier_12_100', 'minutes': 720},  # 12 hours
    config.STRIPE_TIER_25_200_ID: {'name': 'tier_25_200', 'minutes': 1500},  # 25 hours
    config.STRIPE_TIER_50_400_ID: {'name': 'tier_50_400', 'minutes': 3000},  # 50 hours
    config.STRIPE_TIER_125_800_ID: {'name': 'tier_125_800', 'minutes': 7500},  # 125 hours
    config.STRIPE_TIER_200_1000_ID: {'name': 'tier_200_1000', 'minutes': 12000},  # 200 hours
}

# Pydantic models for request/response validation
class CreateCheckoutSessionRequest(BaseModel):
    price_id: str
    success_url: str
    cancel_url: str

class CreatePortalSessionRequest(BaseModel):
    return_url: str

class SubscriptionStatus(BaseModel):
    status: str # e.g., 'active', 'trialing', 'past_due', 'scheduled_downgrade', 'no_subscription'
    plan_name: Optional[str] = None
    price_id: Optional[str] = None # Added price ID
    current_period_end: Optional[datetime] = None
    cancel_at_period_end: bool = False
    trial_end: Optional[datetime] = None
    minutes_limit: Optional[int] = None
    current_usage: Optional[float] = None
    # Fields for scheduled changes
    has_schedule: bool = False
    scheduled_plan_name: Optional[str] = None
    scheduled_price_id: Optional[str] = None # Added scheduled price ID
    scheduled_change_date: Optional[datetime] = None

# Helper functions
async def get_stripe_customer_id(client, user_id: str) -> Optional[str]:
    """Get the Stripe customer ID for a user."""
    result = await client.schema('basejump').from_('billing_customers') \
        .select('id') \
        .eq('account_id', user_id) \
        .execute()
    
    if result.data and len(result.data) > 0:
        return result.data[0]['id']
    return None

async def create_stripe_customer(client, user_id: str, email: str) -> str:
    """Create a new Stripe customer for a user."""
    # Create customer in Stripe
    customer = stripe.Customer.create(
        email=email,
        metadata={"user_id": user_id}
    )
    
    # Store customer ID in Supabase
    await client.schema('basejump').from_('billing_customers').insert({
        'id': customer.id,
        'account_id': user_id,
        'email': email,
        'provider': 'stripe'
    }).execute()
    
    return customer.id

async def get_user_subscription(user_id: str) -> Optional[Dict]:
    """Get the current subscription for a user from Stripe."""
    try:
        # Get customer ID
        db = DBConnection()
        client = await db.client
        customer_id = await get_stripe_customer_id(client, user_id)
        
        if not customer_id:
            return None
            
        # Get all active subscriptions for the customer
        subscriptions = stripe.Subscription.list(
            customer=customer_id,
            status='active'
        )
        # print("Found subscriptions:", subscriptions)
        
        # Check if we have any subscriptions
        if not subscriptions or not subscriptions.get('data'):
            return None
            
        # Filter subscriptions to only include our product's subscriptions
        our_subscriptions = []
        for sub in subscriptions['data']:
            # Get the first subscription item
            if sub.get('items') and sub['items'].get('data') and len(sub['items']['data']) > 0:
                item = sub['items']['data'][0]
                if item.get('price') and item['price'].get('id') in [
                    config.STRIPE_FREE_TIER_ID,
                    config.STRIPE_TIER_2_20_ID,
                    config.STRIPE_TIER_6_50_ID,
                    config.STRIPE_TIER_12_100_ID,
                    config.STRIPE_TIER_25_200_ID,
                    config.STRIPE_TIER_50_400_ID,
                    config.STRIPE_TIER_125_800_ID,
                    config.STRIPE_TIER_200_1000_ID
                ]:
                    our_subscriptions.append(sub)
        
        if not our_subscriptions:
            return None
            
        # If there are multiple active subscriptions, we need to handle this
        if len(our_subscriptions) > 1:
            logger.warning(f"User {user_id} has multiple active subscriptions: {[sub['id'] for sub in our_subscriptions]}")
            
            # Get the most recent subscription
            most_recent = max(our_subscriptions, key=lambda x: x['created'])
            
            # Cancel all other subscriptions
            for sub in our_subscriptions:
                if sub['id'] != most_recent['id']:
                    try:
                        stripe.Subscription.modify(
                            sub['id'],
                            cancel_at_period_end=True
                        )
                        logger.info(f"Cancelled subscription {sub['id']} for user {user_id}")
                    except Exception as e:
                        logger.error(f"Error cancelling subscription {sub['id']}: {str(e)}")
            
            return most_recent
            
        return our_subscriptions[0]
        
    except Exception as e:
        logger.error(f"Error getting subscription from Stripe: {str(e)}")
        return None

async def calculate_monthly_usage(client, user_id: str) -> float:
    """Calculate total agent run minutes for the current month for a user."""
    # Get start of current month in UTC
    now = datetime.now(timezone.utc)
    start_of_month = datetime(now.year, now.month, 1, tzinfo=timezone.utc)
    
    # First get all threads for this user
    threads_result = await client.table('threads') \
        .select('thread_id') \
        .eq('account_id', user_id) \
        .execute()
    
    if not threads_result.data:
        return 0.0
    
    thread_ids = [t['thread_id'] for t in threads_result.data]
    
    # Then get all agent runs for these threads in current month
    runs_result = await client.table('agent_runs') \
        .select('started_at, completed_at') \
        .in_('thread_id', thread_ids) \
        .gte('started_at', start_of_month.isoformat()) \
        .execute()
    
    if not runs_result.data:
        return 0.0
    
    # Calculate total minutes
    total_seconds = 0
    now_ts = now.timestamp()
    
    for run in runs_result.data:
        start_time = datetime.fromisoformat(run['started_at'].replace('Z', '+00:00')).timestamp()
        if run['completed_at']:
            end_time = datetime.fromisoformat(run['completed_at'].replace('Z', '+00:00')).timestamp()
        else:
            # For running jobs, use current time
            end_time = now_ts
        
        total_seconds += (end_time - start_time)
    
    return total_seconds / 60  # Convert to minutes

async def check_billing_status(client, user_id: str) -> Tuple[bool, str, Optional[Dict]]:
    """
    Check if a user can run agents based on their subscription and usage.
    
    Returns:
        Tuple[bool, str, Optional[Dict]]: (can_run, message, subscription_info)
    """
    if config.ENV_MODE == EnvMode.LOCAL:
        logger.info("Running in local development mode - billing checks are disabled")
        return True, "Local development mode - billing disabled", {
            "price_id": "local_dev",
            "plan_name": "Local Development",
            "minutes_limit": "no limit"
        }
    
    # Get current subscription
    subscription = await get_user_subscription(user_id)
    # print("Current subscription:", subscription)
    
    # If no subscription, they can use free tier
    if not subscription:
        subscription = {
            'price_id': config.STRIPE_FREE_TIER_ID,  # Free tier
            'plan_name': 'free'
        }
    
    # Extract price ID from subscription items
    price_id = None
    if subscription.get('items') and subscription['items'].get('data') and len(subscription['items']['data']) > 0:
        price_id = subscription['items']['data'][0]['price']['id']
    else:
        price_id = subscription.get('price_id', config.STRIPE_FREE_TIER_ID)
    
    # Get tier info - default to free tier if not found
    tier_info = SUBSCRIPTION_TIERS.get(price_id)
    if not tier_info:
        logger.warning(f"Unknown subscription tier: {price_id}, defaulting to free tier")
        tier_info = SUBSCRIPTION_TIERS[config.STRIPE_FREE_TIER_ID]
    
    # Calculate current month's usage
    current_usage = await calculate_monthly_usage(client, user_id)
    
    # Check if within limits
    if current_usage >= tier_info['minutes']:
        return False, f"Monthly limit of {tier_info['minutes']} minutes reached. Please upgrade your plan or wait until next month.", subscription
    
    return True, "OK", subscription

# API endpoints
@router.post("/create-checkout-session")
async def create_checkout_session(
    request: CreateCheckoutSessionRequest,
    current_user_id: str = Depends(get_current_user_id_from_jwt)
):
    """Create a Stripe Checkout session or modify an existing subscription."""
    try:
        # Get Supabase client
        db = DBConnection()
        client = await db.client
        
        # Get user email from auth.users
        user_result = await client.auth.admin.get_user_by_id(current_user_id)
        if not user_result: raise HTTPException(status_code=404, detail="User not found")
        email = user_result.user.email
        
        # Get or create Stripe customer
        customer_id = await get_stripe_customer_id(client, current_user_id)
        if not customer_id: customer_id = await create_stripe_customer(client, current_user_id, email)
        
        # Get the target price and product ID
        try:
            price = stripe.Price.retrieve(request.price_id, expand=['product'])
            product_id = price['product']['id']
        except stripe.error.InvalidRequestError:
            raise HTTPException(status_code=400, detail=f"Invalid price ID: {request.price_id}")
            
        # Verify the price belongs to our product
        if product_id != config.STRIPE_PRODUCT_ID:
            raise HTTPException(status_code=400, detail="Price ID does not belong to the correct product.")
            
        # Check for existing subscription for our product
        existing_subscription = await get_user_subscription(current_user_id)
        # print("Existing subscription for product:", existing_subscription)
        
        if existing_subscription:
            # --- Handle Subscription Change (Upgrade or Downgrade) ---
            try:
                subscription_id = existing_subscription['id']
                subscription_item = existing_subscription['items']['data'][0]
                current_price_id = subscription_item['price']['id']
                
                # Skip if already on this plan
                if current_price_id == request.price_id:
                    return {
                        "subscription_id": subscription_id,
                        "status": "no_change",
                        "message": "Already subscribed to this plan.",
                        "details": {
                            "is_upgrade": None,
                            "effective_date": None,
                            "current_price": round(price['unit_amount'] / 100, 2) if price.get('unit_amount') else 0,
                            "new_price": round(price['unit_amount'] / 100, 2) if price.get('unit_amount') else 0,
                        }
                    }
                
                # Get current and new price details
                current_price = stripe.Price.retrieve(current_price_id)
                new_price = price # Already retrieved
                is_upgrade = new_price['unit_amount'] > current_price['unit_amount']

                if is_upgrade:
                    # --- Handle Upgrade --- Immediate modification
                    updated_subscription = stripe.Subscription.modify(
                        subscription_id,
                        items=[{
                            'id': subscription_item['id'],
                            'price': request.price_id,
                        }],
                        proration_behavior='always_invoice', # Prorate and charge immediately
                        billing_cycle_anchor='now' # Reset billing cycle
                    )
                    
                    # Update active status in database to true (customer has active subscription)
                    await client.schema('basejump').from_('billing_customers').update(
                        {'active': True}
                    ).eq('id', customer_id).execute()
                    logger.info(f"Updated customer {customer_id} active status to TRUE after subscription upgrade")
                    
                    latest_invoice = None
                    if updated_subscription.get('latest_invoice'):
                       latest_invoice = stripe.Invoice.retrieve(updated_subscription['latest_invoice']) 
                    
                    return {
                        "subscription_id": updated_subscription['id'],
                        "status": "updated",
                        "message": "Subscription upgraded successfully",
                        "details": {
                            "is_upgrade": True,
                            "effective_date": "immediate",
                            "current_price": round(current_price['unit_amount'] / 100, 2) if current_price.get('unit_amount') else 0,
                            "new_price": round(new_price['unit_amount'] / 100, 2) if new_price.get('unit_amount') else 0,
                            "invoice": {
                                "id": latest_invoice['id'] if latest_invoice else None,
                                "status": latest_invoice['status'] if latest_invoice else None,
                                "amount_due": round(latest_invoice['amount_due'] / 100, 2) if latest_invoice else 0,
                                "amount_paid": round(latest_invoice['amount_paid'] / 100, 2) if latest_invoice else 0
                            } if latest_invoice else None
                        }
                    }
                else:
                    # --- Handle Downgrade --- Use Subscription Schedule
                    try:
                        current_period_end_ts = subscription_item['current_period_end']
                        
                        # Retrieve the subscription again to get the schedule ID if it exists
                        # This ensures we have the latest state before creating/modifying schedule
                        sub_with_schedule = stripe.Subscription.retrieve(subscription_id)
                        schedule_id = sub_with_schedule.get('schedule')

                        # Get the current phase configuration from the schedule or subscription
                        if schedule_id:
                            schedule = stripe.SubscriptionSchedule.retrieve(schedule_id)
                            # Find the current phase in the schedule
                            # This logic assumes simple schedules; might need refinement for complex ones
                            current_phase = None
                            for phase in reversed(schedule['phases']):
                                if phase['start_date'] <= datetime.now(timezone.utc).timestamp():
                                    current_phase = phase
                                    break
                            if not current_phase: # Fallback if logic fails
                                current_phase = schedule['phases'][-1]
                        else:
                             # If no schedule, the current subscription state defines the current phase
                            current_phase = {
                                'items': existing_subscription['items']['data'], # Use original items data
                                'start_date': existing_subscription['current_period_start'], # Use sub start if no schedule
                                # Add other relevant fields if needed for create/modify
                            }

                        # Prepare the current phase data for the update/create
                        # Ensure items is formatted correctly for the API
                        current_phase_items_for_api = []
                        for item in current_phase.get('items', []):
                            price_data = item.get('price')
                            quantity = item.get('quantity')
                            price_id = None
                            
                            # Safely extract price ID whether it's an object or just the ID string
                            if isinstance(price_data, dict):
                                price_id = price_data.get('id')
                            elif isinstance(price_data, str):
                                price_id = price_data
                            
                            if price_id and quantity is not None:
                                current_phase_items_for_api.append({'price': price_id, 'quantity': quantity})
                            else:
                                logger.warning(f"Skipping item in current phase due to missing price ID or quantity: {item}")
                                
                        if not current_phase_items_for_api:
                             raise ValueError("Could not determine valid items for the current phase.")

                        current_phase_update_data = {
                            'items': current_phase_items_for_api,
                            'start_date': current_phase['start_date'], # Preserve original start date
                            'end_date': current_period_end_ts, # End this phase at period end
                            'proration_behavior': 'none'
                            # Include other necessary fields from current_phase if modifying?
                            # e.g., 'billing_cycle_anchor', 'collection_method'? Usually inherited.
                        }
                        
                        # Define the new (downgrade) phase
                        new_downgrade_phase_data = {
                            'items': [{'price': request.price_id, 'quantity': 1}],
                            'start_date': current_period_end_ts, # Start immediately after current phase ends
                            'proration_behavior': 'none'
                            # iterations defaults to 1, meaning it runs for one billing cycle
                            # then schedule ends based on end_behavior
                        }
                        
                        # Update or Create Schedule
                        if schedule_id:
                             # Update existing schedule, replacing all future phases
                            # print(f"Updating existing schedule {schedule_id}")
                            logger.info(f"Updating existing schedule {schedule_id} for subscription {subscription_id}")
                            logger.debug(f"Current phase data: {current_phase_update_data}")
                            logger.debug(f"New phase data: {new_downgrade_phase_data}")
                            updated_schedule = stripe.SubscriptionSchedule.modify(
                                schedule_id,
                                phases=[current_phase_update_data, new_downgrade_phase_data],
                                end_behavior='release' 
                            )
                            logger.info(f"Successfully updated schedule {updated_schedule['id']}")
                        else:
                             # Create a new schedule using the defined phases
                            print(f"Creating new schedule for subscription {subscription_id}")
                            logger.info(f"Creating new schedule for subscription {subscription_id}")
                            # Deep debug logging - write subscription details to help diagnose issues
                            logger.debug(f"Subscription details: {subscription_id}, current_period_end_ts: {current_period_end_ts}")
                            logger.debug(f"Current price: {current_price_id}, New price: {request.price_id}")
                            
                            try:
                                updated_schedule = stripe.SubscriptionSchedule.create(
                                    from_subscription=subscription_id,
                                    phases=[
                                        {
                                            'start_date': current_phase['start_date'],
                                            'end_date': current_period_end_ts,
                                            'proration_behavior': 'none',
                                            'items': [
                                                {
                                                    'price': current_price_id,
                                                    'quantity': 1
                                                }
                                            ]
                                        },
                                        {
                                            'start_date': current_period_end_ts,
                                            'proration_behavior': 'none',
                                            'items': [
                                                {
                                                    'price': request.price_id,
                                                    'quantity': 1
                                                }
                                            ]
                                        }
                                    ],
                                    end_behavior='release'
                                )
                                # Don't try to link the schedule - that's handled by from_subscription
                                logger.info(f"Created new schedule {updated_schedule['id']} from subscription {subscription_id}")
                                # print(f"Created new schedule {updated_schedule['id']} from subscription {subscription_id}")
                                
                                # Verify the schedule was created correctly
                                fetched_schedule = stripe.SubscriptionSchedule.retrieve(updated_schedule['id'])
                                logger.info(f"Schedule verification - Status: {fetched_schedule.get('status')}, Phase Count: {len(fetched_schedule.get('phases', []))}")
                                logger.debug(f"Schedule details: {fetched_schedule}")
                            except Exception as schedule_error:
                                logger.exception(f"Failed to create schedule: {str(schedule_error)}")
                                raise schedule_error  # Re-raise to be caught by the outer try-except
                        
                        return {
                            "subscription_id": subscription_id,
                            "schedule_id": updated_schedule['id'],
                            "status": "scheduled",
                            "message": "Subscription downgrade scheduled",
                            "details": {
                                "is_upgrade": False,
                                "effective_date": "end_of_period",
                                "current_price": round(current_price['unit_amount'] / 100, 2) if current_price.get('unit_amount') else 0,
                                "new_price": round(new_price['unit_amount'] / 100, 2) if new_price.get('unit_amount') else 0,
                                "effective_at": datetime.fromtimestamp(current_period_end_ts, tz=timezone.utc).isoformat()
                            }
                        }
                    except Exception as e:
                         logger.exception(f"Error handling subscription schedule for sub {subscription_id}: {str(e)}")
                         raise HTTPException(status_code=500, detail=f"Error handling subscription schedule: {str(e)}")
            except Exception as e:
                logger.exception(f"Error updating subscription {existing_subscription.get('id') if existing_subscription else 'N/A'}: {str(e)}")
                raise HTTPException(status_code=500, detail=f"Error updating subscription: {str(e)}")
        else:
            # --- Create New Subscription via Checkout Session ---
            session = stripe.checkout.Session.create(
                customer=customer_id,
                payment_method_types=['card'],
                    line_items=[{'price': request.price_id, 'quantity': 1}],
                mode='subscription',
                success_url=request.success_url,
                cancel_url=request.cancel_url,
                metadata={
                        'user_id': current_user_id,
                        'product_id': product_id
                }
            )
            
            # Update customer status to potentially active (will be confirmed by webhook)
            # This ensures customer is marked as active once payment is completed
            await client.schema('basejump').from_('billing_customers').update(
                {'active': True}
            ).eq('id', customer_id).execute()
            logger.info(f"Updated customer {customer_id} active status to TRUE after creating checkout session")
            
            return {"session_id": session['id'], "url": session['url'], "status": "new"}
        
    except Exception as e:
        logger.exception(f"Error creating checkout session: {str(e)}")
        # Check if it's a Stripe error with more details
        if hasattr(e, 'json_body') and e.json_body and 'error' in e.json_body:
            error_detail = e.json_body['error'].get('message', str(e))
        else:
            error_detail = str(e)
        raise HTTPException(status_code=500, detail=f"Error creating checkout session: {error_detail}")

@router.post("/create-portal-session")
async def create_portal_session(
    request: CreatePortalSessionRequest,
    current_user_id: str = Depends(get_current_user_id_from_jwt)
):
    """Create a Stripe Customer Portal session for subscription management."""
    try:
        # Get Supabase client
        db = DBConnection()
        client = await db.client
        
        # Get customer ID
        customer_id = await get_stripe_customer_id(client, current_user_id)
        if not customer_id:
            raise HTTPException(status_code=404, detail="No billing customer found")
        
        # Ensure the portal configuration has subscription_update enabled
        try:
            # First, check if we have a configuration that already enables subscription update
            configurations = stripe.billing_portal.Configuration.list(limit=100)
            active_config = None
            
            # Look for a configuration with subscription_update enabled
            for config in configurations.get('data', []):
                features = config.get('features', {})
                subscription_update = features.get('subscription_update', {})
                if subscription_update.get('enabled', False):
                    active_config = config
                    logger.info(f"Found existing portal configuration with subscription_update enabled: {config['id']}")
                    break
            
            # If no config with subscription_update found, create one or update the active one
            if not active_config:
                # Find the active configuration or create a new one
                if configurations.get('data', []):
                    default_config = configurations['data'][0]
                    logger.info(f"Updating default portal configuration: {default_config['id']} to enable subscription_update")
                    
                    active_config = stripe.billing_portal.Configuration.update(
                        default_config['id'],
                        features={
                            'subscription_update': {
                                'enabled': True,
                                'proration_behavior': 'create_prorations',
                                'default_allowed_updates': ['price']
                            },
                            # Preserve other features that may already be enabled
                            'customer_update': default_config.get('features', {}).get('customer_update', {'enabled': True, 'allowed_updates': ['email', 'address']}),
                            'invoice_history': {'enabled': True},
                            'payment_method_update': {'enabled': True}
                        }
                    )
                else:
                    # Create a new configuration with subscription_update enabled
                    logger.info("Creating new portal configuration with subscription_update enabled")
                    active_config = stripe.billing_portal.Configuration.create(
                        business_profile={
                            'headline': 'Subscription Management',
                            'privacy_policy_url': config.FRONTEND_URL + '/privacy',
                            'terms_of_service_url': config.FRONTEND_URL + '/terms'
                        },
                        features={
                            'subscription_update': {
                                'enabled': True,
                                'proration_behavior': 'create_prorations',
                                'default_allowed_updates': ['price']
                            },
                            'customer_update': {
                                'enabled': True,
                                'allowed_updates': ['email', 'address']
                            },
                            'invoice_history': {'enabled': True},
                            'payment_method_update': {'enabled': True}
                        }
                    )
            
            # Log the active configuration for debugging
            logger.info(f"Using portal configuration: {active_config['id']} with subscription_update: {active_config.get('features', {}).get('subscription_update', {}).get('enabled', False)}")
        
        except Exception as config_error:
            logger.warning(f"Error configuring portal: {config_error}. Continuing with default configuration.")
        
        # Create portal session using the proper configuration if available
        portal_params = {
            "customer": customer_id,
            "return_url": request.return_url
        }
        
        # Add configuration_id if we found or created one with subscription_update enabled
        if active_config:
            portal_params["configuration"] = active_config['id']
        
        # Create the session
        session = stripe.billing_portal.Session.create(**portal_params)
        
        return {"url": session.url}
        
    except Exception as e:
        logger.error(f"Error creating portal session: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/subscription")
async def get_subscription(
    current_user_id: str = Depends(get_current_user_id_from_jwt)
):
    """Get the current subscription status for the current user, including scheduled changes."""
    try:
        # Get subscription from Stripe (this helper already handles filtering/cleanup)
        subscription = await get_user_subscription(current_user_id)
        # print("Subscription data for status:", subscription)
        
        if not subscription:
            # Default to free tier status if no active subscription for our product
            free_tier_id = config.STRIPE_FREE_TIER_ID
            free_tier_info = SUBSCRIPTION_TIERS.get(free_tier_id)
            return SubscriptionStatus(
                status="no_subscription",
                plan_name=free_tier_info.get('name', 'free') if free_tier_info else 'free',
                price_id=free_tier_id,
                minutes_limit=free_tier_info.get('minutes') if free_tier_info else 0
            )
        
        # Extract current plan details
        current_item = subscription['items']['data'][0]
        current_price_id = current_item['price']['id']
        current_tier_info = SUBSCRIPTION_TIERS.get(current_price_id)
        if not current_tier_info:
            # Fallback if somehow subscribed to an unknown price within our product
             logger.warning(f"User {current_user_id} subscribed to unknown price {current_price_id}. Defaulting info.")
             current_tier_info = {'name': 'unknown', 'minutes': 0}
        
        # Calculate current usage
        db = DBConnection()
        client = await db.client
        current_usage = await calculate_monthly_usage(client, current_user_id)
        
        status_response = SubscriptionStatus(
            status=subscription['status'], # 'active', 'trialing', etc.
            plan_name=subscription['plan'].get('nickname') or current_tier_info['name'],
            price_id=current_price_id,
            current_period_end=datetime.fromtimestamp(current_item['current_period_end'], tz=timezone.utc),
            cancel_at_period_end=subscription['cancel_at_period_end'],
            trial_end=datetime.fromtimestamp(subscription['trial_end'], tz=timezone.utc) if subscription.get('trial_end') else None,
            minutes_limit=current_tier_info['minutes'],
            current_usage=round(current_usage, 2),
            has_schedule=False # Default
        )

        # Check for an attached schedule (indicates pending downgrade)
        schedule_id = subscription.get('schedule')
        if schedule_id:
            try:
                schedule = stripe.SubscriptionSchedule.retrieve(schedule_id)
                # Find the *next* phase after the current one
                next_phase = None
                current_phase_end = current_item['current_period_end']
                
                for phase in schedule.get('phases', []):
                    # Check if this phase starts exactly when the current one ends
                    if phase.get('start_date') == current_phase_end:
                        next_phase = phase
                        break # Found the immediate next phase

                if next_phase:
                    scheduled_item = next_phase['items'][0] # Assuming single item
                    scheduled_price_id = scheduled_item['price'] # Price ID might be string here
                    scheduled_tier_info = SUBSCRIPTION_TIERS.get(scheduled_price_id)
                    
                    status_response.has_schedule = True
                    status_response.status = 'scheduled_downgrade' # Override status
                    status_response.scheduled_plan_name = scheduled_tier_info.get('name', 'unknown') if scheduled_tier_info else 'unknown'
                    status_response.scheduled_price_id = scheduled_price_id
                    status_response.scheduled_change_date = datetime.fromtimestamp(next_phase['start_date'], tz=timezone.utc)
                    
            except Exception as schedule_error:
                logger.error(f"Error retrieving or parsing schedule {schedule_id} for sub {subscription['id']}: {schedule_error}")
                # Proceed without schedule info if retrieval fails

        return status_response
        
    except Exception as e:
        logger.exception(f"Error getting subscription status for user {current_user_id}: {str(e)}") # Use logger.exception
        raise HTTPException(status_code=500, detail="Error retrieving subscription status.")

@router.get("/check-status")
async def check_status(
    current_user_id: str = Depends(get_current_user_id_from_jwt)
):
    """Check if the user can run agents based on their subscription and usage."""
    try:
        # Get Supabase client
        db = DBConnection()
        client = await db.client
        
        can_run, message, subscription = await check_billing_status(client, current_user_id)
        
        return {
            "can_run": can_run,
            "message": message,
            "subscription": subscription
        }
        
    except Exception as e:
        logger.error(f"Error checking billing status: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/webhook")
async def stripe_webhook(request: Request):
    """Handle Stripe webhook events."""
    try:
        # Get the webhook secret from config
        webhook_secret = config.STRIPE_WEBHOOK_SECRET
        
        # Get the webhook payload
        payload = await request.body()
        sig_header = request.headers.get('stripe-signature')
        
        # Verify webhook signature
        try:
            event = stripe.Webhook.construct_event(
                payload, sig_header, webhook_secret
            )
        except ValueError as e:
            raise HTTPException(status_code=400, detail="Invalid payload")
        except stripe.error.SignatureVerificationError as e:
            raise HTTPException(status_code=400, detail="Invalid signature")
        
        # Handle the event
        if event.type in ['customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted']:
            # Extract the subscription and customer information
            subscription = event.data.object
            customer_id = subscription.get('customer')
            
            if not customer_id:
                logger.warning(f"No customer ID found in subscription event: {event.type}")
                return {"status": "error", "message": "No customer ID found"}
            
            # Get database connection
            db = DBConnection()
            client = await db.client
            
            if event.type == 'customer.subscription.created' or event.type == 'customer.subscription.updated':
                # Check if subscription is active
                if subscription.get('status') in ['active', 'trialing']:
                    # Update customer's active status to true
                    await client.schema('basejump').from_('billing_customers').update(
                        {'active': True}
                    ).eq('id', customer_id).execute()
                    logger.info(f"Webhook: Updated customer {customer_id} active status to TRUE based on {event.type}")
                else:
                    # Subscription is not active (e.g., past_due, canceled, etc.)
                    # Check if customer has any other active subscriptions before updating status
                    has_active = len(stripe.Subscription.list(
                        customer=customer_id,
                        status='active',
                        limit=1
                    ).get('data', [])) > 0
                    
                    if not has_active:
                        await client.schema('basejump').from_('billing_customers').update(
                            {'active': False}
                        ).eq('id', customer_id).execute()
                        logger.info(f"Webhook: Updated customer {customer_id} active status to FALSE based on {event.type}")
            
            elif event.type == 'customer.subscription.deleted':
                # Check if customer has any other active subscriptions
                has_active = len(stripe.Subscription.list(
                    customer=customer_id,
                    status='active',
                    limit=1
                ).get('data', [])) > 0
                
                if not has_active:
                    # If no active subscriptions left, set active to false
                    await client.schema('basejump').from_('billing_customers').update(
                        {'active': False}
                    ).eq('id', customer_id).execute()
                    logger.info(f"Webhook: Updated customer {customer_id} active status to FALSE after subscription deletion")
            
            logger.info(f"Processed {event.type} event for customer {customer_id}")
        
        return {"status": "success"}
        
    except Exception as e:
        logger.error(f"Error processing webhook: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
