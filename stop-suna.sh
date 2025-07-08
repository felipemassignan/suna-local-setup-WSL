#!/bin/bash
# stop_suna_wsl2.sh - Parar os serviços Suna no WSL2

# Cores e funções de log
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                    SUNA WSL2 STOPPER                          ║
║               Parando os Serviços do Suna no WSL2             ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info "Verificando se os serviços do Suna estão em execução..."

# Lista de serviços na ordem inversa de dependência para parar
SERVICES=("suna-frontend" "suna-backend" "suna-llm" "suna-redis")

for service in "${SERVICES[@]}"; do
    if sudo systemctl is-active --quiet "$service"; then
        log_info "Parando serviço: $service..."
        sudo systemctl stop "$service"
        if sudo systemctl is-active --quiet "$service"; then
            log_error "Falha ao parar $service."
        else
            log_success "$service parado com sucesso."
        fi
    else
        log_info "$service não está em execução ou já foi parado."
    fi
done

log_success "Todos os serviços do Suna foram verificados e parados."
echo ""
log_info "Para iniciar novamente, execute: ./start_suna_wsl2.sh"