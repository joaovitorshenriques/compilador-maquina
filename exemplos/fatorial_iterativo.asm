    LD R4, #0
    ST RESULTADO, R4
    ST ZV1, R4
    ST ZV2, R4
    ST ZT1, R4
    ST ZT2, R4
    ST ZT3, R4
    ST ZT4, R4
    ST ZT5, R4
    ST ZT6, R4
    ST ZT7, R4
    ST ZT8, R4
ZF1:
    LD R4, #0
    ST ZV1, R4
    LD R4, #0
    ST ZV2, R4
    LD R1, #5
    ST ZV1, R1
    LD R1, #2
    ST ZV2, R1
    LD R1, #1
    ST RESULTADO, R1
ZL1:
    LD R1, ZV2
    ST ZT1, R1
    LD R1, ZV1
    ST ZT2, R1
    LD R1, ZT1
    LD R2, ZT2
    SLT R3, R2, R1
    LD R2, #0
    SEQ R3, R3, R2
    ST ZT3, R3
    LD R1, ZT3
    BEQZ R1, ZL2
    LD R1, RESULTADO
    ST ZT4, R1
    LD R1, ZV2
    ST ZT5, R1
    LD R1, ZT4
    LD R2, ZT5
    MUL R3, R1, R2
    ST ZT6, R3
    LD R1, ZT6
    ST RESULTADO, R1
    LD R1, ZV2
    ST ZT7, R1
    LD R1, ZT7
    LD R2, #1
    ADD R3, R1, R2
    ST ZT8, R3
    LD R1, ZT8
    ST ZV2, R1
    BR ZL1
ZL2:
    LD R0, #0
    HALT
