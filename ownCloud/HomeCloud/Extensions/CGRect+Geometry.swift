import UIKit

extension CGRect {
	var topRight: CGPoint { CGPoint(x: maxX, y: minY) }
	var topLeft: CGPoint { CGPoint(x: minX, y: minY) }
	var bottomRight: CGPoint { CGPoint(x: maxX, y: maxY) }
	var bottomLeft: CGPoint { CGPoint(x: minX, y: maxY) }
}
