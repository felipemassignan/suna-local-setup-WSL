```bash
#!/bin/bash
# install_wsl2.sh - Instalação automatizada do Suna no WSL2
# Versão: 1.0
# Autor: Felipe Massignan

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de log
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                    SUNA WSL2 INSTALLER                       ║
║                   Versão Otimizada 1.0                       ║
║              Por Felipe Massignan - CEO IA Solutions         ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificações iniciais
log_info "Verificando ambiente WSL2..."
if ! grep -q microsoft /proc/version; then
    log_error "Este script deve ser executado no WSL2!"
    log_info "Abra o terminal WSL2 e execute novamente."
    exit 1
fi

if [ "$EUID" -eq 0 ]; then
    log_error "Não execute como root! Use seu usuário normal."
    exit 1
fi

# Obter informações do sistema
WSL_IP=$(hostname -I | awk '{print $1}')
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
fi

if [ "$TOTAL_DISK" -lt 20 ]; then
    log_warning "Espaço em disco: ${TOTAL_DISK}GB (recomendado: 50GB+)"
fi

# Atualizar sistema
log_info "Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

# Instalar dependências essenciais
log_info "Instalando dependências essenciais..."
sudo apt install -y \
    curl wget git vim htop \
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
    lsb-release

# Configurar Git LFS
log_info "Configurando Git LFS..."
if ! command -v git-lfs &> /dev/null; then
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
    sudo apt install git-lfs -y
fi
git lfs install

# Criar diretórios
log_info "Criando estrutura de diretórios..."
sudo mkdir -p /opt/suna/{models,data,logs,backups}
sudo mkdir -p /etc/suna/{backend,frontend}
sudo chown -R $USER:$USER /opt/suna
sudo chown -R $USER:$USER /etc/suna

# Clonar repositório original
log_info "Clonando repositório Suna original..."
cd /opt/suna
if [ ! -d "suna-local-setup" ]; then
    git clone https://github.com/88atman77/suna-local-setup.git
fi
cd suna-local-setup

# Tornar scripts executáveis
chmod +x *.sh

# Executar instalação original com modificações
log_info "Executando instalação original do Suna..."
if [ -f "install.sh" ]; then
    # Backup do script original
    cp install.sh install.sh.backup
    
    # Modificar script para WSL2
    sed -i 's/HOST=127.0.0.1/HOST=0.0.0.0/g' install.sh
    sed -i 's/localhost/0.0.0.0/g' install.sh
    
    # Executar instalação
    sudo ./install.sh
else
    log_error "Script install.sh não encontrado no repositório original!"
    exit 1
fi

# Configurar serviços systemd
log_info "Configurando serviços systemd..."

# Serviço Redis
sudo tee /etc/systemd/system/suna-redis.service > /dev/null << EOF
[Unit]
Description=Suna Redis Server
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/redis-server /etc/redis/redis.conf
ExecReload=/bin/kill -USR2 \$MAINPID
TimeoutStopSec=0
Restart=always
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

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/suna-local-setup
ExecStart=/opt/suna/suna-local-setup/llama.cpp/server -m /opt/suna/models/mistral-7b-instruct-v0.1.Q4_K_M.gguf --host 0.0.0.0 --port 8080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Serviço Backend
sudo tee /etc/systemd/system/suna-backend.service > /dev/null << EOF
[Unit]
Description=Suna Backend (FastAPI)
After=network.target suna-redis.service suna-llm.service
Requires=suna-redis.service suna-llm.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=/opt/suna/suna-local-setup/backend
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
WorkingDirectory=/opt/suna/suna-local-setup/frontend
Environment=PATH=/usr/bin:/bin
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Recarregar systemd
sudo systemctl daemon-reload

# Habilitar serviços
sudo systemctl enable suna-redis suna-llm suna-backend suna-frontend

log_success "Instalação base concluída!"

# Configurar rede WSL2
log_info "Configurando rede para WSL2..."
./configure_wsl2_network.sh

log_success "Instalação completa do Suna WSL2 finalizada!"
echo ""
log_info "Próximos passos:"
echo "1. Execute: ./start_suna_wsl2.sh"
echo "2. Configure o firewall do Windows (windows/configure_firewall.ps1)"
echo "3. Acesse: http://$WSL_IP:3000"
echo ""
log_warning "Lembre-se de configurar o Windows para acesso completo!"
