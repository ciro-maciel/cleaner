# Todas as regras com que o Cleaner limpa

O Cleaner só olha onde uma regra do [`rules.json`](../../rules.json) manda. Estas são as 9, escritas a partir desse arquivo pelo `scripts/rules-doc.mjs`. O que você remove passa 7 dias na quarentena antes.

## Caches de aplicativos `app-caches`

| | |
| --- | --- |
| Por que é seguro | Arquivos temporários que cada app recria sozinho quando precisa. |
| Onde | `~/Library/Caches` |
| O que sai | cada item dentro da pasta |
| Fica de fora | `com.apple.*`, `CloudKit`, `FamilyCircle`, `GeoServices`, `click.ciromaciel.cleaner`, `.*` |
| Risco | baixo · Pula os apps que estão abertos |
| Ligada por padrão | sim |

## Registros de aplicativos `logs`

| | |
| --- | --- |
| Por que é seguro | Diários que os apps escrevem para diagnóstico. Ninguém lê depois que o problema passou. |
| Onde | `~/Library/Logs` |
| O que sai | cada item dentro da pasta |
| Fica de fora | `.*` |
| Risco | baixo |
| Ligada por padrão | sim |

## Lixeira `trash`

| | |
| --- | --- |
| Por que é seguro | O que você já mandou para a Lixeira e ainda ocupa espaço. |
| Onde | `~/.Trash` |
| O que sai | cada item dentro da pasta |
| Fica de fora | `.DS_Store` |
| Risco | baixo |
| Ligada por padrão | sim |

## Instaladores em Downloads `installers`

| | |
| --- | --- |
| Por que é seguro | Imagens de disco e pacotes de instalação com mais de 7 dias. O app já está instalado; o instalador sobra. |
| Onde | `~/Downloads` |
| O que sai | os arquivos dentro da pasta |
| Só estas extensões | `dmg`, `pkg`, `mpkg`, `xip`, `iso` |
| Só mais antigos que | 7 dias |
| Risco | baixo |
| Ligada por padrão | sim |

## Compilações do Xcode `xcode-derived-data`

| | |
| --- | --- |
| Por que é seguro | A pasta DerivedData guarda compilações intermediárias. O Xcode refaz tudo na próxima compilação. |
| Onde | `~/Library/Developer/Xcode/DerivedData` |
| O que sai | cada item dentro da pasta |
| Fica de fora | `.*` |
| Risco | baixo |
| Ligada por padrão | sim |

## Caches de ferramentas de desenvolvimento `dev-caches`

| | |
| --- | --- |
| Por que é seguro | Pacotes baixados por npm, Bun, pnpm, Gradle e Cargo. Eles baixam de novo quando precisarem. |
| Onde | `~/.npm/_cacache`, `~/.bun/install/cache`, `~/Library/pnpm/store`, `~/.gradle/caches`, `~/.cargo/registry/cache` |
| O que sai | a própria pasta |
| Risco | baixo |
| Ligada por padrão | sim |

## Suporte a aparelhos do Xcode `xcode-device-support`

| | |
| --- | --- |
| Por que é seguro | Símbolos de cada versão de iOS que já foi plugada. Volta sozinho ao plugar o aparelho, mas demora. |
| Onde | `~/Library/Developer/Xcode/iOS DeviceSupport`, `~/Library/Developer/Xcode/watchOS DeviceSupport` |
| O que sai | cada item dentro da pasta |
| Fica de fora | `.*` |
| Risco | médio |
| Ligada por padrão | não, você escolhe |

## Anexos abertos no Mail `mail-downloads`

| | |
| --- | --- |
| Por que é seguro | Cópias dos anexos que você abriu. O original continua no e-mail. |
| Onde | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` |
| O que sai | cada item dentro da pasta |
| Fica de fora | `.*` |
| Risco | baixo |
| Ligada por padrão | sim |

## Modelos de IA baixados `ai-models`

| | |
| --- | --- |
| Por que é seguro | Modelos que ferramentas como Hugging Face e LM Studio baixam e baixam de novo quando você usa. Costumam ocupar gigabytes; confira cada um, porque o app que usa o modelo precisa dele para funcionar. |
| Onde | `~/.cache/huggingface/hub`, `~/.lmstudio/models`, `~/.cache/lm-studio/models` |
| O que sai | cada item dentro da pasta |
| Fica de fora | `.*`, `CACHEDIR.TAG`, `version*.txt` |
| Risco | médio |
| Ligada por padrão | não, você escolhe |
