//
//  AppPreferences.swift
//  SuggestMeSome
//
//  Created by Alex Yao on 4/10/26.
//

import Foundation

enum AppPreferences {
    static var defaultWeightUnit: WeightUnit {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "globalWeightUnit"),
                  let unit = WeightUnit(rawValue: raw) else { return .lbs }
            return unit
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "globalWeightUnit")
        }
    }
}
