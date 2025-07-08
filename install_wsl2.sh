#!/bin/bash
# install_wsl2.sh - Instalação automatizada do Suna no WSL2
# Versão: 1.3
# Autor: Felipe Massignan

set -e

# Cores e funções de log
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                    SUNA WSL2 INSTALLER                        ║
║                   Versão Melhorada 1.3                        ║
║              Por Felipe Massignan - CEO IA Solutions          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificações iniciais (mantidas do script anterior)
log_info "Verificando ambiente WSL2..."

if ! grep -q microsoft /proc/version; then
    log_error "Este script deve ser executado no WSL2!"
    exit 1
fi

if [ "$EUID" -eq 0 ]; then
    log_error "Não execute como root! Use seu usuário normal."
    exit 1
fi

WSL_IP=$(hostname -I | awk '{print $1}')
log_success "Ambiente WSL2 detectado - IP: $WSL_IP"

# Executar instalação básica até o ponto do erro
log_info "Executando instalação básica..."

# Atualizar sistema
sudo apt update && sudo apt upgrade -y

# Instalar dependências
sudo apt install -y \
    curl wget git vim htop tree \
    build-essential cmake pkg-config \
    python3 python3-pip python3-venv python3-dev \
    nodejs npm \
    redis-server \
    nginx \
    libopenblas-dev liblapack-dev \
    libffi-dev libssl-dev \
    software-properties-common \
    jq

# Configurar Git LFS
if ! command -v git-lfs &> /dev/null; then
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
    sudo apt install git-lfs -y
fi
git lfs install

# Criar estrutura de diretórios
sudo mkdir -p /opt/suna/{models,data,logs,backups}
sudo mkdir -p /etc/suna/{backend,frontend}
sudo chown -R $USER:$USER /opt/suna
sudo chown -R $USER:$USER /etc/suna

# Clonar repositório original
cd /opt/suna
if [ ! -d "suna-local-setup" ]; then
    git clone https://github.com/88atman77/suna-local-setup.git
fi
cd suna-local-setup

# NOVA ABORDAGEM: Executar instalação manualmente
log_info "Executando instalação manual do Suna (evitando erro requirements.txt)..."

# Criar ambiente virtual Python
log_info "Criando ambiente virtual Python..."
python3 -m venv backend/venv
source backend/venv/bin/activate

# Instalar llama-cpp-python
log_info "Instalando llama-cpp-python..."
pip install llama-cpp-python[server]

# Baixar modelo Mistral se não existir
MODEL_PATH="/opt/suna/models/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
if [ ! -f "$MODEL_PATH" ]; then
    log_info "Baixando modelo Mistral 7B..."
    mkdir -p /opt/suna/models
    wget -O "$MODEL_PATH" "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
fi

# Clonar repositório Suna se não existir
if [ ! -d "/opt/suna/repo" ]; then
    log_info "Clonando repositório Suna..."
    git clone https://github.com/kortix-ai/suna.git /opt/suna/repo
fi

# Instalar dependências do backend
log_info "Instalando dependências do backend..."
cd /opt/suna/repo

# Verificar onde está o requirements.txt
if [ -f "backend/requirements.txt" ]; then
    log_info "Encontrado requirements.txt em backend/"
    pip install -r backend/requirements.txt
elif [ -f "requirements.txt" ]; then
    log_info "Encontrado requirements.txt na raiz"
    pip install -r requirements.txt
else
    log_warning "requirements.txt não encontrado. Instalando dependências manualmente..."
    pip install \
        fastapi==0.104.1 \
        uvicorn==0.24.0 \
        python-multipart==0.0.6 \
        redis==5.0.1 \
        faiss-cpu==1.7.4 \
        sentence-transformers==2.2.2 \
        openai==1.3.7 \
        python-dotenv==1.0.0 \
        pydantic==2.5.0 \
        httpx==0.25.2 \
        websockets==12.0 \
        aiofiles==23.2.1 \
        python-jose==3.3.0 \
        passlib==1.7.4 \
        bcrypt==4.1.2
fi

# Instalar dependências do frontend
if [ -d "frontend" ]; then
    log_info "Instalando dependências do frontend..."
    cd frontend
    if [ -f "package.json" ]; then
        npm install
        npm run build
    fi
fi

# Voltar para diretório principal
cd /opt/suna/suna-local-setup

# Configurar serviços systemd
log_info "Configurando serviços systemd..."

# Serviço LLM
sudo tee /etc/systemd/system/suna-llm.service > /dev/null << EOF
[Unit]
Description=Suna LLM Server (llama.cpp)
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/suna-local-setup
ExecStart=/opt/suna/suna-local-setup/backend/venv/bin/python -m llama_cpp.server --model $MODEL_PATH --host 0.0.0.0 --port 8080 --n_threads 4
Restart=always
RestartSec=10
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# Serviço Backend
sudo tee /etc/systemd/system/suna-backend.service > /dev/null << EOF
[Unit]
Description=Suna Backend (FastAPI)
After=network.target suna-llm.service
Requires=suna-llm.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/repo/backend
Environment=PATH=/opt/suna/suna-local-setup/backend/venv/bin
ExecStart=/opt/suna/suna-local-setup/backend/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Serviço Frontend
sudo tee /etc/systemd/system/suna-frontend.service > /dev/null << EOF
[Unit]
Description=Suna Frontend (Next.js)
After=network.target suna-backend.service
Requires=suna-backend.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/repo/frontend
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
sudo systemctl daemon-reload
sudo systemctl enable suna-llm suna-backend suna-frontend

log_success "Instalação WSL2 do Suna concluída!"
log_info "Para iniciar os serviços, execute: ./start_suna_wsl2.sh"
log_info "Acesse em: http://$WSL_IP:3000"