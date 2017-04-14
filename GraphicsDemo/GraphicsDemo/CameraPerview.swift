//
//  CameraPerview.swift
//  GraphicsDemo
//
//  Created by uwei on 14/04/2017.
//  Copyright © 2017 Tencent. All rights reserved.
//

import UIKit
import AVFoundation

class CameraPerview: UIView {

    /*
    // Only override draw() if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func draw(_ rect: CGRect) {
        // Drawing code
    }
    */

    var videoPreviewLayer:AVCaptureVideoPreviewLayer {
        return (self.layer as! AVCaptureVideoPreviewLayer)
    }
    
    var session:AVCaptureSession! {
        set {
            self.session = self.videoPreviewLayer.session
        }
        
        get {
            return self.videoPreviewLayer.session
        }
    }
    
    override var classForCoder: AnyClass {
        return AVCaptureVideoPreviewLayer.classForCoder()
    }
    
    
}
