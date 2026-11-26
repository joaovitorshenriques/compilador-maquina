%{
#include <stdio.h>
#include <stdlib.h>

int yylex(void);
void yyerror(const char *mensagem);
void reiniciar_posicao_lexer(void);

extern FILE *yyin;
extern char *yytext;
extern int erros_lexicos;

static int erros_sintaticos = 0;
%}

%define parse.error detailed
%define parse.lac full
%locations

%token INT "int"
%token FLOAT "float"
%token BOOL "bool"
%token VOID "void"
%token IF "if"
%token ELSE "else"
%token WHILE "while"
%token RETURN "return"
%token PRINCIPAL "principal"
%token LITERAL_BOOL "literal booleano"
%token ID_GLOBAL "identificador global"
%token ID_LOCAL "identificador local"
%token ID_FUNCAO "identificador de funcao"
%token NUM_INT "numero inteiro"
%token NUM_REAL "numero real"
%token IGUAL "=="
%token DIFERENTE "!="
%token MAIOR_IGUAL ">="
%token MENOR_IGUAL "<="
%token E_LOGICO "&&"
%token OU_LOGICO "||"
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

%start programa

%%

programa
    : declaracoes_globais lista_funcoes
    ;

declaracoes_globais
    : %empty
    | declaracoes_globais declaracao_global
    ;

declaracao_global
    : tipo ID_GLOBAL ';'
    ;

lista_funcoes
    : funcao
    | lista_funcoes funcao
    ;

funcao
    : tipo_retorno ID_FUNCAO '(' parametros_opcionais ')' bloco
    | tipo_retorno PRINCIPAL '(' ')' bloco
    ;

tipo_retorno
    : tipo
    | VOID
    ;

tipo
    : INT
    | FLOAT
    | BOOL
    ;

parametros_opcionais
    : %empty
    | lista_parametros
    ;

lista_parametros
    : parametro
    | lista_parametros ',' parametro
    ;

parametro
    : tipo ID_LOCAL
    ;

bloco
    : '{' itens_bloco_opcionais '}'
    /* Recupera um ultimo item invalido que nao chegou a terminar com ';'. */
    | '{' itens_bloco_opcionais error '}' { yyerrok; }
    ;

itens_bloco_opcionais
    : %empty
    | itens_bloco_opcionais item_bloco
    ;

item_bloco
    : declaracao_local
    | comando
    /* Descarta o item invalido ate ';' e continua com o proximo item. */
    | error ';' { yyerrok; }
    ;

declaracao_local
    : tipo ID_LOCAL ';'
    ;

comando
    : atribuicao ';'
    | chamada_funcao ';'
    | RETURN expressao_opcional ';'
    | IF '(' expressao ')' comando %prec IF_SEM_ELSE
    | IF '(' expressao ')' comando ELSE comando
    | WHILE '(' expressao ')' comando
    | bloco
    | ';'
    ;

atribuicao
    : identificador '=' expressao
    ;

identificador
    : ID_LOCAL
    | ID_GLOBAL
    ;

expressao_opcional
    : %empty
    | expressao
    ;

expressao
    : NUM_INT
    | NUM_REAL
    | LITERAL_BOOL
    | identificador
    | chamada_funcao
    | '(' expressao ')'
    | '-' expressao %prec MENOS_UNARIO
    | '!' expressao
    | expressao '+' expressao
    | expressao '-' expressao
    | expressao '*' expressao
    | expressao '/' expressao
    | expressao '%' expressao
    | expressao '>' expressao
    | expressao '<' expressao
    | expressao MAIOR_IGUAL expressao
    | expressao MENOR_IGUAL expressao
    | expressao IGUAL expressao
    | expressao DIFERENTE expressao
    | expressao E_LOGICO expressao
    | expressao OU_LOGICO expressao
    ;

chamada_funcao
    : ID_FUNCAO '(' argumentos_opcionais ')'
    ;

argumentos_opcionais
    : %empty
    | lista_argumentos
    ;

lista_argumentos
    : expressao
    | lista_argumentos ',' expressao
    ;

%%

void yyerror(const char *mensagem)
{
    const char *proximo;

    if (yychar == ERRO_LEXICO) {
        return;
    }

    proximo = yychar == YYEOF
                  ? "fim de arquivo"
                  : ((yytext != NULL && yytext[0] != '\0') ? yytext : "token desconhecido");

    fprintf(stderr,
            "Erro sintatico na linha %d, coluna %d, proximo de '%s': %s.\n",
            yylloc.first_line,
            yylloc.first_column,
            proximo,
            mensagem);
    erros_sintaticos++;
}

int main(int argc, char **argv)
{
    int resultado;

    if (argc != 2) {
        fprintf(stderr, "Uso: %s <arquivo-fonte>\n", argv[0]);
        return EXIT_FAILURE;
    }

    yyin = fopen(argv[1], "r");
    if (yyin == NULL) {
        fprintf(stderr, "Nao foi possivel abrir o arquivo '%s'.\n", argv[1]);
        return EXIT_FAILURE;
    }

    reiniciar_posicao_lexer();
    resultado = yyparse();
    fclose(yyin);

    if (erros_lexicos == 0 && resultado == 0) {
        printf("Analise lexica concluida.\n");
    } else if (erros_lexicos == 0) {
        printf("Nenhum erro lexico encontrado no trecho analisado.\n");
    } else {
        printf("Analise lexica encontrou %d erro(s).\n", erros_lexicos);
    }

    if (erros_sintaticos == 0 && erros_lexicos == 0 && resultado == 0) {
        printf("Analise sintatica concluida.\n");
    } else if (erros_sintaticos > 0) {
        printf("Analise sintatica encontrou %d erro(s).\n", erros_sintaticos);
    } else {
        printf("Analise sintatica comprometida por erro lexico.\n");
    }

    if (erros_lexicos == 0 && erros_sintaticos == 0 && resultado == 0) {
        printf("Programa reconhecido com sucesso.\n");
        return EXIT_SUCCESS;
    }

    printf("Programa rejeitado.\n");
    return EXIT_FAILURE;
}
