# Cleaner by Ciro Cesar Maciel

**O limpador de Mac que mostra tudo antes de apagar qualquer coisa.**

Um dos [seis apps de Mac grátis e de código aberto](#mais-de-ciro-cesar-maciel) de [Ciro Cesar Maciel](https://ciromaciel.click/?ref=oss-cleaner).

**[Veja o vídeo de 1 minuto](https://youtu.be/Wj9M-mYZjJs)** (em inglês)

[![As seen on Open Source Alternatives](https://www.opensourcealternatives.to/badge-osa.svg)](https://www.opensourcealternatives.to)

Toda regra que ele usa para limpar está num arquivo que dá para ler, o [`rules.json`](rules.json). Nada some na hora: o que você remove passa 7 dias numa quarentena e volta ao lugar com um clique. App nativo em Swift, para macOS 14 ou mais novo com Apple Silicon, sem nenhum código de rede.

[English](README.md)

![Visão geral do Cleaner: 4 GB para liberar, uso do disco e as quatro ferramentas](docs/pt-BR/overview.webp)

## Instalar

```bash
curl -fsSL https://blob.ciromaciel.click/tools/cleaner/install.sh | bash
```

O script baixa o `.dmg` mais recente, copia o Cleaner para `/Applications` e abre o app.

Com o [Homebrew](https://github.com/ciro-maciel/homebrew-tap): `brew install --cask ciro-maciel/tap/ciro-cleaner`.

Prefere a imagem de disco? [Baixe o Cleaner-macos.dmg](https://blob.ciromaciel.click/tools/cleaner/latest/Cleaner-macos.dmg). Abra e arraste o Cleaner para Aplicativos. Ele é assinado com Developer ID e notarizado pela Apple, então o macOS abre sem aviso.

Para a varredura completa, ligue o Cleaner em **Ajustes do Sistema → Privacidade e Segurança → Acesso Total ao Disco**. Sem isso, o macOS esconde a Lixeira, o Mail e os contêineres dos apps, e o Cleaner avisa em vez de fingir que viu tudo.

## Por que mais um limpador de Mac

Os limpadores conhecidos pedem que você confie num número de "lixo". O Cleaner mostra de onde vem esse número:

- **As regras são públicas.** O `rules.json` lista cada pasta que o Cleaner olha, por que é seguro limpar e o que fica de fora. Se uma regra estiver errada, você lê e pode mandar a correção.
- **Nada some.** Remover move os itens para um lote da quarentena que guarda o caminho de origem. Devolver é um clique; depois de 7 dias o lote se apaga sozinho.
- **Remover pede segurar o botão por 3 segundos.** Sem clique por engano.
- **Ele diz o que não consegue fazer.** Quando o macOS recusa um item, o Cleaner diz por quê:
  - item do sistema (`EACCES`): pede a senha de administrador uma vez por ação, num pedido que diz o que vai fazer e com quais itens;
  - item protegido (`EPERM`, como Lixeira, Mail, contêineres sem Acesso Total ao Disco ou itens do SIP): nunca pede senha, porque senha não resolveria. O item fica no lugar, e o aviso leva aos Ajustes.

![Limpeza: cada item, a regra que o encontrou e o tamanho](docs/pt-BR/cleanup.webp)

## O que ele faz

| Tela | O que faz |
| --- | --- |
| Visão geral | Uma varredura para tudo: espaço que dá para liberar, disco, apps, inicialização, quarentena |
| Limpeza | Aplica as regras do `rules.json`: caches, registros, Lixeira, instaladores, Xcode, caches de desenvolvimento, anexos do Mail |
| Desinstalador | Lista os apps com tamanho e último uso; remove o app e os restos dele em 38 lugares, recibos de .pkg incluídos |
| Mapa do disco | Mede uma pasta inteira em paralelo e deixa entrar nas maiores |
| Inicialização | Liga e desliga LaunchAgents e LaunchDaemons sem apagar o arquivo |
| Quarentena | Lotes com o caminho de origem; devolve com um clique; apaga sozinho depois de 7 dias |
| Barra de menus | Processador, memória, rede, disco e bateria ao vivo, e quanto dá para liberar agora |

<img src="docs/pt-BR/menubar.webp" alt="O painel da barra de menus: processador, memória, rede, disco e bateria" width="300">

## A desinstalação completa

Em `Sources/Cleaner/Engine/Uninstaller.swift`, nesta ordem:

1. para os processos que rodam de dentro do app (extensões, ajudantes);
2. descarrega os agentes de inicialização;
3. tira o registro do app no macOS (LaunchServices);
4. move tudo para um lote da quarentena, limpando o cache do `cfprefsd` para os `.plist` não renascerem;
5. tira o ícone do Dock;
6. confere o que ficou.

Os restos são procurados em 38 lugares (`AppCatalog.places()`), pelo identificador do app ou pelo nome exato, inclusive pastas do fabricante e os recibos de `.pkg`. Devolver da quarentena refaz o registro e o ícone no Dock.

## Compilar

Precisa das Command Line Tools do Xcode. O Xcode inteiro é opcional.

```bash
git clone https://github.com/ciro-maciel/cleaner.git
cd cleaner
scripts/build.sh                 # dist/Cleaner.app
open dist/Cleaner.app
```

As ilustrações de cada tela vêm de uma galeria licenciada e só vão no build oficial; compilando a partir deste repositório, cada tela mostra o ícone Tabler no lugar. Para usar as suas, ponha PNGs de 560 × 560 em `Resources/Illustrations`.

O `scripts/build.sh` assina com um certificado Developer ID Application quando o seu chaveiro tem um (o build oficial tem). Sem ele, o `scripts/signing-identity.sh` cria, uma vez, um certificado local de assinatura: com ele, o Acesso Total ao Disco continua valendo depois de cada build; sem ele, o build sai com assinatura ad hoc e o macOS pede a permissão de novo toda vez.

Os testes rodam no seu Mac sem mudar nada:

```bash
CLEANER_NO_ADMIN=1 dist/Cleaner.app/Contents/MacOS/Cleaner --selftest   # só lê; a quarentena roda numa pasta temporária
dist/Cleaner.app/Contents/MacOS/Cleaner --uninstall-test                # cria um app falso com todos os rastros, remove, confere e devolve
dist/Cleaner.app/Contents/MacOS/Cleaner --screenshots /tmp/shots        # captura todas as telas
```

`scripts/dist.sh` sobe o patch da versão, gera o `.dmg` e instala em `/Applications`. `bun scripts/assets.mjs` regera fontes, ícones e o ícone do app.

## Como é feito

- Swift e SwiftUI, compilado com `swiftc`, sem projeto do Xcode. Alvo: macOS 14 ou mais novo, Apple Silicon.
- Varredura com `fts(3)`, contando blocos ocupados no disco, em paralelo por pasta.
- Visual do design system Zen: rampa de cinzas, Montserrat, raio zero, ícones Tabler com traço 1,5.

## Limites

- Só Apple Silicon e macOS 14 ou mais novo.
- A interface está em inglês e em português do Brasil, conforme o idioma do Mac.
- Itens protegidos pelo SIP ficam onde estão. É o macOS funcionando como deve.
- Não procura duplicados, não faz varredura de malware e não atualiza apps.

## Contribuir

Issues e pull requests são bem-vindos, principalmente no `rules.json`. Veja o [CONTRIBUTING.md](CONTRIBUTING.md).

## Licença

[MIT](LICENSE). Fontes e ícones mantêm as próprias licenças: veja o [NOTICE](NOTICE).

---

## Mais de Ciro Cesar Maciel

Eu construo software sozinho, com uma equipe de agentes de IA, e abro o que dá para abrir. Seis apps nativos para Mac, todos grátis, MIT, assinados e notarizados pela Apple, em inglês e português do Brasil: [Cleaner](https://github.com/ciro-maciel/cleaner), o limpador de Mac que mostra tudo antes de apagar qualquer coisa (este) · [Screenshots](https://github.com/ciro-maciel/screenshots), captura, anotação e gravação de tela, sem nada sair do Mac · [Speech to Text](https://github.com/ciro-maciel/speech-to-text), ditado por atalho, com o Whisper rodando no Mac · [Assistant](https://github.com/ciro-maciel/voice-assistant), o Claude Code por voz · [Windows](https://github.com/ciro-maciel/windows), janelas no lugar com um atalho ou levando até a borda · [Text to Speech](https://github.com/ciro-maciel/text-to-speech), selecione um texto em qualquer app e ouça.

Além dos apps: [ferramentas grátis no navegador](https://ciromaciel.click/tools?ref=oss-cleaner), [livros](https://ciromaciel.click/books?ref=oss-cleaner) e o [Infrastructure](https://myinfrastructure.click/?ref=oss-cleaner), a infraestrutura que os agentes já sabem operar.

**Toda semana, por e-mail:** as [Cartas do Ciro](https://ciromaciel.click/?ref=oss-cleaner), o que estou construindo e aprendendo.

**Acompanhe.** [Siga @ciro-maciel](https://github.com/ciro-maciel) para os próximos apps abertos, clique em **Watch → Custom → Releases** aqui em cima para saber de cada versão nova, e veja como tudo é feito no [YouTube](https://www.youtube.com/@ciro-maciel).
