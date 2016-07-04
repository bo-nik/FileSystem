//
//  main.swift
//  FileSystem
//
//  Created by Borys Pedos on 04.07.16.
//  Copyright © 2016 bo-nik corp. All rights reserved.
//

import Foundation

let fs = FileSystem(automaticMount: true)

if let command = CommandLine.command {
    if let handler = commands[command] {
        handler()
    } else {
        Logger.log("No such command...")
    }
} else {
    Logger.log("Usage: xfs <command> [parameters]")
}