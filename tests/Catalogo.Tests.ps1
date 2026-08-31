# Testes do catalogo fundido (Debloat/Faxina/Tudo) — extraem o literal via AST e
# avaliam isolado, sem rodar o resto do script (funciona em qualquer SO/Docker).
# Fase 2: catalogo tem so os 11 itens portados do WinFaxina; Fase 3 adiciona
# Apps/Telemetria/Desempenho (Debloat) — ver CLAUDE.md.

BeforeAll {
    $script:CaminhoScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'CaixaDeFerramentasWindows.ps1'
    $tokens = $null; $erros = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CaminhoScript, [ref]$tokens, [ref]$erros)
    $script:Conteudo = Get-Content -Path $script:CaminhoScript -Raw

    $atribuicao = $script:Ast.FindAll({
            param($no)
            $no -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $no.Left.Extent.Text -eq '$script:Catalogo'
        }, $true) | Select-Object -First 1
    $script:Catalogo = @()
    if ($atribuicao) {
        $script:Catalogo = @([scriptblock]::Create($atribuicao.Right.Extent.Text).Invoke())
    }
}

Describe 'Regras herdadas do WinFaxina (validas para o catalogo inteiro)' {
    It 'nao tem item de catalogo para a pasta Prefetch (Microsoft desaconselha limpeza manual)' {
        $item = $script:Catalogo | Where-Object { $_.Id -match 'prefetch' -or $_.Descricao -match 'Prefetch' }
        $item | Should -BeNullOrEmpty
    }

    It 'usa aspas simples ao redor de $PatchCache$ (evita o bug de interpolacao original)' {
        $aspa = [char]39
        $padraoEsperado = $aspa + 'Installer\$PatchCache$' + $aspa
        $script:Conteudo.Contains($padraoEsperado) | Should -BeTrue
    }

    It 'toda chamada a ConvertTo-Json especifica -Depth (padrao do PS 5.1 trunca aninhamento sem aviso)' {
        $chamadas = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.CommandAst] -and
                $no.GetCommandName() -eq 'ConvertTo-Json'
            }, $true)
        $chamadas.Count | Should -BeGreaterThan 0
        foreach ($chamada in $chamadas) {
            $temDepth = $chamada.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Depth'
            }
            $temDepth | Should -Not -BeNullOrEmpty -Because "chamada '$($chamada.Extent.Text)' precisa de -Depth explicito"
        }
    }

    It 'todo item com Tipo=Especial tem um case correspondente em Invoke-ItemCatalogo e em Get-AcaoDescricao' {
        # Guarda mecanica contra a classe de bug real ja encontrada no WinFaxina: um
        # item novo (fila-impressao) ficou sem case em Get-AcaoDescricao por varias
        # sessoes sem nenhum teste pegar, porque a guarda original so cobria o
        # dispatcher de execucao. Alargada desde a origem aqui — cobre os dois.
        $alvosCatalogo = @($script:Catalogo | Where-Object { $_.Tipo -eq 'Especial' } | ForEach-Object { $_.Alvo })

        foreach ($nomeFuncao in @('Invoke-ItemCatalogo', 'Get-AcaoDescricao')) {
            $funcao = $script:Ast.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq $nomeFuncao
                }, $true) | Select-Object -First 1
            $funcao | Should -Not -BeNullOrEmpty -Because "a funcao '$nomeFuncao' precisa existir"

            $switchInterno = $funcao.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.SwitchStatementAst] -and
                    $no.Condition.Extent.Text -match '\$Item\.Alvo'
                }, $true) | Select-Object -First 1
            $switchInterno | Should -Not -BeNullOrEmpty -Because "'$nomeFuncao' precisa ter um switch sobre `$Item.Alvo"

            $casesDispatcher = @($switchInterno.Clauses | ForEach-Object { $_.Item1.Value })

            foreach ($alvo in $alvosCatalogo) {
                $casesDispatcher | Should -Contain $alvo -Because "item Especial com Alvo='$alvo' precisa de um case em '$nomeFuncao'"
            }
        }
    }
}

Describe 'Catalogo' {
    It 'foi extraido do script' {
        $script:Catalogo.Count | Should -BeGreaterThan 5
    }

    It 'tem Ids unicos' {
        $ids = $script:Catalogo | ForEach-Object { $_.Id }
        ($ids | Sort-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'tem os campos obrigatorios em todos os itens' {
        foreach ($item in $script:Catalogo) {
            $item.Id | Should -Not -BeNullOrEmpty
            $item.Categoria | Should -Not -BeNullOrEmpty
            $item.Tipo | Should -Not -BeNullOrEmpty
            $item.Descricao | Should -Not -BeNullOrEmpty
            $item.Nivel | Should -Not -BeNullOrEmpty
        }
    }

    It 'usa apenas Categorias do esquema fundido (7 - ver CLAUDE.md, mesmo antes de Apps/Telemetria/Desempenho terem itens)' {
        $validas = @('Apps', 'Telemetria', 'Desempenho', 'Temporarios', 'Navegadores', 'Sistema', 'Lixeira')
        foreach ($item in $script:Catalogo) {
            $validas | Should -Contain $item.Categoria
        }
    }

    It 'usa apenas Tipos do esquema fundido (Appx/Servico/Registro/TarefaAgendada chegam na Fase 3)' {
        $validos = @('Appx', 'Servico', 'Registro', 'TarefaAgendada', 'LimpezaPasta', 'Especial')
        foreach ($item in $script:Catalogo) {
            $validos | Should -Contain $item.Tipo
        }
    }

    It 'usa apenas Niveis conhecidos (Seguro/Opcional/Agressivo)' {
        $validos = @('Seguro', 'Opcional', 'Agressivo')
        foreach ($item in $script:Catalogo) {
            $validos | Should -Contain $item.Nivel
        }
    }

    It 'SistemasAlvo, quando presente, nunca e um array vazio' {
        # Mesma classe de bug ja corrigida uma vez neste projeto (StartupAppsNinja:
        # Test-BuildValidado precisou parar de ser [Parameter(Mandatory)] porque um
        # array vazio explicito quebra o binding obrigatorio). Aqui a regra e de
        # dados, nao de parametro: ausente/$null = os dois SOs: nunca @().
        foreach ($item in $script:Catalogo) {
            $temPropriedade = $item.PSObject.Properties.Name -contains 'SistemasAlvo'
            if ($temPropriedade -and $null -ne $item.SistemasAlvo) {
                @($item.SistemasAlvo).Count | Should -BeGreaterThan 0 -Because "item '$($item.Id)' declarou SistemasAlvo vazio em vez de omitir o campo"
            }
        }
    }

    It 'a Lixeira (irreversivel) nao e nivel Seguro' {
        $item = $script:Catalogo | Where-Object { $_.Id -eq 'lixeira' }
        $item | Should -Not -BeNullOrEmpty
        $item.Nivel | Should -Not -Be 'Seguro'
    }

    It 'o PatchCache (pode exigir midia original para reparo) e nivel Agressivo' {
        $item = $script:Catalogo | Where-Object { $_.Id -eq 'patch-cache' }
        $item | Should -Not -BeNullOrEmpty
        $item.Nivel | Should -Be 'Agressivo'
    }

    It 'a fila de impressao e categoria Sistema, tipo Especial, nivel Seguro' {
        $item = $script:Catalogo | Where-Object { $_.Id -eq 'fila-impressao' }
        $item | Should -Not -BeNullOrEmpty
        $item.Categoria | Should -Be 'Sistema'
        $item.Tipo | Should -Be 'Especial'
        $item.Nivel | Should -Be 'Seguro'
    }

    It 'perfis formam uma cadeia: ha itens em todos os niveis' {
        @($script:Catalogo | Where-Object { $_.Nivel -eq 'Seguro' }).Count | Should -BeGreaterThan 0
        @($script:Catalogo | Where-Object { $_.Nivel -eq 'Opcional' }).Count | Should -BeGreaterThan 0
        @($script:Catalogo | Where-Object { $_.Nivel -eq 'Agressivo' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'CategoriasPorModo: -Modo pre-filtra Categorias (o "motor unico" do plano)' {
    BeforeAll {
        $noMapa = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $no.Left.Extent.Text -eq '$script:CategoriasPorModo'
            }, $true) | Select-Object -First 1
        $noMapa | Should -Not -BeNullOrEmpty -Because 'a atribuicao de $script:CategoriasPorModo precisa existir no script'

        # AssignmentStatementAst.Right NAO e o HashtableAst diretamente - e um
        # PipelineAst/CommandExpressionAst envolvendo ele (subtileza real da AST,
        # confirmada empiricamente aqui: .Right.KeyValuePairs voltava $null sem erro
        # nenhum, porque acesso a propriedade inexistente em PowerShell nao-strict
        # nao lanca excecao - so silenciosamente vira $null). .Find() desce a arvore
        # ate achar o HashtableAst de verdade.
        $hashtableAst = $noMapa.Right.Find({
                param($no)
                $no -is [System.Management.Automation.Language.HashtableAst]
            }, $true)
        $hashtableAst | Should -Not -BeNullOrEmpty -Because 'o valor atribuido a $script:CategoriasPorModo precisa ser um hashtable literal'

        # Extrai cada entrada do hashtable isoladamente via HashtableAst.KeyValuePairs
        # (mesma API ja usada para clauses de switch neste projeto - Item1=chave,
        # Item2=valor). Faxina/Debloat sao literais autocontidos, avaliam direto. Tudo
        # referencia $script:Categorias (definida em outra atribuicao) - ver teste
        # proprio abaixo para o motivo de nao tentar avaliar essa referencia aqui.
        $script:EntradasMapa = @{}
        foreach ($par in $hashtableAst.KeyValuePairs) {
            $script:EntradasMapa[$par.Item1.Value] = $par.Item2.Extent.Text
        }
        $script:CategoriasFaxina = [scriptblock]::Create($script:EntradasMapa['Faxina']).Invoke()
        $script:CategoriasDebloat = [scriptblock]::Create($script:EntradasMapa['Debloat']).Invoke()
    }

    It 'Faxina so cobre as categorias herdadas do WinFaxina' {
        $script:CategoriasFaxina | Should -Be @('Temporarios', 'Navegadores', 'Sistema', 'Lixeira')
    }

    It 'Debloat reserva as categorias que a Fase 3 vai preencher' {
        $script:CategoriasDebloat | Should -Be @('Apps', 'Telemetria', 'Desempenho', 'Sistema')
    }

    It 'Sistema e a unica categoria que Faxina e Debloat compartilham de proposito' {
        # Nao e um erro os dois modos apontarem para "Sistema" - e a mesma categoria
        # do esquema fundido para ajustes de sistema de qualquer origem (cache de
        # update/DISM/spooler do lado Faxina; tweaks de registro/servico do lado
        # Debloat na Fase 3). O invariante real e no ITEM (Id unico, ja coberto em
        # 'Catalogo'), nao na categoria - varios modos podem apontar pra mesma
        # categoria sem que isso duplique nenhum item.
        $intersecao = @($script:CategoriasFaxina | Where-Object { $script:CategoriasDebloat -contains $_ })
        $intersecao | Should -Be @('Sistema')
    }

    It 'Tudo referencia $script:Categorias por construcao, nao duplica a lista a mao (evita drift)' {
        # Avaliar isso por VALOR exigiria resolver, num [scriptblock] isolado, uma
        # referencia a uma variavel definida noutra atribuicao do arquivo - em teste
        # anterior isso se mostrou nao confiavel (o valor voltava $null mesmo
        # combinando as duas atribuicoes numa unica invocacao: escopo de
        # [scriptblock]::Create(...).Invoke() para $script: nao e o mesmo de
        # dot-sourcing). O que realmente importa aqui e estrutural, nao de valor: que
        # Tudo nunca seja reescrito como uma lista solta (que poderia divergir de
        # $script:Categorias silenciosamente) - conferir a expressao literal cobre
        # exatamente isso, sem depender daquela resolucao fragil.
        $script:EntradasMapa['Tudo'].Trim() | Should -Be '$script:Categorias'
    }

    It 'todo item do catalogo atual (Fase 2) cai dentro das categorias de Faxina' {
        # Confirma que o -Modo Faxina de fato mostra/seleciona os 11 itens de hoje -
        # e o teste que prova que o pre-filtro nao esta descartando nada indevidamente.
        foreach ($item in $script:Catalogo) {
            $script:CategoriasFaxina | Should -Contain $item.Categoria -Because "item '$($item.Id)' (categoria '$($item.Categoria)') deveria ser alcancavel via -Modo Faxina"
        }
    }
}
