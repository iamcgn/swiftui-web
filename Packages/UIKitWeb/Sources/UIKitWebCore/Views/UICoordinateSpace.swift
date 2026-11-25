// UICoordinateSpace (Docs/elements/UIKit/UIView.md, "Coordinate spaces"): something points and
// rectangles convert into and out of. A view is one; the screen's `coordinateSpace` and
// `fixedCoordinateSpace` are the window's coordinates, as the page's window fills the screen
// and never rotates under the app.

/// Converts points and rectangles to and from another coordinate space.
@preconcurrency @MainActor
public protocol UICoordinateSpace: AnyObject {
    var bounds: CGRect { get }
    func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint
    func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint
    func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect
    func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect
}

// A view passed where either a view or a coordinate space is taken goes to the view form: each
// conversion below names its optional view form, so the two never call each other in a loop.
extension UIView: UICoordinateSpace {
    public func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint {
        if let view = coordinateSpace as? UIView { return convert(point, to: view as UIView?) }
        return coordinateSpace.convert(convert(point, to: nil as UIView?), from: UIScreen.main.coordinateSpace)
    }

    public func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint {
        if let view = coordinateSpace as? UIView { return convert(point, from: view as UIView?) }
        return convert(coordinateSpace.convert(point, to: UIScreen.main.coordinateSpace), from: nil as UIView?)
    }

    public func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect {
        if let view = coordinateSpace as? UIView { return convert(rect, to: view as UIView?) }
        return coordinateSpace.convert(convert(rect, to: nil as UIView?), from: UIScreen.main.coordinateSpace)
    }

    public func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect {
        if let view = coordinateSpace as? UIView { return convert(rect, from: view as UIView?) }
        return convert(coordinateSpace.convert(rect, to: UIScreen.main.coordinateSpace), from: nil as UIView?)
    }
}

/// The screen's coordinates: the window's, with the screen's bounds.
@preconcurrency @MainActor
final class UIScreenCoordinateSpace: UICoordinateSpace {
    unowned let screen: UIScreen
    init(screen: UIScreen) { self.screen = screen }

    var bounds: CGRect { screen.bounds }

    func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint {
        if coordinateSpace is UIScreenCoordinateSpace { return point }
        if let view = coordinateSpace as? UIView { return view.convert(point, from: nil as UIView?) }
        return coordinateSpace.convert(point, from: self)
    }

    func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint {
        if coordinateSpace is UIScreenCoordinateSpace { return point }
        if let view = coordinateSpace as? UIView { return view.convert(point, to: nil as UIView?) }
        return coordinateSpace.convert(point, to: self)
    }

    func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect {
        if coordinateSpace is UIScreenCoordinateSpace { return rect }
        if let view = coordinateSpace as? UIView { return view.convert(rect, from: nil as UIView?) }
        return coordinateSpace.convert(rect, from: self)
    }

    func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect {
        if coordinateSpace is UIScreenCoordinateSpace { return rect }
        if let view = coordinateSpace as? UIView { return view.convert(rect, to: nil as UIView?) }
        return coordinateSpace.convert(rect, to: self)
    }
}

extension UIScreen {
    /// The screen's coordinate space, which turns with the interface (here, the window's).
    public var coordinateSpace: any UICoordinateSpace { screenCoordinateSpace }
    /// The screen's coordinate space in its portrait-up orientation (here, the same).
    public var fixedCoordinateSpace: any UICoordinateSpace { screenCoordinateSpace }
}
