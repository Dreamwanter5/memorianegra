#!/bin/bash

# Pasta base onde todos os resultados serão armazenados
PASTA_BASE="Registros"

if [ $# -eq 0 ]; then
    echo "Uso: $0 \"termo1\" \"termo2\" ..."
    echo "Exemplo: $0 \"preconceito racial\" \"arte negra\""
    exit 1
fi

# Cria a pasta base se não existir
mkdir -p "$PASTA_BASE"

executar_busca() {
    local termos="$1"
    local slug=$(echo "$termos" | tr ' ' '_' | sed 's/[^a-zA-Z0-9_]/_/g')
    local pasta_base="${PASTA_BASE}/${slug}_resultados"
    mkdir -p "$pasta_base"

    echo "=========================================="
    echo "Buscando: $termos"
    echo "Pasta: $pasta_base"
    echo "=========================================="

    # Busca no campo assunto (1=21) com palavras separadas
    if [[ "$termos" =~ [[:space:]] ]]; then
        # Termo composto: quebra em palavras e insere @and
        QUERY="find @and"
        for palavra in $termos; do
            QUERY="$QUERY @attr 1=21 $palavra"
        done
    else
        # Termo único
        QUERY="find @attr 1=21 $termos"
    fi
    echo "Query gerada: $QUERY"

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

    # XML
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

    # Outros formatos
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

# Executa para cada argumento
for arg in "$@"; do
    executar_busca "$arg"
done

echo "Todas as buscas foram concluídas. Resultados em '$PASTA_BASE/'"