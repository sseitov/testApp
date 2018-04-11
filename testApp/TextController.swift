//
//  TextController.swift
//  testApp
//
//  Created by Сергей Сейтов on 11.04.2018.
//  Copyright © 2018 V-Channel. All rights reserved.
//

import UIKit

class TextController: UIViewController {

    var data:Data?
    @IBOutlet weak var textView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if data != nil {
            textView.text = String(data: data!, encoding: .utf8)
        }
    }

}
