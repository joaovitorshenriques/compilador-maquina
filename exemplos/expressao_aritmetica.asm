    LD R4, #0
    ST RESULTADO, R4
    ST ZV1, R4
    ST ZV2, R4
    ST ZV3, R4
    ST ZV4, R4
    ST ZT1, R4
    ST ZT2, R4
    ST ZT3, R4
    ST ZT4, R4
    ST ZT5, R4
    ST ZT6, R4
    ST ZT7, R4
ZF1:
    LD R4, #0
    ST ZV1, R4
    LD R4, #0
    ST ZV2, R4
    LD R4, #0
    ST ZV3, R4
    LD R4, #0
    ST ZV4, R4
    LD R1, #2
    ST ZV1, R1
    LD R1, #3
    ST ZV2, R1
    LD R1, #4
    ST ZV3, R1
    LD R1, #5
    ST ZV4, R1
    LD R1, ZV1
    ST ZT1, R1
    LD R1, ZV2
    ST ZT2, R1
    LD R1, ZT1
    LD R2, ZT2
    ADD R3, R1, R2
    ST ZT3, R3
    LD R1, ZV3
    ST ZT4, R1
    LD R1, ZT3
    LD R2, ZT4
    MUL R3, R1, R2
    ST ZT5, R3
    LD R1, ZV4
    ST ZT6, R1
    LD R1, ZT5
    LD R2, ZT6
    SUB R3, R1, R2
    ST ZT7, R3
    LD R1, ZT7
    ST RESULTADO, R1
    LD R0, #0
    HALT
