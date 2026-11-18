# Reglas del firewall de Windows para que los celulares entren al taller por la Wi-Fi (Fase 8, Paso 7). Las corre
# instalar.ps1 como administrador (ventana de permiso de Windows). Solo entrada TCP al puerto del taller y solo en
# redes privadas (ADR-001): en una red pública (un café, un aeropuerto) el portátil no deja entrar a nadie.
# Docker Desktop abre por su cuenta los puertos publicados también en redes públicas (simulacro, 2026-11-16): por eso
# hay además una regla que bloquea el puerto en redes públicas (en Windows, un bloqueo le gana a un permiso).
# -Privadas: índices de las redes que el dueño dijo que son la Wi-Fi del taller; se marcan como privadas.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File regla-firewall.ps1 -Puerto 80 [-Privadas 12,15]
param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$Puerto,
    [int[]]$Privadas = @()
)
$ErrorActionPreference = 'Stop'
$nombre = 'Taller (celulares en la Wi-Fi)'
$bloqueo = 'Taller (bloqueado en redes públicas)'
try {
    foreach ($r in @($nombre, $bloqueo)) { Get-NetFirewallRule -DisplayName $r -ErrorAction SilentlyContinue | Remove-NetFirewallRule }
    New-NetFirewallRule -DisplayName $nombre -Description 'Sistema del taller: entrada desde los celulares de la Wi-Fi.' `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Puerto -Profile Private | Out-Null
    New-NetFirewallRule -DisplayName $bloqueo -Description 'Sistema del taller: nadie entra desde una red pública.' `
        -Direction Inbound -Action Block -Protocol TCP -LocalPort $Puerto -Profile Public | Out-Null
    foreach ($i in $Privadas) { Set-NetConnectionProfile -InterfaceIndex $i -NetworkCategory Private }
    exit 0
}
catch {
    exit 1
}
