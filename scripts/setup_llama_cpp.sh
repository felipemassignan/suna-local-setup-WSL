#!/bin/bash
set -e

# Script to set up llama.cpp with Mistral 7B model
# This script will:
# 1. Clone llama.cpp
# 2. Build llama.cpp
# 3. Download Mistral 7B model
# 4. Convert model to GGUF format if needed
# 5. Start the server with OpenAI API compatibility

echo "Setting up llama.cpp with Mistral 7B model..."

# Create directories
mkdir -p ~/llama_cpp
mkdir -p ~/models

# Clone llama.cpp if not already cloned
if [ ! -d ~/llama_cpp/llama.cpp ]; then
    echo "Cloning llama.cpp repository..."
    cd ~/llama_cpp
    git clone https://github.com/ggerganov/llama.cpp.git
    cd llama.cpp
else
    echo "llama.cpp repository already exists, updating..."
    cd ~/llama_cpp/llama.cpp
    git pull
fi

# Build llama.cpp
echo "Building llama.cpp..."
mkdir -p build
cd build
cmake .. -DLLAMA_CUBLAS=OFF -DLLAMA_METAL=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release -j $(nproc)

# Download Mistral 7B model if not already downloaded
MODEL_DIR=~/models/mistral-7b-instruct-v0.2-GGUF
if [ ! -f "$MODEL_DIR/mistral-7b-instruct-v0.2.Q4_K_M.gguf" ]; then
    echo "Downloading Mistral 7B model..."
    mkdir -p $MODEL_DIR
    cd $MODEL_DIR
    
    # Download the GGUF model directly
    wget -c https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf
else
    echo "Mistral 7B model already exists."
fi

# Create a systemd service file for llama.cpp server
echo "Creating systemd service for llama.cpp server..."
cat > ~/llama_cpp_server.service << EOL
[Unit]
Description=llama.cpp server with OpenAI API compatibility
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=~/llama_cpp/llama.cpp
ExecStart=~/llama_cpp/llama.cpp/build/bin/server -m ~/models/mistral-7b-instruct-v0.2-GGUF/mistral-7b-instruct-v0.2.Q4_K_M.gguf -c 2048 --host 0.0.0.0 --port 8000 --parallel 2 --cont-batching
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Create a script to start the server manually
echo "Creating start script for llama.cpp server..."
cat > ~/start_llama_server.sh << EOL
#!/bin/bash
cd ~/llama_cpp/llama.cpp
./build/bin/server -m ~/models/mistral-7b-instruct-v0.2-GGUF/mistral-7b-instruct-v0.2.Q4_K_M.gguf -c 2048 --host 0.0.0.0 --port 8000 --parallel 2 --cont-batching
EOL

chmod +x ~/start_llama_server.sh

echo "Setup complete!"
echo "To start the server manually, run: ~/start_llama_server.sh"
echo "To install as a system service, run:"
echo "  sudo cp ~/llama_cpp_server.service /etc/systemd/system/"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable llama_cpp_server"
echo "  sudo systemctl start llama_cpp_server"
echo ""
echo "The server will be available at: http://localhost:8000/v1"