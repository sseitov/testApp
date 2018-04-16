//
//  AssetCollectionContentController.swift
//  cryptoBox (MilCryptor Secure Platform)
//
//  Created by Denys Borysiuk on 19.07.16.
//  Copyright © 2016 ArchiSec Solutions, Ltd. All rights reserved.//
//

import UIKit
import Photos

protocol AssetContentControllerDelegate {
    func contentChanged()
    func contentSaved()
}

class AssetCollectionContentController: UICollectionViewController {

    var collectionTitle:String?
    
    var delegate:AssetContentControllerDelegate?
    var counter:UILabel?
    var fetchResult:PHFetchResult<PHObject>?
    var selectedAssets:NSMutableArray?
    
    fileprivate let imageManager = PHCachingImageManager()
    fileprivate var thumbnailSize: CGSize!
    fileprivate var previousCashedAssets:[PHAsset] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = collectionTitle
        imageManager.allowsCachingHighQualityImages = false
        resetCachedAssets()
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    deinit {
        imageManager.stopCachingImagesForAllAssets()
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationItem.rightBarButtonItem?.isEnabled = selectedAssets!.count > 0
        
        // Determine the size of the thumbnails to request from the PHCachingImageManager
        let scale = UIScreen.main.scale
        let cellSize = (collectionViewLayout as! UICollectionViewFlowLayout).itemSize
        thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let space = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let content = UIBarButtonItem(customView: counter!)
        navigationController?.toolbar.setItems([space, content], animated: false)
        
        updateCachedAssets()
    }
    
    @IBAction func save(_ sender: AnyObject) {
        delegate?.contentSaved()
    }

    // MARK: UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }


    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return fetchResult!.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PHCell", for: indexPath) as! PHAssetCell
        if let phAsset = fetchResult!.object(at: (indexPath as NSIndexPath).row) as? PHAsset {
            cell.phAsset = phAsset
            let assets = selectedAssets!.filter({($0 as! AssetWithContent).phAsset == phAsset})
            cell.assetCheck.isHidden = assets.count == 0
        }
        return cell
    }

    // MARK: UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: IndexPath) -> CGSize {
        let w = (self.view.frame.size.width - 40.0) / 3.0
        return CGSize(width: w, height: w)
    }

    fileprivate func updateSelected() {
        navigationItem.rightBarButtonItem?.isEnabled = selectedAssets!.count > 0
        delegate?.contentChanged()
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath) as! PHAssetCell
        if let phAsset = cell.phAsset {
            if cell.assetCheck.isHidden {
/*
                if isPhotoStream {
                    phAsset.requestContentEditingInput(with: nil, completionHandler: { content, _ in
                        if content != nil {
                            let name = (content!.fullSizeImageURL?.lastPathComponent)!
                            if let rawData = try? Data(contentsOf: content!.fullSizeImageURL!) {
                                self.selectedAssets!.add(AssetWithContent(phAsset: cell.phAsset, thumb: cell.assetThumb.image, content: rawData, name: name))
                            } else {
                                self.selectedAssets!.add(AssetWithContent(phAsset: cell.phAsset, thumb: cell.assetThumb.image))
                            }
                        } else {
                            self.selectedAssets!.add(AssetWithContent(phAsset: cell.phAsset, thumb: cell.assetThumb.image))
                        }
                        DispatchQueue.main.async {
                            cell.assetCheck.isHidden = false
                            self.updateSelected()
                        }
                    })
                } else {
                }
 */
                selectedAssets!.add(AssetWithContent(phAsset: cell.phAsset, thumb: cell.assetThumb.image))
                cell.assetCheck.isHidden = false
                updateSelected()
            } else {
                let assets = selectedAssets!.filter({($0 as! AssetWithContent).phAsset == phAsset})
                if assets.count > 0 {
                    selectedAssets!.remove(assets[0])
                }
                cell.assetCheck.isHidden = true
                updateSelected()
            }
        }
    }
    
    // MARK: UIScrollView
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCachedAssets()
    }
    
    // MARK: Asset Caching
    
    fileprivate func resetCachedAssets() {
        imageManager.stopCachingImagesForAllAssets()
        previousCashedAssets = []
    }
    
    fileprivate func updateCachedAssets() {
        // Update only if the view is visible.
        if view.window == nil {
            return
        }
        
        var newAssets:[PHAsset] = []
        for cell in collectionView!.visibleCells {
            newAssets.append((cell as! PHAssetCell).phAsset!)
        }
        
        let old = NSSet(array: previousCashedAssets)
        let addedAssets = NSMutableSet(array: newAssets)
        let removedAssets = NSMutableSet(array: newAssets)
        removedAssets.intersect(old as! Set<PHAsset>)
        addedAssets.minus(old as! Set<PHAsset>)
        
        // Update the assets the PHCachingImageManager is caching.
        imageManager.startCachingImages(for: addedAssets.allObjects as! [PHAsset], targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
        imageManager.stopCachingImages(for: removedAssets.allObjects as! [PHAsset], targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
        
        // Store the preheat rect to compare against in the future.
        previousCashedAssets = newAssets
    }

}


// MARK: PHPhotoLibraryChangeObserver
extension AssetCollectionContentController:PHPhotoLibraryChangeObserver {
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        if let changes = changeInstance.changeDetails(for: fetchResult!) {
            DispatchQueue.main.async {
                self.fetchResult = changes.fetchResultAfterChanges
                self.collectionView!.reloadData()
                self.resetCachedAssets()
            }
        }
    }
}

