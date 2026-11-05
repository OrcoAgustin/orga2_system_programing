/* ** por compatibilidad se omiten tildes **
================================================================================
 TRABAJO PRACTICO 3 - System Programming - ORGANIZACION DE COMPUTADOR II - FCEN
================================================================================

  Definicion de funciones del manejador de memoria
*/

#include "mmu.h"
#include "i386.h"

#include "kassert.h"

static pd_entry_t* kpd = (pd_entry_t*)KERNEL_PAGE_DIR;
static pt_entry_t* kpt = (pt_entry_t*)KERNEL_PAGE_TABLE_0;

static const uint32_t identity_mapping_end = 0x003FFFFF;
static const uint32_t user_memory_pool_end = 0x02FFFFFF;

static paddr_t next_free_kernel_page = 0x100000;
static paddr_t next_free_user_page = 0x400000;

/**
 * kmemset asigna el valor c a un rango de memoria interpretado
 * como un rango de bytes de largo n que comienza en s
 * @param s es el puntero al comienzo del rango de memoria
 * @param c es el valor a asignar en cada byte de s[0..n-1]
 * @param n es el tamaño en bytes a asignar
 * @return devuelve el puntero al rango modificado (alias de s)
*/
static inline void* kmemset(void* s, int c, size_t n) {
  uint8_t* dst = (uint8_t*)s;
  for (size_t i = 0; i < n; i++) {
    dst[i] = c;
  }
  return dst;
}

/**
 * zero_page limpia el contenido de una página que comienza en addr
 * @param addr es la dirección del comienzo de la página a limpiar
*/
static inline void zero_page(vaddr_t addr) {
  kmemset((void*)addr, 0x00, PAGE_SIZE);
}


void mmu_init(void) {}


/**
 * mmu_next_free_kernel_page devuelve la dirección física de la próxima página de kernel disponible. 
 * Las páginas se obtienen en forma incremental, siendo la primera: next_free_kernel_page
 * @return devuelve la dirección de memoria de comienzo de la próxima página libre de kernel
 */
  paddr_t mmu_next_free_kernel_page(void) {
  paddr_t page = next_free_kernel_page;
  next_free_kernel_page += PAGE_SIZE;
  return page;
}

/**
 * mmu_next_free_user_page devuelve la dirección de la próxima página de usuarix disponible
 * @return devuelve la dirección de memoria de comienzo de la próxima página libre de usuarix
 */
paddr_t mmu_next_free_user_page(void) {
  paddr_t page = next_free_user_page;
  next_free_user_page += PAGE_SIZE;
  return page;
}

/**
 * mmu_init_kernel_dir inicializa las estructuras de paginación vinculadas al kernel y
 * realiza el identity mapping
 * @return devuelve la dirección de memoria de la página donde se encuentra el directorio
 * de páginas usado por el kernel
 */
paddr_t mmu_init_kernel_dir(void) {
  zero_page((vaddr_t)kpd);
  zero_page((vaddr_t)kpt);

  kpd[0].attrs = 0x3;   // P | RW, supervisor
  kpd[0].pt = KERNEL_PAGE_TABLE_0 >> 12;

  for (int i = 0; i < 1024; i++) {
    kpt[i].attrs = 0x3;
    kpt[i].page = i;
  }

  return (paddr_t)kpd;
}

/**
 * mmu_map_page agrega las entradas necesarias a las estructuras de paginación de modo de que
 * la dirección virtual virt se traduzca en la dirección física phy con los atributos definidos en attrs
 * @param cr3 el contenido que se ha de cargar en un registro CR3 al realizar la traducción
 * @param virt la dirección virtual que se ha de traducir en phy
 * @param phy la dirección física que debe ser accedida (dirección de destino)
 * @param attrs los atributos a asignar en la entrada de la tabla de páginas
 */
void mmu_map_page(uint32_t cr3, vaddr_t virt, paddr_t phy, uint32_t attrs) {
  pd_entry_t* direc = (pd_entry_t*)(cr3 & 0xFFFFF000); /*sacamos los flags de cr3 y nos quedamos solo con la direccion*/

  /*ahora de virt a la entrada directorio*/
  uint32_t direc_entry = virt>>22; /*los 10 bits mas significativos de virt*/

  /*chequeamos que exista la tabla*/
  if (!(direc[direc_entry].attrs & 0x1)) {/*si el bit 0 no es 1 quiere decir que el flag present esta clear osea no existe*/
    // la tabla no existe: hay que crearla
    paddr_t nueva_tabla = mmu_next_free_kernel_page();   // 1) pedir una página libre
    zero_page((vaddr_t)nueva_tabla);                     // 2) limpiarla (todas las PTE en no presente)
    direc[direc_entry].pt = nueva_tabla >> 12;           // 3) enganchar la PDE a esa tabla
    direc[direc_entry].attrs = MMU_P | MMU_W;            // 4) marcarla presente + escritura
  }

  direc[direc_entry].attrs |= (attrs & MMU_U);

  /*vamos a la tabla*/
  pt_entry_t* tabla = (pt_entry_t*)((uint32_t)direc[direc_entry].pt << 12);
   /*sacamos la direccion de la tabla de paginas*/

  /*ahora de virt a la entrada tabla*/
  uint32_t tabla_entry = (virt>>12) & 0x3FF; /*los 10 bits menos significativos de virt(descontando el offset obvio)*/
  
  /*ahora escribimos la entrada de la tabla*/
  tabla[tabla_entry].page = phy >> 12;
  tabla[tabla_entry].attrs = (attrs & 0xFFF) | MMU_P;

  /*ahora flusheas para actualziar todo por que sino
  ,si esa dirección virtual ya estaba cacheada en la TLB con otra traducción, 
  la CPU sigue usando la vieja*/
  tlbflush();

}

/**
 * mmu_unmap_page elimina la entrada vinculada a la dirección virt en la tabla de páginas correspondiente
 * @param virt la dirección virtual que se ha de desvincular
 * @return la dirección física de la página desvinculada
 */
paddr_t mmu_unmap_page(uint32_t cr3, vaddr_t virt) {
/*procedimiento similar al map*/
pd_entry_t* direc = (pd_entry_t*)(cr3 & 0xFFFFF000); /*sacamos los flags de cr3 y nos quedamos solo con la direccion*/

  /*ahora de virt a la entrada directorio*/
  uint32_t direc_entry = virt>>22; /*los 10 bits mas significativos de virt*/

  /*el caso if no importa, aca si existe*/
  /*vamos a la tabla*/
  pt_entry_t* tabla = (pt_entry_t*)((uint32_t)direc[direc_entry].pt << 12);
   /*sacamos la direccion de la tabla de paginas*/

  /*ahora de virt a la entrada tabla*/
  uint32_t tabla_entry = (virt>>12) & 0x3FF; /*los 10 bits menos significativos de virt(descontando el offset obvio)*/

  /*guardamos la direccion fisica de la pagina que vamos a desvincular*/
  paddr_t phy = tabla[tabla_entry].page << 12;

  tabla[tabla_entry].attrs = 0; /*desvinculamos la tabla de paginas*/
  tabla[tabla_entry].page = 0; /*desvinculamos la pagina*/

  tlbflush(); /*flusheamos para que no quede cacheada la traduccion vieja*/
  return phy;

}

#define DST_VIRT_PAGE 0xA00000
#define SRC_VIRT_PAGE 0xB00000

/**
 * copy_page copia el contenido de la página física localizada en la dirección src_addr a la página física ubicada en dst_addr
 * @param dst_addr la dirección a cuya página queremos copiar el contenido
 * @param src_addr la dirección de la página cuyo contenido queremos copiar
 *
 * Esta función mapea ambas páginas a las direcciones SRC_VIRT_PAGE y DST_VIRT_PAGE, respectivamente, realiza
 * la copia y luego desmapea las páginas. Usar la función rcr3 definida en i386.h para obtener el cr3 actual
 */
void copy_page(paddr_t dst_addr, paddr_t src_addr) {
  uint32_t cr3 = rcr3();

  mmu_map_page(cr3, SRC_VIRT_PAGE, src_addr, MMU_P);
  mmu_map_page(cr3, DST_VIRT_PAGE, dst_addr, MMU_P);

  /*copiamos*/
  uint8_t* src = (uint8_t*)SRC_VIRT_PAGE;
  uint8_t* dst = (uint8_t*)DST_VIRT_PAGE;
  for (size_t i = 0; i < PAGE_SIZE; i++) {
    dst[i] = src[i];
  }

  // Cerramos las ventanas
  mmu_unmap_page(cr3, SRC_VIRT_PAGE);
  mmu_unmap_page(cr3, DST_VIRT_PAGE);
}

 /**
 * mmu_init_task_dir inicializa las estructuras de paginación vinculadas a una tarea cuyo código se encuentra en la dirección phy_start
 * @pararm phy_start es la dirección donde comienzan las dos páginas de código de la tarea asociada a esta llamada
 * @return el contenido que se ha de cargar en un registro CR3 para la tarea asociada a esta llamada
 */
paddr_t mmu_init_task_dir(paddr_t phy_start) {

  /*pedimos pagina(CR3)*/
  paddr_t pd_phys = mmu_next_free_kernel_page();

  /*limpiamos pagina*/
  zero_page((vaddr_t)pd_phys);

  /*hacemos que la nueva tenga misma config del kernel */
  pd_entry_t* pd = (pd_entry_t*)pd_phys;
  pd[0] = kpd[0];

  /*mapeamos las 2 de codigo(solo lecturas y level de user)*/
  mmu_map_page(pd_phys, 0x08000000, phy_start, MMU_P | MMU_U);
  mmu_map_page(pd_phys, 0x08001000, phy_start + PAGE_SIZE, MMU_P | MMU_U);

 // Stack: la página está debajo de TASK_STACK_BASE
  paddr_t stack = mmu_next_free_user_page();
  mmu_map_page(pd_phys, TASK_STACK_BASE - PAGE_SIZE, stack, MMU_P | MMU_W | MMU_U);

  // Compartida: justo después del stack
  mmu_map_page(pd_phys, TASK_SHARED_PAGE, SHARED, MMU_P | MMU_W | MMU_U);
  
  return pd_phys;
}

// COMPLETAR: devuelve true si se atendió el page fault y puede continuar la ejecución 
// y false si no se pudo atender
bool page_fault_handler(vaddr_t virt) {
  print("Atendiendo page fault...", 0, 0, C_FG_WHITE | C_BG_BLACK);
    // ¿El acceso fue dentro del área on-demand?
  if (virt >= ON_DEMAND_MEM_START_VIRTUAL && virt <= ON_DEMAND_MEM_END_VIRTUAL) {
    // Mapear la página como lectura-escritura a nivel usuario
    mmu_map_page(rcr3(), ON_DEMAND_MEM_START_VIRTUAL, ON_DEMAND_MEM_START_PHYSICAL,
                 MMU_P | MMU_W | MMU_U);
    return true;
  }

  return false;
}


void test_copy_page(void) {
  // Páginas del área de kernel: están dentro del identity mapping,
  // así que puedo escribirlas directo por su dirección física
  paddr_t src = mmu_next_free_kernel_page();
  paddr_t dst = mmu_next_free_kernel_page();

  uint32_t* s = (uint32_t*)src;
  uint32_t* d = (uint32_t*)dst;
  for (int i = 0; i < 1024; i++) {
    s[i] = 0xCAFE0000 + i;   // patrón distinto en cada palabra
    d[i] = 0;                // destino limpio
  }

  copy_page(dst, src);

  // Dejá un lugar para poner el breakpoint
  __asm__ volatile("nop");
}
