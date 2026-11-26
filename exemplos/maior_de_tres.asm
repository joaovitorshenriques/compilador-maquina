    LD R4, #0
    ST RESULTADO, R4
    ST ZV1, R4
    ST ZV2, R4
    ST ZV3, R4
    ST ZT1, R4
    ST ZT2, R4
    ST ZT3, R4
    ST ZT4, R4
    ST ZT5, R4
    ST ZT6, R4
    ST ZT7, R4
    ST ZT8, R4
    ST ZT9, R4
    ST ZT10, R4
    ST ZT11, R4
    ST ZT12, R4
    ST ZT13, R4
ZF1:
    LD R4, #0
    ST ZV1, R4
    LD R4, #0
    ST ZV2, R4
    LD R4, #0
    ST ZV3, R4
    LD R1, #7
    ST ZV1, R1
    LD R1, #12
    ST ZV2, R1
    LD R1, #5
    ST ZV3, R1
    LD R1, ZV1
    ST ZT1, R1
    LD R1, ZV2
    ST ZT2, R1
    LD R1, ZT1
    LD R2, ZT2
    SLT R3, R1, R2
    LD R2, #0
    SEQ R3, R3, R2
    ST ZT3, R3
    LD R1, #0
    ST ZT4, R1
    LD R1, ZT3
    BEQZ R1, ZL1
    LD R1, ZV1
    ST ZT5, R1
    LD R1, ZV3
    ST ZT6, R1
    LD R1, ZT5
    LD R2, ZT6
    SLT R3, R1, R2
    LD R2, #0
    SEQ R3, R3, R2
    ST ZT7, R3
    LD R1, ZT7
    ST ZT4, R1
ZL1:
    LD R1, ZT4
    BEQZ R1, ZL2
    LD R1, ZV1
    ST ZT8, R1
    LD R1, ZT8
    ST RESULTADO, R1
    BR ZL3
ZL2:
    LD R1, ZV2
    ST ZT9, R1
    LD R1, ZV3
    ST ZT10, R1
    LD R1, ZT9
    LD R2, ZT10
    SLT R3, R1, R2
    LD R2, #0
    SEQ R3, R3, R2
    ST ZT11, R3
    LD R1, ZT11
    BEQZ R1, ZL4
    LD R1, ZV2
    ST ZT12, R1
    LD R1, ZT12
    ST RESULTADO, R1
    BR ZL5
ZL4:
    LD R1, ZV3
    ST ZT13, R1
    LD R1, ZT13
    ST RESULTADO, R1
ZL5:
ZL3:
    LD R0, #0
    HALT
