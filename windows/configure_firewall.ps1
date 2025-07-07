# configure_firewall.ps1
# Execute como Administrador no PowerShell do Windows

param(
    [switch]$Remove = $false
)

Write-Host "🚀 Configurando Firewall do Windows para Suna WSL2..." -ForegroundColor Cyan

# Verificar se está executando como administrador
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "❌ Este script deve ser executado como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botão direito no PowerShell e selecione 'Executar como Administrador'" -ForegroundColor Yellow
    pause
    exit 1
}

# Definir regras de firewall
$rules = @(
    @{ Name = "Suna Frontend WSL2"; Port = 3000; Protocol = "TCP"; Description = "Acesso ao frontend Suna via WSL2" },
    @{ Name = "Suna Backend WSL2"; Port = 8000; Protocol = "TCP"; Description = "Acesso ao backend Suna via WSL2" },
    @{ Name = "Suna LLM WSL2"; Port = 8080; Protocol = "TCP"; Description = "Acesso ao LLM Suna via WSL2" },
    @{ Name = "Suna Redis WSL2"; Port = 6379; Protocol = "TCP"; Description = "Acesso ao Redis Suna via WSL2" },
    @{ Name = "Suna Nginx WSL2"; Port = 80; Protocol = "TCP"; Description = "Acesso ao Nginx Suna via WSL2" }
)

if ($Remove) {
    Write-Host "🗑️ Removendo regras de firewall..." -ForegroundColor Yellow
    foreach ($rule in $rules) {
        $ruleName = $rule.Name
        try {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            Write-Host "✅ Regra removida: $ruleName" -ForegroundColor Green
        }
        catch {
            Write-Host "⚠️ Regra não encontrada: $ruleName" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "➕ Adicionando regras de firewall..." -ForegroundColor Green
    
    foreach ($rule in $rules) {
        $ruleName = $rule.Name
        $port = $rule.Port
        $protocol = $rule.Protocol
        $description = $rule.Description

        # Remover regra existente se houver
        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

        try {
            New-NetFirewallRule `
                -DisplayName $ruleName `
                -Direction Inbound `
                -Protocol $protocol `
                -LocalPort $port `
                -Action Allow `
                -Description $description `
                -EdgeTraversalPolicy Allow

            Write-Host "✅ Regra adicionada: $ruleName (Porta: $port/$protocol)" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Erro ao adicionar regra $ruleName : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Verificar WSL2 IP
try {
    $wslIP = (wsl hostname -I).Trim()
    if ($wslIP) {
        Write-Host ""
        Write-Host "📍 IP do WSL2 detectado: $wslIP" -ForegroundColor Cyan
        Write-Host "🌐 URLs de acesso:" -ForegroundColor Cyan
        Write-Host "   Frontend: http://$wslIP`:3000" -ForegroundColor White
        Write-Host "   Backend:  http://$wslIP`:8000" -ForegroundColor White
        Write-Host "   LLM API:  http://$wslIP`:8080" -ForegroundColor White
    }
}
catch {
    Write-Host "⚠️ Não foi possível detectar o IP do WSL2" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🎉 Configuração do firewall concluída!" -ForegroundColor Green
Write-Host "💡 Para remover as regras, execute: .\configure_firewall.ps1 -Remove" -ForegroundColor Yellow

pause