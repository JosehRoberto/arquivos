#!/usr/bin/env bash
# embed_fonts.sh — Gera blocos @font-face com base64 para carrossel BrandsDecoded
# Baixa pacotes @fontsource do npm, converte .woff2 para base64 e
# produz CSS pronto para colar dentro do <style> do HTML.
#
# Uso: ./scripts/embed_fonts.sh <fonte-headline> <fonte-body>
# Ex.: ./scripts/embed_fonts.sh barlow-condensed plus-jakarta-sans
#       ./scripts/embed_fonts.sh playfair-display dm-sans > assets/fonts.css
#
# Opcoes:
#   --weights-head W1,W2,...  pesos para fonte headline (padrao: 700,800,900)
#   --weights-body W1,W2,...  pesos para fonte body     (padrao: 400,500,600,700,800)

set -euo pipefail

HEAD_FONT=""
BODY_FONT=""
HEAD_WEIGHTS="700,800,900"
BODY_WEIGHTS="400,500,600,700,800"

while [ $# -gt 0 ]; do
    case "$1" in
        --weights-head)
            HEAD_WEIGHTS="$2"; shift 2 ;;
        --weights-body)
            BODY_WEIGHTS="$2"; shift 2 ;;
        *)
            if [ -z "$HEAD_FONT" ]; then
                HEAD_FONT="$1"
            elif [ -z "$BODY_FONT" ]; then
                BODY_FONT="$1"
            else
                echo "Erro: argumento inesperado: $1" >&2
                echo "Uso: $0 [--weights-head W1,W2,...] [--weights-body W1,W2,...] <fonte-headline> <fonte-body>" >&2
                exit 1
            fi
            shift ;;
    esac
done

if [ -z "$HEAD_FONT" ] || [ -z "$BODY_FONT" ]; then
    echo "Uso: $0 [--weights-head W1,W2,...] [--weights-body W1,W2,...] <fonte-headline> <fonte-body>" >&2
    echo "Ex.:  $0 barlow-condensed plus-jakarta-sans" >&2
    echo "Ex.:  $0 --weights-head 900 --weights-body 400,700 playfair-display dm-sans" >&2
    exit 1
fi

# ---------------------------------------------------------------
# Dependencias
# ---------------------------------------------------------------
if ! command -v npm &>/dev/null; then
    echo "Erro: npm nao encontrado. Instale Node.js (apt install nodejs npm)." >&2
    exit 1
fi

if ! command -v base64 &>/dev/null; then
    echo "Erro: base64 nao encontrado (coreutils)." >&2
    exit 1
fi

# ---------------------------------------------------------------
# Temp dir unico para todas as operacoes
# ---------------------------------------------------------------
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# ---------------------------------------------------------------
# Converte "barlow-condensed" -> "Barlow Condensed"
# (funcao separada e chamada antes das funcoes que usam local)
# ---------------------------------------------------------------
pkg_to_family() {
    echo "$1" | awk -F'-' '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1' OFS=' '
}

# ---------------------------------------------------------------
# Processa um @fontsource package: download -> extract -> base64
# Recebe: pkg_name family_name allowed_weights_csv
# Ex.: process_font barlow-condensed "Barlow Condensed" "700,800,900"
# ---------------------------------------------------------------
process_font() {
    local pkg="$1"
    local family="$2"
    local allowed_csv="$3"
    local out_dir="$WORKDIR/$pkg"

    mkdir -p "$out_dir"

    local tarball
    tarball=$(npm pack "@fontsource/$pkg" --silent 2>/dev/null || true)
    if [ -z "$tarball" ] || [ ! -f "$tarball" ]; then
        echo "/* Erro: nao foi possivel baixar @fontsource/$pkg */" >&2
        return
    fi

    mv "$tarball" "$out_dir/"
    tar -xzf "$out_dir/$(basename "$tarball")" -C "$out_dir"

    local files_dir="$out_dir/package/files"
    if [ ! -d "$files_dir" ]; then
        files_dir="$out_dir/package"
    fi

    local count=0
    for woff2 in "$files_dir"/*.woff2; do
        [ -f "$woff2" ] || continue
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        echo "/* Aviso: nenhum .woff2 encontrado em @fontsource/$pkg */" >&2
        return
    fi

    echo "/* $family — $count pesos */"
    echo ""

    for woff2 in "$files_dir"/*.woff2; do
        [ -f "$woff2" ] || continue
        local basename
        basename=$(basename "$woff2" .woff2)

        IFS='-' read -ra parts <<< "$basename"
        local n=${#parts[@]}
        local weight="${parts[$((n-2))]}"
        local style="${parts[$((n-1))]}"

        case "$style" in
            normal|italic) ;;
            *) style="normal" ;;
        esac

        local b64
        b64=$(base64 -w0 "$woff2")

        cat << CSSEOF
@font-face {
    font-family: '$family';
    font-style: $style;
    font-weight: $weight;
    src: url(data:font/woff2;base64,$b64) format('woff2');
    font-display: swap;
}

CSSEOF
    done
}

# ---------------------------------------------------------------
# Resolve os nomes de exibicao ANTES de chamar process_font
# para evitar interacao entre local e command substitution.
# ---------------------------------------------------------------
HEAD_FAMILY=$(pkg_to_family "$HEAD_FONT")
BODY_FAMILY=$(pkg_to_family "$BODY_FONT")

# ---------------------------------------------------------------
# Saida CSS
# ---------------------------------------------------------------
cat << "INFO"
/*
 * Fontes embedadas via @fontsource — gerado por embed_fonts.sh
 * Regra BrandsDecoded: nunca usar Google Fonts via <link>.
 * Embutir como base64 no <style> do HTML para garantir renderizacao
 * identica no preview (browser) e no export (Playwright headless).
 */

INFO

process_font "$HEAD_FONT" "$HEAD_FAMILY"
process_font "$BODY_FONT" "$BODY_FAMILY"
