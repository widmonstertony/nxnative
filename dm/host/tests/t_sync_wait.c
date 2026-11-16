// WaitSynchronization through real SVCs. Hold G across notification and clear
// to make the lost-notification window deterministic, without scheduler sleeps.
#define DM_TEST_GUEST_EXIT_WATCH 1
#include "../hle_thread.c"
#include <assert.h>
#include <sys/wait.h>
#include <unistd.h>

enum { TEST_GUEST_BASE = 0x0eed000, TEST_GUEST_PC = TEST_GUEST_BASE + 4, TEST_PATCH = 0x4000, TEST_RETURN = 0x0bbe000 };
module_t *module_of(const void *p) {
    static module_t m = {.base = (void *)TEST_GUEST_BASE, .text_end = 0x1000, .patch_off = TEST_PATCH, .patch_len = 0x1000, .size = TEST_PATCH + 0x1000};
    return (uintptr_t)p - TEST_GUEST_BASE < m.size ? &m : NULL;
}

typedef struct { uint32_t write, read; } ends_t;
typedef struct {
    thr_t *thread;
    pthread_t pt;
    uint32_t handles[3];
    int count;
    uint64_t result, index;
} waiter_t;

static ends_t event_new(void) {
    uint64_t r[32] = {0}; assert(svc_thread(0x45, r) && !r[0]);
    return (ends_t){r[1], r[2]};
}
static void close_handle(uint32_t h) {
    uint64_t r[32] = {h}; assert(svc_thread(0x16, r) && !r[0]);
}
static void event_close(ends_t e) { close_handle(e.write); close_handle(e.read); }
static uint64_t wait_now(uint32_t *handles, int n, int64_t timeout, uint64_t *index) {
    uint64_t r[32] = {0, (uint64_t)handles, (uint32_t)n, (uint64_t)timeout};
    assert(svc_thread(0x18, r)); if (index) *index = r[1]; return r[0];
}
static thr_t *new_thread(void) {
    thr_t *t = calloc(1, sizeof *t); assert(t);
    pthread_cond_init(&t->cv, NULL); pthread_cond_init(&t->pcv, NULL);
    t->started = 1; t->prio = 44; t->mask = 7;
    g_lock();
    t->handle = h_new(O_THREAD, t); t->all = g_all; g_all = t;
    g_unlock();
    return t;
}
static void *wait_body(void *arg) {
    waiter_t *w = arg;
    pthread_setspecific(g_keythr, w->thread);
    w->result = wait_now(w->handles, w->count, 500000000, &w->index);
    thread_exit(w->thread);
    return NULL;
}
static void wait_start(waiter_t *w) {
    w->thread = new_thread();
    assert(!pthread_create(&w->pt, NULL, wait_body, w));
    uint64_t deadline = now_ns() + 2000000000;
    for (;;) {
        g_lock(); int waiting = w->thread->wkind == 4; g_unlock();
        if (waiting) return;
        assert(now_ns() < deadline); sched_yield();
    }
}
static void wait_finish(waiter_t *w, uint64_t result, unsigned index) {
    assert(!pthread_join(w->pt, NULL));
    if (w->result != result || (!result && w->index != index))
        fprintf(stderr, "wait returned %#llx / %llu; expected %#llx / %u\n", w->result, w->index, result, index);
    assert(w->result == result && (result || w->index == index));
    close_handle(w->thread->handle);
}
// Caller holds G: this is the signal operation shared by SVC11 and host service
// producers. Keeping the lock lets the test clear/close before waiters resume.
static void signal_locked(uint32_t write) {
    event_t *e = h_peek(write, O_EVENT_W); assert(e);
    e->signaled = 1; wake_sync_waiters(e);
}
static void framing(void) {
    ends_t e = event_new();
    uint64_t r[32] = {e.write}; assert(svc_thread(0x11, r) && !r[0]);
    uint32_t handles[65] = {e.read, 0};
    assert(wait_now(handles, 2, 0, NULL) == R_BAD_HANDLE);
    handles[1] = e.write; assert(wait_now(handles, 2, 0, NULL) == R_BAD_HANDLE);
    handles[1] = H_CUR_THREAD; assert(wait_now(handles, 2, 0, NULL) == R_BAD_HANDLE);
    assert(wait_now(handles, -1, 0, NULL) == 0xee01);
    assert(wait_now(handles, 65, 0, NULL) == 0xee01);
    assert(wait_now(NULL, 0, 0, NULL) == R_TIMEOUT);
    handles[1] = e.read; uint64_t index;
    assert(!wait_now(handles, 2, 0, &index) && index == 0);
    for (int i = 0; i < 64; i++) handles[i] = e.read;
    assert(!wait_now(handles, 64, 0, &index) && index == 0);
    // An already signaled object and a poll both precede pending cancellation.
    r[0] = H_CUR_THREAD; assert(svc_thread(0x19, r) && !r[0]);
    assert(!wait_now(handles, 1, -1, NULL));
    r[0] = e.read; assert(svc_thread(0x12, r) && !r[0]);
    assert(wait_now(handles, 1, 0, NULL) == R_TIMEOUT);
    assert(wait_now(handles, 1, -1, NULL) == R_CANCELLED);
    assert(wait_now(handles, 1, 0, NULL) == R_TIMEOUT);
    assert(wait_now(handles, 1, 100000, NULL) == R_TIMEOUT);
    g_lock();
    assert(((event_t *)h_peek(e.read, O_EVENT_R))->refs == 2);
    g_unlock();
    event_close(e);
}
static uint64_t event_svc(int num, uint32_t handle) {
    uint64_t r[32] = {handle}; assert(svc_thread(num, r)); return r[0];
}
static void endpoints(void) {
    ends_t e = event_new();
    assert(wait_now(&e.read, 1, 0, NULL) == R_TIMEOUT);
    assert(event_svc(0x11, e.read) == R_BAD_HANDLE);
    assert(event_svc(0x17, e.write) == R_BAD_HANDLE);
    assert(event_svc(0x17, cur()->handle) == R_BAD_HANDLE);
    assert(event_svc(0x17, H_CUR_THREAD) == R_BAD_HANDLE);
    assert(event_svc(0x17, e.read) == R_BAD_STATE);
    assert(!event_svc(0x12, e.write));
    assert(!event_svc(0x11, e.write));
    assert(!wait_now(&e.read, 1, 0, NULL));
    assert(!wait_now(&e.read, 1, 0, NULL)); // Waiting does not clear a kernel event.
    assert(!event_svc(0x12, e.read));
    assert(wait_now(&e.read, 1, 0, NULL) == R_TIMEOUT);
    assert(!event_svc(0x11, e.write));
    assert(!event_svc(0x17, e.read));
    assert(event_svc(0x17, e.read) == R_BAD_STATE);
    // Allocator final release signals, then closes the producer's endpoint.
    assert(!event_svc(0x11, e.write)); close_handle(e.write);
    assert(!wait_now(&e.read, 1, 0, NULL)); close_handle(e.read);
}
static void signal_then_clear(void) {
    ends_t a = event_new(), b = event_new();
    waiter_t first = {.handles = {a.read, b.read, b.read}, .count = 3};
    waiter_t second = {.handles = {b.read}, .count = 1};
    wait_start(&first); wait_start(&second);
    g_lock();
    signal_locked(b.write);
    ((event_t *)h_peek(b.write, O_EVENT_W))->signaled = 0;
    g_unlock();
    wait_finish(&first, 0, 1); wait_finish(&second, 0, 0);
    assert(wait_now(&b.read, 1, 0, NULL) == R_TIMEOUT);
    event_close(a); event_close(b);
}
static void close_and_reuse(void) {
    ends_t old = event_new();
    waiter_t w = {.handles = {old.read}, .count = 1}; wait_start(&w);
    close_handle(old.read);
    ends_t replacement = event_new(); assert(replacement.write == old.read);
    g_lock();
    signal_locked(replacement.write); assert(w.thread->wkind == 4);
    signal_locked(old.write);
    g_unlock();
    close_handle(old.write);
    wait_finish(&w, 0, 0); event_close(replacement);
}
static void handle_array_snapshot(void) {
    ends_t old = event_new(), replacement = event_new();
    waiter_t w = {.handles = {old.read}, .count = 1}; wait_start(&w);
    g_lock();
    w.handles[0] = replacement.read;
    signal_locked(replacement.write); assert(w.thread->wkind == 4);
    signal_locked(old.write);
    g_unlock();
    wait_finish(&w, 0, 0); event_close(old); event_close(replacement);
}
static void cancellation_and_release(void) {
    ends_t e = event_new();
    waiter_t w = {.handles = {e.read, e.read}, .count = 2}; wait_start(&w);
    close_handle(e.write); close_handle(e.read);
    uint64_t r[32] = {w.thread->handle}; assert(svc_thread(0x19, r) && !r[0]);
    wait_finish(&w, R_CANCELLED, 0);
    w = (waiter_t){.count = 0}; wait_start(&w);
    r[0] = w.thread->handle; assert(svc_thread(0x19, r) && !r[0]);
    wait_finish(&w, R_CANCELLED, 0);
}
static pthread_mutex_t exit_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t exit_cv = PTHREAD_COND_INITIALIZER;
static int may_exit;
static void *exit_body(void *arg) {
    thr_t *t = arg; pthread_setspecific(g_keythr, t);
    pthread_mutex_lock(&exit_mu);
    while (!may_exit) pthread_cond_wait(&exit_cv, &exit_mu);
    pthread_mutex_unlock(&exit_mu); thread_exit(t); return NULL;
}
static void closed_thread_wait(void) {
    thr_t *target = new_thread(); pthread_t pt;
    assert(!pthread_create(&pt, NULL, exit_body, target));
    waiter_t w = {.handles = {target->handle, target->handle}, .count = 2}; wait_start(&w);
    uint32_t old_handle = target->handle; close_handle(old_handle);
    ends_t replacement = event_new(); assert(replacement.write == old_handle);
    pthread_mutex_lock(&exit_mu); may_exit = 1; pthread_cond_signal(&exit_cv); pthread_mutex_unlock(&exit_mu);
    assert(!pthread_join(pt, NULL));
    wait_finish(&w, 0, 0); event_close(replacement);
}
// GetThreadId / GetThreadCoreMask on a handle another thread closes: the close frees an exited
// thread at once, so a lookup outside G read freed memory (ASan: heap-use-after-free; TSan: race).
static _Atomic int query_stop;
static void *query_body(void *arg) {
    uint32_t h = (uint32_t)(uintptr_t)arg;
    for (;;) {
        uint64_t r[32] = {0, h}; assert(svc_thread(0x25, r));
        if (r[0] == R_BAD_HANDLE) break;
        assert(!r[0] && r[1] >= 0x51);
        uint64_t m[32] = {0, 0, h}; assert(svc_thread(0x0E, m));
        if (m[0] == R_BAD_HANDLE) break;
        assert(!m[0] && m[2] == 7);
    }
    return NULL;
}
static void query_close(void) {
    for (int round = 0; round < 200; round++) {
        thr_t *t = new_thread(); t->exited = 1; t->id = 0x51 + round;
        pthread_t pt; assert(!pthread_create(&pt, NULL, query_body, (void *)(uintptr_t)t->handle));
        for (int i = 0; i < round % 8; i++) sched_yield();
        close_handle(t->handle);
        assert(!pthread_join(pt, NULL));
    }
}
// SetThreadCoreMask from another thread while the target reads its own core without G: each read is the
// core before or after, and the fields are stored and loaded atomically (TSan reports plain accesses).
static void *core_body(void *arg) {
    pthread_setspecific(g_keythr, arg);
    while (!query_stop) {
        uint64_t r[32] = {0}; assert(svc_thread(0x10, r));
        assert(r[0] == 0 || r[0] == 2);
    }
    return NULL;
}
static void core_mask(void) {
    thr_t *t = new_thread(); t->core = 0; t->mask = 1; pthread_t pt;
    query_stop = 0; assert(!pthread_create(&pt, NULL, core_body, t));
    for (int i = 0; i < 20000; i++) {
        uint64_t r[32] = {t->handle, (uint64_t)-3, i & 1 ? 1 : 4}; assert(svc_thread(0x0F, r) && !r[0]);
    }
    query_stop = 1; assert(!pthread_join(pt, NULL));
    g_lock(); t->exited = 1; g_unlock();
    close_handle(t->handle);
}
// CloseHandle before StartThread: the real CreateThread's pthread waits for the start, and must end
// without entering guest code (the stub dm_thread_enter aborts), freeing the object and its thread-limit slot.
static void closed_unstarted(void) {
    int base = thr_limit_used();
    for (int i = 0; i < 24; i++) {
        uint64_t r[32] = {0, 0x1000, 0, 0x2000, 44, 0}; assert(svc_thread(0x08, r) && !r[0]);
        if (i & 1) sched_yield();   // closes both before and after the pthread reaches its wait
        close_handle((uint32_t)r[1]);
    }
    uint64_t deadline = now_ns() + 2000000000;
    for (;;) {
        int handles, live, objects; thr_counts(&handles, &live, &objects);
        if (objects == 1 && thr_limit_used() == base) break;
        assert(now_ns() < deadline); usleep(1000);
    }
}

static pthread_key_t exiting_key;
static _Atomic int exiting_armed, exiting_registered, exiting_destructor, exiting_release;
static void exit_destructor(void *ignored) {
    (void)ignored;
    atomic_store(&exiting_destructor, 1);
    while (!atomic_load(&exiting_release)) sched_yield();
}
static void *exit_watch_body(void *arg) {
    while (!atomic_load(&exiting_armed)) sched_yield();
    exit_watch_current(1);
    assert(!pthread_setspecific(exiting_key, arg));
    atomic_store(&exiting_registered, 1);
    return NULL;
}
static void exit_watch_covers_destructors(void) {
    uint64_t deadline = now_ns() + 2000000000;
    // Let the detached workers from the closed-unstarted test finish exiting.
    while (dm_guest_pthreads_alive() > 1) { assert(now_ns() < deadline); sched_yield(); }
    assert(dm_guest_pthreads_alive() == 1);
    assert(!pthread_key_create(&exiting_key, exit_destructor));
    exit_watch_pending();
    pthread_t worker;
    assert(!pthread_create(&worker, NULL, exit_watch_body, &worker));
    // A child still on its way to thread_main must also block reset.
    assert(dm_guest_pthreads_alive() == 2);
    atomic_store(&exiting_armed, 1);
    while (!atomic_load(&exiting_registered) || !atomic_load(&exiting_destructor)) {
        assert(now_ns() < deadline); sched_yield();
    }
    assert(dm_guest_pthreads_alive() == 2);
    atomic_store(&exiting_release, 1);
    assert(!pthread_join(worker, NULL));
    while (dm_guest_pthreads_alive() != 1) { assert(now_ns() < deadline); sched_yield(); }
    assert(!pthread_key_delete(exiting_key));
}

typedef struct {
    thr_t *t;
    int native_frame;
    atomic_int ready, stop, resumed;
} retire_test;

static void *retire_worker(void *arg) {
    retire_test *test = arg;
    thr_t *t = test->t;
    exit_watch_current(1);
    pthread_setspecific(g_keythr, t);
    _Alignas(16) uint64_t frames[4] = {0, TEST_GUEST_PC, 0, TEST_RETURN};
    uint64_t regs[100] = {0};
    frames[0] = (uintptr_t)&frames[2];
    regs[99] = (uintptr_t)frames;
    t->entered = 1;
    t->svc_pc = 4; // original gate location is module-relative
    t->retirement_root = TEST_RETURN;
    t->retirement_stack_top = (uintptr_t)(frames + 4);
    atomic_store(&t->svc_regs, regs);
    regs[30] = TEST_GUEST_PC;
    assert(!retire_stack_root(t)); // a plain guest PC isn't a registered gate return
    regs[30] = TEST_GUEST_BASE + TEST_PATCH + 8;
    assert(retire_stack_root(t));
    frames[0] = (uintptr_t)frames; // cycle
    assert(!retire_stack_root(t));
    frames[0] = (uintptr_t)(frames + 4); // past stack
    assert(!retire_stack_root(t));
    frames[0] = (uintptr_t)&frames[2];
    frames[3] = 0x1234; // native callback in the chain
    assert(!retire_stack_root(t));
    if (!test->native_frame) frames[3] = TEST_RETURN;
    atomic_store(&test->ready, 1);
    while (!atomic_load(&test->stop)) {
        g_lock();
        if (atomic_load(&g_retire_phase) == RETIRE_GATHER) {
            retire_checkpoint_locked(t);
            atomic_store(&test->resumed, 1);
        }
        g_unlock();
        sched_yield();
    }
    thread_exit(t);
    return NULL;
}

static void retirement_boundaries(int managed) {
    // The coordinator is a shell thread, excluded from the guest registry.
    assert(!pthread_key_create(&g_keythr, NULL));
    retire_test clean = {.t = new_thread()}, native = {.t = new_thread(), .native_frame = 1};
    pthread_t a, b;
    exit_watch_pending(); assert(!pthread_create(&a, NULL, retire_worker, &clean));
    exit_watch_pending(); assert(!pthread_create(&b, NULL, retire_worker, &native));
    while (!atomic_load(&clean.ready) || !atomic_load(&native.ready)) sched_yield();
    assert(!dm_guest_retire_at_boundaries(100)); // native callback blocks retirement
    assert(dm_guest_pthreads_alive() == 2);
    while (!atomic_load(&clean.resumed)) sched_yield(); // pre-commit timeout released the parked guest
    if (managed) {
        // A coordinator with a real stop hook can commit the guest boundary
        // without pretending that the managed native callback has exited.
        g_lock(); native.t->host_owned = 1; g_unlock();
        assert(dm_guest_classic_retire(1000));
        assert(!pthread_join(a, NULL));
        uint64_t deadline = now_ns() + 2000000000;
        while (dm_guest_pthreads_alive() > 1) { assert(now_ns() < deadline); sched_yield(); }
        assert(dm_guest_pthreads_alive() == 1);
        uint64_t regs[104] = {0};
        assert(svc_thread(0x08, regs) && regs[0] == R_BAD_STATE && !regs[1]);
    }
    atomic_store(&native.stop, 1);
    assert(!pthread_join(b, NULL));
    if (!managed) {
        assert(dm_guest_retire_at_boundaries(1000));
        assert(!pthread_join(a, NULL));
    }
    uint64_t deadline = now_ns() + 2000000000;
    while (dm_guest_pthreads_alive()) { assert(now_ns() < deadline); sched_yield(); }
    g_lock();
    assert(clean.t->exited && native.t->exited);
    thr_free(clean.t); thr_free(native.t);
    g_unlock();
    assert(!pthread_key_delete(g_keythr));
}

int main(int argc, char **argv) {
    alarm(10);
    if (argc == 1 || !strcmp(argv[1], "retirement") || !strcmp(argv[1], "managed-retirement")) {
        // Keep committed shutdown in a separate process from unrelated SVC cases.
        if (argc == 1) {
            const char *modes[] = {"retirement", "managed-retirement"};
            for (unsigned i = 0; i < sizeof modes / sizeof *modes; i++) {
                pid_t p = fork();
                assert(p >= 0);
                if (!p) { execl(argv[0], argv[0], modes[i], NULL); _exit(127); }
                int status;
                assert(waitpid(p, &status, 0) == p && WIFEXITED(status) && !WEXITSTATUS(status));
            }
        } else {
            retirement_boundaries(!strcmp(argv[1], "managed-retirement"));
            printf("PASS: %s\n", argv[1]);
            return 0;
        }
    }
    svc_thread_main_init();
    const char *names[] = {"framing", "endpoints", "signal-clear", "close-reuse", "snapshot", "cancel-release", "thread-close", "query-close", "core-mask", "closed-unstarted", "exit-watch"};
    void (*tests[])(void) = {framing, endpoints, signal_then_clear, close_and_reuse, handle_array_snapshot, cancellation_and_release, closed_thread_wait, query_close, core_mask, closed_unstarted, exit_watch_covers_destructors};
    for (unsigned i = 0; i < sizeof tests / sizeof *tests; i++) {
        if (argc > 1 && strcmp(argv[1], names[i])) continue;
        tests[i](); printf("PASS: %s\n", names[i]);
        int handles, live, objects; thr_counts(&handles, &live, &objects);
        assert(handles == 1 && live == 1 && objects == 1);
    }
    return 0;
}
