        PUBLIC  __iar_program_start
        EXTERN __vector_table
        
        EXTERN GPIO_enable
        EXTERN GPIO_special
        EXTERN GPIO_select
        EXTERN UART_enable
        EXTERN UART_config

        SECTION .text:CODE:REORDER(2)
        
        ;; Keep vector table even if it's not referenced
        REQUIRE __vector_table
        
        THUMB
       
const_10                 EQU     10

; System Control bit definitions
PORTA_BIT               EQU     1b ; bit  0 = Port A
UART0_BIT               EQU     1b ; bit  0 = UART 0

; GPIO Port definitions
GPIO_PORTA_BASE         EQU     0x40058000

; UART definitions
UART_FR                 EQU     0x0018
UART_PORT0_BASE         EQU     0x4000C000

;UART bit definitions
TXFE_BIT                EQU     10000000b ; TX FIFO full
RXFF_BIT                EQU     01000000b ; RX FIFO empty
        
__iar_program_start
        
main    
        MOV R2, #(UART0_BIT)
	BL UART_enable ; habilita clock ao port 0 de UART

        MOV R2, #(PORTA_BIT)
	BL GPIO_enable ; habilita clock ao port A de GPIO

        LDR R0, =GPIO_PORTA_BASE
        MOV R1, #11b ; bits 0 e 1 como especiais
        BL GPIO_special
        
        MOV R1, #0xFF ; máscara das funções especiais no port A (bits 1 e 0)
        MOV R2, #0x11  ; funções especiais RX e TX no port A (UART)
        BL GPIO_select
        
        LDR R0, =UART_PORT0_BASE
        BL UART_config ; configura periférico UART0

        MOV R3, #0 
        MOV R5, #10
        
        ; recepção e envio de dados pela UART utilizando sondagem (polling)
        ; resulta em um "eco": dados recebidos são retransmitidos pela UART

loop
UART_read
        LDR R2, [R0, #UART_FR] ; status da UART
        TST R2, #RXFF_BIT ; receptor cheio?
        BEQ UART_read
        
        LDRB R1, [R0] ; lê do registrador de dados da UART0 (recebe)

        CMP R1, #'='
        ITTT EQ
         BLEQ calculate
         BLEQ show_result
         BEQ loop

        BL check_number
        BL check_operator
        
        MOV R2, #1000b
        BL read_register
        
        TEQ R2, #1000b
        IT EQ
         BLEQ print
        
        B loop

; SUB-ROTINAS

; Modifica registrador R3 com mascaramento
; R2 é a máscara 
; Faz determinados bits irem a 0
clear_register
        BIC R3, R3, R2
        BX LR
     
; Modifica registrador R3 com mascaramento
; R2 é a máscara 
; Faz determinados bits irem a 1    
set_register
        ORR R3, R3, R2
        BX LR
        
; Lê parte do registrador R3
; R2 é a máscara e guarda o valor
read_register
        AND R2, R3, R2
        BX LR
    
; Modifica os operandos guardados em R3
; Caracter guardado no registrador R1  
; Modifica: R2, R3 e R6 
store_operand
        PUSH {R4, LR}
        
        ; primeiro operando está sendo digitado? (bit 14 de R3)
        MOV R2, #100000000000000b
        BL read_register
        
        TEQ R2, #100000000000000b
        ITE EQ
         MOVEQ R4, #16 ; deslocamento do segundo operando
         MOVNE R4, #4 ; deslocamento do primeiro operando

        MOV R2, #1111111111b
        LSL R2, R2, R4
 
        BL read_register ; lê operando guardado em R3
        BIC R3, R2
        LSR R2, R2, R4
        MUL R2, R2, R5
        SUB R6, R1, #0x30 ; de ASCII para algarismo
        ADD R2, R2, R6
        LSL R2, R2, R4
        BL set_register ; guarda novo operando
        
        POP {R4, LR}
        BX LR

; Modifica o código do operador guardado em R3
; Desloca o registrador R4 para guardar código do operador em R3
; Modifica: R2
store_operator
        PUSH {LR}

        LSL R2, R2, #27
        BL set_register
        
        POP {LR}
        BX LR

; Realiza a operação entre os dois operandos guardados em R3
; Lê o código do operador guardado em R3
; Resultado da operação guardado em R4
; Faz o bit 30 de R3 ir a 1 finalizando operação
; Modifica: R2 e R3
calculate
        PUSH {R0, R1, LR}
        
        MOV R2, #1111111111b
        LSL R2, R2, #4
        BL read_register
        LSR R2, R2, #4
        MOV R0, R2 ; primeiro operando

        MOV R2, #1111111111b
        LSL R2, R2, #16
        BL read_register
        LSR R2, R2, #16
        MOV R1, R2 ; segundo operando
        
        MOV R2, #111
        LSL R2, R2, #27
        BL read_register ; leitura do código do operador
        LSR R2, R2, #27
        
        CMP R2, #1
        ITT EQ
         ADDEQ R4, R0, R1 ; soma
         BEQ calculate_end
         
        CMP R2, #2
        ITT EQ
         SUBEQ R4, R0, R1 ; subtração
         BEQ calculate_end
         
        CMP R2, #3
        ITT EQ
         MULEQ R4, R0, R1 ; multiplicação
         BEQ calculate_end
         
        ; checa divisão por 0
        CMP R1, #0
        ITTTT EQ
         MOVEQ R2, #1b
         LSLEQ R2, R2, #15
         BLEQ set_register ; flag que indica divisão por 0 é ativada
         BEQ calculate_end
            
        UDIV R4, R0, R1 ; divisão
        
calculate_end
        MOV R2, #1b
        LSL R2, R2, #14
        BL set_register ; operação finalizada

        POP {R0, R1, LR}
        BX LR
        
; Faz bit 3 de R3 ir a 1 permitindo a escrita do caracter digitado pelo usuário
; Bits 2, 1 e 0 de R3 são zerados, reinicializando a conta até 3
; Alterna o estado do bit 14 alternando o operando 
; Modifica: R2 e R3
reinitialize_sum
        PUSH {LR}
        
        MOV R2, #1000b
        BL set_register
        
        MOV R2, #111b
        BL clear_register
        
        MOV R2, #100000000000000b ; bit 14
        BL read_register
         
        EOR R3, R3, #100000000000000b ; alterna estado do bit 14
        
        POP {LR}
        BX LR

; Atualiza os bits 2, 1 e 0 de R3 para representar número de dígitos pressionados pelo usuário
; Máximo valor de dígitos: 4
; Modifica: R2 e R3
sum_register
        PUSH {LR}

        MOV R2, #111b ; máscara para leitura de bits 2, 1 e 0
        BL read_register
        
        CMP R2, #4
        BEQ sum_end
        
        CMP R2, #3
        IT LT
         BLLT store_operand
         
        MOV R2, #111b ; máscara para leitura de bits 2, 1 e 0
        BL read_register
        ADD R2, R2, #1
        
        BIC R3, R3, #111b
        BL set_register
        
        POP {LR}
        BX LR
sum_end
        POP {LR}
        BX LR

; Checa se o caracter digitado pelo usuário é um algarismo
; Faz bit 3 de R3 ir a 0 caso falso e a 1 caso verdadeiro
; Modifica os operandos armazendados nos bits de R3 caso caracter for um algarismo
; Modifica: R2 e R3
check_number
        PUSH {LR}

        MOV R2, #1000b
        BL clear_register

        CMP R1, #'0' 
        BLT check_number_finished
        
        CMP R1, #'9'
        BGT check_number_finished
        
        MOV R2, #1000b
        BL set_register
        BL sum_register
        
check_number_finished
        POP {LR}
        
        BX LR

; Checa se o caracter digitado pelo usuário é um operador
; Faz bit 2 de R3 ir a 0 caso falso e a 1 caso verdadeiro
; Modifica: R2 e R3
check_operator
        PUSH {LR}
        
        CMP R1, #'+'
        ITTT EQ
         BLEQ reinitialize_sum
         MOVEQ R2, #1
         BLEQ store_operator
        
        CMP R1, #'-'
        ITTT EQ
         BLEQ reinitialize_sum
         MOVEQ R2, #2
         BLEQ store_operator
        
        CMP R1, #'*'
        ITTT EQ
         BLEQ reinitialize_sum
         MOVEQ R2, #3
         BLEQ store_operator
        
        CMP R1, #'/'
        ITTT EQ
         BLEQ reinitialize_sum
         MOVEQ R2, #4
         BLEQ store_operator
        
        POP {LR}
        
        BX LR

; Mostra erro na divisão por 0
show_div_error
        PUSH {LR}

        BL UART_can_write
        MOV R2, #'e'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)

        BL UART_can_write
        MOV R2, #'r'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)

        BL UART_can_write
        MOV R2, #'r'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)

        BL UART_can_write
        MOV R2, #'o'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)

        BL UART_can_write
        MOV R2, #'r'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)
        
        POP {LR}
        BX LR
        
; Mostra o resultado da operação para o usuário
; Máximo resultado = 999 * 999 = 998001 (20 bits)
; Resultado se encontra no registrador R4
show_result
        PUSH {R1, R5, LR}

        MOV R2, #1b
        LSL R2, R2, #14
        BL read_register 
        LSR R2, R2, #14
        
        CMP R2, #1
        BNE show_end
        
        BL reinitialize_sum
        
        BL UART_can_write
        MOV R2, #'='
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)
        
        ; verifica divisão por 0
        MOV R2, #1b
        LSL R2, R2, #15
        BL read_register
        CMP R2, #1000000000000000b
        ITT EQ
         BLEQ show_div_error
         BEQ result_showed
         
        BL UART_can_write
        MOV R2, #'0'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)
        BL UART_can_write
        MOV R2, #'x'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)
        
        MOV R2, #11110000000000000000b ; máscara para leitura de 1 byte do resultado
        MOV R5, #16 ; deslocamento para a direita

transmitting_result
        CBZ R2, result_showed 
        PUSH {R2}
        BL UART_can_write
        POP {R2}
        AND R1, R2, R4
        LSR R1, R1, R5
        CMP R1, #9
        ITE LS
         ADDLS R1, R1, #48
         ADDHI R1, R1, #87
         
        STRB R1, [R0] ; escreve no registrador de dados da UART0 (transmite)
        LSR R2, R2, #4 
        SUB R5, R5, #4
        B transmitting_result
        
result_showed
        BL UART_can_write
        MOV R2, #'\r'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)
        BL UART_can_write
        MOV R2, #'\n'
        STRB R2, [R0] ; escreve no registrador de dados da UART0 (transmite)

        ; limpa o registrador R3 para novos cálculos
        MOV R3, #0
     
show_end
        POP {R1, R5, LR}
        BX LR
        
; Aguarda até que o transmissor da UART esteja vazio       
UART_can_write
        LDR R2, [R0, #UART_FR] ; status da UART
        TST R2, #TXFE_BIT ; transmissor vazio?
        BEQ UART_can_write
        
        BX LR

; Confere status da UART e transmite dados para o receptor
; Modifica: R2 
;----------
print
        PUSH {LR}

        BL UART_can_write
        
        MOV R2, #111b
        BL read_register
        
        CMP R2, #4
        IT LO ; número não deve ultrapassar 3 algarismos
         STRBLO R1, [R0] ; escreve no registrador de dados da UART0 (transmite)

        POP {LR}
        BX LR
        
        
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
        ;; Forward declaration of sections.
        SECTION CSTACK:DATA:NOROOT(3)
        SECTION .intvec:CODE:NOROOT(2)
        
        DATA

        END
__vector_table
        DCD     sfe(CSTACK)
        DCD     __iar_program_start

        DCD     NMI_Handler
        DCD     HardFault_Handler
        DCD     MemManage_Handler
        DCD     BusFault_Handler
        DCD     UsageFault_Handler
        DCD     0
        DCD     0
        DCD     0
        DCD     0
        DCD     SVC_Handler
        DCD     DebugMon_Handler
        DCD     0
        DCD     PendSV_Handler
        DCD     SysTick_Handler

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Default interrupt handlers.
;;

        PUBWEAK NMI_Handler
        PUBWEAK HardFault_Handler
        PUBWEAK MemManage_Handler
        PUBWEAK BusFault_Handler
        PUBWEAK UsageFault_Handler
        PUBWEAK SVC_Handler
        PUBWEAK DebugMon_Handler
        PUBWEAK PendSV_Handler
        PUBWEAK SysTick_Handler

        SECTION .text:CODE:REORDER:NOROOT(1)
        THUMB

NMI_Handler
HardFault_Handler
MemManage_Handler
BusFault_Handler
UsageFault_Handler
SVC_Handler
DebugMon_Handler
PendSV_Handler
SysTick_Handler
Default_Handler
__default_handler
        CALL_GRAPH_ROOT __default_handler, "interrupt"
        NOCALL __default_handler
        B __default_handler

        END
