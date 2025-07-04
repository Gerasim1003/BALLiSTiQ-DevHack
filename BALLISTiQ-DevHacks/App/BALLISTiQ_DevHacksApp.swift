//
//  BALLISTiQ_DevHacksApp.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//

import SwiftUI

class Router<T: Hashable>: ObservableObject {
    @Published var path = NavigationPath()
    func push(_ route: T)  {
        path.append(route)
    }
    
    func pop() {
        path.removeLast()
    }
    
    func pop(_ k: Int) {
        path.removeLast(k)
    }
    
    func popToRoot() {
        path.removeLast(path.count)
    }
}

@main
struct BALLISTiQ_DevHacksApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
