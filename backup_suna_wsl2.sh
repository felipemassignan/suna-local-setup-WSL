#!/bin/bash
# backup_suna_wsl2.sh - Sistema de backup automatizado

set -e

source ./scripts/common.sh

BACKUP_DIR="/opt/suna/backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_NAME="suna_backup_$TIMESTAMP"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

log_info "Iniciando backup do Suna..."

# Criar diretório de backup
mkdir -p "$BACKUP_PATH"

# Parar serviços temporariamente
log_info "Parando serviços para backup consistente..."
sudo systemctl stop suna-frontend suna-backend

# Backup de dados
log_info "Fazendo backup dos dados..."
cp -r /opt/suna/data "$BACKUP_PATH/"
cp -r /opt/suna/models "$BACKUP_PATH/"
cp -r /etc/suna "$BACKUP_PATH/config"

# Backup do Redis
log_info "Fazendo backup do Redis..."
redis-cli SAVE
cp /var/lib/redis/dump.rdb "$BACKUP_PATH/"

# Backup de configurações
log_info "Fazendo backup das configurações..."
cp -r /opt/suna/suna-local-setup "$BACKUP_PATH/source"

# Criar arquivo de informações
cat > "$BACKUP_PATH/backup_info.txt" << EOF
Backup criado em: $(date)
Versão do sistema: $(lsb_release -d | cut -f2)
IP WSL2: $(hostname -I | awk '{print $1}')
Usuário: $USER
Tamanho: $(du -sh "$BACKUP_PATH" | cut -f1)
EOF

# Compactar backup
log_info "Compactando backup..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# Reiniciar serviços
log_info "Reiniciando serviços..."
sudo systemctl start suna-backend suna-frontend

# Limpeza de backups antigos (manter últimos 5)
log_info "Limpando backups antigos..."
ls -t suna_backup_*.tar.gz | tail -n +6 | xargs -r rm

BACKUP_SIZE=$(du -sh "${BACKUP_NAME}.tar.gz" | cut -f1)
log_success "Backup concluído!"
log_info "Arquivo: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
log_info "Tamanho: $BACKUP_SIZE"