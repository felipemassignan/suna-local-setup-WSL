#!/bin/bash
set -e

# Script to start all services
# This script will:
# 1. Start the llama.cpp server
# 2. Start the Suna backend
# 3. Start the Suna frontend

echo "Starting all services..."

# Start llama.cpp server in the background
echo "Starting llama.cpp server..."
~/start_llama_server.sh > llama_server.log 2>&1 &
LLAMA_PID=$!
echo "llama.cpp server started with PID $LLAMA_PID"

# Wait for llama.cpp server to initialize
echo "Waiting for llama.cpp server to initialize..."
sleep 10

# Start Suna backend in the background
echo "Starting Suna backend..."
./start_backend.sh > backend.log 2>&1 &
BACKEND_PID=$!
echo "Suna backend started with PID $BACKEND_PID"

# Wait for backend to initialize
echo "Waiting for backend to initialize..."
sleep 5

# Start Suna frontend in the background
echo "Starting Suna frontend..."
./start_frontend.sh > frontend.log 2>&1 &
FRONTEND_PID=$!
echo "Suna frontend started with PID $FRONTEND_PID"

echo "All services started!"
echo "llama.cpp server: PID $LLAMA_PID, log: llama_server.log"
echo "Suna backend: PID $BACKEND_PID, log: backend.log"
echo "Suna frontend: PID $FRONTEND_PID, log: frontend.log"
echo ""
echo "The Suna UI will be available at: https://work-1-bckloeitznuiijqn.prod-runtime.all-hands.dev"
echo ""
echo "To stop all services, run: ./stop-all.sh"