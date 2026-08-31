# Testes do modo Diagnostico (Grupo B - DiagnosticoRapidoDePC). Roda em qualquer SO
# (so valida estrutura/AST); Get-WinEvent contra o Visualizador de Eventos real so
# pode ser validado em execucao real (CI windows-latest / VM).

BeforeAll {
    $script:CaminhoScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'CaixaDeFerramentasWindows.ps1'
    $tokens = $null; $erros = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CaminhoScript, [ref]$tokens, [ref]$erros)
}

Describe 'Diagnostico: funcoes existem e nao elevam' {
    It 'Export-Relatorio e Export-RelatorioHtml existem' {
        foreach ($nome in @('Export-Relatorio', 'Export-RelatorioHtml')) {
            $funcao = $script:Ast.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq $nome
                }, $true) | Select-Object -First 1
            $funcao | Should -Not -BeNullOrEmpty -Because "'$nome' precisa existir"
        }
    }

    It 'o bloco do Modo Diagnostico nao chama Assert-Admin nem Start-Logging (familia somente-leitura)' {
        # Extrai o corpo do case 'Diagnostico' dentro do switch($Modo) principal e
        # confere que os dois nomes proibidos nao aparecem ali dentro - preserva o
        # comportamento original (DiagnosticoRapidoDePC nunca eleva, nunca loga em
        # arquivo, porque System/Application sao legiveis por usuario padrao).
        $switchModo = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.SwitchStatementAst] -and
                $no.Condition.Extent.Text -eq '$Modo'
            }, $true) | Select-Object -First 1
        $switchModo | Should -Not -BeNullOrEmpty

        $clauseDiagnostico = $switchModo.Clauses | Where-Object { $_.Item1.Extent.Text -eq "'Diagnostico'" } | Select-Object -First 1
        $clauseDiagnostico | Should -Not -BeNullOrEmpty -Because "precisa existir um case 'Diagnostico' no switch principal"

        # Comando de verdade (CommandAst), nao busca textual - um comentario
        # explicando "sem Assert-Admin" contem a palavra "Assert-Admin" e daria
        # falso positivo numa busca de texto/regex (achado ao rodar este teste).
        $chamadas = @($clauseDiagnostico.Item2.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.CommandAst]
                }, $true) | ForEach-Object { $_.GetCommandName() })
        $chamadas | Should -Not -Contain 'Assert-Admin' -Because 'Diagnostico nunca eleva'
        $chamadas | Should -Not -Contain 'Start-Logging' -Because 'Diagnostico nunca grava log em arquivo (so o CSV/HTML pedido)'
    }
}

Describe 'ConvertTo-Html: -Head/-Title/-PreContent/-PostContent so recebem string literal fixa' {
    # Guarda mecanica generica (nao especifica de Diagnostico, mas Diagnostico e o
    # primeiro modo deste arquivo fundido a usar ConvertTo-Html) - esses 4 parametros
    # NUNCA sao HTML-escapados pelo cmdlet; dado dinamico so pode entrar via -Body,
    # como saida ja escapada de "ConvertTo-Html -Fragment" (WebUtility.HtmlEncode
    # aplicado por celula). Mesma regra ja documentada no AuditaAdminsLocais desta
    # familia de projetos.
    It 'todo -Head/-Title/-PreContent/-PostContent em chamadas a ConvertTo-Html e string literal, nunca variavel' {
        $chamadas = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.CommandAst] -and
                $no.GetCommandName() -eq 'ConvertTo-Html'
            }, $true)
        $chamadas.Count | Should -BeGreaterThan 0 -Because 'Diagnostico precisa usar ConvertTo-Html para a exportacao HTML'

        $parametrosPerigosos = @('Head', 'Title', 'PreContent', 'PostContent')
        foreach ($chamada in $chamadas) {
            $elementos = @($chamada.CommandElements)
            for ($i = 0; $i -lt $elementos.Count; $i++) {
                $elemento = $elementos[$i]
                if ($elemento -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $parametrosPerigosos -contains $elemento.ParameterName) {
                    $argumento = $elementos[$i + 1]
                    $argumento | Should -Not -BeNullOrEmpty -Because "-$($elemento.ParameterName) precisa ter um valor"
                    $argumento | Should -BeOfType [System.Management.Automation.Language.StringConstantExpressionAst] `
                        -Because "-$($elemento.ParameterName) so pode ser string literal fixa (aspas simples ou dupla sem interpolacao), nunca variavel - ConvertTo-Html nao escapa esses 4 parametros"
                }
            }
        }
    }
}
