#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "[!] Uso: $0 <arquivo1.deb> [arquivo2.deb ...]"
    exit 1
fi

OUT_DIR="${OUT_DIR:-$PWD/dist-repo}"
DISTRO="${DISTRO:-stable}"
COMPONENT="${COMPONENT:-main}"
ARCH="${ARCH:-aarch64}"
ORIGIN="${ORIGIN:-openjdk-8-glibc}"
LABEL="${LABEL:-$ORIGIN}"

POOL_DIR="$OUT_DIR/pool/$COMPONENT"
DIST_DIR="$OUT_DIR/dists/$DISTRO"
BINARY_DIR="$DIST_DIR/$COMPONENT/binary-$ARCH"

echo "[+] Saída do repositório: $OUT_DIR"

for cmd in dpkg-scanpackages gzip sha256sum dpkg-deb; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[!] Comando necessário não encontrado: $cmd"
        echo "    (em Debian/Ubuntu: apt-get install -y dpkg-dev)"
        exit 1
    fi
done

rm -rf "$OUT_DIR"
mkdir -p "$POOL_DIR" "$BINARY_DIR"

echo "[+] Copiando pacotes para o pool..."

for deb in "$@"; do
    if [ ! -f "$deb" ]; then
        echo "[!] Arquivo não encontrado: $deb"
        exit 1
    fi

    pkg_name=$(dpkg-deb -f "$deb" Package)
    first_letter="${pkg_name:0:1}"

    dest_dir="$POOL_DIR/$first_letter/$pkg_name"
    mkdir -p "$dest_dir"
    cp -a "$deb" "$dest_dir/"

    echo "    - $pkg_name -> pool/$COMPONENT/$first_letter/$pkg_name/$(basename "$deb")"
done

echo "[+] Gerando Packages..."

(
    cd "$OUT_DIR"
    dpkg-scanpackages --arch "$ARCH" "pool/$COMPONENT" /dev/null \
        > "dists/$DISTRO/$COMPONENT/binary-$ARCH/Packages"
)

gzip -9 -c "$BINARY_DIR/Packages" > "$BINARY_DIR/Packages.gz"

echo "[+] Gerando Release..."

RELEASE_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S UTC")

{
    echo "Origin: $ORIGIN"
    echo "Label: $LABEL"
    echo "Suite: $DISTRO"
    echo "Codename: $DISTRO"
    echo "Architectures: $ARCH"
    echo "Components: $COMPONENT"
    echo "Date: $RELEASE_DATE"

    for algo in md5sum sha1sum sha256sum; do
        case "$algo" in
            md5sum)    header="MD5Sum:" ;;
            sha1sum)   header="SHA1:" ;;
            sha256sum) header="SHA256:" ;;
        esac

        echo "$header"

        for f in "$COMPONENT/binary-$ARCH/Packages" "$COMPONENT/binary-$ARCH/Packages.gz"; do
            size=$(stat -c%s "$DIST_DIR/$f")
            hash=$("$algo" "$DIST_DIR/$f" | awk '{print $1}')
            echo " $hash $size $f"
        done
    done
} > "$DIST_DIR/Release"

if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    echo "[+] Assinando Release com GPG..."

    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    trap 'rm -rf "$GNUPGHOME"' EXIT

    echo "$GPG_PRIVATE_KEY" | gpg --batch --import

    KEY_ID=$(gpg --batch --list-secret-keys --with-colons | awk -F: '/^sec/ {print $5; exit}')

    gpg --batch --yes --local-user "$KEY_ID" \
        --detach-sign --armor \
        -o "$DIST_DIR/Release.gpg" "$DIST_DIR/Release"

    gpg --batch --yes --local-user "$KEY_ID" \
        --clearsign \
        -o "$DIST_DIR/InRelease" "$DIST_DIR/Release"

    echo "[+] Release assinado (Release.gpg + InRelease gerados)."
    echo "[+] Chave pública exportada em: $OUT_DIR/public.gpg.key"
    gpg --batch --armor --export "$KEY_ID" > "$OUT_DIR/public.gpg.key"
else
    echo "[i] GPG_PRIVATE_KEY não definida — repositório NÃO assinado."
    echo "    Quem for adicionar a fonte precisa usar [trusted=yes]."
fi

echo
echo "=========================================="
echo "        REPOSITÓRIO APT GERADO"
echo "=========================================="
echo
echo "[+] Pasta: $OUT_DIR"
echo
echo "[+] Linha para o usuário adicionar (sem assinatura):"
echo "    echo \"deb [trusted=yes] <SUA_URL_BASE>/ $DISTRO $COMPONENT\" > \$PREFIX/etc/apt/sources.list.d/$ORIGIN.list"
echo
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
echo "[+] Linha para o usuário adicionar (com assinatura):"
echo "    curl -fsSL <SUA_URL_BASE>/public.gpg.key -o \$PREFIX/etc/apt/trusted.gpg.d/$ORIGIN.gpg"
echo "    echo \"deb <SUA_URL_BASE>/ $DISTRO $COMPONENT\" > \$PREFIX/etc/apt/sources.list.d/$ORIGIN.list"
fi
echo