// UIKit's option sets as C declares them, for builds with the Objective-C runtime only
// (UIKitWebCore imports this module under `canImport(ObjectiveC)`; elsewhere the types are
// Swift's). Swift imports a flag enum as an `OptionSet` struct, as it imports UIKit's
// NS_OPTIONS, and such a type is representable in Objective-C: an `@objc` protocol method can
// then take or return it (UINavigationControllerDelegate's
// `navigationControllerSupportedInterfaceOrientations(_:)`). A Swift option set never can.
#ifndef UIKIT_WEB_C_TYPES_H
#define UIKIT_WEB_C_TYPES_H

#define UIKIT_WEB_OPTIONS __attribute__((flag_enum, enum_extensibility(open), swift_attr("@Sendable")))

/// The orientations a view controller supports.
typedef enum UIKIT_WEB_OPTIONS UIInterfaceOrientationMask : unsigned long UIInterfaceOrientationMask;
enum UIInterfaceOrientationMask : unsigned long {
    UIInterfaceOrientationMaskPortrait = 1UL << 1,
    UIInterfaceOrientationMaskPortraitUpsideDown = 1UL << 2,
    UIInterfaceOrientationMaskLandscapeRight = 1UL << 3,
    UIInterfaceOrientationMaskLandscapeLeft = 1UL << 4,
    UIInterfaceOrientationMaskLandscape = (1UL << 3) | (1UL << 4),
    UIInterfaceOrientationMaskAll = (1UL << 1) | (1UL << 2) | (1UL << 3) | (1UL << 4),
    UIInterfaceOrientationMaskAllButUpsideDown = (1UL << 1) | (1UL << 3) | (1UL << 4),
};

#endif
