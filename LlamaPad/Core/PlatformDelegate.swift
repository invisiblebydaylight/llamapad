#if os(macOS)
import SwiftUI

protocol ApplicationDelegate: NSApplicationDelegate {
    var appState: AppState? { get set }
}

class LlamaPadAppDelegate: NSObject, ApplicationDelegate {
    weak var appState: AppState?
    
    func applicationWillTerminate(_ notification: Notification) {
        appState?.llamaContext?.unload()
        shutdownLlamaCppBackend()
    }
}

typealias ApplicationDelegateAdaptor = NSApplicationDelegateAdaptor
#else
import SwiftUI

protocol ApplicationDelegate: UIApplicationDelegate {
    var appState: AppState? { get set }
}

class LlamaPadAppDelegate: NSObject, ApplicationDelegate {
    weak var appState: AppState?
    
    func applicationWillTerminate(_ application: UIApplication) {
        appState?.llamaContext?.unload()
        shutdownLlamaCppBackend()
    }
}

typealias ApplicationDelegateAdaptor = UIApplicationDelegateAdaptor
#endif
