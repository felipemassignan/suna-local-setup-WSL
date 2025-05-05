#!/usr/bin/env python
"""
Script to check Stripe subscriptions for all customers and update their active status.

Usage:
    python update_customer_active_status.py

This script:
1. Queries all customers from basejump.billing_customers
2. Checks subscription status directly on Stripe using customer_id
3. Updates customer active status in database

Make sure your environment variables are properly set:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- STRIPE_SECRET_KEY
"""

import asyncio
import sys
import os
import time
from typing import List, Dict, Any, Tuple
from dotenv import load_dotenv
import stripe

# Load script-specific environment variables
load_dotenv(".env")

# Import relative modules
from services.supabase import DBConnection
from utils.logger import logger
from utils.config import config

# Initialize Stripe with the API key
stripe.api_key = config.STRIPE_SECRET_KEY

# Batch size settings
BATCH_SIZE = 100  # Process customers in batches
MAX_CONCURRENCY = 20  # Maximum concurrent Stripe API calls

# Global DB connection to reuse
db_connection = None

async def get_all_customers() -> List[Dict[str, Any]]:
    """
    Query all customers from the database.
    
    Returns:
        List of customers with their ID (customer_id is used for Stripe)
    """
    global db_connection
    if db_connection is None:
        db_connection = DBConnection()
    
    client = await db_connection.client
    
    # Print the Supabase URL being used
    print(f"Using Supabase URL: {os.getenv('SUPABASE_URL')}")
    
    # Query all customers from billing_customers
    result = await client.schema('basejump').from_('billing_customers').select(
        'id', 
        'active'
    ).execute()
    
    # Print the query result
    print(f"Found {len(result.data)} customers in database")
    
    if not result.data:
        logger.info("No customers found in database")
        return []
    
    return result.data

async def check_stripe_subscription(customer_id: str) -> bool:
    """
    Check if a customer has an active subscription directly on Stripe.
    
    Args:
        customer_id: Customer ID (billing_customers.id) which is the Stripe customer ID
    
    Returns:
        True if customer has at least one active subscription, False otherwise
    """
    if not customer_id:
        print(f"⚠️ Empty customer_id")
        return False
    
    try:
        # Print what we're checking for debugging
        print(f"Checking Stripe subscriptions for customer: {customer_id}")
        
        # List all subscriptions for this customer directly on Stripe
        subscriptions = stripe.Subscription.list(
            customer=customer_id,
            status='active',  # Only get active subscriptions
            limit=1  # We only need to know if there's at least one
        )
        
        # Print the raw data for debugging
        print(f"Stripe returned data: {subscriptions.data}")
        
        # If there's at least one active subscription, the customer is active
        has_active_subscription = len(subscriptions.data) > 0
        
        if has_active_subscription:
            print(f"✅ Customer {customer_id} has ACTIVE subscription")
        else:
            print(f"❌ Customer {customer_id} has NO active subscription")
            
        return has_active_subscription
    
    except Exception as e:
        logger.error(f"Error checking Stripe subscription for customer {customer_id}: {str(e)}")
        print(f"⚠️ Error checking subscription for {customer_id}: {str(e)}")
        return False

async def process_customer_batch(batch: List[Dict[str, Any]], batch_number: int, total_batches: int) -> Dict[str, bool]:
    """
    Process a batch of customers by checking their Stripe subscriptions concurrently.
    
    Args:
        batch: List of customer records in this batch
        batch_number: Current batch number (for logging)
        total_batches: Total number of batches (for logging)
    
    Returns:
        Dictionary mapping customer IDs to subscription status (True/False)
    """
    start_time = time.time()
    batch_size = len(batch)
    print(f"Processing batch {batch_number}/{total_batches} ({batch_size} customers)...")
    
    # Create a semaphore to limit concurrency within the batch to avoid rate limiting
    semaphore = asyncio.Semaphore(MAX_CONCURRENCY)
    
    async def check_single_customer(customer: Dict[str, Any]) -> Tuple[str, bool]:
        async with semaphore:  # Limit concurrent API calls
            customer_id = customer['id']
            
            # Check directly on Stripe - customer_id IS the Stripe customer ID
            is_active = await check_stripe_subscription(customer_id)
            return customer_id, is_active
    
    # Create tasks for all customers in this batch
    tasks = [check_single_customer(customer) for customer in batch]
    
    # Run all tasks in this batch concurrently
    results = await asyncio.gather(*tasks)
    
    # Convert results to dictionary
    subscription_status = {customer_id: status for customer_id, status in results}
    
    end_time = time.time()
    
    # Count active/inactive in this batch
    active_count = sum(1 for status in subscription_status.values() if status)
    inactive_count = batch_size - active_count
    
    print(f"Batch {batch_number} completed in {end_time - start_time:.2f} seconds")
    print(f"Results (batch {batch_number}): {active_count} active, {inactive_count} inactive subscriptions")
    
    return subscription_status

async def update_customer_batch(subscription_status: Dict[str, bool]) -> Dict[str, int]:
    """
    Update a batch of customers in the database.
    
    Args:
        subscription_status: Dictionary mapping customer IDs to active status
    
    Returns:
        Dictionary with statistics about the update
    """
    start_time = time.time()
    
    global db_connection
    if db_connection is None:
        db_connection = DBConnection()
    
    client = await db_connection.client
    
    # Separate customers into active and inactive groups
    active_customers = [cid for cid, status in subscription_status.items() if status]
    inactive_customers = [cid for cid, status in subscription_status.items() if not status]
    
    total_count = len(active_customers) + len(inactive_customers)
    
    # Update statistics
    stats = {
        'total': total_count,
        'active_updated': 0,
        'inactive_updated': 0,
        'errors': 0
    }
    
    # Update active customers in a single operation
    if active_customers:
        try:
            print(f"Updating {len(active_customers)} customers to ACTIVE status")
            await client.schema('basejump').from_('billing_customers').update(
                {'active': True}
            ).in_('id', active_customers).execute()
            
            stats['active_updated'] = len(active_customers)
            logger.info(f"Updated {len(active_customers)} customers to ACTIVE status")
        except Exception as e:
            logger.error(f"Error updating active customers: {str(e)}")
            stats['errors'] += 1
    
    # Update inactive customers in a single operation
    if inactive_customers:
        try:
            print(f"Updating {len(inactive_customers)} customers to INACTIVE status")
            await client.schema('basejump').from_('billing_customers').update(
                {'active': False}
            ).in_('id', inactive_customers).execute()
            
            stats['inactive_updated'] = len(inactive_customers)
            logger.info(f"Updated {len(inactive_customers)} customers to INACTIVE status")
        except Exception as e:
            logger.error(f"Error updating inactive customers: {str(e)}")
            stats['errors'] += 1
    
    end_time = time.time()
    print(f"Database updates completed in {end_time - start_time:.2f} seconds")
    
    return stats

async def main():
    """Main function to run the script."""
    total_start_time = time.time()
    logger.info("Starting customer active status update process")
    
    try:
        # Check Stripe API key
        print(f"Stripe API key configured: {'Yes' if config.STRIPE_SECRET_KEY else 'No'}")
        if not config.STRIPE_SECRET_KEY:
            print("ERROR: Stripe API key not configured. Please set STRIPE_SECRET_KEY in your environment.")
            return
            
        # Initialize global DB connection
        global db_connection
        db_connection = DBConnection()
        
        # Get all customers from the database
        all_customers = await get_all_customers()
        
        if not all_customers:
            logger.info("No customers to process")
            return
        
        # Print a small sample of the customer data
        print("\nCustomer data sample (customer_id = Stripe customer ID):")
        for i, customer in enumerate(all_customers[:5]):  # Show first 5 only
            print(f"  {i+1}. ID: {customer['id']}, Active: {customer.get('active')}")
        if len(all_customers) > 5:
            print(f"  ... and {len(all_customers) - 5} more")
        
        # Split customers into batches
        batches = [all_customers[i:i + BATCH_SIZE] for i in range(0, len(all_customers), BATCH_SIZE)]
        total_batches = len(batches)
        
        # Ask for confirmation before proceeding
        confirm = input(f"\nProcess {len(all_customers)} customers in {total_batches} batches of {BATCH_SIZE}? (y/n): ")
        if confirm.lower() != 'y':
            logger.info("Operation cancelled by user")
            return
        
        # Overall statistics
        all_stats = {
            'total': 0,
            'active_updated': 0,
            'inactive_updated': 0,
            'errors': 0
        }
        
        # Process each batch
        for i, batch in enumerate(batches):
            batch_number = i + 1
            
            # STEP 1: Process this batch of customers
            subscription_status = await process_customer_batch(batch, batch_number, total_batches)
            
            # STEP 2: Update this batch in the database
            batch_stats = await update_customer_batch(subscription_status)
            
            # Accumulate statistics
            all_stats['total'] += batch_stats['total']
            all_stats['active_updated'] += batch_stats['active_updated']
            all_stats['inactive_updated'] += batch_stats['inactive_updated']
            all_stats['errors'] += batch_stats['errors']
            
            # Show batch completion
            print(f"Completed batch {batch_number}/{total_batches}")
            
            # Brief pause between batches to avoid Stripe rate limiting
            if batch_number < total_batches:
                await asyncio.sleep(1)  # 1 second pause between batches
        
        # Print summary
        total_end_time = time.time()
        total_time = total_end_time - total_start_time
        
        print("\nCustomer Status Update Summary:")
        print(f"Total customers processed: {all_stats['total']}")
        print(f"Customers set to active: {all_stats['active_updated']}")
        print(f"Customers set to inactive: {all_stats['inactive_updated']}")
        if all_stats['errors'] > 0:
            print(f"Update errors: {all_stats['errors']}")
        print(f"Total processing time: {total_time:.2f} seconds")
        
        logger.info(f"Customer active status update completed in {total_time:.2f} seconds")
            
    except Exception as e:
        logger.error(f"Error during customer status update: {str(e)}")
        sys.exit(1)
    finally:
        # Clean up database connection
        if db_connection:
            await DBConnection.disconnect()


if __name__ == "__main__":
    asyncio.run(main()) 