#!/bin/bash
# install_wsl2.sh - Instalação automatizada do Suna no WSL2
# Versão: 2.3 - Corrigida e Otimizada
# Autor: Felipe Massignan - CEO IA Solutions

set -e

# Cores e funções de log
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_debug() { echo -e "${PURPLE}🔍 $1${NC}"; }

# Função para instalar pacotes com retry
install_with_retry() {
    package=$1
    max_attempts=3
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Tentativa $attempt de $max_attempts para instalar $package..."
        
        if pip install "$package" --no-cache-dir; then
            log_success "$package instalado com sucesso!"
            return 0
        else
            log_warning "Falha na tentativa $attempt para $package"
            if [ $attempt -lt $max_attempts ]; then
                log_info "Limpando cache e tentando novamente..."
                pip cache purge
                sleep 5
            fi
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "Falha ao instalar $package após $max_attempts tentativas"
    return 1
}

# Verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Obter IP WSL2
get_wsl_ip() {
    hostname -I | awk '{print $1}'
}

# Banner
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                    SUNA WSL2 INSTALLER                        ║
║                   Versão Final 2.3                            ║
║              Por Felipe Massignan - CEO IA Solutions          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificações iniciais
log_info "Verificando ambiente WSL2..."

# Verificar WSL2
if ! grep -q microsoft /proc/version; then
    log_error "Este script deve ser executado no WSL2!"
    log_info "Abra o terminal WSL2 e execute novamente."
    exit 1
fi

# Verificar se não é root
if [ "$EUID" -eq 0 ]; then
    log_error "Não execute como root! Use seu usuário normal."
    exit 1
fi

# Verificar conectividade
log_info "Verificando conectividade..."
if ! ping -c 1 google.com &> /dev/null; then
    log_warning "Problemas de conectividade detectados, continuando..."
fi

# Obter informações do sistema
WSL_IP=$(get_wsl_ip)
DISTRO=$(lsb_release -si 2>/dev/null || echo "Unknown")
VERSION=$(lsb_release -sr 2>/dev/null || echo "Unknown")

log_success "Ambiente WSL2 detectado"
log_info "Distribuição: $DISTRO $VERSION"
log_info "IP do WSL2: $WSL_IP"

# Verificar recursos disponíveis
TOTAL_RAM=$(free -g | awk '/^Mem:/ {print $2}')
TOTAL_DISK=$(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')

if [ "$TOTAL_RAM" -lt 4 ]; then
    log_warning "RAM disponível: ${TOTAL_RAM}GB (recomendado: 8GB+)"
    echo "Continuar mesmo assim? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

if [ "$TOTAL_DISK" -lt 20 ]; then
    log_warning "Espaço em disco: ${TOTAL_DISK}GB (recomendado: 50GB+)"
    echo "Continuar mesmo assim? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Verificar se já existe instalação anterior
if [ -d "/opt/suna/suna-local-setup/backend/venv" ]; then
    log_info "Ambiente virtual já existe. Ativando..."
    source /opt/suna/suna-local-setup/backend/venv/bin/activate
    SKIP_BASIC_INSTALL=true
else
    SKIP_BASIC_INSTALL=false
fi

# Executar instalação básica se necessário
if [ "$SKIP_BASIC_INSTALL" = false ]; then
    log_info "Executando instalação básica..."

    # Atualizar sistema
    log_info "Atualizando sistema..."
    sudo apt update && sudo apt upgrade -y

    # Instalar dependências essenciais
    log_info "Instalando dependências essenciais..."
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
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        jq

    # Verificar versões instaladas
    log_info "Verificando versões instaladas..."
    echo "Python: $(python3 --version)"
    echo "Node.js: $(node --version)"
    echo "npm: $(npm --version)"
    echo "Git: $(git --version)"

    # Configurar Git LFS
    log_info "Configurando Git LFS..."
    if ! command_exists git-lfs; then
        curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
        sudo apt install git-lfs -y
    fi
    git lfs install

    # Criar estrutura de diretórios
    log_info "Criando estrutura de diretórios..."
    sudo mkdir -p /opt/suna/{models,data,logs,backups}
    sudo mkdir -p /etc/suna/{backend,frontend}
    sudo chown -R $USER:$USER /opt/suna
    sudo chown -R $USER:$USER /etc/suna

    # Clonar repositório original se não existir
    log_info "Preparando código fonte..."
    cd /opt/suna
    if [ ! -d "suna-local-setup" ]; then
        log_info "Clonando repositório Suna original..."
        git clone https://github.com/88atman77/suna-local-setup.git
    fi
    cd suna-local-setup

    # Tornar scripts executáveis
    chmod +x *.sh

    # Criar ambiente virtual Python
    log_info "Criando ambiente virtual Python..."
    python3 -m venv backend/venv
    source backend/venv/bin/activate

    # Atualizar pip
    log_info "Atualizando pip..."
    pip install --upgrade pip

    # Instalar llama-cpp-python
    log_info "Instalando llama-cpp-python..."
    pip install llama-cpp-python[server] --no-cache-dir
fi

# Limpar cache do pip
log_info "Limpando cache do pip..."
pip cache purge

# Baixar modelo Mistral se não existir
MODEL_PATH="/opt/suna/models/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
if [ ! -f "$MODEL_PATH" ]; then
    log_info "Baixando modelo Mistral 7B (isso pode demorar)..."
    mkdir -p /opt/suna/models
    wget -O "$MODEL_PATH" "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
    log_success "Modelo Mistral 7B baixado com sucesso!"
else
    log_info "Modelo Mistral 7B já existe, pulando download."
fi

# Clonar repositório Suna se não existir
if [ ! -d "/opt/suna/repo" ]; then
    log_info "Clonando repositório Suna..."
    git clone https://github.com/kortix-ai/suna.git /opt/suna/repo
    log_success "Repositório Suna clonado com sucesso!"
else
    log_info "Repositório Suna já existe, atualizando..."
    cd /opt/suna/repo
    git pull origin main
fi

# Instalar dependências do backend
log_info "Instalando dependências do backend com tratamento robusto..."
cd /opt/suna/repo

# Verificar se requirements.txt existe
if [ -f "backend/requirements.txt" ]; then
    log_info "Encontrado requirements.txt em backend/"
    pip install -r backend/requirements.txt --no-cache-dir
elif [ -f "requirements.txt" ]; then
    log_info "Encontrado requirements.txt na raiz"
    pip install -r requirements.txt --no-cache-dir
else
    log_warning "requirements.txt não encontrado. Instalando dependências manualmente..."
    
    # Lista de pacotes essenciais
    packages=(
        "fastapi==0.104.1"
        "uvicorn==0.24.0"
        "python-multipart==0.0.6"
        "redis==5.0.1"
        "faiss-cpu==1.7.4"
        "openai==1.3.7"
        "python-dotenv==1.0.0"
        "pydantic==2.5.0"
        "httpx==0.25.2"
        "websockets==12.0"
        "aiofiles==23.2.1"
        "python-jose==3.3.0"
        "passlib==1.7.4"
        "bcrypt==4.1.2"
    )

    # Instalar pacotes básicos
    for package in "${packages[@]}"; do
        install_with_retry "$package"
    done
fi

# Instalar sentence-transformers separadamente
log_info "Instalando sentence-transformers..."
st_package="sentence-transformers"
max_attempts_st=3
attempt_st=1

while [ $attempt_st -le $max_attempts_st ]; do
    log_info "Tentativa $attempt_st de $max_attempts_st para instalar $st_package..."
    if pip install "$st_package" --no-cache-dir; then
        log_success "$st_package instalado com sucesso!"
        break
    else
        log_warning "Falha na tentativa $attempt_st para $st_package"
        if [ $attempt_st -lt $max_attempts_st ]; then
            log_info "Limpando cache e tentando novamente..."
            pip cache purge
            sleep 5
        fi
        attempt_st=$((attempt_st + 1))
    fi
done

# Se falhar, instalar dependências manualmente
if [ $attempt_st -gt $max_attempts_st ]; then
    log_error "Falha ao instalar $st_package. Instalando dependências manualmente..."
    pip cache purge
    
    # Instalar dependências do sentence-transformers uma por uma
    st_dependencies=("torch" "transformers" "scikit-learn" "scipy" "nltk" "sentencepiece")
    for dep in "${st_dependencies[@]}"; do
        install_with_retry "$dep"
    done
    
    # Tentar sentence-transformers novamente
    log_info "Tentando instalar sentence-transformers novamente..."
    pip install sentence-transformers --no-cache-dir || log_warning "sentence-transformers pode precisar ser instalado manualmente depois."
fi

# Instalar dependências do frontend
if [ -d "frontend" ]; then
    log_info "Instalando dependências do frontend..."
    cd frontend
    if [ -f "package.json" ]; then
        npm install
        log_info "Construindo frontend..."
        npm run build
        log_success "Frontend construído com sucesso!"
    else
        log_warning "package.json não encontrado no frontend"
    fi
else
    log_warning "Diretório frontend não encontrado"
fi

# Voltar para diretório principal
cd /opt/suna/suna-local-setup

# Configurar serviços systemd
log_info "Configurando serviços systemd..."

# Serviço Redis
sudo tee /etc/systemd/system/suna-redis.service > /dev/null << 'EOF'
[Unit]
Description=Suna Redis Server
After=network.target
Documentation=https://redis.io/documentation

[Service]
Type=notify
ExecStart=/usr/bin/redis-server /etc/redis/redis.conf
ExecReload=/bin/kill -USR2 $MAINPID
TimeoutStopSec=10
Restart=always
RestartSec=5
User=redis
Group=redis
RuntimeDirectory=redis
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

# Serviço LLM
sudo tee /etc/systemd/system/suna-llm.service > /dev/null << EOF
[Unit]
Description=Suna LLM Server (llama.cpp)
After=network.target
Documentation=https://github.com/ggerganov/llama.cpp

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/suna-local-setup
ExecStart=/opt/suna/suna-local-setup/backend/venv/bin/python -m llama_cpp.server --model $MODEL_PATH --host 0.0.0.0 --port 8080 --n_threads 4
Restart=always
RestartSec=10
TimeoutStartSec=300
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Serviço Backend
sudo tee /etc/systemd/system/suna-backend.service > /dev/null << EOF
[Unit]
Description=Suna Backend (FastAPI)
After=network.target suna-llm.service
Requires=suna-llm.service
Documentation=https://fastapi.tiangolo.com/

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/repo/backend
Environment=PATH=/opt/suna/suna-local-setup/backend/venv/bin
ExecStart=/opt/suna/suna-local-setup/backend/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1
Restart=always
RestartSec=10
TimeoutStartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Serviço Frontend
sudo tee /etc/systemd/system/suna-frontend.service > /dev/null << EOF
[Unit]
Description=Suna Frontend (Next.js)
After=network.target suna-backend.service
Requires=suna-backend.service
Documentation=https://nextjs.org/

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/repo/frontend
Environment=PATH=/usr/bin:/bin
Environment=NODE_ENV=production
Environment=PORT=3000
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10
TimeoutStartSec=120
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd e habilitar serviços
log_info "Habilitando serviços systemd..."
sudo systemctl daemon-reload
sudo systemctl enable suna-redis suna-llm suna-backend suna-frontend

# Configurar rede WSL2 se script existir
if [ -f "../configure_wsl2_network.sh" ]; then
    log_info "Configurando rede para WSL2..."
    cd ..
    ./configure_wsl2_network.sh
    cd suna-local-setup
else
    log_warning "Script de configuração de rede não encontrado"
fi

# Finalização
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                 INSTALAÇÃO CONCLUÍDA!                         ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_success "Instalação completa do Suna WSL2 finalizada!"
echo ""
log_info "📋 Próximos passos:"
echo "   1. Execute: ./start_suna_wsl2.sh"
echo "   2. Configure o firewall do Windows (windows/configure_firewall.ps1)"
echo "   3. Atualize o arquivo hosts (windows/update_hosts.ps1)"
echo ""
log_info "🌐 URLs de acesso:"
echo "   Frontend: http://$WSL_IP:3000"
echo "   Backend:  http://$WSL_IP:8000"
echo "   LLM API:  http://$WSL_IP:8080"
echo ""
log_info "🔧 Comandos úteis:"
echo "   Iniciar:    ./start_suna_wsl2.sh"
echo "   Parar:      ./stop_suna_wsl2.sh"
echo "   Monitorar:  ./monitor_suna_wsl2.sh"
echo "   Backup:     ./backup_suna_wsl2.sh"
echo ""
log_warning "⚠️  Lembre-se de configurar o Windows para acesso completo!"