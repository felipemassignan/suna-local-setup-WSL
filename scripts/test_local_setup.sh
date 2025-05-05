#!/bin/bash
set -e

# Script to test the local Suna setup
# This script will:
# 1. Test the llama.cpp server
# 2. Test the Suna backend
# 3. Test the Suna frontend

echo "Testing local Suna setup..."

# Test llama.cpp server
echo "Testing llama.cpp server..."
curl -s http://localhost:8000/v1/models | grep -q "mistral" && echo "✅ llama.cpp server is running and serving Mistral model" || echo "❌ llama.cpp server test failed"

# Test a simple completion with llama.cpp
echo "Testing llama.cpp completion..."
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-7b-instruct",
    "messages": [{"role": "user", "content": "Say hello"}],
    "temperature": 0.7,
    "max_tokens": 50
  }' | grep -q "content" && echo "✅ llama.cpp completion test passed" || echo "❌ llama.cpp completion test failed"

# Test Suna backend health check
echo "Testing Suna backend health check..."
curl -s http://localhost:8001/api/health | grep -q "ok" && echo "✅ Suna backend health check passed" || echo "❌ Suna backend health check failed"

# Test Suna backend local LLM endpoint
echo "Testing Suna backend local LLM endpoint..."
curl -s http://localhost:8001/agent/test_local_llm | grep -q "success" && echo "✅ Suna backend local LLM test passed" || echo "❌ Suna backend local LLM test failed"

# Test Suna frontend
echo "Testing Suna frontend..."
curl -s http://localhost:12000 | grep -q "Suna" && echo "✅ Suna frontend is running" || echo "❌ Suna frontend test failed"

echo "Tests completed!"