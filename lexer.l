%option noyywrap noinput nounput nodefault

%{
#include <stdio.h>
#include <string.h>

#include "parser.tab.h"

int erros_lexicos = 0;

static int linha_atual = 1;
static int coluna_atual = 1;
static int linha_inicio_comentario = 1;
static int coluna_inicio_comentario = 1;

static void atualizar_localizacao(const char *texto, int tamanho);
static void informar_erro_lexico(const char *descricao, const char *lexema);

#define YY_USER_ACTION atualizar_localizacao(yytext, yyleng);
%}

%x COMENTARIO

DIGITO              [0-9]
INTEIRO             {DIGITO}+
REAL                (({DIGITO}+\.{DIGITO}*|{DIGITO}*\.{DIGITO}+)([eE][+-]?{DIGITO}+)?|{DIGITO}+[eE][+-]?{DIGITO}+)
ID_GLOBAL           [A-Z][A-Z0-9_]*
ID_LOCAL            [a-z][a-z0-9_]*
ID_FUNCAO           [a-z]+[A-Z][A-Za-z0-9]*
ID_GENERICO         [A-Za-z_][A-Za-z0-9_]*
NUMERO_MALFORMADO   {DIGITO}+[A-Za-z_][A-Za-z0-9_]*

%%

"int"               { return INT; }
"float"             { return FLOAT; }
"bool"              { return BOOL; }
"void"              { return VOID; }
"if"                { return IF; }
"else"              { return ELSE; }
"while"             { return WHILE; }
"return"            { return RETURN; }
"true"              { return LITERAL_BOOL; }
"false"             { return LITERAL_BOOL; }
"principal"         { return PRINCIPAL; }

"=="                { return IGUAL; }
"!="                { return DIFERENTE; }
">="                { return MAIOR_IGUAL; }
"<="                { return MENOR_IGUAL; }
"&&"                { return E_LOGICO; }
"||"                { return OU_LOGICO; }

{REAL}               { return NUM_REAL; }
{NUMERO_MALFORMADO}  {
                        informar_erro_lexico("numero seguido de identificador sem separacao", yytext);
                        return ERRO_LEXICO;
                     }
{INTEIRO}            { return NUM_INT; }
{ID_FUNCAO}          { return ID_FUNCAO; }
{ID_GLOBAL}          { return ID_GLOBAL; }
{ID_LOCAL}           { return ID_LOCAL; }
{ID_GENERICO}        {
                        informar_erro_lexico("identificador fora do padrao da linguagem", yytext);
                        return ERRO_LEXICO;
                     }

"//"[^\r\n]*        { /* Comentario de uma linha. */ }
"/*"                {
                        linha_inicio_comentario = yylloc.first_line;
                        coluna_inicio_comentario = yylloc.first_column;
                        BEGIN(COMENTARIO);
                     }
<COMENTARIO>"*/"     { BEGIN(INITIAL); }
<COMENTARIO>[^*\n]+  { /* Conteudo do comentario. */ }
<COMENTARIO>\n       { /* A localizacao e atualizada por YY_USER_ACTION. */ }
<COMENTARIO>"*"      { /* Asterisco que nao encerra o comentario. */ }
<COMENTARIO><<EOF>>  {
                        fprintf(stderr,
                                "Erro lexico na linha %d, coluna %d: comentario de bloco nao terminado.\n",
                                linha_inicio_comentario,
                                coluna_inicio_comentario);
                        erros_lexicos++;
                        BEGIN(INITIAL);
                        return ERRO_LEXICO;
                     }

[ \t\f\v\r]+         { /* Espacos em branco. */ }
\n                   { /* Quebra de linha. */ }

"+"                 { return '+'; }
"-"                 { return '-'; }
"*"                 { return '*'; }
"/"                 { return '/'; }
"%"                 { return '%'; }
"="                 { return '='; }
">"                 { return '>'; }
"<"                 { return '<'; }
"!"                 { return '!'; }
";"                 { return ';'; }
","                 { return ','; }
"("                 { return '('; }
")"                 { return ')'; }
"{"                 { return '{'; }
"}"                 { return '}'; }

.                    {
                        informar_erro_lexico("caractere nao reconhecido", yytext);
                        return ERRO_LEXICO;
                     }

%%

static void atualizar_localizacao(const char *texto, int tamanho)
{
    int i;

    yylloc.first_line = linha_atual;
    yylloc.first_column = coluna_atual;

    for (i = 0; i < tamanho; i++) {
        if (texto[i] == '\n') {
            linha_atual++;
            coluna_atual = 1;
        } else {
            coluna_atual++;
        }
    }

    yylloc.last_line = linha_atual;
    yylloc.last_column = coluna_atual > 1 ? coluna_atual - 1 : 1;
}

static void informar_erro_lexico(const char *descricao, const char *lexema)
{
    fprintf(stderr,
            "Erro lexico na linha %d, coluna %d: %s: '%s'.\n",
            yylloc.first_line,
            yylloc.first_column,
            descricao,
            lexema);
    erros_lexicos++;
}

void reiniciar_posicao_lexer(void)
{
    linha_atual = 1;
    coluna_atual = 1;
}
