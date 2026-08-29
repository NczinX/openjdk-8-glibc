# openjdk-8-glibc

OpenJDK 8 (Eclipse Temurin) empacotado pra rodar **nativamente** no Termux, sem `proot-distro`.

## Por que isso importa

O Termux oficialmente só disponibiliza OpenJDK 17, 21 e 25. Se você precisa de Java 8 especificamente — ferramentas Android mais antigas, builds legados de Gradle, ou qualquer projeto que exija essa versão — a saída "padrão" costuma ser instalar um `proot-distro` (um Ubuntu/Debian completo rodando em chroot dentro do Termux) só pra ter acesso a um JDK mais velho.

Isso funciona, mas custa caro: uma imagem de sistema de arquivos inteira, uma camada extra de emulação via `proot` (com perda real de performance), mais espaço em disco, e a dor de cabeça de scripts que rodam fora do proot não conseguirem chamar o `java` diretamente.

Esse pacote resolve isso sem nada disso. Ele pega os binários oficiais do Temurin 8 (build `linux-aarch64`, compilado pra `glibc` padrão, não `bionic`), usa `patchelf` pra corrigir o interpreter ELF de cada binário apontando pro `glibc` que já roda nativamente no Termux (pacote `glibc` da própria comunidade), e empacota tudo como um `.deb` comum. O resultado é `java -version` funcionando direto no seu `$PREFIX/bin`, integrado ao `update-alternatives` do sistema junto dos outros JDKs — **sem chroot, sem proot, sem camada de emulação**.

## Instalação

### Modo automático (recomendado)

Um comando só — instala o `gnupg` se faltar, configura o repositório, instala o pacote e já ativa o Java 8 via `update-alternatives`:

```bash
curl -fsSL https://openjdk-8-glibc.pages.dev/install.sh | bash
```

Se você usa `zsh`, funciona igual:

```bash
curl -fsSL https://openjdk-8-glibc.pages.dev/install.sh | zsh
```

Se não quiser que o Java 8 vire o padrão automaticamente (só instalar, sem trocar o `update-alternatives`), defina a variável antes:

```bash
OPENJDK8_GLIBC_NO_ACTIVATE=1 curl -fsSL https://openjdk-8-glibc.pages.dev/install.sh | bash
```

### Modo manual

Se preferir configurar você mesmo (ou revisar o que está sendo feito antes de rodar):

```bash
curl -fsSL https://openjdk-8-glibc.pages.dev/public.gpg.key | gpg --dearmor -o $PREFIX/etc/apt/trusted.gpg.d/openjdk-8-glibc.gpg
echo "deb https://openjdk-8-glibc.pages.dev/ stable main" > $PREFIX/etc/apt/sources.list.d/openjdk-8-glibc.list
apt update
apt install openjdk-8-glibc
```

Precisa ter `gnupg` instalado (`pkg install gnupg`) pro comando do `gpg --dearmor` funcionar. Nesse modo, o Java 8 **não** vira o padrão automaticamente (veja a seção abaixo pra ativar).

## Trocando entre versões do Java

O pacote se registra no `update-alternatives`, do mesmo jeito que o `openjdk-21`/`openjdk-17` fazem, com prioridade mais baixa que as versões oficiais — então instalar via `apt` (modo manual) não troca o padrão sozinho. O **modo automático** já ativa o Java 8 nesse momento (a menos que você tenha usado `OPENJDK8_GLIBC_NO_ACTIVATE=1`).

Pra ativar manualmente (ou trocar de volta pra outra versão depois):

```bash
update-alternatives --config java
```

Escolhe o Java 8 na lista. Depois disso, **abra uma sessão nova** do Termux (ou rode `source $PREFIX/etc/profile.d/java.sh`) — variáveis de ambiente como `JAVA_HOME` não se atualizam sozinhas numa shell que já estava aberta.

Confirma que funcionou:

```bash
java -version
echo $JAVA_HOME
```

Os dois devem apontar pro Java 8 depois disso.

## Como funciona por baixo dos panos

- **`build.sh`**: baixa o Temurin 8 (`linux-aarch64`) da API da Adoptium, corrige o interpreter ELF de cada binário com `patchelf` pra apontar pro `glibc` do Termux, empacota tudo num `.deb`. Os binários viram wrappers que dão `unset LD_PRELOAD`/`LD_LIBRARY_PATH` antes de rodar o binário real (evita conflito com o `bionic` do Android). O `postinst` do pacote registra tudo via `update-alternatives`, incluindo um slave `java-profile` que troca o `JAVA_HOME` certo junto com o JDK ativo.
- **`scripts/make-repo.sh`**: monta a estrutura padrão de repositório apt (`pool/` + `dists/`) a partir do `.deb` gerado, e assina com GPG se a variável `GPG_PRIVATE_KEY` estiver definida.
- **`.github/workflows/release.yml`**: builda e publica tudo automaticamente. Como o Cloudflare Pages recusa arquivos acima de ~26 MB e o `.deb` passa bem disso, o `.deb` em si fica hospedado no GitHub Releases (tag `apt-pool`, sempre atualizada), e o Cloudflare Pages guarda só os metadados do repositório (poucos KB) + um arquivo `_redirects` que redireciona a requisição do `.deb` pro GitHub Releases via HTTP 302 — o `apt` segue redirecionamento normalmente, é assim que espelhos de repositórios Debian de verdade costumam lidar com arquivos grandes.
- **`install.sh`**: o script do modo automático. É publicado em dois lugares no mesmo site: na raiz (`/`, como `index.html`, pra permitir `curl URL | bash` sem path) e em `/install.sh` (pra quem preferir ser explícito). É idempotente — rodar de novo não refaz o que já está configurado — e detecta se não está rodando dentro do Termux, recusando nesse caso.

## Buildando localmente

Requisitos: `patchelf`, `dpkg-dev`, `python3` (ou `python`), `curl`.

```bash
bash build.sh
```

Gera o `.deb` na raiz do projeto. O script detecta automaticamente se está rodando em CI (variável `CI`) e pula a checagem de `glibc` local nesse caso — só precisa existir de verdade no dispositivo Termux final, não na máquina que builda.

## Publicando sua própria instância

Precisa de:

- Um projeto criado no Cloudflare Pages
- Secrets no GitHub:
  - `CLOUDFLARE_API_TOKEN`
  - `CLOUDFLARE_ACCOUNT_ID`
  - `GPG_PRIVATE_KEY` (opcional — sem isso o repositório sai sem assinatura, e quem instalar precisa usar `[trusted=yes]` no lugar do `gpg --dearmor`)
  - `GPG_PASSPHRASE` (opcional, só se a chave GPG tiver senha)

O workflow dispara em push de tag `v*` ou manualmente pela aba Actions (`workflow_dispatch`).

## Problemas comuns

**`JAVA_HOME` não muda mesmo depois do `update-alternatives --config java`**
Abre uma sessão nova do terminal — variável de ambiente não se propaga pra shells já abertas.

**`gpg: no valid OpenPGP data found`**
Faltam as linhas `-----BEGIN PGP PRIVATE KEY BLOCK-----` / `-----END PGP PRIVATE KEY BLOCK-----` no secret `GPG_PRIVATE_KEY`. Copie a saída completa de `gpg --armor --export-secret-keys <ID>`, sem cortar nada.

**`gpg: signing failed: No passphrase given` ou `Inappropriate ioctl for device`**
A chave usada tem senha, ou está tentando abrir um prompt interativo num ambiente sem terminal (CI). Gere uma chave dedicada, sem senha:

```bash
gpg --batch --passphrase '' --quick-generate-key "openjdk-8-glibc <voce@example.com>" default default never
```

**`The key(s) in the keyring ... are ignored as the file has an unsupported filetype`**
A chave pública foi salva em `trusted.gpg.d/` no formato ASCII (texto), mas o `apt` exige formato binário. Sempre converta com `gpg --dearmor` antes de salvar:

```bash
curl -fsSL <URL>/public.gpg.key | gpg --dearmor -o $PREFIX/etc/apt/trusted.gpg.d/openjdk-8-glibc.gpg
```

**`Error: Pages only supports files up to 26.2 MB in size`**
O `.deb` não pode ir direto pro diretório publicado no Cloudflare Pages. É exatamente o que a variável `DEB_REDIRECT_BASE_URL` do `make-repo.sh` resolve — confirme que ela está sendo passada no workflow.

## Créditos

Java: [Eclipse Temurin](https://adoptium.net/) (Adoptium), licenciado sob GPLv2 com Classpath Exception.
