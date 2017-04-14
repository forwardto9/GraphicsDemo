//
//  SecondViewController.swift
//  GraphicsDemo
//
//  Created by uwei on 12/04/2017.
//  Copyright © 2017 Tencent. All rights reserved.
//

import UIKit
import AVFoundation
class ManualCameraViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var camerasTables:UITableView!
    fileprivate var videoDeviceDiscoverySession:AVCaptureDeviceDiscoverySession!
    fileprivate var cameraSession:AVCaptureSession!
    fileprivate var cameraInput:AVCaptureDeviceInput!
    fileprivate var cameraOutput:AVCaptureMetadataOutput!
    fileprivate var cameraPreview:CameraPerview!
    fileprivate var captuerQueue:DispatchQueue!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
//        let deviceTypes:[AVCaptureDeviceType] = [.builtInDualCamera, .builtInDuoCamera, .builtInTelephotoCamera, .builtInWideAngleCamera]
        let deviceTypes:[AVCaptureDeviceType] = [.builtInDuoCamera, .builtInTelephotoCamera, .builtInWideAngleCamera]
        self.videoDeviceDiscoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaTypeVideo, position: AVCaptureDevicePosition.unspecified)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.videoDeviceDiscoverySession.devices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = self.videoDeviceDiscoverySession.devices[indexPath.row].localizedName
        
        return cell
    }
    
}

