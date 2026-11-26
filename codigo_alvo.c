#include "codigo_alvo.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    FILE *saida;
    const Quadrupla *codigo;
    unsigned argumento;
    int principal;
} Gerador;

static int op_e(const Quadrupla *q, const char *op)
{
    return strcmp(q->op, op) == 0;
}

static unsigned numero_funcao(const Quadrupla *codigo, const char *nome)
{
    const Quadrupla *q;
    unsigned numero = 0;

    for (q = codigo; q != NULL; q = q->prox) {
        if (op_e(q, "func")) {
            numero++;
            if (strcmp(q->result, nome) == 0)
                return numero;
        }
    }
    return 0;
}

/* Nomes internos so usam letras e digitos. Globais ficam visiveis na memoria. */
static void memoria(FILE *saida, const char *nome)
{
    const char *separador = strrchr(nome, '$');

    if (nome[0] == '$')
        fprintf(saida, "ZT%s", nome + 2);
    else if (separador != NULL)
        fprintf(saida, "ZV%s", separador + 1);
    else if (nome[0] == 'Z')
        fprintf(saida, "Z%s", nome);
    else if (nome[0] == 'R' && nome[1] >= '0' && nome[1] <= '7' && nome[2] == '\0')
        fprintf(saida, "ZY%s", nome);
    else
        fputs(nome, saida);
}

static void carregar(FILE *saida, int reg, const char *valor)
{
    fprintf(saida, "    LD R%d, ", reg);
    if (strcmp(valor, "true") == 0 || strcmp(valor, "false") == 0)
        fprintf(saida, "#%d", strcmp(valor, "true") == 0);
    else if (isdigit((unsigned char)valor[0])) {
        uint32_t inteiro = 0;
        int64_t com_sinal;
        for (; *valor != '\0'; valor++)
            inteiro = inteiro * UINT32_C(10) + (uint32_t)(*valor - '0');
        com_sinal = inteiro;
        if (inteiro > INT32_MAX)
            com_sinal -= INT64_C(4294967296);
        fprintf(saida, "#%" PRId64, com_sinal);
    } else
        memoria(saida, valor);
    fputc('\n', saida);
}

static void gravar(FILE *saida, const char *destino, int reg)
{
    fputs("    ST ", saida);
    memoria(saida, destino);
    fprintf(saida, ", R%d\n", reg);
}

/* O plano de armazenamento da funcao e percorrido na mesma ordem antes
   e depois da chamada. A restauracao usa a lista em ordem inversa. */
static size_t listar_locais(const Quadrupla *funcao, const Quadrupla *fim,
                            const char **locais)
{
    const Quadrupla *q;
    size_t quantidade = 0;

    for (q = funcao->prox; q != fim; q = q->prox) {
        size_t i;
        const char *lugar = q->result;

        if (lugar == NULL || strchr(lugar, '$') == NULL)
            continue;
        for (i = 0; i < quantidade; i++)
            if (strcmp(locais[i], lugar) == 0)
                break;
        if (i == quantidade)
            locais[quantidade++] = lugar;
    }
    return quantidade;
}

static int comparacao(FILE *saida, const Quadrupla *q)
{
    static const struct {
        const char *op, *instrucao;
        int trocar, inverter;
    } comparacoes[] = {
        {"==", "SEQ", 0, 0}, {"!=", "SEQ", 0, 1}, {"!", "SEQ", 0, 0},
        {"<", "SLT", 0, 0}, {"<=", "SLT", 1, 1},
        {">", "SLT", 1, 0}, {">=", "SLT", 0, 1}
    };
    size_t i;

    for (i = 0; i < sizeof comparacoes / sizeof *comparacoes; i++) {
        if (!op_e(q, comparacoes[i].op))
            continue;
        carregar(saida, 1, q->arg1);
        carregar(saida, 2, q->arg2 == NULL ? "0" : q->arg2);
        fprintf(saida, "    %s R3, R%d, R%d\n", comparacoes[i].instrucao,
                comparacoes[i].trocar ? 2 : 1, comparacoes[i].trocar ? 1 : 2);
        if (comparacoes[i].inverter)
            fputs("    LD R2, #0\n    SEQ R3, R3, R2\n", saida);
        gravar(saida, q->result, 3);
        return 1;
    }
    return 0;
}

static int operacao(Gerador *g, const Quadrupla *q)
{
    FILE *saida = g->saida;
    const char *instrucao;

    if (comparacao(saida, q))
        return 1;
    switch (q->op[0]) {
    case '+': instrucao = "ADD"; break;
    case '-': instrucao = "SUB"; break;
    case '*': instrucao = "MUL"; break;
    case '/': instrucao = "DIV"; break;
    case '%': instrucao = "MOD"; break;
    case 'n': instrucao = "SUB"; break;
    default:
        fprintf(stderr, "Operacao intermediaria desconhecida: %s.\n", q->op);
        return 0;
    }
    carregar(saida, 1, q->arg2 == NULL ? "0" : q->arg1);
    carregar(saida, 2, q->arg2 == NULL ? q->arg1 : q->arg2);
    fprintf(saida, "    %s R3, R1, R2\n", instrucao);
    gravar(saida, q->result, 3);
    return 1;
}

static int traduzir(Gerador *g, const Quadrupla *q,
                    const char *const *locais, size_t quantidade)
{
    FILE *saida = g->saida;

    if (op_e(q, "global") || op_e(q, "endfunc"))
        return 1;
    if (op_e(q, "func")) {
        g->principal = strcmp(q->result, "principal") == 0;
        fprintf(saida, "ZF%u:\n", numero_funcao(g->codigo, q->result));
    } else if (op_e(q, "local")) {
        carregar(saida, 4, "0");
        gravar(saida, q->result, 4);
    } else if (op_e(q, "recv")) {
        fprintf(saida, "    LD R1, ZA%s\n", q->arg1);
        gravar(saida, q->result, 1);
    } else if (op_e(q, "param")) {
        carregar(saida, 1, q->arg1);
        fprintf(saida, "    ST ZA%u, R1\n", ++g->argumento);
    } else if (op_e(q, "call")) {
        size_t i;

        for (i = 0; i < quantidade; i++) {
            carregar(saida, 4, locais[i]);
            fputs("    PUSH R4\n", saida);
        }
        fprintf(saida, "    CALL ZF%u\n", numero_funcao(g->codigo, q->arg1));
        for (i = quantidade; i > 0; i--) {
            fputs("    POP R4\n", saida);
            gravar(saida, locais[i - 1], 4);
        }
        if (q->result != NULL)
            gravar(saida, q->result, 0);
        g->argumento = 0;
    } else if (op_e(q, "return")) {
        if (q->arg1 != NULL)
            carregar(saida, 0, q->arg1);
        fputs(g->principal ? "    HALT\n" : "    RET\n", saida);
    } else if (op_e(q, "label")) {
        fprintf(saida, "Z%s:\n", q->result);
    } else if (op_e(q, "goto")) {
        fprintf(saida, "    BR Z%s\n", q->result);
    } else if (op_e(q, "ifFalse") || op_e(q, "ifTrue")) {
        carregar(saida, 1, q->arg1);
        fprintf(saida, "    %s R1, Z%s\n", op_e(q, "ifFalse") ? "BEQZ" : "BNEZ", q->result);
    } else if (op_e(q, "=")) {
        carregar(saida, 1, q->arg1);
        gravar(saida, q->result, 1);
    } else {
        return operacao(g, q);
    }
    return 1;
}

static const Quadrupla *fim_funcao(const Quadrupla *funcao)
{
    const Quadrupla *q = funcao->prox;
    while (!op_e(q, "endfunc"))
        q = q->prox;
    return q;
}

static int traduzir_funcao(Gerador *g, const Quadrupla *funcao,
                           const Quadrupla *fim, const char **locais)
{
    size_t quantidade = listar_locais(funcao, fim, locais);
    const Quadrupla *q;

    for (q = funcao; q != fim; q = q->prox)
        if (!traduzir(g, q, locais, quantidade))
            return 0;
    return 1;
}

int validar_codigo_alvo(const Quadrupla *codigo)
{
    const Quadrupla *q;
    for (q = codigo; q != NULL; q = q->prox) {
        const char *tipo = NULL;
        if (op_e(q, "global") || op_e(q, "local") || op_e(q, "func"))
            tipo = q->arg1;
        else if (op_e(q, "recv"))
            tipo = q->arg2;
        if (q->operacao_real || op_e(q, "i2f") ||
            (tipo != NULL && strcmp(tipo, "float") == 0)) {
            fputs("Erro de codigo-alvo: o simulador usa inteiros de 32 bits e nao suporta float.\n",
                  stderr);
            return 0;
        }
    }
    return 1;
}

int gerar_assembly(FILE *saida, const Quadrupla *codigo)
{
    const Quadrupla *q, *fim, *principal = NULL;
    const char **locais;
    size_t total = 0;
    Gerador g = {saida, codigo, 0, 0};
    int sucesso;

    for (q = codigo; q != NULL; q = q->prox)
        total++;
    locais = malloc(total * sizeof *locais);
    if (locais == NULL) {
        fputs("Memoria insuficiente para gerar Assembly.\n", stderr);
        return 0;
    }

    /* Inicializa as celulas antes que possam ser salvas em uma chamada. */
    fputs("    LD R4, #0\n", saida);
    for (q = codigo; q != NULL; q = q->prox) {
        if (op_e(q, "global"))
            gravar(saida, q->result, 4);
        if (op_e(q, "func")) {
            size_t quantidade;

            if (strcmp(q->result, "principal") == 0)
                principal = q;
            fim = fim_funcao(q);
            quantidade = listar_locais(q, fim, locais);
            for (size_t i = 0; i < quantidade; i++)
                gravar(saida, locais[i], 4);
            q = fim;
        }
    }

    /* A execucao comeca em principal, independentemente da ordem no fonte. */
    sucesso = principal != NULL && traduzir_funcao(&g, principal, fim_funcao(principal), locais);
    for (q = codigo; q != NULL && sucesso; q = q->prox) {
        if (op_e(q, "func")) {
            fim = fim_funcao(q);
            if (q != principal)
                sucesso = traduzir_funcao(&g, q, fim, locais);
            q = fim;
        }
    }
    free(locais);
    return sucesso && !ferror(saida);
}
