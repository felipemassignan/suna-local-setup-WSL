#!/bin/bash
set -e

# Script to set up and run Suna with local LLM
# This script will:
# 1. Install dependencies
# 2. Set up environment variables
# 3. Start the backend server
# 4. Start the frontend server

echo "Setting up Suna with local LLM..."

# Create .env file for backend
cat > /workspace/suna-complete-system/backend/.env << EOL
# Environment mode (local, staging, production)
ENV_MODE=local

# OpenAI API configuration for local LLM
OPENAI_API_KEY=sk-dummy-key
OPENAI_API_BASE=http://localhost:8000/v1

# Default model to use
MODEL_TO_USE=local-mistral
EOL

# Create .env.local file for frontend
cat > /workspace/suna-complete-system/frontend/.env.local << EOL
# Environment mode
NEXT_PUBLIC_ENV_MODE=local

# Backend URL
NEXT_PUBLIC_BACKEND_URL=http://localhost:8001

# Default model
NEXT_PUBLIC_DEFAULT_MODEL=local-mistral
EOL

# Install backend dependencies
echo "Installing backend dependencies..."
cd /workspace/suna-complete-system/backend
pip install -r requirements.txt

# Install frontend dependencies
echo "Installing frontend dependencies..."
cd /workspace/suna-complete-system/frontend
npm install

# Create start script for backend
cat > /workspace/suna-complete-system/start_backend.sh << EOL
#!/bin/bash
cd /workspace/suna-complete-system/backend
uvicorn main:app --host 0.0.0.0 --port 8001
EOL

# Create start script for frontend
cat > /workspace/suna-complete-system/start_frontend.sh << EOL
#!/bin/bash
cd /workspace/suna-complete-system/frontend
npm run dev -- --port 12000 --host 0.0.0.0
EOL

chmod +x /workspace/suna-complete-system/start_backend.sh
chmod +x /workspace/suna-complete-system/start_frontend.sh

echo "Setup complete!"
echo "To start the llama.cpp server, run: ~/start_llama_server.sh"
echo "To start the backend server, run: /workspace/suna-complete-system/start_backend.sh"
echo "To start the frontend server, run: /workspace/suna-complete-system/start_frontend.sh"
echo ""
echo "The Suna UI will be available at: https://work-1-bckloeitznuiijqn.prod-runtime.all-hands.dev"