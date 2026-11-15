// The geometry structs as C declares them, for wasm with the Objective-C runtime only
// (WebGraphics imports this module under `os(WASI) && canImport(ObjectiveC)`; elsewhere the
// structs are Swift's or CoreGraphics's). A C struct is representable in Objective-C, so an
// `@objc` method or block can take or return one; WebGraphics adds the Swift API on top.
#ifndef WEB_CG_GEOMETRY_H
#define WEB_CG_GEOMETRY_H

#if defined(__wasi__)

#define WEB_CG_SENDABLE __attribute__((swift_attr("@Sendable")))

/// A point in a two-dimensional coordinate system (`CGFloat` is a `double` on wasm).
struct WEB_CG_SENDABLE CGPoint {
    double x;
    double y;
};
typedef struct CGPoint CGPoint;

/// A width and a height.
struct WEB_CG_SENDABLE CGSize {
    double width;
    double height;
};
typedef struct CGSize CGSize;

/// The location and dimensions of a rectangle.
struct WEB_CG_SENDABLE CGRect {
    CGPoint origin;
    CGSize size;
};
typedef struct CGRect CGRect;

#endif

#endif
