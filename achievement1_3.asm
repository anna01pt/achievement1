
; ============================================================
; ATmega8 - AVR Assembler - Microchip Studio
; F_CPU = 8 MHz
;
; USART: 9600 baud, 8N1
; Timer2: CTC, interrupt every 1 ms
;
; TIMER1 default interval = 12 ms
; TIMER2 default interval = 16 ms
;
; Commands:
;   HELP
;   T1=120
;   T2=240
;   T1?
;   T2?
;
; Valid intervals:
;   4 ... 65532 ms
;   Multiple of 4 ms
;   TIMER1 + TIMER2 >= 28 ms
; ============================================================

.include "m8def.inc"

; ============================================================
; SRAM
; ============================================================

.dseg

timer1_count:       .byte 2
timer2_count:       .byte 2

timer1_interval:    .byte 2
timer2_interval:    .byte 2

timer1_pending:     .byte 1
timer2_pending:     .byte 1
event_overflow:     .byte 1

rx_buffer:          .byte 28
rx_index:           .byte 1
command_ready:      .byte 1
rx_overflow:        .byte 1

parsed_target:      .byte 1
parsed_value:       .byte 2

; Runtime-editable output strings (20 characters + NUL)
timer1_str_buf:     .byte 21
timer2_str_buf:     .byte 21

; Runtime admission-check workspace
exec_t1_interval:  .byte 2
exec_t2_interval:  .byte 2
exec_t1_length:    .byte 1
exec_t2_length:    .byte 1
exec_rate1:        .byte 2
exec_rate2:        .byte 2
candidate_length:  .byte 1

; ============================================================
; INTERRUPT VECTORS
; ============================================================

.cseg

.org 0x0000
    rjmp RESET

.org 0x0001
    reti                    ; INT0

.org 0x0002
    reti                    ; INT1

.org 0x0003
    rjmp TIMER2_ISR         ; TIMER2 COMP

.org 0x0004
    reti                    ; TIMER2 OVF

.org 0x0005
    reti                    ; TIMER1 CAPT

.org 0x0006
    reti                    ; TIMER1 COMPA

.org 0x0007
    reti                    ; TIMER1 COMPB

.org 0x0008
    reti                    ; TIMER1 OVF

.org 0x0009
    reti                    ; TIMER0 OVF

.org 0x000A
    reti                    ; SPI STC

.org 0x000B
    rjmp USART_RX_ISR       ; USART RX

.org 0x000C
    reti                    ; USART UDRE

.org 0x000D
    reti                    ; USART TX

.org 0x000E
    reti                    ; ADC

.org 0x000F
    reti                    ; EEPROM READY

.org 0x0010
    reti                    ; ANALOG COMP

.org 0x0011
    reti                    ; TWI

.org 0x0012
    reti                    ; SPM READY

; ============================================================
; RESET
; ============================================================

RESET:

    cli

    ; Stack pointer
    ldi r16, high(RAMEND)
    out SPH, r16

    ldi r16, low(RAMEND)
    out SPL, r16

    clr r1

    ; Clear counters
    clr r16

    sts timer1_count, r16
    sts timer1_count+1, r16

    sts timer2_count, r16
    sts timer2_count+1, r16

    ; Initial intervals: 12 ms and 16 ms
    ldi r16, low(12)
    sts timer1_interval, r16

    ldi r16, high(12)
    sts timer1_interval+1, r16

    ldi r16, low(16)
    sts timer2_interval, r16

    ldi r16, high(16)
    sts timer2_interval+1, r16

    ; Clear flags and RX state
    clr r16

    sts timer1_pending, r16
    sts timer2_pending, r16
    sts event_overflow, r16

    sts rx_index, r16
    sts command_ready, r16
    sts rx_overflow, r16

    sts parsed_target, r16
    sts parsed_value, r16
    sts parsed_value+1, r16

    ; Default TIMER1_STR = "ping"
    ldi r16, 'p'
    sts timer1_str_buf, r16
    ldi r16, 'i'
    sts timer1_str_buf+1, r16
    ldi r16, 'n'
    sts timer1_str_buf+2, r16
    ldi r16, 'g'
    sts timer1_str_buf+3, r16
    clr r16
    sts timer1_str_buf+4, r16

    ; Default TIMER2_STR = "pong"
    ldi r16, 'p'
    sts timer2_str_buf, r16
    ldi r16, 'o'
    sts timer2_str_buf+1, r16
    ldi r16, 'n'
    sts timer2_str_buf+2, r16
    ldi r16, 'g'
    sts timer2_str_buf+3, r16
    clr r16
    sts timer2_str_buf+4, r16

    ; Initialize peripherals
    rcall USART_INIT
    rcall TIMER2_INIT

    sei

    ; Startup marker: confirms that this firmware is running
    ldi ZL, low(BOOT_STRING*2)
    ldi ZH, high(BOOT_STRING*2)
    rcall USART_SEND_STRING

; ============================================================
; MAIN LOOP
; ============================================================

MAIN:

    ; Report event queue saturation.
    lds r16, event_overflow
    tst r16
    breq MAIN_CHECK_COMMAND
    clr r16
    sts event_overflow, r16
    ldi ZL, low(EVENT_OVERFLOW_STRING*2)
    ldi ZH, high(EVENT_OVERFLOW_STRING*2)
    rcall USART_SEND_STRING

MAIN_CHECK_COMMAND:
    lds r16, command_ready
    tst r16
    breq MAIN_CHECK_TIMER1
    rcall PROCESS_RECEIVED_COMMAND
    rjmp MAIN

MAIN_CHECK_TIMER1:
    lds r16, timer1_pending
    tst r16
    breq MAIN_CHECK_TIMER2
    cli
    lds r16, timer1_pending
    tst r16
    breq MAIN_T1_EMPTY
    dec r16
    sts timer1_pending, r16
    sei
    ldi ZL, low(timer1_str_buf)
    ldi ZH, high(timer1_str_buf)
    rcall USART_SEND_RAM_STRING
    rjmp MAIN
MAIN_T1_EMPTY:
    sei
    rjmp MAIN_CHECK_TIMER2

MAIN_CHECK_TIMER2:
    lds r16, timer2_pending
    tst r16
    breq MAIN
    cli
    lds r16, timer2_pending
    tst r16
    breq MAIN_T2_EMPTY
    dec r16
    sts timer2_pending, r16
    sei
    ldi ZL, low(timer2_str_buf)
    ldi ZH, high(timer2_str_buf)
    rcall USART_SEND_RAM_STRING
    rjmp MAIN
MAIN_T2_EMPTY:
    sei
    rjmp MAIN

; ============================================================
; USART INITIALIZATION
; ============================================================

USART_INIT:

    ; UBRR = 51, approximately 9615 baud at 8 MHz
    ldi r16, high(51)
    out UBRRH, r16

    ldi r16, low(51)
    out UBRRL, r16

    ; Enable receiver, transmitter and RX interrupt
    ldi r16, (1<<RXEN)|(1<<TXEN)|(1<<RXCIE)
    out UCSRB, r16

    ; Asynchronous, 8 data bits, 1 stop bit, no parity
    ldi r16, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out UCSRC, r16

    ret

; ============================================================
; TIMER2 INITIALIZATION
; ============================================================

TIMER2_INIT:

    clr r16
    out TCCR2, r16
    out TCNT2, r16

    ; 8 MHz / 64 = 125 kHz
    ; 125 counts = 1 ms
    ldi r16, 124
    out OCR2, r16

    ; Clear pending compare flag
    ldi r16, (1<<OCF2)
    out TIFR, r16

    ; Enable Timer2 compare interrupt
    ldi r16, (1<<OCIE2)
    out TIMSK, r16

    ; CTC mode, prescaler 64
    ldi r16, (1<<WGM21)|(1<<CS22)
    out TCCR2, r16

    ret

; ============================================================
; TIMER2 COMPARE ISR - 1 ms
; ============================================================

TIMER2_ISR:

    push r16
    push r17
    push r18

    in r16, SREG
    push r16

    ; TIMER1 counter++
    lds r16, timer1_count
    lds r17, timer1_count+1

    subi r16, 0xFF
    sbci r17, 0xFF

    sts timer1_count, r16
    sts timer1_count+1, r17

    ; Compare TIMER1 counter with interval
    lds r16, timer1_count
    lds r17, timer1_count+1

    lds r18, timer1_interval
    cp r16, r18
    brne TIMER2_CHECK_TIMER2

    lds r18, timer1_interval+1
    cp r17, r18
    brne TIMER2_CHECK_TIMER2

    ; Match: reset counter and enqueue event.
    clr r16
    sts timer1_count, r16
    sts timer1_count+1, r16
    lds r16, timer1_pending
    cpi r16, 255
    breq TIMER1_QUEUE_FULL
    inc r16
    sts timer1_pending, r16
    rjmp TIMER1_QUEUE_DONE
TIMER1_QUEUE_FULL:
    ldi r16, 1
    sts event_overflow, r16
TIMER1_QUEUE_DONE:

TIMER2_CHECK_TIMER2:

    ; TIMER2 counter++
    lds r16, timer2_count
    lds r17, timer2_count+1

    subi r16, 0xFF
    sbci r17, 0xFF

    sts timer2_count, r16
    sts timer2_count+1, r17

    ; Compare TIMER2 counter with interval
    lds r16, timer2_count
    lds r17, timer2_count+1

    lds r18, timer2_interval
    cp r16, r18
    brne TIMER2_ISR_EXIT

    lds r18, timer2_interval+1
    cp r17, r18
    brne TIMER2_ISR_EXIT

    ; Match: reset counter and enqueue event.
    clr r16
    sts timer2_count, r16
    sts timer2_count+1, r16
    lds r16, timer2_pending
    cpi r16, 255
    breq TIMER2_QUEUE_FULL
    inc r16
    sts timer2_pending, r16
    rjmp TIMER2_QUEUE_DONE
TIMER2_QUEUE_FULL:
    ldi r16, 1
    sts event_overflow, r16
TIMER2_QUEUE_DONE:

TIMER2_ISR_EXIT:

    pop r16
    out SREG, r16

    pop r18
    pop r17
    pop r16

    reti

; ============================================================
; USART RX ISR
; CR terminates command
; LF is ignored
; Input case is preserved (string payloads are case-sensitive)
; Maximum command length = 27 characters
; ============================================================

USART_RX_ISR:

    push r16

    in r16, SREG
    push r16

    push r17
    push ZL
    push ZH

    ; Read received character
    in r16, UDR

    ; Ignore input while previous command is being processed
    lds r17, command_ready
    tst r17
    brne USART_RX_EXIT

    ; CR terminates command
    cpi r16, 13
    breq USART_RX_CR

    ; LF is ignored
    cpi r16, 10
    breq USART_RX_EXIT

    ; Check overflow state
    lds r17, rx_overflow
    tst r17
    brne USART_RX_EXIT

    ; Normalize only command prefix (first 6 characters).
    ; The user-defined string payload keeps its original letter case.
    lds r17, rx_index
    cpi r17, 6
    brsh USART_RX_CASE_DONE
    cpi r16, 'a'
    brlo USART_RX_CASE_DONE
    cpi r16, 'z'+1
    brsh USART_RX_CASE_DONE
    subi r16, 32

USART_RX_CASE_DONE:

    ; Maximum data length = 27
    lds r17, rx_index
    cpi r17, 27
    brsh USART_RX_SET_OVERFLOW

    ; Calculate rx_buffer address
    ldi ZL, low(rx_buffer)
    ldi ZH, high(rx_buffer)

    add ZL, r17
    adc ZH, r1

    ; Store character
    st Z, r16

    ; Increment index
    inc r17
    sts rx_index, r17

    rjmp USART_RX_EXIT

USART_RX_SET_OVERFLOW:

    ldi r17, 1
    sts rx_overflow, r17

    rjmp USART_RX_EXIT

; ============================================================
; CR RECEIVED
; ============================================================

USART_RX_CR:

    lds r17, rx_index

    ; Ignore empty command unless overflow occurred
    tst r17
    brne USART_RX_TERMINATE

    lds r16, rx_overflow
    tst r16
    breq USART_RX_EXIT

USART_RX_TERMINATE:

    ; Write zero terminator
    ldi ZL, low(rx_buffer)
    ldi ZH, high(rx_buffer)

    add ZL, r17
    adc ZH, r1

    clr r16
    st Z, r16

    ; Mark command as ready
    ldi r16, 1
    sts command_ready, r16

USART_RX_EXIT:

    pop ZH
    pop ZL
    pop r17

    pop r16
    out SREG, r16

    pop r16

    reti

; ============================================================
; PROCESS RECEIVED COMMAND
; ============================================================


; ============================================================
; PROCESS RECEIVED COMMAND
; ============================================================

PROCESS_RECEIVED_COMMAND:

    ; Check receive overflow
    lds r16, rx_overflow
    tst r16
    breq PC_NO_OVERFLOW
    rjmp COMMAND_OVERFLOW

PC_NO_OVERFLOW:
    ldi ZL, low(rx_buffer)
    ldi ZH, high(rx_buffer)

    ; First character selects HELP, RESET or T1/T2 command
    ld r16, Z+
    cpi r16, 'H'
    breq PC_CHECK_HELP
    cpi r16, 'R'
    breq PC_CHECK_RESET
    cpi r16, 'T'
    breq PC_CHECK_TIMER
    rjmp COMMAND_SYNTAX_ERROR

PC_CHECK_HELP:
    ld r16, Z+
    cpi r16, 'E'
    breq PC_HELP_L
    rjmp COMMAND_SYNTAX_ERROR
PC_HELP_L:
    ld r16, Z+
    cpi r16, 'L'
    breq PC_HELP_P
    rjmp COMMAND_SYNTAX_ERROR
PC_HELP_P:
    ld r16, Z+
    cpi r16, 'P'
    breq PC_HELP_END
    rjmp COMMAND_SYNTAX_ERROR
PC_HELP_END:
    ld r16, Z
    tst r16
    breq PC_HELP_VALID
    rjmp COMMAND_SYNTAX_ERROR
PC_HELP_VALID:
    rjmp COMMAND_HELP

PC_CHECK_RESET:
    ld r16, Z+
    cpi r16, 'E'
    breq PC_RESET_S
    rjmp COMMAND_SYNTAX_ERROR
PC_RESET_S:
    ld r16, Z+
    cpi r16, 'S'
    breq PC_RESET_E
    rjmp COMMAND_SYNTAX_ERROR
PC_RESET_E:
    ld r16, Z+
    cpi r16, 'E'
    breq PC_RESET_T
    rjmp COMMAND_SYNTAX_ERROR
PC_RESET_T:
    ld r16, Z
    cpi r16, 'T'
    breq PC_RESET_END
    rjmp COMMAND_SYNTAX_ERROR
PC_RESET_END:
    adiw ZL, 1
    ld r16, Z
    tst r16
    breq PC_RESET_VALID
    rjmp COMMAND_SYNTAX_ERROR
PC_RESET_VALID:
    rjmp COMMAND_RESET_TIMERS

PC_CHECK_TIMER:
    ld r16, Z+
    cpi r16, '1'
    breq PC_TARGET_1
    cpi r16, '2'
    breq PC_TARGET_2
    rjmp COMMAND_SYNTAX_ERROR

PC_TARGET_1:
    ldi r16, 1
    sts parsed_target, r16
    rjmp COMMAND_CHECK_OPERATOR
PC_TARGET_2:
    ldi r16, 2
    sts parsed_target, r16

COMMAND_CHECK_OPERATOR:
    ld r16, Z+
    cpi r16, '?'
    breq PC_OPERATOR_QUERY
    cpi r16, '='
    breq PC_OPERATOR_SET
    cpi r16, 'S'
    breq PC_OPERATOR_STRING
    rjmp COMMAND_SYNTAX_ERROR

PC_OPERATOR_QUERY:
    rjmp COMMAND_QUERY
PC_OPERATOR_SET:
    rjmp COMMAND_SET

; Expect remaining characters "TR=" after T1S / T2S
PC_OPERATOR_STRING:
    ld r16, Z+
    cpi r16, 'T'
    breq PC_STR_R
    rjmp COMMAND_SYNTAX_ERROR
PC_STR_R:
    ld r16, Z+
    cpi r16, 'R'
    breq PC_STR_EQUAL
    rjmp COMMAND_SYNTAX_ERROR
PC_STR_EQUAL:
    ld r16, Z+
    cpi r16, '='
    breq PC_STRING_PAYLOAD
    rjmp COMMAND_SYNTAX_ERROR
PC_STRING_PAYLOAD:
    rjmp COMMAND_SET_STRING

; ============================================================
; QUERY T1? / T2?
; ============================================================

COMMAND_QUERY:

    ; No characters may follow '?'
    ld r16, Z
    tst r16
    breq COMMAND_QUERY_END_OK
    rjmp COMMAND_SYNTAX_ERROR

COMMAND_QUERY_END_OK:
    lds r16, parsed_target

    cpi r16, 1
    breq COMMAND_QUERY_T1

    rjmp COMMAND_QUERY_T2

COMMAND_QUERY_T1:

    ldi ZL, low(T1_PREFIX*2)
    ldi ZH, high(T1_PREFIX*2)
    rcall USART_SEND_STRING

    lds r20, timer1_interval
    lds r21, timer1_interval+1
    rcall USART_SEND_UINT16

    ldi ZL, low(MS_CRLF_STRING*2)
    ldi ZH, high(MS_CRLF_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

COMMAND_QUERY_T2:

    ldi ZL, low(T2_PREFIX*2)
    ldi ZH, high(T2_PREFIX*2)
    rcall USART_SEND_STRING

    lds r20, timer2_interval
    lds r21, timer2_interval+1
    rcall USART_SEND_UINT16

    ldi ZL, low(MS_CRLF_STRING*2)
    ldi ZH, high(MS_CRLF_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

; ============================================================
; SET COMMAND: T1=120 / T2=240
; Z points to first digit
; ============================================================

COMMAND_SET:

    rcall ASCII_TO_UINT16

    tst r16
    breq COMMAND_NUMBER_OK
    rjmp COMMAND_NUMBER_ERROR

COMMAND_NUMBER_OK:
    ; Save parsed value
    sts parsed_value, r20
    sts parsed_value+1, r21

    rcall VALIDATE_VALUE

    cpi r16, 1
    brne COMMAND_CHECK_STEP_RESULT
    rjmp COMMAND_RANGE_ERROR

COMMAND_CHECK_STEP_RESULT:
    cpi r16, 2
    brne COMMAND_CHECK_SUM_RESULT
    rjmp COMMAND_STEP_ERROR

COMMAND_CHECK_SUM_RESULT:
    cpi r16, 3
    brne COMMAND_VALUE_VALID
    rjmp COMMAND_SUM_ERROR

COMMAND_VALUE_VALID:
    rcall PREPARE_INTERVAL_CANDIDATE
    rcall CHECK_EXECUTION
    tst r16
    breq COMMAND_EXECUTION_OK
    rjmp COMMAND_EXECUTION_ERROR

COMMAND_EXECUTION_OK:
    ; Apply only after the candidate passes admission checking.
    rcall COMMAND_APPLY

    ldi ZL, low(OK_STRING*2)
    ldi ZH, high(OK_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

; ============================================================
; RESET BOTH SOFTWARE TIMERS (intervals are preserved)
; ============================================================

COMMAND_RESET_TIMERS:
    cli
    clr r16
    sts timer1_count, r16
    sts timer1_count+1, r16
    sts timer2_count, r16
    sts timer2_count+1, r16
    sts timer1_pending, r16
    sts timer2_pending, r16
    sts event_overflow, r16
    sei

    ldi ZL, low(RESET_OK_STRING*2)
    ldi ZH, high(RESET_OK_STRING*2)
    rcall USART_SEND_STRING
    rjmp COMMAND_CLEANUP

; ============================================================
; SET TIMER1_STR / TIMER2_STR
; Z points to first payload character
; Empty string is allowed; maximum length is 20 characters
; ============================================================

COMMAND_SET_STRING:
    ; First pass: validate length without changing the current string.
    movw r26, r30           ; X = start of payload
    clr r18                 ; character count

COMMAND_STRING_LENGTH_LOOP:
    ld r16, Z+
    tst r16
    breq COMMAND_STRING_LENGTH_OK
    inc r18
    cpi r18, 21
    brlo COMMAND_STRING_LENGTH_LOOP
    rjmp COMMAND_STRING_TOO_LONG

COMMAND_STRING_LENGTH_OK:
    sts candidate_length, r18
    rcall PREPARE_STRING_CANDIDATE
    rcall CHECK_EXECUTION
    tst r16
    breq COMMAND_STRING_EXECUTION_OK
    rjmp COMMAND_EXECUTION_ERROR

COMMAND_STRING_EXECUTION_OK:
    ; Restore Z to payload start for the copy pass.
    movw r30, r26

    lds r16, parsed_target
    cpi r16, 1
    breq COMMAND_STRING_TIMER1

COMMAND_STRING_TIMER2:
    ldi YL, low(timer2_str_buf)
    ldi YH, high(timer2_str_buf)
    rjmp COMMAND_STRING_COPY

COMMAND_STRING_TIMER1:
    ldi YL, low(timer1_str_buf)
    ldi YH, high(timer1_str_buf)

COMMAND_STRING_COPY:
COMMAND_STRING_COPY_LOOP:
    ld r16, Z+
    tst r16
    breq COMMAND_STRING_COPY_DONE
    st Y+, r16
    rjmp COMMAND_STRING_COPY_LOOP

COMMAND_STRING_COPY_DONE:
    clr r16
    st Y, r16
    ldi ZL, low(STRING_OK_STRING*2)
    ldi ZH, high(STRING_OK_STRING*2)
    rcall USART_SEND_STRING
    rjmp COMMAND_CLEANUP

COMMAND_STRING_TOO_LONG:
    ldi ZL, low(STRING_LENGTH_ERROR_STRING*2)
    ldi ZH, high(STRING_LENGTH_ERROR_STRING*2)
    rcall USART_SEND_STRING
    rjmp COMMAND_CLEANUP

; ============================================================
; EXECUTION ADMISSION ERROR
; ============================================================

COMMAND_EXECUTION_ERROR:
    ldi ZL, low(EXECUTION_ERROR_STRING*2)
    ldi ZH, high(EXECUTION_ERROR_STRING*2)
    rcall USART_SEND_STRING
    rjmp COMMAND_CLEANUP

; ============================================================
; HELP
; ============================================================

COMMAND_HELP:

    ldi ZL, low(HELP_STRING*2)
    ldi ZH, high(HELP_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

; ============================================================
; ERROR OUTPUT
; ============================================================

COMMAND_OVERFLOW:

    ldi ZL, low(OVERFLOW_STRING*2)
    ldi ZH, high(OVERFLOW_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

COMMAND_SYNTAX_ERROR:

    ldi ZL, low(SYNTAX_ERROR_STRING*2)
    ldi ZH, high(SYNTAX_ERROR_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

COMMAND_NUMBER_ERROR:

    ldi ZL, low(NUMBER_ERROR_STRING*2)
    ldi ZH, high(NUMBER_ERROR_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

COMMAND_RANGE_ERROR:

    ldi ZL, low(RANGE_ERROR_STRING*2)
    ldi ZH, high(RANGE_ERROR_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

COMMAND_STEP_ERROR:

    ldi ZL, low(STEP_ERROR_STRING*2)
    ldi ZH, high(STEP_ERROR_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

COMMAND_SUM_ERROR:

    ldi ZL, low(SUM_ERROR_STRING*2)
    ldi ZH, high(SUM_ERROR_STRING*2)
    rcall USART_SEND_STRING

    rjmp COMMAND_CLEANUP

; ============================================================
; COMMAND CLEANUP
; ============================================================

COMMAND_CLEANUP:

    cli

    clr r16

    sts rx_index, r16
    sts rx_overflow, r16
    sts command_ready, r16

    sei

    ret

; ============================================================
; ASCII_TO_UINT16
;
; Input:
;   Z = pointer to first digit
;
; Output:
;   r21:r20 = converted unsigned 16-bit value
;   r16 = 0 success, 1 error
;
; Uses repeated addition to calculate value * 10.
; Detects overflow above 65535.
; ============================================================

ASCII_TO_UINT16:

    clr r20
    clr r21

    ; At least one digit is required
    ld r16, Z
    tst r16
    breq ASCII_INVALID

ASCII_NEXT_DIGIT:

    ld r17, Z+

    ; End of string
    tst r17
    breq ASCII_SUCCESS

    ; Check digit range '0'..'9'
    cpi r17, '0'
    brlo ASCII_INVALID

    cpi r17, '9'+1
    brsh ASCII_INVALID

    subi r17, '0'

    ; Save current value
    mov r18, r20
    mov r19, r21

    ; Calculate current value * 10
    clr r22
    clr r23

    ldi r24, 10

ASCII_MULTIPLY_LOOP:

    add r22, r18
    adc r23, r19
    brcs ASCII_INVALID

    dec r24
    brne ASCII_MULTIPLY_LOOP

    ; Add next digit
    add r22, r17
    adc r23, r1
    brcs ASCII_INVALID

    mov r20, r22
    mov r21, r23

    rjmp ASCII_NEXT_DIGIT

ASCII_SUCCESS:

    clr r16
    ret

ASCII_INVALID:

    ldi r16, 1
    ret

; ============================================================
; VALIDATE_VALUE
;
; Input:
;   parsed_target = 1 or 2
;   parsed_value = candidate interval
;
; Output:
;   r16 = 0 success
;   r16 = 1 range error
;   r16 = 2 step error
;   r16 = 3 sum error
; ============================================================

VALIDATE_VALUE:

    lds r20, parsed_value
    lds r21, parsed_value+1

    ; Minimum = 4
    tst r21
    brne VALIDATE_MAXIMUM

    cpi r20, 4
    brlo VALIDATE_RANGE_ERROR

VALIDATE_MAXIMUM:

    ; Maximum = 65532 = 0xFFFC
    cpi r21, 0xFF
    brlo VALIDATE_STEP

    brne VALIDATE_RANGE_ERROR

    cpi r20, 0xFD
    brsh VALIDATE_RANGE_ERROR

VALIDATE_STEP:

    ; Multiple of 4: low two bits must be zero
    mov r18, r20
    andi r18, 0x03
    brne VALIDATE_STEP_ERROR

    ; Load the other timer interval
    lds r16, parsed_target
    cpi r16, 1
    breq VALIDATE_LOAD_TIMER2

    lds r18, timer1_interval
    lds r19, timer1_interval+1
    rjmp VALIDATE_CHECK_SUM

VALIDATE_LOAD_TIMER2:

    lds r18, timer2_interval
    lds r19, timer2_interval+1

VALIDATE_CHECK_SUM:

    ; Candidate + other interval
    add r20, r18
    adc r21, r19

    ; Carry means sum > 65535, therefore >= 28
    brcs VALIDATE_OK

    ; Otherwise sum must be at least 28
    tst r21
    brne VALIDATE_OK

    cpi r20, 28
    brlo VALIDATE_SUM_ERROR

VALIDATE_OK:

    clr r16
    ret

VALIDATE_RANGE_ERROR:

    ldi r16, 1
    ret

VALIDATE_STEP_ERROR:

    ldi r16, 2
    ret

VALIDATE_SUM_ERROR:

    ldi r16, 3
    ret

; ============================================================
; EXECUTION LOAD CHECK
;
; Calculates ceil((string_length + 2) * 1000 / interval_ms)
; for each timer. Sum must not exceed 912 bytes/second.
; USART 9600 8N1 has nominal capacity 960 bytes/second.
; 912 reserves 5 percent headroom.
; ============================================================

PREPARE_INTERVAL_CANDIDATE:
    lds r16, parsed_target
    cpi r16, 1
    breq PIC_T1
    lds r18, timer1_interval
    lds r19, timer1_interval+1
    sts exec_t1_interval, r18
    sts exec_t1_interval+1, r19
    lds r18, parsed_value
    lds r19, parsed_value+1
    sts exec_t2_interval, r18
    sts exec_t2_interval+1, r19
    rjmp PIC_LENGTHS
PIC_T1:
    lds r18, parsed_value
    lds r19, parsed_value+1
    sts exec_t1_interval, r18
    sts exec_t1_interval+1, r19
    lds r18, timer2_interval
    lds r19, timer2_interval+1
    sts exec_t2_interval, r18
    sts exec_t2_interval+1, r19
PIC_LENGTHS:
    ldi ZL, low(timer1_str_buf)
    ldi ZH, high(timer1_str_buf)
    rcall GET_RAM_STRING_LENGTH
    sts exec_t1_length, r16
    ldi ZL, low(timer2_str_buf)
    ldi ZH, high(timer2_str_buf)
    rcall GET_RAM_STRING_LENGTH
    sts exec_t2_length, r16
    ret

PREPARE_STRING_CANDIDATE:
    lds r18, timer1_interval
    lds r19, timer1_interval+1
    sts exec_t1_interval, r18
    sts exec_t1_interval+1, r19
    lds r18, timer2_interval
    lds r19, timer2_interval+1
    sts exec_t2_interval, r18
    sts exec_t2_interval+1, r19
    ldi ZL, low(timer1_str_buf)
    ldi ZH, high(timer1_str_buf)
    rcall GET_RAM_STRING_LENGTH
    sts exec_t1_length, r16
    ldi ZL, low(timer2_str_buf)
    ldi ZH, high(timer2_str_buf)
    rcall GET_RAM_STRING_LENGTH
    sts exec_t2_length, r16
    lds r16, parsed_target
    cpi r16, 1
    breq PSC_T1
    lds r16, candidate_length
    sts exec_t2_length, r16
    ret
PSC_T1:
    lds r16, candidate_length
    sts exec_t1_length, r16
    ret

GET_RAM_STRING_LENGTH:
    clr r16
GRSL_LOOP:
    ld r17, Z+
    tst r17
    breq GRSL_DONE
    inc r16
    rjmp GRSL_LOOP
GRSL_DONE:
    ret

CHECK_EXECUTION:
    lds r16, exec_t1_length
    subi r16, 0xFE
    rcall BUILD_RATE_NUMERATOR
    lds r22, exec_t1_interval
    lds r23, exec_t1_interval+1
    rcall CALC_RATE_CEIL
    sts exec_rate1, r24
    sts exec_rate1+1, r25

    lds r16, exec_t2_length
    subi r16, 0xFE
    rcall BUILD_RATE_NUMERATOR
    lds r22, exec_t2_interval
    lds r23, exec_t2_interval+1
    rcall CALC_RATE_CEIL
    sts exec_rate2, r24
    sts exec_rate2+1, r25

    lds r24, exec_rate1
    lds r25, exec_rate1+1
    lds r18, exec_rate2
    lds r19, exec_rate2+1
    add r24, r18
    adc r25, r19
    cpi r25, high(912)
    brlo CE_OK
    brne CE_FAIL
    cpi r24, low(912)
    brlo CE_OK
    breq CE_OK
CE_FAIL:
    ldi r16, 1
    ret
CE_OK:
    clr r16
    ret

BUILD_RATE_NUMERATOR:
    ; r16 = message byte count, result = r20:r21 = count * 1000.
    clr r20
    clr r21
    mov r17, r16
    ldi r18, low(1000)
BRN_LOOP:
    add r20, r18
    ldi r18, high(1000)
    adc r21, r18
    ldi r18, low(1000)
    dec r17
    brne BRN_LOOP
    ret

CALC_RATE_CEIL:
    ; r20:r21 numerator, r22:r23 divisor; result r25:r24.
    mov r16, r20
    mov r17, r21
    mov r18, r22
    mov r19, r23
    clr r24
    clr r25
CRC_LOOP:
    cp r16, r18
    cpc r17, r19
    brlo CRC_REMAINDER
    sub r16, r18
    sbc r17, r19
    subi r24, 0xFF
    sbci r25, 0xFF
    rjmp CRC_LOOP
CRC_REMAINDER:
    tst r16
    brne CRC_ROUND
    tst r17
    breq CRC_DONE
CRC_ROUND:
    subi r24, 0xFF
    sbci r25, 0xFF
CRC_DONE:
    ret

; ============================================================
; COMMAND_APPLY
;
; Applies parsed_value to selected timer immediately.
; Resets corresponding counter.
; ============================================================

COMMAND_APPLY:

    cli

    lds r16, parsed_target
    cpi r16, 1
    breq APPLY_TIMER1

APPLY_TIMER2:

    lds r20, parsed_value
    lds r21, parsed_value+1

    sts timer2_interval, r20
    sts timer2_interval+1, r21

    clr r16
    sts timer2_count, r16
    sts timer2_count+1, r16

    sei
    ret

APPLY_TIMER1:

    lds r20, parsed_value
    lds r21, parsed_value+1

    sts timer1_interval, r20
    sts timer1_interval+1, r21

    clr r16
    sts timer1_count, r16
    sts timer1_count+1, r16

    sei
    ret

; ============================================================
; USART_SEND_STRING
;
; Input:
;   Z = flash string address
; String ends with zero byte
; ============================================================

USART_SEND_STRING:

USART_SEND_NEXT:

    lpm r16, Z+

    tst r16
    breq USART_SEND_DONE

    rcall USART_SEND_CHAR
    rjmp USART_SEND_NEXT

USART_SEND_DONE:

    ret

; ============================================================
; USART_SEND_RAM_STRING
; Input: Z points to zero-terminated SRAM string
; ============================================================

USART_SEND_RAM_STRING:
USART_SEND_RAM_NEXT:
    ld r16, Z+
    tst r16
    breq USART_SEND_RAM_DONE
    rcall USART_SEND_CHAR
    rjmp USART_SEND_RAM_NEXT
USART_SEND_RAM_DONE:
    ; Append CR/LF to each timer message
    ldi r16, 13
    rcall USART_SEND_CHAR
    ldi r16, 10
    rcall USART_SEND_CHAR
    ret

; ============================================================
; USART_SEND_CHAR
;
; Input:
;   r16 = character
; ============================================================

USART_SEND_CHAR:

USART_WAIT_UDRE:

    sbis UCSRA, UDRE
    rjmp USART_WAIT_UDRE

    out UDR, r16

    ret

; ============================================================
; USART_SEND_UINT16
;
; Input:
;   r21:r20 = unsigned 16-bit number
;
; Prints decimal number without leading zeroes.
; ============================================================

USART_SEND_UINT16:

    ; Preserve value in r23:r22
    mov r22, r20
    mov r23, r21

    clr r19                 ; leading-zero suppression state

    ; Point to decimal divisors
    ldi ZL, low(DECIMAL_TABLE*2)
    ldi ZH, high(DECIMAL_TABLE*2)

    ldi r25, 5              ; five decimal positions

USART_DECIMAL_POSITION:

    ; Load divisor
    lpm r16, Z+
    lpm r17, Z+

    clr r18                 ; digit counter

USART_DECIMAL_SUBTRACT:

    cp r22, r16
    cpc r23, r17
    brlo USART_DECIMAL_DIGIT_READY

    sub r22, r16
    sbc r23, r17

    inc r18
    rjmp USART_DECIMAL_SUBTRACT

USART_DECIMAL_DIGIT_READY:

    ; Print if nonzero or if a previous digit was printed
    tst r18
    brne USART_DECIMAL_PRINT

    tst r19
    brne USART_DECIMAL_PRINT

    ; Always print units position
    cpi r25, 1
    breq USART_DECIMAL_PRINT

    rjmp USART_DECIMAL_NEXT

USART_DECIMAL_PRINT:

    ldi r19, 1

    ldi r16, '0'
    add r16, r18
    rcall USART_SEND_CHAR

USART_DECIMAL_NEXT:

    dec r25
    brne USART_DECIMAL_POSITION

    ret

; ============================================================
; FLASH STRINGS
; ============================================================

BOOT_STRING:
    .db "FIRMWARE VERSION 6", 13, 10, 0

HELP_STRING:
    .db "HELP RESET T1= T2= T1? T2? T1STR= T2STR=", 13, 10, 0

T1_PREFIX:
    .db "T1=", 0

T2_PREFIX:
    .db "T2=", 0

MS_CRLF_STRING:
    .db " ms", 13, 10, 0

OK_STRING:
    .db "OK: INTERVAL APPLIED", 13, 10, 0

SYNTAX_ERROR_STRING:
    .db "ERROR: SYNTAX", 13, 10, 0

NUMBER_ERROR_STRING:
    .db "ERROR: INVALID NUMBER", 13, 10, 0

RANGE_ERROR_STRING:
    .db "ERROR: RANGE 4..65532", 13, 10, 0

STEP_ERROR_STRING:
    .db "ERROR: INTERVAL MUST BE MULTIPLE OF 4", 13, 10, 0

SUM_ERROR_STRING:
    .db "ERROR: TIMER1 + TIMER2 MUST BE >= 28", 13, 10, 0

OVERFLOW_STRING:
    .db "ERROR: RX BUFFER OVERFLOW", 13, 10, 0

RESET_OK_STRING:
    .db "OK: TIMERS RESTARTED", 13, 10, 0

STRING_OK_STRING:
    .db "OK: TIMER STRING CHANGED", 13, 10, 0

STRING_LENGTH_ERROR_STRING:
    .db "ERROR: STRING MAX 20 CHARS", 13, 10, 0

EVENT_OVERFLOW_STRING:
    .db "ERROR: EVENT QUEUE OVERFLOW", 13, 10, 0

EXECUTION_ERROR_STRING:
    .db "ERROR: EXECUTION IMPOSSIBLE", 13, 10, 0

; Decimal divisors: 10000, 1000, 100, 10, 1
DECIMAL_TABLE:
    .db low(10000), high(10000)
    .db low(1000),  high(1000)
    .db low(100),   high(100)
    .db low(10),    high(10)
    .db low(1),     high(1)
