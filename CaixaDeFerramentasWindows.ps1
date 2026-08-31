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

#region Ponto de restauracao (Debloat/Faxina/Tudo) -------------------------------

function New-RestorePoint {
    if ($script:Simular) {
        Write-Log 'Criaria ponto de restauracao "Antes da Caixa de Ferramentas".' 'Simulacao'
        return $true
    }
    Write-Log 'Criando ponto de restauracao do sistema...' 'Titulo'

    $chaveSR = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqExistia = $false
    $freqOriginal = $null
    try {
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue

        $prop = Get-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        if ($null -ne $prop) {
            $freqExistia = $true
            $freqOriginal = $prop.SystemRestorePointCreationFrequency
        }
        Set-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type DWord -ErrorAction Stop

        $antes = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        $seqAntes = 0
        if ($antes.Count -gt 0) { $seqAntes = ($antes | Select-Object -Last 1).SequenceNumber }

        Checkpoint-Computer -Description ('Antes da Caixa de Ferramentas v{0}' -f $script:VERSAO) -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop

        $depois = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
        $seqDepois = 0
        if ($depois.Count -gt 0) { $seqDepois = ($depois | Select-Object -Last 1).SequenceNumber }

        if ($seqDepois -gt $seqAntes) {
            Write-Log ('Ponto de restauracao criado e verificado (sequencia {0}).' -f $seqDepois) 'Ok'
            return $true
        }
        Write-Log 'O Windows nao criou o ponto de restauracao (Restauracao do Sistema pode estar desativada).' 'Aviso'
        return $false
    }
    catch {
        Write-Log ('Falha ao criar ponto de restauracao: {0}' -f $_.Exception.Message) 'Aviso'
        return $false
    }
    finally {
        try {
            if ($freqExistia) {
                Set-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -Value $freqOriginal -Type DWord -ErrorAction SilentlyContinue
            }
            else {
                Remove-ItemProperty -Path $chaveSR -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Verbose ('Nao foi possivel restaurar SystemRestorePointCreationFrequency: {0}' -f $_.Exception.Message)
        }
    }
}

#endregion

#region Catalogo fundido (Debloat/Faxina/Tudo) ------------------------------------
# Cada item: Id unico no catalogo INTEIRO, Categoria, Tipo, Nivel, Descricao,
# SistemasAlvo opcional (@('Win10')|@('Win11')|ausente = os dois - NUNCA array vazio).
# Tipo=Especial usa Alvo como palavra-chave; precisa de case em Invoke-ItemCatalogo E
# em Get-AcaoDescricao (bug real ja corrigido uma vez no WinFaxina por faltar isso).
#
# Fase 2: so os 11 itens do WinFaxina (categorias Temporarios/Navegadores/Sistema/
# Lixeira). Apps/Telemetria/Desempenho (Debloat) entram na Fase 3 - ver CLAUDE.md.
#
# NOTA: a pasta Prefetch foi deliberadamente deixada de fora. A Microsoft confirma
# que o Windows a gerencia sozinho e que apaga-la manualmente NAO acelera nada.

$script:Catalogo = @(
    [pscustomobject]@{ Id = 'temp-usuario'; Categoria = 'Temporarios'; Tipo = 'LimpezaPasta'; Alvo = "$env:TEMP";                                                        Descricao = 'Temporarios do usuario (%TEMP%)';          Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'temp-sistema'; Categoria = 'Temporarios'; Tipo = 'LimpezaPasta'; Alvo = "$env:SystemRoot\Temp";                                             Descricao = 'Temporarios do sistema (Windows\Temp)';    Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'wer-logs';     Categoria = 'Temporarios'; Tipo = 'LimpezaPasta'; Alvo = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive";            Descricao = 'Relatorios antigos de erro (WER)'; Nivel = 'Seguro' }

    [pscustomobject]@{ Id = 'chrome-cache';  Categoria = 'Navegadores'; Tipo = 'Especial'; Alvo = 'CacheChrome';  Descricao = 'Cache do Google Chrome (todos os perfis)'; Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'edge-cache';    Categoria = 'Navegadores'; Tipo = 'Especial'; Alvo = 'CacheEdge';    Descricao = 'Cache do Microsoft Edge (todos os perfis)'; Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'firefox-cache'; Categoria = 'Navegadores'; Tipo = 'Especial'; Alvo = 'CacheFirefox'; Descricao = 'Cache do Firefox (todos os perfis)';       Nivel = 'Seguro' }

    [pscustomobject]@{ Id = 'update-cache';    Categoria = 'Sistema'; Tipo = 'Especial'; Alvo = 'CacheWindowsUpdate'; Descricao = 'Cache de atualizacoes do Windows (SoftwareDistribution)'; Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'dism-cleanup';    Categoria = 'Sistema'; Tipo = 'Especial'; Alvo = 'DismCleanup';        Descricao = 'Otimizar componente store (DISM, pode demorar)';          Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'patch-cache';     Categoria = 'Sistema'; Tipo = 'Especial'; Alvo = 'PatchCache';         Descricao = 'Cache de patches do Windows Installer ($PatchCache$)';    Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'fila-impressao';  Categoria = 'Sistema'; Tipo = 'Especial'; Alvo = 'FilaImpressao';      Descricao = 'Destravar fila de impressao presa (reinicia o Spooler)';  Nivel = 'Seguro' }

    [pscustomobject]@{ Id = 'lixeira'; Categoria = 'Lixeira'; Tipo = 'Especial'; Alvo = 'RecycleBin'; Descricao = 'Esvaziar a Lixeira (irreversivel)'; Nivel = 'Opcional' }
)

# Ordem canonica das 7 categorias do esquema fundido (ver CLAUDE.md). Usada para
# exibicao (ex.: resumo em Show-Confirmacao); a lista que efetivamente aparece no
# menu/participa da selecao por perfil e sempre a filtrada por -Modo, abaixo.
$script:Categorias = @('Apps', 'Telemetria', 'Desempenho', 'Temporarios', 'Navegadores', 'Sistema', 'Lixeira')

# "Um motor so; Modo so pre-filtra Categorias" (decisao do plano). Apps/Telemetria/
# Desempenho ainda nao tem nenhum item no catalogo (chegam na Fase 3) - declarar o
# mapeamento agora nao antecipa a implementacao do Debloat, so a taxonomia ja
# decidida, e evita reabrir este ponto quando a Fase 3 chegar.
$script:CategoriasPorModo = @{
    Faxina  = @('Temporarios', 'Navegadores', 'Sistema', 'Lixeira')
    Debloat = @('Apps', 'Telemetria', 'Desempenho', 'Sistema')
    Tudo    = $script:Categorias
}

function Get-ItensDoPerfil {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Minimo', 'Completo', 'Agressivo')]
        [string]$NomePerfil,
        [Parameter(Mandatory)][string[]]$Categorias
    )
    $niveis = switch ($NomePerfil) {
        'Minimo'    { @('Seguro') }
        'Completo'  { @('Seguro', 'Opcional') }
        'Agressivo' { @('Seguro', 'Opcional', 'Agressivo') }
    }
    $script:Catalogo | Where-Object { $niveis -contains $_.Nivel -and $Categorias -contains $_.Categoria }
}

#endregion

#region Executores do catalogo (Debloat/Faxina/Tudo) ------------------------------

function Get-TamanhoLegivel {
    param([Parameter(Mandatory)][double]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N1} KB' -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-TamanhoPasta {
    param([Parameter(Mandatory)][string]$Caminho)
    if (-not (Test-Path $Caminho)) { return 0 }
    $soma = Get-ChildItem -Path $Caminho -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($soma.Sum) { return $soma.Sum }
    return 0
}

function Clear-PastaComRelatorio {
    param([Parameter(Mandatory)]$Item)

    $alvo = $Item.Alvo
    if (-not (Test-Path $alvo)) {
        return @{ Status = 'NaoEncontrado'; Detalhe = 'pasta nao existe'; BytesLiberados = 0 }
    }
    $antesBytes = Get-TamanhoPasta -Caminho $alvo
    if ($antesBytes -eq 0) {
        return @{ Status = 'Ok'; Detalhe = 'ja estava vazia'; BytesLiberados = 0 }
    }
    Get-ChildItem -Path $alvo -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $depoisBytes = Get-TamanhoPasta -Caminho $alvo
    $liberado = $antesBytes - $depoisBytes
    if ($depoisBytes -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('liberado ~{0}' -f (Get-TamanhoLegivel $liberado)); BytesLiberados = $liberado }
    }
    return @{ Status = 'Parcial'; Detalhe = ('liberado ~{0}, {1} restante (em uso)' -f (Get-TamanhoLegivel $liberado), (Get-TamanhoLegivel $depoisBytes)); BytesLiberados = $liberado }
}

function Get-PastasPerfilNavegador {
    param(
        [Parameter(Mandatory)][string]$RaizUserData,
        [Parameter(Mandatory)][string]$SubcaminhoCache
    )
    # Chrome/Edge: primeiro perfil e sempre "Default"; os demais sao "Profile 1", "Profile 2"...
    $pastas = @()
    if (-not (Test-Path $RaizUserData)) { return $pastas }
    Get-ChildItem -Path $RaizUserData -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' } |
        ForEach-Object {
            $pastas += Join-Path $_.FullName $SubcaminhoCache
        }
    return $pastas
}

function Clear-CacheNavegador {
    param(
        [Parameter(Mandatory)][string]$NomeProcesso,
        [Parameter(Mandatory)][string[]]$PastasCache
    )
    if (Get-Process -Name $NomeProcesso -ErrorAction SilentlyContinue) {
        return @{ Status = 'Parcial'; Detalhe = ('{0} esta aberto — feche-o para uma limpeza completa; itens em uso ficaram de fora' -f $NomeProcesso); BytesLiberados = 0 }
    }
    $existentes = @($PastasCache | Where-Object { Test-Path $_ })
    if ($existentes.Count -eq 0) {
        return @{ Status = 'NaoEncontrado'; Detalhe = 'nenhum perfil encontrado'; BytesLiberados = 0 }
    }
    $totalAntes = 0
    foreach ($pasta in $existentes) { $totalAntes += Get-TamanhoPasta -Caminho $pasta }
    foreach ($pasta in $existentes) {
        Get-ChildItem -Path $pasta -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    $totalDepois = 0
    foreach ($pasta in $existentes) { $totalDepois += Get-TamanhoPasta -Caminho $pasta }
    $liberado = $totalAntes - $totalDepois
    return @{ Status = 'Ok'; Detalhe = ('{0} perfil(is), liberado ~{1}' -f $existentes.Count, (Get-TamanhoLegivel $liberado)); BytesLiberados = $liberado }
}

function Clear-CacheChrome {
    $raiz = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    $pastas = Get-PastasPerfilNavegador -RaizUserData $raiz -SubcaminhoCache 'Cache'
    Clear-CacheNavegador -NomeProcesso 'chrome' -PastasCache $pastas
}

function Clear-CacheEdge {
    $raiz = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
    $pastas = Get-PastasPerfilNavegador -RaizUserData $raiz -SubcaminhoCache 'Cache'
    Clear-CacheNavegador -NomeProcesso 'msedge' -PastasCache $pastas
}

function Clear-CacheFirefox {
    $raiz = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    $pastas = @()
    if (Test-Path $raiz) {
        Get-ChildItem -Path $raiz -Directory -Filter '*.default*' -ErrorAction SilentlyContinue |
            ForEach-Object { $pastas += Join-Path $_.FullName 'cache2\entries' }
    }
    Clear-CacheNavegador -NomeProcesso 'firefox' -PastasCache $pastas
}

function Clear-CacheWindowsUpdate {
    $pastaDownload = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    if (-not (Test-Path $pastaDownload)) {
        return @{ Status = 'NaoEncontrado'; Detalhe = 'pasta nao existe'; BytesLiberados = 0 }
    }
    $antesBytes = Get-TamanhoPasta -Caminho $pastaDownload
    if ($antesBytes -eq 0) {
        return @{ Status = 'Ok'; Detalhe = 'ja estava vazia'; BytesLiberados = 0 }
    }

    # Procedimento oficial da Microsoft: parar os servicos antes de mexer na pasta,
    # para evitar erro de arquivo em uso ou corromper um download em andamento.
    $servicos = @('wuauserv', 'bits', 'cryptsvc')
    $pararam = @()
    try {
        foreach ($svc in $servicos) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq 'Running') {
                Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                $pararam += $svc
            }
        }
        Get-ChildItem -Path $pastaDownload -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    finally {
        foreach ($svc in $pararam) {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }
    }

    $depoisBytes = Get-TamanhoPasta -Caminho $pastaDownload
    $liberado = $antesBytes - $depoisBytes
    if ($depoisBytes -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('liberado ~{0}' -f (Get-TamanhoLegivel $liberado)); BytesLiberados = $liberado }
    }
    return @{ Status = 'Parcial'; Detalhe = ('liberado ~{0}, {1} restante (em uso)' -f (Get-TamanhoLegivel $liberado), (Get-TamanhoLegivel $depoisBytes)); BytesLiberados = $liberado }
}

function Invoke-DismCleanup {
    try {
        # Deliberadamente SEM /ResetBase: a documentacao da Microsoft confirma que
        # /ResetBase remove de forma permanente a capacidade de desinstalar
        # atualizacoes ja aplicadas. Sem essa flag, a limpeza e reversivel.
        $saida = & Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
        if ($LASTEXITCODE -eq 0) {
            # DISM nao informa quanto foi liberado -- nao ha como medir sem escanear
            # o WinSxS inteiro antes/depois (caro demais so para fins de relatorio).
            return @{ Status = 'Ok'; Detalhe = 'componente store otimizado'; BytesLiberados = $null }
        }
        $resumoSaida = ($saida | Select-Object -Last 3) -join ' | '
        return @{ Status = 'Falha'; Detalhe = ('DISM retornou codigo {0}: {1}' -f $LASTEXITCODE, $resumoSaida); BytesLiberados = $null }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message; BytesLiberados = $null }
    }
}

function Clear-PatchCache {
    # Correcao de bug (herdada do WinFaxina): "$PatchCache$" dentro de aspas duplas
    # faz o PowerShell interpretar "$PatchCache" como referencia a variavel
    # inexistente (vira string vazia). Aspas simples tratam o nome como texto literal.
    $alvo = Join-Path $env:SystemRoot 'Installer\$PatchCache$'
    if (-not (Test-Path $alvo)) {
        return @{ Status = 'NaoEncontrado'; Detalhe = 'pasta nao existe'; BytesLiberados = 0 }
    }
    $antesBytes = Get-TamanhoPasta -Caminho $alvo
    if ($antesBytes -eq 0) {
        return @{ Status = 'Ok'; Detalhe = 'ja estava vazia'; BytesLiberados = 0 }
    }
    Get-ChildItem -Path $alvo -Recurse -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $depoisBytes = Get-TamanhoPasta -Caminho $alvo
    $liberado = $antesBytes - $depoisBytes
    return @{ Status = 'Ok'; Detalhe = ('liberado ~{0} (guarde a midia de instalacao original de programas MSI, caso precise repara-los depois)' -f (Get-TamanhoLegivel $liberado)); BytesLiberados = $liberado }
}

function Clear-FilaImpressao {
    # Procedimento oficial de suporte da Microsoft: parar o Spooler antes de mexer
    # na pasta de spool (evita erro de arquivo em uso com um job ainda "gravando"),
    # limpar o conteudo, reiniciar o Spooler.
    $pastaSpool = Join-Path $env:SystemRoot 'System32\spool\PRINTERS'
    if (-not (Test-Path $pastaSpool)) {
        return @{ Status = 'NaoEncontrado'; Detalhe = 'pasta de spool nao existe'; BytesLiberados = 0 }
    }
    $antesBytes = Get-TamanhoPasta -Caminho $pastaSpool
    if ($antesBytes -eq 0) {
        return @{ Status = 'Ok'; Detalhe = 'fila ja estava vazia'; BytesLiberados = 0 }
    }

    $servico = Get-Service -Name 'Spooler' -ErrorAction SilentlyContinue
    $estavaRodando = $servico -and $servico.Status -eq 'Running'
    try {
        if ($estavaRodando) { Stop-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue }
        Get-ChildItem -Path $pastaSpool -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    finally {
        if ($estavaRodando) { Start-Service -Name 'Spooler' -ErrorAction SilentlyContinue }
    }

    $depoisBytes = Get-TamanhoPasta -Caminho $pastaSpool
    $liberado = $antesBytes - $depoisBytes
    if ($depoisBytes -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('fila destravada, liberado ~{0}' -f (Get-TamanhoLegivel $liberado)); BytesLiberados = $liberado }
    }
    return @{ Status = 'Parcial'; Detalhe = ('liberado ~{0}, {1} restante (job em uso)' -f (Get-TamanhoLegivel $liberado), (Get-TamanhoLegivel $depoisBytes)); BytesLiberados = $liberado }
}

function Clear-Lixeira {
    # BytesLiberados fica $null de proposito: medir o tamanho real da Lixeira exigiria
    # enumerar via COM (Shell.Application) em vez de Get-ChildItem simples, complexidade
    # que nao se paga so para um numero informativo no relatorio.
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        return @{ Status = 'Ok'; Detalhe = 'lixeira esvaziada'; BytesLiberados = $null }
    }
    catch {
        # Algumas versoes do Windows retornam erro quando a Lixeira ja esta vazia —
        # nao ha um tipo de excecao unico e documentado para esse caso, entao
        # tratamos pela mensagem em vez de assumir uma classe especifica.
        if ($_.Exception.Message -match 'empty|vazia|vazio') {
            return @{ Status = 'Ok'; Detalhe = 'ja estava vazia'; BytesLiberados = 0 }
        }
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message; BytesLiberados = $null }
    }
}

function Get-AcaoDescricao {
    param([Parameter(Mandatory)]$Item)
    switch ($Item.Tipo) {
        'LimpezaPasta' { 'limparia {0}' -f $Item.Alvo }
        'Especial' {
            switch ($Item.Alvo) {
                'CacheChrome'         { 'limparia o cache do Chrome em todos os perfis' }
                'CacheEdge'           { 'limparia o cache do Edge em todos os perfis' }
                'CacheFirefox'        { 'limparia o cache do Firefox em todos os perfis' }
                'CacheWindowsUpdate'  { 'pararia wuauserv/bits/cryptsvc, limparia SoftwareDistribution\Download e reiniciaria os servicos' }
                'DismCleanup'         { 'rodaria DISM /StartComponentCleanup (sem /ResetBase)' }
                'PatchCache'          { 'limparia C:\Windows\Installer\$PatchCache$' }
                'RecycleBin'          { 'esvaziaria a Lixeira (irreversivel)' }
                'FilaImpressao'       { 'pararia o Spooler, limparia System32\spool\PRINTERS e reiniciaria o Spooler' }
            }
        }
    }
}

function Invoke-ItemCatalogo {
    param([Parameter(Mandatory)]$Item)

    if ($script:Simular) {
        return @{ Status = 'Simulado'; Detalhe = (Get-AcaoDescricao -Item $Item); BytesLiberados = $null }
    }
    switch ($Item.Tipo) {
        'LimpezaPasta' { return Clear-PastaComRelatorio -Item $Item }
        'Especial' {
            switch ($Item.Alvo) {
                'CacheChrome'        { return Clear-CacheChrome }
                'CacheEdge'          { return Clear-CacheEdge }
                'CacheFirefox'       { return Clear-CacheFirefox }
                'CacheWindowsUpdate' { return Clear-CacheWindowsUpdate }
                'DismCleanup'        { return Invoke-DismCleanup }
                'PatchCache'         { return Clear-PatchCache }
                'RecycleBin'         { return Clear-Lixeira }
                'FilaImpressao'      { return Clear-FilaImpressao }
            }
        }
    }
    return @{ Status = 'Falha'; Detalhe = ('tipo de item desconhecido: {0}' -f $Item.Tipo); BytesLiberados = $null }
}

function Invoke-Selecao {
    param([Parameter(Mandatory)][object[]]$Itens)

    if ($script:Simular) {
        Write-Log 'Iniciando SIMULACAO (nada sera alterado)...' 'Titulo'
    }
    else {
        Write-Log 'Iniciando execucao...' 'Titulo'
    }

    $contagem = @{ Ok = 0; Parcial = 0; NaoEncontrado = 0; Falha = 0; Simulado = 0 }
    # Relatorio antes/depois: cada item processado entra aqui com o resultado
    # detalhado (nao so a contagem agregada), para exportacao em JSON.
    $detalhes = [System.Collections.Generic.List[object]]::new()
    $total = $Itens.Count
    $indice = 0
    foreach ($item in $Itens) {
        $indice++
        $prefixo = '[{0,2}/{1}]' -f $indice, $total
        $resultado = Invoke-ItemCatalogo -Item $item
        $contagem[$resultado.Status]++
        $detalhes.Add([pscustomobject]@{
            Id             = $item.Id
            Categoria      = $item.Categoria
            Descricao      = $item.Descricao
            Nivel          = $item.Nivel
            Status         = $resultado.Status
            Detalhe        = $resultado.Detalhe
            BytesLiberados = $resultado.BytesLiberados
        })
        $linha = '{0} {1}: {2}' -f $prefixo, $item.Descricao, $resultado.Detalhe
        switch ($resultado.Status) {
            'Ok'            { Write-Log $linha 'Ok' }
            'Parcial'       { Write-Log $linha 'Aviso' }
            'NaoEncontrado' { Write-Log ('{0} {1}: nao encontrado neste sistema — nada a fazer' -f $prefixo, $item.Descricao) 'Info' }
            'Falha'         { Write-Log $linha 'Erro' }
            'Simulado'      { Write-Log $linha 'Simulacao' }
        }
    }

    Write-Log '--------------------------------------------------------------' 'Info'
    if ($script:Simular) {
        Write-Log ('Simulacao concluida: {0} acao(oes) seriam executadas.' -f $contagem.Simulado) 'Simulacao'
    }
    else {
        Write-Log ('Concluido: {0} ok, {1} parcial(is), {2} nao encontrado(s), {3} falha(s).' -f $contagem.Ok, $contagem.Parcial, $contagem.NaoEncontrado, $contagem.Falha) 'Titulo'
    }
    return @{ Contagem = $contagem; Detalhes = $detalhes }
}

function Export-RelatorioJson {
    param(
        [Parameter(Mandatory)][string]$Caminho,
        [Parameter(Mandatory)][object[]]$Detalhes,
        [Parameter(Mandatory)][hashtable]$Contagem
    )
    $totalBytes = ($Detalhes | Where-Object { $null -ne $_.BytesLiberados } | Measure-Object -Property BytesLiberados -Sum).Sum
    if (-not $totalBytes) { $totalBytes = 0 }

    $relatorio = [pscustomobject]@{
        SchemaVersion          = 1
        Ferramenta             = 'CaixaDeFerramentasWindows'
        Modo                   = $Modo
        Versao                 = $script:VERSAO
        DataHora                = (Get-Date).ToString('o')
        VersaoWindowsDetectada = $script:VersaoWindowsDetectada
        Simulacao              = [bool]$script:Simular
        Contagem                = $Contagem
        TotalBytesLiberados    = $totalBytes
        Itens                   = $Detalhes
    }
    try {
        $pasta = Split-Path -Path $Caminho -Parent
        if ($pasta -and -not (Test-Path $pasta)) {
            New-Item -Path $pasta -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        # -Depth explicito sempre: o padrao do PS 5.1 e 2, e trunca aninhamento sem
        # aviso ("Itens" e uma lista de objetos, ja passaria dos 2 niveis).
        $relatorio | ConvertTo-Json -Depth 5 | Set-Content -Path $Caminho -Encoding UTF8 -ErrorAction Stop
        Write-Log ('Relatorio JSON salvo em: {0}' -f $Caminho) 'Info'
    }
    catch {
        Write-Log ('Nao foi possivel salvar o relatorio JSON: {0}' -f $_.Exception.Message) 'Aviso'
    }
}

#endregion

#region Menu do catalogo (Debloat/Faxina/Tudo) ------------------------------------

function Initialize-Selecao {
    param(
        [Parameter(Mandatory)][string]$NomePerfil,
        [Parameter(Mandatory)][string[]]$Categorias
    )
    $script:Selecionados = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in (Get-ItensDoPerfil -NomePerfil $NomePerfil -Categorias $Categorias)) {
        [void]$script:Selecionados.Add($item.Id)
    }
}

function Get-ContagemCategoria {
    param([Parameter(Mandatory)][string]$Categoria)
    $itens = @($script:Catalogo | Where-Object { $_.Categoria -eq $Categoria })
    $selecionados = @($itens | Where-Object { $script:Selecionados.Contains($_.Id) })
    @{ Selecionados = $selecionados.Count; Total = $itens.Count }
}

function Show-CategoryMenu {
    param([Parameter(Mandatory)][string]$Categoria)

    $itens = @($script:Catalogo | Where-Object { $_.Categoria -eq $Categoria })
    while ($true) {
        Clear-Host
        Write-Host '=============================================================='
        Write-Host (' CATEGORIA: {0}' -f $Categoria.ToUpper())
        Write-Host '=============================================================='
        for ($i = 0; $i -lt $itens.Count; $i++) {
            $item = $itens[$i]
            $marca = '[ ]'
            if ($script:Selecionados.Contains($item.Id)) { $marca = '[X]' }
            $sufixo = ''
            if ($item.Nivel -eq 'Opcional') { $sufixo = '  *opcional' }
            elseif ($item.Nivel -eq 'Agressivo') { $sufixo = '  *AGRESSIVO' }
            $linha = ' {0} {1,2}) {2,-58}{3}' -f $marca, ($i + 1), $item.Descricao, $sufixo
            if ($item.Nivel -eq 'Agressivo') { Write-Host $linha -ForegroundColor Yellow }
            else { Write-Host $linha }
        }
        Write-Host '--------------------------------------------------------------'
        Write-Host ' Digite o(s) numero(s) para marcar/desmarcar (ex.: 3 ou 1,4,7)'
        Write-Host ' T) Marcar todos    N) Desmarcar todos    V) Voltar'
        Write-Host '=============================================================='
        $opcao = (Read-Host 'Opcao').Trim().ToUpper()

        switch ($opcao) {
            'V' { return }
            'T' { foreach ($item in $itens) { [void]$script:Selecionados.Add($item.Id) } }
            'N' { foreach ($item in $itens) { [void]$script:Selecionados.Remove($item.Id) } }
            default {
                $numeros = $opcao -split '[,; ]+' | Where-Object { $_ -match '^\d+$' }
                foreach ($numero in $numeros) {
                    $posicao = [int]$numero - 1
                    if ($posicao -ge 0 -and $posicao -lt $itens.Count) {
                        $id = $itens[$posicao].Id
                        if ($script:Selecionados.Contains($id)) { [void]$script:Selecionados.Remove($id) }
                        else { [void]$script:Selecionados.Add($id) }
                    }
                }
            }
        }
    }
}

function Show-Confirmacao {
    param(
        [Parameter(Mandatory)][object[]]$Itens,
        [Parameter(Mandatory)][bool]$ComRestore
    )
    Clear-Host
    Write-Host '====================== RESUMO DA EXECUCAO ===================='
    Write-Host (' {0} item(ns) selecionado(s):' -f $Itens.Count)
    foreach ($categoria in $script:Categorias) {
        $porCategoria = @($Itens | Where-Object { $_.Categoria -eq $categoria })
        if ($porCategoria.Count -gt 0) {
            Write-Host ('   {0,-14} {1,2} item(ns)' -f ($categoria + ':'), $porCategoria.Count)
        }
    }
    $agressivos = @($Itens | Where-Object { $_.Nivel -eq 'Agressivo' })
    if ($agressivos.Count -gt 0) {
        Write-Host (' ATENCAO: {0} item(ns) AGRESSIVO(S) selecionado(s) — irreversiveis:' -f $agressivos.Count) -ForegroundColor Yellow
        foreach ($item in $agressivos) {
            Write-Host ('   - {0}' -f $item.Descricao) -ForegroundColor Yellow
        }
    }
    $textoRestore = 'NAO'
    if ($ComRestore) { $textoRestore = 'SIM' }
    $textoSimulacao = 'NAO'
    if ($script:Simular) { $textoSimulacao = 'SIM' }
    Write-Host (' Ponto de restauracao: {0}    Simulacao: {1}' -f $textoRestore, $textoSimulacao)
    if ($script:ArquivoLog) { Write-Host (' Log: {0}' -f $script:ArquivoLog) }
    Write-Host '--------------------------------------------------------------'
    Write-Host ' C) Confirmar e executar        V) Voltar ao menu'
    Write-Host '=============================================================='
    $opcao = (Read-Host 'Opcao').Trim().ToUpper()
    return ($opcao -eq 'C')
}

function Show-MainMenu {
    param(
        [Parameter(Mandatory)][string[]]$Categorias,
        [Parameter(Mandatory)][string]$TituloModo
    )
    $perfilAtual = $Perfil
    Initialize-Selecao -NomePerfil $perfilAtual -Categorias $Categorias
    $comRestore = -not $SemPontoRestauracao

    while ($true) {
        Clear-Host
        $textoSimulacao = 'NAO'
        if ($script:Simular) { $textoSimulacao = 'SIM' }
        Write-Host '=============================================================='
        Write-Host (' CAIXA DE FERRAMENTAS — {0} (v{1})      [SIMULACAO: {2}]' -f $TituloModo.ToUpper(), $script:VERSAO, $textoSimulacao)
        Write-Host (' Perfil base: {0}   |   Selecionados: {1} de {2} itens' -f $perfilAtual, $script:Selecionados.Count, ($script:Catalogo | Where-Object { $Categorias -contains $_.Categoria }).Count)
        Write-Host '=============================================================='
        for ($i = 0; $i -lt $Categorias.Count; $i++) {
            $contagem = Get-ContagemCategoria -Categoria $Categorias[$i]
            Write-Host ('  {0}) {1,-14} ({2,2} de {3,2} selecionados)' -f ($i + 1), $Categorias[$i], $contagem.Selecionados, $contagem.Total)
        }
        $textoRestore = 'NAO'
        if ($comRestore) { $textoRestore = 'SIM' }
        Write-Host '--------------------------------------------------------------'
        Write-Host ' P) Trocar perfil base (Minimo / Completo / Agressivo)'
        Write-Host (' R) Ponto de restauracao antes de executar: {0}' -f $textoRestore)
        Write-Host ' E) EXECUTAR selecao'
        Write-Host ' S) Sair sem executar'
        Write-Host '=============================================================='
        $opcao = (Read-Host 'Opcao').Trim().ToUpper()

        switch ($opcao) {
            'S' { return $null }
            'P' {
                $perfilAtual = switch ($perfilAtual) {
                    'Minimo'    { 'Completo' }
                    'Completo'  { 'Agressivo' }
                    'Agressivo' { 'Minimo' }
                }
                Initialize-Selecao -NomePerfil $perfilAtual -Categorias $Categorias
            }
            'R' { $comRestore = -not $comRestore }
            'E' {
                $itens = @($script:Catalogo | Where-Object { $script:Selecionados.Contains($_.Id) })
                if ($itens.Count -eq 0) {
                    Write-Log 'Nenhum item selecionado.' 'Aviso'
                    Start-Sleep -Seconds 2
                    continue
                }
                if (Show-Confirmacao -Itens $itens -ComRestore $comRestore) {
                    return @{ Itens = $itens; ComRestore = $comRestore }
                }
            }
            default {
                if ($opcao -match '^\d{1,2}$') {
                    $posicao = [int]$opcao - 1
                    if ($posicao -ge 0 -and $posicao -lt $Categorias.Count) {
                        Show-CategoryMenu -Categoria $Categorias[$posicao]
                    }
                }
            }
        }
    }
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
    { $_ -in @('Debloat', 'Tudo') } {
        Write-Log ("Modo '{0}' ainda sera implementado na Fase 3 deste projeto (fusao do catalogo Debloat10/11)." -f $Modo) 'Erro'
        exit 9
    }
    'Faxina' {
        Assert-Admin -ParametrosOriginais $PSBoundParameters
        $script:VersaoWindowsDetectada = Get-VersaoWindows
        Assert-VersaoSuportada -VersaoDetectada $script:VersaoWindowsDetectada
        Start-Logging -CaminhoPersonalizado $CaminhoLog -Prefixo 'faxina'

        Write-Log ('Modo Faxina — perfil "{0}"{1}' -f $Perfil, $(if ($NaoInterativo) { ' (nao interativo)' } else { '' })) 'Titulo'
        if ($script:ArquivoLog) { Write-Log ('Log: {0}' -f $script:ArquivoLog) 'Info' }
        if ($script:Simular) { Write-Log 'MODO SIMULACAO: nenhuma alteracao sera feita no sistema.' 'Simulacao' }

        $categoriasModo = $script:CategoriasPorModo['Faxina']
        $codigoSaida = 0
        try {
            if ($NaoInterativo) {
                $itensExecucao = @(Get-ItensDoPerfil -NomePerfil $Perfil -Categorias $categoriasModo)
                $fazRestore = -not $SemPontoRestauracao
            }
            else {
                $selecao = Show-MainMenu -Categorias $categoriasModo -TituloModo 'Modo Faxina'
                if (-not $selecao) {
                    Write-Log 'Nenhuma acao executada.' 'Info'
                    Stop-LoggingSeAtivo
                    exit 0
                }
                $itensExecucao = @($selecao.Itens)
                $fazRestore = $selecao.ComRestore
            }

            if ($fazRestore) {
                $restoreOk = New-RestorePoint
                if (-not $restoreOk -and -not $script:Simular) {
                    if ($NaoInterativo) {
                        Write-Log 'Prosseguindo sem ponto de restauracao (modo nao interativo).' 'Aviso'
                    }
                    else {
                        $resposta = Read-Host 'Continuar SEM ponto de restauracao? (S/N)'
                        if ($resposta -notmatch '^[sS]') {
                            Write-Log 'Execucao cancelada pelo usuario.' 'Info'
                            Stop-LoggingSeAtivo
                            exit 4
                        }
                    }
                }
            }
            elseif (-not $script:Simular) {
                Write-Log 'Ponto de restauracao desativado por opcao do usuario.' 'Aviso'
            }

            $resultado = Invoke-Selecao -Itens $itensExecucao
            if ($resultado.Contagem.Falha -gt 0) { $codigoSaida = 5 }
            if ($CaminhoRelatorioJson) {
                Export-RelatorioJson -Caminho $CaminhoRelatorioJson -Detalhes $resultado.Detalhes -Contagem $resultado.Contagem
            }
        }
        finally {
            Stop-LoggingSeAtivo
        }

        if (-not $NaoInterativo) {
            Read-Host 'Pressione ENTER para sair' | Out-Null
        }
        exit $codigoSaida
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
