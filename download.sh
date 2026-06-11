#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Uso: $0 termo1 [termo2 ...]"
    echo "Exemplo: $0 preconceito racial"
    exit 1
fi

# Monta query: find @and termo1 termo2 ...
QUERY="find @and"
for term in "$@"; do
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
    echo "Erro: não foi possível obter o número de hits."
    exit 1
fi
echo "Total de registros encontrados: $HITS"

# -------------------------------------------------------------------
# 1. Baixar XML (todos de uma vez) e extrair identifiers
# -------------------------------------------------------------------
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

RAW_XML=$(mktemp)
busca_tudo "xml" "$RAW_XML"

# Divide a saída XML em registros individuais (usando </dc-record>)
TEMP_XML_DIR=$(mktemp -d)
awk 'BEGIN {RS="</dc-record>"; ORS=""} /<dc-record>/ {print $0 "</dc-record>"}' "$RAW_XML" > "$TEMP_XML_DIR/todos.xml"
csplit --quiet --prefix="$TEMP_XML_DIR/temp_" --suffix-format="%05d.xml" "$TEMP_XML_DIR/todos.xml" '/<dc-record>/' '{*}'

# Array para armazenar os identificadores (ou fallback numérico)
# Garante que a pasta xml existe
mkdir -p xml

declare -a IDS
index=0
for xmlfile in "$TEMP_XML_DIR"/temp_*.xml; do
    [ -f "$xmlfile" ] || continue
    # Pula o primeiro arquivo se ele contiver cabeçalho de conexão
    if grep -q "Connecting" "$xmlfile"; then
        echo "Ignorando arquivo de cabeçalho: $(basename "$xmlfile")"
        rm "$xmlfile"
        continue
    fi
    id=$(sed -n 's/.*<identifier>\([^<]*\)<\/identifier>.*/\1/p' "$xmlfile" | head -1)
    if [ -z "$id" ]; then
        id=$(printf "%05d" $index)
        echo "Aviso: identifier não encontrado, usando seq $id"
    else
        # Sanitiza o identifier: remove caracteres problemáticos para nome de arquivo
        id=$(echo "$id" | sed 's/[\/:*?"<>| ]/_/g' | sed 's/__*/_/g')
    fi
    IDS+=("$id")
    cp "$xmlfile" "xml/${id}.xml"
    ((index++))
done

# -------------------------------------------------------------------
# 2. Baixar outros formatos (um registro por vez)
# -------------------------------------------------------------------
# Função para baixar um único registro em um formato específico
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

# Processa cada formato
for formato in USmarc SUTRS OPAC; do
    # Define a pasta de destino (minúsculo)
    case "$formato" in
        (USmarc) pasta="marc" ;;
        (SUTRS)  pasta="sutrs" ;;
        (OPAC)   pasta="opac" ;;
    esac
    mkdir -p "$pasta"
    echo "Processando formato: $formato -> pasta $pasta"

    for ((i=0; i<HITS; i++)); do
        numero=$((i+1))
        id="${IDS[$i]}"
        temp_file=$(mktemp)
        baixa_registro "$formato" "$numero" "$temp_file"

        # Extrai apenas o conteúdo do registro (remove cabeçalhos e rodapés)
        # O registro começa com "[USP01]Record type: $formato" e vai até "nextResultSetPosition"
        cleaned_file=$(mktemp)
        sed -n '/\[USP01\]Record type:/,/nextResultSetPosition/ {
            /nextResultSetPosition/d
            p
        }' "$temp_file" > "$cleaned_file"

        if [ -s "$cleaned_file" ]; then
            cp "$cleaned_file" "$pasta/${id}.${pasta}"
        else
            echo "Aviso: registro $numero vazio para formato $formato"
        fi

        rm -f "$temp_file" "$cleaned_file"
        # Feedback a cada 10 registros
        if (( (numero % 10) == 0 )); then
            echo "  $numero de $HITS concluídos para $formato"
        fi
    done
    echo "Formato $formato concluído."
done

echo "Concluído. Arquivos salvos em: xml/, marc/, sutrs/, opac/"