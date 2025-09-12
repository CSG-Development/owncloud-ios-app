import UIKit

private var kNavSeparatorKey: UInt8 = 0

public extension UIViewController {
    private var oc_navSeparatorView: UIView? {
        get { return objc_getAssociatedObject(self, &kNavSeparatorKey) as? UIView }
        set { objc_setAssociatedObject(self, &kNavSeparatorKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func oc_ensureTopNavigationSeparator(color: UIColor) {
        if oc_navSeparatorView == nil {
            let separator = UIView()
            separator.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(separator)

            let onePixel = 1.0 / UIScreen.main.scale
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                separator.heightAnchor.constraint(equalToConstant: onePixel)
            ])

            oc_navSeparatorView = separator
        }

        oc_navSeparatorView?.backgroundColor = color
    }
}
