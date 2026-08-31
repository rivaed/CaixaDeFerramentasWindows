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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Show-MenuFerramentas: nome decidido no plano aprovado da fusao (resolucao da colisao de Show-MainMenu — ver CLAUDE.md). "Ferramentas" aqui e a caixa de ferramentas inteira, nao uma colecao de objetos processados. A propria funcao nao tem param() pra hospedar um atributo de escopo mais estreito (SuppressMessageAttribute antes de "function" exige um param()/CmdletBinding logo em seguida, senao e erro de parse — confirmado ao tentar). A regra em si usa heuristica rasa (sufixo termina em "s"), nao analise semantica: outros nomes plurais em portugues no arquivo (Get-ItensRegistroRun etc.) so nao disparam porque o composto nao termina literalmente em "s".')]
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

    # ===== Fase 3: Debloat (fundido de Windows10-Debloat + Windows11-Debloat) =====
    # temp-usuario/temp-sistema do Debloat foram DESCARTADOS de proposito (colidiam
    # com os dois itens do WinFaxina acima) - ver CLAUDE.md, Bloqueio A.

    # --- Apps: identicos byte a byte nos dois scripts-fonte, sem SistemasAlvo ---
    [pscustomobject]@{ Id = 'bing-news';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.BingNews';                    Descricao = 'Noticias (Bing News)';           Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'bing-weather'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.BingWeather';                 Descricao = 'Clima (Bing Weather)';           Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'get-help';     Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.GetHelp';                     Descricao = 'Obter Ajuda';                    Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'solitaire';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.MicrosoftSolitaireCollection'; Descricao = 'Solitaire Collection';          Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'people';       Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.People';                      Descricao = 'Pessoas';                        Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'media-player'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.ZuneMusic';                   Descricao = 'Media Player (musica)';          Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'filmes-tv';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.ZuneVideo';                   Descricao = 'Filmes e TV';                    Nivel = 'Seguro' }
    [pscustomobject]@{ Id = 'xbox-overlay'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxGameOverlay';             Descricao = 'Xbox Game Overlay';              Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'xbox-gamebar'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxGamingOverlay';           Descricao = 'Xbox Game Bar';                  Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'xbox-speech';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxSpeechToTextOverlay';     Descricao = 'Xbox Speech-to-Text';            Nivel = 'Opcional' }
    [pscustomobject]@{ Id = 'store-purchase'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.StorePurchaseApp';         Descricao = 'Compras da Microsoft Store';      Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'xbox-identity';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxIdentityProvider';     Descricao = 'Login Xbox (Minecraft/Game Pass)'; Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'xbox-tcui';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Xbox.TCUI';                Descricao = 'Xbox TCUI (UI de conta Xbox)';    Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'widgets-pacote'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftWindows.Client.WebExperience'; Descricao = 'Widgets (remocao do pacote)';  Nivel = 'Agressivo' }
    [pscustomobject]@{ Id = 'onedrive';       Categoria = 'Apps'; Tipo = 'Especial'; Alvo = 'OneDrive';                       Descricao = 'OneDrive (desinstalacao)';        Nivel = 'Agressivo' }

    # --- Apps: exclusivos do Windows10-Debloat ---
    [pscustomobject]@{ Id = 'getstarted';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Getstarted';           Descricao = 'Dicas (Get Started)';   Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'alarmes';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.WindowsAlarms';        Descricao = 'Alarmes e Relogio';     Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'gravador-som'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.WindowsSoundRecorder'; Descricao = 'Gravador de Som';       Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'mapas';        Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.WindowsMaps';         Descricao = 'Mapas';                 Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'feedback-hub'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.WindowsFeedbackHub';  Descricao = 'Hub de Comentarios';    Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'office-lens';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Office.Lens';         Descricao = 'Office Lens';           Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'network-speed'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.NetworkSpeedTest';   Descricao = 'Teste de Velocidade de Rede'; Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'print3d';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Print3D';             Descricao = 'Print 3D';              Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'teams-chat';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftTeams';                Descricao = 'Teams (Chat, barra de tarefas — versao W10)'; Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'cortana';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.549981C3F5F10';       Descricao = 'Cortana (descontinuada)'; Nivel = 'Seguro'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'sticky-notes'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.MicrosoftStickyNotes'; Descricao = 'Notas Adesivas';        Nivel = 'Opcional'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'camera';       Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.WindowsCamera';       Descricao = 'Camera';                Nivel = 'Opcional'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'mail-calendario'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'microsoft.windowscommunicationsapps'; Descricao = 'Email e Calendario (Mail)'; Nivel = 'Opcional'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'onenote-app';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Office.OneNote';      Descricao = 'OneNote (app da Store)'; Nivel = 'Opcional'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'mixed-reality'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.MixedReality.Portal'; Descricao = 'Mixed Reality Portal (sem suporte apos 01/11/2026)'; Nivel = 'Opcional'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'xbox-app';     Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.XboxApp';             Descricao = 'Xbox (app antigo)';     Nivel = 'Opcional'; SistemasAlvo = @('Win10') }

    # --- Apps: exclusivos do Windows11-Debloat ---
    [pscustomobject]@{ Id = 'bing-search';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.BingSearch';                     Descricao = 'Bing Search (24H2)';       Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'office-hub';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.MicrosoftOfficeHub';              Descricao = 'Microsoft 365 (Office Hub)'; Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'todos';         Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Todos';                          Descricao = 'Microsoft To Do';          Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'clipchamp';     Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Clipchamp.Clipchamp';                      Descricao = 'Clipchamp (editor de video)'; Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'teams';         Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MSTeams';                                  Descricao = 'Microsoft Teams (pessoal)'; Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'outlook-novo';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.OutlookForWindows';              Descricao = 'Novo Outlook';             Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'power-automate'; Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.PowerAutomateDesktop';          Descricao = 'Power Automate';           Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'family';        Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftCorporationII.MicrosoftFamily';   Descricao = 'Microsoft Family';         Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'linkedin';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = '7EE7776C.LinkedInforWindows';              Descricao = 'LinkedIn';                 Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'dev-home';      Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Windows.DevHome';                Descricao = 'Dev Home (descontinuado)'; Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'copilot-app';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.Copilot';                        Descricao = 'Copilot (app)';            Nivel = 'Seguro'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'xbox-gaming';   Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.GamingApp';                      Descricao = 'Xbox (app atual)';         Nivel = 'Opcional'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'phone-link';    Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'Microsoft.YourPhone';                      Descricao = 'Phone Link (celular vinculado)'; Nivel = 'Opcional'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'cross-device';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftWindows.CrossDevice';             Descricao = 'Cross Device (par do Phone Link)'; Nivel = 'Opcional'; SistemasAlvo = @('Win11') }
    [pscustomobject]@{ Id = 'quick-assist';  Categoria = 'Apps'; Tipo = 'Appx'; Alvo = 'MicrosoftCorporationII.QuickAssist';       Descricao = 'Assistencia Rapida';       Nivel = 'Opcional'; SistemasAlvo = @('Win11') }

    # --- Telemetria: identicos nos dois scripts-fonte, sem SistemasAlvo ---
    [pscustomobject]@{ Id = 'diagtrack'; Categoria = 'Telemetria'; Tipo = 'Servico'; Alvo = 'DiagTrack'; Descricao = 'Servico de telemetria (DiagTrack)'; Nivel = 'Seguro' }
    [pscustomobject]@{
        Id = 'telemetria-registro'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'Telemetria no minimo (politica de registro)'; Nivel = 'Seguro'
        Valores = @(
            # AllowTelemetry=1 (Basico): 0 so e honrado em Enterprise/Education/IoT Enterprise.
            @{ Caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Nome = 'AllowTelemetry';                 Valor = 1; Tipo = 'DWord' }
            @{ Caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Nome = 'DoNotShowFeedbackNotifications'; Valor = 1; Tipo = 'DWord' }
            @{ Caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Nome = 'LimitDiagnosticLogCollection';   Valor = 1; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'tarefas-telemetria'; Categoria = 'Telemetria'; Tipo = 'TarefaAgendada'
        Descricao = 'Tarefas agendadas de telemetria (CEIP)'; Nivel = 'Seguro'
        Alvos = @(
            @{ Caminho = '\Microsoft\Windows\Application Experience\';                   Nome = 'Microsoft Compatibility Appraiser' }
            @{ Caminho = '\Microsoft\Windows\Application Experience\';                   Nome = 'ProgramDataUpdater' }
            @{ Caminho = '\Microsoft\Windows\Customer Experience Improvement Program\';  Nome = 'Consolidator' }
            @{ Caminho = '\Microsoft\Windows\Customer Experience Improvement Program\';  Nome = 'UsbCeip' }
            @{ Caminho = '\Microsoft\Windows\Autochk\';                                  Nome = 'Proxy' }
            @{ Caminho = '\Microsoft\Windows\DiskDiagnostic\';                           Nome = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
        )
    }
    [pscustomobject]@{
        Id = 'advertising-id'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'ID de publicidade (anuncios personalizados)'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Nome = 'Enabled'; Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        # Valores identicos nos dois scripts-fonte; Descricao mais precisa (a do W10,
        # que fala especificamente da CAIXA DE BUSCA, que e o que DisableSearchBoxSuggestions
        # de fato controla) venceu o drift de copia entre os dois repos.
        Id = 'bing-iniciar'; Categoria = 'Telemetria'; Tipo = 'Registro'
        Descricao = 'Bing/sugestoes web fora da busca do menu Iniciar'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Nome = 'DisableSearchBoxSuggestions'; Valor = 1; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{ Id = 'dmwappush'; Categoria = 'Telemetria'; Tipo = 'Servico'; Alvo = 'dmwappushservice'; Descricao = 'WAP Push (quebra MDM/Intune)'; Nivel = 'Opcional' }

    # --- Telemetria: cdm dividido em dois itens - o NOME do valor de registro
    # difere de verdade entre W10 e W11 (nao e so drift de copia); os outros 9
    # valores sao identicos nos dois e ficam duplicados nos dois itens de proposito
    # (SistemasAlvo garante que so o correto para o SO detectado e oferecido).
    [pscustomobject]@{
        Id = 'cdm-w10'; Categoria = 'Telemetria'; Tipo = 'Registro'; SistemasAlvo = @('Win10')
        Descricao = 'Apps promovidos/sugestoes (Content Delivery) — Windows 10'; Nivel = 'Seguro'
        Valores = @(
            # Sem isso, o Windows reinstala apps promovidos e o debloat "se desfaz" sozinho.
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'ContentDeliveryAllowed';           Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SilentInstalledAppsEnabled';       Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'OemPreInstalledAppsEnabled';       Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'PreInstalledAppsEnabled';          Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SystemPaneSuggestionsEnabled';     Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'RotatingLockScreenOverlayEnabled'; Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-338388Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-338389Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-353694Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-310093Enabled';  Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'cdm-w11'; Categoria = 'Telemetria'; Tipo = 'Registro'; SistemasAlvo = @('Win11')
        Descricao = 'Apps promovidos/sugestoes (Content Delivery) — Windows 11'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'ContentDeliveryAllowed';           Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SilentInstalledAppsEnabled';       Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'OemPreInstalledAppsEnabled';       Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'PreInstalledAppsEnabled';          Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SystemPaneSuggestionsEnabled';     Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'RotatingLockScreenOverlayEnabled'; Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-338388Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-338389Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-353694Enabled';  Valor = 0; Tipo = 'DWord' }
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Nome = 'SubscribedContent-353696Enabled';  Valor = 0; Tipo = 'DWord' }
        )
    }

    # --- Telemetria: exclusivos de um dos dois scripts-fonte ---
    [pscustomobject]@{
        Id = 'cortana-politica'; Categoria = 'Telemetria'; Tipo = 'Registro'; SistemasAlvo = @('Win10')
        Descricao = 'Politica: desativar Cortana na busca'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Nome = 'AllowCortana'; Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'copilot-politica'; Categoria = 'Telemetria'; Tipo = 'Registro'; SistemasAlvo = @('Win11')
        Descricao = 'Politica: desativar integracao Copilot'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Nome = 'TurnOffWindowsCopilot'; Valor = 1; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{ Id = 'recall'; Categoria = 'Telemetria'; Tipo = 'Especial'; Alvo = 'Recall'; Descricao = 'Recall (snapshots de tela, Copilot+)'; Nivel = 'Opcional'; SistemasAlvo = @('Win11') }

    # --- Desempenho: identicos nos dois scripts-fonte, sem SistemasAlvo ---
    [pscustomobject]@{ Id = 'efeitos-visuais'; Categoria = 'Desempenho'; Tipo = 'Especial'; Alvo = 'EfeitosVisuais'; Descricao = 'Efeitos visuais: melhor desempenho'; Nivel = 'Seguro' }
    [pscustomobject]@{
        # Descricao com "(se presente)" (a do W10) venceu — a presenca do botao
        # Widgets varia por atualizacao em AMBAS as versoes, nao so na 11.
        Id = 'widgets-botao'; Categoria = 'Desempenho'; Tipo = 'Registro'
        Descricao = 'Ocultar botao de Widgets da barra (se presente)'; Nivel = 'Seguro'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'TaskbarDa'; Valor = 0; Tipo = 'DWord' }
        )
    }
    [pscustomobject]@{
        Id = 'extensoes-arquivo'; Categoria = 'Desempenho'; Tipo = 'Registro'
        Descricao = 'Mostrar extensoes de arquivo'; Nivel = 'Opcional'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Nome = 'HideFileExt'; Valor = 0; Tipo = 'DWord' }
        )
    }

    # --- Desempenho: exclusivos do Windows10-Debloat ---
    [pscustomobject]@{ Id = 'fax';          Categoria = 'Desempenho'; Tipo = 'Servico'; Alvo = 'Fax';           Descricao = 'Servico de Fax e Digitalizacao'; Nivel = 'Seguro';   SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'wsearch';      Categoria = 'Desempenho'; Tipo = 'Servico'; Alvo = 'WSearch';       Descricao = 'Indexacao de busca (Windows Search)'; Nivel = 'Opcional'; SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'sysmain';      Categoria = 'Desempenho'; Tipo = 'Servico'; Alvo = 'SysMain';       Descricao = 'Superfetch/Prefetch (SysMain)'; Nivel = 'Opcional';  SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'xbl-gamesave'; Categoria = 'Desempenho'; Tipo = 'Servico'; Alvo = 'XblGameSave';   Descricao = 'Xbox Live Game Save'; Nivel = 'Opcional';             SistemasAlvo = @('Win10') }
    [pscustomobject]@{ Id = 'xbox-netapi';  Categoria = 'Desempenho'; Tipo = 'Servico'; Alvo = 'XboxNetApiSvc'; Descricao = 'Xbox Live Networking Service'; Nivel = 'Opcional';    SistemasAlvo = @('Win10') }

    # --- Desempenho: exclusivo do Windows11-Debloat (menu de contexto classico so
    # existe pra reverter porque so o W11 mudou essa UX; W10 nao tem o que reverter) ---
    [pscustomobject]@{
        Id = 'menu-contexto'; Categoria = 'Desempenho'; Tipo = 'Registro'; SistemasAlvo = @('Win11')
        Descricao = 'Menu de contexto classico (muda a UX padrao)'; Nivel = 'Agressivo'
        Valores = @(
            @{ Caminho = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Nome = '(default)'; Valor = ''; Tipo = 'String' }
        )
    }
)

# Ordem canonica das 7 categorias do esquema fundido (ver CLAUDE.md). Usada para
# exibicao (ex.: resumo em Show-Confirmacao); a lista que efetivamente aparece no
# menu/participa da selecao por perfil e sempre a filtrada por -Modo, abaixo.
$script:Categorias = @('Apps', 'Telemetria', 'Desempenho', 'Temporarios', 'Navegadores', 'Sistema', 'Lixeira')

# "Um motor so; Modo so pre-filtra Categorias" (decisao do plano).
# Sistema fica exclusivo de Faxina - confirmado direto no codigo-fonte (Fase 3) que
# nem Windows10-Debloat nem Windows11-Debloat jamais tiveram uma categoria "Sistema"
# (so Apps|Telemetria|Desempenho|Limpeza); a versao anterior desta lista incluia
# 'Sistema' aqui por suposicao, antes de ler os scripts-fonte - isso teria feito
# -Modo Debloat tambem rodar DISM/patch-cache/spooler do WinFaxina, que nao e o
# esperado (quem quer isso usa -Modo Faxina ou -Modo Tudo).
$script:CategoriasPorModo = @{
    Faxina  = @('Temporarios', 'Navegadores', 'Sistema', 'Lixeira')
    Debloat = @('Apps', 'Telemetria', 'Desempenho')
    Tudo    = $script:Categorias
}

function Test-ItemAplicavelAoSO {
    # SistemasAlvo ausente/$null = item vale para qualquer SO (WinFaxina inteiro e a
    # maior parte do Debloat fundido). Quando presente, o item so vale se o SO
    # detectado estiver na lista - NUNCA array vazio (ver Catalogo.Tests.ps1).
    # Fica em funcao propria (nao inline no Where-Object) porque e repetida em 4
    # lugares (Get-ItensDoPerfil, Get-ContagemCategoria, Show-CategoryMenu e aqui
    # mesmo) - um so ponto pra essa regra, nao 4 copias do mesmo -or.
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$VersaoWindows
    )
    -not $Item.SistemasAlvo -or $Item.SistemasAlvo -contains $VersaoWindows
}

function Get-ItensDoPerfil {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Minimo', 'Completo', 'Agressivo')]
        [string]$NomePerfil,
        [Parameter(Mandatory)][string[]]$Categorias,
        [Parameter(Mandatory)][string]$VersaoWindows
    )
    $niveis = switch ($NomePerfil) {
        'Minimo'    { @('Seguro') }
        'Completo'  { @('Seguro', 'Opcional') }
        'Agressivo' { @('Seguro', 'Opcional', 'Agressivo') }
    }
    $script:Catalogo | Where-Object {
        $niveis -contains $_.Nivel -and
        $Categorias -contains $_.Categoria -and
        (Test-ItemAplicavelAoSO -Item $_ -VersaoWindows $VersaoWindows)
    }
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

function Get-InventarioAppx {
    Write-Log 'Inventariando pacotes instalados e provisionados (pode levar alguns segundos)...' 'Info'
    # Enumeracoes feitas UMA vez (Get-AppxProvisionedPackage e uma operacao DISM lenta).
    $script:PacotesInstalados = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $script:PacotesProvisionados = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
}

function Remove-BloatApp {
    param([Parameter(Mandatory)]$Item)

    # Matching EXATO por nome de pacote (curingas removiam pacotes alem do pretendido).
    $provisionados = @($script:PacotesProvisionados | Where-Object { $_.DisplayName -eq $Item.Alvo })
    $instalados = @($script:PacotesInstalados | Where-Object { $_.Name -eq $Item.Alvo })

    if ($provisionados.Count -eq 0 -and $instalados.Count -eq 0) {
        return @{ Status = 'NaoEncontrado'; Detalhe = ('pacote "{0}" nao esta presente' -f $Item.Alvo) }
    }

    $okProv = 0; $okInst = 0
    $falhas = @()

    # Desprovisiona PRIMEIRO: se so a remocao por usuario falhar, o app nao volta
    # para novas contas criadas na maquina.
    foreach ($pacote in $provisionados) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pacote.PackageName -ErrorAction Stop | Out-Null
            $okProv++
        }
        catch {
            $falhas += ('desprovisionar {0}: {1}' -f $pacote.PackageName, $_.Exception.Message)
        }
    }
    foreach ($pacote in $instalados) {
        try {
            Remove-AppxPackage -Package $pacote.PackageFullName -AllUsers -ErrorAction Stop
            $okInst++
        }
        catch {
            $falhas += ('remover {0}: {1}' -f $pacote.PackageFullName, $_.Exception.Message)
        }
    }

    $partes = @()
    if ($okInst -gt 0) { $partes += ('{0} instalado(s) removido(s)' -f $okInst) }
    if ($okProv -gt 0) { $partes += ('{0} provisionado(s) removido(s)' -f $okProv) }
    $resumo = $partes -join ', '

    if ($falhas.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = $resumo }
    }
    if ($okInst -gt 0 -or $okProv -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('{0}; falhas: {1}' -f $resumo, ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Disable-BloatService {
    param([Parameter(Mandatory)]$Item)

    $servico = Get-Service -Name $Item.Alvo -ErrorAction SilentlyContinue
    if (-not $servico) {
        return @{ Status = 'NaoEncontrado'; Detalhe = ('servico "{0}" nao existe neste sistema' -f $Item.Alvo) }
    }
    try {
        Stop-Service -Name $Item.Alvo -Force -ErrorAction SilentlyContinue
        Set-Service -Name $Item.Alvo -StartupType Disabled -ErrorAction Stop
        return @{ Status = 'Ok'; Detalhe = 'parado e desativado' }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = ('nao foi possivel desativar (servico protegido ou acesso negado): {0}' -f $_.Exception.Message) }
    }
}

function Set-RegistryTweak {
    param([Parameter(Mandatory)]$Item)

    $ok = 0
    $falhas = @()
    foreach ($valor in $Item.Valores) {
        try {
            if (-not (Test-Path -Path $valor.Caminho)) {
                New-Item -Path $valor.Caminho -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $valor.Caminho -Name $valor.Nome -Value $valor.Valor -Type $valor.Tipo -ErrorAction Stop
            $ok++
        }
        catch {
            $falhas += ('{0}\{1}: {2}' -f $valor.Caminho, $valor.Nome, $_.Exception.Message)
        }
    }

    if ($falhas.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('{0} valor(es) de registro aplicado(s)' -f $ok) }
    }
    if ($ok -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('{0} aplicado(s); falhas: {1}' -f $ok, ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Disable-BloatScheduledTask {
    param([Parameter(Mandatory)]$Item)

    $ok = 0; $ausentes = 0
    $falhas = @()
    foreach ($alvo in $Item.Alvos) {
        $tarefa = Get-ScheduledTask -TaskPath $alvo.Caminho -TaskName $alvo.Nome -ErrorAction SilentlyContinue
        if (-not $tarefa) {
            $ausentes++
            continue
        }
        try {
            $tarefa | Disable-ScheduledTask -ErrorAction Stop | Out-Null
            $ok++
        }
        catch {
            $falhas += ('{0}{1}: {2}' -f $alvo.Caminho, $alvo.Nome, $_.Exception.Message)
        }
    }

    $resumo = ('{0} desativada(s), {1} inexistente(s) neste build' -f $ok, $ausentes)
    if ($falhas.Count -eq 0) {
        if ($ok -eq 0 -and $ausentes -gt 0) {
            return @{ Status = 'NaoEncontrado'; Detalhe = $resumo }
        }
        return @{ Status = 'Ok'; Detalhe = $resumo }
    }
    if ($ok -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('{0}; falhas: {1}' -f $resumo, ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Invoke-BroadcastSettingChange {
    # Notifica o sistema (WM_SETTINGCHANGE) para aplicar ajustes de aparencia sem reiniciar.
    if (-not ('Win32.NativeMethods' -as [type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $resultado = [UIntPtr]::Zero
    # HWND_BROADCAST = 0xffff, WM_SETTINGCHANGE = 0x001A, SMTO_ABORTIFHUNG = 0x0002
    [void][Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'WindowMetrics', 0x0002, 5000, [ref]$resultado)
    [void][Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, $null, 0x0002, 5000, [ref]$resultado)
}

function Set-VisualEffectsPerformance {
    # Aplica de fato o perfil de desempenho: VisualFXSetting sozinho so muda o botao
    # de radio do dialogo "Opcoes de Desempenho", sem alterar nenhum efeito real.
    try {
        $fx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        if (-not (Test-Path $fx)) { New-Item -Path $fx -Force | Out-Null }
        # 3 = Personalizado: melhor desempenho mantendo a suavizacao de fontes (legibilidade).
        Set-ItemProperty -Path $fx -Name 'VisualFXSetting' -Value 3 -Type DWord -ErrorAction Stop

        # Mascara de "melhor desempenho" com o bit de suavizacao de fontes ligado (byte 5 = 0x12).
        $mascara = [byte[]](0x90, 0x12, 0x03, 0x80, 0x12, 0x00, 0x00, 0x00)
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value $mascara -Type Binary -ErrorAction Stop
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '0' -Type String -ErrorAction Stop
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'FontSmoothing' -Value '2' -Type String -ErrorAction Stop
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String -ErrorAction Stop

        $avancado = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Set-ItemProperty -Path $avancado -Name 'TaskbarAnimations' -Value 0 -Type DWord -ErrorAction Stop
        Set-ItemProperty -Path $avancado -Name 'ListviewAlphaSelect' -Value 0 -Type DWord -ErrorAction Stop
        Set-ItemProperty -Path $avancado -Name 'ListviewShadow' -Value 0 -Type DWord -ErrorAction Stop

        $dwm = 'HKCU:\Software\Microsoft\Windows\DWM'
        if (-not (Test-Path $dwm)) { New-Item -Path $dwm -Force | Out-Null }
        Set-ItemProperty -Path $dwm -Name 'EnableAeroPeek' -Value 0 -Type DWord -ErrorAction Stop

        Invoke-BroadcastSettingChange
        return @{ Status = 'Ok'; Detalhe = 'perfil de desempenho aplicado (efeito completo no proximo logon)' }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message }
    }
}

function Remove-OneDriveApp {
    # OneDrive nao e Appx: usa o desinstalador nativo.
    Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue

    $candidatos = @(
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\Update\OneDriveSetup.exe')
    )
    $instaladorMaquina = Join-Path $env:ProgramFiles 'Microsoft OneDrive'
    if (Test-Path $instaladorMaquina) {
        $achado = Get-ChildItem -Path $instaladorMaquina -Filter 'OneDriveSetup.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($achado) { $candidatos = @($achado.FullName) + $candidatos }
    }

    $setup = $candidatos | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $setup) {
        return @{ Status = 'NaoEncontrado'; Detalhe = 'instalador do OneDrive nao encontrado (ja removido?)' }
    }
    try {
        Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -ErrorAction Stop
        return @{ Status = 'Ok'; Detalhe = ('desinstalador executado ({0})' -f $setup) }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message }
    }
}

function Disable-RecallFeature {
    # So se aplica a Windows 11 Copilot+ (hardware especifico) - o recurso opcional
    # nao existir no hardware/edicao atual e o resultado ESPERADO na maioria das
    # maquinas, nao uma falha. A politica de registro (DisableAIDataAnalysis) e
    # aplicada sempre, independente do recurso opcional existir ou nao.
    $ok = 0
    $falhas = @()
    foreach ($raiz in @('HKCU:\Software\Policies\Microsoft\Windows\WindowsAI', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI')) {
        try {
            if (-not (Test-Path $raiz)) { New-Item -Path $raiz -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $raiz -Name 'DisableAIDataAnalysis' -Value 1 -Type DWord -ErrorAction Stop
            $ok++
        }
        catch {
            $falhas += ('{0}: {1}' -f $raiz, $_.Exception.Message)
        }
    }

    $detalheFeature = 'recurso opcional "Recall" nao existe neste hardware'
    try {
        $recurso = Get-WindowsOptionalFeature -Online -FeatureName 'Recall' -ErrorAction SilentlyContinue
        if ($recurso -and $recurso.State -eq 'Enabled') {
            Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -NoRestart -ErrorAction Stop | Out-Null
            $detalheFeature = 'recurso opcional "Recall" desabilitado (requer reinicio)'
        }
        elseif ($recurso) {
            $detalheFeature = 'recurso opcional "Recall" ja estava desabilitado'
        }
    }
    catch {
        $falhas += ('recurso Recall: {0}' -f $_.Exception.Message)
    }

    if ($falhas.Count -eq 0) {
        return @{ Status = 'Ok'; Detalhe = ('politica aplicada; {0}' -f $detalheFeature) }
    }
    if ($ok -gt 0) {
        return @{ Status = 'Parcial'; Detalhe = ('politica parcial; falhas: {0}' -f ($falhas -join ' | ')) }
    }
    return @{ Status = 'Falha'; Detalhe = ($falhas -join ' | ') }
}

function Test-UsuarioDivergente {
    # Cenario classico de manutencao: usuario padrao logado + credencial de admin no UAC.
    # Nesse caso HKCU e %TEMP% deste processo pertencem ao ADMIN, nao ao usuario atendido.
    # Promovida para rodar em TODOS os modos que elevam (nao so Debloat, origem
    # original) - o mesmo risco vale igual pro WinFaxina, que hoje mexe em HKCU/%TEMP%.
    try {
        $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
            Select-Object -First 1
        if (-not $explorer) { return $false }
        $dono = (Invoke-CimMethod -InputObject $explorer -MethodName GetOwner -ErrorAction Stop).User
        if ($dono -and $dono -ne $env:USERNAME) {
            Write-Log ('Atencao: a sessao interativa e do usuario "{0}", mas o script roda como "{1}".' -f $dono, $env:USERNAME) 'Aviso'
            Write-Log ('Ajustes por usuario (HKCU) e a limpeza de %TEMP% serao aplicados ao perfil de "{0}". Veja "Limitacoes" no README.' -f $env:USERNAME) 'Aviso'
            return $true
        }
    }
    catch {
        # Sem explorer.exe (sessao SYSTEM/RMM) ou sem WMI: segue sem o aviso.
        Write-Verbose ('Nao foi possivel determinar o usuario da sessao interativa: {0}' -f $_.Exception.Message)
    }
    return $false
}

function Get-AcaoDescricao {
    param([Parameter(Mandatory)]$Item)
    switch ($Item.Tipo) {
        'Appx'           { 'removeria o pacote {0} (instalado e provisionado)' -f $Item.Alvo }
        'Servico'        { 'pararia e desativaria o servico {0}' -f $Item.Alvo }
        'Registro'       { 'aplicaria {0} valor(es) de registro' -f @($Item.Valores).Count }
        'TarefaAgendada' { 'desativaria {0} tarefa(s) agendada(s)' -f @($Item.Alvos).Count }
        'LimpezaPasta'   { 'limparia {0}' -f $Item.Alvo }
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
                'EfeitosVisuais'      { 'aplicaria o perfil de desempenho (efeitos visuais)' }
                'OneDrive'            { 'rodaria o desinstalador nativo do OneDrive' }
                'Recall'              { 'aplicaria a politica DisableAIDataAnalysis e desabilitaria o recurso opcional Recall, se presente' }
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
        'Appx'           { return Remove-BloatApp -Item $Item }
        'Servico'        { return Disable-BloatService -Item $Item }
        'Registro'       { return Set-RegistryTweak -Item $Item }
        'TarefaAgendada' { return Disable-BloatScheduledTask -Item $Item }
        'LimpezaPasta'   { return Clear-PastaComRelatorio -Item $Item }
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
                'EfeitosVisuais'     { return Set-VisualEffectsPerformance }
                'OneDrive'           { return Remove-OneDriveApp }
                'Recall'             { return Disable-RecallFeature }
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

    # Pre-requisito de Remove-BloatApp (Tipo=Appx): inventariar pacotes UMA vez antes
    # do loop, nao por item. Fica aqui (no motor compartilhado), nao em cada chamador,
    # para nenhum modo futuro com itens Appx esquecer de preparar isso.
    $temAppx = @($Itens | Where-Object { $_.Tipo -eq 'Appx' }).Count -gt 0
    if ($temAppx -and -not $script:Simular) {
        Get-InventarioAppx
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
            Tipo           = $item.Tipo
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
        [Parameter(Mandatory)][string[]]$Categorias,
        [Parameter(Mandatory)][string]$VersaoWindows
    )
    $script:Selecionados = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($item in (Get-ItensDoPerfil -NomePerfil $NomePerfil -Categorias $Categorias -VersaoWindows $VersaoWindows)) {
        [void]$script:Selecionados.Add($item.Id)
    }
}

function Get-ContagemCategoria {
    param(
        [Parameter(Mandatory)][string]$Categoria,
        [Parameter(Mandatory)][string]$VersaoWindows
    )
    $itens = @($script:Catalogo | Where-Object { $_.Categoria -eq $Categoria -and (Test-ItemAplicavelAoSO -Item $_ -VersaoWindows $VersaoWindows) })
    $selecionados = @($itens | Where-Object { $script:Selecionados.Contains($_.Id) })
    @{ Selecionados = $selecionados.Count; Total = $itens.Count }
}

function Show-CategoryMenu {
    param(
        [Parameter(Mandatory)][string]$Categoria,
        [Parameter(Mandatory)][string]$VersaoWindows
    )

    $itens = @($script:Catalogo | Where-Object { $_.Categoria -eq $Categoria -and (Test-ItemAplicavelAoSO -Item $_ -VersaoWindows $VersaoWindows) })
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
        [Parameter(Mandatory)][string]$TituloModo,
        [Parameter(Mandatory)][string]$VersaoWindows
    )
    $perfilAtual = $Perfil
    Initialize-Selecao -NomePerfil $perfilAtual -Categorias $Categorias -VersaoWindows $VersaoWindows
    $comRestore = -not $SemPontoRestauracao
    $totalAplicavel = @($script:Catalogo | Where-Object { $Categorias -contains $_.Categoria -and (Test-ItemAplicavelAoSO -Item $_ -VersaoWindows $VersaoWindows) }).Count

    while ($true) {
        Clear-Host
        $textoSimulacao = 'NAO'
        if ($script:Simular) { $textoSimulacao = 'SIM' }
        Write-Host '=============================================================='
        Write-Host (' CAIXA DE FERRAMENTAS — {0} (v{1})      [SIMULACAO: {2}]' -f $TituloModo.ToUpper(), $script:VERSAO, $textoSimulacao)
        Write-Host (' Perfil base: {0}   |   Selecionados: {1} de {2} itens' -f $perfilAtual, $script:Selecionados.Count, $totalAplicavel)
        Write-Host '=============================================================='
        for ($i = 0; $i -lt $Categorias.Count; $i++) {
            $contagem = Get-ContagemCategoria -Categoria $Categorias[$i] -VersaoWindows $VersaoWindows
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
                Initialize-Selecao -NomePerfil $perfilAtual -Categorias $Categorias -VersaoWindows $VersaoWindows
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
                        Show-CategoryMenu -Categoria $Categorias[$posicao] -VersaoWindows $VersaoWindows
                    }
                }
            }
        }
    }
}

#endregion

#region Diagnostico (Grupo B — DiagnosticoRapidoDePC) -----------------------------
# Familia "Relatorio somente-leitura": nunca eleva (System/Application sao legiveis
# por usuario padrao; so Security exigiria admin, e nenhuma verificacao usa Security),
# nunca chama Start-Logging/transcript - preserva o comportamento original.

function Export-Relatorio {
    param($Dados, $CaminhoDestino)
    $pasta = Split-Path -Path $CaminhoDestino -Parent
    if ($pasta -and -not (Test-Path -Path $pasta)) {
        New-Item -Path $pasta -ItemType Directory -Force | Out-Null
    }
    try {
        $Dados | Export-Csv -Path $CaminhoDestino -NoTypeInformation -Encoding UTF8
        Write-Log ('Arquivo exportado com sucesso: {0}' -f $CaminhoDestino) 'Ok'
        return $true
    }
    catch {
        Write-Log ('Erro ao exportar o arquivo: {0}' -f $_) 'Erro'
        return $false
    }
}

function Export-RelatorioHtml {
    param($Dados, $CaminhoDestino, $Resumo)
    $pasta = Split-Path -Path $CaminhoDestino -Parent
    if ($pasta -and -not (Test-Path -Path $pasta)) {
        New-Item -Path $pasta -ItemType Directory -Force | Out-Null
    }
    try {
        # -Head/-Title/-PostContent recebem SOMENTE texto literal fixo — nunca dado do
        # Event Log (mensagem de evento, nome de provedor, etc.). $Resumo e $Dados
        # entram via -Body/pipeline, mas ja chegam pre-escapados: ConvertTo-Html aplica
        # HtmlEncode em todo valor de celula automaticamente.
        $fragmentoResumo = $Resumo | ConvertTo-Html -Fragment -As List
        $html = $Dados | ConvertTo-Html `
            -Head '<meta charset="utf-8"><style>body{font-family:"Segoe UI",Arial,sans-serif;margin:2em;color:#222;} table{border-collapse:collapse;margin-bottom:1.5em;} th,td{border:1px solid #ccc;padding:6px 12px;text-align:left;} th{background:#2c3e50;color:#fff;} tr:nth-child(even){background:#f5f5f5;}</style>' `
            -Title 'Relatorio - Diagnostico da Caixa de Ferramentas' `
            -Body ('<h1>Diagnostico do Visualizador de Eventos</h1>' + $fragmentoResumo) `
            -PostContent '<p><em>Relatorio somente leitura — nenhum log foi apagado ou alterado.</em></p>'
        $html | Set-Content -Path $CaminhoDestino -Encoding UTF8
        Write-Log ('Arquivo HTML exportado com sucesso: {0}' -f $CaminhoDestino) 'Ok'
        return $true
    }
    catch {
        Write-Log ('Erro ao exportar o arquivo HTML: {0}' -f $_) 'Erro'
        return $false
    }
}

#endregion

#region AdminOculto (Grupo B — ativar-win-admin) -----------------------------------
# Familia "Utilitario pontual elevado": SEMPRE eleva (Set-LocalUser/Enable-LocalUser
# mexem em conta local). Identifica a conta SEMPRE pelo SID (-500), nunca por nome
# (varia por idioma do Windows). Regra inegociavel: nunca ativar com senha vazia.

function Get-ContaAdminEmbutida {
    # Identifica a conta pelo SID bem-conhecido (RID 500), nao pelo nome —
    # "Administrator"/"Administrador"/etc. varia por idioma do Windows, o SID nao.
    try {
        $conta = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID -like '*-500' } | Select-Object -First 1
    }
    catch {
        return $null
    }
    return $conta
}

function Get-EstadoConta {
    $conta = Get-ContaAdminEmbutida
    if (-not $conta) {
        return @{ Encontrada = $false; Ativa = $false; Nome = $null; Detalhe = 'conta administrativa embutida (SID -500) nao encontrada' }
    }
    return @{ Encontrada = $true; Ativa = $conta.Enabled; Nome = $conta.Name; Detalhe = ('conta "{0}" — {1}' -f $conta.Name, $(if ($conta.Enabled) { 'ATIVA' } else { 'desativada' })) }
}

function Read-SenhaConfirmada {
    while ($true) {
        $senha1 = Read-Host 'Nova senha para a conta administrativa' -AsSecureString
        if ($senha1.Length -eq 0) {
            Write-Log 'Senha vazia nao e permitida — a conta ficaria com acesso sem senha.' 'Aviso'
            continue
        }
        $senha2 = Read-Host 'Confirme a senha' -AsSecureString
        $bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($senha1)
        $bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($senha2)
        try {
            $iguais = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1) -ceq [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
        }
        if ($iguais) { return $senha1 }
        Write-Log 'As senhas nao coincidem. Tente novamente.' 'Aviso'
    }
}

function Enable-ContaAdmin {
    param([Parameter(Mandatory)][System.Security.SecureString]$Senha)

    if ($Senha.Length -eq 0) {
        return @{ Status = 'Falha'; Detalhe = 'senha vazia recusada — a conta nao foi alterada' }
    }
    $conta = Get-ContaAdminEmbutida
    if (-not $conta) {
        return @{ Status = 'Falha'; Detalhe = 'conta administrativa embutida (SID -500) nao encontrada' }
    }
    try {
        # Senha e setada ANTES de habilitar — a conta nunca fica ativa sem senha
        # nova definida, nem por um instante.
        Set-LocalUser -Name $conta.Name -Password $Senha -ErrorAction Stop
        Enable-LocalUser -Name $conta.Name -ErrorAction Stop
        return @{ Status = 'Ok'; Detalhe = ('conta "{0}" ativada com senha nova definida' -f $conta.Name) }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message }
    }
}

function Disable-ContaAdmin {
    $conta = Get-ContaAdminEmbutida
    if (-not $conta) {
        return @{ Status = 'Falha'; Detalhe = 'conta administrativa embutida (SID -500) nao encontrada' }
    }
    if (-not $conta.Enabled) {
        return @{ Status = 'Ok'; Detalhe = ('conta "{0}" ja estava desativada' -f $conta.Name) }
    }
    try {
        Disable-LocalUser -Name $conta.Name -ErrorAction Stop
        return @{ Status = 'Ok'; Detalhe = ('conta "{0}" desativada' -f $conta.Name) }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message }
    }
}

function Show-MainMenuAdmin {
    while ($true) {
        Clear-Host
        $estado = Get-EstadoConta
        Write-Host '=============================================================='
        Write-Host (' CAIXA DE FERRAMENTAS — Modo AdminOculto (v{0})' -f $script:VERSAO)
        Write-Host (' Estado atual: {0}' -f $estado.Detalhe)
        Write-Host '=============================================================='
        Write-Host ' 1) Ver estado atual (nao altera nada)'
        Write-Host ' 2) Ativar (vai pedir uma senha nova — nunca fica sem senha)'
        Write-Host ' 3) Desativar'
        Write-Host ' S) Sair'
        Write-Host '=============================================================='
        $opcao = (Read-Host 'Opcao').Trim().ToUpper()

        switch ($opcao) {
            'S' { return $null }
            '1' {
                Write-Log ('Estado atual: {0}' -f $estado.Detalhe) 'Info'
                Read-Host 'Pressione ENTER para continuar' | Out-Null
            }
            '2' {
                Clear-Host
                Write-Host '====================== ATIVAR CONTA ============================'
                Write-Host ' A conta administrativa embutida NAO tem UAC — todo processo' -ForegroundColor Yellow
                Write-Host ' roda com privilegio total, sem prompt de elevacao. Recomendado' -ForegroundColor Yellow
                Write-Host ' usar so temporariamente e desativar de novo depois.' -ForegroundColor Yellow
                Write-Host '=================================================================='
                $resposta = Read-Host 'Confirmar ativacao? (S/N)'
                if ($resposta -match '^[sS]') {
                    $senha = Read-SenhaConfirmada
                    return @{ Acao = 'Ativar'; Senha = $senha }
                }
            }
            '3' {
                $resposta = Read-Host 'Confirmar desativacao da conta? (S/N)'
                if ($resposta -match '^[sS]') { return @{ Acao = 'Desativar' } }
            }
        }
    }
}

#endregion

#region SafeBoot (Grupo B — SafeBoot-Ninja) ----------------------------------------
# Familia "Utilitario pontual elevado": sempre eleva (bcdedit exige admin). Confirmacao
# tem aviso PROPRIO de RDP (Confirm-AcaoSafeBoot, nao a Confirm-Acao generica — nem
# Minimo nem Rede iniciam RDP; quem so tem acesso remoto pode ficar sem acesso).

function Get-EstadoSafeBoot {
    # Le a saida de "bcdedit /enum {current}" e procura a linha "safeboot" —
    # metodo documentado pela Microsoft para checar o estado antes de alterar.
    # Sem essa linha = boot normal. Valor "Minimal" ou "Network" = modo ativo.
    try {
        $saida = & bcdedit /enum '{current}' 2>&1
    }
    catch {
        return @{ Estado = 'Desconhecido'; Detalhe = $_.Exception.Message }
    }
    $linha = $saida | Where-Object { $_ -match '^\s*safeboot\s+(\S+)' }
    if (-not $linha) {
        return @{ Estado = 'Normal'; Detalhe = 'nenhuma entrada safeboot — boot normal' }
    }
    $valor = $Matches[1]
    if ($valor -match '^(?i)network') {
        return @{ Estado = 'Rede'; Detalhe = 'Modo de Seguranca com Rede (safeboot=Network)' }
    }
    return @{ Estado = 'Minimo'; Detalhe = 'Modo de Seguranca minimo (safeboot=Minimal)' }
}

function Set-SafeBoot {
    param([Parameter(Mandatory)][ValidateSet('Minimo', 'Rede', 'Normal')][string]$Alvo)

    try {
        switch ($Alvo) {
            'Minimo' { & bcdedit /set '{current}' safeboot minimal   | Out-Null }
            'Rede'   { & bcdedit /set '{current}' safeboot network   | Out-Null }
            'Normal' { & bcdedit /deletevalue '{current}' safeboot   | Out-Null }
        }
        if ($LASTEXITCODE -ne 0) {
            return @{ Status = 'Falha'; Detalhe = ('bcdedit retornou codigo {0}' -f $LASTEXITCODE) }
        }
    }
    catch {
        return @{ Status = 'Falha'; Detalhe = $_.Exception.Message }
    }

    # Nunca confia so no exit code do bcdedit - relê o estado e compara com o esperado.
    $confirmado = Get-EstadoSafeBoot
    $estadoEsperado = if ($Alvo -eq 'Rede') { 'Rede' } else { $Alvo }
    if ($confirmado.Estado -eq $estadoEsperado) {
        return @{ Status = 'Ok'; Detalhe = ('aplicado e verificado: {0}' -f $confirmado.Detalhe) }
    }
    return @{ Status = 'Parcial'; Detalhe = ('bcdedit nao reportou erro, mas o estado verificado e "{0}" (esperado "{1}")' -f $confirmado.Estado, $estadoEsperado) }
}

function Show-AvisoCritico {
    Write-Log 'ATENCAO: nem o Modo de Seguranca minimo NEM o "com rede" iniciam o RDP.' 'Aviso'
    Write-Log 'Se voce so tem acesso remoto a esta maquina, ela pode ficar inacessivel apos reiniciar,' 'Aviso'
    Write-Log 'ate alguem com acesso fisico (ou KVM/iLO/iDRAC) desfazer a mudanca ("Normal").' 'Aviso'
}

function Confirm-AcaoSafeBoot {
    # Variante com aviso PROPRIO de RDP - nao e a Confirm-Acao generica (essa e usada
    # por Inicializacao; contratos diferentes de proposito, ver CLAUDE.md).
    param([Parameter(Mandatory)][string]$Alvo)

    Clear-Host
    Write-Host '====================== CONFIRMACAO ============================'
    Write-Host (' Acao: configurar boot para "{0}"' -f $Alvo)
    if ($Alvo -ne 'Normal') {
        Write-Host ''
        Write-Host ' ATENCAO: nem "Minimo" nem "Rede" iniciam o RDP. Se voce so tem' -ForegroundColor Yellow
        Write-Host ' acesso remoto a esta maquina, ela pode ficar inacessivel apos' -ForegroundColor Yellow
        Write-Host ' reiniciar, ate alguem com acesso fisico desfazer a mudanca.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host ' O efeito so vale a partir do PROXIMO reinicio, e continua' -ForegroundColor Yellow
        Write-Host ' valendo em TODO reinicio futuro ate voce escolher "Normal".' -ForegroundColor Yellow
    }
    Write-Host '=================================================================='
    $resposta = Read-Host 'Confirmar? (S/N)'
    return $resposta -match '^[sS]'
}

function Show-MainMenuSafeBoot {
    while ($true) {
        Clear-Host
        $estado = Get-EstadoSafeBoot
        Write-Host '=============================================================='
        Write-Host (' CAIXA DE FERRAMENTAS — Modo SafeBoot (v{0})' -f $script:VERSAO)
        Write-Host (' Estado atual: {0}' -f $estado.Detalhe)
        Write-Host '=============================================================='
        Write-Host ' 1) Ver estado atual (nao altera nada)'
        Write-Host ' 2) Ativar Modo de Seguranca minimo (sem rede, sem RDP)'
        Write-Host ' 3) Ativar Modo de Seguranca com rede (sem RDP tambem — leia o aviso)'
        Write-Host ' 4) Voltar ao boot normal'
        Write-Host ' S) Sair'
        Write-Host '=============================================================='
        $opcao = (Read-Host 'Opcao').Trim().ToUpper()

        switch ($opcao) {
            'S' { return $null }
            '1' {
                Write-Log ('Estado atual: {0}' -f $estado.Detalhe) 'Info'
                Read-Host 'Pressione ENTER para continuar' | Out-Null
            }
            '2' { if (Confirm-AcaoSafeBoot -Alvo 'Minimo') { return 'Minimo' } }
            '3' { if (Confirm-AcaoSafeBoot -Alvo 'Rede') { return 'Rede' } }
            '4' { if (Confirm-AcaoSafeBoot -Alvo 'Normal') { return 'Normal' } }
        }
    }
}

#endregion

#region Inicializacao (Grupo B — StartupAppsNinja) ---------------------------------
# Familia "Utilitario pontual elevado": SEMPRE eleva, mesmo so pra Listar (muitas
# chaves envolvidas ficam em HKLM). Confirm-Acao generica (param $Descricao) tem AQUI
# a sua origem/dono (ver CLAUDE.md, Bloqueio B) - ja existe desde a Fase 1.

# Builds do Windows ja validados em VM real (reg export antes/depois + conferencia
# visual no Task Manager) para a acao Habilitar/Desabilitar. Comeca VAZIA de
# proposito: nenhum build foi validado ainda nesta primeira versao.
$script:BuildsValidados = @()

function ConvertTo-ItemInicializacao {
    param(
        [Parameter(Mandatory)][string]$Nome,
        [string]$Comando,
        [Parameter(Mandatory)][string]$Origem,
        [byte[]]$ValorStartupApproved
    )
    # Sem entrada em StartupApproved = Windows trata como HABILITADO por padrao —
    # nao presumir desabilitado so por falta de dado.
    $habilitado = if ($null -eq $ValorStartupApproved -or $ValorStartupApproved.Count -eq 0) {
        $true
    }
    else {
        $ValorStartupApproved[0] -in @(0x02, 0x06)
    }
    [pscustomobject]@{
        Nome       = $Nome
        Comando    = $Comando
        Origem     = $Origem
        Habilitado = $habilitado
    }
}

function New-ValorStartupApproved {
    param([Parameter(Mandatory)][bool]$Habilitado)
    # 12 bytes: [0]=flag (02/06 habilitado, 03 desabilitado), [1..3]=reservado
    # (zerado — semantica exata nao confirmada), [4..11]=FILETIME (8 bytes,
    # little-endian Int64). Usado só quando NAO ha valor existente pra preservar.
    $bytes = New-Object byte[] 12
    $bytes[0] = if ($Habilitado) { 0x02 } else { 0x03 }
    $filetimeBytes = [BitConverter]::GetBytes([DateTime]::Now.ToFileTime())
    [Array]::Copy($filetimeBytes, 0, $bytes, 4, 8)
    return $bytes
}

function Set-PrimeiroByteStartupApproved {
    param(
        [Parameter(Mandatory)][byte[]]$ValorAtual,
        [Parameter(Mandatory)][bool]$Habilitado
    )
    # So altera o byte 0 (flag) e preserva os outros 11 bytes exatamente como
    # estavam — nao regenera o FILETIME nem o restante, porque o significado exato
    # desses bytes nao esta confirmado (nao documentado pela Microsoft). Preservar
    # o que ja existia e sempre mais seguro do que tentar reconstruir "o valor certo".
    $novoValor = $ValorAtual.Clone()
    $novoValor[0] = if ($Habilitado) { 0x02 } else { 0x03 }
    return $novoValor
}

function Test-BuildValidado {
    param(
        [Parameter(Mandatory)][int]$BuildAtual,
        # Sem [Parameter(Mandatory)] de proposito: um parametro de array obrigatorio
        # rejeita @() com ParameterBindingValidationException ("it is an empty
        # array") — e $script:BuildsValidados comeca vazio de proposito (nenhum
        # build validado em VM ainda), entao Mandatory aqui quebraria a PRIMEIRA
        # chamada real desta funcao. Bug real, achado pelo teste Pester.
        [int[]]$BuildsValidados = @()
    )
    return $BuildsValidados -contains $BuildAtual
}

function Get-CaminhoRegistroRun {
    param([ValidateSet('Usuario', 'TodosUsuarios')][string]$Escopo, [ValidateSet('Run', 'RunOnce')][string]$Chave)
    if ($Escopo -eq 'Usuario') {
        return "HKCU:\Software\Microsoft\Windows\CurrentVersion\$Chave"
    }
    return "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\$Chave"
}

function Get-CaminhoRegistroRunWow6432 {
    param([ValidateSet('Run', 'RunOnce')][string]$Chave)
    return "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\$Chave"
}

function Get-CaminhoStartupApproved {
    param([ValidateSet('Usuario', 'TodosUsuarios')][string]$Escopo, [ValidateSet('Run', 'StartupFolder')][string]$Secao = 'Run')
    $base = if ($Escopo -eq 'Usuario') { 'HKCU:' } else { 'HKLM:' }
    return "$base\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$Secao"
}

function Get-ValorStartupApproved {
    param([Parameter(Mandatory)][string]$CaminhoChave, [Parameter(Mandatory)][string]$Nome)
    if (-not (Test-Path $CaminhoChave)) { return $null }
    $item = Get-ItemProperty -Path $CaminhoChave -Name $Nome -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    return [byte[]]$item.$Nome
}

function Get-ItensRegistroRun {
    $itens = [System.Collections.Generic.List[object]]::new()
    $combinacoes = @(
        @{ Escopo = 'Usuario'; Chave = 'Run'; Origem = 'HKCU:Run' }
        @{ Escopo = 'Usuario'; Chave = 'RunOnce'; Origem = 'HKCU:RunOnce' }
        @{ Escopo = 'TodosUsuarios'; Chave = 'Run'; Origem = 'HKLM:Run' }
        @{ Escopo = 'TodosUsuarios'; Chave = 'RunOnce'; Origem = 'HKLM:RunOnce' }
    )
    foreach ($c in $combinacoes) {
        $caminho = Get-CaminhoRegistroRun -Escopo $c.Escopo -Chave $c.Chave
        $caminhoAprovado = Get-CaminhoStartupApproved -Escopo $c.Escopo -Secao 'Run'
        if (Test-Path $caminho) {
            $propriedades = Get-ItemProperty -Path $caminho -ErrorAction SilentlyContinue
            if ($propriedades) {
                foreach ($nomeProp in ($propriedades.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' })) {
                    $valorAprovado = Get-ValorStartupApproved -CaminhoChave $caminhoAprovado -Nome $nomeProp.Name
                    $itens.Add((ConvertTo-ItemInicializacao -Nome $nomeProp.Name -Comando $nomeProp.Value -Origem $c.Origem -ValorStartupApproved $valorAprovado))
                }
            }
        }
    }
    # WOW6432Node: so existe/faz sentido em Windows 64-bit; Test-Path cobre a ausencia.
    foreach ($chave in @('Run', 'RunOnce')) {
        $caminhoWow = Get-CaminhoRegistroRunWow6432 -Chave $chave
        if (Test-Path $caminhoWow) {
            $propriedades = Get-ItemProperty -Path $caminhoWow -ErrorAction SilentlyContinue
            if ($propriedades) {
                foreach ($nomeProp in ($propriedades.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' })) {
                    # Espelho de StartupApproved para WOW6432Node NAO confirmado —
                    # reporta o item sem tentar ler um estado habilitado/desabilitado.
                    $itens.Add((ConvertTo-ItemInicializacao -Nome $nomeProp.Name -Comando $nomeProp.Value -Origem "HKLM:WOW6432Node:$chave" -ValorStartupApproved $null))
                }
            }
        }
    }
    return $itens
}

function Get-ItensPastaInicializacao {
    $itens = [System.Collections.Generic.List[object]]::new()
    $pastas = @(
        @{ Caminho = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'; Origem = 'PastaUsuario' }
        @{ Caminho = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'; Origem = 'PastaTodosUsuarios' }
    )
    foreach ($p in $pastas) {
        if (Test-Path $p.Caminho) {
            Get-ChildItem -Path $p.Caminho -File -ErrorAction SilentlyContinue | ForEach-Object {
                $itens.Add((ConvertTo-ItemInicializacao -Nome $_.Name -Comando $_.FullName -Origem $p.Origem -ValorStartupApproved $null))
            }
        }
    }
    return $itens
}

function Get-TarefasComGatilhoLogon {
    # Somente informativo — nunca habilitado/desabilitado por este script (nao
    # aparecem na aba Inicializar do Task Manager, consenso tecnico forte mas nao
    # documentado oficialmente pela Microsoft; nao misturar com o toggle abaixo).
    try {
        Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }
        } | Select-Object TaskName, TaskPath, State
    }
    catch {
        Write-Log ('Nao foi possivel listar Tarefas Agendadas: {0}' -f $_.Exception.Message) 'Aviso'
        @()
    }
}

function Invoke-AcaoListar {
    Write-Log 'Registro (Run/RunOnce, HKCU + HKLM + WOW6432Node):' 'Titulo'
    $itensRegistro = Get-ItensRegistroRun
    $itensRegistro | Format-Table Nome, Origem, Habilitado, Comando -AutoSize -Wrap

    Write-Log 'Pastas de Inicializacao:' 'Titulo'
    $itensPasta = Get-ItensPastaInicializacao
    $itensPasta | Format-Table Nome, Origem, Comando -AutoSize -Wrap

    Write-Log 'Tarefas Agendadas com gatilho de logon (informativo — NAO aparecem no Task Manager, nunca alteradas por este script):' 'Titulo'
    Get-TarefasComGatilhoLogon | Format-Table TaskName, TaskPath, State -AutoSize
}

function Invoke-AcaoAdicionar {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Comando, [Parameter(Mandatory)][string]$Escopo)
    [void](Confirm-Acao -Descricao ('Adicionar "{0}" = "{1}" em Run (escopo: {2}).' -f $Nome, $Comando, $Escopo))
    $caminho = Get-CaminhoRegistroRun -Escopo $Escopo -Chave 'Run'
    if (-not (Test-Path $caminho)) { New-Item -Path $caminho -Force | Out-Null }
    Set-ItemProperty -Path $caminho -Name $Nome -Value $Comando -Type String -Force
    Write-Log ('Adicionado: {0}' -f $Nome) 'Ok'
}

function Invoke-AcaoRemover {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Escopo)
    [void](Confirm-Acao -Descricao ('Remover "{0}" de Run (escopo: {1}).' -f $Nome, $Escopo))
    $caminho = Get-CaminhoRegistroRun -Escopo $Escopo -Chave 'Run'
    if (-not (Test-Path $caminho) -or -not (Get-ItemProperty -Path $caminho -Name $Nome -ErrorAction SilentlyContinue)) {
        Write-Log ('"{0}" nao encontrado em Run (escopo: {1}) — nada a remover.' -f $Nome, $Escopo) 'Aviso'
        return
    }
    Remove-ItemProperty -Path $caminho -Name $Nome -Force
    Write-Log ('Removido: {0}' -f $Nome) 'Ok'
}

function Invoke-AcaoToggleExperimental {
    param([Parameter(Mandatory)][string]$Nome, [Parameter(Mandatory)][string]$Escopo, [Parameter(Mandatory)][bool]$Habilitado)

    if (-not $PermitirExperimental) {
        Write-Log 'Esta acao (toggle estilo Task Manager via StartupApproved) exige -PermitirExperimental — formato binario nao documentado oficialmente pela Microsoft.' 'Erro'
        Write-Log 'Alternativa segura e documentada: use -AcaoInicializacao Remover para desativar de forma definitiva e reversivel.' 'Info'
        exit 2
    }

    $buildAtual = [int](Get-CimInstance -ClassName Win32_OperatingSystem).BuildNumber
    if (-not (Test-BuildValidado -BuildAtual $buildAtual -BuildsValidados $script:BuildsValidados)) {
        Write-Log ("Build $buildAtual do Windows nao esta na lista de builds validados em VM para esta acao (lista atual: $($script:BuildsValidados -join ', ')). Comportamento nao confirmado neste build.") 'Aviso'
        if ($NaoInterativo -and -not $ForcarBuildNaoValidado) {
            Write-Log 'Modo nao interativo: use -ForcarBuildNaoValidado para prosseguir mesmo sem validacao do build.' 'Erro'
            exit 2
        }
        if (-not $NaoInterativo) {
            $resposta = Read-Host 'Continuar mesmo assim, neste build nao validado? (S/N)'
            if ($resposta -notmatch '^[sS]') { Write-Log 'Cancelado pelo usuario.' 'Info'; exit 4 }
        }
    }

    [void](Confirm-Acao -Descricao ('{0} "{1}" via StartupApproved (escopo: {2}) — toggle experimental estilo Task Manager.' -f $(if ($Habilitado) { 'Habilitar' } else { 'Desabilitar' }), $Nome, $Escopo))

    $caminhoStartupApproved = Get-CaminhoStartupApproved -Escopo $Escopo -Secao 'Run'
    if (-not (Test-Path $caminhoStartupApproved)) { New-Item -Path $caminhoStartupApproved -Force | Out-Null }

    $valorAtual = Get-ValorStartupApproved -CaminhoChave $caminhoStartupApproved -Nome $Nome
    if ($null -eq $valorAtual) {
        Write-Log 'Nenhuma entrada StartupApproved existente para este item — criando valor completo de 12 bytes (Windows trata "ausente" como habilitado por padrao).' 'Info'
        $novoValor = New-ValorStartupApproved -Habilitado $Habilitado
    }
    else {
        Write-Log ('Valor atual (backup, hex): {0}' -f (($valorAtual | ForEach-Object { $_.ToString('X2') }) -join ' ')) 'Info'
        $novoValor = Set-PrimeiroByteStartupApproved -ValorAtual $valorAtual -Habilitado $Habilitado
    }

    Set-ItemProperty -Path $caminhoStartupApproved -Name $Nome -Value $novoValor -Type Binary -Force

    $valorRelido = Get-ValorStartupApproved -CaminhoChave $caminhoStartupApproved -Nome $Nome
    $flagEsperada = if ($Habilitado) { @(0x02, 0x06) } else { @(0x03) }
    if ($null -eq $valorRelido -or $valorRelido[0] -notin $flagEsperada) {
        Write-Log ('Escreveu, mas a releitura NAO confirmou o estado esperado. Valor relido (hex): {0}' -f $(if ($valorRelido) { ($valorRelido | ForEach-Object { $_.ToString('X2') }) -join ' ' } else { '(vazio)' })) 'Erro'
        Write-Log 'O registro pode estar num estado nao verificado — confira manualmente no Task Manager.' 'Erro'
        exit 5
    }
    Write-Log ('Confirmado por releitura: {0}' -f $Nome) 'Ok'
}

#endregion

#region Menu principal (sem -Modo) -------------------------------------------------

function Show-MenuFerramentas {
    while ($true) {
        Clear-Host
        Write-Host '=============================================================='
        Write-Host (' CAIXA DE FERRAMENTAS WINDOWS (v{0})' -f $script:VERSAO)
        Write-Host '=============================================================='
        Write-Host ' 1) Debloat        - remover bloatware/telemetria (detecta Win10/11)'
        Write-Host ' 2) Faxina         - limpeza de disco (temporarios, cache, lixeira)'
        Write-Host ' 3) Tudo           - Debloat + Faxina juntos'
        Write-Host ' 4) Diagnostico    - verificar Visualizador de Eventos (so leitura)'
        Write-Host ' 5) AdminOculto    - ativar/desativar a conta Administrador oculta'
        Write-Host ' 6) SafeBoot       - ligar/desligar o Modo de Seguranca'
        Write-Host ' 7) Inicializacao  - gerenciar itens de inicializacao (Run/RunOnce)'
        Write-Host ' S) Sair'
        Write-Host '=============================================================='
        $opcao = (Read-Host 'Opcao').Trim().ToUpper()
        switch ($opcao) {
            'S' { return $null }
            '1' { return 'Debloat' }
            '2' { return 'Faxina' }
            '3' { return 'Tudo' }
            '4' { return 'Diagnostico' }
            '5' { return 'AdminOculto' }
            '6' { return 'SafeBoot' }
            '7' { return 'Inicializacao' }
        }
    }
}

#endregion

#region Fluxo principal ----------------------------------------------------------

if (-not $Modo -and $NaoInterativo) {
    Write-Log 'Modo nao interativo exige -Modo (sem ele nao ha como saber o que executar sem perguntar).' 'Erro'
    exit 2
}

if (-not $Modo) {
    $Modo = Show-MenuFerramentas
    if (-not $Modo) {
        Write-Log 'Nenhuma acao executada.' 'Info'
        exit 0
    }
}

if ($WhatIfPreference -and $Modo -notin @('Debloat', 'Faxina', 'Tudo', $null)) {
    Write-Log '-WhatIf nao tem efeito neste modo; use -Simular (funciona so em Debloat/Faxina/Tudo).' 'Aviso'
}

switch ($Modo) {
    { $_ -in @('Debloat', 'Faxina', 'Tudo') } {
        Assert-Admin -ParametrosOriginais $PSBoundParameters
        $script:VersaoWindowsDetectada = Get-VersaoWindows
        Assert-VersaoSuportada -VersaoDetectada $script:VersaoWindowsDetectada
        Start-Logging -CaminhoPersonalizado $CaminhoLog -Prefixo $Modo.ToLower()
        [void](Test-UsuarioDivergente)

        Write-Log ('Modo {0} — perfil "{1}"{2}' -f $Modo, $Perfil, $(if ($NaoInterativo) { ' (nao interativo)' } else { '' })) 'Titulo'
        if ($script:ArquivoLog) { Write-Log ('Log: {0}' -f $script:ArquivoLog) 'Info' }
        if ($script:Simular) { Write-Log 'MODO SIMULACAO: nenhuma alteracao sera feita no sistema.' 'Simulacao' }

        $categoriasModo = $script:CategoriasPorModo[$Modo]
        $codigoSaida = 0
        try {
            if ($NaoInterativo) {
                $itensExecucao = @(Get-ItensDoPerfil -NomePerfil $Perfil -Categorias $categoriasModo -VersaoWindows $script:VersaoWindowsDetectada)
                $fazRestore = -not $SemPontoRestauracao
            }
            else {
                $selecao = Show-MainMenu -Categorias $categoriasModo -TituloModo ('Modo {0}' -f $Modo) -VersaoWindows $script:VersaoWindowsDetectada
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

            # So pede reinicio se algo que realmente exige (Appx/Servico/Registro/
            # TarefaAgendada) foi executado - uma sessao so-de-limpeza (LimpezaPasta/
            # Especial, ex.: rodar so -Modo Faxina) nao deveria mandar reiniciar a toa.
            $tiposQueExigemReinicio = @('Appx', 'Servico', 'Registro', 'TarefaAgendada')
            $precisaReiniciar = @($resultado.Detalhes | Where-Object {
                    $_.Status -in @('Ok', 'Parcial') -and $_.Tipo -in $tiposQueExigemReinicio
                }).Count -gt 0
            if ($precisaReiniciar -and -not $script:Simular) {
                Write-Log 'Recomendado reiniciar o computador para que todas as mudancas tenham efeito completo.' 'Aviso'
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
        # Sem Assert-Admin, sem Start-Logging: familia "somente-leitura", nunca eleva.
        if (-not $Dias) {
            if ($NaoInterativo) {
                Write-Log 'Modo nao interativo exige -Dias.' 'Erro'
                exit 2
            }
            $entrada = Read-Host 'Informe quantos dias para tras verificar (ex: 30)'
            if (-not [int]::TryParse($entrada, [ref]$null) -or [int]$entrada -le 0) {
                Write-Log 'Valor invalido. Informe um numero inteiro maior que zero.' 'Erro'
                exit 2
            }
            $Dias = [int]$entrada
        }

        $dataLimite = (Get-Date).AddDays(-$Dias)
        Write-Log ('Verificando os ultimos {0} dias nos logs System e Application...' -f $Dias) 'Titulo'

        $verificacoes = @(
            @{ Nome = 'Desligamento sujo ou travamento (Kernel-Power)'; LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41 }
            @{ Nome = 'Desligamento inesperado registrado ao reiniciar'; LogName = 'System'; Id = 6008 }
            @{ Nome = 'Erro de controlador de disco'; LogName = 'System'; ProviderName = 'disk'; Id = @(7, 51) }
            @{ Nome = 'Timeout de I/O em disco (storport)'; LogName = 'System'; ProviderName = 'storport'; Id = 153 }
            @{ Nome = 'Erro de hardware ou memoria (WHEA)'; LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger' }
            @{ Nome = 'Falha de aplicativo (Application Error)'; LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000 }
        )

        $resultadosDiagnostico = foreach ($v in $verificacoes) {
            $parametrosFiltro = @{ LogName = $v.LogName; StartTime = $dataLimite }
            if ($v.ProviderName) { $parametrosFiltro.ProviderName = $v.ProviderName }
            if ($v.Id) { $parametrosFiltro.Id = $v.Id }

            try {
                $eventos = @(Get-WinEvent -FilterHashtable $parametrosFiltro -ErrorAction Stop)
            }
            catch {
                if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') {
                    $eventos = @()
                }
                else {
                    Write-Log ("Falha ao verificar '{0}': {1}" -f $v.Nome, $_) 'Aviso'
                    $eventos = $null
                }
            }

            $status = if ($null -eq $eventos) { 'NaoVerificado' } elseif ($eventos.Count -eq 0) { 'Limpo' } else { 'Achado' }
            $detalheVerificacao = switch ($status) {
                'NaoVerificado' { 'falha ao consultar este log/provedor' }
                'Limpo'         { 'nenhuma ocorrencia no periodo' }
                'Achado'        { '{0} ocorrencia(s) no periodo' -f $eventos.Count }
            }
            [pscustomobject]@{ Verificacao = $v.Nome; Status = $status; Detalhe = $detalheVerificacao; Eventos = @($eventos) }
        }

        $totalAchados = @($resultadosDiagnostico | Where-Object Status -eq 'Achado').Count
        $totalNaoVerificado = @($resultadosDiagnostico | Where-Object Status -eq 'NaoVerificado').Count

        if ($totalNaoVerificado -eq $resultadosDiagnostico.Count) {
            Write-Log 'Nenhuma verificacao conseguiu consultar o Visualizador de Eventos. Confira se o servico "Log de Eventos do Windows" esta rodando.' 'Erro'
            exit 3
        }

        Write-Log ('Verificacoes com ocorrencia: {0} de {1}.' -f $totalAchados, $resultadosDiagnostico.Count) 'Info'
        if ($totalNaoVerificado -gt 0) {
            Write-Log ('Atencao: {0} verificacao(oes) nao puderam ser consultadas — veja o detalhe abaixo.' -f $totalNaoVerificado) 'Aviso'
        }

        $linhasRelatorioDiagnostico = foreach ($r in $resultadosDiagnostico) {
            if ($r.Eventos.Count -gt 0) {
                foreach ($ev in $r.Eventos) {
                    [pscustomobject]@{
                        Verificacao = $r.Verificacao
                        DataHora    = $ev.TimeCreated
                        Id          = $ev.Id
                        Provedor    = $ev.ProviderName
                        Mensagem    = ($ev.Message -split "`r?`n")[0]
                    }
                }
            }
            else {
                [pscustomobject]@{
                    Verificacao = $r.Verificacao
                    DataHora    = $null
                    Id          = $null
                    Provedor    = $null
                    Mensagem    = $r.Detalhe
                }
            }
        }

        $resumoHtmlDiagnostico = @(
            [pscustomobject]@{ Campo = 'Dias verificados'; Valor = $Dias }
            [pscustomobject]@{ Campo = 'Gerado em'; Valor = (Get-Date).ToString('dd/MM/yyyy HH:mm') }
            [pscustomobject]@{ Campo = 'Computador'; Valor = $env:COMPUTERNAME }
            [pscustomobject]@{ Campo = 'Verificacoes com ocorrencia'; Valor = ('{0} de {1}' -f $totalAchados, $resultadosDiagnostico.Count) }
        )
        $pediuCsv = $Exportar -or $CaminhoCsv
        $pediuHtml = $ExportarHtml -or $CaminhoHtml

        if ($NaoInterativo -or $pediuCsv -or $pediuHtml) {
            if ($pediuCsv -or ($NaoInterativo -and -not $pediuHtml)) {
                $destino = if ($CaminhoCsv) { $CaminhoCsv } else { Join-Path 'C:\AD_Relatorios' "DiagnosticoPC_${Dias}dias.csv" }
                [void](Export-Relatorio -Dados $linhasRelatorioDiagnostico -CaminhoDestino $destino)
            }
            if ($pediuHtml) {
                $destinoHtml = if ($CaminhoHtml) { $CaminhoHtml } else { Join-Path 'C:\AD_Relatorios' "DiagnosticoPC_${Dias}dias.html" }
                [void](Export-RelatorioHtml -Dados $linhasRelatorioDiagnostico -CaminhoDestino $destinoHtml -Resumo $resumoHtmlDiagnostico)
            }
        }
        else {
            $resultadosDiagnostico | Format-Table Verificacao, Status, Detalhe -AutoSize -Wrap

            $resposta = Read-Host 'Exportar este relatorio? [C]SV, [H]TML, [A]mbos, [N]ao'
            switch -Regex ($resposta) {
                '^[cC]' {
                    $destino = Join-Path 'C:\AD_Relatorios' "DiagnosticoPC_${Dias}dias.csv"
                    [void](Export-Relatorio -Dados $linhasRelatorioDiagnostico -CaminhoDestino $destino)
                }
                '^[hH]' {
                    $destinoHtml = Join-Path 'C:\AD_Relatorios' "DiagnosticoPC_${Dias}dias.html"
                    [void](Export-RelatorioHtml -Dados $linhasRelatorioDiagnostico -CaminhoDestino $destinoHtml -Resumo $resumoHtmlDiagnostico)
                }
                '^[aA]' {
                    $destino = Join-Path 'C:\AD_Relatorios' "DiagnosticoPC_${Dias}dias.csv"
                    [void](Export-Relatorio -Dados $linhasRelatorioDiagnostico -CaminhoDestino $destino)
                    $destinoHtml = Join-Path 'C:\AD_Relatorios' "DiagnosticoPC_${Dias}dias.html"
                    [void](Export-RelatorioHtml -Dados $linhasRelatorioDiagnostico -CaminhoDestino $destinoHtml -Resumo $resumoHtmlDiagnostico)
                }
                default {
                    Write-Log 'Nenhum arquivo exportado.' 'Info'
                }
            }
        }

        Write-Log 'Execucao concluida.' 'Titulo'
        exit 0
    }
    'AdminOculto' {
        # Sempre eleva (Set-LocalUser/Enable-LocalUser exigem admin).
        Assert-Admin -ParametrosOriginais $PSBoundParameters
        Start-Logging -CaminhoPersonalizado $CaminhoLog -Prefixo 'admin'

        $sufixoAcao = if ($AcaoAdmin) { ' — acao "{0}"' -f $AcaoAdmin } else { '' }
        $sufixoModo = if ($NaoInterativo) { ' (nao interativo)' } else { '' }
        Write-Log ('Modo AdminOculto{0}{1}' -f $sufixoAcao, $sufixoModo) 'Titulo'
        if ($script:ArquivoLog) { Write-Log ('Log: {0}' -f $script:ArquivoLog) 'Info' }

        $codigoSaida = 0
        try {
            if ($AcaoAdmin -eq 'Status') {
                $estado = Get-EstadoConta
                Write-Log ('Estado atual: {0}' -f $estado.Detalhe) 'Info'
            }
            elseif ($NaoInterativo) {
                if (-not $AcaoAdmin) {
                    Write-Log 'Modo nao interativo exige -AcaoAdmin (Status, Ativar ou Desativar).' 'Erro'
                    exit 2
                }
                if ($AcaoAdmin -eq 'Ativar') {
                    if (-not $SenhaSegura -or $SenhaSegura.Length -eq 0) {
                        Write-Log 'Modo nao interativo com -AcaoAdmin Ativar exige -SenhaSegura (a conta nunca e ativada sem senha).' 'Erro'
                        exit 2
                    }
                    $resultadoAdmin = Enable-ContaAdmin -Senha $SenhaSegura
                }
                else {
                    $resultadoAdmin = Disable-ContaAdmin
                }
                if ($resultadoAdmin.Status -eq 'Ok') { Write-Log $resultadoAdmin.Detalhe 'Ok' }
                else { Write-Log $resultadoAdmin.Detalhe 'Erro'; $codigoSaida = 5 }
            }
            else {
                if ($AcaoAdmin -eq 'Ativar') {
                    $senhaConfirmada = Read-SenhaConfirmada
                    $resultadoAdmin = Enable-ContaAdmin -Senha $senhaConfirmada
                }
                elseif ($AcaoAdmin -eq 'Desativar') {
                    $resultadoAdmin = Disable-ContaAdmin
                }
                else {
                    $escolha = Show-MainMenuAdmin
                    if (-not $escolha) {
                        Write-Log 'Nenhuma acao executada.' 'Info'
                        Stop-LoggingSeAtivo
                        exit 0
                    }
                    if ($escolha.Acao -eq 'Ativar') {
                        $resultadoAdmin = Enable-ContaAdmin -Senha $escolha.Senha
                    }
                    else {
                        $resultadoAdmin = Disable-ContaAdmin
                    }
                }
                if ($resultadoAdmin.Status -eq 'Ok') { Write-Log $resultadoAdmin.Detalhe 'Ok' }
                else { Write-Log $resultadoAdmin.Detalhe 'Erro'; $codigoSaida = 5 }
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
    'SafeBoot' {
        # Sempre eleva (bcdedit exige admin).
        Assert-Admin -ParametrosOriginais $PSBoundParameters
        Start-Logging -CaminhoPersonalizado $CaminhoLog -Prefixo 'safeboot'

        $sufixoAcao = if ($AcaoSafeBoot) { ' — acao "{0}"' -f $AcaoSafeBoot } else { '' }
        $sufixoModo = if ($NaoInterativo) { ' (nao interativo)' } else { '' }
        Write-Log ('Modo SafeBoot{0}{1}' -f $sufixoAcao, $sufixoModo) 'Titulo'
        if ($script:ArquivoLog) { Write-Log ('Log: {0}' -f $script:ArquivoLog) 'Info' }

        $codigoSaida = 0
        try {
            if ($AcaoSafeBoot -eq 'Status') {
                $estadoSafeBoot = Get-EstadoSafeBoot
                Write-Log ('Estado atual: {0}' -f $estadoSafeBoot.Detalhe) 'Info'
            }
            elseif ($NaoInterativo) {
                if (-not $AcaoSafeBoot) {
                    Write-Log 'Modo nao interativo exige -AcaoSafeBoot (Status, Minimo, Rede ou Normal).' 'Erro'
                    exit 2
                }
                if (-not $Confirmar) {
                    Write-Log ('Acao "{0}" exige -Confirmar em modo nao interativo (acao muda o comportamento de boot).' -f $AcaoSafeBoot) 'Erro'
                    exit 2
                }
                if ($AcaoSafeBoot -ne 'Normal') { Show-AvisoCritico }
                $resultadoSafeBoot = Set-SafeBoot -Alvo $AcaoSafeBoot
                if ($resultadoSafeBoot.Status -eq 'Ok') { Write-Log $resultadoSafeBoot.Detalhe 'Ok' }
                elseif ($resultadoSafeBoot.Status -eq 'Parcial') { Write-Log $resultadoSafeBoot.Detalhe 'Aviso' }
                else { Write-Log $resultadoSafeBoot.Detalhe 'Erro'; $codigoSaida = 5 }
            }
            else {
                if ($AcaoSafeBoot -and $AcaoSafeBoot -ne 'Status') {
                    if ($AcaoSafeBoot -ne 'Normal') { Show-AvisoCritico }
                    if (-not (Confirm-AcaoSafeBoot -Alvo $AcaoSafeBoot)) {
                        Write-Log 'Cancelado pelo usuario.' 'Info'
                        exit 4
                    }
                    $alvoSafeBoot = $AcaoSafeBoot
                }
                else {
                    $alvoSafeBoot = Show-MainMenuSafeBoot
                    if (-not $alvoSafeBoot) {
                        Write-Log 'Nenhuma acao executada.' 'Info'
                        Stop-LoggingSeAtivo
                        exit 0
                    }
                }
                $resultadoSafeBoot = Set-SafeBoot -Alvo $alvoSafeBoot
                if ($resultadoSafeBoot.Status -eq 'Ok') { Write-Log $resultadoSafeBoot.Detalhe 'Ok' }
                elseif ($resultadoSafeBoot.Status -eq 'Parcial') { Write-Log $resultadoSafeBoot.Detalhe 'Aviso' }
                else { Write-Log $resultadoSafeBoot.Detalhe 'Erro'; $codigoSaida = 5 }
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
    'Inicializacao' {
        # Sempre eleva, mesmo so pra Listar (varias chaves envolvidas ficam em HKLM).
        Assert-Admin -ParametrosOriginais $PSBoundParameters
        Start-Logging -CaminhoPersonalizado $CaminhoLog -Prefixo 'startup'

        Write-Log ('Modo Inicializacao — acao "{0}"' -f $AcaoInicializacao) 'Titulo'
        if ($script:ArquivoLog) { Write-Log ('Log: {0}' -f $script:ArquivoLog) 'Info' }

        try {
            switch ($AcaoInicializacao) {
                'Listar' {
                    Invoke-AcaoListar
                }
                'Adicionar' {
                    if (-not $Nome -or -not $Comando) {
                        Write-Log '-AcaoInicializacao Adicionar exige -Nome e -Comando.' 'Erro'
                        exit 2
                    }
                    Invoke-AcaoAdicionar -Nome $Nome -Comando $Comando -Escopo $Escopo
                }
                'Remover' {
                    if (-not $Nome) {
                        Write-Log '-AcaoInicializacao Remover exige -Nome.' 'Erro'
                        exit 2
                    }
                    Invoke-AcaoRemover -Nome $Nome -Escopo $Escopo
                }
                'Habilitar' {
                    if (-not $Nome) {
                        Write-Log '-AcaoInicializacao Habilitar exige -Nome.' 'Erro'
                        exit 2
                    }
                    Invoke-AcaoToggleExperimental -Nome $Nome -Escopo $Escopo -Habilitado $true
                }
                'Desabilitar' {
                    if (-not $Nome) {
                        Write-Log '-AcaoInicializacao Desabilitar exige -Nome.' 'Erro'
                        exit 2
                    }
                    Invoke-AcaoToggleExperimental -Nome $Nome -Escopo $Escopo -Habilitado $false
                }
            }
        }
        finally {
            Stop-LoggingSeAtivo
        }

        exit 0
    }
    default {
        # Inalcancavel na pratica: -Modo tem ValidateSet com os 7 valores validos, e o
        # bloco "sem -Modo" acima ja garante $Modo preenchido (via Show-MenuFerramentas
        # ou -NaoInterativo falhando cedo) antes de chegar aqui. Guarda defensiva, nao
        # um caminho real.
        Write-Log ('Modo desconhecido: "{0}".' -f $Modo) 'Erro'
        exit 9
    }
}

#endregion
