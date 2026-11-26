%code requires {
typedef enum {
    T_INVALIDO, T_INT, T_FLOAT, T_BOOL, T_VOID
} Tipo;

typedef struct {
    Tipo tipo;
    const char *lugar;
} Valor;

typedef struct Lista Lista;

typedef struct {
    const char *inicio;
    const char *fim;
} Laco;

typedef struct {
    const char *fim;
    int ramo_anterior_retorna;
} Condicional;

const char *copiar_lexema(const char *texto);
}

%code {
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "codigo_alvo.h"

int yylex(void);
void yyerror(const char *mensagem);
void yyrestart(FILE *arquivo);
void reiniciar_posicao_lexer(void);

extern FILE *yyin;
extern char *yytext;
extern int erros_lexicos;

struct Lista {
    Valor valor;
    YYLTYPE local;
    Lista *prox;
    Lista *ultimo;
};

typedef struct Simbolo {
    const char *nome;
    Valor valor;
    const char *categoria;
    const char *funcao;
    unsigned bloco;
    struct Simbolo *prox;
    struct Simbolo *prox_declarado;
} Simbolo;

typedef struct Escopo {
    Simbolo *variaveis;
    struct Escopo *pai;
    unsigned numero;
} Escopo;

typedef struct Funcao {
    const char *nome;
    Tipo retorno;
    Lista *parametros;
    struct Funcao *prox;
} Funcao;

typedef union Memoria Memoria;
union Memoria {
    Memoria *prox;
    long double alinhamento;
    void *ponteiro;
};

static Memoria *memoria;
static Escopo global;
static Escopo *escopo = &global;
static Simbolo *declarados;
static Simbolo *ultimo_declarado;
static Funcao *funcoes;
static Funcao *funcao_atual;
static Quadrupla *codigo;
static Quadrupla *ultima;
static unsigned temporarios, rotulos, locais, blocos;
static int coletando = 1;
static int erros_sintaticos, erros_semanticos;

static void *alocar(size_t tamanho)
{
    Memoria *bloco = calloc(1, sizeof *bloco + tamanho);
    if (bloco == NULL) {
        fputs("Memoria insuficiente.\n", stderr);
        exit(EXIT_FAILURE);
    }
    bloco->prox = memoria;
    memoria = bloco;
    return bloco + 1;
}

const char *copiar_lexema(const char *texto)
{
    size_t tamanho = strlen(texto) + 1;
    return memcpy(alocar(tamanho), texto, tamanho);
}

static const char *numerar(const char *prefixo, unsigned numero)
{
    char texto[64];
    snprintf(texto, sizeof texto, "%s%u", prefixo, numero);
    return copiar_lexema(texto);
}

static void erro_semantico(YYLTYPE local, const char *formato, ...)
{
    va_list argumentos;
    fprintf(stderr, "Erro semantico na linha %d, coluna %d: ",
            local.first_line, local.first_column);
    va_start(argumentos, formato);
    vfprintf(stderr, formato, argumentos);
    va_end(argumentos);
    fputs(".\n", stderr);
    erros_semanticos++;
}

static const char *nome_tipo(Tipo tipo)
{
    static const char *nomes[] = {"invalido", "int", "float", "bool", "void"};
    return nomes[tipo];
}

static void emitir(const char *op, const char *arg1, const char *arg2,
                   const char *result)
{
    Quadrupla *instrucao = alocar(sizeof *instrucao);
    *instrucao = (Quadrupla){op, arg1, arg2, result, 0, NULL};
    if (ultima != NULL)
        ultima->prox = instrucao;
    else
        codigo = instrucao;
    ultima = instrucao;
}

static Valor temporario(Tipo tipo)
{
    return (Valor){tipo, numerar("$t", ++temporarios)};
}

static const char *rotulo(void)
{
    return numerar("L", ++rotulos);
}

static void marcar(const char *nome)
{
    emitir("label", NULL, NULL, nome);
}

static Lista *adicionar(Lista *lista, Valor valor, YYLTYPE local)
{
    Lista *item = alocar(sizeof *item);
    *item = (Lista){valor, local, NULL, item};
    if (lista == NULL)
        return item;
    lista->ultimo->prox = item;
    lista->ultimo = item;
    return lista;
}

static Simbolo *buscar_no_escopo(Escopo *ambiente, const char *nome)
{
    Simbolo *simbolo;
    for (simbolo = ambiente->variaveis; simbolo != NULL; simbolo = simbolo->prox)
        if (strcmp(simbolo->nome, nome) == 0)
            return simbolo;
    return NULL;
}

static Valor declarar(Tipo tipo, const char *nome, const char *categoria,
                      YYLTYPE local)
{
    Simbolo *simbolo;
    const char *lugar;

    if (buscar_no_escopo(escopo, nome) != NULL) {
        erro_semantico(local, "variavel '%s' ja declarada neste escopo", nome);
        return (Valor){T_INVALIDO, NULL};
    }
    lugar = nome;
    if (escopo != &global) {
        /* O separador distingue, por exemplo, x1 (nome) de x (nome) + 1. */
        size_t tamanho = strlen(nome) + 32;
        char *identidade = alocar(tamanho);
        snprintf(identidade, tamanho, "%s$%u", nome, ++locais);
        lugar = identidade;
    }
    simbolo = alocar(sizeof *simbolo);
    *simbolo = (Simbolo){nome, {tipo, lugar}, categoria,
                         funcao_atual == NULL ? NULL : funcao_atual->nome,
                         escopo->numero, escopo->variaveis, NULL};
    escopo->variaveis = simbolo;
    if (ultimo_declarado == NULL)
        declarados = simbolo;
    else
        ultimo_declarado->prox_declarado = simbolo;
    ultimo_declarado = simbolo;
    return simbolo->valor;
}

static void declarar_variavel(Tipo tipo, const char *nome, YYLTYPE local)
{
    Valor valor = declarar(tipo, nome, "variavel", local);
    if (valor.tipo != T_INVALIDO)
        emitir(escopo == &global ? "global" : "local",
               nome_tipo(tipo), NULL, valor.lugar);
}

static Valor resolver(const char *nome, YYLTYPE local)
{
    Escopo *ambiente;
    for (ambiente = escopo; ambiente != NULL; ambiente = ambiente->pai) {
        Simbolo *simbolo = buscar_no_escopo(ambiente, nome);
        if (simbolo != NULL)
            return simbolo->valor;
    }
    erro_semantico(local, "variavel '%s' usada sem declaracao visivel", nome);
    return (Valor){T_INVALIDO, NULL};
}

static void abrir_escopo(void)
{
    Escopo *novo = alocar(sizeof *novo);
    novo->pai = escopo;
    novo->numero = ++blocos;
    escopo = novo;
}

static Funcao *buscar_funcao(const char *nome)
{
    Funcao *funcao;
    for (funcao = funcoes; funcao != NULL; funcao = funcao->prox)
        if (strcmp(funcao->nome, nome) == 0)
            return funcao;
    return NULL;
}

static void iniciar_funcao(Tipo tipo, const char *nome, Lista *parametros,
                           YYLTYPE local)
{
    Funcao *funcao = buscar_funcao(nome);
    unsigned indice = 0;

    if (coletando) {
        if (funcao != NULL) {
            erro_semantico(local, "funcao '%s' ja declarada", nome);
            return;
        }
        funcao = alocar(sizeof *funcao);
        *funcao = (Funcao){nome, tipo, parametros, funcoes};
        funcoes = funcao;
        return;
    }

    funcao_atual = funcao;
    abrir_escopo();
    emitir("func", nome_tipo(tipo), NULL, nome);
    for (; parametros != NULL; parametros = parametros->prox) {
        Valor parametro = declarar(parametros->valor.tipo, parametros->valor.lugar, "parametro",
                                   parametros->local);
        indice++;
        if (parametro.tipo != T_INVALIDO)
            emitir("recv", numerar("", indice), nome_tipo(parametro.tipo),
                   parametro.lugar);
    }
}

static void encerrar_funcao(int retorna, YYLTYPE local)
{
    if (coletando)
        return;
    if (!retorna) {
        if (funcao_atual->retorno == T_VOID)
            emitir("return", NULL, NULL, NULL);
        else if (funcao_atual->retorno == T_INT &&
                 strcmp(funcao_atual->nome, "principal") == 0)
            emitir("return", "0", NULL, NULL);
        else
            erro_semantico(local, "funcao '%s' pode terminar sem retorno",
                           funcao_atual->nome);
    }
    emitir("endfunc", NULL, NULL, funcao_atual->nome);
    escopo = escopo->pai;
    funcao_atual = NULL;
}

static int numerico(Tipo tipo)
{
    return tipo == T_INT || tipo == T_FLOAT;
}

static Valor converter(Tipo destino, Valor origem, YYLTYPE local,
                       const char *contexto)
{
    if (origem.tipo == destino || origem.tipo == T_INVALIDO)
        return origem;
    if (destino == T_FLOAT && origem.tipo == T_INT) {
        Valor convertido = temporario(T_FLOAT);
        emitir("i2f", origem.lugar, NULL, convertido.lugar);
        return convertido;
    }
    erro_semantico(local, "%s espera %s, recebeu %s", contexto,
                   nome_tipo(destino), nome_tipo(origem.tipo));
    return (Valor){T_INVALIDO, NULL};
}

static Valor ler_variavel(const char *nome, YYLTYPE local)
{
    Valor origem, copia;
    if (coletando)
        return (Valor){T_INVALIDO, NULL};
    origem = resolver(nome, local);
    if (origem.tipo == T_INVALIDO)
        return origem;
    /* Captura o valor antes que uma chamada posterior possa altera-lo. */
    copia = temporario(origem.tipo);
    emitir("=", origem.lugar, NULL, copia.lugar);
    return copia;
}

static void atribuir(const char *nome, Valor valor, YYLTYPE local)
{
    Valor destino;
    if (coletando)
        return;
    destino = resolver(nome, local);
    if (destino.tipo != T_INVALIDO) {
        valor = converter(destino.tipo, valor, local, "atribuicao");
        if (valor.tipo != T_INVALIDO)
            emitir("=", valor.lugar, NULL, destino.lugar);
    }
}

static Valor operar(Tipo tipo, const char *op, Valor a, Valor b)
{
    Valor resultado = temporario(tipo);
    emitir(op, a.lugar, b.lugar, resultado.lugar);
    ultima->operacao_real = a.tipo == T_FLOAT;
    return resultado;
}

static Valor unario(const char *op, Valor valor, YYLTYPE local)
{
    Valor invalido = {T_INVALIDO, NULL};
    if (coletando || valor.tipo == T_INVALIDO)
        return invalido;
    if ((*op == '!' && valor.tipo == T_BOOL) ||
        (*op == 'n' && numerico(valor.tipo)))
        return operar(valor.tipo, op, valor, invalido);
    erro_semantico(local, "operador %s incompativel com %s",
                   *op == 'n' ? "-" : op, nome_tipo(valor.tipo));
    return invalido;
}

static Valor binario(const char *op, Valor a, Valor b, YYLTYPE local)
{
    Valor invalido = {T_INVALIDO, NULL};
    int igualdade = *op == '=' || *op == '!';
    int comparacao = igualdade || *op == '<' || *op == '>';
    Tipo tipo;

    if (coletando || a.tipo == T_INVALIDO || b.tipo == T_INVALIDO)
        return invalido;
    if (igualdade && a.tipo == T_BOOL && b.tipo == T_BOOL)
        return operar(T_BOOL, op, a, b);
    if (!numerico(a.tipo) || !numerico(b.tipo) ||
        (*op == '%' && (a.tipo != T_INT || b.tipo != T_INT))) {
        erro_semantico(local, "operador %s incompativel com %s e %s", op,
                       nome_tipo(a.tipo), nome_tipo(b.tipo));
        return invalido;
    }
    tipo = a.tipo == T_FLOAT || b.tipo == T_FLOAT ? T_FLOAT : T_INT;
    a = converter(tipo, a, local, op);
    b = converter(tipo, b, local, op);
    return operar(comparacao ? T_BOOL : tipo, op, a, b);
}

static Valor obter_valor(Valor valor, YYLTYPE local)
{
    if (!coletando && valor.tipo == T_VOID) {
        erro_semantico(local, "chamada de funcao void usada como expressao");
        return (Valor){T_INVALIDO, NULL};
    }
    return valor;
}

static Valor chamar(const char *nome, Lista *argumentos, YYLTYPE local)
{
    Funcao *funcao;
    Lista *parametro, *argumento;
    unsigned quantidade = 0;
    Valor resultado;

    if (coletando)
        return (Valor){T_INVALIDO, NULL};
    funcao = buscar_funcao(nome);
    if (funcao == NULL) {
        erro_semantico(local, "funcao '%s' nao declarada", nome);
        return (Valor){T_INVALIDO, NULL};
    }
    parametro = funcao->parametros;
    argumento = argumentos;
    while (parametro != NULL && argumento != NULL) {
        char contexto[64];
        quantidade++;
        snprintf(contexto, sizeof contexto, "argumento %u", quantidade);
        argumento->valor = converter(parametro->valor.tipo, argumento->valor,
                                     argumento->local, contexto);
        argumento = argumento->prox;
        parametro = parametro->prox;
    }
    if (parametro != NULL || argumento != NULL) {
        unsigned esperados = quantidade, recebidos = quantidade;
        for (; parametro != NULL; parametro = parametro->prox)
            esperados++;
        for (; argumento != NULL; argumento = argumento->prox)
            recebidos++;
        erro_semantico(local, "funcao '%s' espera %u argumento(s), recebeu %u",
                       nome, esperados, recebidos);
        return (Valor){T_INVALIDO, NULL};
    }
    for (argumento = argumentos; argumento != NULL; argumento = argumento->prox)
        emitir("param", argumento->valor.lugar, NULL, NULL);
    resultado = funcao->retorno == T_VOID ? (Valor){T_VOID, NULL}
                                         : temporario(funcao->retorno);
    emitir("call", nome, numerar("", quantidade), resultado.lugar);
    return resultado;
}

static void retornar(Valor valor, int tem_valor, YYLTYPE local)
{
    Tipo retorno;
    if (coletando)
        return;
    retorno = funcao_atual->retorno;
    if ((retorno == T_VOID) == tem_valor) {
        erro_semantico(local, retorno == T_VOID
                       ? "funcao void deve usar return sem valor"
                       : "funcao com retorno %s deve retornar um valor",
                       nome_tipo(retorno));
        return;
    }
    if (tem_valor)
        valor = converter(retorno, valor, local, "retorno");
    emitir("return", valor.lugar, NULL, NULL);
}

static void exigir_bool(Valor valor, YYLTYPE local, const char *contexto)
{
    if (valor.tipo != T_BOOL && valor.tipo != T_INVALIDO)
        erro_semantico(local, "%s exige bool, recebeu %s", contexto,
                       nome_tipo(valor.tipo));
}

static const char *desviar(Valor condicao, YYLTYPE local)
{
    const char *fim;
    if (coletando)
        return NULL;
    exigir_bool(condicao, local, "condicao");
    fim = rotulo();
    emitir("ifFalse", condicao.lugar, NULL, fim);
    return fim;
}

static Laco iniciar_logico(Valor esquerdo, int conjuncao, YYLTYPE local)
{
    Laco controle = {NULL, NULL};
    if (!coletando) {
        exigir_bool(esquerdo, local, "operador logico");
        controle.inicio = temporario(T_BOOL).lugar;
        controle.fim = rotulo();
        emitir("=", conjuncao ? "false" : "true", NULL, controle.inicio);
        emitir(conjuncao ? "ifFalse" : "ifTrue", esquerdo.lugar, NULL, controle.fim);
    }
    return controle;
}

static Valor encerrar_logico(Laco controle, Valor direito, YYLTYPE local)
{
    if (coletando)
        return (Valor){T_INVALIDO, NULL};
    exigir_bool(direito, local, "operador logico");
    emitir("=", direito.lugar, NULL, controle.inicio);
    marcar(controle.fim);
    return (Valor){T_BOOL, controle.inicio};
}

static void imprimir_simbolos(void)
{
    const Simbolo *simbolo;
    const Funcao *funcao;

    puts("\nTabela de simbolos");
    printf("%-20s %-12s %-8s %-20s %s\n",
           "nome", "categoria", "tipo", "identificador IR", "escopo");
    for (simbolo = declarados; simbolo != NULL; simbolo = simbolo->prox_declarado) {
        printf("%-20s %-12s %-8s %-20s ", simbolo->nome, simbolo->categoria,
               nome_tipo(simbolo->valor.tipo), simbolo->valor.lugar);
        if (simbolo->funcao == NULL)
            puts("global");
        else
            printf("%s (bloco %u)\n", simbolo->funcao, simbolo->bloco);
    }
    for (funcao = funcoes; funcao != NULL; funcao = funcao->prox) {
        const Lista *parametro;
        printf("%-20s %-12s %-8s %-20s global | parametros (",
               funcao->nome, "funcao", nome_tipo(funcao->retorno), funcao->nome);
        for (parametro = funcao->parametros; parametro != NULL; parametro = parametro->prox)
            printf("%s%s", parametro == funcao->parametros ? "" : ", ",
                   nome_tipo(parametro->valor.tipo));
        puts(")");
    }
}

static void imprimir_tres_enderecos(void)
{
    const Quadrupla *q;

    puts("\nCodigo de tres enderecos");
    for (q = codigo; q != NULL; q = q->prox) {
        const char *op = q->op;
        if (strcmp(op, "func") == 0)
            printf("\n%s:  [retorno %s]\n", q->result, q->arg1);
        else if (strcmp(op, "label") == 0)
            printf("%s:\n", q->result);
        else if (strcmp(op, "global") == 0 || strcmp(op, "local") == 0)
            printf("  %s %s %s\n", op, q->arg1, q->result);
        else if (strcmp(op, "recv") == 0)
            printf("  %s %s = recv %s\n", q->arg2, q->result, q->arg1);
        else if (strcmp(op, "goto") == 0)
            printf("  goto %s\n", q->result);
        else if (strcmp(op, "ifFalse") == 0 || strcmp(op, "ifTrue") == 0)
            printf("  %s %s goto %s\n", op, q->arg1, q->result);
        else if (strcmp(op, "param") == 0)
            printf("  param %s\n", q->arg1);
        else if (strcmp(op, "call") == 0) {
            if (q->result != NULL)
                printf("  %s = ", q->result);
            else
                printf("  ");
            printf("call %s, %s\n", q->arg1, q->arg2);
        } else if (strcmp(op, "return") == 0) {
            if (q->arg1 == NULL)
                puts("  return");
            else
                printf("  return %s\n", q->arg1);
        } else if (strcmp(op, "endfunc") == 0)
            printf("endfunc %s\n", q->result);
        else if (strcmp(op, "=") == 0)
            printf("  %s = %s\n", q->result, q->arg1);
        else if (q->arg2 == NULL)
            printf("  %s = %s %s\n", q->result,
                   strcmp(op, "neg") == 0 ? "-" : op, q->arg1);
        else
            printf("  %s = %s %s %s\n", q->result, q->arg1, op, q->arg2);
    }
}

static void imprimir_codigo(FILE *saida)
{
    const Quadrupla *instrucao;
    fputs("\nCodigo intermediario (quadruplas)\n", saida);
    fprintf(saida, "%-9s %-16s %-12s %s\n", "op", "arg1", "arg2", "result");
    for (instrucao = codigo; instrucao != NULL; instrucao = instrucao->prox)
        fprintf(saida, "%-9s %-16s %-12s %s\n", instrucao->op,
               instrucao->arg1 == NULL ? "-" : instrucao->arg1,
               instrucao->arg2 == NULL ? "-" : instrucao->arg2,
               instrucao->result == NULL ? "-" : instrucao->result);
}

static const char *caminho_saida(const char *fonte, const char *extensao)
{
    const char *nome = fonte;
    const char *p;
    size_t base;
    char *caminho;

    for (p = fonte; *p != '\0'; p++)
        if (*p == '/' || *p == '\\')
            nome = p + 1;
    p = strrchr(nome, '.');
    /* Aceita fontes .txt e outros sufixos sem sobrescrever o fonte. */
    base = p != NULL && p != nome && strcmp(p, ".txt") == 0
           ? (size_t)(p - fonte) : strlen(fonte);
    caminho = alocar(base + strlen(extensao) + 1);
    memcpy(caminho, fonte, base);
    strcpy(caminho + base, extensao);
    return caminho;
}

static int salvar_codigo(const char *fonte)
{
    const char *ir = caminho_saida(fonte, ".ir");
    const char *asm_alvo = caminho_saida(fonte, ".asm");
    FILE *intermediario = fopen(ir, "w");
    FILE *assembly;
    int sucesso;

    if (intermediario == NULL) {
        perror(ir);
        return 0;
    }
    imprimir_codigo(intermediario);
    if (fclose(intermediario) != 0) {
        perror(ir);
        return 0;
    }
    if (!validar_codigo_alvo(codigo)) {
        fprintf(stderr, "Codigo intermediario salvo em %s.\n", ir);
        return 0;
    }
    assembly = fopen(asm_alvo, "w");
    if (assembly == NULL) {
        perror(asm_alvo);
        return 0;
    }
    sucesso = gerar_assembly(assembly, codigo);
    if (fclose(assembly) != 0) {
        perror(asm_alvo);
        sucesso = 0;
    }
    if (!sucesso) {
        remove(asm_alvo);
        return 0;
    }
    printf("\nArquivos gerados %s e %s\n", ir, asm_alvo);
    return 1;
}
}

%define parse.error detailed
%define parse.lac full
%locations

%union {
    const char *texto;
    Tipo tipo;
    Valor valor;
    Lista *lista;
    Laco laco;
    Condicional condicional;
    int retorna;
}

%token INT "int" FLOAT "float" BOOL "bool" VOID "void"
%token IF "if" ELSE "else" WHILE "while" RETURN "return"
%token <texto> PRINCIPAL "principal"
%token <texto> LITERAL_BOOL "literal booleano"
%token <texto> ID_GLOBAL "identificador global" ID_LOCAL "identificador local"
%token <texto> ID_FUNCAO "identificador de funcao"
%token <texto> NUM_INT "numero inteiro" NUM_REAL "numero real"
%token IGUAL "==" DIFERENTE "!=" MAIOR_IGUAL ">=" MENOR_IGUAL "<="
%token E_LOGICO "&&" OU_LOGICO "||"
%token ERRO_LEXICO "token lexico invalido"

%left OU_LOGICO
%left E_LOGICO
%left IGUAL DIFERENTE
%left '>' '<' MAIOR_IGUAL MENOR_IGUAL
%left '+' '-'
%left '*' '/' '%'
%precedence '!' MENOS_UNARIO
%precedence IF_SEM_ELSE
%precedence ELSE

%type <tipo> tipo tipo_retorno
%type <texto> identificador inicio_if inicio_while
%type <valor> expressao chamada_funcao
%type <lista> parametros_opcionais lista_parametros argumentos_opcionais lista_argumentos
%type <laco> condicao_while
%type <condicional> inicio_else
%type <retorna> bloco comando item_bloco itens_bloco_opcionais

%start programa

%%

programa
    : declaracao_global programa
    | lista_funcoes
    ;

declaracao_global
    : tipo ID_GLOBAL ';'
      { if (coletando) declarar_variavel($1, $2, @2); }
    ;

lista_funcoes
    : funcao
    | lista_funcoes funcao
    ;

funcao
    : cabecalho '{' itens_bloco_opcionais '}' { encerrar_funcao($3, @1); }
    ;

cabecalho
    : tipo_retorno ID_FUNCAO '(' parametros_opcionais ')'
      { iniciar_funcao($1, $2, $4, @2); }
    | tipo_retorno PRINCIPAL '(' ')'
      { iniciar_funcao($1, $2, NULL, @2); }
    ;

tipo_retorno
    : tipo { $$ = $1; }
    | VOID { $$ = T_VOID; }
    ;

tipo
    : INT   { $$ = T_INT; }
    | FLOAT { $$ = T_FLOAT; }
    | BOOL  { $$ = T_BOOL; }
    ;

parametros_opcionais
    : %empty           { $$ = NULL; }
    | lista_parametros { $$ = $1; }
    ;

lista_parametros
    : tipo ID_LOCAL
      { $$ = adicionar(NULL, (Valor){$1, $2}, @2); }
    | lista_parametros ',' tipo ID_LOCAL
      { $$ = adicionar($1, (Valor){$3, $4}, @4); }
    ;

bloco
    : '{' { if (!coletando) abrir_escopo(); } itens_bloco_opcionais '}'
      { if (!coletando) escopo = escopo->pai; $$ = $3; }
    ;

itens_bloco_opcionais
    : %empty { $$ = 0; }
    | itens_bloco_opcionais item_bloco { $$ = $1 || $2; }
    ;

item_bloco
    : declaracao_local { $$ = 0; }
    | comando
    ;

declaracao_local
    : tipo ID_LOCAL ';'
      { if (!coletando) declarar_variavel($1, $2, @2); }
    ;

comando
    : identificador '=' expressao ';' { atribuir($1, $3, @1); $$ = 0; }
    | chamada_funcao ';' { $$ = 0; }
    | RETURN ';' { retornar((Valor){T_VOID, NULL}, 0, @1); $$ = 1; }
    | RETURN expressao ';' { retornar($2, 1, @1); $$ = 1; }
    | inicio_if comando %prec IF_SEM_ELSE
      { if (!coletando) marcar($1); $$ = 0; }
    | inicio_else comando
      { if (!coletando) marcar($1.fim); $$ = $1.ramo_anterior_retorna && $2; }
    | condicao_while comando
      {
          if (!coletando) {
              emitir("goto", NULL, NULL, $1.inicio);
              marcar($1.fim);
          }
          $$ = 0;
      }
    | bloco
    | ';' { $$ = 0; }
    ;

inicio_if
    : IF '(' expressao ')' { $$ = desviar($3, @3); }
    ;

inicio_else
    : inicio_if comando ELSE
      {
          $$ = (Condicional){NULL, $2};
          if (!coletando) {
              $$.fim = rotulo();
              emitir("goto", NULL, NULL, $$.fim);
              marcar($1);
          }
      }
    ;

inicio_while
    : WHILE
      {
          $$ = NULL;
          if (!coletando) {
              $$ = rotulo();
              marcar($$);
          }
      }
    ;

condicao_while
    : inicio_while '(' expressao ')' { $$ = (Laco){$1, desviar($3, @3)}; }
    ;

identificador
    : ID_LOCAL  { $$ = $1; }
    | ID_GLOBAL { $$ = $1; }
    ;

expressao
    : NUM_INT      { $$ = (Valor){T_INT, $1}; }
    | NUM_REAL     { $$ = (Valor){T_FLOAT, $1}; }
    | LITERAL_BOOL { $$ = (Valor){T_BOOL, $1}; }
    | identificador { $$ = ler_variavel($1, @1); }
    | chamada_funcao { $$ = obter_valor($1, @1); }
    | '(' expressao ')' { $$ = $2; }
    | '-' expressao %prec MENOS_UNARIO { $$ = unario("neg", $2, @1); }
    | '!' expressao { $$ = unario("!", $2, @1); }
    | expressao '+' expressao { $$ = binario("+", $1, $3, @2); }
    | expressao '-' expressao { $$ = binario("-", $1, $3, @2); }
    | expressao '*' expressao { $$ = binario("*", $1, $3, @2); }
    | expressao '/' expressao { $$ = binario("/", $1, $3, @2); }
    | expressao '%' expressao { $$ = binario("%", $1, $3, @2); }
    | expressao '>' expressao { $$ = binario(">", $1, $3, @2); }
    | expressao '<' expressao { $$ = binario("<", $1, $3, @2); }
    | expressao MAIOR_IGUAL expressao { $$ = binario(">=", $1, $3, @2); }
    | expressao MENOR_IGUAL expressao { $$ = binario("<=", $1, $3, @2); }
    | expressao IGUAL expressao { $$ = binario("==", $1, $3, @2); }
    | expressao DIFERENTE expressao { $$ = binario("!=", $1, $3, @2); }
    | expressao E_LOGICO { $<laco>$ = iniciar_logico($1, 1, @1); } expressao %prec E_LOGICO
      { $$ = encerrar_logico($<laco>3, $4, @4); }
    | expressao OU_LOGICO { $<laco>$ = iniciar_logico($1, 0, @1); } expressao %prec OU_LOGICO
      { $$ = encerrar_logico($<laco>3, $4, @4); }
    ;

chamada_funcao
    : ID_FUNCAO '(' argumentos_opcionais ')' { $$ = chamar($1, $3, @1); }
    ;

argumentos_opcionais
    : %empty           { $$ = NULL; }
    | lista_argumentos { $$ = $1; }
    ;

lista_argumentos
    : expressao { $$ = coletando ? NULL : adicionar(NULL, $1, @1); }
    | lista_argumentos ',' expressao
      { $$ = coletando ? NULL : adicionar($1, $3, @3); }
    ;

%%

void yyerror(const char *mensagem)
{
    const char *proximo;
    if (yychar == ERRO_LEXICO)
        return;
    proximo = yychar == YYEOF ? "fim de arquivo" : yytext;
    fprintf(stderr, "Erro sintatico na linha %d, coluna %d, proximo de '%s': %s.\n",
            yylloc.first_line, yylloc.first_column, proximo, mensagem);
    erros_sintaticos++;
}

int main(int argc, char **argv)
{
    int resultado;
    int sucesso;

    if (argc != 2) {
        fprintf(stderr, "Uso: %s <arquivo-fonte>\n", argv[0]);
        return EXIT_FAILURE;
    }

    yyin = fopen(argv[1], "r");
    if (yyin == NULL) {
        fprintf(stderr, "Nao foi possivel abrir o arquivo '%s'.\n", argv[1]);
        return EXIT_FAILURE;
    }

    /* Primeira passagem registra globais e assinaturas. A segunda traduz os corpos. */
    reiniciar_posicao_lexer();
    resultado = yyparse();
    if (resultado == 0 && erros_lexicos == 0 && erros_sintaticos == 0 &&
        buscar_funcao("principal") == NULL)
        erro_semantico(yylloc, "funcao principal ausente");
    if (resultado == 0 && erros_lexicos == 0 && erros_sintaticos == 0 &&
        erros_semanticos == 0) {
        coletando = 0;
        if (fseek(yyin, 0, SEEK_SET) != 0) {
            fputs("Nao foi possivel reler o arquivo-fonte.\n", stderr);
            resultado = 1;
        } else {
            yyrestart(yyin);
            reiniciar_posicao_lexer();
            resultado = yyparse();
        }
    }
    fclose(yyin);

    sucesso = resultado == 0 && erros_lexicos == 0 &&
              erros_sintaticos == 0 && erros_semanticos == 0;
    if (sucesso) {
        puts("Programa reconhecido com sucesso.");
        imprimir_simbolos();
        imprimir_tres_enderecos();
        imprimir_codigo(stdout);
        sucesso = salvar_codigo(argv[1]);
    } else {
        puts("Programa rejeitado.");
    }

    while (memoria != NULL) {
        Memoria *bloco = memoria;
        memoria = bloco->prox;
        free(bloco);
    }
    return sucesso ? EXIT_SUCCESS : EXIT_FAILURE;
}
