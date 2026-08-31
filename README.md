# CaixaDeFerramentasWindows

Caixa de ferramentas unificada para Windows: um arquivo só, zero dependências, que junta
debloat (detecta Windows 10/11 automaticamente), faxina de disco, diagnóstico rápido,
administrador oculto, Modo de Segurança e itens de inicialização.

Os 7 modos (`Faxina`/`Debloat`/`Tudo`/`Diagnostico`/`AdminOculto`/`SafeBoot`/
`Inicializacao`) e o menu principal estão todos funcionais. Os 6 repositórios individuais
abaixo continuam mantidos separadamente — esta caixa é um pacote complementar para quem
quer tudo junto, não uma substituição.

## ⚠️ Antes de usar

- **Superfície de segurança**: este artefato único mexe em remoção de Appx, política de
  registro, chaves de autostart, alternância de boot (`bcdedit`) **e** ativação da conta
  Administrador oculta — tudo no mesmo arquivo. Isso é uma assinatura mais "valiosa" para
  EDR/antivírus monitorar do que qualquer um dos 6 scripts pequenos e focados de origem.
  Se você roda em ambiente monitorado, avise seu time de segurança antes de usar em escala.
- **Valide numa VM antes de produção**: `-Simular`/`-AcaoX Status` primeiro, depois
  `Minimo`. Cada modo já rodou de verdade em CI (`windows-latest`, GitHub Actions) — mas
  só os caminhos seguros/não-destrutivos (simulação, leitura de estado, e um único
  round-trip real de Adicionar+Remover em `Inicializacao`). Nenhum modo passou por
  validação manual interativa numa VM dedicada (menus, `Habilitar`/`Desabilitar` de
  verdade, `SafeBoot` com reinício real, `AdminOculto` com login de teste) — isso ainda
  não foi feito neste projeto. Ver [CONTRIBUTING.md](CONTRIBUTING.md).
- **Todo modo que altera o sistema exige confirmação explícita**: `-NaoInterativo`
  **e** `-Confirmar` juntos (ou rodar interativo, que pergunta na hora). Nunca altera nada
  silenciosamente.

## 🚀 Como usar

Sem `-Modo`, o script mostra um menu interativo com os 7 modos:

```powershell
.\CaixaDeFerramentasWindows.ps1
```

Ou direto por parâmetro (recomendado para automação/RMM — sempre com `-NaoInterativo`):

```powershell
# Faxina de disco
.\CaixaDeFerramentasWindows.ps1 -Modo Faxina -NaoInterativo -Perfil Completo

# Debloat (detecta Windows 10/11 sozinho e filtra o catalogo)
.\CaixaDeFerramentasWindows.ps1 -Modo Debloat -NaoInterativo -Perfil Completo

# Os dois juntos
.\CaixaDeFerramentasWindows.ps1 -Modo Tudo -NaoInterativo -Perfil Completo

# Diagnostico rapido (Visualizador de Eventos, nunca eleva, so leitura)
.\CaixaDeFerramentasWindows.ps1 -Modo Diagnostico -NaoInterativo -Dias 30

# Administrador oculto (ver estado - nunca altera nada sem -AcaoAdmin Ativar/Desativar)
.\CaixaDeFerramentasWindows.ps1 -Modo AdminOculto -NaoInterativo -AcaoAdmin Status

# Modo de Seguranca (ver estado - nunca altera nada sem -AcaoSafeBoot Minimo/Rede/Normal)
.\CaixaDeFerramentasWindows.ps1 -Modo SafeBoot -NaoInterativo -AcaoSafeBoot Status

# Itens de inicializacao (listar - nunca altera nada sem -AcaoInicializacao Adicionar/Remover/...)
.\CaixaDeFerramentasWindows.ps1 -Modo Inicializacao -NaoInterativo -AcaoInicializacao Listar
```

### Parâmetros por modo

| Modo | Parâmetros específicos |
|---|---|
| `Faxina` / `Debloat` / `Tudo` | `-Perfil Minimo\|Completo\|Agressivo`, `-Simular`, `-SemPontoRestauracao`, `-CaminhoRelatorioJson` |
| `Diagnostico` | `-Dias <N>`, `-Exportar`, `-CaminhoCsv`, `-ExportarHtml`, `-CaminhoHtml` |
| `AdminOculto` | `-AcaoAdmin Status\|Ativar\|Desativar`, `-SenhaSegura` (SecureString, exigido para `Ativar` não interativo) |
| `SafeBoot` | `-AcaoSafeBoot Status\|Minimo\|Rede\|Normal` |
| `Inicializacao` | `-AcaoInicializacao Listar\|Adicionar\|Remover\|Habilitar\|Desabilitar`, `-Nome`, `-Comando`, `-Escopo Usuario\|TodosUsuarios`, `-PermitirExperimental`, `-ForcarBuildNaoValidado` |
| Todos | `-NaoInterativo`, `-Confirmar`, `-CaminhoLog` |

`-Modo Inicializacao -AcaoInicializacao Habilitar/Desabilitar` usa um formato de registro
(`StartupApproved`) não documentado oficialmente pela Microsoft — por isso exige
`-PermitirExperimental` explícito mesmo em modo não interativo. Prefira `Adicionar`/
`Remover` (documentado, reversível) quando possível.

## Repositórios individuais (a mesma funcionalidade, um arquivo por ferramenta)

| Ferramenta | O que faz |
|---|---|
| [Windows10-Debloat](https://github.com/rivaed/Windows10-Debloat) | Remove bloatware/telemetria do Windows 10 |
| [Windows11-Debloat](https://github.com/rivaed/Windows11-Debloat) | Remove bloatware/telemetria do Windows 11 |
| [WinFaxina](https://github.com/rivaed/WinFaxina) | Faxina de disco (temporários, cache, lixeira) |
| [StartupAppsNinja](https://github.com/rivaed/StartupAppsNinja) | Gerencia itens de inicialização |
| [SafeBoot-Ninja](https://github.com/rivaed/SafeBoot-Ninja) | Liga/desliga o Modo de Segurança (safe boot) |
| [ativar-win-admin](https://github.com/rivaed/ativar-win-admin) | Ativa/desativa a conta Administrador oculta |

Progresso detalhado: [CHANGELOG.md](CHANGELOG.md). Decisões de arquitetura e critérios de
fusão dos catálogos: [CLAUDE.md](CLAUDE.md). Quer contribuir: [CONTRIBUTING.md](CONTRIBUTING.md).

## Requisitos

- Windows PowerShell 5.1 (o script se auto-relança no 5.1 quando detecta PowerShell 7+).
- Privilégios de administrador — o script se auto-eleva via UAC quando interativo.
  Exceção: `-Modo Diagnostico` é somente-leitura e nunca eleva.

## Licença

[MIT](LICENSE).

---

**Feito por [rivaed](https://github.com/rivaed).**
