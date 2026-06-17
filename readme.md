# Geração de arquivos de registro da Base USP

O código ainda está numa versão inicial e está sujeito a alterações, mas ele já é capaz de fazer buscas na base da USP e extrair as informações dos arquivos em `marc`, `xml`, `sutrs` e `opac` .

## Nomeação dos arquivos

Por padrão, o script tenta usar o conteúdo da tag <identifier> do XML como nome do arquivo (ex: 8585775092.xml). Quando esse campo não está presente, o arquivo recebe um nome sequencial de 5 dígitos (00000.xml, 00001.xml etc.), baseado na posição do registro.

Importante: independentemente do formato (marc, sutrs, opac), todos os arquivos referentes ao mesmo registro recebem o mesmo nome, alterando apenas a extensão.

> Note que todo o resultado passa por um pequeno processo de sanitização (espaços, dois-pontos, barras, etc.) e os substituindo por `_`.  

---

# Funcionamento

O script se resume a uma função principal (executar_busca). Para cada termo de busca fornecido, ele:

1. Monta a query adequada (explicada abaixo).
2. Envia a busca ao servidor e obtém o número total de hits ($HITS).
3. Baixa todos os registros em XML de uma só vez (uso de show 1+$HITS).
4. Extrai os identifiers e salva cada XML individualmente.
5. Para os formatos USmarc, SUTRS e OPAC, baixa cada registro separadamente (loop de 1 a $HITS), limpando os cabeçalhos e salvando com o mesmo nome base.

## *IMPORTANTE*
- O script funciona de uma forma pontual no que diz respeito ao seu mecanismo de busca. Pegando um exemplo prático, pode ser que ao utilizar o comando: `find CANDOMBLÉ` dentro do _cliente yaz_ ele retorne 594 resultados. Porém no `.sh`, ao executar o comando `./download.sh CANDOMBLÉ` o resultado que será obtido seria de apenas 460. Isso porque o script faz uma filtragem baseando-se *apenas* se as palavras buscadas estão no campo *assunto*. Esse é o efeito de utilizar `@attr 1=21` na montagem da `query` (iniciada na linha 55).
Caso seja mais conveniente capturar mais resultados, a alteração a ser feita é fazer uma substituição de `@attr 1=21` para `@attr 1=7`, que busca em todos os campos. 

---

# Utilização com uma lista de termos

- O código vem com um arquivo chamado `termos.txt` em sua pasta contendo palavras que compõem um arquivo de biblioteca temática da USP. 

```
while read -r termo; do
    ./download.sh "$termo"
done < termos.txt
```

## Nuances de execução

Termos que contêm espaços (ex: "JOGO DE BÚZIOS") devem ser escritos entre aspas no arquivo termos.txt. O script quebra a frase em palavras e monta uma query com @and entre cada palavra. Isso funciona bem para a maioria dos casos, mas pode encontrar problemas com stop words (palavras muito comuns como da, de, do, e, etc.). Por exemplo, buscando "Extinção da África", a palavra _da_ pode ser ignorada pelo servidor, reduzindo a precisão.

## Critérios de personalização

Na criação do código a variável `QUERY` é montada de duas formas:
    - Termo simples (sem espaços): `find @attr 1=21 termo`
    - Termo composto (com espaços): `find @and @attr 1=21 palavra1 @attr 1=21 palavra2 ...`

Mas ela é passível de ser alterada para outros critérios com:

- `@attr 4=1` busca uma adjacência EXATA.
- `@attr 1=7` busca palavras chave sem necessidade de uma adjacência.
- `@attr 1=21` se refere ao atributo de "Assunto" em buscas mais elaboradas.
- Nenhum atributo	Busca geral no servidor (comportamento padrão do find)

# Estrutura de diretórios

Todos os resultados são salvos dentro da pasta `Registros/` (criada automaticamente). Dentro dela, cada termo de busca gera uma subpasta com o formato `{termo_sanitizado}_resultados/`, contendo subpastas `xml/`, `marc/`, `sutrs/`, `opac/`. Exemplo:

---

# Obs:

- O script foi feito e testado em um ambiente Linux com o `yaz-client`;
- Fazer buscas maiores pode acabar exigindo um pouco de seu computador, por isso, pode ser conveniente adicionar pausas na execução do código. Ex:
    ```
    while IFS= read -r termo; do
        ./download.sh "$termo"
        sleep 2   # pausa opcional para não sobrecarregar o servidor
    done < termos.tx
    ```
- Para depurar erros de busca, é muito útil fazer testes manuais dentro do `yaz-client` 
- O código transforma frases como "Extinção da África" para "Extinção África" por conta de uma limitação do sistema de _stopwords_ do servidor original.