//
//  AppDelegate.swift
//  testApp
//
//  Created by Сергей Сейтов on 11.04.2018.
//  Copyright © 2018 V-Channel. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    let webServer = GCDWebServer()


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        try? FileManager.default.createDirectory(at: mediaDirectory(), withIntermediateDirectories: false, attributes: nil)
        
        webServer.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self, processBlock: { request in
            print("======== request \(request.path)")
            let fullPath = "\(mediaDirectory().relativePath)\(request.path)"
            print("======== fullPath \(fullPath)")
            if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) {
                return GCDWebServerDataResponse(data: data, contentType: "")
            } else {
                return GCDWebServerErrorResponse(statusCode: 400)
            }
        })
        
        do {
            let options = [GCDWebServerOption_AutomaticallySuspendInBackground:false, GCDWebServerOption_Port:8080, GCDWebServerOption_BonjourName:UIDevice.current.name] as [String : Any]
            try webServer.start(options: options as [AnyHashable: Any])
        } catch {
            print(error)
        }
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

