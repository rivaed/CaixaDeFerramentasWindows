# Testes do modo AdminOculto (Grupo B - ativar-win-admin). Roda em qualquer SO (so
# valida estrutura/AST + a logica pura de senha vazia); Get-LocalUser/Enable-LocalUser
# contra a conta -500 real so pode ser validado em execucao real (CI windows-latest / VM).

BeforeAll {
    $script:CaminhoScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'CaixaDeFerramentasWindows.ps1'
    $tokens = $null; $erros = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CaminhoScript, [ref]$tokens, [ref]$erros)
}

Describe 'AdminOculto: funcoes existem, identidade por SID, sempre eleva' {
    It 'todas as funcoes do modo existem' {
        foreach ($nome in @('Get-ContaAdminEmbutida', 'Get-EstadoConta', 'Read-SenhaConfirmada', 'Enable-ContaAdmin', 'Disable-ContaAdmin', 'Show-MainMenuAdmin')) {
            $funcao = $script:Ast.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq $nome
                }, $true) | Select-Object -First 1
            $funcao | Should -Not -BeNullOrEmpty -Because "'$nome' precisa existir"
        }
    }

    It 'Get-ContaAdminEmbutida identifica a conta pelo SID (-500), nunca por nome' {
        # "Administrator"/"Administrador"/etc. varia por idioma do Windows - o SID nao.
        $funcao = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Get-ContaAdminEmbutida'
            }, $true) | Select-Object -First 1
        $funcao.Extent.Text | Should -Match "-500" -Because 'a busca precisa ser pelo SID terminado em -500'
        $funcao.Extent.Text | Should -Not -Match "(?i)'administrator'|'administrador'" -Because 'nunca filtrar por nome literal da conta'
    }

    It 'o bloco do Modo AdminOculto chama Assert-Admin (familia sempre eleva)' {
        $switchModo = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.SwitchStatementAst] -and
                $no.Condition.Extent.Text -eq '$Modo'
            }, $true) | Select-Object -First 1
        $clauseAdmin = $switchModo.Clauses | Where-Object { $_.Item1.Extent.Text -eq "'AdminOculto'" } | Select-Object -First 1
        $clauseAdmin | Should -Not -BeNullOrEmpty

        $chamadas = @($clauseAdmin.Item2.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.CommandAst]
                }, $true) | ForEach-Object { $_.GetCommandName() })
        $chamadas | Should -Contain 'Assert-Admin' -Because 'Set-LocalUser/Enable-LocalUser exigem admin'
    }
}

Describe 'Enable-ContaAdmin: nunca ativa com senha vazia (logica pura, testavel sem Get-LocalUser real)' {
    BeforeEach {
        # A checagem de Length=0 e a PRIMEIRA linha da funcao, antes de qualquer
        # chamada a Get-ContaAdminEmbutida/Get-LocalUser - por isso e seguro extrair
        # e chamar isolado num fixture, sem tocar no sistema de contas real.
        $funcAst = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Enable-ContaAdmin'
            }, $true) | Select-Object -First 1
        Invoke-Expression $funcAst.Extent.Text
    }

    It 'senha vazia (SecureString de comprimento 0) e recusada com Status=Falha, sem tentar Get-LocalUser' {
        $senhaVazia = [System.Security.SecureString]::new()
        $resultado = Enable-ContaAdmin -Senha $senhaVazia
        $resultado.Status | Should -Be 'Falha'
        $resultado.Detalhe | Should -Match 'vazia'
    }
}
