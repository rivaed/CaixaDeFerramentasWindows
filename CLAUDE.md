# CaixaDeFerramentasWindows

Caixa de ferramentas unificada para Windows: junta Windows10-Debloat, Windows11-Debloat,
WinFaxina, StartupAppsNinja, SafeBoot-Ninja e ativar-win-admin num arquivo só. Os 6 repos
originais **continuam existindo e sendo mantidos separadamente** — esta caixa é uma 7ª
opção complementar para quem quer tudo junto, não uma substituição. Arquivo único, zero
dependências, Windows PowerShell 5.1 — mesmo padrão de todos os repos irmãos.

**Projeto construído em fases** (script final gira em torno de 3000+ linhas). Estado atual:
**Fase 1 e Fase 2 concluídas** (esqueleto + `-Modo Faxina` funcional, provando o motor
único de catálogo com os 11 itens do WinFaxina). Fases 3-5 pendentes — ver "Ordem de
execução" abaixo. Cada fase vira um push próprio para `main`; **só `-Modo Faxina`
executa lógica real** nesta versão — `Debloat`/`Tudo`/`Inicializacao`/`SafeBoot`/
`AdminOculto`/`Diagnostico` ainda saem com código 9 e aviso "ainda será implementado".

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

## Fusão do catálogo (Grupo A) — decisões já tomadas para a Fase 3

- **`temp-usuario`/`temp-sistema` colidem** entre Debloat e WinFaxina (mesmos Ids, mesmas
  pastas). Descartar as versões do Debloat (`Clear-TempPath`, só conta itens); manter as
  do WinFaxina (`Clear-PastaComRelatorio`, mede bytes antes/depois — cumpre a regra do
  projeto de nunca reportar OK sem medir efeito real). Categoria `Limpeza` do Debloat
  colapsa dentro de `Temporarios` do WinFaxina — **7 categorias no total**: Apps,
  Telemetria, Desempenho, Temporarios, Navegadores, Sistema, Lixeira.
- **`cdm` vira dois itens** (`cdm-w10`/`cdm-w11`): o nome do valor de registro difere de
  verdade entre W10 (`SubscribedContent-310093Enabled`) e W11
  (`SubscribedContent-353696Enabled`) — não dá para fundir num item só.
- **`bing-iniciar`/`widgets-botao` viram um item só cada**: os `Valores` são idênticos
  entre W10 e W11 (só a `Descricao` tinha drift de cópia entre os dois repos) — usar a
  `Descricao` mais precisa (a de `widgets-botao` do W10, "(se presente)").
- **`SistemasAlvo`**: campo opcional (`@('Win10')` | `@('Win11')` | ausente = os dois).
  **Nunca array vazio** — testar a distinção null-vs-vazio explicitamente. Mesma classe de
  bug que já mordeu este projeto (StartupAppsNinja: `Test-BuildValidado` precisou parar de
  ser `[Parameter(Mandatory)]` porque `@()` explícito quebra o binding obrigatório).
- **O literal do catálogo nunca lê nada calculado em runtime** (nem
  `$script:VersaoWindowsDetectada`, nem `$env:*` direto dentro de `Join-Path`/cmdlets) — os
  testes Pester extraem o literal via AST e avaliam isolado, sem rodar o resto do script
  nem detectar SO real. Regra herdada do WinFaxina: usar interpolação de string
  (`"$env:SystemRoot\X"`), nunca `Join-Path $env:SystemRoot 'X'` dentro do literal.
- Ao portar `Invoke-FaxinaItem`/`Get-AcaoDescricao` (ou seus equivalentes fundidos): todo
  item `Tipo=Especial` precisa de um `case` nos DOIS dispatchers (execução real E
  descrição sob `-Simular`) — bug real já corrigido uma vez no WinFaxina
  (`Get-AcaoDescricao` sem case para `FilaImpressao`; o teste mecânico só cobria o
  dispatcher de execução). Portar a versão já alargada do teste, cobrindo os dois.

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
- Mensagem de "reinicie o PC" (herdada do Debloat) deve ficar condicional a pelo menos um
  item `Appx`/`Servico`/`Registro`/`TarefaAgendada` ter sido executado — pendente para a
  Fase 3, não incondicional como no Debloat original.
- `Test-UsuarioDivergente` (aviso de sessão elevada como usuário diferente do interativo)
  hoje só existe no Debloat, mas o risco vale igual para WinFaxina — promover para rodar
  incondicionalmente no fluxo fundido (Fase 2/3).
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
3. Fundir Debloat10+Debloat11 no catálogo (ver seção acima); ligar `-Modo Debloat`/`Tudo`.
4. Portar Grupo B do mais seguro ao mais arriscado: Diagnostico → AdminOculto → SafeBoot →
   Inicializacao (o maior, mais crítico em segurança, por último).
5. `Show-MenuFerramentas`, passe completo de README/CONTRIBUTING/CHANGELOG, CI unindo as
   etapas reais dos 6 repos originais (uma etapa por modo), PSScriptAnalyzer, validação
   manual em VM nos 6 modos. **Remover a supressão temporária de `PSReviewUnusedParameter`
   no topo do `.ps1` nesta fase** — só faz sentido enquanto existem parâmetros de modos
   ainda não implementados.

## Verificação

- Sintaxe/Pester/PSScriptAnalyzer: Docker (`mcr.microsoft.com/powershell:lts-ubuntu-22.04
  --platform linux/amd64`), zero apontamentos antes de cada commit (com a supressão
  temporária documentada acima até a Fase 5).
- CI (GitHub Actions): cresce junto com o script — lint + Pester desde a Fase 1; uma etapa
  de execução real por modo é adicionada na mesma fase em que o modo é implementado.
- Antes de confiar em produção: VM Windows real, `-Simular` primeiro, depois
  `Minimo`/`Status`, nos 6 modos — mesma limitação já documentada nos 6 repos originais.

## Commits

Conventional Commits em pt-BR (`feat`, `fix`, `docs`, `test`, `chore`…), sem menção a IA.
CHANGELOG marca a entrada por modo quando a correção é isolada a um só (ex.:
`### [SafeBoot] Corrigido`) — evita que um bump de versão pareça relacionado a modos que
não mudaram.
