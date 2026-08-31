# Testes estruturais do CaixaDeFerramentasWindows.ps1 (Pester 5) — parametros,
# sintaxe/encoding, e guardas mecanicas fundamentais que valem para o arquivo
# inteiro (nao soem catalogo/modo especifico — ver outros arquivos *.Tests.ps1).

BeforeAll {
    $script:CaminhoScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'CaixaDeFerramentasWindows.ps1'
    $tokens = $null; $erros = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CaminhoScript, [ref]$tokens, [ref]$erros)
    $script:ErrosParse = $erros
    $script:Conteudo = Get-Content -Path $script:CaminhoScript -Raw
}

Describe 'Sintaxe e encoding' {
    It 'faz parse sem erros de sintaxe' {
        $script:ErrosParse | Should -BeNullOrEmpty
    }

    It 'esta salvo como UTF-8 com BOM (obrigatorio para acentos no PowerShell 5.1)' {
        $bytes = [System.IO.File]::ReadAllBytes($script:CaminhoScript)[0..2]
        $bytes | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'declara #Requires -Version 5.1' {
        (Get-Content -Path $script:CaminhoScript -TotalCount 5) -join "`n" |
            Should -Match '#Requires -Version 5\.1'
    }

    It 'nao usa Pause (bloqueia execucao nao interativa)' {
        $comandos = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.CommandAst] -and
                $no.GetCommandName() -eq 'Pause'
            }, $true)
        $comandos | Should -BeNullOrEmpty
    }
}

Describe 'Colisao de nome de funcao (guarda mecanica fundamental desta fusao)' {
    It 'nenhuma funcao e definida duas vezes no arquivo inteiro' {
        # Motivo de existir: colar varios scripts que cada um definia sua propria
        # Show-MainMenu/Confirm-Acao no mesmo arquivo faz a ULTIMA definicao na ordem
        # do arquivo vencer SILENCIOSAMENTE (sem erro de parse, sem teste falhando a
        # menos que exista este teste especifico) — o risco mecanico mais perigoso
        # desta fusao, porque so aparece cruzando varios arquivos-fonte ao mesmo
        # tempo, nao lendo um de cada vez.
        $funcoes = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true)
        $nomes = @($funcoes | ForEach-Object { $_.Name })
        $duplicados = $nomes | Group-Object | Where-Object Count -gt 1 | ForEach-Object { $_.Name }
        $duplicados | Should -BeNullOrEmpty -Because "funcoes definidas mais de uma vez: $($duplicados -join ', ')"
    }
}

Describe 'Parametros: colisao de -Acao resolvida por renomeio' {
    It 'nao existe um parametro chamado exatamente -Acao (renomeado por modo)' {
        # -Acao colidia entre StartupAppsNinja/SafeBoot-Ninja/ativar-win-admin, cada
        # um com um ValidateSet diferente — nao da pra declarar isso uma vez so.
        # Resolvido com nomes especificos por modo; este teste garante que ninguem
        # reintroduz um -Acao generico ambiguo por engano.
        $nomes = $script:Ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        $nomes | Should -Not -Contain 'Acao'
    }

    It 'aceita -Modo, -AcaoInicializacao, -AcaoSafeBoot e -AcaoAdmin (nomes especificos por modo)' {
        $nomes = $script:Ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        foreach ($esperado in @('Modo', 'AcaoInicializacao', 'AcaoSafeBoot', 'AcaoAdmin')) {
            $nomes | Should -Contain $esperado
        }
    }

    It 'aceita todos os demais parametros do param() fundido (um por area)' {
        $nomes = $script:Ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        $esperados = @(
            'Perfil', 'Simular', 'SemPontoRestauracao', 'CaminhoRelatorioJson',
            'Nome', 'Comando', 'Escopo', 'PermitirExperimental', 'ForcarBuildNaoValidado',
            'SenhaSegura',
            'Dias', 'Exportar', 'CaminhoCsv', 'ExportarHtml', 'CaminhoHtml',
            'NaoInterativo', 'Confirmar', 'CaminhoLog'
        )
        foreach ($esperado in $esperados) {
            $nomes | Should -Contain $esperado
        }
    }

    It '-Modo so aceita os 7 modos definidos' {
        $paramModo = $script:Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Modo' }
        $validateSet = $paramModo.Attributes | Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $validateSet | Should -Not -BeNullOrEmpty
        $valores = $validateSet.PositionalArguments.Value
        foreach ($esperado in @('Debloat', 'Faxina', 'Tudo', 'Inicializacao', 'SafeBoot', 'AdminOculto', 'Diagnostico')) {
            $valores | Should -Contain $esperado
        }
        $valores.Count | Should -Be 7
    }

    It 'modo nao interativo sem -Modo sai com erro claro' {
        $script:Conteudo | Should -Match 'Modo nao interativo exige -Modo'
    }
}

Describe 'ConvertTo-VersaoWindows: deteccao pura, testavel sem Windows real' {
    BeforeEach {
        $funcAst = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'ConvertTo-VersaoWindows'
            }, $true) | Select-Object -First 1
        Invoke-Expression $funcAst.Extent.Text
    }

    It 'ProductType=1 (workstation) e build >= 22000 = Win11' {
        ConvertTo-VersaoWindows -ProductType 1 -Build 22631 | Should -Be 'Win11'
        ConvertTo-VersaoWindows -ProductType 1 -Build 26100 | Should -Be 'Win11'
    }

    It 'ProductType=1 (workstation) e build entre 10240 e 21999 = Win10' {
        ConvertTo-VersaoWindows -ProductType 1 -Build 19045 | Should -Be 'Win10'
        ConvertTo-VersaoWindows -ProductType 1 -Build 10240 | Should -Be 'Win10'
    }

    It 'build abaixo de 10240 = Desconhecido, mesmo sendo workstation' {
        ConvertTo-VersaoWindows -ProductType 1 -Build 7601 | Should -Be 'Desconhecido'
    }

    It 'ProductType diferente de 1 (Server/DC) = Desconhecido mesmo com build de Win10/11' {
        # Corrige um gap real do Assert-Windows10 original (Windows10-Debloat): a
        # versao antiga so checava o build, nao o ProductType, e passaria hoje num
        # Windows Server com build na faixa 10240-21999.
        ConvertTo-VersaoWindows -ProductType 2 -Build 19045 | Should -Be 'Desconhecido'
        ConvertTo-VersaoWindows -ProductType 3 -Build 22631 | Should -Be 'Desconhecido'
    }
}
