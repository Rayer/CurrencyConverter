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
                //https://stackoverflow.com/questions/60994255/swiftui-get-toggle-state-from-items-inside-a-list
                List(dataset.data.indices, id:\.self) { index in
                    Toggle("", isOn: self.$dataset.data[index].isChecked)
                    EntityDetailRow(self.dataset.data[index])
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
