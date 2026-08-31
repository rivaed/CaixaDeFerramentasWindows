# CaixaDeFerramentasWindows

Caixa de ferramentas unificada para Windows: um arquivo só, zero dependências, que junta
debloat (detecta Windows 10/11 automaticamente), faxina de disco, itens de inicialização,
modo de segurança, administrador oculto e diagnóstico rápido.

> **Em construção por fases.** Esta versão (`0.1.0`) já tem os 6 modos funcionais — só o
> menu principal interativo (sem `-Modo`) ainda está pendente; até lá, use sempre `-Modo`
> explícito. Os repositórios individuais abaixo continuam mantidos separadamente; esta
> caixa é um pacote complementar, não uma substituição.

```powershell
# Faxina de disco
.\CaixaDeFerramentasWindows.ps1 -Modo Faxina -NaoInterativo -Perfil Completo

# Debloat (detecta Windows 10/11 sozinho e filtra o catalogo)
.\CaixaDeFerramentasWindows.ps1 -Modo Debloat -NaoInterativo -Perfil Completo

# Os dois juntos
.\CaixaDeFerramentasWindows.ps1 -Modo Tudo -NaoInterativo -Perfil Completo

# Diagnostico rapido (Visualizador de Eventos, nunca eleva)
.\CaixaDeFerramentasWindows.ps1 -Modo Diagnostico -NaoInterativo -Dias 30

# Administrador oculto (so ver o estado - nunca altera nada)
.\CaixaDeFerramentasWindows.ps1 -Modo AdminOculto -NaoInterativo -AcaoAdmin Status

# Modo de Seguranca (so ver o estado - nunca altera nada)
.\CaixaDeFerramentasWindows.ps1 -Modo SafeBoot -NaoInterativo -AcaoSafeBoot Status

# Itens de inicializacao (listar - nunca altera nada)
.\CaixaDeFerramentasWindows.ps1 -Modo Inicializacao -NaoInterativo -AcaoInicializacao Listar
```

Sem `-Modo`, o script mostra este texto e sai (código 9) até o menu principal da Fase 5
existir. Todo modo que faz alteração precisa de `-NaoInterativo` **e** `-Confirmar` juntos
(ou rodar interativo, que pede confirmação na hora) — nunca altera nada sem confirmação
explícita.

## Repositórios individuais (funcionam hoje)

| Ferramenta | O que faz |
|---|---|
| [Windows10-Debloat](https://github.com/rivaed/Windows10-Debloat) | Remove bloatware/telemetria do Windows 10 |
| [Windows11-Debloat](https://github.com/rivaed/Windows11-Debloat) | Remove bloatware/telemetria do Windows 11 |
| [WinFaxina](https://github.com/rivaed/WinFaxina) | Faxina de disco (temporários, cache, lixeira) |
| [StartupAppsNinja](https://github.com/rivaed/StartupAppsNinja) | Gerencia itens de inicialização |
| [SafeBoot-Ninja](https://github.com/rivaed/SafeBoot-Ninja) | Liga/desliga o Modo de Segurança (safe boot) |
| [ativar-win-admin](https://github.com/rivaed/ativar-win-admin) | Ativa/desativa a conta Administrador oculta |

## Status de implementação

| `-Modo` | Origem | Status |
|---|---|---|
| `Debloat` | Windows10/11-Debloat | ✅ Implementado |
| `Faxina` | WinFaxina | ✅ Implementado |
| `Tudo` | Debloat + WinFaxina | ✅ Implementado |
| `Diagnostico` | DiagnosticoRapidoDePC | ✅ Implementado |
| `AdminOculto` | ativar-win-admin | ✅ Implementado |
| `SafeBoot` | SafeBoot-Ninja | ✅ Implementado |
| `Inicializacao` | StartupAppsNinja | ✅ Implementado |
| Menu principal (sem `-Modo`) | — | Pendente (Fase 5) |

Progresso detalhado: [CHANGELOG.md](CHANGELOG.md). Decisões de arquitetura e critérios de
fusão dos catálogos: [CLAUDE.md](CLAUDE.md).

## Requisitos

- Windows PowerShell 5.1 (o script se auto-relança no 5.1 quando detecta PowerShell 7+).

## Licença

[MIT](LICENSE).

---

**Feito por [rivaed](https://github.com/rivaed).**
