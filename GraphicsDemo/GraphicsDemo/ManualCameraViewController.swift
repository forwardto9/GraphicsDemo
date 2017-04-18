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
    
    fileprivate var deviceInputArray = ["AVCaptureMetadataOutput", "AVCaptureMovieFileOutput", "AVCapturePhotoOutput", "AVCaptureStillImageOutput", "AVCaptureVideoDataOutput"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        camerasTables.register(UITableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        // Do any additional setup after loading the view, typically from a nib.
//        let deviceTypes:[AVCaptureDeviceType] = [.builtInDualCamera, .builtInDuoCamera, .builtInTelephotoCamera, .builtInWideAngleCamera]
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.deviceInputArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = deviceInputArray[indexPath.row]        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cameraViewController = self.storyboard?.instantiateViewController(withIdentifier: "CameraViewController") as! CameraViewController
        self.present(cameraViewController, animated: false, completion: nil)
    }
    
}

