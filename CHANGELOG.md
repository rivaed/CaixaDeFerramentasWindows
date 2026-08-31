# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.1.0] — não lançado

### Adicionado
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
- Nenhum `-Modo` executa lógica real ainda — todos saem com código 9 e aviso "ainda
  será implementado". Ver "Status de implementação" no README para o mapa de fases.
- Supressão temporária de `PSReviewUnusedParameter` no topo do `.ps1`: os parâmetros
  específicos de cada modo já existem (decisão deliberada — resolver toda colisão de
  nome de uma vez só no esqueleto), mas ainda não são consumidos até sua fase ser
  implementada. Remover a supressão na Fase 5.
