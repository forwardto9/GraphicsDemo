//
//  FirstViewController.swift
//  GraphicsDemo
//
//  Created by uwei on 12/04/2017.
//  Copyright © 2017 Tencent. All rights reserved.
//

import UIKit
import CoreImage

class AlbumsViewController: UIViewController,UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    @IBOutlet weak var chooseButton: UIButton!

    @IBOutlet weak var photoImageView: UIImageView!
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func chooseFromAlbums(_ sender: Any) {
        let imageViewController = UIImagePickerController()
        imageViewController.sourceType = UIImagePickerControllerSourceType.savedPhotosAlbum
        imageViewController.delegate = self
        self.present(imageViewController, animated: true, completion: nil)
//        let navigationViewController = UINavigationController(rootViewController: imageViewController)
//        let appDelegate = UIApplication.shared.delegate as! AppDelegate
//        appDelegate.window?.rootViewController = imageViewController
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true, completion: nil)
        let image = info[UIImagePickerControllerOriginalImage];
        self.photoImageView.image = image as? UIImage
        
        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeFace, context: context, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])
        let detectImage = CIImage(cgImage: self.photoImageView.image!.cgImage!)
        let features = detector?.features(in: detectImage, options: [CIDetectorImageOrientation : 5])
        if features != nil {
            for f in features! {
                print(f.type)
            }
        }
        
    }
}

