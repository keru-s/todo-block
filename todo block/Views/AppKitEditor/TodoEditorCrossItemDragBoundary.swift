import CoreGraphics

enum TodoEditorCrossItemDragBoundary {
    static func hasExitedTextSelectionRegion(
        at location: CGPoint,
        rowFrame: CGRect,
        titleFrame: CGRect,
        horizontalProtection: CGFloat
    ) -> Bool {
        guard rowFrame.minY <= location.y, location.y <= rowFrame.maxY else {
            return true
        }

        let leadingBoundary = titleFrame.minX - horizontalProtection
        let trailingBoundary = titleFrame.maxX + horizontalProtection
        return location.x < leadingBoundary || trailingBoundary < location.x
    }
}
