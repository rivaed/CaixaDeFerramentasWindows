# Testes do modo SafeBoot (Grupo B - SafeBoot-Ninja). Roda em qualquer SO (so valida
# estrutura/AST); bcdedit real so pode ser validado em execucao real (CI windows-latest / VM).

BeforeAll {
    $script:CaminhoScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'CaixaDeFerramentasWindows.ps1'
    $tokens = $null; $erros = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CaminhoScript, [ref]$tokens, [ref]$erros)
}

Describe 'SafeBoot: funcoes existem, sempre eleva, usa a Confirm-Acao PROPRIA (nao a generica)' {
    It 'todas as funcoes do modo existem' {
        foreach ($nome in @('Get-EstadoSafeBoot', 'Set-SafeBoot', 'Show-AvisoCritico', 'Confirm-AcaoSafeBoot', 'Show-MainMenuSafeBoot')) {
            $funcao = $script:Ast.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq $nome
                }, $true) | Select-Object -First 1
            $funcao | Should -Not -BeNullOrEmpty -Because "'$nome' precisa existir"
        }
    }

    It 'Confirm-AcaoSafeBoot tem assinatura param($Alvo), nao param($Descricao) (contrato diferente da Confirm-Acao generica)' {
        $funcao = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Confirm-AcaoSafeBoot'
            }, $true) | Select-Object -First 1
        $nomesParametros = @($funcao.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        $nomesParametros | Should -Be @('Alvo')
    }

    It 'Set-SafeBoot relê o estado apos bcdedit (nunca confia so no exit code)' {
        $funcao = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Set-SafeBoot'
            }, $true) | Select-Object -First 1
        $chamadas = @($funcao.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.CommandAst]
                }, $true) | ForEach-Object { $_.GetCommandName() })
        $chamadas | Should -Contain 'Get-EstadoSafeBoot' -Because 'precisa reler o estado real, nao so confiar no $LASTEXITCODE do bcdedit'
    }

    It 'o bloco do Modo SafeBoot chama Assert-Admin e Confirm-AcaoSafeBoot, nunca a Confirm-Acao generica' {
        $switchModo = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.SwitchStatementAst] -and
                $no.Condition.Extent.Text -eq '$Modo'
            }, $true) | Select-Object -First 1
        $clauseSafeBoot = $switchModo.Clauses | Where-Object { $_.Item1.Extent.Text -eq "'SafeBoot'" } | Select-Object -First 1
        $clauseSafeBoot | Should -Not -BeNullOrEmpty

        $chamadas = @($clauseSafeBoot.Item2.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.CommandAst]
                }, $true) | ForEach-Object { $_.GetCommandName() })
        $chamadas | Should -Contain 'Assert-Admin' -Because 'bcdedit exige admin'
        $chamadas | Should -Contain 'Confirm-AcaoSafeBoot' -Because 'o aviso de RDP e especifico deste modo'
        $chamadas | Should -Not -Contain 'Confirm-Acao' -Because 'a Confirm-Acao generica nao tem o aviso de RDP - misturar os dois contratos foi um risco real identificado no plano da fusao'
    }
}
