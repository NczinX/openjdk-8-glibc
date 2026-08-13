#!/data/data/com.termux/files/usr/bin/bash
set -e

PKG_NAME="openjdk-8-glibc"
PKG_ARCH="aarch64"
PKG_MAINTAINER="NczinX (@67nc in dc)"
PKG_DESCRIPTION="Eclipse Temurin OpenJDK 8 for Termux AArch64"
PKG_URL="https://github.com/NczinX/openjdk-8-glibc"

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
WORK="$PWD/build"
ROOT="$WORK/root"
DEBIAN="$ROOT/DEBIAN"
JSON="$WORK/adoptium.json"
CACHE_DIR="$PWD/cache"

GLIBC_LOADER="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"

SKIP_GLIBC_CHECK="${SKIP_GLIBC_CHECK:-0}"
if [ -n "${CI:-}" ]; then
    SKIP_GLIBC_CHECK=1
fi

PYTHON_BIN="python"
if ! command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python3"
fi

echo "[+] Consultando Adoptium..."

rm -rf "$WORK"

mkdir -p "$DEBIAN"
mkdir -p "$CACHE_DIR"

if [ "$SKIP_GLIBC_CHECK" != "1" ]; then
    if [ ! -x "$GLIBC_LOADER" ]; then
        echo "[!] GLIBC não encontrado:"
        echo "    $GLIBC_LOADER"
        exit 1
    fi
else
    echo "[i] SKIP_GLIBC_CHECK ativo — pulando checagem local do glibc (build em CI)."
fi

if ! command -v patchelf >/dev/null 2>&1; then
    echo "[!] patchelf não encontrado."
    exit 1
fi

if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "[!] dpkg-deb não encontrado."
    exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "[!] python/python3 não encontrado."
    exit 1
fi

curl -fsSL \
    'https://api.adoptium.net/v3/assets/latest/8/hotspot' \
    -o "$JSON"

readarray -t INFO < <(
"$PYTHON_BIN" - "$JSON" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

for item in data:
    binary = item.get("binary", {})
    package = binary.get("package", {})
    version = item.get("version", {})

    if (
        binary.get("os") == "linux"
        and binary.get("architecture") == "aarch64"
        and binary.get("image_type") == "jdk"
        and binary.get("jvm_impl") == "hotspot"
    ):
        print(item.get("release_name", ""))
        print(version.get("openjdk_version", ""))
        print(package.get("name", ""))
        print(package.get("link", ""))
        print(package.get("checksum", ""))
        break
PY
)

RELEASE="${INFO[0]}"
JAVA_VERSION="${INFO[1]}"
ARCHIVE="${INFO[2]}"
DOWNLOAD_URL="${INFO[3]}"
CHECKSUM="${INFO[4]}"

if [ -z "$DOWNLOAD_URL" ]; then
    echo "[!] Não foi possível encontrar um JDK Temurin 8 AArch64."
    exit 1
fi

echo "[+] Release : $RELEASE"
echo "[+] Version : $JAVA_VERSION"
echo "[+] File    : $ARCHIVE"
echo "[+] URL     : $DOWNLOAD_URL"

PKG_VERSION=$("$PYTHON_BIN" - "$JAVA_VERSION" <<'PY'
import sys
import re

v = sys.argv[1]

m = re.search(r'1\.8\.0_(\d+)-b(\d+)', v)

if not m:
    raise SystemExit("Versão inválida: " + v)

print(f"8.{m.group(1)}.b{m.group(2)}")
PY
)

echo "[+] Versão do pacote: $PKG_VERSION"

CACHED_ARCHIVE="$CACHE_DIR/$ARCHIVE"
ARCHIVE_PATH="$WORK/$ARCHIVE"

NEED_DOWNLOAD=1

if [ -f "$CACHED_ARCHIVE" ]; then
    echo "[+] Encontrado em cache: $CACHED_ARCHIVE"
    echo "[+] Verificando SHA256 do cache..."

    CACHED_CHECKSUM=$(sha256sum "$CACHED_ARCHIVE" | awk '{print $1}')

    if [ "$CACHED_CHECKSUM" = "$CHECKSUM" ]; then
        echo "[+] Cache válido, pulando download."
        NEED_DOWNLOAD=0
    else
        echo "[!] Checksum do cache não confere (arquivo desatualizado/corrompido)."
        echo "    Esperado: $CHECKSUM"
        echo "    Obtido:   $CACHED_CHECKSUM"
        rm -f "$CACHED_ARCHIVE"
    fi
fi

if [ "$NEED_DOWNLOAD" -eq 1 ]; then
    echo "[+] Baixando..."

    curl -fL \
        --retry 3 \
        --retry-delay 2 \
        -o "$CACHED_ARCHIVE" \
        "$DOWNLOAD_URL"

    echo "[+] Verificando SHA256..."

    ACTUAL_CHECKSUM=$(sha256sum "$CACHED_ARCHIVE" | awk '{print $1}')

    if [ "$ACTUAL_CHECKSUM" != "$CHECKSUM" ]; then
        echo "[!] SHA256 inválido!"
        echo "    Esperado: $CHECKSUM"
        echo "    Obtido:   $ACTUAL_CHECKSUM"
        rm -f "$CACHED_ARCHIVE"
        exit 1
    fi

    echo "[+] SHA256 OK"
fi

cp "$CACHED_ARCHIVE" "$ARCHIVE_PATH"

echo "[+] Extraindo Temurin..."

mkdir -p "$WORK/extract"

tar -xzf "$ARCHIVE_PATH" -C "$WORK/extract"

JDK_DIR=$(find "$WORK/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)

if [ -z "$JDK_DIR" ]; then
    echo "[!] JDK não encontrado."
    exit 1
fi

JAVA_DIR="$ROOT/data/data/com.termux/files/usr/opt/openjdk-8"
WRAPPER_DIR="$JAVA_DIR/wrapper-bin"
PROFILE_DIR="$JAVA_DIR/etc/profile.d"

mkdir -p "$JAVA_DIR"
mkdir -p "$WRAPPER_DIR"
mkdir -p "$PROFILE_DIR"

echo "[+] Instalando Temurin..."

cp -a "$JDK_DIR"/. "$JAVA_DIR"/

echo "[+] Criando profile.d (define JAVA_HOME quando este JDK está ativo)..."

cat > "$PROFILE_DIR/java.sh" <<'EOF'
export JAVA_HOME="/data/data/com.termux/files/usr/opt/openjdk-8"
EOF

echo "[+] Corrigindo permissões..."

find "$JAVA_DIR" -type d -exec chmod 755 {} \;
find "$JAVA_DIR" -type f -exec chmod 644 {} \;
find "$JAVA_DIR/bin" -type f -exec chmod 755 {} \;
chmod 644 "$PROFILE_DIR/java.sh"

echo "[+] Corrigindo interpreters ELF..."

ELF_COUNT=0

while IFS= read -r -d '' binary; do
    if file "$binary" | grep -q 'ELF 64-bit.*ARM aarch64'; then
        CURRENT_INTERPRETER=$(patchelf --print-interpreter "$binary" 2>/dev/null || true)

        if [ "$CURRENT_INTERPRETER" != "$GLIBC_LOADER" ]; then
            echo "[+] Corrigindo: ${binary#$JAVA_DIR/}"
            patchelf --set-interpreter "$GLIBC_LOADER" "$binary"
        fi

        ELF_COUNT=$((ELF_COUNT + 1))
    fi
done < <(find "$JAVA_DIR/bin" -maxdepth 1 -type f -executable -print0)

if [ "$ELF_COUNT" -eq 0 ]; then
    echo "[!] Nenhum ELF encontrado em bin/."
    exit 1
fi

echo "[+] ELF corrigidos: $ELF_COUNT"

echo "[+] Verificando interpreters..."

while IFS= read -r -d '' binary; do
    if file "$binary" | grep -q 'ELF 64-bit.*ARM aarch64'; then
        INTERPRETER=$(patchelf --print-interpreter "$binary")

        if [ "$INTERPRETER" != "$GLIBC_LOADER" ]; then
            echo "[!] Interpreter incorreto:"
            echo "    $binary"
            echo "    Esperado: $GLIBC_LOADER"
            echo "    Obtido:   $INTERPRETER"
            exit 1
        fi
    fi
done < <(find "$JAVA_DIR/bin" -maxdepth 1 -type f -executable -print0)

echo "[+] Todos os interpreters estão corretos."

echo "[+] Criando wrappers..."

create_wrapper() {
    local name="$1"
    local target="$2"

    cat > "$WRAPPER_DIR/$name" <<EOF
#!/data/data/com.termux/files/usr/bin/bash

PREFIX="\${PREFIX:-/data/data/com.termux/files/usr}"
JAVA_HOME="\$PREFIX/opt/openjdk-8"

export JAVA_HOME
unset LD_PRELOAD
unset LD_LIBRARY_PATH

exec "\$JAVA_HOME/bin/$target" "\$@"
EOF

    chmod 755 "$WRAPPER_DIR/$name"
}

LAUNCHER_NAMES=()

while IFS= read -r -d '' binary; do
    name="$(basename "$binary")"

    case "$name" in
        java-rmi.cgi)
            continue
            ;;
    esac

    create_wrapper "$name" "$name"
    LAUNCHER_NAMES+=("$name")
done < <(find "$JAVA_DIR/bin" -maxdepth 1 -type f -executable -print0)

LAUNCHER_COUNT=${#LAUNCHER_NAMES[@]}

if [ -f "$JAVA_DIR/bin/java-rmi.cgi" ]; then
    create_wrapper "java-rmi.cgi" "java-rmi.cgi"
    LAUNCHER_NAMES+=("java-rmi.cgi")
    LAUNCHER_COUNT=$((LAUNCHER_COUNT + 1))
fi

echo "[+] Wrappers criados: $LAUNCHER_COUNT"

if [ -z "${LAUNCHER_NAMES[*]:-}" ]; then
    echo "[!] Nenhum wrapper criado."
    exit 1
fi

MASTER_NAME="java"
HAS_JAVA=0
SLAVE_NAMES=()

for n in "${LAUNCHER_NAMES[@]}"; do
    if [ "$n" = "$MASTER_NAME" ]; then
        HAS_JAVA=1
    else
        SLAVE_NAMES+=("$n")
    fi
done

if [ "$HAS_JAVA" -ne 1 ]; then
    echo "[!] Wrapper 'java' não encontrado, não é possível registrar alternatives."
    exit 1
fi

echo "[+] Criando control..."

cat > "$DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: $PKG_ARCH
Maintainer: $PKG_MAINTAINER
Homepage: $PKG_URL
Section: java
Priority: optional
Depends: glibc, patchelf, termux-tools
Description: $PKG_DESCRIPTION
 Eclipse Temurin OpenJDK 8 running through the Termux glibc environment.
EOF

echo "[+] Gerando comando update-alternatives..."

ALT_SLAVES=""
for n in "${SLAVE_NAMES[@]}"; do
    ALT_SLAVES+="      --slave \"\$PREFIX/bin/$n\" \"$n\" \"\$JAVA_HOME/wrapper-bin/$n\" \\"$'\n'
done

ALT_SLAVES+="      --slave \"\$PREFIX/etc/profile.d/java.sh\" \"java-profile\" \"\$JAVA_HOME/etc/profile.d/java.sh\""

{
cat <<EOF
#!/data/data/com.termux/files/usr/bin/bash

PREFIX="\${PREFIX:-/data/data/com.termux/files/usr}"
JAVA_HOME="\$PREFIX/opt/openjdk-8"
GLIBC_LOADER="\$PREFIX/glibc/lib/ld-linux-aarch64.so.1"

if [ ! -x "\$GLIBC_LOADER" ]; then
    echo "[!] glibc não está instalado corretamente."
    exit 1
fi

if [ ! -x "\$JAVA_HOME/bin/java" ]; then
    echo "[!] Java 8 não foi instalado corretamente."
    exit 1
fi

if ! command -v patchelf >/dev/null 2>&1; then
    echo "[!] patchelf não está instalado."
    exit 1
fi

FAILED=0

while IFS= read -r -d '' binary; do
    if file "\$binary" | grep -q 'ELF 64-bit.*ARM aarch64'; then
        INTERPRETER=\$(patchelf --print-interpreter "\$binary" 2>/dev/null || true)

        if [ "\$INTERPRETER" != "\$GLIBC_LOADER" ]; then
            echo "[!] Interpreter incorreto:"
            echo "    \$binary"
            echo "    \$INTERPRETER"
            FAILED=1
        fi
    fi
done < <(find "\$JAVA_HOME/bin" -maxdepth 1 -type f -executable -print0)

if [ "\$FAILED" -ne 0 ]; then
    echo "[!] Um ou mais binários possuem interpreter incorreto."
    exit 1
fi

if [ ! -x "\$PREFIX/bin/update-alternatives" ]; then
    echo "[!] update-alternatives não encontrado (pacote termux-tools ausente?)."
    exit 1
fi

echo "[+] Registrando Java 8 no update-alternatives (prioridade 50)..."

"\$PREFIX/bin/update-alternatives" \\
    --install "\$PREFIX/bin/java" "java" "\$JAVA_HOME/wrapper-bin/java" 50 \\
$ALT_SLAVES

echo "[+] Java 8 registrado. Para ativar:"
echo "    update-alternatives --config java"

exit 0
EOF
} > "$DEBIAN/postinst"

cat > "$DEBIAN/prerm" <<EOF
#!/data/data/com.termux/files/usr/bin/bash

PREFIX="\${PREFIX:-/data/data/com.termux/files/usr}"
JAVA_HOME="\$PREFIX/opt/openjdk-8"

if [ -x "\$PREFIX/bin/update-alternatives" ]; then
    "\$PREFIX/bin/update-alternatives" --remove "java" "\$JAVA_HOME/wrapper-bin/java" || true
fi

exit 0
EOF

chmod 755 "$DEBIAN"
chmod 644 "$DEBIAN/control"
chmod 755 "$DEBIAN/postinst"
chmod 755 "$DEBIAN/prerm"

chmod 755 "$ROOT"
chmod 755 "$ROOT/data"
chmod 755 "$ROOT/data/data"
chmod 755 "$ROOT/data/data/com.termux"
chmod 755 "$ROOT/data/data/com.termux/files"
chmod 755 "$ROOT/data/data/com.termux/files/usr"
chmod 755 "$ROOT/data/data/com.termux/files/usr/opt"

echo "[+] Verificando pacote antes de construir..."

PACKAGE_ELF_COUNT=0

while IFS= read -r -d '' binary; do
    if file "$binary" | grep -q 'ELF 64-bit.*ARM aarch64'; then
        INTERPRETER=$(patchelf --print-interpreter "$binary")

        if [ "$INTERPRETER" != "$GLIBC_LOADER" ]; then
            echo "[!] ELF com interpreter incorreto:"
            echo "    $binary"
            echo "    $INTERPRETER"
            exit 1
        fi

        PACKAGE_ELF_COUNT=$((PACKAGE_ELF_COUNT + 1))
    fi
done < <(find "$JAVA_DIR/bin" -maxdepth 1 -type f -executable -print0)

echo "[+] ELF verificados: $PACKAGE_ELF_COUNT"

if [ "$PACKAGE_ELF_COUNT" -ne "$ELF_COUNT" ]; then
    echo "[!] Quantidade de ELF inconsistente."
    exit 1
fi

if [ ! -x "$JAVA_DIR/bin/java" ]; then
    echo "[!] java não encontrado."
    exit 1
fi

if [ ! -x "$WRAPPER_DIR/java" ]; then
    echo "[!] wrapper java não encontrado."
    exit 1
fi

if [ ! -x "$WRAPPER_DIR/jar" ]; then
    echo "[!] wrapper jar não encontrado."
    exit 1
fi

if [ ! -x "$WRAPPER_DIR/javac" ]; then
    echo "[!] wrapper javac não encontrado."
    exit 1
fi

if [ ! -f "$PROFILE_DIR/java.sh" ]; then
    echo "[!] profile.d/java.sh não encontrado."
    exit 1
fi

OUTPUT="$PWD/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"

rm -f "$OUTPUT"

echo "[+] Construindo .deb..."

dpkg-deb \
    --build \
    --root-owner-group \
    "$ROOT" \
    "$OUTPUT"

echo
echo "=========================================="
echo "        JAVA 8 GLIBC CONCLUÍDO"
echo "=========================================="
echo
echo "[+] Pacote : $OUTPUT"
echo "[+] Cache  : $CACHE_DIR"
echo "[+] Java   : $JAVA_VERSION"
echo "[+] Release: $RELEASE"
echo "[+] ELF    : $ELF_COUNT"
echo "[+] Launchers: $LAUNCHER_COUNT"
echo
echo "[+] Interpreter:"
echo "    $GLIBC_LOADER"
echo
echo "[+] Instalação:"
echo "    dpkg -i $(basename "$OUTPUT")"
echo
echo "[+] O Java 8 fica registrado no update-alternatives (prioridade 50,"
echo "    NÃO vira o padrão automaticamente). Para ativar:"
echo "    update-alternatives --config java"
echo
echo "[+] Depois de ativar, abra uma NOVA sessão do Termux (ou rode"
echo "    'source /data/data/com.termux/files/usr/etc/profile.d/java.sh')"
echo "    para o JAVA_HOME atualizar na shell atual."
echo
echo "[+] Teste:"
echo "    java -version"
echo "    echo \$JAVA_HOME"
echo "    javac -version"
echo "    jar --help"
echo "    javadoc -version"
echo