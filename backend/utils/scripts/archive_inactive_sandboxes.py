#!/usr/bin/env python
"""
Script to archive sandboxes for projects whose account_id is not associated with an active billing customer.

Usage:
    python archive_inactive_sandboxes.py

This script:
1. Gets all active account_ids from basejump.billing_customers (active=TRUE)
2. Gets all projects from the projects table
3. Archives sandboxes for any project whose account_id is not in the active billing customers list

Make sure your environment variables are properly set:
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY
- DAYTONA_SERVER_URL
"""

import asyncio
import sys
import os
import argparse
from typing import List, Dict, Any, Set
from dotenv import load_dotenv

# Load script-specific environment variables
load_dotenv(".env")

from services.supabase import DBConnection
from sandbox.sandbox import daytona
from utils.logger import logger

# Global DB connection to reuse
db_connection = None


async def get_active_billing_customer_account_ids() -> Set[str]:
    """
    Query all account_ids from the basejump.billing_customers table where active=TRUE.
    
    Returns:
        Set of account_ids that have an active billing customer record
    """
    global db_connection
    if db_connection is None:
        db_connection = DBConnection()
    
    client = await db_connection.client
    
    # Print the Supabase URL being used
    print(f"Using Supabase URL: {os.getenv('SUPABASE_URL')}")
    
    # Query all account_ids from billing_customers where active=true
    result = await client.schema('basejump').from_('billing_customers').select('account_id, active').execute()
    
    # Print the query result
    print(f"Found {len(result.data)} billing customers in database")
    print(result.data)
    
    if not result.data:
        logger.info("No billing customers found in database")
        return set()
    
    # Extract account_ids for active customers and return as a set for fast lookups
    active_account_ids = {customer.get('account_id') for customer in result.data 
                          if customer.get('account_id') and customer.get('active') is True}
    
    print(f"Found {len(active_account_ids)} active billing customers")
    return active_account_ids


async def get_all_projects() -> List[Dict[str, Any]]:
    """
    Query all projects with sandbox information.
    
    Returns:
        List of projects with their sandbox information
    """
    global db_connection
    if db_connection is None:
        db_connection = DBConnection()
    
    client = await db_connection.client
    
    # Initialize variables for pagination
    all_projects = []
    page_size = 1000
    current_page = 0
    has_more = True
    
    logger.info("Starting to fetch all projects (paginated)")
    
    # Paginate through all projects
    while has_more:
        # Query projects with pagination
        start_range = current_page * page_size
        end_range = start_range + page_size - 1
        
        logger.info(f"Fetching projects page {current_page+1} (range: {start_range}-{end_range})")
        
        result = await client.table('projects').select(
            'project_id',
            'name',
            'account_id',
            'sandbox'
        ).range(start_range, end_range).execute()
        
        if not result.data:
            has_more = False
        else:
            all_projects.extend(result.data)
            current_page += 1
            
            # Progress update
            logger.info(f"Loaded {len(all_projects)} projects so far")
            print(f"Loaded {len(all_projects)} projects so far...")
            
            # Check if we've reached the end
            if len(result.data) < page_size:
                has_more = False
    
    # Print the query result
    total_projects = len(all_projects)
    print(f"Found {total_projects} projects in database")
    logger.info(f"Total projects found in database: {total_projects}")
    
    if not all_projects:
        logger.info("No projects found in database")
        return []
    
    # Filter projects that have sandbox information
    projects_with_sandboxes = [
        project for project in all_projects
        if project.get('sandbox') and project['sandbox'].get('id')
    ]
    
    logger.info(f"Found {len(projects_with_sandboxes)} projects with sandboxes")
    return projects_with_sandboxes


async def archive_sandbox(project: Dict[str, Any], dry_run: bool) -> bool:
    """
    Archive a single sandbox.
    
    Args:
        project: Project information containing sandbox to archive
        dry_run: If True, only simulate archiving
        
    Returns:
        True if successful, False otherwise
    """
    sandbox_id = project['sandbox'].get('id')
    project_name = project.get('name', 'Unknown')
    project_id = project.get('project_id', 'Unknown')
    
    try:
        logger.info(f"Checking sandbox {sandbox_id} for project '{project_name}' (ID: {project_id})")
        
        if dry_run:
            logger.info(f"DRY RUN: Would archive sandbox {sandbox_id}")
            print(f"Would archive sandbox {sandbox_id} for project '{project_name}'")
            return True
        
        # Get the sandbox
        sandbox = daytona.get_current_sandbox(sandbox_id)
        
        # Check sandbox state - it must be stopped before archiving
        sandbox_info = sandbox.info()
        
        # Log the current state
        logger.info(f"Sandbox {sandbox_id} is in '{sandbox_info.state}' state")
        
        # Only archive if the sandbox is in the stopped state
        if sandbox_info.state == "stopped":
            logger.info(f"Archiving sandbox {sandbox_id} as it is in stopped state")
            sandbox.archive()
            logger.info(f"Successfully archived sandbox {sandbox_id}")
            return True
        else:
            logger.info(f"Skipping sandbox {sandbox_id} as it is not in stopped state (current: {sandbox_info.state})")
            return True
            
    except Exception as e:
        import traceback
        error_type = type(e).__name__
        stack_trace = traceback.format_exc()
        
        # Log detailed error information
        logger.error(f"Error processing sandbox {sandbox_id}: {str(e)}")
        logger.error(f"Error type: {error_type}")
        logger.error(f"Stack trace:\n{stack_trace}")
        
        # If the exception has a response attribute (like in HTTP errors), log it
        if hasattr(e, 'response'):
            try:
                response_data = e.response.json() if hasattr(e.response, 'json') else str(e.response)
                logger.error(f"Response data: {response_data}")
            except Exception:
                logger.error(f"Could not parse response data from error")
        
        print(f"Failed to process sandbox {sandbox_id}: {error_type} - {str(e)}")
        return False


async def process_sandboxes(inactive_projects: List[Dict[str, Any]], dry_run: bool) -> tuple[int, int]:
    """
    Process all sandboxes sequentially.
    
    Args:
        inactive_projects: List of projects without active billing
        dry_run: Whether to actually archive sandboxes or just simulate
        
    Returns:
        Tuple of (processed_count, failed_count)
    """
    processed_count = 0
    failed_count = 0
    
    if dry_run:
        logger.info(f"DRY RUN: Would archive {len(inactive_projects)} sandboxes")
    else:
        logger.info(f"Archiving {len(inactive_projects)} sandboxes")
    
    print(f"Processing {len(inactive_projects)} sandboxes...")
    
    # Process each sandbox sequentially
    for i, project in enumerate(inactive_projects):
        success = await archive_sandbox(project, dry_run)
        
        if success:
            processed_count += 1
        else:
            failed_count += 1
        
        # Print progress periodically
        if (i + 1) % 20 == 0 or (i + 1) == len(inactive_projects):
            progress = (i + 1) / len(inactive_projects) * 100
            print(f"Progress: {i + 1}/{len(inactive_projects)} sandboxes processed ({progress:.1f}%)")
            print(f"  - Processed: {processed_count}, Failed: {failed_count}")
    
    return processed_count, failed_count


async def main():
    """Main function to run the script."""
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Archive sandboxes for projects without active billing')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be archived without actually archiving')
    args = parser.parse_args()

    logger.info("Starting sandbox cleanup for projects without active billing")
    if args.dry_run:
        logger.info("DRY RUN MODE - No sandboxes will be archived")
    
    # Print environment info
    print(f"Environment Mode: {os.getenv('ENV_MODE', 'Not set')}")
    print(f"Daytona Server: {os.getenv('DAYTONA_SERVER_URL', 'Not set')}")
    
    try:
        # Initialize global DB connection
        global db_connection
        db_connection = DBConnection()
        
        # Get all account_ids that have an active billing customer
        active_billing_customer_account_ids = await get_active_billing_customer_account_ids()
        
        # Get all projects with sandboxes
        all_projects = await get_all_projects()
        
        if not all_projects:
            logger.info("No projects with sandboxes to process")
            return
        
        # Filter projects whose account_id is not in the active billing customers list
        inactive_projects = [
            project for project in all_projects
            if project.get('account_id') not in active_billing_customer_account_ids
        ]
        
        # Print summary of what will be processed
        active_projects_count = len(all_projects) - len(inactive_projects)
        print("\n===== SANDBOX CLEANUP SUMMARY =====")
        print(f"Total projects found: {len(all_projects)}")
        print(f"Projects with active billing accounts: {active_projects_count}")
        print(f"Projects without active billing accounts: {len(inactive_projects)}")
        print(f"Sandboxes that will be archived: {len(inactive_projects)}")
        print("===================================")
        
        logger.info(f"Found {len(inactive_projects)} projects without an active billing customer account")
        
        if not inactive_projects:
            logger.info("No projects to archive sandboxes for")
            return
        
        # Ask for confirmation before proceeding
        if not args.dry_run:
            print("\n⚠️  WARNING: You are about to archive sandboxes for inactive accounts ⚠️")
            print("This action cannot be undone!")
            confirmation = input("\nAre you sure you want to proceed with archiving? (TRUE/FALSE): ").strip().upper()
            
            if confirmation != "TRUE":
                print("Archiving cancelled. Exiting script.")
                logger.info("Archiving cancelled by user")
                return
            
            print("\nProceeding with sandbox archiving...\n")
            logger.info("User confirmed sandbox archiving")
        
        # List all projects to be processed
        for i, project in enumerate(inactive_projects[:5]):  # Just show first 5 for brevity
            account_id = project.get('account_id', 'Unknown')
            project_name = project.get('name', 'Unknown')
            project_id = project.get('project_id', 'Unknown')
            sandbox_id = project['sandbox'].get('id')
            
            print(f"{i+1}. Project: {project_name}")
            print(f"   Project ID: {project_id}")
            print(f"   Account ID: {account_id}")
            print(f"   Sandbox ID: {sandbox_id}")
            
        if len(inactive_projects) > 5:
            print(f"   ... and {len(inactive_projects) - 5} more projects")
        
        # Process all sandboxes
        processed_count, failed_count = await process_sandboxes(inactive_projects, args.dry_run)
        
        # Print final summary
        print("\nSandbox Cleanup Summary:")
        print(f"Total projects without active billing: {len(inactive_projects)}")
        print(f"Total sandboxes processed: {len(inactive_projects)}")
        
        if args.dry_run:
            print(f"DRY RUN: No sandboxes were actually archived")
        else:
            print(f"Successfully processed: {processed_count}")
            print(f"Failed to process: {failed_count}")
        
        logger.info("Sandbox cleanup completed")
            
    except Exception as e:
        logger.error(f"Error during sandbox cleanup: {str(e)}")
        sys.exit(1)
    finally:
        # Clean up database connection
        if db_connection:
            await DBConnection.disconnect()


if __name__ == "__main__":
    asyncio.run(main()) 