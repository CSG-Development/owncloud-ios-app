import ownCloudSDK

public protocol DisplayHostType {
	var clientContext: ClientContext? { get }
	var location: OCLocation? { get }
}
