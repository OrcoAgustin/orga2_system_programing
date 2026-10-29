; ** por compatibilidad se omiten tildes **
; ==============================================================================
; TALLER System Programming - Arquitectura y Organizacion de Computadoras - FCEN
; ==============================================================================
extern A20_enable
extern GDT_DESC
extern screen_draw_layout
extern idt_init
extern IDT_DESC
extern pic_reset
extern pic_enable

%define C_FG_GREEN 0x2
%define KERNEL_STACK 0x00025000

%include "print.mac"

global start


; COMPLETAR - Agreguen declaraciones extern según vayan necesitando

; COMPLETAR - Definan correctamente estas constantes cuando las necesiten
%define CS_RING_0_SEL (1 << 3)   
%define DS_RING_0_SEL (3 << 3)   


BITS 16
;; Saltear seccion de datos
jmp start

;;
;; Seccion de datos.
;; -------------------------------------------------------------------------- ;;
start_rm_msg db     'Iniciando kernel en Modo Real'
start_rm_len equ    $ - start_rm_msg

start_pm_msg db     'Iniciando kernel en Modo Protegido'
start_pm_len equ    $ - start_pm_msg

;;
;; Seccion de código.
;; -------------------------------------------------------------------------- ;;

;; Punto de entrada del kernel.
BITS 16
start:
    ; ==============================
    ; ||  Salto a modo protegido  ||
    ; ==============================

    ; COMPLETADO- Deshabilitar interrupciones (Parte 1: Pasaje a modo protegido)
    Cli 

    ; Cambiar modo de video a 80 X 50
    mov ax, 0003h
    int 10h ; set mode 03h
    xor bx, bx
    mov ax, 1112h
    int 10h ; load 8x8 font

    ; COMPLETADO - Imprimir mensaje de bienvenida - MODO REAL (Parte 1: Pasaje a modo protegido)
    ; (revisar las funciones definidas en print.mac y los mensajes se encuentran en la
    ; sección de datos)
    print_text_rm start_rm_msg, start_rm_len,C_FG_GREEN,0,0 


    ; COMPLETADO - Habilitar A20 (Parte 1: Pasaje a modo protegido)
    ; (revisar las funciones definidas en a20.asm)
    Call A20_enable

    ; COMPLETADO - los defines para la GDT en defines.h y las entradas de la GDT en gdt.c
    ; COMPLETADO - Cargar la GDT (Parte 1: Pasaje a modo protegido)
    
    lgdt[GDT_DESC]

    ; COMPLETADO - Setear el bit PE del registro CR0 (Parte 1: Pasaje a modo protegido)
    
    mov eax, cr0
    or  eax, 1          
    mov cr0, eax
    
    ; COMPLETADO - Saltar a modo protegido (far jump) (Parte 1: Pasaje a modo protegido)
    ; (recuerden que un far jmp se especifica como jmp CS_selector:address)
    ; Pueden usar la constante CS_RING_0_SEL definida en este archivo

    jmp CS_RING_0_SEL:modo_protegido
    
   

BITS 32
modo_protegido:
    ; COMPLETAR (Parte 1: Pasaje a modo protegido) - A partir de aca, todo el codigo se va a ejectutar en modo protegido
    ; Establecer selectores de segmentos DS, ES, GS, FS y SS en el segmento de datos de nivel 0
    ; Pueden usar la constante DS_RING_0_SEL definida en este archivo


    ;arranca todo en el valor de 11 shifteado 3 a la izq
    mov ax, DS_RING_0_SEL
    mov ds, ax
    mov es, ax
    mov gs, ax
    mov fs, ax
    mov ss, ax


    ; COMPLETAR - Establecer el tope y la base de la pila (Parte 1: Pasaje a modo protegido)
    mov esp, KERNEL_STACK
    mov ebp, esp        

    ; COMPLETAR - Imprimir mensaje de bienvenida - MODO PROTEGIDO (Parte 1: Pasaje a modo protegido)
    print_text_pm start_pm_msg, start_pm_len,C_FG_GREEN,0,0

    call screen_draw_layout
    ; COMPLETAR - Inicializar pantalla (Parte 1: Pasaje a modo protegido)
    
    ; ===================================
    ; ||     (Parte 3: Paginación)     ||
    ; ===================================

    ; COMPLETAR - los defines para la MMU en defines.h
    ; COMPLETAR - las funciones en mmu.c
    ; COMPLETAR - reemplazar la implementacion de la interrupcion 88 (ver comentarios en isr.asm)
    ; COMPLETAR - La rutina de atención del page fault en isr.asm
    ; COMPLETAR - Inicializar el directorio de paginas

    ; COMPLETAR - Cargar directorio de paginas 

    ; COMPLETAR - Habilitar paginacion 

    ; ========================
    ; ||  (Parte 4: Tareas) ||
    ; ========================

    ; COMPLETAR - reemplazar la implementacion de la interrupcion 88 (ver comentarios en isr.asm)
    ; COMPLETAR - las funciones en tss.c
    ; COMPLETAR - Inicializar tss

    ; COMPLETAR - Inicializar el scheduler

    ; COMPLETAR - Inicializar las tareas


    ; ===================================
    ; ||   (Parte 2: Interrupciones)   ||
    ; ===================================

    ; COMPLETADO - las funciones en idt.c

    ; COMPLETADO- Inicializar y cargar la IDT

    call idt_init
    lidt [IDT_DESC]

    ; COMPLETADO- Reiniciar y habilitar el controlador de interrupciones (ver pic.c)

    call pic_reset
    call pic_enable

    sti 

    ; COMPLETADO - Rutinas de atención de reloj, teclado, e interrupciones 88 y 89 (en isr.asm)

    mov eax,0
    int 88

    ; COMPLETAR (Parte 4: Tareas)- Cargar tarea inicial

    ; COMPLETAR - Habilitar interrupciones (!! en etapas posteriores, evaluar si se debe comentar este código !!)
    
    ; NOTA: Pueden chequear que las interrupciones funcionen forzando a que se
    ;       dispare alguna excepción (lo más sencillo es usar la instrucción
    ;       `int3`)
    ;int3

    ; COMPLETAR - Probar Sys_call (para etapas posteriores, comentar este código)

    ; COMPLETAR - Probar generar una excepción (para etapas posteriores, comentar este código)
    
    ; ========================
    ; ||  (Parte 4: Tareas)  ||
    ; ========================
    
    ; COMPLETAR - Inicializar el directorio de paginas de la tarea de prueba

    ; COMPLETAR - Cargar directorio de paginas de la tarea

    ; COMPLETAR - Restaurar directorio de paginas del kernel

    ; COMPLETAR - Saltar a la primera tarea: Idle

    ; Ciclar infinitamente 
    mov eax, 0xFFFF
    mov ebx, 0xFFFF
    mov ecx, 0xFFFF
    mov edx, 0xFFFF
    jmp $

;; -------------------------------------------------------------------------- ;;

%include "a20.asm"
