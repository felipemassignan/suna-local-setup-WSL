#!/bin/bash
# check_syntax.sh - Verificador de sintaxe

echo "🔍 Verificando sintaxe dos scripts..."

scripts=("install_wsl2.sh" "start_suna_wsl2.sh" "stop_suna_wsl2.sh" "monitor_suna_wsl2.sh" "configure_wsl2_network.sh")

for script in "${scripts[@]}"; do
    if [ -f "$script" ]; then
        echo -n "Verificando $script... "
        if bash -n "$script" 2>/dev/null; then
            echo "✅ OK"
        else
            echo "❌ ERRO"
            echo "Detalhes do erro:"
            bash -n "$script"
        fi
    else
        echo "⚠️  $script não encontrado"
    fi
done

echo "✅ Verificação concluída!"