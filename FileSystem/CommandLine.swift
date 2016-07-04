//
//  CommandLine.swift
//  FileSystem
//
//  Created by Borys Pedos on 04.07.16.
//  Copyright © 2016 bo-nik corp. All rights reserved.
//

import Foundation

class CommandLine {
    
    static let arguments: [String: String] = {
        var arguments: [String: String] = [:]
        
        if Process.arguments.count > 2 {
            for i in 2 ..< Process.arguments.count - 1 {
                if Process.arguments[i].hasPrefix("-") {
                    arguments[Process.arguments[i]] = Process.arguments[i + 1]
                }
            }
        }
        
        return arguments
    }()
    
    
    static let command: String? = {
        if Process.arguments.count > 1 {
            return Process.arguments[1]
        }
        return nil
    }()
}