//
//  main.swift
//  com.ihms.accountmanager.helper
//
//  Entry point for the privileged XPC helper daemon.
//  Runs as root via launchd. Never call directly.
//

import Foundation

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: helperMachServiceName)
listener.delegate = delegate
listener.resume()

// Park the run loop — launchd keeps us alive and terminates us when idle.
RunLoop.main.run()
