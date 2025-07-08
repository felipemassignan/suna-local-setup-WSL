# Suna Local Setup

A complete, 100% local implementation of the [Suna AI agent framework](https://github.com/kortix-ai/suna) that runs entirely on your own hardware without any external API dependencies. This system replaces all cloud services with local alternatives, centered around a Mistral 7B model served via llama.cpp.

## Features

- **Completely offline operation** - no external API dependencies whatsoever
- Uses Mistral 7B Instruct model via llama.cpp for local AI capabilities
- Replaces all cloud services with local alternatives:
  - Local LLM instead of OpenAI
  - Local FAISS vector store for document retrieval
  - Local mock search instead of Tavily
  - Local mock image generation
  - Local authentication instead of Supabase
  - Local file storage instead of cloud storage
- Optimized for CPU-only operation with minimal resource usage
- Bypasses authentication and database requirements in LOCAL mode
- Includes systemd service files for all components
- Provides scripts for easy installation and management

# Suna Local Setup - WSL2 Edition

Fork otimizado do [suna-local-setup](https://github.com/88atman77/suna-local-setup) para ambiente WSL2 com acesso via navegador Windows.

## 🎯 **Características**

- ✅ Instalação automatizada no WSL2
- ✅ Configuração automática de rede
- ✅ Acesso via navegador Windows
- ✅ Scripts de monitoramento
- ✅ Configuração automática de firewall
- ✅ Backup automatizado

## ⚡ **Instalação Rápida**

```bash
# 1. Clone este repositório no WSL2
git clone https://github.com/felipemassignan/suna-wsl2-setup.git
cd suna-wsl2-setup

# 2. Execute a instalação automatizada
chmod +x *.sh
./install_wsl2.sh

# 3. Configure o Windows (PowerShell como Admin)
cd windows
.\configure_firewall.ps1
.\update_hosts.ps1
## Troubleshooting

## **Melhorias Prioritárias a Implementar**

### **Alta Prioridade:**
1. ✅ Melhorar `install_wsl2.sh` com verificações robustas
2. ✅ Criar `scripts/common.sh` com funções compartilhadas  
3. ✅ Adicionar documentação detalhada
4. ✅ Melhorar tratamento de erros nos scripts
5. ✅ Adicionar verificação de recursos do sistema

### **Média Prioridade:**
1. 🔄 Criar script de atualização automática
2. 🔄 Implementar sistema de logs estruturado
3. 🔄 Adicionar testes automatizados
4. 🔄 Criar dashboard web de monitoramento
5. 🔄 Implementar backup incremental

### **Baixa Prioridade:**
1. 📋 Adicionar suporte a outros modelos LLM
2. 📋 Criar interface de configuração web
3. 📋 Implementar métricas de performance
4. 📋 Adicionar suporte a Docker Compose
5. 📋 Criar instalador GUI para Windows

## 🎯 **Próximos Passos Recomendados**

1. **Implementar as melhorias de alta prioridade**
2. **Testar instalação em ambiente limpo**
3. **Criar CI/CD para testes automatizados**
4. **Documentar casos de uso específicos**
5. **Criar vídeo tutorial de instalação**

### High Memory Usage

If the system is running out of memory:
1. Reduce the Redis memory limit
2. Use a more quantized model (Q2_K instead of Q4_K)
3. Reduce the context size in llama.cpp server

### Slow Response Times

If responses are too slow:
1. Adjust the number of threads based on your CPU
2. Consider using a smaller model if necessary

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [Suna AI](https://github.com/kortix-ai/suna) - The original AI agent framework
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - Efficient inference of LLaMA models
- [Mistral AI](https://mistral.ai/) - Creators of the Mistral 7B model
- [FAISS](https://github.com/facebookresearch/faiss) - Vector similarity search library
