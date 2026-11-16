
; =====================================================
; ATmega8
; AVR Assembler (Microchip Studio)
;
; F_CPU = 16 MHz
; USART  = 9600 baud, 8N1
;
; TIMER1_INTERVAL = 1000 ms
; TIMER2_INTERVAL = 2000 ms
;
; Timer2 generates interrupt every 1 ms.
; Two independent software timers are implemented.
; =====================================================

.include "m8def.inc"

; -----------------------------------------------------
; CONSTANTS
; -----------------------------------------------------

.equ TIMER1_INTERVAL = 1000
.equ TIMER2_INTERVAL = 2000

; Timer2:
; 16 MHz / 64 = 250 kHz
; 250 ticks = 1 ms
; OCR2 = 249

.equ TIMER2_OCR = 124

; USART 9600 baud at 16 MHz
.equ UBRR_VALUE = 51

; -----------------------------------------------------
; SRAM
; -----------------------------------------------------

.dseg

timer1_count: .byte 2
timer2_count: .byte 2

timer1_flag:  .byte 1
timer2_flag:  .byte 1

; -----------------------------------------------------
; INTERRUPT VECTOR TABLE
; -----------------------------------------------------

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
    reti                    ; SPI

.org 0x000B
    reti                    ; USART RX

.org 0x000C
    reti                    ; USART UDRE

.org 0x000D
    reti                    ; USART TX

.org 0x000E
    reti                    ; ADC

.org 0x000F
    reti                    ; EEPROM

.org 0x0010
    reti                    ; ANALOG COMP

.org 0x0011
    reti                    ; TWI

.org 0x0012
    reti                    ; SPM READY

; -----------------------------------------------------
; STRINGS IN FLASH
; -----------------------------------------------------

TIMER1_STR:
    .db "ping", 13, 10, 0

TIMER2_STR:
    .db "pong", 13, 10, 0

; -----------------------------------------------------
; RESET
; -----------------------------------------------------

RESET:

    ; Initialize stack

    ldi r16, high(RAMEND)
    out SPH, r16

    ldi r16, low(RAMEND)
    out SPL, r16

    ; Clear variables

    clr r16

    sts timer1_count, r16
    sts timer1_count+1, r16

    sts timer2_count, r16
    sts timer2_count+1, r16

    sts timer1_flag, r16
    sts timer2_flag, r16

    ; -------------------------------------------------
    ; USART INITIALIZATION
    ; -------------------------------------------------

    ; Baud rate = 9600

    ldi r16, high(UBRR_VALUE)
    out UBRRH, r16

    ldi r16, low(UBRR_VALUE)
    out UBRRL, r16

    ; Enable transmitter

    ldi r16, (1<<TXEN)
    out UCSRB, r16

    ; 8 data bits, no parity, 1 stop bit

    ldi r16, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out UCSRC, r16

    ; -------------------------------------------------
    ; TIMER2 INITIALIZATION
    ; -------------------------------------------------

    ; Stop Timer2 during configuration

    clr r16
    out TCCR2, r16

    ; Reset counter

    out TCNT2, r16

    ; CTC mode, OCR2 = 249

    ldi r16, TIMER2_OCR
    out OCR2, r16

    ; Clear pending Compare Match flag

    ldi r16, (1<<OCF2)
    out TIFR, r16

    ; Enable Timer2 Compare Match interrupt

    ldi r16, (1<<OCIE2)
    out TIMSK, r16

    ; CTC mode, prescaler = 64
    ; WGM21 = 1, CS22 = 1

    ldi r16, (1<<WGM21)|(1<<CS22)
    out TCCR2, r16

    ; Enable global interrupts

    sei

; -----------------------------------------------------
; MAIN LOOP
; -----------------------------------------------------

MAIN:

    ; ================================================
    ; CHECK TIMER1 FLAG
    ; ================================================

    cli

    lds r16, timer1_flag

    clr r17
    sts timer1_flag, r17

    sei

    tst r16
    breq CHECK_TIMER2

    ; Send "ping\r\n"

    ldi ZL, low(TIMER1_STR*2)
    ldi ZH, high(TIMER1_STR*2)

    rcall USART_SEND_STRING

CHECK_TIMER2:

    ; ================================================
    ; CHECK TIMER2 FLAG
    ; ================================================

    cli

    lds r16, timer2_flag

    clr r17
    sts timer2_flag, r17

    sei

    tst r16
    breq MAIN

    ; Send "pong\r\n"

    ldi ZL, low(TIMER2_STR*2)
    ldi ZH, high(TIMER2_STR*2)

    rcall USART_SEND_STRING

    rjmp MAIN

; -----------------------------------------------------
; TIMER2 COMPARE MATCH ISR
; Interrupt period = 1 ms
; -----------------------------------------------------

TIMER2_ISR:

    ; Save registers

    push r16
    in r16, SREG
    push r16

    push r17
    push r18

    ; ================================================
    ; SOFTWARE TIMER 1
    ; ================================================

    ; Increment 16-bit counter

    lds r16, timer1_count

    inc r16

    sts timer1_count, r16

    brne TIMER1_CHECK

    lds r17, timer1_count+1

    inc r17

    sts timer1_count+1, r17

TIMER1_CHECK:

    ; Compare counter with TIMER1_INTERVAL

    lds r16, timer1_count
    lds r17, timer1_count+1

    ldi r18, low(TIMER1_INTERVAL)
    cp r16, r18

    ldi r18, high(TIMER1_INTERVAL)
    cpc r17, r18

    brne TIMER2_PROCESS

    ; Reset counter

    clr r16

    sts timer1_count, r16
    sts timer1_count+1, r16

    ; Set event flag

    ldi r16, 1
    sts timer1_flag, r16

    ; ================================================
    ; SOFTWARE TIMER 2
    ; ================================================

TIMER2_PROCESS:

    ; Increment 16-bit counter

    lds r16, timer2_count

    inc r16

    sts timer2_count, r16

    brne TIMER2_CHECK

    lds r17, timer2_count+1

    inc r17

    sts timer2_count+1, r17

TIMER2_CHECK:

    ; Compare counter with TIMER2_INTERVAL

    lds r16, timer2_count
    lds r17, timer2_count+1

    ldi r18, low(TIMER2_INTERVAL)
    cp r16, r18

    ldi r18, high(TIMER2_INTERVAL)
    cpc r17, r18

    brne TIMER_ISR_EXIT

    ; Reset counter

    clr r16

    sts timer2_count, r16
    sts timer2_count+1, r16

    ; Set event flag

    ldi r16, 1
    sts timer2_flag, r16

TIMER_ISR_EXIT:

    ; Restore registers

    pop r18
    pop r17

    pop r16
    out SREG, r16

    pop r16

    reti

; -----------------------------------------------------
; USART SEND STRING
;
; Input:
;   Z = address of string in FLASH
;
; String must end with zero.
; -----------------------------------------------------

USART_SEND_STRING:

    ; Read byte from FLASH

    lpm r16, Z+

    ; Check end of string

    tst r16
    breq USART_SEND_END

USART_WAIT:

    ; Wait until USART data register is empty

    sbis UCSRA, UDRE
    rjmp USART_WAIT

    ; Send character

    out UDR, r16

    rjmp USART_SEND_STRING

USART_SEND_END:

    ret
