Conteúdo do arquivo check_html.sh:

#!/usr/bin/env python3
"""
Exporta slides de um HTML de carrossel para PNGs individuais (1080×1350).
Cada slide é capturado individualmente via screenshot do elemento .slide.

Uso:
    python scripts/export_png.py
    python scripts/export_png.py --html /caminho/carousel.html --dir /caminho/slides

Dependencias:
    pip install playwright
    playwright install chromium
"""

import argparse
import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright


DEFAULT_HTML = "/home/roberto/carousel.html"
DEFAULT_OUT = "/home/roberto/slides"

# Playwright aguarda fonts.ready (promessa nativa do browser).
# Os timeouts abaixo sao margens de seguranca para ambientes sem rede.
FONT_INITIAL_MS = 2000
FONT_FALLBACK_MS = 5000


def resolve_path(p: str) -> str:
    return str(Path(p).expanduser().resolve())


def wait_fonts_loaded(page) -> None:
    """Aguarda fontes carregarem via API nativa do browser."""
    page.wait_for_timeout(FONT_INITIAL_MS)
    page.evaluate("document.fonts.ready")
    page.wait_for_timeout(FONT_INITIAL_MS)

    font_ok = page.evaluate("""
        () => document.fonts && document.fonts.size > 0
    """)
    if not font_ok:
        page.wait_for_timeout(FONT_FALLBACK_MS)
        page.evaluate("document.fonts.ready")


def main():
    parser = argparse.ArgumentParser(description="Exporta slides de carrossel HTML para PNGs")
    parser.add_argument("--html", default=DEFAULT_HTML, help=f"Caminho do HTML (default: {DEFAULT_HTML})")
    parser.add_argument("--dir", default=DEFAULT_OUT, help=f"Diretorio de saida (default: {DEFAULT_OUT})")
    args = parser.parse_args()

    html_path = resolve_path(args.html)
    out_dir = resolve_path(args.dir)

    if not os.path.isfile(html_path):
        print(f"Erro: arquivo HTML nao encontrado: {html_path}")
        sys.exit(1)

    os.makedirs(out_dir, exist_ok=True)
    file_url = f"file://{html_path}"

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 1200, "height": 1400})
            page.goto(file_url, wait_until="networkidle")

            wait_fonts_loaded(page)

            slides = page.locator(".slide")
            count = slides.count()

            if count == 0:
                print("Erro: nenhum elemento .slide encontrado no HTML.")
                browser.close()
                sys.exit(1)

            print(f"Exportando {count} slides para {out_dir} ...")

            for i in range(count):
                slide = slides.nth(i)
                slide.scroll_into_view_if_needed()
                page.wait_for_timeout(300)
                output_path = os.path.join(out_dir, f"slide_{i + 1:02d}.png")
                slide.screenshot(path=output_path)
                print(f"  slide_{i + 1:02d}.png")

            browser.close()
            print(f"\nConcluido. {count} PNGs salvos em: {out_dir}")

    except ImportError:
        print("Erro: Playwright nao instalado. Execute: pip install playwright && playwright install chromium")
        sys.exit(1)
    except Exception as e:
        print(f"Erro ao exportar PNGs: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
