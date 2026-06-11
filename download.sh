#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Uso: $0 \"termo1 termo2\" \"termo3 termo4\" ..."
    echo "Exemplo: $0 \"preconceito racial\" \"arte negra\""
    exit 1
fi

# Função que executa uma busca para um conjunto de termos
executar_busca() {
    local termos="$1"
    # Cria uma slug a partir dos termos (ex: "preconceito_racial")
    local slug=$(echo "$termos" | tr ' ' '_' | sed 's/[^a-zA-Z0-9_]/_/g')
    local pasta_base="${slug}_resultados"
    mkdir -p "$pasta_base"

    echo "=========================================="
    echo "Buscando: $termos"
    echo "Pasta: $pasta_base"
    echo "=========================================="

    # Monta query
    QUERY="find @and"
    for term in $termos; do
        term_upper=$(echo "$term" | tr '[:lower:]' '[:upper:]')
        QUERY="$QUERY @attr 1=21 $term_upper"
    done
    echo "Query gerada: $QUERY"

    # Obtém total de hits
    HITS=$(
        (
            echo "base USP01"
            echo "$QUERY"
            echo "quit"
        ) | yaz-client dedalus.usp.br:9991 2>&1 | grep -i "Number of hits" | sed -E 's/.*Number of hits: ([0-9]+).*/\1/'
    )

    if ! [[ "$HITS" =~ ^[0-9]+$ ]]; then
        echo "Erro: não foi possível obter o número de hits para $termos."
        return 1
    fi
    echo "Total de registros encontrados: $HITS"

    # Função que baixa todos os registros de uma vez (para XML)
    busca_tudo() {
        local FORMATO="$1"
        local OUT_RAW="$2"
        local CMDS
        CMDS=$(mktemp)
        {
            echo "base USP01"
            echo "format $FORMATO"
            echo "$QUERY"
            echo "show 1+$HITS"
            echo "quit"
        } > "$CMDS"
        yaz-client dedalus.usp.br:9991 < "$CMDS" > "$OUT_RAW" 2>&1
        rm "$CMDS"
    }

    # 1. XML
    RAW_XML=$(mktemp)
    busca_tudo "xml" "$RAW_XML"
    TEMP_XML_DIR=$(mktemp -d)
    awk 'BEGIN {RS="</dc-record>"; ORS=""} /<dc-record>/ {print $0 "</dc-record>"}' "$RAW_XML" > "$TEMP_XML_DIR/todos.xml"
    csplit --quiet --prefix="$TEMP_XML_DIR/temp_" --suffix-format="%05d.xml" "$TEMP_XML_DIR/todos.xml" '/<dc-record>/' '{*}'

    mkdir -p "$pasta_base/xml"
    declare -a IDS
    index=0
    for xmlfile in "$TEMP_XML_DIR"/temp_*.xml; do
        [ -f "$xmlfile" ] || continue
        if grep -q "Connecting" "$xmlfile"; then
            rm "$xmlfile"
            continue
        fi
        id=$(sed -n 's/.*<identifier>\([^<]*\)<\/identifier>.*/\1/p' "$xmlfile" | head -1)
        if [ -z "$id" ]; then
            id=$(printf "%05d" $index)
        else
            id=$(echo "$id" | sed 's/[\/:*?"<>| ]/_/g' | sed 's/__*/_/g')
        fi
        IDS+=("$id")
        cp "$xmlfile" "$pasta_base/xml/${id}.xml"
        ((index++))
    done
    rm -rf "$TEMP_XML_DIR" "$RAW_XML"

    # 2. Baixar outros formatos (um por vez)
    baixa_registro() {
        local FORMATO="$1"
        local NUMERO="$2"
        local OUT_FILE="$3"
        local CMDS
        CMDS=$(mktemp)
        {
            echo "base USP01"
            echo "format $FORMATO"
            echo "$QUERY"
            echo "show $NUMERO"
            echo "quit"
        } > "$CMDS"
        yaz-client dedalus.usp.br:9991 < "$CMDS" > "$OUT_FILE" 2>&1
        rm "$CMDS"
    }

    for formato in USmarc SUTRS OPAC; do
        case "$formato" in
            (USmarc) pasta_fmt="marc" ;;
            (SUTRS)  pasta_fmt="sutrs" ;;
            (OPAC)   pasta_fmt="opac" ;;
        esac
        mkdir -p "$pasta_base/$pasta_fmt"
        echo "Processando formato: $formato"

        for ((i=0; i<HITS; i++)); do
            numero=$((i+1))
            id="${IDS[$i]}"
            temp_file=$(mktemp)
            baixa_registro "$formato" "$numero" "$temp_file"
            cleaned_file=$(mktemp)
            sed -n '/\[USP01\]Record type:/,/nextResultSetPosition/ {
                /nextResultSetPosition/d
                p
            }' "$temp_file" > "$cleaned_file"
            if [ -s "$cleaned_file" ]; then
                cp "$cleaned_file" "$pasta_base/$pasta_fmt/${id}.${pasta_fmt}"
            fi
            rm -f "$temp_file" "$cleaned_file"
            if (( (numero % 20) == 0 )); then
                echo "  $numero de $HITS concluídos para $formato"
            fi
        done
    done

    echo "Concluído para '$termos'. Resultados em $pasta_base/"
    echo "=========================================="
}

# Executa para cada argumento (que pode conter múltiplas palavras entre aspas)
for arg in "$@"; do
    executar_busca "$arg"
done

echo "Todas as buscas foram concluídas!"