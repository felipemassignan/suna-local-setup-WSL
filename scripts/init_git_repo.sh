#!/bin/bash
set -e

# Script to initialize git repository and push to GitHub
# This script will:
# 1. Initialize git repository
# 2. Add all files
# 3. Commit changes
# 4. Push to GitHub

echo "Initializing git repository..."

# Initialize git repository
cd /workspace/suna-complete-system
git init

# Add all files
git add .

# Commit changes
git commit -m "Initial commit: Suna Local System with 100% offline operation"

# Create .gitignore file
cat > .gitignore << EOL
# Node modules
node_modules/
.next/

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
*.egg-info/
.installed.cfg
*.egg

# Environment variables
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Models
models/
*.gguf

# Logs
logs/
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# OS specific
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
EOL

# Add .gitignore
git add .gitignore
git commit -m "Add .gitignore file"

echo "Git repository initialized!"
echo "To push to GitHub, run:"
echo "  git remote add origin https://github.com/yourusername/suna-local-setup.git"
echo "  git push -u origin master"