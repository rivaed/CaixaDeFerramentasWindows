# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.1.0] — não lançado

### Adicionado
- **[SafeBoot]** Modo `-Modo SafeBoot` funcional: liga/desliga o Modo de Segurança
  (mínimo/com rede) via `bcdedit`, sempre **relendo o estado real** depois de aplicar
  (nunca confia só no exit code). Resolvido o Bloqueio B do plano: `Confirm-Acao`
  original do SafeBoot-Ninja (`param($Alvo)`, aviso próprio de RDP) virou
  `Confirm-AcaoSafeBoot` — **não** foi colapsada na `Confirm-Acao` genérica
  (`param($Descricao)`, usada por Inicializacao), contratos diferentes de propósito.
  `Show-MainMenu` original renomeado para `Show-MainMenuSafeBoot`. Aviso crítico
  preservado: nem Mínimo nem Rede iniciam RDP — quem só tem acesso remoto pode ficar
  sem acesso até alguém com acesso físico desfazer a mudança.
- **[AdminOculto]** Modo `-Modo AdminOculto` funcional: ativa/desativa a conta
  Administrador embutida, identificada **sempre pelo SID** (termina em `-500`), nunca por
  nome (varia por idioma do Windows). Regra inegociável preservada e testada: nunca ativa
  a conta com senha vazia (`Enable-ContaAdmin` recusa antes de tocar em `Get-LocalUser`).
  `Show-MainMenu` original renomeado para `Show-MainMenuAdmin` (colisão de nome já prevista
  na Fase 1). Sempre eleva — `Set-LocalUser`/`Enable-LocalUser` exigem admin.
- **[Diagnostico]** Modo `-Modo Diagnostico` funcional (primeiro modo do Grupo B, portado
  quase como estava, arquiteturalmente independente do motor de catálogo): 6 verificações
  fixas no Visualizador de Eventos (desligamento sujo/Kernel-Power, desligamento
  inesperado, erro de disco, timeout storport, erro WHEA, falha de aplicativo), exportação
  CSV e HTML, menu interativo `[C]SV/[H]TML/[A]mbos/[N]ao`. **Nunca eleva, nunca grava log
  em arquivo** — System/Application são legíveis por usuário padrão; preservado do
  original e agora coberto por teste mecânico (procura chamadas reais a `Assert-Admin`/
  `Start-Logging` via AST, não busca de texto — evita falso positivo em comentário).
- **[Diagnostico]** Nova guarda mecânica genérica: toda chamada a `ConvertTo-Html` no
  arquivo tem `-Head`/`-Title`/`-PreContent`/`-PostContent` verificados como string
  literal fixa via AST (nunca variável) — regra já documentada em CLAUDE.md desde a Fase
  1, mas só ganhou teste de verdade agora que `Diagnostico` é o primeiro modo a usar o
  cmdlet.
- **[Debloat]** Modo `-Modo Debloat`/`-Modo Tudo` funcionais: fusão dos catálogos do
  Windows10-Debloat e Windows11-Debloat (66 itens novos: 46 Apps, 11 Telemetria, 9
  Desempenho) no mesmo motor único do `-Modo Faxina`. Novidades no motor: campo
  `SistemasAlvo` (opcional; ausente = vale para os dois SOs) filtrado por
  `Test-ItemAplicavelAoSO`, agora usado em `Get-ItensDoPerfil`/`Initialize-Selecao`/
  `Get-ContagemCategoria`/`Show-CategoryMenu`/`Show-MainMenu`; novos executores
  (`Remove-BloatApp`, `Disable-BloatService`, `Set-RegistryTweak`,
  `Disable-BloatScheduledTask`, `Set-VisualEffectsPerformance`, `Remove-OneDriveApp`,
  `Disable-RecallFeature`, `Get-InventarioAppx`); `Invoke-Selecao` agora inventaria
  pacotes Appx uma vez antes do loop quando a seleção inclui algum; mensagem de
  "reinicie o PC" ficou condicional a pelo menos um item `Appx`/`Servico`/`Registro`/
  `TarefaAgendada` ter sido executado (antes incondicional no Debloat original);
  `Test-UsuarioDivergente` promovida para rodar em todos os modos que elevam (antes
  só existia no Debloat) — corrige de graça o mesmo risco para quem só usa Faxina.
- **[Debloat]** Resolvido o Bloqueio A do plano: `temp-usuario`/`temp-sistema` do
  Debloat foram descartados (colidiam com os do WinFaxina); `cdm` virou dois itens
  (`cdm-w10`/`cdm-w11`, `SistemasAlvo` correspondente) porque o NOME do valor de
  registro difere de verdade entre os dois SOs (`SubscribedContent-310093Enabled` vs.
  `-353696Enabled`), não é só drift de cópia; `bing-iniciar`/`widgets-botao` viraram
  item único cada (Valores idênticos nos dois scripts-fonte, só a Descrição tinha
  drift de cópia entre os repos).
- **[Debloat]** **Correção antes de qualquer execução real**: `Debloat` não tem —
  nunca teve — a categoria `Sistema` (confirmado direto no código-fonte: os dois
  scripts originais só usam `Apps|Telemetria|Desempenho|Limpeza`). O
  `$script:CategoriasPorModo['Debloat']` definido na Fase 1 incluía `Sistema` por
  suposição, antes de qualquer código do Debloat ter sido lido — isso teria feito
  `-Modo Debloat` também rodar a faxina de disco do WinFaxina (DISM/patch-cache/
  spooler) sem pedir. Corrigido para `@('Apps', 'Telemetria', 'Desempenho')` antes do
  primeiro push desta fase; pego pela própria suíte de testes ao revisar a
  intersecção Faxina×Debloat, não por execução em produção.
- **[Faxina]** Modo `-Modo Faxina` funcional: catálogo com os 11 itens portados do
  WinFaxina (Temporários/Navegadores/Sistema/Lixeira), motor único de execução
  (`Invoke-ItemCatalogo`/`Get-AcaoDescricao`, renomeado de `Invoke-FaxinaItem` para
  refletir que a Fase 3 vai estender os mesmos dispatchers com os tipos do Debloat),
  perfis Minimo/Completo/Agressivo, menu interativo por categoria, ponto de
  restauração verificado, simulação (`-Simular`/`-WhatIf`) e relatório JSON
  antes/depois (agora com `Modo` e `VersaoWindowsDetectada` na raiz, além dos campos
  que o WinFaxina original já tinha — necessário porque um relatório fundido não se
  autoidentifica mais pela identidade da ferramenta como cada script original fazia).
- **[Faxina]** `$script:CategoriasPorModo`: primeira prova do modelo "um motor só,
  `-Modo` pré-filtra `Categorias`" — `Get-ItensDoPerfil`/`Initialize-Selecao`/
  `Show-MainMenu` agora recebem a lista de categorias do modo em vez de usar uma
  lista global fixa (reaproveitado pela Fase 3 para `Debloat`/`Tudo` sem alterar
  essas funções de novo). `Faxina` e `Debloat` não compartilham nenhuma categoria
  (ver correção acima — a nota original aqui dizia o contrário e estava errada).
- **[Faxina]** CI: etapa de execução real (`-NaoInterativo -Simular -Perfil
  Agressivo`) contra o próprio runner `windows-latest`, validando o relatório JSON
  gerado (11 itens, `Modo`/`Simulacao` corretos).
- **[Debloat]** CI: mesma etapa de execução real para `-Modo Debloat`. O runner do
  GitHub Actions não é uma workstation Win10/11 de verdade (`VersaoWindowsDetectada`
  vem `Desconhecido` — ver CLAUDE.md), então o teste confere um piso de 24 itens (os
  que não têm `SistemasAlvo`, válidos em qualquer SO) em vez de um total fixo.
- **[Esqueleto]** `#Requires -Version 5.1`, UTF-8 com BOM, help completo.
- **[Esqueleto]** `param()` fundido com os 7 modos (`Debloat`, `Faxina`, `Tudo`,
  `Inicializacao`, `SafeBoot`, `AdminOculto`, `Diagnostico`) e todos os parâmetros
  específicos por modo. Colisão de `-Acao` (existia com `ValidateSet` diferente em
  StartupAppsNinja/SafeBoot-Ninja/ativar-win-admin) resolvida por renomeio:
  `-AcaoInicializacao`, `-AcaoSafeBoot`, `-AcaoAdmin`.
- **[Esqueleto]** Funções compartilhadas: `Write-Log` (6 níveis), `Test-Admin`,
  `Assert-Admin` (com relançamento PS7→5.1 e exclusão de `SecureString` por tipo,
  não por nome), `Start-Logging`/`Stop-LoggingSeAtivo`, `Confirm-Acao`,
  `Get-VersaoWindows`/`ConvertTo-VersaoWindows` (detecção pura e testável de Windows
  10 vs. 11, corrigindo um gap real do `Assert-Windows10` original que não checava
  `ProductType` — passaria hoje num Windows Server com build na faixa certa).
- **[Esqueleto]** Guarda mecânica: nenhum `FunctionDefinitionAst.Name` duplicado no
  arquivo inteiro — protege contra o risco real de colar múltiplos scripts-fonte no
  mesmo arquivo (`Show-MainMenu` existia em 5 dos 6 scripts originais, com corpos
  diferentes e sem relação nenhuma em 2 deles).
- **[Esqueleto]** 14 testes Pester (sintaxe/encoding, colisão de nome de função,
  cobertura do `param()` fundido, `ConvertTo-VersaoWindows` com fixtures incluindo o
  caso Server-com-build-de-Win10/11) e CI (GitHub Actions: PSScriptAnalyzer + Pester).

### Notas
- `-Modo Faxina`/`Debloat`/`Tudo`/`Diagnostico`/`AdminOculto`/`SafeBoot` executam lógica
  real nesta versão. `Inicializacao` continua saindo com código 9 e aviso "ainda será
  implementado". Ver "Status de implementação" no README.
- Supressão temporária de `PSReviewUnusedParameter` no topo do `.ps1`: os parâmetros do
  modo `Inicializacao` (o único ainda não implementado) já existem no `param()` fundido
  (decisão deliberada — resolver toda
  colisão de nome de uma vez só no esqueleto), mas não são consumidos até sua fase
  ser implementada. Remover a supressão na Fase 5.
