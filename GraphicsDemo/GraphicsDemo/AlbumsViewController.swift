//
//  FirstViewController.swift
//  GraphicsDemo
//
//  Created by uwei on 12/04/2017.
//  Copyright © 2017 Tencent. All rights reserved.
//

import UIKit
import CoreImage


extension CGRect {
    func toString() -> String {
        let str = "(x:\(String(format:"%.3f",self.origin.x)), y:\(String(format:"%.3f",self.origin.y)), w:\(String(format:"%.3f",self.size.width)). h:\(String(format:"%.3f",self.size.height)))"
        return str
    }
}

extension CGPoint {
    func toString() -> String {
        return "Point(x:\(String(format:"%.3f",self.x)), y:\(String(format:"%.3f",self.y)))"
    }
}


class AlbumsViewController: UIViewController,UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet weak var chooseButton: UIButton!

    @IBOutlet weak var photoImageView: UIImageView!
    
    @IBOutlet weak var resultTableView: UITableView!
    fileprivate var featureLabels = [String]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.resultTableView.delegate = self
        self.resultTableView.dataSource = self
        
        self.resultTableView.register(UITableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        
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
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        self.featureLabels.removeAll()
        picker.dismiss(animated: true, completion: nil)
        let image = info[UIImagePickerControllerOriginalImage];
        self.photoImageView.image = image as? UIImage
        
        let context = CIContext()
        let faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: context, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh, CIDetectorNumberOfAngles:11])
        let detectImage = CIImage(cgImage: self.photoImageView.image!.cgImage!)
        let faceFeatures = faceDetector?.features(in: detectImage, options: [CIDetectorImageOrientation : 5])
        if faceFeatures != nil {
            for faceFeature in faceFeatures! {
                self.featureLabels.append("type:" + faceFeature.type)
                self.featureLabels.append("bounds:" + faceFeature.bounds.toString())
                if (faceFeature as! CIFaceFeature).hasMouthPosition {
                    self.featureLabels.append("mouth:" + (faceFeature as! CIFaceFeature).mouthPosition.toString())
                }
                if (faceFeature as! CIFaceFeature).hasLeftEyePosition {
                    self.featureLabels.append("letEye:" + (faceFeature as! CIFaceFeature).leftEyePosition.toString())
                }
                if (faceFeature as! CIFaceFeature).hasRightEyePosition {
                    self.featureLabels.append("rightEye:" + (faceFeature as! CIFaceFeature).rightEyePosition.toString())
                }
            }
        }
        
        let typeCodeDetector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyLow, CIDetectorNumberOfAngles:5])
        let QRCodeFeatures = typeCodeDetector?.features(in: detectImage, options: [CIDetectorImageOrientation : index])
        
        if QRCodeFeatures != nil {
            for qrcodeFeature in QRCodeFeatures! {
                self.featureLabels.append("type:" + qrcodeFeature.type)
                self.featureLabels.append("bounds:" + qrcodeFeature.bounds.toString())
                self.featureLabels.append("message:" + ((qrcodeFeature as! CIQRCodeFeature).messageString ?? "null"))
            }
        }
        
        
        let textDetector = CIDetector(ofType: CIDetectorTypeText, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])
        let textFeatures = textDetector?.features(in: detectImage, options: [CIDetectorReturnSubFeatures:1])
        if textFeatures != nil {
            for textFeature in textFeatures! {
                self.featureLabels.append("type:" + textFeature.type)
                self.featureLabels.append("bounds:" + textFeature.bounds.toString())
                if (textFeature as! CITextFeature).subFeatures != nil {
                    for subFeature in (textFeature as! CITextFeature).subFeatures! {
                        self.featureLabels.append("type:" + (subFeature as! CITextFeature).type)
                        self.featureLabels.append("bounds:" + (subFeature as! CITextFeature).bounds.toString())
                    }
                
                }
            }
        }
        
        let rectDetector = CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])
        let rectFeatures = rectDetector?.features(in: detectImage, options: [CIDetectorAspectRatio:1.75, CIDetectorFocalLength:0, CIDetectorAccuracy:CIDetectorAccuracyLow])
        
        if rectFeatures != nil {
            for rectFeature in rectFeatures! {
                self.featureLabels.append("type:" + rectFeature.type)
                self.featureLabels.append("bounds:" + rectFeature.bounds.toString())
            }
        }
        
        
        self.resultTableView.reloadData()
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.featureLabels.count
    }
    

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = self.featureLabels[indexPath.row]
        cell.textLabel?.font = UIFont.systemFont(ofSize: 10, weight: UIFontWeightThin)
        
        return cell
    }
    
    
}

