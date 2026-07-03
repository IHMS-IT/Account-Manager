//
//  RemoteHostStore.swift
//  Account Manager
//

import Foundation
import Observation

@Observable
final class RemoteHostStore {

    var hosts: [RemoteHost] = []

    static let shared = RemoteHostStore()
    private init() { load() }

    func add(_ host: RemoteHost) {
        hosts.append(host)
        save()
    }

    func update(_ host: RemoteHost) {
        if let i = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[i] = host
            save()
        }
    }

    func remove(_ host: RemoteHost) {
        hosts.removeAll { $0.id == host.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        UserDefaults.standard.set(data, forKey: "savedRemoteHosts")
    }

    private func load() {
        guard
            let data    = UserDefaults.standard.data(forKey: "savedRemoteHosts"),
            let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data)
        else { return }
        hosts = decoded
    }
}
