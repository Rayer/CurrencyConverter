//
//  ContentView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/9/23.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    let previewTarget = readFromCore()!

    var body: some View {
        List(previewTarget, id: \.id) { c in
            EntityDetailRow(c)
        }
    }
}


struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
        ContentView()
            
    }
}
