param(
    [string]$CC = "gcc"
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Path build -Force | Out-Null
    & win_bison -Wall -d -o build/parser.tab.c parser.y
    if ($LASTEXITCODE -ne 0) { throw "Falha no Bison." }
    & win_flex -o build/lex.yy.c lexer.l
    if ($LASTEXITCODE -ne 0) { throw "Falha no Flex." }
    & $CC -std=c11 -Wall -Wextra -I. build/parser.tab.c build/lex.yy.c -o build/compilador.exe
    if ($LASTEXITCODE -ne 0) { throw "Falha no compilador C." }
} finally {
    Pop-Location
}
