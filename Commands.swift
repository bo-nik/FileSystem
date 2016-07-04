//
//  Commands.swift
//  FileSystem
//
//  Created by Borys Pedos on 04.07.16.
//  Copyright © 2016 bo-nik corp. All rights reserved.
//

import Foundation

let commands = [
    "format":       Commands.format,
    "mount":        Commands.mount,
    "umount":       Commands.umount,
    "filestat":     Commands.filestat,
    "list":         Commands.list,
    "ls":           Commands.list,
    "create":       Commands.create,
    "open":         Commands.open,
    "close":        Commands.close,
    "close-all":    Commands.closeAll,
    "read":         Commands.read,
    "write":        Commands.write,
    "link":         Commands.link,
    "unlink":       Commands.unlink,
    "truncate":     Commands.truncate,
    "info":         Commands.info,
    "version":      Commands.version
]

struct Commands {
    
    static func format() {
        if let fileName = CommandLine.arguments["-file-name"] ?? CommandLine.arguments["-f"],
            let size = file_size_t(CommandLine.arguments["-size"] ?? CommandLine.arguments["-s"] ?? "-1"),
            let blockSize = block_size_t(CommandLine.arguments["-block-size"] ?? CommandLine.arguments["-b"] ?? "-1"),
            let descriptorsCount = size_t(CommandLine.arguments["-descriptors-count"] ?? CommandLine.arguments["-d"] ?? "-1") {
            
            fs.format(fileName: fileName, size: size, blockSize: blockSize, descriptorsCount: descriptorsCount)
        } else {
            Logger.log("Usage: xfs format -file-name <name> -size <size> -block-size <size> -descriptors-count <count>")
        }
    }
    
    static func mount() {
        if let fileName = CommandLine.arguments["-file-name"] ?? CommandLine.arguments["-f"] {
            fs.mount(fileName: fileName)
        } else {
            Logger.log("Usage: xfs mount -file-name <name>")
        }
    }
    
    static func umount() {
        fs.umount()
    }
    
    static func filestat() {
        if let fileName = CommandLine.arguments["-file-name"] ?? CommandLine.arguments["-f"] {
            if let fileInfo = fs.filestat(fileName: fileName) {
                var description = "File '\(fileInfo.name)':\n"
                description += "\tSize               – \(fileInfo.size)B\n"
                description += "\tDescriptor index   – \(fileInfo.descriptorIndex)\n"
                description += "\tBlocks count       – \(fileInfo.blocksCount)\n"
                description += "\tLinks count        – \(fileInfo.linksCount)"
                Logger.log(description)
            }
        } else {
            Logger.log("Usage: xfs filestat -file-name <name>")
        }
    }
    
    static func list() {
        let filesList = fs.list()
        for (name, id, isOpened) in filesList {
            Logger.log("\(String(format: "%-5d", id))\(isOpened ? "*" : " ")\(name)")
        }
    }
    static func create() {
        if let fileName = CommandLine.arguments["-file-name"] ?? CommandLine.arguments["-f"] {
            fs.create(fileName: fileName)
        } else {
            Logger.log("Usage: xfs create -file-name <name>")
        }
    }
    
    static func open() {
        if let fileName = CommandLine.arguments["-file-name"] ?? CommandLine.arguments["-f"] {
            if let descriptor = fs.open(fileName: fileName) {
                Logger.log("File was opened with descriptor \(descriptor)")
            }
        } else {
            Logger.log("Usage: xfs open -file-name <name>")
        }
    }
    
    static func close() {
        if let fd = size_t(CommandLine.arguments["-fd"] ?? "-1") {
            fs.close(fd: fd)
        } else {
            Logger.log("Usage: xfs close -fd <fd>")
        }
    }
    
    static func closeAll() {
        fs.closeAll()
    }
    
    static func read() {
        if let fd = size_t(CommandLine.arguments["-fd"] ?? "-1"),
            let offset = file_size_t(CommandLine.arguments["-offset"] ?? CommandLine.arguments["-o"] ?? "0"),
            let size = file_size_t(CommandLine.arguments["-size"] ?? CommandLine.arguments["-s"] ?? "-1") {
            
            if let data = fs.read(fd: fd, offset: offset, size: size) {
                Logger.log(String.fromCString(data.map({ return CChar($0) }))!)
            }
        } else {
            Logger.log("Usage: xfs read -fd <fd> [-offset <offset>] -size <size>")
        }
    }
    
    static func write() {
        if let fd = size_t(CommandLine.arguments["-fd"] ?? "-1"),
            let offset = file_size_t(CommandLine.arguments["-offset"] ?? CommandLine.arguments["-o"] ?? "0") {
            
            var stringData = ""
            while let input = readLine(stripNewline: false) {
                stringData += input
            }
            var cStringData = stringData.cStringUsingEncoding(NSUTF8StringEncoding)!
            cStringData.removeLast() // remove '\0'
            let data = cStringData.map({ return UInt8($0) })
            
            Logger.log("")
            
            fs.write(fd: fd, offset: offset, data: data)
            
        } else {
            Logger.log("Usage: xfs read -fd <fd> [-offset <offset>]")
        }
    }
    
    static func link() {
        if let fileName = CommandLine.arguments["-file-name"] ?? CommandLine.arguments["-f"],
            let linkName = CommandLine.arguments["-link-name"] ?? CommandLine.arguments["-l"] {
            fs.link(fileName: fileName, linkName: linkName)
        } else {
            Logger.log("Usage: xfs link -file-name <name> -link-name <name>")
        }
    }
    
    static func unlink() {
        if let linkName = CommandLine.arguments["-link-name"] {
            fs.unlink(linkName: linkName)
        } else {
            Logger.log("Usage: xfs unlink -link-name <name>")
        }
    }
    
    static func truncate() {
        if let fileName = CommandLine.arguments["-file-name"] ?? CommandLine.arguments["-f"],
            let size = file_size_t(CommandLine.arguments["-size"] ?? CommandLine.arguments["-s"] ?? "-1") {
            
            fs.truncate(fileName: fileName, size: size)
        } else {
            Logger.log("Usage: xfs truncate format -file-name <name> -size <size>")
        }
    }
    
    static func info() {
        Logger.log(fs.description)
    }
    
    static func version() {
        Logger.log("Version 0.0.2. Tonight release.")
    }
}