/* Non-game x86 correctness probe for the optional BoxedWine scalar JIT. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <xmmintrin.h>
#include <emmintrin.h>
#include <mmintrin.h>

static unsigned passed, failed;
#define CHECK(v) do { if (v) ++passed; else { ++failed; printf("FAIL line %d\n", __LINE__); } } while (0)
static volatile uint32_t initial = 0x12345678u;
static volatile float lanes[4] = {1, 2, 3, 4};
static volatile short packed[4] = {-5, 128, 300, 255};

int main(void) {
    puts("TON_CPU_BEGIN");
    uint32_t value = initial;
    for (unsigned i = 0; i < 1000000; ++i) value = value * 1664525u + 1013904223u;
    CHECK(value == 0xa16b61b8u); /* independently generated modulo-2^32 reference */
    for (unsigned repeat = 0; repeat < 256; ++repeat) {
        uint32_t carry = 0xffffffffu, upper = 0x1234;
        __asm__ volatile("addl $1, %0; adcl $0, %1" : "+r"(carry), "+r"(upper) :: "cc");
        CHECK(carry == 0 && upper == 0x1235);
        char from[64], to[64];
        for (unsigned i = 0; i < 64; ++i) from[i] = (char)(i ^ repeat);
        memset(to, 0, sizeof(to));
        char *s = from, *d = to; unsigned length = sizeof(from);
        __asm__ volatile("cld; rep movsb" : "+S"(s), "+D"(d), "+c"(length) :: "memory", "cc");
        CHECK(memcmp(from, to, sizeof(to)) == 0);
        __m128 x = _mm_loadu_ps((const float *)lanes);
        x = _mm_mul_ps(_mm_add_ps(x, _mm_set1_ps(1)), _mm_set1_ps(2));
        float out[4]; _mm_storeu_ps(out, x);
        CHECK(out[0] == 4 && out[1] == 6 && out[2] == 8 && out[3] == 10);
        __m128i a = _mm_set_epi32(4, 3, 2, 1);
        __m128i b = _mm_loadu_si128((const __m128i *)&a);
        b = _mm_add_epi32(b, _mm_set1_epi32((int)repeat));
        int result[4]; _mm_storeu_si128((__m128i *)result, b);
        CHECK(result[0] == 1 + (int)repeat && result[3] == 4 + (int)repeat);
        __m64 words; memcpy(&words, (const void *)packed, 8);
        __m64 bytes = _mm_packs_pu16(words, words);
        unsigned char bytes_out[8]; memcpy(bytes_out, &bytes, 8); _mm_empty();
        CHECK(bytes_out[0] == 0 && bytes_out[1] == 128 && bytes_out[2] == 255 && bytes_out[3] == 255);
        double two;
        __asm__ volatile("fld1; fld1; faddp; fstpl %0" : "=m"(two) :: "st");
        CHECK(two == 2.0);
    }
    printf("Summary: %u passed, %u failed, 0 skipped\n", passed, failed);
    return failed != 0;
}
