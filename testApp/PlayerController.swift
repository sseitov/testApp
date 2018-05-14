//
//  PlayerController.swift
//  testApp
//
//  Created by Сергей Сейтов on 14.05.2018.
//  Copyright © 2018 V-Channel. All rights reserved.
//

import UIKit

class PlayerController: UIViewController {

    var player:DLGPlayer?
    var url:URL?
    var rotation:Int = 0
    
    @IBOutlet weak var videoView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        player = DLGPlayer()
        player?.playerView.frame = self.view.frame
        
        switch (rotation) {
        case 1:
            player?.playerView.layer.transform = CATransform3DMakeRotation(CGFloat(Double.pi / 2), 0.0, 0.0, 1.0);
            break;
        case 2:
            player?.playerView.layer.transform = CATransform3DMakeRotation(CGFloat(Double.pi), 0.0, 0.0, 1.0);
            break;
        case 3:
            player?.playerView.layer.transform = CATransform3DMakeRotation(CGFloat(Double.pi / 2 + Double.pi), 0.0, 0.0, 1.0);
            break;
        default:
            break;
        }

        videoView.addSubview(player!.playerView)
        
        NotificationCenter.default.addObserver(forName: Notification.Name(DLGPlayerNotificationOpened), object: nil, queue: OperationQueue.main, using: { notify in
            self.player?.play()
        })
        NotificationCenter.default.addObserver(forName: Notification.Name(DLGPlayerNotificationBufferStateChanged), object: nil, queue: OperationQueue.main, using: { notify in
            if let info = notify.userInfo, let state = info[DLGPlayerNotificationBufferStateKey] as? Bool {
                if state {
                    SVProgressHUD.show()
                } else {
                    SVProgressHUD.dismiss()
                }
            }
        })
        player?.open(url!.absoluteString)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        player?.playerView.frame = videoView.bounds
    }
}
