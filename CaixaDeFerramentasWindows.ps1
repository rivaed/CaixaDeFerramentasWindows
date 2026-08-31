#Requires -Version 5.1
<#
.SYNOPSIS
    Caixa de ferramentas unificada para Windows: debloat (detecta Windows 10/11
    automaticamente), faxina de disco, e mais ferramentas pontuais no mesmo arquivo.

.DESCRIPTION
    Junta varios scripts de manutencao de Windows num arquivo so. Os modos Debloat/
    Faxina/Tudo compartilham um catalogo unico data-driven (mesmo estilo dos scripts
    Windows10-Debloat/Windows11-Debloat/WinFaxina de origem): perfis Minimo/Completo/
    Agressivo, menu interativo por categorias, simulacao (dry-run), log em arquivo,
    relatorio JSON antes/depois. O modo Debloat detecta a versao do Windows (10 ou 11)
    e filtra o catalogo automaticamente para os itens aplicaveis.

    Outras ferramentas (itens de inicializacao, modo de seguranca, administrador
    oculto, diagnostico) tem seus proprios modos, cada um com sua propria logica —
    nao cabem no mesmo catalogo de perfis (ver CLAUDE.md para o motivo).

    Este script e construido em fases; alguns modos ainda nao estao implementados
    nesta versao (ver -Modo abaixo e o CHANGELOG).

.PARAMETER Modo
    Qual parte da caixa de ferramentas rodar: Debloat, Faxina, Tudo (debloat + faxina
    juntos), Inicializacao, SafeBoot, AdminOculto ou Diagnostico. Sem este parametro,
    mostra um menu para escolher.

.PARAMETER Perfil
    (Modos Debloat/Faxina/Tudo) Minimo (so itens seguros), Completo (seguros +
    opcionais, padrao) ou Agressivo (tudo, incluindo itens que quebram
    funcionalidades ou sao irreversiveis).

.PARAMETER Simular
    (Modos Debloat/Faxina/Tudo) Dry-run: mostra o que seria feito sem alterar nada.

.PARAMETER SemPontoRestauracao
    (Modos Debloat/Faxina/Tudo) Nao cria ponto de restauracao antes de executar.

.PARAMETER CaminhoRelatorioJson
    (Modos Debloat/Faxina/Tudo) Exporta um relatorio antes/depois em JSON.

.PARAMETER NaoInterativo
    Nao mostra menu nem pede confirmacao (exceto onde -Confirmar for exigido). Exige
    -Modo (sem -Modo, nao ha como saber o que executar sem perguntar).

.PARAMETER Confirmar
    Confirma a execucao de uma acao que altera o sistema em modo nao interativo
    (usado pelos modos Inicializacao e SafeBoot).

.PARAMETER CaminhoLog
    Caminho do arquivo de log. Padrao: %ProgramData%\CaixaDeFerramentasWindows\logs\<prefixo>_<data>.log

.EXAMPLE
    .\CaixaDeFerramentasWindows.ps1
    Mostra o menu principal para escolher o que fazer.

.EXAMPLE
    .\CaixaDeFerramentasWindows.ps1 -Modo Tudo -NaoInterativo -Perfil Completo
    Roda debloat (detectando Windows 10 ou 11 automaticamente) + faxina de disco juntos,
    perfil Completo, sem menu.

.EXAMPLE
    .\CaixaDeFerramentasWindows.ps1 -Modo Faxina -NaoInterativo -Perfil Minimo -Simular
    Simula (sem alterar nada) o que a faxina de disco faria no perfil Minimo.

.NOTES
    Irmao dos repositorios Windows10-Debloat, Windows11-Debloat, WinFaxina,
    StartupAppsNinja, SafeBoot-Ninja e ativar-win-admin — que continuam existindo e
    sendo mantidos separadamente para quem quer so uma ferramenta pequena. Esta caixa
    de ferramentas e um pacote complementar pra quem quer tudo junto.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script de console interativo: cores e menu fazem parte da UX; transcript captura tudo.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Dry-run proprio via -Simular nos modos Debloat/Faxina/Tudo; -Confirmar/prompt proprio nos demais.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Write-Log so existe no PowerShell 6.1+; o alvo deste script e o Windows PowerShell 5.1, onde nao ha colisao.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'TEMPORARIO (Fase 1/5): parametros especificos de Debloat/Faxina/Inicializacao/SafeBoot/AdminOculto/Diagnostico ja existem no param() fundido (decisao deliberada do plano: resolver toda colisao de nome uma vez so, no esqueleto), mas cada switch de -Modo ainda e um placeholder ate sua fase ser implementada. Remover esta supressao ao final da Fase 5, quando todo modo estiver com logica real consumindo seu parametro (ver CHANGELOG e o passe de PSScriptAnalyzer da Fase 5).')]
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Debloat', 'Faxina', 'Tudo', 'Inicializacao', 'SafeBoot', 'AdminOculto', 'Diagnostico')]
    [string]$Modo,

    # --- Catalogo fundido: Debloat | Faxina | Tudo (um motor so; Modo so pre-filtra Categorias) ---
    [ValidateSet('Minimo', 'Completo', 'Agressivo')]
    [string]$Perfil = 'Completo',

    [switch]$Simular,

    [switch]$SemPontoRestauracao,

    [ValidateNotNullOrEmpty()]
    [string]$CaminhoRelatorioJson,

    # --- Inicializacao (StartupAppsNinja) ---
    [ValidateSet('Listar', 'Adicionar', 'Remover', 'Habilitar', 'Desabilitar')]
    [string]$AcaoInicializacao = 'Listar',

    [ValidateNotNullOrEmpty()]
    [string]$Nome,

    [ValidateNotNullOrEmpty()]
    [string]$Comando,

    [ValidateSet('Usuario', 'TodosUsuarios')]
    [string]$Escopo = 'Usuario',

    [switch]$PermitirExperimental,

    [switch]$ForcarBuildNaoValidado,

    # --- SafeBoot ---
    [ValidateSet('Status', 'Minimo', 'Rede', 'Normal')]
    [string]$AcaoSafeBoot,

    # --- AdminOculto (ativar-win-admin) ---
    [ValidateSet('Status', 'Ativar', 'Desativar')]
    [string]$AcaoAdmin,

    [System.Security.SecureString]$SenhaSegura,

    # --- Diagnostico (DiagnosticoRapidoDePC) ---
    [ValidateRange(1, 3650)]
    [int]$Dias,

    [switch]$Exportar,

    [ValidateNotNullOrEmpty()]
    [string]$CaminhoCsv,

    [switch]$ExportarHtml,

    [ValidateNotNullOrEmpty()]
    [string]$CaminhoHtml,

    # --- Compartilhados entre modos ---
    [switch]$NaoInterativo,

    [switch]$Confirmar,

    [ValidateNotNullOrEmpty()]
    [string]$CaminhoLog
)

$script:VERSAO = '0.1.0'
$script:Simular = [bool]$Simular -or [bool]$WhatIfPreference
$script:TranscriptAtivo = $false
$script:ArquivoLog = $null

#region Utilitarios compartilhados (usados por todos os modos) -----------------

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Mensagem,
        [ValidateSet('Info', 'Ok', 'Aviso', 'Erro', 'Simulacao', 'Titulo')]
        [string]$Nivel = 'Info'
    )
    switch ($Nivel) {
        'Ok'        { Write-Host "[OK] $Mensagem" -ForegroundColor Green }
        'Aviso'     { Write-Host "[!] $Mensagem" -ForegroundColor Yellow }
        'Erro'      { Write-Host "[X] $Mensagem" -ForegroundColor Red }
        'Simulacao' { Write-Host "[SIMULACAO] $Mensagem" -ForegroundColor Cyan }
        'Titulo'    { Write-Host "`n$Mensagem" -ForegroundColor Cyan }
        default     { Write-Host $Mensagem }
    }
}

function Test-Admin {
    $identidade = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identidade).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    # Relanca em powershell.exe 5.1 quando falta elevacao ou quando esta no pwsh 7+
    # (modulos como Appx e Microsoft.PowerShell.LocalAccounts nao funcionam de forma
    # confiavel no PowerShell Core). Adotado em TODOS os modos que elevam, mesmo os
    # que originalmente nao precisavam dessa checagem — pior caso e um relancamento a
    # mais e inofensivo numa maquina rara onde PS7 e o ponto de entrada.
    param([Parameter(Mandatory)][System.Collections.IDictionary]$ParametrosOriginais)

    $precisaElevar = -not (Test-Admin)
    $precisaEngine = $PSVersionTable.PSEdition -eq 'Core'
    if (-not $precisaElevar -and -not $precisaEngine) { return }

    if ($NaoInterativo -and $precisaElevar) {
        Write-Log 'Sessao nao interativa sem privilegios de administrador. Execute ja elevado (RMM/SYSTEM/terminal admin).' 'Erro'
        exit 2
    }

    if ($precisaEngine -and -not $precisaElevar) {
        Write-Log 'Detectado PowerShell 7+. Reabrindo no Windows PowerShell 5.1...' 'Aviso'
    }
    else {
        Write-Log 'Solicitando privilegios de Administrador...' 'Aviso'
    }

    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    foreach ($p in $ParametrosOriginais.GetEnumerator()) {
        if ($p.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($p.Value) { $argumentos += ('-{0}' -f $p.Key) }
        }
        elseif ($p.Value -is [System.Security.SecureString]) {
            # SecureString nao pode virar argumento de linha de comando em texto puro
            # sem expor a senha — sera pedida de novo apos a elevacao. Checagem por
            # TIPO, nao por nome de parametro: cobre qualquer SecureString futuro
            # automaticamente, nao so -SenhaSegura.
            Write-Log ("-{0} nao pode ser repassado ao processo elevado (evita expor segredo na linha de comando). Sera pedido de novo." -f $p.Key) 'Aviso'
        }
        else {
            $argumentos += @(('-{0}' -f $p.Key), ('"{0}"' -f $p.Value))
        }
    }

    try {
        if ($precisaElevar) {
            Start-Process -FilePath 'powershell.exe' -ArgumentList ($argumentos -join ' ') -Verb RunAs -ErrorAction Stop
        }
        else {
            Start-Process -FilePath 'powershell.exe' -ArgumentList ($argumentos -join ' ') -ErrorAction Stop
        }
    }
    catch {
        Write-Log ('Elevacao cancelada ou falhou: {0}' -f $_.Exception.Message) 'Erro'
        exit 1
    }
    exit 0
}

function Start-Logging {
    param(
        [string]$CaminhoPersonalizado,
        [Parameter(Mandatory)][string]$Prefixo
    )
    $script:ArquivoLog = if ($CaminhoPersonalizado) {
        $CaminhoPersonalizado
    }
    else {
        $pasta = Join-Path $env:ProgramData 'CaixaDeFerramentasWindows\logs'
        if (-not (Test-Path $pasta)) { New-Item -Path $pasta -ItemType Directory -Force | Out-Null }
        Join-Path $pasta ('{0}_{1}.log' -f $Prefixo, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    try {
        $pastaLog = Split-Path -Path $script:ArquivoLog -Parent
        if ($pastaLog -and -not (Test-Path $pastaLog)) { New-Item -Path $pastaLog -ItemType Directory -Force | Out-Null }
        Start-Transcript -Path $script:ArquivoLog -ErrorAction Stop | Out-Null
        $script:TranscriptAtivo = $true
    }
    catch {
        Write-Log ('Nao foi possivel iniciar o log em arquivo: {0}' -f $_.Exception.Message) 'Aviso'
    }
}

function Stop-LoggingSeAtivo {
    if ($script:TranscriptAtivo) {
        try { Stop-Transcript | Out-Null }
        catch { Write-Verbose ('Falha ao encerrar o transcript: {0}' -f $_.Exception.Message) }
        $script:TranscriptAtivo = $false
        Write-Host ('Log salvo em: {0}' -f $script:ArquivoLog)
    }
}

function Confirm-Acao {
    # Forma compartilhada (usada por Inicializacao e SafeBoot): trata interativo e
    # -NaoInterativo/-Confirmar junto, sai direto quando nao confirmado. SafeBoot tem
    # uma variante propria (Confirm-AcaoSafeBoot) com aviso extra de RDP — nao reusar
    # esta para isso, contratos diferentes de proposito.
    param([Parameter(Mandatory)][string]$Descricao)
    if ($NaoInterativo) {
        if (-not $Confirmar) {
            Write-Log ('Acao "{0}" exige -Confirmar em modo nao interativo (altera o sistema).' -f $Descricao) 'Erro'
            exit 2
        }
        return $true
    }
    Write-Log $Descricao 'Aviso'
    $resposta = Read-Host 'Confirmar? (S/N)'
    if ($resposta -notmatch '^[sS]') {
        Write-Log 'Cancelado pelo usuario.' 'Info'
        exit 4
    }
    return $true
}

function ConvertTo-VersaoWindows {
    # Funcao pura (sem chamada ao Windows) para ser testavel com fixture em qualquer
    # SO. Checa ProductType=1 (workstation) nos DOIS casos de forma consistente — o
    # Assert-Windows10 original (Windows10-Debloat) tinha um gap real aqui (nao
    # checava ProductType, passaria hoje num Windows Server com build na faixa
    # certa); corrigido na versao unificada.
    param(
        [Parameter(Mandatory)][int]$ProductType,
        [Parameter(Mandatory)][int]$Build
    )
    $ehWorkstation = $ProductType -eq 1
    if ($ehWorkstation -and $Build -ge 22000) { return 'Win11' }
    if ($ehWorkstation -and $Build -ge 10240 -and $Build -lt 22000) { return 'Win10' }
    return 'Desconhecido'
}

function Get-VersaoWindows {
    # Retorna 'Win10' | 'Win11' | 'Desconhecido'. So o wrapper que consulta o Windows
    # de verdade — a decisao em si vive em ConvertTo-VersaoWindows (pura, testavel).
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return ConvertTo-VersaoWindows -ProductType ([int]$os.ProductType) -Build ([int]$os.BuildNumber)
}

function Assert-VersaoSuportada {
    param([Parameter(Mandatory)][string]$VersaoDetectada)
    if ($VersaoDetectada -ne 'Desconhecido') { return }

    Write-Log 'Sistema detectado nao e Windows 10/11 workstation (ou nao foi possivel determinar a versao).' 'Aviso'
    if ($script:Simular) {
        Write-Log 'Prosseguindo mesmo assim por estar em modo simulacao.' 'Aviso'
        return
    }
    if ($NaoInterativo) {
        Write-Log 'Abortando: modo nao interativo em sistema nao suportado.' 'Erro'
        exit 3
    }
    $resposta = Read-Host 'Continuar mesmo assim? (S/N)'
    if ($resposta -notmatch '^[sS]') { exit 3 }
}

#endregion

#region Fluxo principal ----------------------------------------------------------

if (-not $Modo -and $NaoInterativo) {
    Write-Log 'Modo nao interativo exige -Modo (sem ele nao ha como saber o que executar sem perguntar).' 'Erro'
    exit 2
}

if ($WhatIfPreference -and $Modo -notin @('Debloat', 'Faxina', 'Tudo', $null)) {
    Write-Log '-WhatIf nao tem efeito neste modo; use -Simular (funciona so em Debloat/Faxina/Tudo).' 'Aviso'
}

switch ($Modo) {
    { $_ -in @('Debloat', 'Faxina', 'Tudo') } {
        Write-Log ("Modo '{0}' ainda sera implementado na Fase 2/3 deste projeto (catalogo fundido)." -f $Modo) 'Erro'
        exit 9
    }
    'Diagnostico' {
        Write-Log "Modo 'Diagnostico' ainda sera implementado na Fase 4 deste projeto." 'Erro'
        exit 9
    }
    'AdminOculto' {
        Write-Log "Modo 'AdminOculto' ainda sera implementado na Fase 4 deste projeto." 'Erro'
        exit 9
    }
    'SafeBoot' {
        Write-Log "Modo 'SafeBoot' ainda sera implementado na Fase 4 deste projeto." 'Erro'
        exit 9
    }
    'Inicializacao' {
        Write-Log "Modo 'Inicializacao' ainda sera implementado na Fase 4 deste projeto." 'Erro'
        exit 9
    }
    default {
        Write-Log "Menu principal ainda sera implementado na Fase 5 deste projeto. Use -Modo por enquanto." 'Erro'
        exit 9
    }
}

#endregion
