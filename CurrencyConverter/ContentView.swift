//
//  ContentView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @State var historicalData = readFromCore()

    var body: some View {
        
        TabView(selection: /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Selection@*/.constant(1)/*@END_MENU_TOKEN@*/) {
            VStack {
                List(historicalData!, id: \.id) { c in
                    EntityDetailRow(ConvertHistoryDM.fromCoreData(c: c))
                }
                HStack {
                    Button("Reload") {
                        historicalData = readFromCore()
                    }
                    Button("Wipe all") {
                        historicalData = []
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
