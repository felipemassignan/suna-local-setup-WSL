"""
Centralized database connection management for AgentPress using Supabase.
"""

import os
from typing import Optional
from supabase import create_async_client, AsyncClient
from utils.logger import logger
from utils.config import config

class DBConnection:
    """Singleton database connection manager using Supabase."""
    
    _instance: Optional['DBConnection'] = None
    _initialized = False
    _client: Optional[AsyncClient] = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        """No initialization needed in __init__ as it's handled in __new__"""
        pass

    async def initialize(self):
        """Initialize the database connection."""
        if self._initialized:
            return
        
        # For local development with our custom setup, we don't need Supabase
        from utils.config import EnvMode
        if config.ENV_MODE == EnvMode.LOCAL:
            logger.info("Running in LOCAL mode. Skipping Supabase initialization.")
            self._initialized = True
            return
                
        try:
            supabase_url = config.SUPABASE_URL
            # Use service role key preferentially for backend operations
            supabase_key = config.SUPABASE_SERVICE_ROLE_KEY or config.SUPABASE_ANON_KEY
            
            if not supabase_url or not supabase_key:
                logger.error("Missing required environment variables for Supabase connection")
                raise RuntimeError("SUPABASE_URL and a key (SERVICE_ROLE_KEY or ANON_KEY) environment variables must be set.")

            logger.debug("Initializing Supabase connection")
            self._client = await create_async_client(supabase_url, supabase_key)
            self._initialized = True
            key_type = "SERVICE_ROLE_KEY" if config.SUPABASE_SERVICE_ROLE_KEY else "ANON_KEY"
            logger.debug(f"Database connection initialized with Supabase using {key_type}")
        except Exception as e:
            logger.error(f"Database initialization error: {e}")
            from utils.config import EnvMode
            if config.ENV_MODE == EnvMode.LOCAL:
                logger.warning("Running in LOCAL mode. Continuing without Supabase.")
                self._initialized = True
                return
            raise RuntimeError(f"Failed to initialize database connection: {str(e)}")

    @classmethod
    async def disconnect(cls):
        """Disconnect from the database."""
        if cls._client:
            logger.info("Disconnecting from Supabase database")
            await cls._client.close()
            cls._initialized = False
            logger.info("Database disconnected successfully")

    @property
    async def client(self) -> AsyncClient:
        """Get the Supabase client instance."""
        if not self._initialized:
            logger.debug("Supabase client not initialized, initializing now")
            await self.initialize()
        from utils.config import EnvMode
        if not self._client and config.ENV_MODE != EnvMode.LOCAL:
            logger.error("Database client is None after initialization")
            raise RuntimeError("Database not initialized")
        # In local mode, we might not have a client but we're still initialized
        if config.ENV_MODE == EnvMode.LOCAL and not self._client:
            logger.warning("Running in LOCAL mode without Supabase client")
            return None
        return self._client


