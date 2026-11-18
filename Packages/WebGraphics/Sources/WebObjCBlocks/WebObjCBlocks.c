// imp_implementationWithBlock's trampolines on wasm (include/WebObjCBlocks.h says why a pool).
//
// A block object is laid out as the Block ABI specifies (clang's "Block Implementation
// Specification"): its isa, flags, a reserved word, the invoke function and a descriptor, which
// holds the block's Objective-C type signature when the flags say it has one. The signature
// gives the call's shape: the return type, the block itself, the receiver, then the method's
// arguments. On wasm32 every pointer, object, selector, class and integer up to 32 bits is one
// i32, so a shape is its return class (none, i32, i64, f32, f64) and how many i32 arguments
// follow the receiver; each shape has its own trampolines, as an indirect call's type must match
// the function it reaches.
#include "WebObjCBlocks.h"

#if defined(__wasm__)
#include <stddef.h>
#include <stdint.h>

typedef void *word;

struct web_block_descriptor {
    unsigned long reserved;
    unsigned long size;
    // then copy and dispose helpers (BLOCK_HAS_COPY_DISPOSE), then the signature (BLOCK_HAS_SIGNATURE)
};

struct web_block {
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    const struct web_block_descriptor *descriptor;
};

enum { BLOCK_HAS_COPY_DISPOSE = 1 << 25, BLOCK_HAS_SIGNATURE = 1 << 30 };

// The runtime's block classes (its BlocksRuntime). Weak, so a module without the runtime links.
extern void *_NSConcreteGlobalBlock[] __attribute__((weak));
extern void *_NSConcreteMallocBlock[] __attribute__((weak));

// A value's class in a call, and so a trampoline's return class.
enum { CLASS_VOID, CLASS_I32, CLASS_I64, CLASS_F32, CLASS_F64, CLASS_COUNT, CLASS_OTHER = CLASS_COUNT };

#define SLOTS 8
#define MAX_ARGUMENTS 5
#define SHAPES (CLASS_COUNT * (MAX_ARGUMENTS + 1))
#define SHAPE(returns, arguments) ((returns) * (MAX_ARGUMENTS + 1) + (arguments))

// The block each trampoline calls, NULL while the trampoline is free.
static const struct web_block *blocks[SHAPES][SLOTS];

// The trampolines, `tramp_<return><arguments>_<slot>`: a method taking `arguments` words after
// `self` and `_cmd`, calling slot `slot`'s block with `self` and those words.
#define PARAMS0
#define PARAMS1 PARAMS0, word a1
#define PARAMS2 PARAMS1, word a2
#define PARAMS3 PARAMS2, word a3
#define PARAMS4 PARAMS3, word a4
#define PARAMS5 PARAMS4, word a5
#define TYPES0
#define TYPES1 TYPES0, word
#define TYPES2 TYPES1, word
#define TYPES3 TYPES2, word
#define TYPES4 TYPES3, word
#define TYPES5 TYPES4, word
#define ARGS0
#define ARGS1 ARGS0, a1
#define ARGS2 ARGS1, a2
#define ARGS3 ARGS2, a3
#define ARGS4 ARGS3, a4
#define ARGS5 ARGS4, a5

#define EACH_SLOT(M, ...) M(__VA_ARGS__, 0) M(__VA_ARGS__, 1) M(__VA_ARGS__, 2) M(__VA_ARGS__, 3) \
    M(__VA_ARGS__, 4) M(__VA_ARGS__, 5) M(__VA_ARGS__, 6) M(__VA_ARGS__, 7)

#define TRAMP_VOID(k, n)                                                                           \
    static void tramp_v##k##_##n(word self, word cmd PARAMS##k) {                                  \
        (void)cmd;                                                                                 \
        const struct web_block *block = blocks[SHAPE(CLASS_VOID, k)][n];                           \
        if (!block) __builtin_trap();                                                              \
        ((void (*)(word, word TYPES##k))block->invoke)((word)block, self ARGS##k);                 \
    }
#define TRAMP_VALUE(type, name, cls, k, n)                                                         \
    static type tramp_##name##k##_##n(word self, word cmd PARAMS##k) {                             \
        (void)cmd;                                                                                 \
        const struct web_block *block = blocks[SHAPE(cls, k)][n];                                  \
        if (!block) __builtin_trap();                                                              \
        return ((type (*)(word, word TYPES##k))block->invoke)((word)block, self ARGS##k);          \
    }
#define TRAMPS(k)                                                                                  \
    EACH_SLOT(TRAMP_VOID, k)                                                                       \
    EACH_SLOT(TRAMP_VALUE, word, i, CLASS_I32, k)                                                  \
    EACH_SLOT(TRAMP_VALUE, int64_t, j, CLASS_I64, k)                                               \
    EACH_SLOT(TRAMP_VALUE, float, f, CLASS_F32, k)                                                 \
    EACH_SLOT(TRAMP_VALUE, double, d, CLASS_F64, k)
TRAMPS(0)
TRAMPS(1)
TRAMPS(2)
TRAMPS(3)
TRAMPS(4)
TRAMPS(5)

typedef void (*function)(void);
#define REF_VOID(k, n) (function)tramp_v##k##_##n,
#define REF_VALUE(name, k, n) (function)tramp_##name##k##_##n,
#define ROW_VOID(k) { EACH_SLOT(REF_VOID, k) },
#define ROW_VALUE(name, k) { EACH_SLOT(REF_VALUE, name, k) },
#define ROWS_VALUE(name) ROW_VALUE(name, 0) ROW_VALUE(name, 1) ROW_VALUE(name, 2) ROW_VALUE(name, 3) \
    ROW_VALUE(name, 4) ROW_VALUE(name, 5)

// In SHAPE order: the return class, then the argument count.
static const function trampolines[SHAPES][SLOTS] = {
    ROW_VOID(0) ROW_VOID(1) ROW_VOID(2) ROW_VOID(3) ROW_VOID(4) ROW_VOID(5)
    ROWS_VALUE(i) ROWS_VALUE(j) ROWS_VALUE(f) ROWS_VALUE(d)
};

// One type of an Objective-C type encoding: its class in a call, and the rest of the encoding
// after it and its offset.
static const char *skip_balanced(const char *s, char open, char close) {
    int depth = 0;
    for (; *s; s++) {
        if (*s == open) depth++;
        else if (*s == close && --depth == 0) return s + 1;
    }
    return s;
}

static const char *next_type(const char *s, int *cls) {
    while (*s == 'r' || *s == 'n' || *s == 'N' || *s == 'o' || *s == 'O' || *s == 'R' || *s == 'V' || *s == 'A' || *s == 'j') s++;
    switch (*s) {
    case 'v': *cls = CLASS_VOID; s++; break;
    case 'c': case 'C': case 's': case 'S': case 'i': case 'I': case 'l': case 'L':
    case 'B': case '*': case ':': case '#':
        *cls = CLASS_I32; s++; break;
    case 'q': case 'Q': *cls = CLASS_I64; s++; break;
    case 'f': *cls = CLASS_F32; s++; break;
    case 'd': *cls = CLASS_F64; s++; break;
    case '@':
        *cls = CLASS_I32;
        s++;
        if (*s == '?') {
            s++;
            if (*s == '<') s = skip_balanced(s, '<', '>');  // a block's own signature (extended encoding)
        } else if (*s == '"') {
            s++;
            while (*s && *s != '"') s++;
            if (*s) s++;
        }
        break;
    case '^': {
        int pointee;
        s = next_type(s + 1, &pointee);
        *cls = CLASS_I32;
        return s;
    }
    case '{': *cls = CLASS_OTHER; s = skip_balanced(s, '{', '}'); break;
    case '(': *cls = CLASS_OTHER; s = skip_balanced(s, '(', ')'); break;
    case '[': *cls = CLASS_OTHER; s = skip_balanced(s, '[', ']'); break;
    default: *cls = CLASS_OTHER; return s;  // a bit field, long double, or an encoding this does not read
    }
    while (*s == '-' || (*s >= '0' && *s <= '9')) s++;
    return s;
}

/// The shape of the call `block` takes as a method, or 0 with `*reason` set.
static int shape_of(const struct web_block *block, int *returns, int *arguments, const char **reason) {
    if (!(block->flags & BLOCK_HAS_SIGNATURE) || !block->descriptor) {
        *reason = "the block has no type signature, so its arguments are unknown";
        return 0;
    }
    size_t offset = 2 * sizeof(unsigned long) + ((block->flags & BLOCK_HAS_COPY_DISPOSE) ? 2 * sizeof(void *) : 0);
    const char *s = *(const char *const *)((const char *)block->descriptor + offset);
    if (!s) {
        *reason = "the block has no type signature, so its arguments are unknown";
        return 0;
    }
    int cls;
    s = next_type(s, &cls);
    if (cls == CLASS_OTHER) {
        *reason = "the block returns a struct or another type that is not one wasm value";
        return 0;
    }
    *returns = cls;
    while (*s == 'r' || *s == 'n' || *s == 'N' || *s == 'o' || *s == 'O' || *s == 'R' || *s == 'V' || *s == 'A' || *s == 'j') s++;
    if (s[0] != '@' || s[1] != '?') {
        *reason = "the block's signature does not start with the block itself";
        return 0;
    }
    s = next_type(s, &cls);
    int count = 0;
    while (*s) {
        s = next_type(s, &cls);
        if (cls != CLASS_I32) {
            *reason = "the block takes an argument that is not a pointer, object or 32-bit integer";
            return 0;
        }
        count++;
    }
    if (count == 0) {
        *reason = "the block takes no receiver, and a method's block takes the receiver first";
        return 0;
    }
    if (count - 1 > MAX_ARGUMENTS) {
        *reason = "the block takes more arguments after the receiver than the trampolines do (5)";
        return 0;
    }
    *arguments = count - 1;
    return 1;
}

void *_webIMPWithBlock(const void *pointer, const char **reason) {
    const struct web_block *block = pointer;
    void *isa = block->isa;
    if (!isa || (isa != (void *)_NSConcreteMallocBlock && isa != (void *)_NSConcreteGlobalBlock)) {
        *reason = "the value is not a block";
        return NULL;
    }
    int returns, arguments;
    if (!shape_of(block, &returns, &arguments, reason)) return NULL;
    const struct web_block **row = blocks[SHAPE(returns, arguments)];
    for (int n = 0; n < SLOTS; n++) {
        if (!row[n]) {
            row[n] = block;
            return (void *)(uintptr_t)trampolines[SHAPE(returns, arguments)][n];
        }
    }
    *reason = "all 8 trampolines for the block's shape are in use (imp_removeBlock frees one)";
    return NULL;
}

static int find(const void *imp, int *shape, int *slot) {
    for (int s = 0; s < SHAPES; s++)
        for (int n = 0; n < SLOTS; n++)
            if ((const void *)(uintptr_t)trampolines[s][n] == imp) {
                *shape = s;
                *slot = n;
                return 1;
            }
    return 0;
}

int _webRemoveIMPBlock(const void *imp) {
    int shape, slot;
    if (!find(imp, &shape, &slot) || !blocks[shape][slot]) return 0;
    blocks[shape][slot] = NULL;
    return 1;
}
#endif
