//
//  FileSystem.swift
//  FileSystem
//
//  Created by Borys Pedos on 04.07.16.
//  Copyright © 2016 bo-nik corp. All rights reserved.
//

import Foundation

typealias size_t = UInt32
typealias block_size_t = UInt32
typealias file_size_t = UInt64

class FileSystem {
    
    ///
    /// Represents a file descriptor (like `inode` in normal filesystems).
    ///
    struct Descriptor {
        
        ///
        /// Ofsets in bytes in binary `Descriptor` structure.
        ///
        private struct Offsets {
            static let LinksCount = 0
            static let FileSize = sizeof(size_t)
            static let Blocks = sizeof(size_t) + sizeof(file_size_t)
        }
        
        ///
        /// Count of links to this file.
        ///
        var linksCount: size_t = 0 {
            didSet {
                if linksCount == 0 {
                    fileSize = 0
                    blocks = [file_size_t?](count: Int(FileSystem.Limits.MaxFileBlocksCount), repeatedValue: nil)
                }
            }
        }
        
        ///
        /// Size of file in bytes.
        ///
        var fileSize: file_size_t = 0
        
        ///
        /// Blocks map to store file data.
        ///
        /// Indexes of blocks in filesystem, that are used to store file data.
        ///
        var blocks: [file_size_t?] = [file_size_t?](count: Int(FileSystem.Limits.MaxFileBlocksCount), repeatedValue: nil)
        
        ///
        /// Size of `Descriptor` in bytes.
        ///
        static var size: Int {
            return
                sizeof(size_t) +                                                        // linksCount
                    sizeof(file_size_t) +                                               // fileSize
                    sizeof(file_size_t?) * Int(FileSystem.Limits.MaxFileBlocksCount)    // blocks
        }
        
        init() {
            
        }
        
        init(data: NSData) {
            data.getBytes(&linksCount, range: NSRange(location: Offsets.LinksCount, length: sizeof(size_t)))
            data.getBytes(&fileSize, range: NSRange(location: Offsets.FileSize, length: sizeof(file_size_t)))
            for i in 0 ..< blocks.count {
                data.getBytes(&blocks[i], range:
                    NSRange(location: Offsets.Blocks + sizeof(file_size_t?) * i, length: sizeof(file_size_t?)))
            }
        }
        
        func toNSData() -> NSData {
            var linksCount = self.linksCount
            var fileSize = self.fileSize
            
            let data = NSMutableData()
            data.appendBytes(&linksCount, length: sizeof(size_t))
            data.appendBytes(&fileSize, length: sizeof(file_size_t))
            for var block in blocks {
                data.appendBytes(&block, length: sizeof(file_size_t?))
            }
            return data
        }
        
    }
    
    ///
    /// Represents a pair of file name and its descriptor index (something like link).
    ///
    struct Link {
        
        ///
        /// File name.
        ///
        var name: String = ""
        
        ///
        /// Descriptor index.
        ///
        var descriptorIndex: size_t? = nil
        
        ///
        /// Size of `Link` in bytes.
        ///
        static var size: Int {
            return Int(Limits.MaxFileNameLength) * sizeof(CChar) + sizeof(size_t?)
        }
        
        init() {
            
        }
        
        init(name: String, descriptorIndex: size_t) {
            self.name = name
            self.descriptorIndex = descriptorIndex
        }
        
        init(data: NSData) {
            var cstringFileName = [CChar](count: Int(Limits.MaxFileNameLength), repeatedValue: 0)
            let fileNameSize = Int(Limits.MaxFileNameLength) * sizeof(CChar)
            data.getBytes(&cstringFileName, range: NSRange(location: 0, length: fileNameSize))
            name = String.fromCString(cstringFileName)!
            
            data.getBytes(&descriptorIndex, range: NSRange(location: fileNameSize, length: sizeof(size_t?)))
        }
        
        func toNSData() -> NSData {
            var descriptorIndex = self.descriptorIndex
            
            var cstringFileName = name.cStringUsingEncoding(NSUTF8StringEncoding)!
            let data = NSMutableData()
            var char: CChar = 0
            for i in 0 ..< Int(Limits.MaxFileNameLength) {
                if i < cstringFileName.count {
                    data.appendBytes(&cstringFileName[i], length: sizeof(CChar))
                } else {
                    data.appendBytes(&char, length: sizeof(CChar))
                }
            }
            data.appendBytes(&descriptorIndex, length: sizeof(size_t?))
            return data
        }
    }
    
    ///
    /// Filesystem limits.
    ///
    struct Limits {
        static let MaxFileBlocksCount: size_t = 256
        static let MaxFileLinksCount: size_t = 8
        static let MaxFileNameLength: size_t = 128
        static let MaxOpenedFilesCount: size_t = 128
    }
    
    ///
    /// Filesystem info.
    ///
    struct Info {
        var fileName: String = ""
        var blockSize: block_size_t = 0
        var blocksCount: file_size_t = 0
        var usedBlocksCount: file_size_t = 0
        var freeBlocksCount: file_size_t = 0
        var descriptorsCount: size_t = 0
        var usedDescriptorsCount: size_t = 0
        var freeDescriptorsCount: size_t = 0
        var linksCount: size_t = 0
        var usedLinksCount: size_t = 0
        var availableLinksCount: size_t = 0
    }
    
    // MARK:
    
    ///
    /// Ofsets in bytes in binary filesystem structure.
    ///
    private struct Offsets {
        var blocksBitmapOffset: UInt64
        var descriptorsOffset: UInt64
        var linksOffset: UInt64
        var dataBlocksOffset: UInt64
    }
    
    private var offsets = Offsets(blocksBitmapOffset: 0, descriptorsOffset: 0, linksOffset: 0, dataBlocksOffset: 0)
    
    private var fsFile: NSFileHandle! = nil
    private var fsInfo: Info! = nil
    private var openedFiles: [size_t: size_t] = [:] // [fd: descriptorIndex]
    
    private var isMounted: Bool {
        return fsFile != nil
    }
    
    init(automaticMount: Bool = false) {
        if (automaticMount) {
            shadowMount()
        }
    }
    
    private func shadowMount() {
        
        // Create fs file handle
        if let fsFileName =  NSUserDefaults.standardUserDefaults().valueForKey("fs-file-name") as? String {
            fsFile = NSFileHandle(forUpdatingAtPath: fsFileName)
            if (fsFile == nil) {
                return
            }
            
            updateFsInfo()
            
            // Update offsets
            let blocksBitmapOffset =
                UInt64(sizeof(block_size_t)) +                              // Block size
                    UInt64(sizeof(file_size_t)) +                           // Blocks count
                    UInt64(sizeof(size_t))                                  // Descriptors count
            
            let descriptorsOffset = blocksBitmapOffset +
                fsInfo.blocksCount * UInt64((sizeof(Bool)))                 // Blocks bitmap table
            
            let linksOffset = descriptorsOffset +
                UInt64(fsInfo.descriptorsCount) * UInt64(Descriptor.size)   // Descriptors
            
            let totalLinksCount = fsInfo.descriptorsCount * Limits.MaxFileLinksCount
            let dataBlocksOffset = linksOffset + UInt64(Link.size) * UInt64(totalLinksCount)
            
            offsets = Offsets(blocksBitmapOffset: blocksBitmapOffset,
                              descriptorsOffset: descriptorsOffset,
                              linksOffset: linksOffset,
                              dataBlocksOffset: dataBlocksOffset)
        }
    }
    
    private func updateFsInfo() {
        
        guard isMounted else {
            return
        }
        
        let fsFileName =  NSUserDefaults.standardUserDefaults().valueForKey("fs-file-name") as! String
        
        fsInfo = Info()
        fsInfo.fileName = fsFileName
        
        fsFile.seekToFileOffset(0)
        fsFile.readDataOfLength(sizeof(block_size_t)).getBytes(&fsInfo.blockSize, length: sizeof(block_size_t))
        fsFile.readDataOfLength(sizeof(file_size_t)).getBytes(&fsInfo.blocksCount, length: sizeof(file_size_t))
        fsFile.readDataOfLength(sizeof(size_t)).getBytes(&fsInfo.descriptorsCount, length: sizeof(size_t))
        for _ in 0 ..< fsInfo.blocksCount {
            var blockSate = false
            fsFile.readDataOfLength(sizeof(Bool)).getBytes(&blockSate, length: sizeof(Bool))
            if blockSate {
                fsInfo.usedBlocksCount += 1
            } else {
                fsInfo.freeBlocksCount += 1
            }
        }
        for _ in 0 ..< fsInfo.descriptorsCount {
            let descriptor = Descriptor(data: fsFile.readDataOfLength(Descriptor.size))
            if descriptor.linksCount > 0 {
                fsInfo.usedDescriptorsCount += 1
            } else {
                fsInfo.freeDescriptorsCount += 1
            }
        }
        fsInfo.linksCount = fsInfo.descriptorsCount * Limits.MaxFileLinksCount
        for _ in 0 ..< fsInfo.linksCount {
            fsFile.seekToFileOffset(fsFile.offsetInFile + UInt64(Limits.MaxFileNameLength) * UInt64(sizeof(CChar)))
            
            var descriptorIndex: size_t? = nil
            fsFile.readDataOfLength(sizeof(size_t?)).getBytes(&descriptorIndex, length: sizeof(size_t?))
            if descriptorIndex != nil {
                fsInfo.usedLinksCount += 1
            } else {
                fsInfo.availableLinksCount += 1
            }
        }
        
        loadOpenedFilesTable()
    }
    
    // MARK: Commands
    
    ///
    /// Format file `fileName` as filesystem.
    ///
    /// - parameters:
    ///   - fileName: Name of file to be formated.
    ///   - size: Size of new filesystem in bytes (Actualy, the size of file).
    ///   - blockSize: Size of block in bytes.
    ///   - descriptorsCount: Maximum amount of files in new filesystem.
    ///
    func format(fileName fileName: String, size: file_size_t, blockSize: block_size_t, descriptorsCount: size_t) {
        
        if let fsFileName = NSUserDefaults.standardUserDefaults().valueForKey("fs-file-name") as? String {
            if fsFileName == fileName {
                umount()
            }
        }
        
        let fileNameLastPathComponent = (fileName as NSString).lastPathComponent
        
        // Prepare fs atributes
        var fsBlockSize = blockSize
        var fsBlocksCount: file_size_t
        var fsDescriptorsCount = descriptorsCount
        var fsBlocksBitmapDefaultValue = false
        
        let totalLinksCount = fsDescriptorsCount * Limits.MaxFileLinksCount // Number of pairs 'Name' - 'Descriptor'
        let linksTableSize = UInt64(Link.size) * UInt64(totalLinksCount)
        
        // Calculate count of blocks
        var headerSize =
            UInt64(sizeof(block_size_t)) +                                      // Block size
                UInt64(sizeof(file_size_t)) +                                   // Blocks count
                UInt64(sizeof(size_t)) +                                        // Descriptors count
                UInt64(FileSystem.Descriptor.size * Int(fsDescriptorsCount)) +  // Descriptors
                UInt64(linksTableSize)                                          // Links table
        if size < headerSize {
            Logger.error("Unable to foramt filesystem. No free space to store headers...")
            return
        }
        let freeSize = size - headerSize
        fsBlocksCount = freeSize / UInt64(fsBlockSize)
        var blocksBitmapSize = fsBlocksCount * UInt64(sizeof(Bool))
        let maxIterationsCount = fsBlocksCount
        var iterationsCount: file_size_t = 0
        while freeSize < (blocksBitmapSize + fsBlocksCount * UInt64(fsBlockSize)) &&
            iterationsCount <= maxIterationsCount {
                fsBlocksCount -= 1
                blocksBitmapSize = fsBlocksCount * UInt64(sizeof(Bool))
                iterationsCount += 1
        }
        
        headerSize += blocksBitmapSize
        if size < (headerSize + fsBlocksCount * UInt64(fsBlockSize)) ||
            iterationsCount == maxIterationsCount {
            Logger.error("Unable to foramt filesystem. No free space to store headers...")
            return
        }
        
        // Create fs file structure
        if let file = NSFileHandle(forWritingAtPath: fileName) {
            Logger.log("Formating...")
            
            file.truncateFileAtOffset(0)
            file.truncateFileAtOffset(size)
            file.seekToFileOffset(0)
            
            file.writeData(NSData(bytes: &fsBlockSize, length: sizeof(block_size_t)))   // Block size
            file.writeData(NSData(bytes: &fsBlocksCount, length: sizeof(file_size_t)))  // Blocks count
            file.writeData(NSData(bytes: &fsDescriptorsCount, length: sizeof(size_t)))  // Descriptors count
            for _ in 0 ..< fsBlocksCount {                                              // Blocks bitmap
                file.writeData(NSData(bytes: &fsBlocksBitmapDefaultValue, length: sizeof(Bool)))
            }
            for _ in 0 ..< fsDescriptorsCount {                                         // Descriptors
                file.writeData(Descriptor().toNSData())
            }
            for _ in 0 ..< totalLinksCount {                                            // Links table
                file.writeData(Link().toNSData())
            }
            
            file.closeFile()
            
            Logger.log("File '\(fileNameLastPathComponent)' has been formated as filesystem...")
        } else {
            Logger.error("Unable to foramt filesystem. Unable to open file '\(fileNameLastPathComponent)'...")
        }
    }
    
    ///
    /// Mount `fileName` as filesystem.
    ///
    /// - parameters:
    ///   - fileName: Name of file to be mounted as filesystem.
    ///
    func mount(fileName fileName: String) {
        umount(quite: true)
        
        let fileNameLastPathComponent = (fileName as NSString).lastPathComponent
        
        if let file = NSFileHandle(forReadingAtPath: fileName) {
            let fileAbsolutePath = NSURL(fileURLWithPath: fileName).path!
            NSUserDefaults.standardUserDefaults().setValue(fileAbsolutePath, forKey: "fs-file-name")
            file.closeFile()
            shadowMount()
            Logger.log("Filesystem '\(fileNameLastPathComponent)' has been mounted...")
        } else {
            Logger.error("Unable to mount filesystem '\(fileNameLastPathComponent)'...")
        }
    }
    
    ///
    /// Unmount filesystem.
    ///
    func umount(quite quite: Bool = false) {
        
        // Close all opened files
        openedFiles = [:]
        saveOpenedFilesTable()
        
        if let fsFileName = NSUserDefaults.standardUserDefaults().valueForKey("fs-file-name") as? String {
            if fsFile != nil {
                fsFile.closeFile()
                fsFile = nil
            }
            NSUserDefaults.standardUserDefaults().removeObjectForKey("fs-file-name")
            if !quite {
                let fileNameLastPathComponent = (fsFileName as NSString).lastPathComponent
                Logger.log("Filesystem '\(fileNameLastPathComponent)' has been unmouned...")
            }
        } else {
            if !quite {
                Logger.error("No filesystem mounted...")
            }
        }
    }
    
    ///
    /// Create file
    ///
    /// - parameters:
    ///   - fileName: Name of file to be created.
    ///
    func create(fileName fileName: String) {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return
        }
        
        guard fsInfo.freeDescriptorsCount > 0 else {
            Logger.error("Unable to create file: there are no more available descriptors...")
            return
        }
        
        guard fileName.characters.count <= Int(Limits.MaxFileNameLength) else {
            Logger.error("File name length owerflows all limits...")
            return
        }
        
        guard !fileName.isEmpty else {
            Logger.error("Illegal file name...")
            return
        }
        
        var linkIndex: size_t! = nil
        var descriptorIndex: size_t! = nil
        
        // Check if there is no file with such name
        // Find free link
        for i in 0 ..< fsInfo.linksCount {
            let link = getLinkWithIndex(index: i)
            
            // Check if there is no file with such name
            if link.name == fileName {
                Logger.error("File with such name already exists...")
                return
            }
            
            // Find free link
            if link.descriptorIndex == nil && linkIndex == nil {
                linkIndex = i
            }
        }
        
        // Find free descriptor and it's index
        for i in 0 ..< fsInfo.descriptorsCount {
            let descriptor = getDescriptorWithIndex(index: i)
            if descriptor.linksCount == 0 {
                descriptorIndex = i
                break
            }
        }
        
        // Create descriptor and save it
        var descriptor = Descriptor()
        descriptor.linksCount = 1
        setDescriptor(descriptor, withIndex: descriptorIndex)
        
        // Create link to descriptor
        let link = Link(name: fileName, descriptorIndex: descriptorIndex)
        setLink(link, withIndex: linkIndex)
        
        updateFsInfo()
        Logger.log("File '\(fileName)' created...")
    }
    
    ///
    /// Cretaes link to the file `fileName` with name `linkName`.
    ///
    /// - parameters:
    ///   - fileName: Name of the file source file.
    ///   - linkName: Name of the link.
    ///
    func link(fileName sourceFileName: String, linkName: String) {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return
        }
        
        guard linkName.characters.count <= Int(Limits.MaxFileNameLength) else {
            Logger.error("Link name length owerflows all limits...")
            return
        }
        
        var linkIndex: size_t! = nil
        var descriptorIndex: size_t! = nil
        
        // Check if there is no file with such name
        // Get source file descriptor index
        // Find free link
        for i in 0 ..< fsInfo.linksCount {
            let link = getLinkWithIndex(index: i)
            
            // Check if there is no file with such name
            if link.name == linkName {
                Logger.error("Link with such name already exists...")
                return
            }
            
            // Find source file descriptor index
            if let index = link.descriptorIndex {
                if link.name == sourceFileName {
                    descriptorIndex = index
                }
            }
            
            // Find free link
            if link.descriptorIndex == nil && linkIndex == nil {
                linkIndex = i
            }
        }
        
        if descriptorIndex == nil {
            Logger.error("No such file...")
            return
        }
        
        // Update descriptor
        var descriptor = getDescriptorWithIndex(index: descriptorIndex)
        if descriptor.linksCount >= Limits.MaxFileLinksCount {
            Logger.error("Links limit owerflow...")
            return
        }
        descriptor.linksCount += 1
        setDescriptor(descriptor, withIndex: descriptorIndex)
        
        // Create link to descriptor
        let link = Link(name: linkName, descriptorIndex: descriptorIndex)
        setLink(link, withIndex: linkIndex)
        
        updateFsInfo()
        Logger.log("Link created...")
    }
    
    ///
    /// Remove link.
    ///
    /// If there are no links to descriptor, it will be removed.
    ///
    /// - parameters:
    ///   - linkName: Name of link to be removed.
    ///
    func unlink(linkName linkName: String) {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return
        }
        
        var linkIndex: size_t! = nil
        var descriptorIndex: size_t! = nil
        
        // Get file descriptor index
        for i in 0 ..< fsInfo.linksCount {
            let link = getLinkWithIndex(index: i)
            
            if let index = link.descriptorIndex {
                if link.name == linkName {
                    linkIndex = i
                    descriptorIndex = index
                    break
                }
            }
        }
        
        if descriptorIndex == nil {
            Logger.error("No such file...")
            return
        }
        
        var descriptor = getDescriptorWithIndex(index: descriptorIndex)
        
        // Clear blocks
        if descriptor.linksCount == 1 {
            for (i, block) in descriptor.blocks.enumerate() {
                if block != nil {
                    setBlockState(false, atIndex: file_size_t(i))
                } else {
                    break
                }
            }
        }
        
        // Update descriptor
        descriptor.linksCount -= 1
        setDescriptor(descriptor, withIndex: descriptorIndex)
        
        // Remove link to descriptor
        setLink(Link(), withIndex: linkIndex)
        
        updateFsInfo()
        Logger.log("Link removed...")
    }
    
    ///
    /// Open file and creates file descriptor for it.
    ///
    /// - parameters:
    ///   - fileName: Name of file to open.
    /// - returns: Opened file descriptor.
    ///
    func open(fileName fileName: String) -> size_t? {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return nil
        }
        
        guard openedFiles.count <= Int(Limits.MaxOpenedFilesCount) else {
            Logger.error("Opened files count overflows all limits...")
            return nil
        }
        
        var fd: size_t? = nil
        
        if let descriptorIndex = getDescriptorIndexForFileName(fileName) {
            
            // If file is already opened
            if openedFiles.values.contains(descriptorIndex) {
                for key in openedFiles.keys {
                    if openedFiles[key] == descriptorIndex {
                        return key
                    }
                }
            }
            
            // Find free fd
            for i in 0 ..< Limits.MaxOpenedFilesCount {
                if !openedFiles.keys.contains(i) {
                    openedFiles[i] = descriptorIndex
                    fd = i
                    break
                }
            }
        } else {
            Logger.error("No such file...")
        }
        
        saveOpenedFilesTable()
        
        return fd
    }
    
    ///
    /// Close file with specific descriptor.
    ///
    /// - parameters:
    ///   - fd: Opened file descriptor.
    ///
    func close(fd fd: size_t) {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return
        }
        
        guard openedFiles.keys.contains(fd) else {
            Logger.error("No opened file with such descriptor...")
            return
        }
        
        openedFiles.removeValueForKey(fd)
        saveOpenedFilesTable()
    }
    
    ///
    /// Close all opened files.
    ///
    func closeAll() {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return
        }
        
        openedFiles = [:]
        saveOpenedFilesTable()
    }
    
    ///
    /// Write data to file with descriptor `fd`
    ///
    /// - parameters:
    ///   - fd: Opened file descriptor.
    ///   - offset: Positon in file to strat writing.
    ///   - data: Data to write.
    ///
    func write(fd fd: size_t, offset: file_size_t, data: [UInt8]) {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return
        }
        
        guard openedFiles.keys.contains(fd) else {
            Logger.error("No opened file with such fd...")
            return
        }
        
        if let descriptor = getDescriptorWithIndex(index: openedFiles[fd]!) {
            
            if (offset + UInt64(data.count) * UInt64(sizeof(UInt8))) > descriptor.fileSize {
                Logger.error("File size overflow...")
                return
            }
            
            let bytesCount = (UInt64(data.count) / UInt64(sizeof(UInt8)))
            var writenBytesCount: file_size_t = 0
            var currentOffset = offset
            
            while writenBytesCount < bytesCount {
                let blockNumber = size_t(currentOffset / UInt64(fsInfo.blockSize))
                var blockBytesCount = block_size_t(UInt64(fsInfo.blockSize) - currentOffset % UInt64(fsInfo.blockSize))
                let startByteIndex = block_size_t(UInt64(fsInfo.blockSize) / UInt64(sizeof(UInt8)) - UInt64(blockBytesCount))
                
                if UInt64(blockBytesCount) > (bytesCount - writenBytesCount) {
                    blockBytesCount = block_size_t(bytesCount - writenBytesCount)
                }
                
                let blockIndex = descriptor.blocks[Int(blockNumber)]
                if blockIndex == nil {
                    Logger.error("Something wrong with filesystem structure...")
                }
                
                var blockData = readBlockWithIndex(blockIndex!)
                if blockData == nil {
                    Logger.error("Something wrong with filesystem structure...")
                }
                
                for i in startByteIndex ..< (startByteIndex + blockBytesCount) {
                    blockData![Int(i)] = data[Int(writenBytesCount) + Int(i) - Int(startByteIndex)]
                }
                
                writeBlockWithIndex(blockIndex!, data: blockData!)
                writenBytesCount += file_size_t(blockBytesCount)
                currentOffset += file_size_t(blockBytesCount)
            }
            
        } else {
            Logger.error("Unable to open file...")
        }
    }
    
    ///
    /// Read data from file with descriptor `fd`
    ///
    /// - parameters:
    ///   - fd: Opened file descriptor.
    ///   - offset: Positon in file to strat reading.
    ///   - size: Size of data to read.
    ///
    func read(fd fd: size_t, offset: file_size_t, size: file_size_t) -> [UInt8]? {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return nil
        }
        
        guard openedFiles.keys.contains(fd) else {
            Logger.error("No opened file with such fd...")
            return nil
        }
        
        if let descriptor = getDescriptorWithIndex(index: openedFiles[fd]!) {
            
            if (offset + size * UInt64(sizeof(UInt8))) > descriptor.fileSize {
                Logger.error("Reading out of file...")
                return nil
            }
            
            var data: [UInt8] = []
            
            let bytesCount = (size / UInt64(sizeof(UInt8)))
            var readBytesCount: file_size_t = 0
            var currentOffset = offset
            
            while readBytesCount < bytesCount {
                let blockNumber = size_t(currentOffset / UInt64(fsInfo.blockSize))
                var blockBytesCount = block_size_t(UInt64(fsInfo.blockSize) - currentOffset % UInt64(fsInfo.blockSize))
                let startByteIndex = block_size_t(UInt64(fsInfo.blockSize) / UInt64(sizeof(UInt8)) - UInt64(blockBytesCount))
                
                if UInt64(blockBytesCount) > (bytesCount - readBytesCount) {
                    blockBytesCount = block_size_t(bytesCount - readBytesCount)
                }
                
                let blockIndex = descriptor.blocks[Int(blockNumber)]
                if blockIndex == nil {
                    Logger.error("Something wrong with filesystem structure...")
                }
                
                var blockData = readBlockWithIndex(blockIndex!)
                if blockData == nil {
                    Logger.error("Something wrong with filesystem structure...")
                }
                
                for i in startByteIndex ..< (startByteIndex + blockBytesCount) {
                    data += [blockData![Int(i)]]
                }
                
                readBytesCount += file_size_t(blockBytesCount)
                currentOffset += file_size_t(blockBytesCount)
            }
            
            return data
            
        } else {
            Logger.error("Unable to open file...")
        }
        
        return nil
    }
    
    ///
    /// Change the file size to `size` in bytes.
    ///
    /// - parameters:
    ///   - fileName: Name of file.
    ///   - size: New file size in bytes.
    ///
    func truncate(fileName fileName: String, size: file_size_t) {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return
        }
        
        if let descriptorIndex = getDescriptorIndexForFileName(fileName) {
            var descriptor = getDescriptorWithIndex(index: descriptorIndex)
            
            let blocksCount = file_size_t(ceil(1.0 * Double(size) / Double(fsInfo.blockSize)))
            
            var usedBlocksCount: file_size_t = 0;
            for block in descriptor.blocks {
                if block != nil {
                    usedBlocksCount += 1
                } else {
                    break
                }
            }
            if blocksCount < usedBlocksCount { // Reduce file size
                for i in blocksCount ..< usedBlocksCount {
                    setBlockState(false, atIndex: descriptor.blocks[Int(i)]!)
                    descriptor.blocks[Int(i)] = nil
                }
            } else if blocksCount > usedBlocksCount { // Increase file size
                if (blocksCount - usedBlocksCount) > fsInfo.freeBlocksCount {
                    Logger.error("No free space...")
                    return
                }
                for i in usedBlocksCount ..< blocksCount {
                    let blockIndex = getFreeBlock()!
                    descriptor.blocks[Int(i)] = blockIndex
                    setBlockState(true, atIndex: blockIndex)
                }
            } else {
                Logger.log("No need to change file size...")
                return
            }
            
            descriptor.fileSize = size
            setDescriptor(descriptor, withIndex: descriptorIndex)
            
            updateFsInfo()
            Logger.log("File size changed...")
        } else {
            Logger.error("No such file...")
        }
    }
    
    ///
    /// Returns files list.
    ///
    /// - returns: Array of tuples (name, descriptorIndex).
    ///
    func list() -> [(name: String, descriptorIndex: size_t, isOpened: Bool)] {
        
        guard isMounted else {
            Logger.error("No filesystem mounted...")
            return []
        }
        
        var filesList: [(name: String, descriptorIndex: size_t, isOpened: Bool)] = []
        for i in 0 ..< fsInfo.linksCount {
            let link = getLinkWithIndex(index: i)
            if link.descriptorIndex != nil {
                let isOpened = openedFiles.values.contains(link.descriptorIndex!)
                filesList += [(link.name, link.descriptorIndex!, isOpened: isOpened)]
            }
        }
        
        return filesList
    }
    
    ///
    /// Returns file's info.
    ///
    /// - returns: Tuple of file's attributes
    ///
    func filestat(fileName fileName: String) -> (
        name: String,
        descriptorIndex: size_t,
        size: file_size_t,
        blocksCount: file_size_t,
        linksCount: size_t)? {
            
            guard isMounted else {
                Logger.error("No filesystem mounted...")
                return nil
            }
            
            if let descriptorIndex = getDescriptorIndexForFileName(fileName) {
                let descriptor = getDescriptorWithIndex(index: descriptorIndex)
                
                let info = (name: fileName,
                            descriptorIndex: descriptorIndex,
                            size: descriptor.fileSize,
                            blocksCount: file_size_t(descriptor.blocks.filter({ $0 != nil }).count),
                            linksCount: descriptor.linksCount)
                
                return info
            } else {
                Logger.error("No such file...")
            }
            return nil
    }
    
    
    // MARK: FS Tools
    
    private func getLinkWithIndex(index index: size_t) -> Link! {
        
        guard isMounted && index < fsInfo.linksCount else {
            return nil
        }
        
        fsFile.seekToFileOffset(offsets.linksOffset + UInt64(Link.size) * UInt64(index))
        return Link(data: fsFile.readDataOfLength(Link.size))
    }
    
    private func setLink(link: Link, withIndex index: size_t) {
        
        guard isMounted && index < fsInfo.linksCount else {
            return
        }
        
        fsFile.seekToFileOffset(offsets.linksOffset + UInt64(Link.size) * UInt64(index))
        fsFile.writeData(link.toNSData())
    }
    
    private func getDescriptorWithIndex(index index: size_t) -> Descriptor! {
        
        guard isMounted && index < fsInfo.descriptorsCount else {
            return nil
        }
        
        fsFile.seekToFileOffset(offsets.descriptorsOffset + UInt64(Descriptor.size) * UInt64(index))
        return Descriptor(data: fsFile.readDataOfLength(Descriptor.size))
    }
    
    private func getDescriptorForFileName(fileName: String) -> Descriptor? {
        
        guard isMounted else {
            return nil
        }
        
        if let descriptorIndex = getDescriptorIndexForFileName(fileName) {
            return getDescriptorWithIndex(index: descriptorIndex)
        }
        return nil
    }
    
    private func getDescriptorIndexForFileName(fileName: String) -> size_t? {
        
        guard isMounted else {
            return nil
        }
        
        // Get file descriptor index
        for i in 0 ..< fsInfo.linksCount {
            let link = getLinkWithIndex(index: i)
            
            if let index = link.descriptorIndex {
                if link.name == fileName {
                    return index
                }
            }
        }
        return nil
    }
    
    private func setDescriptor(descriptor: Descriptor, withIndex index: size_t) {
        
        guard isMounted && index < fsInfo.descriptorsCount else {
            return
        }
        
        fsFile.seekToFileOffset(offsets.descriptorsOffset + UInt64(Descriptor.size) * UInt64(index))
        fsFile.writeData(descriptor.toNSData())
    }
    
    private func getBlockStateAtIndex(index: file_size_t) -> Bool {
        
        guard isMounted && index < fsInfo.blocksCount else {
            return false
        }
        
        var state = false
        fsFile.seekToFileOffset(offsets.blocksBitmapOffset + UInt64(sizeof(Bool)) * index)
        fsFile.readDataOfLength(sizeof(Bool)).getBytes(&state, length: sizeof(Bool))
        
        return state
    }
    
    private func setBlockState(state: Bool, atIndex index: file_size_t) {
        
        guard isMounted && index < fsInfo.blocksCount else {
            return
        }
        
        var state = state
        fsFile.seekToFileOffset(offsets.blocksBitmapOffset + UInt64(sizeof(Bool)) * index)
        fsFile.writeData(NSData(bytes: &state, length: sizeof(Bool)))
    }
    
    private func getFreeBlock() -> file_size_t? {
        for i in 0 ..< fsInfo.blocksCount {
            if getBlockStateAtIndex(i) == false {
                return i
            }
        }
        return nil
    }
    
    private func writeBlockWithIndex(index: file_size_t, data: [UInt8]) {
        
        guard index < fsInfo.blocksCount else {
            return
        }
        
        guard block_size_t(data.count * sizeof(UInt8)) == fsInfo.blockSize else {
            return
        }
        var data = data
        fsFile.seekToFileOffset(offsets.dataBlocksOffset + UInt64(fsInfo.blockSize) * index)
        fsFile.writeData(NSData(bytes: &data, length: data.count * sizeof(UInt8)))
    }
    
    private func readBlockWithIndex(index: file_size_t) -> [UInt8]? {
        
        guard index < fsInfo.blocksCount else {
            return nil
        }
        
        let bytesCount = Int(fsInfo.blockSize) / sizeof(UInt8)
        var data = [UInt8](count: bytesCount, repeatedValue: 0)
        
        fsFile.seekToFileOffset(offsets.dataBlocksOffset + UInt64(fsInfo.blockSize) * index)
        fsFile.readDataOfLength(Int(fsInfo.blockSize)).getBytes(&data, length: bytesCount)
        
        return data
    }
    
    private func saveOpenedFilesTable() {
        var openedFilesTable: [String: Int] = [:]
        for (key, value) in openedFiles {
            openedFilesTable["\(key)"] = Int(value)
        }
        let data = NSKeyedArchiver.archivedDataWithRootObject(openedFilesTable)
        NSUserDefaults.standardUserDefaults().setValue(data, forKey: "open-files")
    }
    
    private func loadOpenedFilesTable() {
        if let data = NSUserDefaults.standardUserDefaults().valueForKey("open-files") as? NSData,
            let openedFilesTable = NSKeyedUnarchiver.unarchiveObjectWithData(data)! as? NSDictionary {
            openedFiles = [:]
            for (key, value) in openedFilesTable {
                openedFiles[size_t(key as! String)!] = size_t(value as! Int)
            }
        } else {
            Logger.log("Unable to load opened files table...")
        }
    }
    
    // MARK:
    
    ///
    /// Descrtiption of filesystem.
    ///
    /// String representation of `info`.
    ///
    var description: String {
        
        guard isMounted else {
            return "No system – no description =)"
        }
        
        var description = "Filesystem '\(fsInfo.fileName)':\n"
        description += "\tBlock size        – \(fsInfo.blockSize)B\n\n"
        description += "\tBlocks count      – \(fsInfo.blocksCount)\n"
        description += "\tUsed blocks       – \(fsInfo.usedBlocksCount)\n"
        description += "\tFree blocks       – \(fsInfo.freeBlocksCount)\n\n"
        description += "\tDescriptors count – \(fsInfo.descriptorsCount)\n"
        description += "\tUsed descriptors  – \(fsInfo.usedDescriptorsCount)\n"
        description += "\tFree descriptors  – \(fsInfo.freeDescriptorsCount)\n\n"
        description += "\tLinks count       – \(fsInfo.linksCount)\n"
        description += "\tUsed links        – \(fsInfo.usedLinksCount)\n"
        description += "\tAvailable links   – \(fsInfo.availableLinksCount)"
        return description
        
    }
    
}