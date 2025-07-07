#!/bin/bash
# monitor_suna_wsl2.sh - Monitoramento avançado do sistema

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                    SUNA WSL2 MONITOR                         ║
║                   Dashboard de Status                        ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

WSL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo -e "${BLUE}📊 Status em: $TIMESTAMP${NC}"
echo -e "${BLUE}📍 IP WSL2: $WSL_IP${NC}"
echo ""

# Verificar serviços
echo -e "${PURPLE}🔧 STATUS DOS SERVIÇOS${NC}"
echo "=========================="

services=("suna-redis" "suna-llm" "suna-backend" "suna-frontend")
service_ports=(6379 8080 8000 3000)
service_names=("Redis" "LLM Server" "Backend API" "Frontend")

for i in "${!services[@]}"; do
    service=${services[$i]}
    port=${service_ports[$i]}
    name=${service_names[$i]}
    
    # Verificar status do systemd
    if systemctl is-active --quiet $service.service 2>/dev/null; then
        status_systemd="${GREEN}✅ ATIVO${NC}"
    else
        status_systemd="${RED}❌ INATIVO${NC}"
    fi
    
    # Verificar conectividade
    if curl -s --connect-timeout 2 "http://localhost:$port" > /dev/null 2>&1; then
        status_network="${GREEN}🌐 ONLINE${NC}"
    else
        status_network="${RED}🔌 OFFLINE${NC}"
    fi
    
    printf "%-15s %s %s\n" "$name:" "$status_systemd" "$status_network"
done

echo ""

# URLs de acesso
echo -e "${PURPLE}🌐 URLS DE ACESSO${NC}"
echo "=================="
echo -e "Frontend:    ${CYAN}http://$WSL_IP:3000${NC}"
echo -e "Backend API: ${CYAN}http://$WSL_IP:8000${NC}"
echo -e "LLM API:     ${CYAN}http://$WSL_IP:8080${NC}"
echo -e "Redis:       ${CYAN}redis://$WSL_IP:6379${NC}"

# Verificar se hosts está configurado
if grep -q "suna.local" /mnt/c/Windows/System32/drivers/etc/hosts 2>/dev/null; then
    echo -e "Suna Local:  ${GREEN}http://suna.local:3000${NC}"
fi

echo ""

# Recursos do sistema
echo -e "${PURPLE}📈 RECURSOS DO SISTEMA${NC}"
echo "======================"

# CPU
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
echo -e "CPU:         ${YELLOW}${CPU_USAGE}%${NC}"

# Memória
MEMORY_INFO=$(free -h | awk '/^Mem:/ {printf "%.1f/%.1fGB (%.1f%%)", $3/1024, $2/1024, ($3/$2)*100}')
echo -e "Memória:     ${YELLOW}$MEMORY_INFO${NC}"

# Disco
DISK_INFO=$(df -h / | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')
echo -e "Disco:       ${YELLOW}$DISK_INFO${NC}"

# Uptime
UPTIME=$(uptime -p)
echo -e "Uptime:      ${YELLOW}$UPTIME${NC}"

echo ""

# Processos Suna
echo -e "${PURPLE}🔍 PROCESSOS SUNA${NC}"
echo "=================="

ps aux | grep -E "(suna|llama|redis|uvicorn|npm)" | grep -v grep | while read line; do
    echo -e "${YELLOW}$line${NC}"
done

echo ""

# Logs recentes
echo -e "${PURPLE}📝 LOGS RECENTES${NC}"
echo "================="

for service in "${services[@]}"; do
    echo -e "${CYAN}$service:${NC}"
    sudo journalctl -u $service.service --no-pager -n 2 --since "5 minutes ago" 2>/dev/null | tail -1 || echo "  Sem logs recentes"
done

echo ""

# Comandos úteis
echo -e "${PURPLE}🛠️ COMANDOS ÚTEIS${NC}"
echo "=================="
echo -e "${CYAN}Iniciar:${NC}     ./start_suna_wsl2.sh"
echo -e "${CYAN}Parar:${NC}       ./stop_suna_wsl2.sh"
echo -e "${CYAN}Reiniciar:${NC}   ./restart_suna_wsl2.sh"
echo -e "${CYAN}Backup:${NC}      ./backup_suna_wsl2.sh"
echo -e "${CYAN}Logs:${NC}        sudo journalctl -u suna-frontend.service -f"

echo ""
echo -e "${GREEN}✅ Monitoramento concluído!${NC}"
echo -e "${YELLOW}💡 Execute novamente para atualizar o status${NC}"