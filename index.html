#!/data/data/com.termux/files/usr/bin/bash
set -e

REPO_URL="https://openjdk-8-glibc.pages.dev"
GLIBC_REPO="https://packages-cf.termux.dev/apt/termux-glibc"

KEYRING="$PREFIX/etc/apt/trusted.gpg.d/openjdk-8-glibc.gpg"
SOURCES_LIST="$PREFIX/etc/apt/sources.list.d/openjdk-8-glibc.list"
GLIBC_SOURCES_LIST="$PREFIX/etc/apt/sources.list.d/glibc.list"

SOURCES_LINE="deb $REPO_URL/ stable main"
GLIBC_SOURCES_LINE="deb $GLIBC_REPO glibc stable"

JAVA_HOME_8="$PREFIX/opt/openjdk-8"
JAVA_WRAPPER="$JAVA_HOME_8/wrapper-bin/java"
JAVAC_WRAPPER="$JAVA_HOME_8/wrapper-bin/javac"

is_termux() {
    case "$PREFIX" in
        */com.termux/*)
            return 0
            ;;
    esac

    return 1
}

die() {
    echo ""
    echo "[!] $1"
    echo ""
    exit 1
}

run_quiet() {
    local msg="$1"
    shift
    local out
    if ! out="$("$@" 2>&1)"; then
        echo "$out"
        die "$msg"
    fi
}

echo ""
echo "======================================================================"
echo " openjdk-8-glibc installer"
echo " Java 8 nativo no Termux, sem proot-distro."
echo "======================================================================"
echo ""

if [ -z "$PREFIX" ] || ! is_termux; then
    die "Este instalador funciona somente no Termux."
fi

mkdir -p \
    "$PREFIX/etc/apt/sources.list.d" \
    "$PREFIX/etc/apt/trusted.gpg.d"

if ! command -v curl >/dev/null 2>&1; then
    echo "[+] Instalando curl..."
    run_quiet "Não foi possível instalar o curl." apt install -y curl
fi

if ! command -v gpg >/dev/null 2>&1; then
    echo "[+] Instalando gnupg..."
    run_quiet "Não foi possível instalar o gnupg." apt install -y gnupg
fi

echo "[+] Configurando repositório do OpenJDK 8..."

if [ ! -s "$KEYRING" ]; then
    curl -fsSL "$REPO_URL/public.gpg.key" |
        gpg --dearmor -o "$KEYRING" ||
        die "Não foi possível instalar a chave GPG."
fi

printf '%s\n' "$SOURCES_LINE" > "$SOURCES_LIST"

echo "[+] Configurando repositório glibc..."

if [ -f "$GLIBC_SOURCES_LIST" ]; then
    if ! grep -Fxq "$GLIBC_SOURCES_LINE" "$GLIBC_SOURCES_LIST"; then
        printf '%s\n' "$GLIBC_SOURCES_LINE" > "$GLIBC_SOURCES_LIST"
    fi
else
    printf '%s\n' "$GLIBC_SOURCES_LINE" > "$GLIBC_SOURCES_LIST"
fi

rm -f "$PREFIX/etc/apt/sources.list.d/termux-glibc.list"

echo "[+] Atualizando índices..."

run_quiet "Não foi possível atualizar os índices do APT." apt update -qq

echo "[+] Verificando dependências pendentes..."

if ! dpkg --audit >/dev/null 2>&1; then
    echo "[+] Existem pacotes incompletos. Corrigindo..."

    run_quiet "Não foi possível corrigir as dependências pendentes." apt-get --fix-broken install -y
fi

if ! dpkg-query -W -f='${Status}\n' glibc 2>/dev/null |
    grep -q '^install ok installed$'; then

    echo "[+] Instalando/verificando glibc..."

    if ! GLIBC_OUT="$(apt-get install -y glibc 2>&1)"; then
        echo "$GLIBC_OUT"
        echo "[!] A instalação direta do glibc falhou."
        echo "[+] Tentando corrigir as dependências..."

        run_quiet "Não foi possível instalar/corrigir o glibc." apt-get --fix-broken install -y
    fi

    run_quiet "Não foi possível finalizar o glibc." apt-get --fix-broken install -y
else
    echo "[+] glibc já está instalado."
fi

if ! dpkg-query -W -f='${Status}\n' openjdk-8-glibc 2>/dev/null |
    grep -q '^install ok installed$'; then

    echo "[+] Instalando openjdk-8-glibc..."

    if ! JDK_OUT="$(apt-get install -y openjdk-8-glibc 2>&1)"; then
        echo "$JDK_OUT"
        echo "[!] A instalação do OpenJDK 8 falhou."
        echo "[+] Tentando corrigir as dependências..."

        run_quiet "Não foi possível finalizar o OpenJDK 8." apt-get --fix-broken install -y
    fi
else
    echo "[+] openjdk-8-glibc já está instalado."
fi

echo "[+] Verificando instalação..."

if ! dpkg-query -W -f='${Status}\n' openjdk-8-glibc 2>/dev/null |
    grep -q '^install ok installed$'; then

    run_quiet "O pacote openjdk-8-glibc não pôde ser configurado." apt-get --fix-broken install -y
fi

if ! dpkg-query -W -f='${Status}\n' openjdk-8-glibc 2>/dev/null |
    grep -q '^install ok installed$'; then

    die "openjdk-8-glibc não foi instalado corretamente."
fi

if [ ! -x "$JAVA_WRAPPER" ]; then
    die "Wrapper do Java 8 não encontrado."
fi

if [ ! -x "$JAVAC_WRAPPER" ]; then
    die "Wrapper do javac 8 não encontrado."
fi

if [ ! -x "$PREFIX/bin/update-alternatives" ]; then
    die "update-alternatives não foi encontrado."
fi

echo "[+] Registrando Java 8 no update-alternatives..."

if ! ALT_OUT="$(update-alternatives \
    --install "$PREFIX/bin/java" \
    java \
    "$JAVA_WRAPPER" \
    50 \
    --slave "$PREFIX/bin/javac" \
    javac \
    "$JAVAC_WRAPPER" 2>&1)"; then
    echo "$ALT_OUT"
    die "Não foi possível registrar o Java 8 no update-alternatives."
fi

if [ "${OPENJDK8_GLIBC_NO_ACTIVATE:-0}" != "1" ]; then
    run_quiet "Não foi possível ativar o Java 8." update-alternatives --set java "$JAVA_WRAPPER"
else
    echo "[+] OPENJDK8_GLIBC_NO_ACTIVATE=1: pulando ativação automática."
fi

export JAVA_HOME="$JAVA_HOME_8"

if ! "$JAVA_WRAPPER" -version >/dev/null 2>&1; then
    die "Java 8 não conseguiu iniciar."
fi

if ! "$JAVAC_WRAPPER" -version >/dev/null 2>&1; then
    die "javac 8 não conseguiu iniciar."
fi

echo ""
echo "======================================================================"
echo " Instalação concluída com sucesso!"
echo "======================================================================"
echo ""
echo " Java 8 (openjdk-8-glibc):"
"$JAVA_WRAPPER" -version
echo ""
echo " Javac 8 (openjdk-8-glibc):"
"$JAVAC_WRAPPER" -version
echo ""
echo " JAVA_HOME:"
echo "$JAVA_HOME"
echo ""
echo " Java selecionado no update-alternatives:"
readlink -f "$PREFIX/bin/java"
echo ""
echo " Para trocar de versão:"
echo ""
echo "     update-alternatives --config java"
echo ""
echo "======================================================================"
echo ""
