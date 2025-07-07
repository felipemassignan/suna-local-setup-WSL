#!/bin/bash
# start_suna_wsl2.sh - Inicialização inteligente dos serviços

set -e

source ./scripts/common.sh

log_info "Iniciando Suna Local Setup no WSL2..."

WSL_IP=$(hostname -I | awk '{print $1}')

# Função para verificar se serviço está rodando
check_service() {
    local service=$1
    local port=$2
    local timeout=${3:-30}
    
    log_info "Verificando $service na porta $port..."
    
    local count=0
    while [ $count -lt $timeout ]; do
        if curl -s "http://localhost:$port" > /dev/null 2>&1; then
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

# Verificar recursos do sistema
log_info "Verificando recursos do sistema..."
FREE_RAM=$(free -m | awk '/^Mem:/ {print $7}')
if [ "$FREE_RAM" -lt 2048 ]; then
    log_warning "RAM livre baixa: ${FREE_RAM}MB (recomendado: 2GB+)"
fi

# Iniciar Redis
log_info "Iniciando Redis..."
sudo systemctl start suna-redis
if ! check_service "Redis" 6379 10; then
    log_error "Falha ao iniciar Redis"
    exit 1
fi

# Iniciar LLM Server
log_info "Iniciando servidor LLM (pode demorar)..."
sudo systemctl start suna-llm

log_info "Aguardando LLM carregar modelo..."
if ! check_service "LLM" 8080 180; then
    log_error "Falha ao iniciar LLM"
    log_info "Verificando logs: sudo journalctl -u suna-llm.service -n 50"
    exit 1
fi

# Iniciar Backend
log_info "Iniciando backend..."
sudo systemctl start suna-backend
if ! check_service "Backend" 8000 60; then
    log_error "Falha ao iniciar Backend"
    exit 1
fi

# Iniciar Frontend
log_info "Iniciando frontend..."
sudo systemctl start suna-frontend
if ! check_service "Frontend" 3000 60; then
    log_error "Falha ao iniciar Frontend"
    exit 1
fi

# Verificação final
log_success "Todos os serviços iniciados com sucesso!"
echo ""
echo "🌐 URLs de Acesso (Windows):"
echo "   Frontend: http://$WSL_IP:3000"
echo "   Backend:  http://$WSL_IP:8000"
echo "   LLM API:  http://$WSL_IP:8080"
echo ""
echo "🔧 Comandos úteis:"
echo "   Monitorar: ./monitor_suna_wsl2.sh"
echo "   Parar:     ./stop_suna_wsl2.sh"
echo "   Logs:      sudo journalctl -u suna-frontend.service -f"
echo ""
log_warning "Configure o firewall do Windows se necessário!"
