#!/bin/bash
# common.sh - Funções compartilhadas

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funções de log
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_debug() { echo -e "${PURPLE}🔍 $1${NC}"; }

# Verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Verificar se serviço está rodando
check_service() {
    local service=$1
    local port=$2
    local timeout=${3:-30}
    
    log_info "Verificando $service na porta $port..."
    
    local count=0
    while [ $count -lt $timeout ]; do
        if curl -s --connect-timeout 2 "http://localhost:$port" > /dev/null 2>&1; then
            log_success "$service está rodando!"
            return 0
        fi
        sleep 2
        count=$((count + 2))
        echo -n "."
    done
    
    log_error "$service não respondeu em ${timeout}s"
    return 1
}

# Obter IP WSL2
get_wsl_ip() {
    hostname -I | awk '{print $1}'
}

# Verificar recursos do sistema
check_resources() {
    local min_ram_gb=${1:-2}
    local min_disk_gb=${2:-10}
    
    local free_ram=$(free -g | awk '/^Mem:/ {print $7}')
    local free_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ "$free_ram" -lt "$min_ram_gb" ]; then
        log_warning "RAM livre baixa: ${free_ram}GB (mínimo: ${min_ram_gb}GB)"
        return 1
    fi
    
    if [ "$free_disk" -lt "$min_disk_gb" ]; then
        log_warning "Espaço livre baixo: ${free_disk}GB (mínimo: ${min_disk_gb}GB)"
        return 1
    fi
    
    return 0
}