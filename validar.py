"""Valida o Assembly em um modelo local, independente do compilador e do Moodle."""

import re
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


RAIZ = Path(__file__).resolve().parent
REGISTRADORES = {f"R{i}" for i in range(8)}
def divisao(a, b):
    quociente = abs(a) // abs(b)
    return -quociente if (a < 0) != (b < 0) else quociente


def inteiro32(valor):
    return ((valor + 2**31) % 2**32) - 2**31


ARITMETICA = {
    "ADD": lambda a, b: a + b,
    "SUB": lambda a, b: a - b,
    "MUL": lambda a, b: a * b,
    "DIV": divisao,
    "MOD": lambda a, b: a - divisao(a, b) * b,
    "SLT": lambda a, b: int(a < b),
    "SEQ": lambda a, b: int(a == b),
}


def executar(assembly):
    rotulos, instrucoes = {}, []
    registradores = dict.fromkeys(REGISTRADORES, 0)
    memoria, pilha = {}, []
    for linha in assembly.splitlines():
        linha = linha.strip()
        if linha.endswith(":"):
            rotulo = linha[:-1].upper()
            assert rotulo not in rotulos, f"Rotulo duplicado: {rotulo}"
            rotulos[rotulo] = len(instrucoes)
        elif linha:
            instrucoes.append(re.split(r"[,\s]+", linha))

    def ler(operando):
        if operando.startswith("#"):
            assert re.fullmatch(r"[+-]?\d+", operando[1:]), operando
            valor = int(operando[1:])
            assert -(2**31) <= valor < 2**31, operando
            return valor
        if operando.upper() in REGISTRADORES:
            return registradores[operando.upper()]
        return memoria[operando]

    pc = 0
    for _ in range(50_000):
        op, *args = instrucoes[pc]
        pc += 1
        if op == "HALT":
            assert not pilha, "Pilha ainda ocupada depois de HALT"
            return memoria
        if op == "LD":
            destino, fonte = args
            assert destino in REGISTRADORES
            registradores[destino] = ler(fonte)
        elif op == "ST":
            destino, fonte = args
            assert destino not in REGISTRADORES
            memoria[destino] = registradores[fonte]
        elif op in ARITMETICA:
            destino, a, b = args
            assert destino in REGISTRADORES
            registradores[destino] = inteiro32(ARITMETICA[op](ler(a), ler(b)))
        elif op == "BR":
            pc = rotulos[args[0].upper()]
        elif op in {"BEQZ", "BNEZ"}:
            reg, rotulo = args
            if (registradores[reg] == 0) == (op == "BEQZ"):
                pc = rotulos[rotulo.upper()]
        elif op == "CALL":
            pilha.append(("retorno", pc))
            pc = rotulos[args[0].upper()]
        elif op == "RET":
            tipo, pc = pilha.pop()
            assert tipo == "retorno"
        elif op == "PUSH":
            pilha.append(("dado", registradores[args[0]]))
        elif op == "POP":
            tipo, valor = pilha.pop()
            assert tipo == "dado"
            assert args[0] in REGISTRADORES
            registradores[args[0]] = valor
        else:
            raise AssertionError(f"Instrucao fora do modelo local: {op}")
        assert len(pilha) <= 4096, "Pilha excedeu 4096 posicoes"
    raise AssertionError("Programa excedeu 50.000 instrucoes")


def compilar(compilador, fonte):
    return subprocess.run([str(compilador), str(fonte)], capture_output=True, text=True)


def conferir(compilador, destino, texto, esperado):
    destino.write_text(texto, encoding="utf-8")
    processo = compilar(compilador, destino)
    assert processo.returncode == 0, processo.stderr
    assert "endfunc" in destino.with_suffix(".ir").read_text(encoding="utf-8")
    memoria = executar(destino.with_suffix(".asm").read_text(encoding="utf-8"))
    obtido = {nome: memoria[nome] for nome in esperado}
    assert obtido == esperado, f"{destino.name}: esperado {esperado}, obtido {obtido}"
    return obtido


CASOS_TP = {
    "expressao_aritmetica": (("a", "b", "c", "d"), [
        ((2, 3, 4, 5), 15), ((-2, 5, 3, 4), 5), ((2, 3, 0, 7), -7),
    ]),
    "maior_de_tres": (("a", "b", "c"), [
        ((7, 12, 5), 12), ((9, 9, 3), 9), ((-4, -4, -4), -4),
    ]),
    "fatorial_iterativo": (("n",), [
        ((5,), 120), ((0,), 1), ((1,), 1),
    ]),
    "fatorial_recursivo": (("n",), [
        ((0,), 1), ((1,), 1), ((4,), 24), ((5,), 120),
    ]),
}


def main(compilador):
    with TemporaryDirectory(prefix="validacao-", dir=RAIZ / "build") as temporario:
        destino = Path(temporario)
        for problema, (variaveis, casos) in CASOS_TP.items():
            texto = (RAIZ / "exemplos" / f"{problema}.txt").read_text(encoding="utf-8")
            for indice, (valores, resultado) in enumerate(casos, start=1):
                programa = texto
                for nome, valor in zip(variaveis, valores):
                    programa, alteracoes = re.subn(
                        rf"(?m)^(\s*{nome} = )\d+;", rf"\g<1>{valor};", programa
                    )
                    assert alteracoes == 1
                obtido = conferir(compilador, destino / f"{problema}_{indice}.txt",
                                   programa, {"RESULTADO": resultado})
                print(f"{problema} {valores}: {obtido['RESULTADO']}")

        texto = (RAIZ / "teste_valido.txt").read_text(encoding="utf-8")
        fonte_real = destino / "teste_valido.txt"
        fonte_real.write_text(texto, encoding="utf-8")
        processo = compilar(compilador, fonte_real)
        assert processo.returncode != 0 and "nao suporta float" in processo.stderr
        assert "i2f" in fonte_real.with_suffix(".ir").read_text(encoding="utf-8")
        assert not fonte_real.with_suffix(".asm").exists()
        conferir(compilador, destino / "funcoes.txt", """
int RESULTADO;
int ESTADO;
int salvarEstado(int x) { ESTADO = x; return x; }
int combinarValores(int x, int y) { return x * 10 + y; }
int principal() {
    ESTADO = 4;
    RESULTADO = combinarValores(ESTADO, salvarEstado(7));
    if (false && salvarEstado(8) == 8) ESTADO = 9;
    if (true || salvarEstado(8) == 8) {
        RESULTADO = RESULTADO + (-9 / 2) * 10 + (-9 % 2);
    }
    return 0;
}
""", {"RESULTADO": 6, "ESTADO": 7})
        conferir(compilador, destino / "comparacoes.txt", """
int RESULTADO;
int principal() {
    int a;
    int b;
    a = -2147483648;
    b = 2147483647;
    if (a < b && b > a && a <= a && b >= b && a != b && !(b == a)) {
        RESULTADO = 1;
    }
}
""", {"RESULTADO": 1})
        print("Chamadas, curto-circuito, div/mod, comparacoes de 32 bits e rejeicao de float: OK")

        invalidos = {
            "lexico": ("int principal() { @ }", "Erro lexico"),
            "sintatico": ("int principal() { return 0 }", "Erro sintatico"),
            "semantico": ((RAIZ / "teste_erros.txt").read_text(encoding="utf-8"),
                          "Erro semantico"),
            "sem_principal": ("void outraFuncao() {}", "funcao principal ausente"),
            "sem_retorno": ("int outraFuncao() {} int principal() {}", "pode terminar sem retorno"),
        }
        for caso, (texto, diagnostico) in invalidos.items():
            fonte = destino / f"{caso}.txt"
            fonte.write_text(texto, encoding="utf-8")
            processo = compilar(compilador, fonte)
            assert processo.returncode != 0 and diagnostico in processo.stderr, processo
            assert not fonte.with_suffix(".ir").exists()
            assert not fonte.with_suffix(".asm").exists()
            print(processo.stderr.splitlines()[0])


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
