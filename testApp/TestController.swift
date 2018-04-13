//
//  TestController.swift
//  testApp
//
//  Created by Сергей Сейтов on 11.04.2018.
//  Copyright © 2018 V-Channel. All rights reserved.
//

import UIKit
import MobileCoreServices
import AVFoundation
import AVKit

extension OutputStream {
    func write(data: Data) -> Int {
        return data.withUnsafeBytes { write($0, maxLength: data.count) }
    }
}
extension String {
    
    func digitsFromString() -> String {
        let digitSet = CharacterSet.decimalDigits
        let filteredCharacters = self.filter {
            return  String($0).rangeOfCharacter(from: digitSet) != nil
        }
        return String(filteredCharacters)
    }
    
}

class TestController: UITableViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate {

    var files:[URL] = []
    var meta:[AnyHashable:Any]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    var dateFormatter:DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss";
        return formatter
    }
    
    func refresh() {
        files = dirContent(mediaDirectory()).filter({ file in
            return file.pathExtension.lowercased() == "mov"
        })
        tableView.reloadData()
    }

    func clear() {
        clearURL(mediaDirectory())
        do {
            try FileManager.default.createDirectory(at: mediaDirectory(), withIntermediateDirectories: false, attributes: nil)
        } catch {
            print(error.localizedDescription)
        }
        meta = nil
        tableView.reloadData()
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return files.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let url = files[indexPath.row]
        cell.textLabel?.text = url.lastPathComponent
        cell.detailTextLabel?.text = "\(fileSizeFromURL(url))"
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        performSegue(withIdentifier: "showMovie", sender: files[indexPath.row])
    }

/*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            try? FileManager.default.removeItem(at: files[indexPath.row])
            files.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let url = files[indexPath.row]
        let hls = HLS_Converter()
        let hlsURL = mediaDirectory().appendingPathComponent("list.m3u8")
        if hls.open(url.relativePath, info: nil) {
            hls.convert(to: hlsURL.relativePath, doSegments: true, progressBlock: { progress in
                print(">>>>>>>>>> segmenting \(progress)")
            }, completionBlock: { success in
                hls.close()
                if success {
                    let tsFile = mediaDirectory().appendingPathComponent("output.ts")
                    let stream = OutputStream(url: tsFile, append: false)
                    let tsContent = dirContent(mediaDirectory()).filter( {url in
                        return url.pathExtension == "ts"
                    })
                    let sorted = tsContent.sorted(by: { url1, url2 in
                        return url1.relativePath < url2.relativePath
                    })
                    stream?.open()
                    for file in sorted {
                        if let data = try? Data(contentsOf: file) {
                            _ = stream?.write(data: data)
                            print("wrine \(file.lastPathComponent)")
                        }
                        try? FileManager.default.removeItem(at: file)
                    }
                    stream?.close()
                    
                    let info = hls.info
                    hls.close()
                    
                    if hls.open(tsFile.relativePath, info: info) {
                        let outFile = mediaDirectory().appendingPathComponent("output.mov")
                        hls.convert(to: outFile.relativePath, doSegments: false, progressBlock: { progress in
                            print("<<<<<<<<<<< desegmenting \(progress)")
                        }, completionBlock: { success in
                            print(success)
                            self.refresh()
                        })
                    }
                } else {
                    print("error")
                }
            })
        }
    }
 */
    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let url = sender as! URL
        if segue.identifier == "showMovie" {
            let player = AVPlayer(url: url)
            let next = segue.destination as! AVPlayerViewController
            next.player = player
        }
    }
    
    // MARK: - UIImagePickerController delegate
    
    @IBAction func addMoview(_ sender: Any) {
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let imagePickerController = UIImagePickerController()
            imagePickerController.sourceType = .photoLibrary
            imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary)!
            imagePickerController.delegate = self
            imagePickerController.allowsEditing = false
            imagePickerController.videoQuality = .typeHigh
            self.present(imagePickerController, animated: true, completion:nil)
        }
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        let mediaType = info[UIImagePickerControllerMediaType] as! String
        picker.dismiss(animated: true, completion: {
            if mediaType == kUTTypeMovie as String {
                if let url = info[UIImagePickerControllerMediaURL] as? URL {
                    let name = "\(self.dateFormatter.string(from: Date())).MOV"
                    let dstURL = mediaDirectory().appendingPathComponent(name)
                    self.clear()
                    do {
                        try FileManager.default.copyItem(at: url, to: dstURL)
                        let hlsURL = mediaDirectory().appendingPathComponent("index.m3u8")
                        self.convertVideo(dstURL, to: hlsURL, info: nil, result: { meta in
                            if meta != nil {
                                self.meta = meta
                                self.refresh()
                            } else {
                                print("import error")
                                self.clear()
                            }
                        })
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
        })
    }
    
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func export(_ sender: Any) {
        
        let tsContent = dirContent(mediaDirectory()).filter( {url in
            return url.pathExtension == "ts"
        })

        let sorted = tsContent.sorted(by: { url1, url2 in
            if let num1 = Int(url1.lastPathComponent.digitsFromString()), let num2 = Int(url2.lastPathComponent.digitsFromString()) {
                return num1 < num2
            } else {
                return false
            }
        })
        
        let tsFile = mediaDirectory().appendingPathComponent("output.ts")
        let stream = OutputStream(url: tsFile, append: false)
        stream?.open()
        for file in sorted {
            print(file.lastPathComponent)
            if let data = try? Data(contentsOf: file) {
                _ = stream?.write(data: data)
            }
        }
        stream?.close()
        print(fileSizeFromURL(tsFile))
        let exportURL = mediaDirectory().appendingPathComponent("export.mov")
        convertVideo(tsFile, to: exportURL, info: meta, result: { info in
            if info != nil {
                self.refresh()
            } else {
                self.clear()
            }
        })
    }
    
    private func convertVideo(_ from:URL, to:URL, info:[AnyHashable : Any]?, result: (([AnyHashable : Any]?) -> Void)!) {
        let converter = HLS_Converter()

        var meta:[AnyHashable : Any]?
        if (info == nil) {
            meta = converter.open(from.relativePath)
            if meta == nil {
                result(nil)
                return
            }
        } else if !converter.open(withInfo: from.relativePath) {
            result(nil)
            return
        }
        
        let fileSize = fileSizeFromURL(from)
        var currentProgress = 0
        converter.convert(to: to.relativePath, info: info, progressBlock: { progress in
            if progress <= fileSize {
                let newProgress = Int(Double(progress)/Double(fileSize) * 100.0)
                if (newProgress >  currentProgress) {
                    currentProgress = newProgress
                    print(currentProgress)
                }
            }
        }, completionBlock: { success in
            if success {
                if info == nil {
                    result(meta)
                } else {
                    result(info)
                }
            } else {
                result(nil)
            }
        })
    }

}
