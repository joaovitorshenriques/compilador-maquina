# Compilador para a máquina hipotética do Aho

Trabalho Prático de **Compiladores I (CSI506)**, desenvolvido para a Universidade Federal de Ouro Preto (UFOP), no campus ICEA. O projeto implementa uma linguagem didática inspirada em C e gera Assembly para o simulador da disciplina.

O Flex reconhece os tokens. O Bison analisa a gramática e aciona a análise semântica, a tabela de símbolos e a geração de quádruplas. O gerador traduz essas quádruplas para Assembly, incluindo desvios, laços e funções recursivas. O compilador executa todas essas etapas localmente. O simulador do Moodle executa o código-alvo gerado.

## Como compilar e executar

### Windows

Com WinFlex, WinBison e GCC no `PATH`, execute no PowerShell a partir da raiz do projeto:

```powershell
.\compilar.ps1
.\build\compilador.exe .\exemplos\fatorial_recursivo.txt
```

Se estiver usando Clang, rode `.\compilar.ps1 -CC clang` ou passe o caminho do executável em `-CC`.

### Linux

Instale Flex, Bison e um compilador C como GCC. No Debian e no Ubuntu, os pacotes são `flex`, `bison` e `build-essential`. Na raiz do projeto, execute:

```bash
mkdir -p build
bison -Wall -d -o build/parser.tab.c parser.y
flex -o build/lex.yy.c lexer.l
cc -std=c11 -Wall -Wextra -I. build/parser.tab.c build/lex.yy.c codigo_alvo.c -o build/compilador
./build/compilador exemplos/fatorial_recursivo.txt
```

### Simulador do Moodle

O compilador grava os arquivos `.ir` e `.asm` ao lado do código-fonte. Abra `exemplos/fatorial_recursivo.asm` no [simulador do Moodle](https://moodlepresencial.ufop.br/mod/scorm/view.php?id=1307685), deixe **Memória inicial** em branco e clique em **Preparar código** e **Executar**. Confira `RESULTADO = 120` no painel **Memória** depois de `HALT`.

## Exemplos do trabalho

| Programa | Resultado esperado |
| --- | ---: |
| [Expressão aritmética](exemplos/expressao_aritmetica.txt) | 15 |
| [Maior de três números](exemplos/maior_de_tres.txt) | 12 |


### Fatoriais de 0 a 5

Abra o Assembly correspondente no Moodle e confira `RESULTADO`. Cada caso tem o fonte `.txt` e as quádruplas `.ir` ao lado do `.asm`.

| Entrada `n` | `RESULTADO` | Assembly iterativo | Assembly recursivo |
| ---: | ---: | --- | --- |
| 0 | 1 | [Iterativo](exemplos/fatoriais/iterativo_n0.asm) | [Recursivo](exemplos/fatoriais/recursivo_n0.asm) |
| 1 | 1 | [Iterativo](exemplos/fatoriais/iterativo_n1.asm) | [Recursivo](exemplos/fatoriais/recursivo_n1.asm) |
| 2 | 2 | [Iterativo](exemplos/fatoriais/iterativo_n2.asm) | [Recursivo](exemplos/fatoriais/recursivo_n2.asm) |
| 3 | 6 | [Iterativo](exemplos/fatoriais/iterativo_n3.asm) | [Recursivo](exemplos/fatoriais/recursivo_n3.asm) |
| 4 | 24 | [Iterativo](exemplos/fatoriais/iterativo_n4.asm) | [Recursivo](exemplos/fatoriais/recursivo_n4.asm) |
| 5 | 120 | [Iterativo](exemplos/fatorial_iterativo.asm) | [Recursivo](exemplos/fatorial_recursivo.asm) |

A linguagem reconhece `int`, `bool`, `float` e o retorno `void`. O Assembly usa inteiros de 32 bits com sinal e representa booleanos como 0 ou 1. Programas com `float` geram quádruplas e recebem um diagnóstico na geração de código-alvo.

## Validação

Use os arquivos `.asm` dos exemplos para conferir `RESULTADO` no simulador. Para observar diagnósticos do compilador, passe `teste_erros.txt` como entrada no lugar do exemplo. O [relatório técnico](RELATORIO.md) detalha a linguagem, a estratégia de uso dos registradores, a convenção de chamada e os casos de teste.
