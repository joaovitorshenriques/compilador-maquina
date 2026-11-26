#ifndef CODIGO_ALVO_H
#define CODIGO_ALVO_H

#include <stdio.h>

typedef struct Quadrupla {
    const char *op;
    const char *arg1;
    const char *arg2;
    const char *result;
    int operacao_real;
    struct Quadrupla *prox;
} Quadrupla;

int validar_codigo_alvo(const Quadrupla *codigo);
int gerar_assembly(FILE *saida, const Quadrupla *codigo);

#endif
