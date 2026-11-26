# Trabalho Prático de Compiladores — Parte II

O compilador recebe um programa-fonte e gera dois arquivos ao lado dele. A extensão `.ir` contém as quádruplas e a extensão `.asm` contém o código-alvo. A tradução acontece inteiramente no executável do compilador.

## Compilação e execução

No Windows, com WinFlex, WinBison e GCC disponíveis no PATH, execute os comandos na raiz do projeto. O parâmetro `-CC` também aceita o nome ou caminho de outro compilador C, como Clang.

```powershell
.\compilar.ps1
.\build\compilador.exe .\exemplos\fatorial_recursivo.txt
python validar.py .\build\compilador.exe
```

Com Flex, Bison e um compilador C no Linux, os comandos equivalentes são os seguintes.

```bash
mkdir -p build
bison -Wall -d -o build/parser.tab.c parser.y
flex -o build/lex.yy.c lexer.l
cc -std=c11 -Wall -Wextra -I. build/parser.tab.c build/lex.yy.c codigo_alvo.c -o build/compilador
./build/compilador exemplos/fatorial_recursivo.txt
python3 validar.py build/compilador
```

A execução local foi feita no Windows com WinFlex, WinBison e Clang. A tabela de símbolos e as duas representações do intermediário são exibidas no terminal. Para fontes `.txt`, a extensão é substituída pelos sufixos de saída. Para outras extensões, os sufixos são acrescentados ao nome completo.

No simulador do Moodle, use **Abrir .asm** ou cole o conteúdo do arquivo no editor. Deixe **Memória inicial** em branco, pois o código gerado inicializa as células usadas. Clique em **Preparar código** e depois em **Executar**. Ao chegar a `HALT`, confira `RESULTADO` no painel **Memória**. Para alterar uma entrada, edite as atribuições do `.txt`, recompile e abra o novo `.asm`.

## Linguagem e análise léxica

| Elemento | Regra do Flex ou lexemas |
| --- | --- |
| Variável global | `[A-Z][A-Z0-9_]*`, por exemplo `RESULTADO` |
| Variável local e parâmetro | `[a-z][a-z0-9_]*`, por exemplo `total` |
| Função | `[a-z]+[A-Z][A-Za-z0-9]*`, por exemplo `calcularFatorial` |
| Inteiro | `[0-9]+` |
| Real | Com ponto decimal, expoente ou ambos, conforme a regra `REAL` de `lexer.l` |
| Palavras reservadas | `int`, `float`, `bool`, `void`, `if`, `else`, `while`, `return`, `principal`, `true`, `false` |
| Operadores | `+`, `-`, `*`, `/`, `%`, `=`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `!`, `&&`, `\|\|` |
| Separadores | Ponto e vírgula, vírgula, parênteses e chaves |
| Comentários | `//` até o fim da linha ou `/* ... */` |

O Flex aplica a regra do maior casamento e usa a ordem das regras para desempatar. Palavras reservadas aparecem antes dos identificadores. As regras de erro detectam caracteres desconhecidos, identificadores fora do padrão, números colados a identificadores e comentários de bloco abertos. Cada token inclui linha e coluna.

## Gramática e análise sintática

O símbolo inicial é `programa`. A gramática completa está em `parser.y`. A tabela resume as produções que comandam a tradução. As alternativas abaixo estão separadas por ponto e vírgula.

| Produção | Alternativas e componentes |
| --- | --- |
| `programa` | Declaração global seguida de `programa`; lista de funções |
| `declaracao_global` | Tipo, identificador global e ponto e vírgula |
| `funcao` | Cabeçalho, chaves e sequência opcional de itens |
| `cabecalho` | Tipo de retorno, nome de função e lista opcional de parâmetros; tipo de retorno e `principal()` |
| `item_bloco` | Declaração local; comando |
| `comando` | Atribuição; chamada; retorno; `if`; `if-else`; `while`; bloco; comando vazio |
| `expressao` | Literal; variável; chamada; expressão entre parênteses; operador unário; operador binário |

O Bison usa tabelas **LALR(1)**, seu padrão nesta configuração. A gramática declara precedência e associatividade para resolver ambiguidades das expressões. Por exemplo, a multiplicação tem precedência sobre a soma, e os operadores binários de mesma precedência associam à esquerda. A produção do `if` sem `else` recebe precedência menor que o token `else`, que é deslocado e se associa ao `if` mais próximo. A geração com `-Werror=conflicts-sr -Werror=conflicts-rr` confirmou a ausência de conflitos sem resolução. A opção `--report=state,solved` mostra as decisões de precedência nas tabelas.

## Ações semânticas e geração de quádruplas

O compilador faz duas passagens. Na primeira, coleta as globais e as assinaturas das funções, o que permite chamadas para funções definidas mais abaixo no fonte. Na segunda, abre os escopos, associa cada declaração ao identificador interno e traduz os corpos. A busca de variáveis começa no escopo atual e percorre os escopos externos. A tabela registra nome, categoria, tipo e escopo.

| Construção | Verificação e quádruplas |
| --- | --- |
| Declaração | Detecta redeclaração no mesmo escopo. Emite `global`, `local` ou `recv`. |
| Atribuição e expressão | Resolve o identificador, valida tipos e emite `=`, a operação em si ou `i2f` para promoção de inteiro a real. |
| `if` e `while` | Exige condição `bool`. Usa `ifFalse`, `goto` e `label` para montar os desvios e laços. |
| `&&` e `\|\|` | Usa `ifFalse` ou `ifTrue` para pular a expressão direita quando o valor da esquerda é suficiente. |
| Chamada | Confere assinatura, aridade e tipos. Emite `param` para cada argumento e `call` com destino temporário quando há retorno. |
| Retorno | Verifica o valor em relação ao tipo declarado e emite `return`. Exige retorno em todos os caminhos de funções com valor, com retorno implícito 0 em `int principal()`. |

Um temporário `$tN` representa um resultado intermediário ou uma leitura de variável. Essa cópia preserva o valor da leitura caso uma função chamada depois modifique a variável. Os rótulos `LN` recebem números consecutivos. A emissão de quádruplas é feita durante as ações semânticas e a tradução para Assembly só começa após a aceitação do programa.

## Tradução para Assembly

O módulo `codigo_alvo.c` percorre as quádruplas e emite instruções. Globais como `RESULTADO` ficam acessíveis pelo nome. As células internas têm nomes distintos para temporários (`ZT`), locais e parâmetros (`ZV`) e posições de passagem de argumentos (`ZA`). Funções e desvios também recebem rótulos distintos. A inicialização escreve zero nas células globais, locais e temporárias antes de entrar em `principal`. O retorno de `principal` emite `HALT`.

| Quádrupla | Tradução |
| --- | --- |
| `=` | `LD` da origem e `ST` no destino. |
| `+`, `-`, `*`, `/`, `%` | Carrega os operandos, emite `ADD`, `SUB`, `MUL`, `DIV` ou `MOD` e armazena o resultado. A instrução `DIV` trunca em direção a zero. |
| Comparações e `!` | Usa `SLT` e `SEQ` para produzir 0 ou 1. Para `>` ou `<=`, troca a ordem dos operandos de `SLT`. Para inverter um resultado booleano, compara-o a zero com `SEQ`. |
| `ifFalse`, `ifTrue`, `goto` | Emite `BEQZ`, `BNEZ` ou `BR`, respectivamente. |
| `param`, `recv` | O chamador grava cada argumento em `ZA1`, `ZA2` etc. A função copia cada valor para sua célula de parâmetro. |
| `call`, `return` | `PUSH` salva as células da ativação do chamador, `CALL` desvia, `RET` retorna e `POP` restaura os valores em ordem inversa. |

| Registrador | Uso |
| --- | --- |
| R0 | Valor de retorno |
| R1 e R2 | Carga dos operandos e comparação |
| R3 | Resultado de operações aritméticas e booleanas |
| R4 | Inicialização das células e movimentação de valores entre a memória e a pilha |
| R5 a R7 | Reservados |

Os resultados intermediários são gravados na memória imediatamente. R1 a R4 podem ser reutilizados na instrução seguinte. Antes de `CALL`, o chamador empilha seus parâmetros, locais e temporários. O chamado copia os argumentos e executa com suas próprias células. Se houver reentrada por recursão, as células podem ser sobrescritas porque seus valores anteriores já estão na pilha. Após `RET`, o chamador restaura suas células e só então grava R0 no temporário da chamada. No fatorial, esse mecanismo preserva o `n` de cada ativação para a multiplicação após a volta.

## Programas e resultados

Cada linha aponta para o fonte entregue e para as saídas geradas pelo compilador. O verificador local `validar.py` executa o Assembly em um modelo do conjunto de instruções documentado pelo simulador. A execução dos arquivos no Moodle está pendente.

| Problema | Fonte | Quádruplas | Assembly |
| --- | --- | --- | --- |
| Expressão aritmética | [fonte](exemplos/expressao_aritmetica.txt) | [IR](exemplos/expressao_aritmetica.ir) | [Assembly](exemplos/expressao_aritmetica.asm) |
| Maior de três | [fonte](exemplos/maior_de_tres.txt) | [IR](exemplos/maior_de_tres.ir) | [Assembly](exemplos/maior_de_tres.asm) |
| Fatorial iterativo | [fonte](exemplos/fatorial_iterativo.txt) | [IR](exemplos/fatorial_iterativo.ir) | [Assembly](exemplos/fatorial_iterativo.asm) |
| Fatorial recursivo | [fonte](exemplos/fatorial_recursivo.txt) | [IR](exemplos/fatorial_recursivo.ir) | [Assembly](exemplos/fatorial_recursivo.asm) |

| Problema | Entradas | Esperado | Obtido localmente |
| --- | --- | ---: | ---: |
| Expressão aritmética | 2, 3, 4, 5 | 15 | 15 |
| Expressão aritmética | −2, 5, 3, 4 | 5 | 5 |
| Expressão aritmética | 2, 3, 0, 7 | −7 | −7 |
| Maior de três | 7, 12, 5 | 12 | 12 |
| Maior de três | 9, 9, 3 | 9 | 9 |
| Maior de três | −4, −4, −4 | −4 | −4 |
| Fatorial iterativo | 0 | 1 | 1 |
| Fatorial iterativo | 1 | 1 | 1 |
| Fatorial iterativo | 2 | 2 | 2 |
| Fatorial iterativo | 3 | 6 | 6 |
| Fatorial iterativo | 4 | 24 | 24 |
| Fatorial iterativo | 5 | 120 | 120 |
| Fatorial recursivo | 0 | 1 | 1 |
| Fatorial recursivo | 1 | 1 | 1 |
| Fatorial recursivo | 2 | 2 | 2 |
| Fatorial recursivo | 3 | 6 | 6 |
| Fatorial recursivo | 4 | 24 | 24 |
| Fatorial recursivo | 5 | 120 | 120 |

Os resultados são conferidos em `RESULTADO`. O verificador usa os fontes entregues para cada fatorial e adapta as atribuições iniciais dos outros dois programas. Ele compila cada caso em uma pasta temporária e confere se a pilha está vazia no fim da execução. Também cobre curto-circuito, chamadas aninhadas, divisão inteira, comparações nos extremos de 32 bits e os diagnósticos de erro. Os arquivos de cada fatorial estão na [tabela de exemplos](README.md#fatoriais-de-0-a-5).

## Diagnósticos

| Classe | Entrada ou erro | Mensagem emitida |
| --- | --- | --- |
| Léxico | `int principal() { @ }` | `Erro lexico na linha 1, coluna 19: caractere nao reconhecido: '@'.` |
| Sintático | `int principal() { return 0 }` | `Erro sintatico na linha 1, coluna 28, proximo de '}': syntax error, unexpected '}'.` |
| Semântico | `return 1;` em `registrarFim` do arquivo `teste_erros.txt` | `Erro semantico na linha 6, coluna 5: funcao void deve usar return sem valor.` |
| Semântico | Apenas `void outraFuncao() {}` | `Erro semantico na linha 1, coluna 22: funcao principal ausente.` |

A rejeição resulta em código de saída diferente de zero e interrompe a geração de novos arquivos. O analisador encerra no primeiro erro léxico ou sintático e pode emitir vários diagnósticos semânticos para um fonte sintaticamente válido.

## Limitações

- O alvo trabalha com inteiros de 32 bits com sinal. Os imediatos inteiros são representados nos 32 bits da máquina e os booleanos usam 0 e 1. Programas com `float` podem gerar `.ir`. Nesses casos, o compilador informa a limitação do alvo e interrompe a geração de Assembly.
- O simulador limita a execução a 50.000 instruções e a pilha a 4.096 posições. O gerador salva todos os valores da ativação atual a cada chamada, inclusive temporários que podem já ter deixado de ser usados.
- A verificação de retorno trata laços de forma conservadora. Mesmo com condição constante, a função precisa de um caminho de retorno demonstrável pela estrutura dos comandos.
- Os programas do TP recebem entradas por atribuições. Fatoriais pressupõem entradas inteiras não negativas e valores que caibam no formato numérico da máquina. O compilador não inclui tratamento em tempo de execução para divisão por zero ou estouro.
