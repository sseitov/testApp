//
//  WebViewController.swift
//  testApp
//
//  Created by Сергей Сейтов on 10.05.2018.
//  Copyright © 2018 V-Channel. All rights reserved.
//

import UIKit

class WebViewController: UIViewController, UIWebViewDelegate {

    @IBOutlet weak var webView: UIWebView!
    
    let pageSize = CGSize(width: 595.2, height: 841.8)
    let pageMargins = UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 5)

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.scalesPageToFit = true
        let url = URL(string: "http://www.google.com")
        webView.loadRequest(URLRequest(url: url!))
    }

    
    func webViewDidFinishLoad(_ webView: UIWebView) {
        print("loaded")
        let btn = UIBarButtonItem(title: "Save", style: .plain, target: self, action: #selector(self.save))
        navigationItem.setRightBarButton(btn, animated: true)
    }
    
    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        print("Can not load web page: \(error.localizedDescription)")
    }
    
    @objc func save() {
        
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        
        let printableRect = CGRect(x: pageMargins.left,
                                   y: pageMargins.top,
                                   width: pageSize.width - pageMargins.left - pageMargins.right,
                                   height: pageSize.height - pageMargins.top - pageMargins.bottom)
        let paperRect = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        
        renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printableRect), forKey: "printableRect")
        let pdfData = renderer.printToPDF()
        let outURL = mediaDirectory().appendingPathComponent("google.pdf")
        do {
            try pdfData.write(to: outURL)
            print(outURL.relativePath)
        } catch {
            print(error.localizedDescription)
        }
    }

}

extension UIPrintPageRenderer {
    func printToPDF() -> Data {
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, self.paperRect, nil)
        prepare(forDrawingPages: NSRange(location: 0, length: self.numberOfPages))
        
        let bounds = UIGraphicsGetPDFContextBounds()
        
        for i in 0..<numberOfPages {
            UIGraphicsBeginPDFPage()
            drawPage(at: i, in: bounds)
        }
        UIGraphicsEndPDFContext()
        
        return pdfData as Data
    }
}
