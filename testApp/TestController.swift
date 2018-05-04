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
import Photos
import AssetsLibrary

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

class TestController: UITableViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate, AddAssetControllerDelegate {

    var files:[URL] = []
    var meta:[AnyHashable:Any]?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print(mediaDirectory().relativePath)
        refresh()
    }

    var dateFormatter:DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss";
        return formatter
    }
    
    func refresh() {
        files = dirContent(mediaDirectory())
/*
        files = dirContent(mediaDirectory()).filter({ file in
            return file.pathExtension.lowercased() == "mov"
        })
 */
        tableView.reloadData()
    }

    func clear() {
        clearURL(mediaDirectory())
        do {
            try FileManager.default.createDirectory(at: mediaDirectory(), withIntermediateDirectories: false, attributes: nil)
        } catch {
            print(error.localizedDescription)
        }
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
        let url = files[indexPath.row]
        performSegue(withIdentifier: "showMovie", sender: url)
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let url = files[indexPath.row]
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { completed, error in
            DispatchQueue.main.async {
                self.refresh()
                if error != nil {
                    print(error!.localizedDescription)
                } else if completed {
                    print("============ file exported")
                } else {
                    print("unknown error")
                }
            }
        })
    }
    
    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let url = sender as! URL
        if segue.identifier == "showMovie" {
            let player = AVPlayer(url: url)
            let next = segue.destination as! AVPlayerViewController
            next.player = player
        }
    }
    
    @IBAction func addMoview(_ sender: Any) {
        AddAssetController.checkPermission({ enabled in
            if enabled {
                let picker = UIStoryboard(name: "AssetPicker", bundle: nil)
                let nav = picker.instantiateViewController(withIdentifier: "AssetPicker") as? UINavigationController
                if nav != nil {
                    if let controller = nav!.topViewController as? AddAssetController {
                        controller.delegate = self
                    }
                    nav!.modalPresentationStyle = .formSheet
                    self.present(nav!, animated: true, completion: nil)
                }
            } else {
                print("You must enable access to Photo Library in cryptoBox settings.")
            }
        })
 /*
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            let imagePickerController = UIImagePickerController()
            imagePickerController.sourceType = .photoLibrary
            imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary)!
            imagePickerController.delegate = self
            imagePickerController.allowsEditing = false
            imagePickerController.videoQuality = .typeHigh
            self.present(imagePickerController, animated: true, completion:nil)
        }
 */
    }
/*
    // MARK: - UIImagePickerController delegate
    
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
                                print(meta!)
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
 */
    // MARK: - AddAssetControllerDelegate
    
    func didAssetPickerSelected(_ selectedAssets:NSMutableArray) {
        if let asset = selectedAssets.object(at: 0) as? AssetWithContent {
            importAsset(asset)
        }
        dismiss(animated: true, completion: nil)
    }
    
    func didAssetPickerCanceled() {
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: - Import

    func importAsset(_ asset:AssetWithContent) {
        let options = PHVideoRequestOptions()
        options.version = .original
        options.isNetworkAccessAllowed = false
        _ = PHImageManager.default().requestAVAsset(forVideo: asset.phAsset!, options: options, resultHandler: { avAsset, _, info in
            guard let urlAsset = avAsset as? AVURLAsset else {
                return
            }
            DispatchQueue.main.async {
                self.importURL(urlAsset.url)
            }
        })
    }

    func importURL(_ url:URL) {
        clear()
        let outURL = mediaDirectory().appendingPathComponent("original.mov")
        print(outURL.relativePath)
        try? FileManager.default.copyItem(at: url, to: outURL)
        let tsURL = mediaDirectory().appendingPathComponent("index.m3u8")
        convertVideo(outURL, to: tsURL, info: nil, result: { info in
            try? FileManager.default.removeItem(at: tsURL)
            if info != nil {
                self.meta = info
                print("import success")
                self.exportTS(info!)
                self.refresh()
            }
        })
    }
    
    // MARK: - Export

    func exportTS(_ meta:[AnyHashable:Any]) {

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
                try? FileManager.default.removeItem(at: file)
            }
        }
        stream?.close()
    }
    
    @IBAction func export(_ sender: Any) {
//        let url = URL(string: "https://bitmovin-a.akamaihd.net/content/dataset/multi-codec/hevc/stream_fmp4.m3u8")
//        let url = URL(string: "http://127.0.0.1:8080/index.m3u8")
//        performSegue(withIdentifier: "showMovie", sender: url)

        let tsFile = mediaDirectory().appendingPathComponent("output.ts")
        let exportURL = mediaDirectory().appendingPathComponent("export.mov")
        convertVideo(tsFile, to: exportURL, info: meta!, result: { info in
//            try? FileManager.default.removeItem(at: tsFile)
            self.refresh()
            if info != nil {
                print("success")
            } else {
                print("error")
            }
        })

/*
        let exportURL = mediaDirectory().appendingPathComponent("export.mov")
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: exportURL)
        }, completionHandler: { completed, error in
            DispatchQueue.main.async {
                if !completed {
                    print(error!.localizedDescription)
                } else {
                    print("============ file exported")
                }
            }
        })
*/
    }

    private func convertVideo(_ from:URL, to:URL, info:[AnyHashable : Any]?, result: (([AnyHashable : Any]?) -> Void)!) {
        let converter = HLS_Converter()

        var meta:[AnyHashable : Any]?
        if (info == nil) {
            meta = converter.openMovie(from.relativePath)
            if meta == nil {
                result(nil)
                return
            }
        } else if !converter.openStream(from.relativePath) {
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
//                    print(currentProgress)
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
