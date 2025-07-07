#!/bin/bash
# configure_wsl2_network.sh - Configuração de rede para WSL2

set -e

source ./scripts/common.sh

log_info "Configurando rede WSL2..."

WSL_IP=$(hostname -I | awk '{print $1}')
WINDOWS_IP=$(ip route | grep default | awk '{print $3}')

log_info "IP WSL2: $WSL_IP"
log_info "IP Windows: $WINDOWS_IP"

# Configurar backend
log_info "Configurando backend..."
cat > /etc/suna/backend/.env << EOF
# Configuração WSL2 - Backend
ENVIRONMENT=LOCAL_WSL2
HOST=0.0.0.0
PORT=8000
FRONTEND_URL=http://$WSL_IP:3000
CORS_ORIGINS=["http://$WSL_IP:3000","http://suna.local:3000","http://localhost:3000"]

# LLM Configuration
LLM_API_BASE=http://localhost:8080/v1
LLM_MODEL=mistral-7b-instruct
LLM_TEMPERATURE=0.7
LLM_MAX_TOKENS=2048

# Redis Configuration
REDIS_URL=redis://localhost:6379
REDIS_DB=0

# Vector Store
VECTOR_STORE_PATH=/opt/suna/data/vector_store
VECTOR_STORE_TYPE=FAISS

# Security (Desabilitado para modo local)
DISABLE_AUTH=true
LOCAL_MODE=true
DEBUG=true

# Logging
LOG_LEVEL=INFO
LOG_FILE=/opt/suna/logs/backend.log
EOF

# Configurar frontend
log_info "Configurando frontend..."
cat > /etc/suna/frontend/.env.local << EOF
# Configuração WSL2 - Frontend
NEXT_PUBLIC_API_URL=http://$WSL_IP:8000
NEXT_PUBLIC_WS_URL=ws://$WSL_IP:8000
NEXT_PUBLIC_LOCAL_MODE=true
NEXT_PUBLIC_DISABLE_AUTH=true
NEXT_PUBLIC_DEBUG=true

# Configurações de desenvolvimento
NEXT_PUBLIC_DEV_MODE=true
NEXT_PUBLIC_WSL2_MODE=true
EOF

# Configurar Redis para aceitar conexões externas
log_info "Configurando Redis..."
sudo sed -i 's/bind 127.0.0.1/bind 0.0.0.0/g' /etc/redis/redis.conf
sudo sed -i 's/protected-mode yes/protected-mode no/g' /etc/redis/redis.conf

# Configurar Nginx como proxy reverso (opcional)
log_info "Configurando Nginx..."
sudo tee /etc/nginx/sites-available/suna << EOF
server {
    listen 80;
    server_name suna.local $WSL_IP;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    location /api {
        proxy_pass http://localhost:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/suna /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

log_success "Configuração de rede WSL2 concluída!"
log_info "URLs de acesso:"
echo "  Frontend: http://$WSL_IP:3000"
echo "  Backend:  http://$WSL_IP:8000"
echo "  LLM API:  http://$WSL_IP:8080"
