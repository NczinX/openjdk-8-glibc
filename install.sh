#!/bin/sh
set -e

REPO_URL="https://openjdk-8-glibc.pages.dev"
KEYRING="$PREFIX/etc/apt/trusted.gpg.d/openjdk-8-glibc.gpg"
SOURCES_LIST="$PREFIX/etc/apt/sources.list.d/openjdk-8-glibc.list"
SOURCES_LINE="deb $REPO_URL/ stable main"
JAVA_WRAPPER="$PREFIX/opt/openjdk-8/wrapper-bin/java"

is_termux() {
    case "$PREFIX" in
        */com.termux/*) return 0 ;;
    esac
    return 1
}

echo ""
echo "======================================================================"
echo " openjdk-8-glibc installer"
echo " Java 8 nativo no Termux, sem proot-distro."
echo "======================================================================"
echo ""

if [ -z "$PREFIX" ] || ! is_termux; then
    echo "======================================================================"
    echo " Este instalador é feito só para o Termux (Android)."
    echo " Não detectei um ambiente Termux válido nesse sistema."
    echo "======================================================================"
    echo ""
    exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
    echo "[+] Instalando gnupg..."
    pkg install -y gnupg
fi

echo "[+] Configurando repositório..."

if [ ! -f "$KEYRING" ]; then
    curl -fsSL "$REPO_URL/public.gpg.key" | gpg --dearmor -o "$KEYRING"
fi

if [ ! -f "$SOURCES_LIST" ] || [ "$(cat "$SOURCES_LIST")" != "$SOURCES_LINE" ]; then
    echo "$SOURCES_LINE" > "$SOURCES_LIST"
fi

echo "[+] Atualizando índices..."
apt update -qq

echo "[+] Instalando openjdk-8-glibc..."
apt install -y openjdk-8-glibc

if [ "$OPENJDK8_GLIBC_NO_ACTIVATE" != "1" ] && [ -x "$JAVA_WRAPPER" ]; then
    echo "[+] Ativando Java 8 (update-alternatives)..."
    update-alternatives --set java "$JAVA_WRAPPER"
fi

CURRENT_JAVA_HOME=""
if command -v java >/dev/null 2>&1; then
    CURRENT_JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi

echo ""
echo "======================================================================"
echo " Instalação concluída!"
echo ""
echo " Abra uma sessão NOVA do Termux, ou rode um dos comandos abaixo na"
echo " sessão atual para o JAVA_HOME atualizar:"
echo ""
echo "     source \$PREFIX/etc/profile.d/java.sh"
if [ -n "$CURRENT_JAVA_HOME" ]; then
echo ""
echo " ou, direto (equivalente):"
echo ""
echo "     export JAVA_HOME=\"$CURRENT_JAVA_HOME\""
fi
echo ""
echo " Depois confira:"
echo ""
echo "     java -version"
echo "     echo \$JAVA_HOME"
echo ""
echo " Pra trocar de volta pra outra versão do Java:"
echo ""
echo "     update-alternatives --config java"
echo "======================================================================"
echo ""
