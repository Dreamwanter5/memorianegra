#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import re
import csv
import xml.etree.ElementTree as ET
from pathlib import Path
import unicodedata

ENCODING = "latin-1"

# ------------------------------------------------------------
# Função principal de limpeza de escapes
# ------------------------------------------------------------
def decodificar_escapamentos(texto):
    r"""
    Converte sequências do tipo \xXX ou \Xxx (onde XX são hex) em caracteres reais.
    Exemplo: "S\XC3\XA3o Paulo" -> "São Paulo"
    """
    if not texto or not isinstance(texto, str):
        return texto
    # Encontra todas as ocorrências de \xXX ou \Xxx
    padrao = re.compile(r'\\[xX]([0-9A-Fa-f]{2})')
    partes = []
    pos = 0
    for match in padrao.finditer(texto):
        # Texto antes do escape (codificado em Latin-1)
        partes.append(texto[pos:match.start()].encode('latin-1', errors='replace'))
        # Byte do escape
        byte_val = int(match.group(1), 16)
        partes.append(bytes([byte_val]))
        pos = match.end()
    # Restante do texto
    partes.append(texto[pos:].encode('latin-1', errors='replace'))
    # Junta todos os bytes e decodifica como UTF-8
    try:
        resultado = b''.join(partes).decode('utf-8')
    except UnicodeDecodeError:
        resultado = b''.join(partes).decode('latin-1', errors='replace')
    return resultado

# ------------------------------------------------------------
# Outras funções auxiliares (limpeza, mapeamento)
# ------------------------------------------------------------
def limpar_autor(nome):
    if not nome:
        return ""
    nome = re.sub(r'\s*https?://[^\s]+$', '', nome)
    nome = re.sub(r'[\(\,]\s*\d{4}[-\d]*\s*[\)]?$', '', nome)
    nome = re.sub(r'\s+\d{4}[-\d]*\s*$', '', nome)
    nome = re.sub(r'\s+', ' ', nome).strip()
    return nome

def mapear_tipo(codigo):
    if not codigo:
        return ""
    token = codigo.split()[0] if codigo else ""
    mapa = {
        'T': 'Tese',
        'D': 'Dissertação',
        'L': 'Livro',
        'P': 'Periódico / Parte de livro',
        'A': 'Artigo',
        'C': 'Capítulo de livro',
        'R': 'Relatório',
        'E': 'Evento',
        'M': 'Material didático',
        'S': 'Série',
        'N': 'Norma',
        'O': 'Outros',
    }
    return mapa.get(token, codigo)

def extrair_cidade(imprenta):
    if not imprenta:
        return ""
    imprenta = re.sub(r'\s+\d{4}$', '', imprenta).strip()
    partes = imprenta.split()
    if not partes:
        return ""
    cidade = []
    for token in partes:
        if re.match(r'^\d+$', token):
            break
        if len(token) >= 3 and token.isupper():
            break
        cidade.append(token)
        if len(cidade) >= 3:
            break
    return " ".join(cidade).strip()

# ------------------------------------------------------------
# Extração XML
# ------------------------------------------------------------
def extrair_xml(caminho_xml):
    try:
        with open(caminho_xml, 'r', encoding='utf-8', errors='ignore') as f:
            conteudo = f.read()
    except Exception:
        return {}

    conteudo = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', conteudo)
    padrao = r'(<record-list>.*?</record-list>)'
    match = re.search(padrao, conteudo, re.DOTALL)
    if not match:
        padrao = r'(<dc-record>.*?</dc-record>)'
        match = re.search(padrao, conteudo, re.DOTALL)
        if not match:
            padrao = r'(<[a-zA-Z_][^>]*>.*?</[a-zA-Z_][^>]*>)'
            match = re.search(padrao, conteudo, re.DOTALL)
            if not match:
                return {}
    xml_limpo = match.group(1)
    xml_limpo = re.sub(r'<!DOCTYPE[^>]*>', '', xml_limpo, flags=re.IGNORECASE)
    xml_limpo = re.sub(r'<\?xml[^?]*\?>', '', xml_limpo)
    xml_limpo = re.sub(r'<!--.*?-->', '', xml_limpo, flags=re.DOTALL)

    try:
        tree = ET.fromstring(xml_limpo)
    except Exception as e:
        print(f"Erro ao parsear XML {caminho_xml}: {e}")
        return {}

    if tree.tag == 'record-list':
        dc_record = tree.find('dc-record')
        if dc_record is None:
            return {}
    else:
        dc_record = tree

    def get_text(tag):
        elem = dc_record.find(tag)
        return elem.text.strip() if elem is not None and elem.text else ""

    titulo = get_text("title")
    contribuidores = []
    for elem in dc_record.findall("contributor"):
        if elem.text:
            contribuidores.append(elem.text.strip())

    autor = ""
    co_autor = ""
    orientador = ""
    if contribuidores:
        autor = limpar_autor(contribuidores[0])
        if len(contribuidores) > 1:
            orientador = limpar_autor(contribuidores[-1])
            if len(contribuidores) > 2:
                co_autor = "; ".join([limpar_autor(c) for c in contribuidores[1:-1]])

    data = get_text("date")
    paginas = get_text("format")
    local_publicacao = ""
    for elem in dc_record.findall("coverage"):
        if elem.text and elem.text.strip():
            local_publicacao = elem.text.strip()
            break

    subjects = []
    for elem in dc_record.findall("subject"):
        if elem.text:
            subjects.append(elem.text.strip())
    subjects_str = "|".join(subjects)

    descricao = get_text("description")

    # Aplica decodificação a todos os campos de texto
    titulo = decodificar_escapamentos(titulo)
    autor = decodificar_escapamentos(autor)
    co_autor = decodificar_escapamentos(co_autor)
    orientador = decodificar_escapamentos(orientador)
    local_publicacao = decodificar_escapamentos(local_publicacao)
    descricao = decodificar_escapamentos(descricao)

    # Normalização Unicode
    titulo = unicodedata.normalize('NFC', titulo)
    autor = unicodedata.normalize('NFC', autor)
    co_autor = unicodedata.normalize('NFC', co_autor)
    orientador = unicodedata.normalize('NFC', orientador)
    local_publicacao = unicodedata.normalize('NFC', local_publicacao)
    descricao = unicodedata.normalize('NFC', descricao)

    return {
        "titulo": titulo,
        "autor": autor,
        "co_autor": co_autor,
        "orientador": orientador,
        "data": data,
        "paginas": paginas,
        "local_publicacao": local_publicacao,
        "subjects": subjects_str,
        "descricao": descricao,
    }

# ------------------------------------------------------------
# Extração SUTRS
# ------------------------------------------------------------
def extrair_sutrs(caminho_sutrs):
    try:
        with open(caminho_sutrs, "r", encoding=ENCODING, errors="ignore") as f:
            conteudo = f.read()
    except Exception:
        return {"modelo": "", "local_defesa": "", "descricao": ""}

    # Primeiro, decodifica escapes em todo o conteúdo
    conteudo = decodificar_escapamentos(conteudo)

    modelo = ""
    padrao_modelo = r"Tipo\s+de\s+material:\s*(.*?)(?:\n|$)"
    match = re.search(padrao_modelo, conteudo, re.IGNORECASE)
    if match:
        codigo = match.group(1).strip()
        modelo = mapear_tipo(codigo)

    local_defesa = ""
    padrao_imprenta = r"Imprenta:\s*(.*?)(?:\n|$)"
    match = re.search(padrao_imprenta, conteudo, re.IGNORECASE)
    if match:
        imprenta = match.group(1).strip()
        imprenta = re.sub(r"\s+\d{4}$", "", imprenta).strip()
        local_defesa = extrair_cidade(imprenta)

    if not modelo:
        padrao_nota = r"Nota\s+de\s+tese:\s*(.*?)(?:\n|$)"
        match = re.search(padrao_nota, conteudo, re.IGNORECASE)
        if match:
            nota = match.group(1).strip()
            if "MESTRADO" in nota.upper():
                modelo = "Dissertação (Mestrado)"
            elif "DOUTORADO" in nota.upper():
                modelo = "Tese (Doutorado)"
            else:
                modelo = nota

    descricao = ""
    padrao_resumo = r"Nota\s+de\s+resumo:\s*(.*?)(?:\n|$)"
    match = re.search(padrao_resumo, conteudo, re.IGNORECASE)
    if match:
        descricao = match.group(1).strip()

    # Aplica decodificação e normalização nos campos extraídos (por segurança)
    modelo = decodificar_escapamentos(modelo)
    local_defesa = decodificar_escapamentos(local_defesa)
    descricao = decodificar_escapamentos(descricao)

    modelo = unicodedata.normalize('NFC', modelo)
    local_defesa = unicodedata.normalize('NFC', local_defesa)
    descricao = unicodedata.normalize('NFC', descricao)

    return {"modelo": modelo, "local_defesa": local_defesa, "descricao": descricao}

# ------------------------------------------------------------
# Processamento principal
# ------------------------------------------------------------
def processar_pastas(pastas, filtro_id=None):
    for pasta in pastas:
        print(f"Processando pasta: {pasta.name}")
        pasta_saida = pasta / "saídas"
        pasta_saida.mkdir(exist_ok=True)

        if filtro_id:
            nome_csv = f"saida_{filtro_id}.csv"
        else:
            nome_csv = f"resultados_{pasta.name}.csv"

        caminho_csv = pasta_saida / nome_csv

        total_linhas = 0
        with open(caminho_csv, "w", newline="", encoding="utf-8-sig") as csvfile:
            writer = csv.writer(csvfile, delimiter=";", quoting=csv.QUOTE_MINIMAL)
            writer.writerow([
                "identifier",
                "titulo",
                "autor",
                "co_autor",
                "orientador",
                "data",
                "paginas",
                "local_publicacao",
                "subjects",
                "modelo_trabalho",
                "descricao",
                "local_defesa"
            ])

            for xml_file in pasta.glob("xml/*.xml"):
                identifier = xml_file.stem
                if filtro_id and identifier != filtro_id:
                    continue

                sutrs_file = pasta / "sutrs" / f"{identifier}.sutrs"
                dados_xml = extrair_xml(xml_file)
                dados_sutrs = extrair_sutrs(sutrs_file) if sutrs_file.exists() else {"modelo": "", "local_defesa": "", "descricao": ""}

                descricao = dados_xml.get("descricao", "") or dados_sutrs.get("descricao", "")

                linha = [
                    identifier,
                    dados_xml.get("titulo", ""),
                    dados_xml.get("autor", ""),
                    dados_xml.get("co_autor", ""),
                    dados_xml.get("orientador", ""),
                    dados_xml.get("data", ""),
                    dados_xml.get("paginas", ""),
                    dados_xml.get("local_publicacao", ""),
                    dados_xml.get("subjects", ""),
                    dados_sutrs.get("modelo", ""),
                    descricao,
                    dados_sutrs.get("local_defesa", ""),
                ]

                writer.writerow(linha)
                total_linhas += 1

        print(f"CSV gerado: {caminho_csv} com {total_linhas} registros.")

# ------------------------------------------------------------
# Interface de linha de comando
# ------------------------------------------------------------
def main():
    import sys
    if len(sys.argv) < 2:
        print("Uso:")
        print("  1) Processar tudo em 'Registros/':")
        print("     python3 extract_to_csv.py Registros")
        print("  2) Processar uma pasta específica (ex: Preconceito_Racial_resultados):")
        print("     python3 extract_to_csv.py Registros/Preconceito_Racial_resultados")
        print("  3) Processar apenas um identificador (ex: 00294) em todas as pastas:")
        print("     python3 extract_to_csv.py Registros 00294")
        sys.exit(1)

    arg1 = sys.argv[1]
    arg2 = sys.argv[2] if len(sys.argv) > 2 else None

    if len(sys.argv) == 2:
        caminho_base = Path(arg1)
        if not caminho_base.exists():
            print(f"Erro: pasta '{caminho_base}' não encontrada.")
            sys.exit(1)
        pastas = list(caminho_base.glob("*_resultados"))
        if not pastas:
            print(f"Nenhuma pasta '*_resultados' encontrada em {caminho_base}.")
            sys.exit(1)
        processar_pastas(pastas, filtro_id=None)

    elif len(sys.argv) == 2 and Path(arg1).is_dir() and "_resultados" in arg1:
        pasta = Path(arg1)
        if not pasta.exists():
            print(f"Erro: pasta '{pasta}' não encontrada.")
            sys.exit(1)
        processar_pastas([pasta], filtro_id=None)

    elif len(sys.argv) == 3:
        caminho_base = Path(arg1)
        filtro_id = arg2
        if not caminho_base.exists():
            print(f"Erro: pasta '{caminho_base}' não encontrada.")
            sys.exit(1)
        pastas = list(caminho_base.glob("*_resultados"))
        if not pastas:
            print(f"Nenhuma pasta '*_resultados' encontrada em {caminho_base}.")
            sys.exit(1)
        processar_pastas(pastas, filtro_id=filtro_id)

    else:
        print("Argumentos não reconhecidos. Consulte o uso com: python3 extract_to_csv.py")

if __name__ == "__main__":
    main()