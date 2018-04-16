//
//  AssetCollectionCell.swift
//  cryptoBox (MilCryptor Secure Platform)
//
//  Created by Denys Borysiuk on 19.07.16.
//  Copyright © 2016 ArchiSec Solutions, Ltd. All rights reserved.//
//

import UIKit
import Photos
import AVFoundation

class AssetCollectionCell: UITableViewCell {

    @IBOutlet weak var collectionImage: UIImageView!
    @IBOutlet weak var collectionTitle: UILabel!
    @IBOutlet weak var collectionCounter: UILabel!
 
    weak var fetchResult:PHFetchResult<AnyObject>? {
        didSet {
            collectionCounter.text = "\(fetchResult!.count)"
            collectionImage.image = UIImage()
 
            if let phAsset = fetchResult!.firstObject as? PHAsset {
                let scale = UIScreen.main.scale
                let cellSize = self.bounds.size
                let thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
                PHImageManager.default().requestImage(for:phAsset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: { image, _ in
                    DispatchQueue.main.async {
                        self.collectionImage.image = image
                    }
                })
            } else {
                collectionImage.image = UIImage(named: "empty")
            }
        }
    }

}
