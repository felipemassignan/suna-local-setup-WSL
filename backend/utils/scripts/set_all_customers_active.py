#!/usr/bin/env python
"""
Script to set all Stripe customers in the database to active status.

Usage:
    python update_customer_status.py

This script:
1. Queries all customer IDs from basejump.billing_customers
2. Sets all customers' active field to True in the database

Make sure your environment variables are properly set:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
"""

import asyncio
import sys
import os
from typing import List, Dict, Any
from dotenv import load_dotenv

# Load script-specific environment variables
load_dotenv(".env")

from services.supabase import DBConnection
from utils.logger import logger

# Semaphore to limit concurrent database connections
DB_CONNECTION_LIMIT = 20
db_semaphore = asyncio.Semaphore(DB_CONNECTION_LIMIT)

# Global DB connection to reuse
db_connection = None


async def get_all_customers() -> List[Dict[str, Any]]:
    """
    Query all customers from the database.
    
    Returns:
        List of customers with their ID and account_id
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
        'account_id',
        'active'
    ).execute()
    
    # Print the query result
    print(f"Found {len(result.data)} customers in database")
    print(result.data)
    
    if not result.data:
        logger.info("No customers found in database")
        return []
    
    return result.data


async def update_all_customers_to_active() -> Dict[str, int]:
    """
    Update all customers to active status in the database.
    
    Returns:
        Dict with count of updated customers
    """
    try:
        global db_connection
        if db_connection is None:
            db_connection = DBConnection()
        
        client = await db_connection.client
        
        # Update all customers to active
        result = await client.schema('basejump').from_('billing_customers').update(
            {'active': True}
        ).filter('id', 'neq', None).execute()
        
        updated_count = len(result.data) if hasattr(result, 'data') else 0
        logger.info(f"Updated {updated_count} customers to active status")
        print(f"Updated {updated_count} customers to active status")
        print("Result:", result)
        
        return {'updated': updated_count}
    except Exception as e:
        logger.error(f"Error updating customers in database: {str(e)}")
        return {'updated': 0, 'error': str(e)}


async def main():
    """Main function to run the script."""
    logger.info("Starting customer status update process")
    
    try:
        # Initialize global DB connection
        global db_connection
        db_connection = DBConnection()
        
        # Get all customers from the database
        customers = await get_all_customers()
        
        if not customers:
            logger.info("No customers to process")
            return
        
        # Ask for confirmation before proceeding
        confirm = input(f"\nSet all {len(customers)} customers to active? (y/n): ")
        if confirm.lower() != 'y':
            logger.info("Operation cancelled by user")
            return
        
        # Update all customers to active
        results = await update_all_customers_to_active()
        
        # Print summary
        print("\nCustomer Status Update Summary:")
        print(f"Total customers set to active: {results.get('updated', 0)}")
        
        logger.info("Customer status update completed")
            
    except Exception as e:
        logger.error(f"Error during customer status update: {str(e)}")
        sys.exit(1)
    finally:
        # Clean up database connection
        if db_connection:
            await DBConnection.disconnect()


if __name__ == "__main__":
    asyncio.run(main()) 