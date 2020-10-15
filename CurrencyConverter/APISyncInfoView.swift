//
//  UserDefaultsView.swift
//  CurrencyConverter
//
//  Created by Rayer on 2020/10/14.
//  Copyright © 2020 Rayer. All rights reserved.
//

import SwiftUI

struct APISyncInfoView: View {
    @State var host : APISyncInfoDataModel
    var body: some View {
        VStack {
            Text("Last updated : " + (host.lastUpdate ?? "----"))
            Text("Parsed data time stamp : " + (host.parsedPayloadUpdate ?? "----"))
            Text("Raw Data : " + (host.rawData ?? "----"))
        }
    }
}

struct APISyncInfoView_Previews: PreviewProvider {
    static var previews: some View {
        APISyncInfoView(host: APISyncInfoDataModel(sharedUserDefaults))
    }
}
