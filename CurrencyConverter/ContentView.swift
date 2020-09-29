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
        NotificationCenter.default.addObserver(dataset, selector: #selector(type(of: dataset).reload), name: .NSPersistentStoreRemoteChange, object: persistentContainer.persistentStoreCoordinator)
        dataset.reload()
    }
    
    var body: some View {
        
        TabView() {
            VStack {
                List(dataset.data, id: \.id) { c in
                    EntityDetailRow(c)
                }
                HStack {
                    Button("Reload(For debugging)") {
                        dataset.reload()
                    }
                    Button("Wipe all") {
                        dataset.wipe()
                        //wipeAll()
                    }
                    Button("Wipe selected") {
                        dataset.wipeChecked()
                    }
                }
            }
                .tabItem { Text("Data") }
                .tag(1)
            
            Text("Tab Content 2")
                .tabItem { Text("Settings") }
                .tag(2)
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .center)
        
    }
}


struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
    }
}
