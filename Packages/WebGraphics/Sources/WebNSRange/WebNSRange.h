// `NSRange` as C declares it, for wasm with the Objective-C runtime only (WebFoundation imports
// this module under `os(WASI) && canImport(ObjectiveC)`; elsewhere it is a Swift struct or
// Foundation's). A C struct is representable in Objective-C, so an `@objc` method or protocol
// requirement can take or return one (Highlightr's `HighlightDelegate`); WebFoundation adds
// the Swift API on top.
#ifndef WEB_NS_RANGE_H
#define WEB_NS_RANGE_H

#if defined(__wasi__)

/// A portion of a series, such as a string's UTF-16 units: where it starts and how long it is
/// (`long`, the width of Swift's `Int` here, so both members import as `Int`).
typedef struct __attribute__((swift_attr("@Sendable"))) _NSRange {
    long location;
    long length;
} NSRange;

#endif

#endif
