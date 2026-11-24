// The network file server is intentionally disabled in the offline build.
import Foundation

@available(*, deprecated, message: "The network file server is disabled in the offline build.")
public final class FileServer {
  public init(port: Int, publicDirectory: URL) {}
  public func start() {}
  public func shutdown() {}
}
