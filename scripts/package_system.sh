#!/bin/bash
set -e

# Script to package the entire system for distribution
# This script will:
# 1. Create a tarball of the entire system
# 2. Create a download script
# 3. Create a README file for the archive

echo "Packaging Suna Local System..."

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
ARCHIVE_NAME="suna-local-setup.tar.gz"
DOWNLOAD_SCRIPT="download_suna_local.sh"
ARCHIVE_README="ARCHIVE_README.md"

# Copy all files to the temporary directory
echo "Copying files..."
cp -r /workspace/suna-complete-system/* $TEMP_DIR/

# Remove node_modules and other large directories
echo "Removing unnecessary files..."
rm -rf $TEMP_DIR/frontend/node_modules
rm -rf $TEMP_DIR/frontend/.next
rm -rf $TEMP_DIR/backend/__pycache__
find $TEMP_DIR -name "*.pyc" -delete
find $TEMP_DIR -name "__pycache__" -delete

# Create the tarball
echo "Creating tarball..."
cd $TEMP_DIR
tar -czf /workspace/$ARCHIVE_NAME .

# Create the download script
echo "Creating download script..."
cat > /workspace/$DOWNLOAD_SCRIPT << 'EOL'
#!/bin/bash
set -e

# Script to download and extract Suna Local System
# This script will:
# 1. Download the tarball
# 2. Extract it to the current directory
# 3. Run the installation script

echo "Downloading Suna Local System..."

# Download the tarball
wget -O suna-local-setup.tar.gz https://github.com/yourusername/suna-local-setup/releases/download/v1.0.0/suna-local-setup.tar.gz

# Extract the tarball
echo "Extracting files..."
mkdir -p suna-local-setup
tar -xzf suna-local-setup.tar.gz -C suna-local-setup

# Change to the extracted directory
cd suna-local-setup

# Make scripts executable
chmod +x scripts/*.sh
chmod +x *.sh

echo "Download and extraction complete!"
echo "To install, run: sudo ./install.sh"
EOL

chmod +x /workspace/$DOWNLOAD_SCRIPT

# Create the README file for the archive
echo "Creating README file for the archive..."
cat > /workspace/$ARCHIVE_README << 'EOL'
# Suna Local Setup Archive

This archive contains the complete Suna Local System, configured to run entirely locally on a VDS without GPU. Instead of using external APIs like OpenAI, it's wired to a local Mistral 7B model served via llama.cpp, using an OpenAI-compatible endpoint.

## Installation

1. Extract the archive:
   ```bash
   tar -xzf suna-local-setup.tar.gz
   cd suna-local-setup
   ```

2. Run the installation script:
   ```bash
   sudo ./install.sh
   ```

3. Start the services:
   ```bash
   sudo ./start-suna.sh
   ```

4. Access the Suna UI at: http://localhost:12000

## System Requirements

- Linux VDS with at least 2 CPU cores
- 16GB RAM minimum (more is better)
- 20GB free disk space for model and code

## Components

- **llama.cpp server**: Serves the Mistral 7B model with an OpenAI-compatible API
- **Suna backend**: FastAPI server that handles agent logic and communicates with the LLM
- **Suna frontend**: Next.js web interface for interacting with the agent

## Troubleshooting

If you encounter any issues, please check the logs:
```bash
journalctl -u suna-llama.service -n 50
journalctl -u suna-backend.service -n 50
journalctl -u suna-frontend.service -n 50
```

For more information, see the README.md file in the extracted directory.
EOL

echo "Packaging complete!"
echo "Archive: /workspace/$ARCHIVE_NAME"
echo "Download script: /workspace/$DOWNLOAD_SCRIPT"
echo "Archive README: /workspace/$ARCHIVE_README"

# Clean up
rm -rf $TEMP_DIR