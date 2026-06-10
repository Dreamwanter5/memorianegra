#!/bin/bash

BUSCA="$*"

if [ -z "$BUSCA" ]; then
    echo "Uso:"
    echo "  $0 preconceito racial"
    exit 1
fi

#
#1 - salvar todos registros, não apenas os primeiros 10. A quantidade de registro é retornada como Number of hits: 330, nesse caso 330. 
# 2 - PRECONCEITO RACIAL deve ser uma variável, pois vou fazer a busca para vários termos, que pode ter um ou mais palavras, exemplo: arte negra, relações étnicos raciais, etc, que ficaria então: find @and @attr 1=21 relações @attr 1=21 étnicos @attr 1=21 raciais 
# 3 - salvar 4 tipos de arquivos marc, xml, SUTRS e opac para cada registro. 
# 4 - para nomear os arquivos, usar o campo identifider do xml: <identifier>8585775092</identifier>, então ficaria 8585775092.xml, 8585775092.opac etc

# Como testar na unha:
# sudo apt install yaz
# yaz-client dedalus.usp.br:9991
# base USP01
# find @and @attr 1=21 PRECONCEITO @attr 1=21 RACIAL

# Pedro: Montar essa lista dinamicamente
QUERY='find @and @attr 1=21 PRECONCEITO @attr 1=21 RACIAL'

TMP=$(mktemp)

cat > "$TMP" <<EOF
base USP01
format xml
$QUERY
EOF

HITS=$(
    echo -e "base USP01\n$QUERY\nquit" |
    yaz-client dedalus.usp.br:9991 2>/dev/null |
    grep "Number of hits" |
    sed 's/.*Number of hits: *//'
)

echo "Total: $HITS"

# Pedro: capturar o número acima
HITS=330
for ((i=1;i<=HITS;i++))
do
    echo "show $i"
    echo "show $i" >> "$TMP"
done

echo "quit" >> "$TMP"

mkdir -p xml

yaz-client dedalus.usp.br:9991 < "$TMP" > resultado.xml

rm "$TMP"

awk '
BEGIN{
    RS="</record>"
}
/<record>/{
    print $0 "</record>"
}
' resultado.xml > registros.tmp

csplit \
    --quiet \
    --prefix=registro_ \
    --suffix-format="%05d.xml" \
    registros.tmp \
    '/<record>/' '{*}'