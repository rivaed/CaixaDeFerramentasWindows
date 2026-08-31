# Contribuindo

Antes de mexer na arquitetura (fusão de catálogo, nomes de função compartilhados,
`SistemasAlvo`), leia [CLAUDE.md](CLAUDE.md) — documenta as decisões já tomadas e o
porquê, para não reabrir uma discussão já resolvida sem motivo novo.

## Duas famílias, regras diferentes

- **Grupo A** (`-Modo Faxina`/`Debloat`/`Tudo`): catálogo único fundido
  (`$script:Catalogo`). Todo item novo entra aqui — nunca como código solto.
- **Grupo B** (`-Modo Diagnostico`/`AdminOculto`/`SafeBoot`/`Inicializacao`): cada um com
  sua própria lógica portada do repositório original. Não force um desses num item de
  catálogo — a decisão de mantê-los separados já foi validada (ver CLAUDE.md).

## Critérios para um item novo no catálogo (Grupo A)

Um item só entra se:

1. **Libera espaço real e mensurável**, ou corrige um problema técnico documentado — não
   "achismo" de otimização.
2. **Nível correto:**
   - `Seguro` — sem efeito colateral perceptível, sempre regenerável;
   - `Opcional` — tem algum trade-off real (demora, irreversibilidade comum/esperada);
   - `Agressivo` — irreversível de forma não óbvia, ou pode exigir ação manual futura
     (ex.: mídia de instalação) — documente exatamente o risco.
3. **`SistemasAlvo` correto**: omita o campo se o item vale para Windows 10 **e** 11;
   declare `@('Win10')` ou `@('Win11')` só se o item genuinamente não se aplica ao outro
   SO. **Nunca** `SistemasAlvo = @()` (array vazio) — é tratado como bug pelo teste
   mecânico, não como "nenhuma restrição".
4. **`Id` único no catálogo inteiro** (não só dentro da categoria) — o teste mecânico
   trava isso, mas confira antes de abrir o PR.
5. **Todo `Tipo=Especial` novo precisa de um `case` nos DOIS dispatchers**
   (`Invoke-ItemCatalogo` **e** `Get-AcaoDescricao`) — um item Especial sem `case` em
   `Get-AcaoDescricao` fica com descrição vazia sob `-Simular` (bug real já cometido e
   corrigido neste projeto). O teste mecânico cobre isso, mas é fácil esquecer ao
   escrever o código pela primeira vez.
6. **Testado numa VM Windows real** antes do PR, quando possível — veja a ressalva sobre
   validação manual no README; este projeto ainda não teve acesso a uma VM Windows
   durante o desenvolvimento inicial, então PRs com validação manual real são
   especialmente bem-vindos.

## Mexendo num modo do Grupo B

- Não duplique `Write-Log`/`Test-Admin`/`Assert-Admin`/`Start-Logging`/
  `Stop-LoggingSeAtivo` — são compartilhadas entre todos os modos.
- `Confirm-Acao` (genérica, `param($Descricao)`) é compartilhada entre `Inicializacao` e
  qualquer modo futuro sem aviso especial. Se seu modo precisa de um aviso extra
  específico (como o de RDP em `SafeBoot`), crie uma variante nomeada
  (`Confirm-Acao<Modo>`) em vez de adicionar um parâmetro condicional na genérica — foi
  a decisão tomada para `Confirm-AcaoSafeBoot`.
- Se seu modo precisa de um parâmetro que colide em nome/propósito com outro modo (ex.:
  um novo "`-Acao`"), renomeie com o prefixo do modo (`-Acao<Modo>`) em vez de reusar
  `-Acao` genérico — motivo documentado em CLAUDE.md, Bloqueio B.
- Todo modo tem sua própria suíte de testes (`tests/<Modo>.Tests.ps1`). Ao adicionar um
  modo novo, siga o padrão já usado: teste que as funções existem, que o bloco do modo no
  `switch ($Modo)` chama (ou não chama) `Assert-Admin` conforme o esperado, e fixtures
  para qualquer lógica pura extraível via AST + `Invoke-Expression` — ver a nota em
  CLAUDE.md sobre escopo do Pester 5 antes de escrever esse tipo de teste (é fácil errar
  de um jeito sutil).

## Checklist do PR

- [ ] Encoding do `.ps1` continua UTF-8 **com BOM** (`head -c 3 arquivo.ps1 | xxd` deve
      mostrar `ef bb bf`).
- [ ] `Invoke-ScriptAnalyzer` sem apontamentos novos (zero é o padrão deste projeto).
- [ ] `Invoke-Pester -Path ./tests` verde.
- [ ] Se mexeu no catálogo: tabela/exemplos relevantes no README atualizados na mesma PR.
- [ ] CHANGELOG atualizado na mesma PR, com a tag do modo entre colchetes (ex.:
      `**[SafeBoot]**`) quando a mudança é isolada a um só modo.
- [ ] CI verde (lint + Pester + execução real por modo).

## Convenções

- **Commits:** Conventional Commits em pt-BR — `tipo(escopo): descrição` no imperativo
  (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`), explicando o *porquê* quando não
  for óbvio.
- **Compatibilidade:** todo código roda no Windows PowerShell 5.1 (sem sintaxe exclusiva
  do PowerShell 7) — o script se auto-relança no 5.1 quando detecta PS7+, mas isso não
  substitui escrever código compatível com 5.1 desde o início.
- **`ConvertTo-Json`:** sempre com `-Depth` explícito (o padrão do PS 5.1 é 2 e trunca
  aninhamento sem aviso). Guarda mecânica no Pester.
- **`ConvertTo-Html`:** `-Head`/`-Title`/`-PreContent`/`-PostContent` só recebem string
  literal fixa — nunca variável (não é escapado pelo cmdlet). Dado dinâmico só via
  `-Body`, como saída de `ConvertTo-Html -Fragment`. Guarda mecânica no Pester.
- **Catálogo e testes cross-platform:** os testes Pester extraem o literal do catálogo
  via AST e avaliam isolado, em qualquer SO (Docker/Linux no CI local). O literal nunca
  pode ler nada calculado em runtime (nem `$script:VersaoWindowsDetectada`, nem
  `Join-Path`/cmdlets com `$env:SystemRoot`/`$env:ProgramData` direto) — use interpolação
  de string (`"$env:SystemRoot\X"`), que só fica vazia quando a variável não existe, sem
  quebrar a extração do catálogo nos testes.
- **Validação local:** `docker run --rm --platform linux/amd64 -v "$PWD:/src" -w /src
  mcr.microsoft.com/powershell:lts-ubuntu-22.04 pwsh -c "..."` para sintaxe/Pester/
  PSScriptAnalyzer. **Importante:** instale/registre o PSGallery e os módulos (Pester,
  PSScriptAnalyzer) **antes** de qualquer `ParseFile`/uso de
  `System.Management.Automation.Language` no mesmo comando — a ordem inversa quebra a
  resolução do PSGallery de forma reproduzível dentro do container (achado real,
  documentado em CLAUDE.md).
