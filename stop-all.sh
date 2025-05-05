#!/bin/bash

# Script to stop all services
# This script will:
# 1. Stop the Suna frontend
# 2. Stop the Suna backend
# 3. Stop the llama.cpp server

echo "Stopping all services..."

# Find and kill the frontend process
echo "Stopping Suna frontend..."
pkill -f "npm run dev -- --port 12000" || echo "Frontend not running"

# Find and kill the backend process
echo "Stopping Suna backend..."
pkill -f "uvicorn main:app --host 0.0.0.0 --port 8001" || echo "Backend not running"

# Find and kill the llama.cpp server process
echo "Stopping llama.cpp server..."
pkill -f "./build/bin/server -m" || echo "llama.cpp server not running"

echo "All services stopped!"