// The C half of `imp_implementationWithBlock` on wasm (WebFoundation, BlockImplementations.swift).
//
// The Objective-C runtime SDK of decision 0023 has no `imp_implementationWithBlock`: Apple's
// makes a trampoline at run time, and WebAssembly cannot make code at run time. This module
// keeps a fixed pool of trampolines instead, one set for each shape of call a block can take
// (its return class and how many arguments follow the receiver). A trampoline is the method:
// called as `imp(self, _cmd, args...)`, it calls its block as `invoke(block, self, args...)`.
#ifndef WEB_OBJC_BLOCKS_H
#define WEB_OBJC_BLOCKS_H

/// A trampoline that calls `block`, an Objective-C block object, or NULL with `*reason` saying
/// why there is none (not a block, a shape this pool has no trampolines for, the pool is full).
void *_Nullable _webIMPWithBlock(const void *_Nonnull block, const char *_Nullable *_Nonnull reason);
/// Frees a trampoline from `_webIMPWithBlock` for another block: 1 when `imp` was one, else 0.
int _webRemoveIMPBlock(const void *_Nonnull imp);

#endif
