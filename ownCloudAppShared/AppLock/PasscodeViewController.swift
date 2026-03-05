//
//  PasscodeViewController.swift
//  ownCloud
//
//  Created by Javier Gonzalez on 03/05/2018.
//  Copyright © 2018 ownCloud GmbH. All rights reserved.
//

/*
 * Copyright (C) 2018, ownCloud GmbH.
 *
 * This code is covered by the GNU Public License Version 3.
 *
 * For distribution utilizing Apple mechanisms please see https://owncloud.org/contribute/iOS-license-exception/
 * You should have received a copy of this license along with this program. If not, see <http://www.gnu.org/licenses/gpl-3.0.en.html>.
 *
 */

import UIKit
import SnapKit
import ownCloudApp
import LocalAuthentication

public typealias PasscodeViewControllerCancelHandler = ((_ passcodeViewController: PasscodeViewController) -> Void)
public typealias PasscodeViewControllerBiometricalHandler = ((_ passcodeViewController: PasscodeViewController) -> Void)
public typealias PasscodeViewControllerCompletionHandler = ((_ passcodeViewController: PasscodeViewController, _ passcode: String) -> Void)

public class PasscodeViewController: UIViewController, Themeable {
	// MARK: - Constants
	fileprivate var passCodeCompletionDelay: TimeInterval = 0.1

	// MARK: - Navigation bar
	private let navigationBarContainer = UIView()

	private lazy var navigationBar: UINavigationBar = {
		let bar = UINavigationBar()
		bar.isTranslucent = false

		let item = UINavigationItem(title: OCLocalizedString("Passcode.navigationTitle", nil))
		if cancelButtonAvailable {
			let cancelButton = ThemeRoundedButton(withSelectors: [.primary, .plain])
			cancelButton.setTitle(OCLocalizedString("Cancel", nil), for: .normal)
			cancelButton.setTitleColor(.white, for: .normal)
			cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 20)
			cancelButton.addTarget(self, action: #selector(didTapNavigationCancel), for: .touchUpInside)
			item.rightBarButtonItem = UIBarButtonItem(customView: cancelButton)
		}
		bar.setItems([item], animated: false)
		return bar
	}()

	// MARK: - Layout views
	private let portraitLayout = PasscodePortraitView(frame: .zero)
	private let landscapeLayout = PasscodeLandscapeView(frame: .zero)

	// MARK: - Properties
	private var passcodeLength: Int

	public var passcode: String? {
		didSet {
			updatePasscodeDots()
		}
	}

	public var message: String? {
		didSet {
			let text = message ?? " "
			portraitLayout.titleLabel.text = text
			landscapeLayout.titleLabel.text = text
		}
	}

	public var subtitle: String? {
		didSet {
			let text = subtitle ?? " "
			portraitLayout.subtitleLabel.text = text
			landscapeLayout.subtitleLabel.text = text
		}
	}

	public var errorMessage: String? {
		didSet {
			let text = errorMessage ?? " "
			portraitLayout.errorLabel.text = text
			landscapeLayout.errorLabel.text = text

			if errorMessage != nil {
				portraitLayout.passcodeLabel.shakeHorizontally()
				landscapeLayout.passcodeLabel.shakeHorizontally()
			}
		}
	}

	var timeoutMessage: String? {
		didSet {
			let text = timeoutMessage ?? ""
			portraitLayout.timeoutLabel.text = text
			landscapeLayout.timeoutLabel.text = text

			let active = (timeoutMessage != nil && !timeoutMessage!.isEmpty)
			portraitLayout.setTimeoutActive(active)
			landscapeLayout.setTimeoutActive(active)
		}
	}

	var keypadButtonsHidden: Bool {
		didSet {
			if oldValue != keypadButtonsHidden {
				updateKeypadButtons()
			}
		}
	}

	var cancelButtonAvailable: Bool {
		didSet {
			cancelButton?.isEnabled = cancelButtonAvailable
			cancelButton?.isHidden = !cancelButtonAvailable
		}
	}

	public var cancelButton: ThemeRoundedButton?

	var biometricalButtonHidden: Bool = false {
		didSet {
			let image: UIImage? = biometricalButtonHidden ? nil : biometryIcon
			portraitLayout.codePad.biometryImage = image
			landscapeLayout.codePad.biometryImage = image
		}
	}

	private var biometryIcon: UIImage? {
		let context = LAContext()
		guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
		switch context.biometryType {
		case .touchID: return HCIcon.touchId
		case .faceID: return HCIcon.faceId
		default: return nil
		}
	}

	var hasCompactHeight: Bool {
		return traitCollection.verticalSizeClass == .compact
	}

	// MARK: - Handlers
	public var cancelHandler: PasscodeViewControllerCancelHandler?
	public var biometricalHandler: PasscodeViewControllerBiometricalHandler?
	public var completionHandler: PasscodeViewControllerCompletionHandler?

	// MARK: - Init
	public init(
		cancelHandler: PasscodeViewControllerCancelHandler? = nil,
		biometricalHandler: PasscodeViewControllerBiometricalHandler? = nil,
		completionHandler: @escaping PasscodeViewControllerCompletionHandler,
		hasCancelButton: Bool = true,
		keypadButtonsEnabled: Bool = true,
		requiredLength: Int
	) {
		self.cancelHandler = cancelHandler
		self.biometricalHandler = biometricalHandler
		self.completionHandler = completionHandler
		self.cancelButtonAvailable = hasCancelButton
		self.keypadButtonsHidden = false
		self.passcodeLength = requiredLength

		super.init(nibName: nil, bundle: nil)
		self.cssSelector = .passcode
		self.modalPresentationStyle = .fullScreen
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - View Controller Events
	public override func viewDidLoad() {
		super.viewDidLoad()

		self.title = VendorServices.shared.appName

		self.errorMessage = { self.errorMessage }()
		self.timeoutMessage = { self.timeoutMessage }()
		self.cancelButtonAvailable = { self.cancelButtonAvailable }()
		self.keypadButtonsHidden = { self.keypadButtonsHidden }()
		self.biometricalButtonHidden = (!AppLockSettings.shared.biometricalSecurityEnabled || !AppLockSettings.shared.lockEnabled || cancelButtonAvailable)

		updateKeypadButtons()

		setupNavigationBar()
		setupLayoutViews()
		activateLayoutForCurrentTraits()
	}

	public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		coordinator.animate(alongsideTransition: { _ in
			self.activateLayoutForCurrentTraits()
			self.view.layoutIfNeeded()
			self.portraitLayout.codePad.forceButtonRelayout()
			self.landscapeLayout.codePad.forceButtonRelayout()
		}, completion: nil)
	}

	public override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		Theme.shared.register(client: self)
		updatePasscodeDots()
	}

	public override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		Theme.shared.unregister(client: self)
	}

	// MARK: - Setup

	private func setupNavigationBar() {
		guard cancelButtonAvailable else {
			navigationBarContainer.isHidden = true
			return
		}

		navigationBarContainer.backgroundColor = .black
		navigationBarContainer.layer.shadowColor = UIColor.black.cgColor
		navigationBarContainer.layer.shadowOpacity = 0.3
		navigationBarContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
		navigationBarContainer.layer.shadowRadius = 4

		view.addSubview(navigationBarContainer)
		navigationBarContainer.translatesAutoresizingMaskIntoConstraints = false

		navigationBarContainer.addSubview(navigationBar)
		navigationBar.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			navigationBarContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			navigationBarContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			navigationBarContainer.topAnchor.constraint(equalTo: view.topAnchor),

			navigationBar.leadingAnchor.constraint(equalTo: navigationBarContainer.leadingAnchor),
			navigationBar.trailingAnchor.constraint(equalTo: navigationBarContainer.trailingAnchor),
			navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
			navigationBar.bottomAnchor.constraint(equalTo: navigationBarContainer.bottomAnchor),
			navigationBar.heightAnchor.constraint(equalToConstant: 44)
		])
	}

	private func setupLayoutViews() {
		let topAnchor = navigationBarContainer.isHidden
			? view.safeAreaLayoutGuide.snp.top
			: navigationBarContainer.snp.bottom

		// Portrait layout
		view.addSubview(portraitLayout)
		portraitLayout.snp.makeConstraints {
			$0.top.equalTo(topAnchor)
			$0.leading.trailing.equalTo(view.safeAreaLayoutGuide)
			$0.bottom.equalTo(view.safeAreaLayoutGuide)
		}

		wireCodePad(portraitLayout.codePad)

		// Landscape layout
		view.addSubview(landscapeLayout)
		landscapeLayout.snp.makeConstraints {
			$0.top.equalTo(topAnchor)
			$0.leading.trailing.equalTo(view.safeAreaLayoutGuide)
			$0.bottom.equalTo(view.safeAreaLayoutGuide)
		}

		wireCodePad(landscapeLayout.codePad)

		if !navigationBarContainer.isHidden {
			view.bringSubviewToFront(navigationBarContainer)
		}
	}

	// MARK: - Layout switching

	private func activateLayoutForCurrentTraits() {
		if hasCompactHeight {
			portraitLayout.isHidden = true
			portraitLayout.isUserInteractionEnabled = false
			landscapeLayout.isHidden = false
			landscapeLayout.isUserInteractionEnabled = true
		} else {
			portraitLayout.isHidden = false
			portraitLayout.isUserInteractionEnabled = true
			landscapeLayout.isHidden = true
			landscapeLayout.isUserInteractionEnabled = false
		}
	}

	private func wireCodePad(_ codePad: HCCodePadView) {
		codePad.onDigit = { [weak self] digit in
			self?.appendDigit(digit: "\(digit)")
		}
		codePad.onDelete = { [weak self] in
			self?.deleteLastDigit()
		}
		codePad.onBiometry = { [weak self] in
			guard let self else { return }
			self.biometricalHandler?(self)
		}

		let showBiometry = AppLockSettings.shared.biometricalSecurityEnabled
			&& AppLockSettings.shared.lockEnabled
			&& !cancelButtonAvailable
		if showBiometry {
			codePad.biometryImage = biometryIcon
		}
	}

	// MARK: - UI updates

	private func updateKeypadButtons() {
		portraitLayout.codePad.isUserInteractionEnabled = !keypadButtonsHidden
		landscapeLayout.codePad.isUserInteractionEnabled = !keypadButtonsHidden
	}

	private func updatePasscodeDots() {
		var placeholders = ""
		let enteredDigits = passcode?.count ?? 0

		for index in 1...passcodeLength {
			if index > 1 {
				placeholders += "  "
			}
			if index <= enteredDigits {
				placeholders += "●"
			} else {
				placeholders += "○"
			}
		}
		portraitLayout.passcodeLabel.text = placeholders
		landscapeLayout.passcodeLabel.text = placeholders
	}

	// MARK: - Actions

	public func appendDigit(digit: String) {
		if let currentPasscode = passcode {
			if currentPasscode.count < passcodeLength {
				self.passcode = currentPasscode + digit
			}
		} else {
			self.passcode = digit
		}

		if let enteredPasscode = passcode {
			if enteredPasscode.count == passcodeLength {
				OnMainThread(after: passCodeCompletionDelay) {
					self.completionHandler?(self, enteredPasscode)
				}
			}
		}
	}

	public func deleteLastDigit() {
		if passcode != nil, passcode!.count > 0 {
			passcode?.removeLast()
			updatePasscodeDots()
		}
	}

	@IBAction func cancel(_ sender: UIButton) {
		cancelHandler?(self)
	}

	@objc private func didTapNavigationCancel() {
		cancelHandler?(self)
	}

	@IBAction func biometricalAction(_ sender: UIButton) {
		biometricalHandler?(self)
	}

	// MARK: - Theming

	public override var preferredStatusBarStyle: UIStatusBarStyle {
		if VendorServices.shared.isBranded {
			return .darkContent
		}
		return Theme.shared.activeCollection.css.getStatusBarStyle(for: self) ?? .default
	}

	open func applyThemeCollection(theme: Theme, collection: ThemeCollection, event: ThemeEvent) {
		view.backgroundColor = collection.css.getColor(.fill, selectors: [.hcColorCardBackground], for: nil)

		let barColor = collection.css.getColor(.fill, selectors: [.hcColorMenuBackground], for: nil) ?? .white

		let textColor = collection.css.getColor(.fill, selectors: [.text], for: nil) ?? .white
		let appearance = UINavigationBarAppearance()
		appearance.configureWithOpaqueBackground()
		appearance.backgroundColor = barColor
		appearance.shadowColor = UIColor.black.withAlphaComponent(0.1)
		appearance.titleTextAttributes = [
			.foregroundColor: textColor
		]
		navigationBar.standardAppearance = appearance
		navigationBar.scrollEdgeAppearance = appearance
		navigationBar.tintColor = textColor
		navigationBarContainer.backgroundColor = barColor
	}
}

extension PasscodeViewController: UITextFieldDelegate {
	open func textField(
		_ textField: UITextField,
		shouldChangeCharactersIn range: NSRange,
		replacementString string: String
	) -> Bool {
		if range.length > 0 {
			deleteLastDigit()
		} else {
			appendDigit(digit: string)
		}
		return false
	}
}

extension ThemeCSSSelector {
	static let passcode = ThemeCSSSelector(rawValue: "passcode")
	static let digit = ThemeCSSSelector(rawValue: "digit")
	static let code = ThemeCSSSelector(rawValue: "code")
	static let backspace = ThemeCSSSelector(rawValue: "backspace")
	static let biometrical = ThemeCSSSelector(rawValue: "biometrical")
	static let timeout = ThemeCSSSelector(rawValue: "timeout")
}
