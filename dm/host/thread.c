// Guest thread environment: gate slot = this thread's gate entry (guest_gate_stack); x18 slot cleared; tpidr_el0 slot = ELF TLS block; tpidrro_el0 slot = Horizon ThreadLocalRegion (0x200).
// The kernel owns two fields of the ThreadLocalRegion that the SDK reads: the current thread object at TLR[0x1f8] and, since SDK 22, the thread's ID at TLR[0x110] (nn::os 22's internal critical
// section stores it as a mutex's owner and compares it in IsLockedByCurrentThread, where SDK 16 compared the object pointer). Here each thread gets a zero-initialized object allocated and
// written in, and its ID once the thread table has one (guest_thread_set_id)
#include "dm.h"
#include <sys/mman.h>
#define TLS_SIZE 8192
#define TLR_SIZE 0x200
#define THREAD_OBJ_SIZE 0x400
static pthread_key_t g_keyown;   // raw pointers of the TLS block / thread-local region this thread allocated (see the end of guest_thread_init)
static pthread_once_t g_keyown_once = PTHREAD_ONCE_INIT;
#if defined(DM_CLASSIC_SHELF_LIFECYCLE)
static int g_own_key_ready, g_gslot_key_ready;
#endif
static void own_free(void *p) { void **own = p; free(own[0]); free(own[1]); free(own); }
static void own_key_init(void) {
    if (pthread_key_create(&g_keyown, own_free)) die("cannot create the free key for thread-local blocks");
#if defined(DM_CLASSIC_SHELF_LIFECYCLE)
    g_own_key_ready = 1;
#endif
}
void guest_thread_init(void) {
    pthread_setspecific(g_key18, 0);
    // The TLS block and the thread-local region are freed when the thread exits. The guest overwrites the slots of the TLS / thread-local-region keys (it sets its own thread pointer), so they cannot be freed by the current value in the key:
    // the raw pointers that were allocated are recorded separately on this file's own key g_keyown and freed by its destructor (key destructors run at pthread_exit, like crash.c's signal alternate stack; the destructor only calls free, which is safe on a guest thread's small stack too).
    // They used not to be freed: every short-lived thread the game started leaked 8192 + 0x200 + 0x400 = 9728 bytes. The thread-local region and the current thread object are one block (the SDK may also overwrite the TLR[0x1f8] slot)
    pthread_once(&g_keyown_once, own_key_init);
    void **own = calloc(2, sizeof *own); uint8_t *tlr = calloc(1, TLR_SIZE + THREAD_OBJ_SIZE);
    if (!own || !tlr) die("guest thread-local block allocation failed");
    own[0] = calloc(1, TLS_SIZE); own[1] = tlr;
    if (!own[0]) die("guest thread TLS block allocation failed");
    *(void **)(tlr + 0x1f8) = tlr + TLR_SIZE;               // current thread object
    pthread_setspecific(g_keytls, own[0]); pthread_setspecific(g_keytlr, tlr);
    void **prev = pthread_getspecific(g_keyown); if (prev) own_free(prev);   // re-initialised on the same thread: free the previous set first (the new one is what the slots now point to)
    pthread_setspecific(g_keyown, own);
}
// The thread's kernel ID at TLR[0x110], the one svcGetThreadId answers (hle_thread.c's thr_t id, never 0: 0 is the owner word of an unlocked mutex). Without it every
// unlocked SDK 22 mutex reads as the caller's and the first heap lock aborts (docs/reference/threads.md)
void guest_thread_set_id(uint64_t id) { *(uint32_t *)((uint8_t *)pthread_getspecific(g_keytlr) + 0x110) = (uint32_t)id; }

// Gate stacks (entry.S dm_gate): the SVC gate's register frame and the host's SVC handlers run on a stack of the thread's own, never below the guest's sp, as on Horizon, whose kernel leaves a
// thread's stack untouched during an SVC. Each thread holds a gate slot k: its KGATE slot points to entry.S stub k, which loads dm_gate_top[k]. A guest thread (hle_thread.c thread_main) runs
// its guest code on the guest stack the SDK gave it, so its gate stack is the rest of its own pthread stack (1 MB), below thread_main's frame: it lives exactly as long as the thread, which
// exits from inside an SVC (ExitThread → pthread_exit on the gate stack). The guest main thread runs its guest code on its pthread's stack, so it gets a separate mapped gate stack.
// iOS retains that mapping until the shell can prove the pthread has really exited: the TSD destructor can still be running on the mapping it retires.
#define GATE_SLOTS 1024                 // = entry.S .rept count and dm_gate_top size
#define GATE_STACK_SIZE (1 << 20)       // = entry.S nesting check
extern uint64_t dm_gate_top[GATE_SLOTS];
extern const uint8_t dm_gate_stubs[];
static pthread_mutex_t g_gate_lock = PTHREAD_MUTEX_INITIALIZER;
static uint16_t g_gate_free[GATE_SLOTS]; static int g_gate_nfree = -1;
static pthread_key_t g_keygslot; static pthread_once_t g_gslot_once = PTHREAD_ONCE_INIT;
#if defined(DM_CLASSIC_SHELF_LIFECYCLE)
void dm_guest_classic_drop_tls_keys(void) {
    if (g_gslot_key_ready) { pthread_key_delete(g_keygslot); g_gslot_key_ready = 0; }
    if (g_own_key_ready) { pthread_key_delete(g_keyown); g_own_key_ready = 0; }
}
#endif
#if TARGET_OS_IOS || defined(DM_TEST_GATE_RETIRE)
struct gate_mapping { struct gate_mapping *next; void *base; };
static struct gate_mapping *g_gate_mapping[GATE_SLOTS], *g_gate_retired;
int dm_guest_gate_release_drained(void) {
    unsigned dm_guest_pthreads_alive(void);
    if (dm_guest_pthreads_alive()) return 0;
    pthread_mutex_lock(&g_gate_lock);
    struct gate_mapping *retired = g_gate_retired;
    g_gate_retired = NULL;
    pthread_mutex_unlock(&g_gate_lock);
    while (retired) {
        struct gate_mapping *next = retired->next;
        munmap(retired->base, GATE_STACK_SIZE + 16384);
        free(retired);
        retired = next;
    }
    return 1;
}
#endif
static void gslot_release(void *p) {   // key destructor (pthread_exit): slot + 1
    unsigned k = (unsigned)((uintptr_t)p - 1);
    pthread_mutex_lock(&g_gate_lock);
#if TARGET_OS_IOS || defined(DM_TEST_GATE_RETIRE)
    while (g_gate_mapping[k]) {
        struct gate_mapping *m = g_gate_mapping[k];
        g_gate_mapping[k] = m->next;
        m->next = g_gate_retired; g_gate_retired = m;
    }
#endif
    g_gate_free[g_gate_nfree++] = (uint16_t)k;
    pthread_mutex_unlock(&g_gate_lock);
}
static void gslot_key_init(void) {
    if (pthread_key_create(&g_keygslot, gslot_release)) die("cannot create the gate slot key");
#if defined(DM_CLASSIC_SHELF_LIFECYCLE)
    g_gslot_key_ready = 1;
#endif
    if ((uintptr_t)dm_gate_top & 0xfff) die("gate stack table %p is not page-aligned (entry.S stubs address it with adrp alone)", (void *)dm_gate_top);
}
void dm_gate_nested(uint64_t sp) { die("SVC gate entered on its own gate stack (sp %#llx): a gate handler ran guest code", (unsigned long long)sp); }
__attribute__((noinline)) void guest_gate_stack(int own_stack) {
    pthread_once(&g_gslot_once, gslot_key_init);
    uint8_t *top;
#if TARGET_OS_IOS || defined(DM_TEST_GATE_RETIRE)
    struct gate_mapping *mapping = NULL;
#endif
    if (own_stack) top = (uint8_t *)__builtin_frame_address(0);   // this function's frame record: everything above it is the caller's frame, everything below is free once the guest runs elsewhere
    else {
        uint8_t *m = mmap(NULL, GATE_STACK_SIZE + 16384, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (m == MAP_FAILED || mprotect(m, 16384, PROT_NONE)) die("cannot map a gate stack (errno %d)", errno);   // guard page at the bottom
        top = m + 16384 + GATE_STACK_SIZE;
#if TARGET_OS_IOS || defined(DM_TEST_GATE_RETIRE)
        mapping = malloc(sizeof *mapping);
        if (!mapping) die("cannot track the mapped gate stack");
        mapping->base = m;
#endif
    }
    uintptr_t prev = (uintptr_t)pthread_getspecific(g_keygslot);
    int k;
    if (prev) k = (int)prev - 1;   // set again on the same thread: keep its slot
    else {
        pthread_mutex_lock(&g_gate_lock);
        if (g_gate_nfree < 0) { g_gate_nfree = 0; for (int i = GATE_SLOTS - 1; i >= 0; i--) g_gate_free[g_gate_nfree++] = (uint16_t)i; }
        if (!g_gate_nfree) die("more than %d threads with a gate stack", GATE_SLOTS);
        k = g_gate_free[--g_gate_nfree];
        pthread_mutex_unlock(&g_gate_lock);
        pthread_setspecific(g_keygslot, (void *)(uintptr_t)(k + 1));
    }
#if TARGET_OS_IOS || defined(DM_TEST_GATE_RETIRE)
    if (mapping) {
        pthread_mutex_lock(&g_gate_lock);
        mapping->next = g_gate_mapping[k]; g_gate_mapping[k] = mapping;
        pthread_mutex_unlock(&g_gate_lock);
    }
#endif
    dm_gate_top[k] = (uint64_t)(uintptr_t)top & ~15ull;
    pthread_setspecific(g_keygate, (void *)(dm_gate_stubs + 16 * k));
}
