//
//  CurrencyConverter.swift
//  Utilplugin
//
//  Created by Rayer on 2019/11/1.
//  Copyright © 2019 Rayer. All rights reserved.
//

import Foundation
import Cocoa

struct CurrencyRateEntity : Codable {
    var base: String
    var date: String
    var rates: [String:Float32]
}

class CurrencyConverter {
    var currencyRateEntity: CurrencyRateEntity?
    var context: NSExtensionContext?
    
    static let shared = CurrencyConverter()
    private init(){}

    init(context: NSExtensionContext? = nil) {
        self.context = context
        print("Setting context : \(String(describing: context))")
    }
    
    fileprivate func loadFromWeb(_ completionHandler: @escaping (Error?) -> Void) {
        let feed_url = URL(string: "http://data.fixer.io/api/latest?access_key=676ac77e5ce5d4b9a57ee6464ff84433&format=1")
        URLSession.shared.dataTask(with: feed_url!) { (data, response, error) in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                completionHandler(error)
                return
            } else if let response = response as? HTTPURLResponse,let data = data {
                print("Status code: \(response.statusCode)")
                let decoder = JSONDecoder()
                if let currencyRateEntity = try? decoder.decode(CurrencyRateEntity.self, from: data) {
                    self.currencyRateEntity = currencyRateEntity
                    let e = NSEntityDescription.insertNewObject(forEntityName: "CEREntityMO", into: persistentContainer.viewContext)
                    //e.base = currencyRateEntity.base
                    //e.rates = currencyRateEntity.rates as NSObject
                    e.setValue(currencyRateEntity.base, forKey: "base")
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "YYYY-MM-dd"
                    guard let date = dateFormatter.date(from: currencyRateEntity.date) else {
                       fatalError("ERROR: Date conversion failed due to mismatched format.")
                    }
                    e.setValue(date, forKey: "date")
                    let encoder = JSONEncoder()
                    let data = try! encoder.encode(currencyRateEntity.rates)
                    e.setValue(String(data: data, encoding: .utf8), forKey: "rates")
                    print("Saving rate data : \(e.description)")
                    try! persistentContainer.viewContext.save()
                }

            }
            completionHandler(nil)
        }.resume()
    }
    
//    func loadFromCD(_ completionHandler: @escaping (Error?) -> Void) {
//        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CEREntityMO")
////        //gather current calendar
////        NSCalendar *calendar = [NSCalendar currentCalendar];
////
////        //gather date components from date
////        NSDateComponents *dateComponents = [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:[NSDate date]];
//        let calendar = Calendar.current
//        DateComponents components = calendar.component(component: [.year, .], from: <#T##Date#>)
//
//        request.predicate = NSPredicate(format: "date = %@", "")
//    }
    
    func loadData(completionHandler: @escaping (Error?) -> Void = {_ in }) {
        
        if currencyRateEntity != nil {
            completionHandler(nil)
            return
        }
        
        //TODO: Peek if there are today's record in entry
        //loadFromCD(completionHandler);
        
        loadFromWeb(completionHandler)
    }
    
    func convert(from: String, to: String, unit: Float32, completionHandler: @escaping (Float32, Error?) -> Void) {
        loadData { (error) in
            if error != nil {
                completionHandler(0.0, error)
                return
            }
            
            let fromRate = self.currencyRateEntity?.rates[from]!
            let toRate = self.currencyRateEntity?.rates[to]!
            
            completionHandler((unit / fromRate!) * toRate!, nil)
        }
    }
    
    func getSymbols(completionHandler: @escaping ([String]?, Error?) -> Void) {
        loadData { (error) in
            if error != nil {
                completionHandler(nil, error)
            }
            completionHandler(Array((self.currencyRateEntity?.rates.keys)!), nil)
        }
    }
    
}
