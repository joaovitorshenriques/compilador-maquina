    LD R4, #0
    ST RESULTADO, R4
    ST ZV1, R4
    ST ZT1, R4
    ST ZT2, R4
    ST ZT3, R4
    ST ZT4, R4
    ST ZT5, R4
    ST ZT6, R4
    ST ZT7, R4
    ST ZV2, R4
    ST ZT8, R4
    ST ZT9, R4
ZF2:
    LD R4, #0
    ST ZV2, R4
    LD R1, #2
    ST ZV2, R1
    LD R1, ZV2
    ST ZT8, R1
    LD R1, ZT8
    ST ZA1, R1
    LD R4, ZV2
    PUSH R4
    LD R4, ZT8
    PUSH R4
    LD R4, ZT9
    PUSH R4
    CALL ZF1
    POP R4
    ST ZT9, R4
    POP R4
    ST ZT8, R4
    POP R4
    ST ZV2, R4
    ST ZT9, R0
    LD R1, ZT9
    ST RESULTADO, R1
    LD R0, #0
    HALT
ZF1:
    LD R1, ZA1
    ST ZV1, R1
    LD R1, ZV1
    ST ZT1, R1
    LD R1, ZT1
    LD R2, #1
    SLT R3, R2, R1
    LD R2, #0
    SEQ R3, R3, R2
    ST ZT2, R3
    LD R1, ZT2
    BEQZ R1, ZL1
    LD R0, #1
    RET
ZL1:
    LD R1, ZV1
    ST ZT3, R1
    LD R1, ZV1
    ST ZT4, R1
    LD R1, ZT4
    LD R2, #1
    SUB R3, R1, R2
    ST ZT5, R3
    LD R1, ZT5
    ST ZA1, R1
    LD R4, ZV1
    PUSH R4
    LD R4, ZT1
    PUSH R4
    LD R4, ZT2
    PUSH R4
    LD R4, ZT3
    PUSH R4
    LD R4, ZT4
    PUSH R4
    LD R4, ZT5
    PUSH R4
    LD R4, ZT6
    PUSH R4
    LD R4, ZT7
    PUSH R4
    CALL ZF1
    POP R4
    ST ZT7, R4
    POP R4
    ST ZT6, R4
    POP R4
    ST ZT5, R4
    POP R4
    ST ZT4, R4
    POP R4
    ST ZT3, R4
    POP R4
    ST ZT2, R4
    POP R4
    ST ZT1, R4
    POP R4
    ST ZV1, R4
    ST ZT6, R0
    LD R1, ZT3
    LD R2, ZT6
    MUL R3, R1, R2
    ST ZT7, R3
    LD R0, ZT7
    RET
