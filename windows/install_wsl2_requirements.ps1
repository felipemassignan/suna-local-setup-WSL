# install_wsl2_requirements.ps1
# Verificar e instalar pre-requisitos WSL2

Write-Host "Verificando pre-requisitos WSL2..." -ForegroundColor Cyan

# Verificar se está executando como administrador
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERRO: Este script deve ser executado como Administrador!" -ForegroundColor Red
    exit 1
}

# Verificar versão do Windows
$windowsVersion = [System.Environment]::OSVersion.Version
Write-Host "Versao do Windows: $($windowsVersion.Major).$($windowsVersion.Minor).$($windowsVersion.Build)" -ForegroundColor White

if ($windowsVersion.Build -lt 19041) {
    Write-Host "ERRO: WSL2 requer Windows 10 versao 2004 (build 19041) ou superior" -ForegroundColor Red
    exit 1
}

# Verificar se WSL está habilitado
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -eq "Disabled") {
    Write-Host "Habilitando WSL..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
}

# Verificar se Virtual Machine Platform está habilitado
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmFeature.State -eq "Disabled") {
    Write-Host "Habilitando Virtual Machine Platform..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
}

# Verificar se WSL2 está instalado
try {
    $wslVersion = wsl --version
    Write-Host "WSL instalado: $wslVersion" -ForegroundColor Green
}
catch {
    Write-Host "AVISO: WSL nao encontrado. Instalando..." -ForegroundColor Yellow
    wsl --install --no-distribution
}

# Verificar distribuições instaladas
try {
    $distributions = wsl --list --verbose
    Write-Host "Distribuicoes WSL instaladas:" -ForegroundColor Cyan
    Write-Host $distributions -ForegroundColor White
}
catch {
    Write-Host "Nenhuma distribuicao WSL encontrada." -ForegroundColor Yellow
    Write-Host "Instale uma distribuicao com: wsl --install -d Ubuntu-22.04" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Verificacao de pre-requisitos concluida!" -ForegroundColor Green
Write-Host "Reinicie o computador se necessario antes de continuar." -ForegroundColor Yellow

pause