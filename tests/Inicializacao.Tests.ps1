# Testes do modo Inicializacao (Grupo B - StartupAppsNinja). Roda em qualquer SO (so
# valida logica pura via fixture + estrutura/AST); leitura/escrita real do registro
# Run/StartupApproved so pode ser validada em execucao real (CI windows-latest / VM).

BeforeAll {
    $script:CaminhoScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'CaixaDeFerramentasWindows.ps1'
    $tokens = $null; $erros = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CaminhoScript, [ref]$tokens, [ref]$erros)

    # So retorna TEXTO (dado) - seguro chamar atraves de uma funcao normal. O
    # Invoke-Expression que DEFINE a funcao extraida precisa ficar direto no
    # BeforeEach de cada Describe, nao aqui dentro: uma funcao criada via
    # Invoke-Expression executado DE DENTRO de outra funcao fica presa no escopo
    # local dessa funcao e desaparece assim que ela retorna - achado ao rodar este
    # arquivo pela primeira vez (a extraida sumia antes do It rodar, mesmo com o
    # helper em si sendo encontrado normalmente).
    function Get-TextoFuncao {
        param([Parameter(Mandatory)][string]$Nome)
        $funcAst = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq $Nome
            }, $true) | Select-Object -First 1
        $funcAst | Should -Not -BeNullOrEmpty -Because "a funcao '$Nome' precisa existir"
        return $funcAst.Extent.Text
    }
}

Describe 'Inicializacao: funcoes existem, sempre eleva' {
    It 'todas as funcoes do modo existem' {
        foreach ($nome in @(
                'ConvertTo-ItemInicializacao', 'New-ValorStartupApproved', 'Set-PrimeiroByteStartupApproved',
                'Test-BuildValidado', 'Get-CaminhoRegistroRun', 'Get-CaminhoRegistroRunWow6432',
                'Get-CaminhoStartupApproved', 'Get-ValorStartupApproved', 'Get-ItensRegistroRun',
                'Get-ItensPastaInicializacao', 'Get-TarefasComGatilhoLogon', 'Invoke-AcaoListar',
                'Invoke-AcaoAdicionar', 'Invoke-AcaoRemover', 'Invoke-AcaoToggleExperimental'
            )) {
            $funcao = $script:Ast.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq $nome
                }, $true) | Select-Object -First 1
            $funcao | Should -Not -BeNullOrEmpty -Because "'$nome' precisa existir"
        }
    }

    It 'o bloco do Modo Inicializacao chama Assert-Admin, mesmo para Listar (varias chaves ficam em HKLM)' {
        $switchModo = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.SwitchStatementAst] -and
                $no.Condition.Extent.Text -eq '$Modo'
            }, $true) | Select-Object -First 1
        $clauseInicializacao = $switchModo.Clauses | Where-Object { $_.Item1.Extent.Text -eq "'Inicializacao'" } | Select-Object -First 1
        $clauseInicializacao | Should -Not -BeNullOrEmpty

        $chamadas = @($clauseInicializacao.Item2.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.CommandAst]
                }, $true) | ForEach-Object { $_.GetCommandName() })
        $chamadas | Should -Contain 'Assert-Admin'
    }

    It 'Get-ItensRegistroRun varre as 4 combinacoes fixas (HKCU/HKLM x Run/RunOnce) sem depender de -Escopo' {
        # -Escopo so importa pras acoes de escrita (Adicionar/Remover/toggle) - Listar
        # sempre mostra tudo. Confirma que a funcao nao referencia $Escopo.
        $funcao = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Get-ItensRegistroRun'
            }, $true) | Select-Object -First 1
        $funcao.Extent.Text | Should -Not -Match '\$Escopo\b'
    }

    It 'Invoke-AcaoToggleExperimental checa -PermitirExperimental ANTES de qualquer chamada a Get-CimInstance (camada de seguranca 1, nunca remover)' {
        $funcao = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Invoke-AcaoToggleExperimental'
            }, $true) | Select-Object -First 1
        $textoAntesDoExit = $funcao.Extent.Text.Substring(0, $funcao.Extent.Text.IndexOf('exit 2'))
        $textoAntesDoExit | Should -Match 'PermitirExperimental'
        $textoAntesDoExit | Should -Not -Match 'Get-CimInstance' -Because 'o gate de -PermitirExperimental precisa vir antes de qualquer consulta ao build do Windows'
    }
}

Describe 'Test-BuildValidado: regressao do bug real (Mandatory + array vazio)' {
    BeforeEach { Invoke-Expression (Get-TextoFuncao -Nome 'Test-BuildValidado') }

    It 'aceita ser chamada SEM -BuildsValidados (usa o default @() sem lancar ParameterBindingValidationException)' {
        # Esta e a chamada que quebrava antes da correcao: um parametro de array
        # obrigatorio rejeita @() (mesmo implicito, via default) com
        # ParameterBindingValidationException - e $script:BuildsValidados comeca
        # vazio de proposito nesta versao (nenhum build validado em VM ainda).
        { Test-BuildValidado -BuildAtual 26100 } | Should -Not -Throw
        Test-BuildValidado -BuildAtual 26100 | Should -BeFalse
    }

    It 'aceita -BuildsValidados @() explicito (o caso exato do bug original) sem lancar' {
        { Test-BuildValidado -BuildAtual 26100 -BuildsValidados @() } | Should -Not -Throw
        Test-BuildValidado -BuildAtual 26100 -BuildsValidados @() | Should -BeFalse
    }

    It 'retorna true quando o build atual esta na lista de validados' {
        Test-BuildValidado -BuildAtual 26100 -BuildsValidados @(19045, 26100) | Should -BeTrue
    }
}

Describe 'ConvertTo-ItemInicializacao: ausencia de StartupApproved = habilitado por padrao' {
    BeforeEach { Invoke-Expression (Get-TextoFuncao -Nome 'ConvertTo-ItemInicializacao') }

    It 'sem ValorStartupApproved (nunca configurado) = Habilitado' {
        $item = ConvertTo-ItemInicializacao -Nome 'X' -Comando 'x.exe' -Origem 'HKCU:Run'
        $item.Habilitado | Should -BeTrue
    }

    It 'byte 0 = 0x02 ou 0x06 = Habilitado' {
        (ConvertTo-ItemInicializacao -Nome 'X' -Origem 'HKCU:Run' -ValorStartupApproved ([byte[]](0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))).Habilitado | Should -BeTrue
        (ConvertTo-ItemInicializacao -Nome 'X' -Origem 'HKCU:Run' -ValorStartupApproved ([byte[]](0x06, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))).Habilitado | Should -BeTrue
    }

    It 'byte 0 = 0x03 = Desabilitado' {
        (ConvertTo-ItemInicializacao -Nome 'X' -Origem 'HKCU:Run' -ValorStartupApproved ([byte[]](0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))).Habilitado | Should -BeFalse
    }
}

Describe 'New-ValorStartupApproved / Set-PrimeiroByteStartupApproved: formato binario de 12 bytes' {
    BeforeEach {
        Invoke-Expression (Get-TextoFuncao -Nome 'New-ValorStartupApproved')
        Invoke-Expression (Get-TextoFuncao -Nome 'Set-PrimeiroByteStartupApproved')
    }

    It 'New-ValorStartupApproved gera 12 bytes com o byte 0 correto por estado' {
        $valorHabilitado = New-ValorStartupApproved -Habilitado $true
        $valorHabilitado.Count | Should -Be 12
        $valorHabilitado[0] | Should -Be 0x02

        $valorDesabilitado = New-ValorStartupApproved -Habilitado $false
        $valorDesabilitado[0] | Should -Be 0x03
    }

    It 'Set-PrimeiroByteStartupApproved so troca o byte 0, preserva os outros 11 exatamente' {
        $original = [byte[]](0x03, 11, 22, 33, 44, 55, 66, 77, 88, 99, 111, 122)
        $atualizado = Set-PrimeiroByteStartupApproved -ValorAtual $original -Habilitado $true
        $atualizado[0] | Should -Be 0x02
        $atualizado[1..11] | Should -Be $original[1..11]
        # Nao deve mutar o array original (Clone() esperado).
        $original[0] | Should -Be 0x03
    }
}
