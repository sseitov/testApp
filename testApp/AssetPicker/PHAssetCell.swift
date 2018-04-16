//
//  PHAssetCell.swift
//  cryptoBox (MilCryptor Secure Platform)
//
//  Created by Denys Borysiuk on 19.07.16.
//  Copyright © 2016 ArchiSec Solutions, Ltd. All rights reserved.//
//

import UIKit
import Photos

class PHAssetCell: UICollectionViewCell {
    @IBOutlet weak var assetThumb: UIImageView!
    @IBOutlet weak var assetCheck: UIImageView!
    @IBOutlet weak var typeIcon: UIImageView!
    @IBOutlet weak var timeLabel: UILabel!
    
    weak var phAsset:PHAsset? {
        didSet {
            if (phAsset!.mediaType == .video) {
                if phAsset!.mediaSubtypes == .videoHighFrameRate {
                    typeIcon.image = UIImage(named: "icon_slo-mo")
                } else {
                    typeIcon.image = UIImage(named: "icon_film")
                }
            } else if (phAsset!.mediaType == .image) {
                if #available(iOS 9.1, *) {
                    if phAsset!.mediaSubtypes == .photoLive {
                        typeIcon.image = UIImage(named: "icon_live-photo")
                    } else {
                        typeIcon.image = UIImage(named: "icon_photo")
                    }
                } else {
                    typeIcon.image = UIImage(named: "icon_photo")
                }
            } else {
                typeIcon.image = UIImage()
            }

            self.assetThumb.image = nil
            timeLabel.text = ""
            if phAsset!.mediaType == .video {
                let options = PHVideoRequestOptions()
                options.version = .original
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestAVAsset(forVideo: phAsset!, options: options, resultHandler: { player, _, _ in
                    if player != nil {
                        DispatchQueue.main.async {
                            let time = CMTimeGetSeconds(player!.duration)
                            self.timeLabel.text = timeToString(time)
                            let imageGenerator = AVAssetImageGenerator(asset: player!)
                            imageGenerator.appliesPreferredTrackTransform = true
                            if let img = try? imageGenerator.copyCGImage(at: CMTimeMake(1, 1), actualTime: nil) {
                                self.assetThumb.image = UIImage(cgImage: img)
                            }
                        }
                    }
                })
            } else {
                let scale = UIScreen.main.scale
                let cellSize = self.bounds.size
                let thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
                PHImageManager.default().requestImage(for: phAsset!, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: { image, _ in
                    if image != nil {
                        DispatchQueue.main.async {
                            self.assetThumb.image = image
                        }
                    }
                })
            }
        }
    }
}
