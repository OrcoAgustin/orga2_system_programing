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
extern mmu_init_kernel_dir
extern mmu_init_task_dir
extern tss_init
extern tasks_init               ; verificar el nombre exacto en tasks.c
extern switch_to_usermode       ; definida en isr.asm (con "global" alla)

;extern test_copy_page

%define C_FG_GREEN 0x2
%define KERNEL_STACK 0x00025000
%define TASK_INITIAL_SEL (11 << 3)
%define IDLE_PHYS_ADDR 0x00018000   ; verificar contra defines.h
%include "print.mac"

global start

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
;; Seccion de codigo.
;; -------------------------------------------------------------------------- ;;

;; Punto de entrada del kernel.
BITS 16
start:
    ; ==============================
    ; ||  Salto a modo protegido  ||
    ; ==============================

    cli

    ; Cambiar modo de video a 80 X 50
    mov ax, 0003h
    int 10h ; set mode 03h
    xor bx, bx
    mov ax, 1112h
    int 10h ; load 8x8 font

    print_text_rm start_rm_msg, start_rm_len, C_FG_GREEN, 0, 0

    call A20_enable

    lgdt [GDT_DESC]

    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    jmp CS_RING_0_SEL:modo_protegido


BITS 32
modo_protegido:
    mov ax, DS_RING_0_SEL
    mov ds, ax
    mov es, ax
    mov gs, ax
    mov fs, ax
    mov ss, ax

    mov esp, KERNEL_STACK
    mov ebp, esp

    print_text_pm start_pm_msg, start_pm_len, C_FG_GREEN, 0, 0

    call screen_draw_layout

    ; ===================================
    ; ||   (Parte 2: Interrupciones)   ||
    ; ===================================

    call idt_init
    lidt [IDT_DESC]

    call pic_reset
    call pic_enable

    ; ===================================
    ; ||     (Parte 3: Paginacion)     ||
    ; ===================================

    call mmu_init_kernel_dir     ; devuelve en EAX la dir. del directorio (0x25000)
    mov cr3, eax                 ; CR3 = dir. fisica del directorio de paginas

    mov eax, cr0
    or  eax, 0x80000000          ; bit 31 (PG) = 1 -> activa paginacion
    mov cr0, eax

    ;prueba de copy page
    ;call test_copy_page

    ; ========================
    ; ||  (Parte 4: Tareas)  ||
    ; ========================

    ; Descriptores de TSS en la GDT
    call tss_init
    mov ax, TASK_INITIAL_SEL
    ltr ax

    call tasks_init          ; crea idle (tasks[0]) y las demas, con sus cr3

    call switch_to_usermode  ; sin argumentos, lee tasks[0]

    ; ---- Prueba de la tarea ficticia (comentada, ya cumplio su funcion) ----
    ;push 0x18000
    ;call mmu_init_task_dir
    ;add esp, 4
    ;mov ebx, eax                    ; ebx = cr3 de la tarea
    ;mov eax, cr3
    ;push eax                        ; guardo el cr3 del kernel
    ;mov cr3, ebx                    ; breakpoint: info page
    ;mov dword [0x07000000], 0x1234  ; 1ra escritura: page fault -> se mapea
    ;mov dword [0x07000004], 0x5678  ; 2da escritura: ya mapeada
    ;pop eax
    ;mov cr3, eax

    ; ---- Prueba de la int 88 (comentada) ----
    ;mov eax, 0
    ;int 88

    ; ---- Prueba de excepcion (comentada) ----
    ;int3

    ; Directorio de paginas de la tarea Idle
    push IDLE_PHYS_ADDR
    call mmu_init_task_dir
    add esp, 4                   ; EAX = cr3 de la idle

    ; Saltar a la Idle en ring 3 (carga cr3, arma la pila y hace iret).
    ; El iret deja IF=1, por eso no hace falta un sti antes.
    push eax
    call switch_to_usermode      ; no vuelve

    ; Red de seguridad: nunca deberia llegar aca
    mov eax, 0xFFFF
    mov ebx, 0xFFFF
    mov ecx, 0xFFFF
    mov edx, 0xFFFF
    jmp $

;; -------------------------------------------------------------------------- ;;

%include "a20.asm"