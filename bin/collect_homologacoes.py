#!/usr/bin/env python3
"""
Coleta publicações do PJe Comunica que indicam homologação de cálculo
para os advogados do escritório Capano no TJSP.

Busca por termos no texto das publicações:
  - "homologo" + ("cálculo" ou "calculo")
  - "homologação" + "cálculo"
  - "homologatória" + "cálculo"

API: https://comunicaapi.pje.jus.br/api/v1/comunicacao
"""

import urllib.request
import urllib.parse
import json
import time
import sys
import os
import re

API_BASE = "https://comunicaapi.pje.jus.br/api/v1/comunicacao"
ADVOGADOS = [
    "FERNANDO FABIANI CAPANO",
    "EVANDRO CAPANO",
    "LEONARDO SALVADOR PASSAFARO",
]
TRIBUNAL = "TJSP"
MAX_PAGES = 65  # 6452 items / 100 per page = 65 pages
TARGET_MATCHES = 50


def fetch_page(advogado, pagina):
    params = urllib.parse.urlencode({
        "nomeAdvogado": advogado,
        "siglaTribunal": TRIBUNAL,
        "pagina": pagina,
    })
    url = f"{API_BASE}?{params}"
    req = urllib.request.Request(url, headers={"accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"  ERRO pagina {pagina}: {e}")
        return None


def is_homologacao_calculo(texto):
    """Detecta se o texto da publicação indica homologação de cálculo."""
    if not texto:
        return False
    txt = texto.lower()

    # Padrões positivos
    patterns = [
        r'homolog\w*\s.{0,80}(cálculo|calculo)',
        r'(cálculo|calculo)\s.{0,80}homolog',
        r'homologo.*cálculo',
        r'homologatória.*cálculo',
        r'homologação.*cálculo',
        r'homologo.*o\s+cálculo',
        r'homologo.*a\s+conta',
        r'homologo.*os\s+cálculos',
        r'decisão\s+homologatória.*cálc',
    ]
    for p in patterns:
        if re.search(p, txt):
            return True
    return False


def extract_trecho(texto, max_len=200):
    """Extrai trecho relevante da publicação."""
    txt_lower = texto.lower()
    idx = txt_lower.find('homolog')
    if idx < 0:
        idx = txt_lower.find('cálculo')
    if idx < 0:
        return texto[:max_len]
    start = max(0, idx - 60)
    end = min(len(texto), idx + max_len - 60)
    return ("..." if start > 0 else "") + texto[start:end] + ("..." if end < len(texto) else "")


def main():
    all_matches = []
    seen_processos = set()

    for advogado in ADVOGADOS:
        print(f"\n{'='*60}")
        print(f"Advogado: {advogado}")
        print(f"{'='*60}")

        # Primeira pagina para saber total
        data = fetch_page(advogado, 1)
        if not data or data.get("status") != "success":
            print(f"  Falha na API para {advogado}")
            continue

        total = data.get("count", 0)
        total_pages = min((total + 99) // 100, MAX_PAGES)
        print(f"  Total comunicacoes: {total} ({total_pages} paginas)")

        page = 1
        while page <= total_pages and len(all_matches) < TARGET_MATCHES:
            if page > 1:
                data = fetch_page(advogado, page)
                if not data:
                    page += 1
                    continue

            items = data.get("items", [])
            if not items:
                break

            for item in items:
                texto = item.get("texto", "") or ""
                if not is_homologacao_calculo(texto):
                    continue

                proc = item.get("numeroprocessocommascara", "")
                if proc in seen_processos:
                    continue
                seen_processos.add(proc)

                # Extrair dados
                destinatarios = item.get("destinatarios", [])
                parte_ativa = destinatarios[0]["nome"] if destinatarios else ""

                # Parte passiva: extrair do texto se possivel
                parte_passiva = ""
                m = re.search(r'(?:FAZENDA|Estado de São Paulo|SPPREV|CBPM|DER)', texto, re.IGNORECASE)
                if m:
                    parte_passiva = m.group(0)

                orgao = item.get("nomeOrgao", "")

                # Parse foro/vara
                parts = orgao.split(" - ")
                if len(parts) >= 3:
                    foro = parts[0] + " - " + parts[1]
                    vara = " - ".join(parts[2:])
                elif len(parts) == 2:
                    foro = parts[0]
                    vara = parts[1]
                else:
                    foro = orgao
                    vara = ""

                # Advogados
                advs = [a["advogado"]["nome"] for a in item.get("destinatarioadvogados", []) if a.get("advogado")]

                match = {
                    "processo": proc,
                    "incidente_depre": "",
                    "classe": item.get("nomeClasse", ""),
                    "parte_ativa": parte_ativa,
                    "parte_passiva": parte_passiva,
                    "foro": foro.strip(),
                    "vara": vara.strip(),
                    "advogados": advs,
                    "data_publicacao": item.get("data_disponibilizacao", ""),
                    "trecho": extract_trecho(texto),
                    "orgao": orgao,
                }
                all_matches.append(match)
                print(f"  [{len(all_matches)}/{TARGET_MATCHES}] {proc} | {item.get('data_disponibilizacao','')} | {parte_ativa[:30]}")

                if len(all_matches) >= TARGET_MATCHES:
                    break

            page += 1
            time.sleep(0.3)  # rate limiting

        if len(all_matches) >= TARGET_MATCHES:
            break

    # Salvar
    output_path = "reports/homologacoes_calculo.json"
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_matches, f, ensure_ascii=False, indent=2)

    print(f"\n{'='*60}")
    print(f"RESULTADO: {len(all_matches)} processos com homologacao de calculo")
    print(f"Salvo em: {output_path}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
