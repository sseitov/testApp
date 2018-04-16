//
//  AddAssetController.swift
//  cryptoBox (MilCryptor Secure Platform)
//
//  Created by Denys Borysiuk on 19.07.16.
//  Copyright © 2016 ArchiSec Solutions, Ltd. All rights reserved.//
//

import UIKit
import Photos

protocol AddAssetControllerDelegate:class {
    func didAssetPickerSelected(_ selectedAssets:NSMutableArray)
    func didAssetPickerCanceled()
}

class AssetWithContent:NSObject {
    var phAsset:PHAsset?
    var thumb:UIImage?
    var content:Data?
    var name:String?
    var size:Int?
    
    init(phAsset:PHAsset?, thumb:UIImage?, content:Data? = nil, name:String? = nil) {
        super.init()
        self.phAsset = phAsset
        self.thumb = thumb
        self.content = content
        self.name = name
    }
}

class AddAssetController: UITableViewController, AssetContentControllerDelegate {

    var delegate:AddAssetControllerDelegate?
    
    var smartAlbums: [Any] = []
    var albumTitles: [String] = []
    
    let counter = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
    let selectedAssets:NSMutableArray = NSMutableArray()
    let deselectAllButton = UIButton(frame: CGRect(x: 0, y: 0, width: 100, height: 32))
    
    class func checkPermission(_ result:@escaping (Bool) -> ()) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized:
            result(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        result(true)
                    } else {
                        result(false)
                    }
                }
            })
        default:
            result(false)
        }
    }

    fileprivate func addAlbum(_ type:PHAssetCollectionType, subtype:PHAssetCollectionSubtype) {
        let result:PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: type, subtype: subtype, options: nil)
        if let collection = result.firstObject {
            let options = PHFetchOptions()
            options.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: true) ]
            let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
            if fetchResult.count > 0 {
                albumTitles.append(collection.localizedTitle!)
                smartAlbums.append(fetchResult)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Albums"
        navigationItem.rightBarButtonItem?.isEnabled = false

        addAlbum(.album, subtype: .albumMyPhotoStream)
        addAlbum(.album, subtype: .albumCloudShared)

        addAlbum(.smartAlbum, subtype: .smartAlbumGeneric)
        addAlbum(.smartAlbum, subtype: .smartAlbumPanoramas)
        addAlbum(.smartAlbum, subtype: .smartAlbumVideos)
        addAlbum(.smartAlbum, subtype: .smartAlbumFavorites)
        addAlbum(.smartAlbum, subtype: .smartAlbumTimelapses)
        addAlbum(.smartAlbum, subtype: .smartAlbumAllHidden)
        addAlbum(.smartAlbum, subtype: .smartAlbumRecentlyAdded)
        addAlbum(.smartAlbum, subtype: .smartAlbumBursts)
        addAlbum(.smartAlbum, subtype: .smartAlbumSlomoVideos)
        addAlbum(.smartAlbum, subtype: .smartAlbumUserLibrary)
        if #available(iOS 9.0, *) {
            addAlbum(.smartAlbum, subtype: .smartAlbumSelfPortraits)
        }
        if #available(iOS 9.0, *) {
            addAlbum(.smartAlbum, subtype: .smartAlbumScreenshots)
        }
        if #available(iOS 10.2, *) {
            addAlbum(.smartAlbum, subtype: .smartAlbumDepthEffect)
        }
        if #available(iOS 10.3, *) {
            addAlbum(.smartAlbum, subtype: .smartAlbumLivePhotos)
        }
        if #available(iOS 11.0, *) {
            addAlbum(.smartAlbum, subtype: .smartAlbumAnimated)
        }
        if #available(iOS 11.0, *) {
            addAlbum(.smartAlbum, subtype: .smartAlbumLongExposures)
        }
        
        let syncedResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumSyncedAlbum, options: nil)
        for i in 0..<syncedResult.count{
            let collection = syncedResult.object(at: i)
            let options = PHFetchOptions()
            options.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: true) ]
            let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
            albumTitles.append(collection.localizedTitle!)
            smartAlbums.append(fetchResult)
        }
        
        let importedResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        for i in 0..<importedResult.count{
            let collection = importedResult.object(at: i)
            let options = PHFetchOptions()
            options.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: true) ]
            let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
            albumTitles.append(collection.localizedTitle!)
            smartAlbums.append(fetchResult)
        }
 
        PHPhotoLibrary.shared().register(self)
        
        counter.text = "Nothing selected"
        counter.textAlignment = .right
        counter.textColor = UIColor.black
        counter.font = UIFont(name: "HelveticaNeue", size: 13)
        
        deselectAllButton.setTitle("Deselect all", for: UIControlState())
        deselectAllButton.setTitleColor(UIColor.lightGray, for: UIControlState())
        deselectAllButton.titleLabel?.font = UIFont(name: "HelveticaNeue", size: 17)
        deselectAllButton.addTarget(self, action: #selector(AddAssetController.deselectAll), for: .touchUpInside)
        deselectAllButton.isEnabled = false
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationItem.rightBarButtonItem?.isEnabled = selectedAssets.count > 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let content = UIBarButtonItem(customView: counter)
        let deselectAllButtonItem = UIBarButtonItem(customView: deselectAllButton)
        navigationController?.toolbar.setItems([deselectAllButtonItem, space, content], animated: false)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return smartAlbums.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! AssetCollectionCell

        cell.collectionTitle.text = albumTitles[(indexPath as NSIndexPath).row]
        cell.fetchResult = smartAlbums[(indexPath as NSIndexPath).row] as? PHFetchResult
        
        return cell
    }
    
    // MARK: - AssetContentControllerDelegate
    
    @IBAction func cancel(_ sender: AnyObject) {
        delegate?.didAssetPickerCanceled()
    }
    
    @IBAction func selectItems(_ sender: AnyObject) {
        delegate?.didAssetPickerSelected(selectedAssets)
    }
    
    // MARK: - AssetContentControllerDelegate
    
    @objc func deselectAll() {
        selectedAssets.removeAllObjects()
        counter.text = "Nothing selected"
        deselectAllButton.setTitleColor(UIColor.lightGray, for: UIControlState())
        navigationItem.rightBarButtonItem?.isEnabled = selectedAssets.count > 0
    }
    
    func contentSaved() {
        delegate?.didAssetPickerSelected(selectedAssets)
    }

    func contentChanged() {
        if selectedAssets.count > 0 {
            var imageCount = 0
            var videoCount = 0
            for asset in selectedAssets {
                if let assetWithContent = asset as? AssetWithContent {
                    if let phAsset = assetWithContent.phAsset {
                        if phAsset.mediaType == .image {
                            imageCount += 1
                        } else if phAsset.mediaType == .video {
                            videoCount += 1
                        }
                    }
                }
            }
            var text = "Selected "
            if imageCount == 1 {
                text += "1 Photo"
            } else if imageCount > 1 {
                text += "\(imageCount) Photos"
            }
            if videoCount > 0 {
                text += ", "
            }
            if videoCount == 1 {
                text += "1 Video"
            } else if videoCount > 1 {
                text += "\(videoCount) Videos"
            }
            counter.text = text
            deselectAllButton.setTitleColor(UIColor.black, for: UIControlState())
        } else {
            counter.text = "Nothing selected"
            deselectAllButton.setTitleColor(UIColor.lightGray, for: UIControlState())
        }
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "CollectionContent" {
            if let controller = segue.destination as? AssetCollectionContentController {
                if let cell = sender as? UITableViewCell {
                    if let indexPath = self.tableView.indexPath(for: cell) {
                        controller.collectionTitle = albumTitles[(indexPath as NSIndexPath).row]
                        controller.fetchResult = smartAlbums[(indexPath as NSIndexPath).row] as? PHFetchResult
                        controller.delegate = self
                        controller.counter = self.counter
                        controller.selectedAssets = self.selectedAssets
//                        if (indexPath as NSIndexPath).row == 1 {
//                            controller.isPhotoStream = true
//                        }
                    }
                }
            }
        }
    }

}

// MARK: PHPhotoLibraryChangeObserver
extension AddAssetController:PHPhotoLibraryChangeObserver {
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async {
            for i in 0..<self.smartAlbums.count {
                let row = self.smartAlbums[i]
                if let changeDetailes = changeInstance.changeDetails(for:(row as! PHFetchResult)) {
                    self.smartAlbums[i] = changeDetailes.fetchResultAfterChanges
                }
            }
        }
    }
}
