import UIKit

extension UIBezierPath {
	static func trueRoundedRect(rect: CGRect, cornerRadius: CGFloat) -> UIBezierPath {
		let path = CGMutablePath()
		let start = CGPoint(x: rect.midX, y: rect.minY)
		path.move(to: start)
		path.addArc(tangent1End: rect.topRight, tangent2End: rect.bottomRight, radius: cornerRadius)
		path.addArc(tangent1End: rect.bottomRight, tangent2End: rect.bottomLeft, radius: cornerRadius)
		path.addArc(tangent1End: rect.bottomLeft, tangent2End: rect.topLeft, radius: cornerRadius)
		path.addArc(tangent1End: rect.topLeft, tangent2End: start, radius: cornerRadius)
		path.closeSubpath()
		return UIBezierPath(cgPath: path)
	}
}
