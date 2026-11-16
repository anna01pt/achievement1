
; =====================================================
; ATmega8
; AVR Assembler - Microchip Studio
;
; F_CPU = 8 MHz
; USART = 9600 baud, 8N1
;
; TIMER1_INTERVAL = 100128 CPU clocks
; TIMER2_INTERVAL = 100128 CPU clocks
;
; Timer1 prescaler = 1
; Timer1 resolution = 1 CPU clock
; Intervals are multiples of 4 clocks.
;
; Output:
; ping
; pong
; =====================================================

.include "m8def.inc"

; -----------------------------------------------------
; CONSTANTS
; -----------------------------------------------------

.equ TIMER1_INTERVAL = 100128
.equ TIMER2_INTERVAL = 100128

.equ UBRR_VALUE = 51

; 100128 = 1 * 65536 + 0x8720
.equ INTERVAL_LOW = 0x8720

; -----------------------------------------------------
; SRAM
; -----------------------------------------------------

.dseg

epoch_lo:       .byte 1
epoch_hi:       .byte 1

target1_hi:     .byte 2
target2_hi:     .byte 2

pending_ping:   .byte 1
pending_pong:   .byte 1

; -----------------------------------------------------
; INTERRUPT VECTOR TABLE
; -----------------------------------------------------

.cseg

.org 0x0000
    rjmp RESET

.org 0x0001
    reti

.org 0x0002
    reti

.org 0x0003
    reti

.org 0x0004
    reti

.org 0x0005
    reti

.org 0x0006
    rjmp TIMER1_COMPA_ISR

.org 0x0007
    rjmp TIMER1_COMPB_ISR

.org 0x0008
    rjmp TIMER1_OVF_ISR

.org 0x0009
    reti

.org 0x000A
    reti

.org 0x000B
    reti

.org 0x000C
    reti

.org 0x000D
    reti

.org 0x000E
    reti

.org 0x000F
    reti

.org 0x0010
    reti

.org 0x0011
    reti

.org 0x0012
    reti

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

    ; Clear SRAM variables

    clr r16

    sts epoch_lo, r16
    sts epoch_hi, r16

    sts target1_hi, r16
    sts target1_hi+1, r16

    sts target2_hi, r16
    sts target2_hi+1, r16

    sts pending_ping, r16
    sts pending_pong, r16

    ; -------------------------------------------------
    ; USART INITIALIZATION
    ; -------------------------------------------------

    ldi r16, high(UBRR_VALUE)
    out UBRRH, r16

    ldi r16, low(UBRR_VALUE)
    out UBRRL, r16

    ldi r16, (1<<TXEN)
    out UCSRB, r16

    ldi r16, (1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
    out UCSRC, r16

    ; -------------------------------------------------
    ; TIMER1 INITIALIZATION
    ; -------------------------------------------------

    clr r16

    out TCCR1A, r16
    out TCCR1B, r16

    ; Reset Timer1 counter

    out TCNT1H, r16
    out TCNT1L, r16

    ; Initial compare values = 0x8720

    ldi r16, 0x87
    out OCR1AH, r16
    out OCR1BH, r16

    ldi r16, 0x20
    out OCR1AL, r16
    out OCR1BL, r16

    ; Initial target high words = 1

    ldi r16, 1

    sts target1_hi, r16
    sts target2_hi, r16

    clr r16

    sts target1_hi+1, r16
    sts target2_hi+1, r16

    ; Clear pending Timer1 flags

    ldi r16, (1<<OCF1A)|(1<<OCF1B)|(1<<TOV1)
    out TIFR, r16

    ; Enable Compare A, Compare B and Overflow

    ldi r16, (1<<OCIE1A)|(1<<OCIE1B)|(1<<TOIE1)
    out TIMSK, r16

    ; Start Timer1, prescaler = 1

    ldi r16, (1<<CS10)
    out TCCR1B, r16

    ; Enable global interrupts

    sei

; -----------------------------------------------------
; MAIN LOOP
; -----------------------------------------------------

MAIN:

    ; -----------------------------------------------
    ; CHECK PING EVENTS
    ; -----------------------------------------------

    cli

    lds r16, pending_ping

    tst r16
    breq CHECK_PONG

    dec r16
    sts pending_ping, r16

    sei

    ; Send ping

    ldi ZL, low(TIMER1_STR*2)
    ldi ZH, high(TIMER1_STR*2)

    rcall USART_SEND_STRING

    rjmp MAIN

; -----------------------------------------------------
; CHECK PONG EVENTS
; -----------------------------------------------------

CHECK_PONG:

    sei
    cli

    lds r16, pending_pong

    tst r16
    breq NO_EVENTS

    dec r16
    sts pending_pong, r16

    sei

    ; Send pong

    ldi ZL, low(TIMER2_STR*2)
    ldi ZH, high(TIMER2_STR*2)

    rcall USART_SEND_STRING

    rjmp MAIN

NO_EVENTS:

    sei
    rjmp MAIN

; -----------------------------------------------------
; TIMER1 COMPARE A ISR
; -----------------------------------------------------

TIMER1_COMPA_ISR:

    push r16
    in r16, SREG
    push r16

    push r17
    push r18
    push r19
    push r20

    ; Check current epoch against target1_hi

    lds r16, epoch_lo
    lds r17, epoch_hi

    lds r18, target1_hi
    lds r19, target1_hi+1

    cp r16, r18
    cpc r17, r19

    brne COMPA_EXIT

    ; Register ping event

    lds r18, pending_ping
    inc r18
    sts pending_ping, r18

    ; Advance OCR1A by 100128 clocks

    in r16, OCR1AL
    in r17, OCR1AH

    ldi r20, low(TIMER1_INTERVAL)
    add r16, r20

    ldi r20, high(TIMER1_INTERVAL)
    adc r17, r20

    out OCR1AH, r17
    out OCR1AL, r16

    ; Advance target high word by 1 + carry

    lds r18, target1_hi
    lds r19, target1_hi+1

    ldi r20, 1
    adc r18, r20

    ldi r20, 0
    adc r19, r20

    sts target1_hi, r18
    sts target1_hi+1, r19

COMPA_EXIT:

    pop r20
    pop r19
    pop r18
    pop r17

    pop r16
    out SREG, r16

    pop r16

    reti

; -----------------------------------------------------
; TIMER1 COMPARE B ISR
; -----------------------------------------------------

TIMER1_COMPB_ISR:

    push r16
    in r16, SREG
    push r16

    push r17
    push r18
    push r19
    push r20

    ; Check current epoch against target2_hi

    lds r16, epoch_lo
    lds r17, epoch_hi

    lds r18, target2_hi
    lds r19, target2_hi+1

    cp r16, r18
    cpc r17, r19

    brne COMPB_EXIT

    ; Register pong event

    lds r18, pending_pong
    inc r18
    sts pending_pong, r18

    ; Advance OCR1B by 100128 clocks

    in r16, OCR1BL
    in r17, OCR1BH

    ldi r20, low(TIMER2_INTERVAL)
    add r16, r20

    ldi r20, high(TIMER2_INTERVAL)
    adc r17, r20

    out OCR1BH, r17
    out OCR1BL, r16

    ; Advance target high word by 1 + carry

    lds r18, target2_hi
    lds r19, target2_hi+1

    ldi r20, 1
    adc r18, r20

    ldi r20, 0
    adc r19, r20

    sts target2_hi, r18
    sts target2_hi+1, r19

COMPB_EXIT:

    pop r20
    pop r19
    pop r18
    pop r17

    pop r16
    out SREG, r16

    pop r16

    reti

; -----------------------------------------------------
; TIMER1 OVERFLOW ISR
; Extends 16-bit timer to 32-bit time base
; -----------------------------------------------------

TIMER1_OVF_ISR:

    push r16
    in r16, SREG
    push r16

    lds r16, epoch_lo

    inc r16
    sts epoch_lo, r16

    brne OVERFLOW_EXIT

    lds r16, epoch_hi

    inc r16
    sts epoch_hi, r16

OVERFLOW_EXIT:

    pop r16
    out SREG, r16

    pop r16

    reti

; -----------------------------------------------------
; USART SEND STRING
; Z = Flash address
; -----------------------------------------------------

USART_SEND_STRING:

    lpm r16, Z+

    tst r16
    breq USART_SEND_END

USART_WAIT:

    sbis UCSRA, UDRE
    rjmp USART_WAIT

    out UDR, r16

    rjmp USART_SEND_STRING

USART_SEND_END:

    ret
