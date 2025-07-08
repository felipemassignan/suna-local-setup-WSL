# update_hosts.ps1
# Atualiza arquivo hosts do Windows para acesso amigavel

param(
    [switch]$Remove = $false,
    [string]$Hostname = "suna.local"
)

Write-Host "Atualizando arquivo hosts do Windows..." -ForegroundColor Cyan

# Verificar privilegios de administrador
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERRO: Este script deve ser executado como Administrador!" -ForegroundColor Red
    exit 1
}

$hostsPath = "C:\Windows\System32\drivers\etc\hosts"

if ($Remove) {
    Write-Host "Removendo entradas do Suna do arquivo hosts..." -ForegroundColor Yellow
    
    try {
        $hostsContent = Get-Content $hostsPath
        $newContent = $hostsContent | Where-Object { $_ -notmatch $Hostname }
        $newContent | Set-Content $hostsPath -Force
        Write-Host "OK: Entradas removidas com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Host "ERRO: Falha ao remover entradas: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    # Obter IP do WSL2
    try {
        $wslIP = (wsl hostname -I).Trim()
        if (-not $wslIP) {
            throw "IP do WSL2 nao encontrado"
        }
        
        Write-Host "IP do WSL2 detectado: $wslIP" -ForegroundColor Cyan
        
        # Ler arquivo hosts atual
        $hostsContent = Get-Content $hostsPath -Raw
        
        # Remover entradas antigas do hostname
        $cleanContent = $hostsContent -replace "(?m)^.*\s+$([regex]::Escape($Hostname))\s*`r?`n?", ""
        
        # Adicionar nova entrada
        $newEntry = "$wslIP`t$Hostname"
        $updatedContent = $cleanContent.TrimEnd() + "`n" + $newEntry + "`n"
        
        # Salvar arquivo
        $updatedContent | Set-Content $hostsPath -Force -NoNewline
        
        Write-Host "OK: Arquivo hosts atualizado com sucesso!" -ForegroundColor Green
        Write-Host "Agora voce pode acessar:" -ForegroundColor Cyan
        Write-Host "   http://$Hostname`:3000 (Frontend)" -ForegroundColor White
        Write-Host "   http://$Hostname`:8000 (Backend)" -ForegroundColor White
        Write-Host "   http://$Hostname`:8080 (LLM API)" -ForegroundColor White
        
    }
    catch {
        Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Certifique-se de que o WSL2 esta rodando e tente novamente." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Para reverter as mudancas, execute: .\update_hosts.ps1 -Remove" -ForegroundColor Yellow

pause