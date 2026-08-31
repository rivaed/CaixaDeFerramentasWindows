# Testes do catalogo fundido (Debloat/Faxina/Tudo) — extraem o literal via AST e
# avaliam isolado, sem rodar o resto do script (funciona em qualquer SO/Docker).
# Fase 2 portou os 11 itens do WinFaxina; Fase 3 fundiu Windows10-Debloat +
# Windows11-Debloat (Apps/Telemetria/Desempenho) — ver CLAUDE.md.

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
    It 'nao tem item de LIMPEZA da pasta Prefetch (Microsoft desaconselha limpeza manual)' {
        # Restrito a Tipo=LimpezaPasta mirando a pasta - o item 'sysmain' (Servico,
        # desativa o servico SysMain/Superfetch, legitimo e ja no Windows10-Debloat
        # original) tem "Prefetch" na Descricao mas e uma coisa completamente
        # diferente de apagar a PASTA Prefetch; um match textual amplo demais em
        # Descricao ou Id daria falso positivo nele (achado ao rodar este teste
        # apos a fusao do catalogo do Debloat).
        $item = $script:Catalogo | Where-Object {
            $_.Tipo -eq 'LimpezaPasta' -and ($_.Id -match 'prefetch' -or $_.Alvo -match 'Prefetch')
        }
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

    It 'todo Tipo de item usado no catalogo tem um case no switch de nivel superior (por Tipo) em Invoke-ItemCatalogo e em Get-AcaoDescricao' {
        # Guarda irma da guarda de Especial/Alvo acima, mas um nivel acima: cobre o
        # caso de esquecer um Tipo INTEIRO (ex.: nunca ter adicionado o case 'Appx'),
        # nao so um Alvo especifico dentro de 'Especial'.
        $tiposCatalogo = @($script:Catalogo | ForEach-Object { $_.Tipo } | Sort-Object -Unique)

        foreach ($nomeFuncao in @('Invoke-ItemCatalogo', 'Get-AcaoDescricao')) {
            $funcao = $script:Ast.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq $nomeFuncao
                }, $true) | Select-Object -First 1
            $switchTipo = $funcao.FindAll({
                    param($no)
                    $no -is [System.Management.Automation.Language.SwitchStatementAst] -and
                    $no.Condition.Extent.Text -match '\$Item\.Tipo'
                }, $true) | Select-Object -First 1
            $switchTipo | Should -Not -BeNullOrEmpty -Because "'$nomeFuncao' precisa ter um switch sobre `$Item.Tipo"

            $casesTipo = @($switchTipo.Clauses | ForEach-Object { $_.Item1.Value })
            foreach ($tipo in $tiposCatalogo) {
                $casesTipo | Should -Contain $tipo -Because "Tipo='$tipo' presente no catalogo precisa de um case em '$nomeFuncao'"
            }
        }
    }

    It 'nenhum pacote Appx (Alvo) e referenciado por mais de um Id de catalogo' {
        # Id ja e garantido unico (teste acima); isso pega o erro adjacente: dois
        # Ids diferentes apontando sem querer pro MESMO pacote (copia colada errada
        # ao fundir os dois catalogos do Debloat).
        $alvosAppx = @($script:Catalogo | Where-Object { $_.Tipo -eq 'Appx' } | ForEach-Object { $_.Alvo })
        ($alvosAppx | Sort-Object -Unique).Count | Should -Be $alvosAppx.Count
    }

    It 'cdm-w10 e cdm-w11 existem, cada um so no seu SO, e so o nome do SubscribedContent difere entre eles' {
        # O motivo real desses serem DOIS itens (nao um so com SistemasAlvo ausente):
        # o NOME do valor de registro difere de verdade entre W10 e W11 (nao e so
        # drift de copia, como bing-iniciar/widgets-botao) - ver CLAUDE.md, Bloqueio A.
        $cdmW10 = $script:Catalogo | Where-Object { $_.Id -eq 'cdm-w10' }
        $cdmW11 = $script:Catalogo | Where-Object { $_.Id -eq 'cdm-w11' }
        $cdmW10 | Should -Not -BeNullOrEmpty
        $cdmW11 | Should -Not -BeNullOrEmpty
        $cdmW10.SistemasAlvo | Should -Be @('Win10')
        $cdmW11.SistemasAlvo | Should -Be @('Win11')

        $nomesW10 = @($cdmW10.Valores | ForEach-Object { $_.Nome } | Sort-Object)
        $nomesW11 = @($cdmW11.Valores | ForEach-Object { $_.Nome } | Sort-Object)
        $cdmW10.Valores.Count | Should -Be 10
        $cdmW11.Valores.Count | Should -Be 10
        $nomesW10 | Should -Contain 'SubscribedContent-310093Enabled'
        $nomesW11 | Should -Contain 'SubscribedContent-353696Enabled'

        # Os outros 9 valores (tudo exceto o SubscribedContent especifico do SO) sao
        # identicos nos dois - se algum dia divergirem sem querer, este teste pega.
        $compartilhadosW10 = @($nomesW10 | Where-Object { $_ -ne 'SubscribedContent-310093Enabled' } | Sort-Object)
        $compartilhadosW11 = @($nomesW11 | Where-Object { $_ -ne 'SubscribedContent-353696Enabled' } | Sort-Object)
        (Compare-Object $compartilhadosW10 $compartilhadosW11 -SyncWindow 0 | Measure-Object).Count | Should -Be 0
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

    It 'Debloat cobre Apps/Telemetria/Desempenho (sem Sistema)' {
        # Confirmado direto no codigo-fonte (Fase 3): nem Windows10-Debloat nem
        # Windows11-Debloat jamais tiveram uma categoria "Sistema" - so
        # Apps|Telemetria|Desempenho|Limpeza. "Sistema" e 100% origem WinFaxina
        # (update-cache/dism-cleanup/patch-cache/fila-impressao) - incluir Sistema
        # aqui faria -Modo Debloat tambem rodar essa faxina de disco, que nao e o
        # esperado (quem quer isso usa -Modo Faxina ou -Modo Tudo).
        $script:CategoriasDebloat | Should -Be @('Apps', 'Telemetria', 'Desempenho')
    }

    It 'Faxina e Debloat nao compartilham nenhuma categoria' {
        $intersecao = @($script:CategoriasFaxina | Where-Object { $script:CategoriasDebloat -contains $_ })
        $intersecao | Should -BeNullOrEmpty
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

    It 'todo item das 4 categorias de origem WinFaxina cai dentro de Faxina, nunca de Debloat' {
        $categoriasWinFaxina = @('Temporarios', 'Navegadores', 'Sistema', 'Lixeira')
        $itensWinFaxina = $script:Catalogo | Where-Object { $categoriasWinFaxina -contains $_.Categoria }
        $itensWinFaxina.Count | Should -BeGreaterThan 0
        foreach ($item in $itensWinFaxina) {
            $script:CategoriasFaxina | Should -Contain $item.Categoria -Because "item '$($item.Id)' deveria ser alcancavel via -Modo Faxina"
            $script:CategoriasDebloat | Should -Not -Contain $item.Categoria -Because "item '$($item.Id)' (origem WinFaxina) nao deveria aparecer em -Modo Debloat"
        }
    }

    It 'todo item das 3 categorias de origem Debloat cai dentro de Debloat, nunca de Faxina' {
        $categoriasDebloat = @('Apps', 'Telemetria', 'Desempenho')
        $itensDebloat = $script:Catalogo | Where-Object { $categoriasDebloat -contains $_.Categoria }
        $itensDebloat.Count | Should -BeGreaterThan 0
        foreach ($item in $itensDebloat) {
            $script:CategoriasDebloat | Should -Contain $item.Categoria -Because "item '$($item.Id)' deveria ser alcancavel via -Modo Debloat"
            $script:CategoriasFaxina | Should -Not -Contain $item.Categoria -Because "item '$($item.Id)' (origem Debloat) nao deveria aparecer em -Modo Faxina"
        }
    }
}

Describe 'Test-ItemAplicavelAoSO: filtro por SistemasAlvo (novo motor da Fase 3)' {
    BeforeEach {
        $funcAst = $script:Ast.FindAll({
                param($no)
                $no -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $no.Name -eq 'Test-ItemAplicavelAoSO'
            }, $true) | Select-Object -First 1
        Invoke-Expression $funcAst.Extent.Text
    }

    It 'item sem SistemasAlvo vale para qualquer SO detectado' {
        $item = [pscustomobject]@{ Id = 'x' }
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Win10' | Should -BeTrue
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Win11' | Should -BeTrue
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Desconhecido' | Should -BeTrue
    }

    It 'item com SistemasAlvo=Win10 so vale quando o SO detectado e Win10' {
        $item = [pscustomobject]@{ Id = 'x'; SistemasAlvo = @('Win10') }
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Win10' | Should -BeTrue
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Win11' | Should -BeFalse
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Desconhecido' | Should -BeFalse
    }

    It 'item com SistemasAlvo=Win11 so vale quando o SO detectado e Win11' {
        $item = [pscustomobject]@{ Id = 'x'; SistemasAlvo = @('Win11') }
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Win10' | Should -BeFalse
        Test-ItemAplicavelAoSO -Item $item -VersaoWindows 'Win11' | Should -BeTrue
    }
}
