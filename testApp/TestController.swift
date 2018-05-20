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
    
    func videoRotation() -> Int {
        if let vm = meta!["videoMeta"] as? [String:Any] {
            if let rotate = vm["rotate"] as? String {
                if rotate == "270" {
                    return 3
                } else if rotate == "180" {
                    return 2
                } else if rotate == "90" {
                    return 1
                }
            }
        }
        return 0
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let url = sender as! URL
        if segue.identifier == "showMovie" {
            let next = segue.destination as! AVPlayerViewController //PlayerController
            next.player = AVPlayer(url: url)
//            next.url = url
//            next.rotation = videoRotation()
        }
    }
    
    @IBAction func addMoview(_ sender: Any) {
        let alert = UIAlertController(title: "Open", message: "Select source", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Camera Roll", style: .default, handler: { action in
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
        }))
        alert.addAction(UIAlertAction(title: "Camera", style: .default, handler: { action in
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                let imagePickerController = UIImagePickerController()
                imagePickerController.sourceType = .camera
                imagePickerController.mediaTypes = UIImagePickerController.availableMediaTypes(for: .camera)!
                imagePickerController.delegate = self
                imagePickerController.allowsEditing = false
                imagePickerController.videoQuality = .typeHigh
                self.present(imagePickerController, animated: true, completion:nil)
            }
        }))
        present(alert, animated: true, completion: nil)
    }

    // MARK: - UIImagePickerController delegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        let mediaType = info[UIImagePickerControllerMediaType] as! String
        picker.dismiss(animated: true, completion: {
            if mediaType == kUTTypeMovie as String {
                if let url = info[UIImagePickerControllerMediaURL] as? URL {
                    self.importURL(url)
                }
            }
        })
    }
    
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
 
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
        let tsURL = mediaDirectory().appendingPathComponent("list.m3u8")
        convertVideo(outURL, to: tsURL, info: nil, result: { info in
//            try? FileManager.default.removeItem(at: tsURL)
            if info != nil {
                self.meta = info
                print("import success")
//                self.exportTS()
            }
            self.refresh()
        })
    }
    
    // MARK: - Export
/*
    func exportTS() {

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
 */
    @IBAction func clear(_ sender: Any) {
        clear()
        refresh()
    }
    
    @IBAction func play(_ sender: Any) {
        let url = URL(string: "http://127.0.0.1:8080/list.m3u8")
        performSegue(withIdentifier: "showMovie", sender: url)
    }
    
    @IBAction func export(_ sender: Any) {
//        let url = URL(string: "http://127.0.0.1:8080/index.m3u8")
        let url = mediaDirectory().appendingPathComponent("list.m3u8")
        let exportURL = mediaDirectory().appendingPathComponent("export.mov")
        convertVideo(url, to: exportURL, info: meta!, result: { info in
            if info != nil {
                print("success")
                self.refresh()

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
 
            } else {
                print("error")
            }
        })
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
