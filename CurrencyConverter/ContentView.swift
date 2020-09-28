//
//  ContentView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var dataset = ConvertHistoryDMCollection()
    
    init() {
//        NotificationCenter.default.addObserver(dataset, selector: #selector(dataset.reload), name: NSNotification.Name(rawValue: "NSPersistentStoreRemoteChangeNotificationOptionKey"), object: persistentContainer.persistentStoreCoordinator)
        NotificationCenter.default.addObserver(dataset, selector: #selector(type(of: dataset).reload), name: .NSPersistentStoreRemoteChange, object: persistentContainer.persistentStoreCoordinator)
        dataset.reload()
    }
    
    var body: some View {
        
        TabView() {
            VStack {
                List(dataset.data!, id: \.id) { c in
                    EntityDetailRow(ConvertHistoryDM.fromCoreData(c: c))
                }
                HStack {
                    Button("Reload") {
                        dataset.reload()
                    }
                    Button("Wipe all") {
                        dataset.wipe()
                        wipeAll()
                    }
                }
            }
                .tabItem { Text("Data") }
                .tag(1)
            
            Text("Tab Content 2")
                .tabItem { Text("Settings") }
                .tag(2)
        }
        .frame(minWidth: 400, idealWidth: 400, maxWidth: .infinity, minHeight: 400, idealHeight: 400, maxHeight: .infinity, alignment: .center)
        
    }
}


struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
    }
}
