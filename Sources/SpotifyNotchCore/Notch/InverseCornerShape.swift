import SwiftUI

/// A panel whose top corners curve *into* the notch instead of away from it.
///
/// This is the detail that separates a notch app from a black rectangle parked
/// under the camera: the concave shoulders make the panel read as milled from
/// the same piece of aluminium as the cutout, rather than floating in front of
/// it.
public struct InverseCornerShape: Shape {
    public var topRadius: CGFloat      // the concave shoulders
    public var bottomRadius: CGFloat   // the ordinary convex bottom

    public init(topRadius: CGFloat = 11, bottomRadius: CGFloat = 16) {
        self.topRadius = topRadius; self.bottomRadius = bottomRadius
    }

    /// Lets the shape morph smoothly as the panel expands.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = min(topRadius, rect.width / 2, rect.height / 2)
        let br = min(bottomRadius, rect.width / 2, rect.height / 2)

        p.move(to: CGPoint(x: rect.minX - tr, y: rect.minY))
        // Concave shoulder, curving down and inward from the menu-bar line.
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + tr, y: rect.minY),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
