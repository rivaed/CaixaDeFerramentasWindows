# CaixaDeFerramentasWindows

Caixa de ferramentas unificada para Windows: junta Windows10-Debloat, Windows11-Debloat,
WinFaxina, StartupAppsNinja, SafeBoot-Ninja e ativar-win-admin num arquivo só. Os 6 repos
originais **continuam existindo e sendo mantidos separadamente** — esta caixa é uma 7ª
opção complementar para quem quer tudo junto, não uma substituição. Arquivo único, zero
dependências, Windows PowerShell 5.1 — mesmo padrão de todos os repos irmãos.

**Projeto construído em fases** (script final gira em torno de 3000+ linhas). Estado atual:
**Fases 1-4 concluídas** — os 6 modos (catálogo fundido: `Faxina`/`Debloat`/`Tudo`; Grupo
B: `Diagnostico`/`AdminOculto`/`SafeBoot`/`Inicializacao`) todos funcionais. Falta só a
**Fase 5** (menu principal `Show-MenuFerramentas`, passe final de docs, remover a
supressão temporária de `PSReviewUnusedParameter`, CI consolidado). Cada modo/fase virou
um push próprio para `main`. Sem `-Modo`, o script ainda sai com código 9 até a Fase 5.

## Arquitetura: duas famílias, não uma

**Grupo A — catálogo único fundido**: Debloat10 + Debloat11 + WinFaxina. `-Modo Debloat|
Faxina|Tudo` compartilham UM motor de catálogo data-driven (`$script:Catalogo`, dispatcher
por `Tipo`, perfis Minimo/Completo/Agressivo). `-Modo` só pré-filtra `Categorias`.

**Grupo B — modo próprio por ferramenta**: `-Modo Inicializacao|SafeBoot|AdminOculto` usam
sua própria lógica portada quase como estava (itens descobertos em runtime, parâmetros
obrigatórios por invocação, seleção de estado mutuamente exclusivo — nenhum desses cabe
num catálogo estático). Só as funções compartilhadas (`Write-Log`, `Assert-Admin` etc.) são
deduplicadas. `-Modo Diagnostico` (DiagnosticoRapidoDePC) é Grupo B também: somente-leitura,
nunca eleva, nunca usa `Start-Logging`/transcript — preservar esse comportamento original.

Forçar Inicializacao/SafeBoot/AdminOculto num catálogo de itens seria abstração ruim, não
simplicidade — decisão já validada, não reabrir sem motivo novo.

## Colisões de nome já resolvidas (não reintroduzir)

- **Sem `-Acao` genérico.** Colidia entre StartupAppsNinja/SafeBoot-Ninja/ativar-win-admin,
  cada um com `ValidateSet` diferente. Resolvido com nomes por modo: `-AcaoInicializacao`,
  `-AcaoSafeBoot`, `-AcaoAdmin`. Teste mecânico (`Parametros.Tests.ps1`) garante que
  ninguém reintroduz um `-Acao` ambíguo.
- **`Show-MainMenu` existia 5x** (Debloat10/11, WinFaxina — mesma família — E TAMBÉM
  SafeBoot-Ninja e ativar-win-admin, sem relação nenhuma, só coincidência de nome).
  `Show-MainMenu` fica só para o catálogo fundido (Debloat/Faxina/Tudo); os outros viram
  `Show-MainMenuSafeBoot`, `Show-MainMenuAdmin`; o menu de topo novo é
  `Show-MenuFerramentas`.
- **`Confirm-Acao` tinha 2 contratos diferentes** (SafeBoot-Ninja: `param($Alvo)`, só
  interativo, aviso de RDP; StartupAppsNinja: `param($Descricao)`, trata interativo E
  `-NaoInterativo`/`-Confirmar`). A versão do StartupAppsNinja (mais completa) é a
  `Confirm-Acao` compartilhada (usada por Inicializacao e SafeBoot); a variante com aviso
  de RDP do SafeBoot vira `Confirm-AcaoSafeBoot` — não forçar o aviso extra para dentro da
  genérica.
- **Guarda mecânica obrigatória**: nenhum `FunctionDefinitionAst.Name` duplicado no arquivo
  inteiro (`Parametros.Tests.ps1`). Colar múltiplos scripts-fonte no mesmo arquivo faz a
  ÚLTIMA definição na ordem do arquivo vencer silenciosamente — sem isso, esse é o risco
  mecânico mais perigoso da fusão. Ao portar cada modo (Fase 2-4), rodar essa suíte antes
  de seguir para o próximo.

## Fusão do catálogo (Grupo A) — decisões da Fase 3 (feita)

- **`Debloat` NUNCA teve categoria `Sistema`** — confirmado direto no código-fonte dos
  dois scripts originais (`$script:Categorias = @('Apps', 'Telemetria', 'Desempenho',
  'Limpeza')` nos dois, sem exceção). `Sistema` é 100% origem WinFaxina. **Bug real
  cometido e corrigido na própria Fase 3**: `$script:CategoriasPorModo['Debloat']` tinha
  sido definido na Fase 1 como `@('Apps', 'Telemetria', 'Desempenho', 'Sistema')` — por
  suposição, antes de qualquer código do Debloat ter sido lido. Isso teria feito
  `-Modo Debloat` também rodar a faxina de disco do WinFaxina (DISM/patch-cache/spooler)
  sem pedir. Corrigido para `@('Apps', 'Telemetria', 'Desempenho')` antes do push desta
  fase. **Nunca reintroduzir `Sistema` em `CategoriasPorModo['Debloat']`** sem antes
  verificar que existe um item de catálogo de origem Debloat de verdade nessa categoria.
- **`temp-usuario`/`temp-sistema` colidiam** entre Debloat e WinFaxina (mesmos Ids, mesmas
  pastas). Descartadas as versões do Debloat (`Clear-TempPath`, só contava itens);
  mantidas as do WinFaxina (`Clear-PastaComRelatorio`, mede bytes antes/depois). Categoria
  `Limpeza` do Debloat colapsou dentro de `Temporarios` do WinFaxina — **7 categorias no
  total**: Apps, Telemetria, Desempenho, Temporarios, Navegadores, Sistema, Lixeira.
- **`cdm` virou dois itens** (`cdm-w10`/`cdm-w11`): o nome do valor de registro difere de
  verdade entre W10 (`SubscribedContent-310093Enabled`) e W11
  (`SubscribedContent-353696Enabled`) — os outros 9 valores são idênticos e ficam
  duplicados nos dois itens de propósito (`SistemasAlvo` garante que só o certo aparece).
- **`bing-iniciar`/`widgets-botao` viraram um item só cada**: os `Valores` eram idênticos
  entre W10 e W11 (só a `Descricao` tinha drift de cópia entre os dois repos) — usada a
  `Descricao` mais precisa de cada (a do W10 nos dois casos: "fora da BUSCA do menu
  Iniciar" é mais exata pro que `DisableSearchBoxSuggestions` faz; "(se presente)" no
  Widgets é mais correto, já que a presença do botão varia em ambas as versões).
- **`extensoes-arquivo` era idêntico byte a byte** nos dois scripts-fonte — nenhuma
  decisão a tomar, só um item.
- **Todo o resto de Apps/Telemetria/Desempenho que existe em só um dos dois scripts
  ganhou `SistemasAlvo` correspondente** (16 exclusivos de Win10, 15 exclusivos de Win11,
  mais `cortana-politica`=Win10 e `copilot-politica`/`recall`=Win11 em Telemetria, e 5
  serviços exclusivos de Win10 + `menu-contexto` exclusivo de Win11 em Desempenho) — a
  curadoria de CADA script original foi tratada como autoritativa pro seu próprio SO, sem
  tentar adivinhar se um item Win10-only também funcionaria no Win11 (ou vice-versa).
- **`SistemasAlvo`**: campo opcional (`@('Win10')` | `@('Win11')` | ausente = os dois).
  **Nunca array vazio** — testado explicitamente. Mesma classe de bug que já mordeu este
  projeto (StartupAppsNinja: `Test-BuildValidado` precisou parar de ser
  `[Parameter(Mandatory)]` porque `@()` explícito quebra o binding obrigatório). Filtrado
  por `Test-ItemAplicavelAoSO` (função própria — reusada em `Get-ItensDoPerfil`/
  `Get-ContagemCategoria`/`Show-CategoryMenu`, não copiada 3x).
- **O literal do catálogo nunca lê nada calculado em runtime** (nem
  `$script:VersaoWindowsDetectada`, nem `$env:*` direto dentro de `Join-Path`/cmdlets) — os
  testes Pester extraem o literal via AST e avaliam isolado, sem rodar o resto do script
  nem detectar SO real. Regra herdada do WinFaxina: usar interpolação de string
  (`"$env:SystemRoot\X"`), nunca `Join-Path $env:SystemRoot 'X'` dentro do literal.
- `Invoke-ItemCatalogo`/`Get-AcaoDescricao` ganharam um segundo nível de guarda mecânica
  na Fase 3: além do `case` por `Alvo` dentro de `Especial` (já existia), agora também
  testa que todo `Tipo` usado no catálogo (`Appx`/`Servico`/`Registro`/`TarefaAgendada`/
  `LimpezaPasta`/`Especial`) tem um `case` no switch de nível superior nos DOIS
  dispatchers — pega o erro de esquecer um Tipo inteiro, não só um Alvo dentro de
  Especial.
- `Invoke-Selecao` (motor compartilhado) ganhou a chamada a `Get-InventarioAppx` (uma vez
  antes do loop, só se a seleção tiver algum item `Tipo=Appx` e não estiver em
  `-Simular`) — fica no motor, não em cada `-Modo` chamador, pra nenhum modo futuro com
  itens Appx esquecer de preparar isso.

## Decisões de fusão de funções compartilhadas

- **`Write-Log`**: versão de 6 níveis (Debloat/WinFaxina, inclui `Simulacao`) — já é o que
  está neste arquivo, supraconjunto puro da versão de 5 níveis dos outros 3 scripts.
- **`Assert-Admin`**: versão completa do Debloat (checagem PS7→5.1 + relançamento) rodando
  em TODOS os modos, mesmo os que originalmente não precisavam — `ativar-win-admin` usa
  `Microsoft.PowerShell.LocalAccounts`, que tem o mesmo perfil de instabilidade em PS7 que
  o módulo Appx (motivo original da checagem). Exclusão de `-SenhaSegura` do
  relançamento é por TIPO (`-is [System.Security.SecureString]`), não por nome — cobre
  qualquer `SecureString` futuro automaticamente. Já implementado.
- **`Start-Logging`**: forma com `-CaminhoPersonalizado` (StartupAppsNinja). Pasta de log
  compartilhada (`%ProgramData%\CaixaDeFerramentasWindows\logs\`), mas prefixo de arquivo
  POR MODO (`debloat_`, `faxina_`, `startup_`, `safeboot_`, `admin_`) via `-Prefixo`
  derivado de `$Modo` — sem isso, ninguém sabe qual modo escreveu qual log numa pasta
  compartilhada. `Diagnostico` não chama `Start-Logging` (preserva comportamento original).
- **Elevação não é incondicional no topo do script** — `Assert-Admin` é chamado de dentro
  do handler de cada modo, depois de `$Modo` resolvido, e nunca no modo `Diagnostico`.
- **Risco de `-WhatIf` vazar para modos que não o tratam**: `SupportsShouldProcess = $true`
  expõe `-WhatIf` como parâmetro comum em QUALQUER modo, mesmo os que nunca checam
  `$WhatIfPreference` (SafeBoot/Inicializacao/AdminOculto executariam de verdade mesmo com
  `-WhatIf`). Mitigado: aviso explícito já implementado no fluxo principal quando
  `$WhatIfPreference` é verdadeiro e `$Modo` não é Debloat/Faxina/Tudo.

## Outras correções que "pegam carona" na fusão

- `Get-VersaoWindows`/`ConvertTo-VersaoWindows` checa `ProductType -eq 1` (workstation) de
  forma consistente nos dois SOs — o `Assert-Windows10` original (Windows10-Debloat) tinha
  um gap real aqui (só checava o build, passaria hoje num Windows Server com build na
  faixa 10240-21999). Já corrigido e coberto por teste de fixture (incluindo o caso
  Server-com-build-de-Win10/11, que é a regressão específica desse gap).
- Mensagem de "reinicie o PC" (herdada do Debloat, era incondicional lá): **feito na Fase
  3** — só aparece se pelo menos um item `Appx`/`Servico`/`Registro`/`TarefaAgendada` com
  `Status` `Ok`/`Parcial` foi executado (uma sessão só-de-limpeza não pede reinício à toa).
- `Test-UsuarioDivergente` (aviso de sessão elevada como usuário diferente do interativo):
  **feito na Fase 3** — promovida pra rodar em qualquer `-Modo` do Grupo A
  (`Debloat`/`Faxina`/`Tudo`), não só quando era originalmente do Debloat.
- Menu de categorias: usar `'^\d{1,2}$'` (não `'^\d$'`) — com Limpeza colapsada em
  Temporarios ficam 7 categorias (cabe em 1 dígito), mas sem folga para uma 8ª.

## Convenções herdadas (WinFaxina/AuditaAdminsLocais) que se aplicam aqui também

- UTF-8 **com BOM** obrigatório no `.ps1` — 5.1 lê sem BOM como ANSI e quebra acentos.
- Toda chamada a `ConvertTo-Json` precisa de `-Depth` explícito (padrão do 5.1 trunca em 2).
- `ConvertTo-Html`: `-Head`/`-Title`/`-PreContent`/`-PostContent` só recebem string literal
  fixa — nunca dado dinâmico (não é HTML-escapado pelo cmdlet). Dado dinâmico só via
  `-Body`, como saída de `ConvertTo-Html -Fragment` (aí sim escapado por
  `WebUtility.HtmlEncode`). Aplica-se se/quando o modo `Diagnostico` for portado com
  export HTML.
- HRESULT: converter hex para Int32 assinado sempre via `[int]0xHEXLITERAL` — nunca
  calcular o decimal à mão (classe de erro já cometida nesta sessão).

## Ordem de execução (ver plano completo salvo fora do repo, em
`~/.claude/plans/tempos-atras-fiz-o-sharded-ritchie.md`, para o raciocínio completo)

0. ~~Corrigir bug do `Get-AcaoDescricao` no WinFaxina~~ — feito, fora deste repo (branch
   `fix/get-acao-descricao-fila-impressao`, ainda não mesclada em main daquele repo —
   aguarda instrução explícita de push, por convenção da sessão).
1. ~~Esqueleto: param() fundido, funções compartilhadas, `Get-VersaoWindows`~~ — **feito**.
2. ~~Provar o modelo "um motor, `-Modo` pré-filtra `Categorias`" só com os 11 itens do
   WinFaxina (`-Modo Faxina`)~~ — **feito**. `Invoke-FaxinaItem` foi renomeado para
   `Invoke-ItemCatalogo` (nome neutro — a Fase 3 estende o MESMO dispatcher com os
   tipos do Debloat, não cria um novo). `$script:CategoriasPorModo` já existe com as
   3 chaves (`Faxina`/`Debloat`/`Tudo`) — Fase 3 só precisa preencher o catálogo, não
   mexer no mecanismo de filtro.
3. ~~Fundir Debloat10+Debloat11 no catálogo (ver seção acima); ligar `-Modo Debloat`/
   `Tudo`~~ — **feito**. 66 itens novos, `SistemasAlvo`/`Test-ItemAplicavelAoSO` novos no
   motor, guarda de dispatcher por Tipo alargada, CI com execução real de `-Modo Debloat`.
4. Portar Grupo B do mais seguro ao mais arriscado: Diagnostico → AdminOculto → SafeBoot →
   Inicializacao (o maior, mais crítico em segurança, por último).
   - ~~Diagnostico~~ — **feito**. `Export-Relatorio`/`Export-RelatorioHtml` portadas,
     nunca eleva/nunca loga em arquivo (preservado e coberto por teste AST). Nova guarda
     mecânica genérica de `ConvertTo-Html` (`-Head`/`-Title`/`-PreContent`/`-PostContent`
     só string literal) — vale para qualquer modo futuro que use o cmdlet, não só este.
   - ~~AdminOculto~~ — **feito**. `Get-ContaAdminEmbutida`/`Get-EstadoConta`/
     `Read-SenhaConfirmada`/`Enable-ContaAdmin`/`Disable-ContaAdmin` portadas verbatim;
     `Show-MainMenu` renomeado para `Show-MainMenuAdmin` (colisão já prevista). Sempre
     eleva (coberto por teste AST). Fixture testa a regra inegociável "nunca ativa com
     senha vazia" isolando `Enable-ContaAdmin` (o guard de `Length -eq 0` é a primeira
     linha, antes de qualquer `Get-LocalUser` — seguro de extrair/chamar sem tocar no
     sistema de contas real).
   - ~~SafeBoot~~ — **feito**. `Get-EstadoSafeBoot`/`Set-SafeBoot`/`Show-AvisoCritico`
     portadas verbatim; `Confirm-Acao` original (RDP) virou `Confirm-AcaoSafeBoot`
     (Bloqueio B do plano resolvido — coberto por teste que confirma o bloco do modo
     NUNCA chama a `Confirm-Acao` genérica, só a própria); `Show-MainMenu` virou
     `Show-MainMenuSafeBoot`. `Set-SafeBoot` relê o estado real após `bcdedit`, nunca
     confia só no exit code (coberto por teste AST).
   - ~~Inicializacao~~ — **feito** (última do Grupo B, portada por último de propósito).
     `Confirm-Acao` genérica confirmada como já sendo a versão deste modo (origem desde a
     Fase 1, nenhuma mudança necessária). As 5 camadas de segurança do toggle
     `Habilitar`/`Desabilitar` via `StartupApproved` preservadas: gate de
     `-PermitirExperimental` primeiro (antes de qualquer `Get-CimInstance`, coberto por
     teste AST), checagem de build contra `$script:BuildsValidados` (vazio de propósito),
     só o byte 0 é escrito preservando os outros 11, releitura confirma antes de reportar
     sucesso. `Test-BuildValidado` (a correção do bug `Mandatory`+array vazio) coberta por
     fixture regressiva. CI prova um round-trip real de Adicionar+Remover contra HKCU do
     próprio runner — não só leitura.
5. `Show-MenuFerramentas`, passe completo de README/CONTRIBUTING/CHANGELOG, CI unindo as
   etapas reais dos 6 repos originais (uma etapa por modo), PSScriptAnalyzer, validação
   manual em VM nos 6 modos. **Remover a supressão temporária de `PSReviewUnusedParameter`
   no topo do `.ps1` nesta fase** — só faz sentido enquanto existem parâmetros de modos
   ainda não implementados.

## Verificação

- Sintaxe/Pester/PSScriptAnalyzer: Docker (`mcr.microsoft.com/powershell:lts-ubuntu-22.04
  --platform linux/amd64`), zero apontamentos antes de cada commit (com a supressão
  temporária documentada acima até a Fase 5).
- **Achado real da Fase 4 (AdminOculto), sobre a ORDEM dentro do comando Docker**: rodar
  `[System.Management.Automation.Language.Parser]::ParseFile(...)` ANTES de
  `Set-PSRepository`/`Install-Module` faz `Get-PSRepository -Name PSGallery` falhar com
  "Unable to find repository" de forma consistente e reproduzível (não é flake de rede -
  confirmado com `Get-PSRepository | Format-List` funcionando isolado, e o mesmo comando
  falhando quando precedido pelo ParseFile, no mesmo container/mount). Causa exata não
  investigada a fundo (suspeita: alguma interação entre carregar os tipos de
  `Language.Parser` e o bootstrap lazy do provider NuGet do PackageManagement), mas a
  ordem importa: **sempre instalar Pester/PSScriptAnalyzer (e configurar o PSGallery)
  ANTES de qualquer `ParseFile`/uso de `System.Management.Automation.Language` no mesmo
  comando Docker** — nunca o contrário. Também: comandos Docker em background NÃO herdam
  `cd` de uma chamada anterior separada (mesmo foreground) — sempre prefixar com
  `cd <caminho-absoluto-do-repo> &&` explícito, mesmo que pareça redundante.
- **Achado real da Fase 4 (Inicializacao), sobre escopo do Pester 5 ao extrair funções via
  AST + `Invoke-Expression`** (o padrão usado em todo `*.Tests.ps1` deste projeto para
  testar funções puras com fixture, sem rodar o script inteiro): (1) uma função declarada
  solta no topo de um arquivo `.Tests.ps1`, **fora** de `Describe`/`BeforeAll`, só existe
  na fase de Discovery do Pester 5 — some antes da fase de Run, onde `BeforeEach`/`It`
  realmente executam (`CommandNotFoundException`). Sempre declarar dentro de um
  `BeforeAll` de nível superior. (2) Mais sutil: se esse `Invoke-Expression
  $funcAst.Extent.Text` (o que DEFINE a função extraída) roda **dentro de uma função
  helper própria** (ex.: um `Import-FuncaoIsolada` chamado de dentro do `BeforeEach`), a
  função recém-definida fica presa no escopo local do helper e desaparece assim que ele
  retorna — mesmo sintoma (`CommandNotFoundException`), causa diferente. O padrão correto,
  já usado em `Parametros.Tests.ps1`/`Catalogo.Tests.ps1`: `Invoke-Expression` direto no
  corpo do `BeforeEach`, nunca indireto via outra função. Um helper que só devolve o
  **texto** da função (sem executar `Invoke-Expression`) é seguro de chamar através de
  função normal — só a definição em si precisa ficar no nível certo.
- CI (GitHub Actions): cresce junto com o script — lint + Pester desde a Fase 1; uma etapa
  de execução real por modo é adicionada na mesma fase em que o modo é implementado.
- **Achado real da Fase 2, confirmado em execução real no runner**: o `windows-latest`
  do GitHub Actions relata `VersaoWindowsDetectada=Desconhecido` (não é `ProductType=1`
  de workstation Win10/11 de verdade). Não é bug — `Assert-VersaoSuportada` avisa e
  segue em frente porque a etapa de CI roda com `-Simular`; NÃO adicionar uma asserção
  de `VersaoWindowsDetectada` no CI esperando `Win10`/`Win11` (quebraria à toa, mesma
  classe de cuidado já documentada no `AuditaAdminsLocais` para `Status=Inalcancavel`).
- Antes de confiar em produção: VM Windows real, `-Simular` primeiro, depois
  `Minimo`/`Status`, nos 6 modos — mesma limitação já documentada nos 6 repos originais.

## Commits

Conventional Commits em pt-BR (`feat`, `fix`, `docs`, `test`, `chore`…), sem menção a IA.
CHANGELOG marca a entrada por modo quando a correção é isolada a um só (ex.:
`### [SafeBoot] Corrigido`) — evita que um bump de versão pareça relacionado a modos que
não mudaram.
