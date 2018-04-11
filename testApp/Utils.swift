//
//  Utils.swift
//  testApp
//
//  Created by Сергей Сейтов on 11.04.2018.
//  Copyright © 2018 V-Channel. All rights reserved.
//

import Foundation

func mediaDirectory() -> URL {
    let doc = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
    return doc.appendingPathComponent("media")
}

func clearURL(_ url:URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        print(error.localizedDescription)
    }
}

func fileSizeFromURL(_ url:URL) -> Int {
    if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path) as NSDictionary {
        return fileAttributes.fileSize().hashValue
    } else {
        return 0
    }
}

func dirContent(_ url:URL) -> [URL] {
    do {
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [])
    } catch {
        print(error.localizedDescription)
        return []
    }
}
