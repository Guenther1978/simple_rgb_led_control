;
; dual_pwm_control.asm
;
; Created: 25.06.2023 11:15:47
; Author : guent
;



	#include <tn13Adef.inc>

	.equ	warmwhite = 0
	.equ	coldwhite = 1

	.def	memory = r0
	.def	isr_save = r1
	.def	aux_2 = r2
	.def	rand_lo = r3
	.def	rand_hi = r4
	.def	counter = r5


	.def	aux = r16
	.def	pointer = r17
	.def	darker = r18
	.def	w_reg = r19
	.def	interrupts = r20
	.def	duration = r21

 	rjmp	RESET
	reti						; EXT_INT0
	reti						; PCINT0
	rjmp	ISR_TIM0_OVF		; Timer0 Overflow Handler
	reti						; EE_RDY
	reti						; ANA_COMP
	reti						; TIM0_COMPA
	reti						; TIMO_COMPB
	reti						; WATCHDOG
	reti						; ADC
	;;
RESET:
	ldi		aux, low(RAMEND)
	out		SPL, aux
	;; Initialize PWM Ports
	sbi		DDRB, 0
	sbi		DDRB, 1
	;; Initialize ADC
	ldi		aux, 0x22
	out		ADMUX, aux
	ldi		aux, 0x80
	out		ADCSRA, aux
	;; Initialize random register
	sbi		ADCSRA, ADSC
init1_ready:
	sbic	ADCSRA, ADSC
	rjmp	init1_ready
	sbi		ADCSRA, ADSC
value1_ready:
	sbic	ADCSRA, ADSC
	rjmp	value1_ready
	in		rand_lo,ADCL
	sbi		ADCSRA, ADSC
init2_ready:
	sbic	ADCSRA, ADSC
	rjmp	init2_ready
	sbi		ADCSRA, ADSC
value2_ready:
	sbic	ADCSRA, ADSC
	rjmp	value2_ready
	in		rand_hi, ADCL
	mov		aux, rand_lo
	cpi		aux, 0
	brne	random_init_done
	mov		aux, rand_lo
	cpi		aux, 0
	brne	random_init_done
	ldi		aux, 0x30
	mov		rand_hi, aux
	ldi		aux, 0x45
	mov		rand_lo, aux
random_init_done:
	;; Initialize pointer
	ldi		aux, 0
	mov		pointer, aux
	mov		darker, aux
	ldi		aux, 64
	mov		interrupts, aux
	ldi		aux, 1
	mov		counter, aux
	mov		duration, aux
	;; Initialize Timer
	ldi		aux, 0xA3
	out		TCCR0A, aux
	ldi		aux, 2
	out		TCCR0B, aux
	ldi		aux, 2
	out		TCCR0B, aux
	;; Enable Timer Overflow Interrupt
	ldi		aux, 2
	out		TIMSK0, aux
	;; Load PWM outpts with rand_hi and rand_lo
	out		OCR0A, rand_lo
	out		OCR0B, rand_hi
	rcall	myWait_10s
	;; Gloabal Interrupt enable
	sei
loop:
	rjmp	loop

ISR_TIM0_OVF:
	in		isr_save, SREG

	; PWM frequency must be high to avoid flickering
	; so use additional register to extend the time
	dec		interrupts
	brbc	1, isr_return
	ldi		interrupts, 64
	
	; Use random dalay to change the speed
	dec		counter
	brbc	1, isr_return
	mov		counter, duration

	; is the pointer increaing or decrasing
	cpi		darker, 255 
	brbs	1, decrease_pointer

	; pointer is increasing
	inc		pointer

	; is the pointe at its max. position
	cpi		pointer, 255
	brbc	1, load_intensity

	; change darker and load new random duration
	ser		darker
	rcall	Random16
	mov		duration, rand_lo
	andi	duration, 0x07
	inc		duration
	rjmp	load_intensity

	;pointer is decrasing
decrease_pointer:
	dec		pointer

	; is the pointer at its min. position
	cpi		pointer, 0
	brbc	1, load_intensity

	; change darker and load new random duration
	clr		darker
	rcall	Random16
	mov		duration, rand_lo
	andi	duration, 0x07
	inc		duration

	; load intensities to the pwm registers
load_intensity:
	; first LED
	mov		aux, pointer
	ldi		ZH, high(2 * intensity_table)
	ldi		ZL, low(2 * intensity_table)
	add		ZL, aux
	brcc	z_register_ready_1
	inc		ZH
z_register_ready_1:
	lpm
	mov		aux, memory
	out		OCR0A, aux

	; second LED
	mov		aux, pointer
	com		aux						; = 255 - aux
	ldi		ZH, high(2 * intensity_table)
	ldi		ZL, low(2 * intensity_table)
	add		ZL, aux
	brcc	z_register_ready_2
	inc		ZH
z_register_ready_2:
	lpm		
	mov		aux, memory
	out		OCR0B, aux

isr_return:
	out		SREG, isr_save
	reti

;--------------------------------------------------------------------
; This function calculates a 16 bit random number
; Adapted from Microchips AN544
;--------------------------------------------------------------------
Random16:
	; rlcf	RandHi,W
	mov		w_reg, rand_hi
	rol		w_reg

	; xorwf	RandHi,W
	eor		w_reg, rand_hi

	; rlcf	WREG, F ; carry bit = xorwf(Q15,14)
	rol		w_reg

	; swapf	RandHi, F
	swap	rand_hi

	; swapf	RandLo,W
	mov		w_reg, rand_lo
	swap	w_reg

	; rlncf	WREG, F
	rol		w_reg
	brcs	rlncf_carry
	andi	w_reg, 0xFE
	rjmp	rlncf_done
rlncf_carry:
	ori		w_reg, 0x01
rlncf_done:
	
	; xorwf	RandHi,W ; LSB = xorwf(Q12,Q3)
	eor		w_reg, rand_hi

	; swapf	RandHi, F
	swap	rand_hi

	; andlw	0x01
	andi	w_reg, 0x01

	; rlcf	RandLo, F
	rol		rand_lo

	; xorwf	RandLo, F
	eor		rand_lo, w_reg

	; rlcf	RandHi, F
	rol		rand_hi

	ret

;--------------------------------------------------------------------
; This function waits 10 s
; Adapted from SiSy Solutions GmbH
;--------------------------------------------------------------------
myWait_10s:
 	push 	r16
 	ldi 	r16,200
myWait_100ms_3:
 	push 	r16
 	ldi 	r16,255
myWait_100ms_2:
 	push 	r16
 	ldi 	r16,255
myWait_100ms_1:
 	dec 	r16 	
 	brne 	myWait_100ms_1
 	pop 	r16
 	dec 	r16 	
 	brne 	myWait_100ms_2
 	pop 	r16
 	dec 	r16 	
 	brne 	myWait_100ms_3
 	pop 	r16
 	ret

intensity_table:
	#include "intensities.inc"
