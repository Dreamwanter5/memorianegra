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

---

# Transformando os registros em `.CSV`

Além do download dos registros, disponibilizamos um script Python (extract_to_csv.py) que extrai informações estruturadas dos arquivos baixados e as organiza em uma planilha CSV. Esse script percorre as pastas de resultados, lê os arquivos .xml, .opac e .sutrs de cada registro, e gera um arquivo .csv com os campos mais relevantes para sua biblioteca temática.

## Como usar

O script pode ser executado de três formas principais:
```
# 1. Processar todas as pastas dentro de 'Registros/'
python3 extract_to_csv.py Registros

# 2. Processar apenas uma pasta específica (ex: Preconceito_Racial_resultados)
python3 extract_to_csv.py Registros/Preconceito_Racial_resultados

# 3. Filtrar por um identificador (ex: 00294) em todas as pastas
python3 extract_to_csv.py Registros 00294
```

*Saída*
Para cada pasta processada, o script cria uma subpasta chamada `saídas/` (dentro da própria pasta de resultados) e salva um arquivo CSV com o nome:

- `resultados_<nome_da_pasta>.csv` (quando processa uma pasta inteira)
- `saida_<identifier>.csv` (quando filtra por identificador)

*Exemplo de estrutura:*
```text
Registros/
├── Preconceito_Racial_resultados/
│   ├── xml/
│   ├── marc/
│   ├── sutrs/
│   ├── opac/
│   └── saídas/
│       └── saida_00294.csv
├── outro_termo_resultados/
│   └── saídas/
│       └── resultados_outro_termo_resultados.csv
└── ...
```

## Campos extraídos para o CSV

Dentre os diferentes tipos de arquivo, era notável que cada um possuia alguns identificadores que eram únicos de seu formato, pensando nessa variedade de informações, o código escaneia os diferentes tipos de registros e coleta dados importantes para o registro:

| Coluna | Fonte | Descrição |
| :--- | :--- | :--- |
| **identifier** | Nome do arquivo | Identificador único do registro (extraído do XML ou sequencial) |
| **titulo** | XML (`<title>`) | Título completo do trabalho |
| **autor** | XML (`<contributor>`) | Autor principal (com data e ORCID removidos) |
| **co_autor** | XML (`<contributor>`) | Coautores (se houver mais de um contribuidor) |
| **orientador** | XML (`<contributor>`) | Orientador (último contribuidor, quando há mais de um) |
| **data** | XML (`<date>`) | Ano de publicação |
| **paginas** | XML (`<format>`) | Extensão ou número de páginas |
| **local_publicacao** | XML (`<coverage>`) | Local de publicação (ex: BRASIL) – extraído do XML |
| **subjects** | XML (`<subject>`) | Assuntos/descritores, separados por `|` (pipe) |
| **modelo_trabalho** | SUTRS (Tipo de material:) | Tipo de material traduzido (ex: "Tese", "Periódico / Parte de livro") |
| **descricao** | XML (`<description>`) | Resumo/descrição do trabalho (fallback para SUTRS se ausente) |
| **local_defesa** | SUTRS (Imprenta:) | Cidade de defesa/publicação (extraída do campo "Imprenta") |

## Tratamento de informações

- *Limpeza do autor:* Se houver elementos tipo datas ou outros sufixos desnescessários, o código faz a limpeza, deixando apenas o nome.

- *Mapeamento de tipo:* códigos como T, D, P são convertidos para descrições legíveis (ex: T → Tese, P → Periódico / Parte de livro).

- *Decodificação de caracteres:* sequências como S\XC3\XA3o Paulo são automaticamente convertidas para São Paulo durante a extração.

- *Normalização Unicode:* todos os textos são normalizados para a forma NFC, garantindo consistência nos acentos.

- *Fallback de descrição:* se o XML não tiver <description>, o script busca Nota de resumo: no arquivo SUTRS.

## Exemplo de saída

| identifier | titulo | autor | co_autor | orientador | data | paginas | local_publicacao | subjects | modelo_trabalho | descricao | local_defesa |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 00294 | Oriente-se marcas da assimilação asiática no Brasil... | Nakamura, Aline Watanabe |  | Ambra, Pedro | 2023 | 142 p | BRASIL | PRECONCEITO RACIAL\|ORIENTALISMO\|... | Tese | A presente pesquisa... | São Paulo |