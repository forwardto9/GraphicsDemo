//
//  CameraViewController.swift
//  GraphicsDemo
//
//  Created by uwei on 18/04/2017.
//  Copyright © 2017 Tencent. All rights reserved.
//

import UIKit
import AVFoundation
import Photos


extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }
}

extension UIInterfaceOrientation {
    var videoOrientation: AVCaptureVideoOrientation? {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return nil
        }
    }
}

private enum LivePhotoMode {
    case on
    case off
}


class CameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet private weak var cameraPreview:CameraPerview!
    
    fileprivate var metadataOutput = AVCaptureMetadataOutput()
    fileprivate var photoOutput = AVCapturePhotoOutput()
    fileprivate var movieFileOutput:AVCaptureMovieFileOutput?
    fileprivate var videoDataOutput:AVCaptureVideoDataOutput?
    
    fileprivate var cameraInput:AVCaptureDeviceInput!
    
    fileprivate var assetWriter:AVAssetWriter!
    fileprivate var videoWriterInput:AVAssetWriterInput?
    
    fileprivate var currentDevice:AVCaptureDevice?
    
    fileprivate var videoDeviceDiscoverySession:AVCaptureDeviceDiscoverySession!
    fileprivate var cameraSession:AVCaptureSession = AVCaptureSession()
    
    
    fileprivate var captureQueue:DispatchQueue = DispatchQueue(label: "session queue", attributes: [], target: nil)
    fileprivate var audioCaptureQueue:DispatchQueue = DispatchQueue(label: "audio session queue", attributes: [], target: nil)
    
    
    private var isSessionRunning = false
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
    private var livePhotoMode: LivePhotoMode = .off
    private var inProgressLivePhotoCapturesCount = 0
    
    private var inProgressPhotoCaptureDelegates = [Int64 : PhotoCaptureDelegate]()
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let deviceTypes:[AVCaptureDeviceType] = [.builtInDuoCamera, .builtInTelephotoCamera, .builtInWideAngleCamera]
        self.videoDeviceDiscoverySession = AVCaptureDeviceDiscoverySession(deviceTypes: deviceTypes, mediaType: AVMediaTypeVideo, position: AVCaptureDevicePosition.unspecified)
        cameraPreview.session = cameraSession
        cameraPreview.videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        
        /*
         Check video authorization status. Video access is required and audio
         access is optional. If audio access is denied, audio is not recorded
         during movie recording.
         */
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. We suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            captureQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { [unowned self] granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.captureQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        captureQueue.async { [unowned self] in
            self.configureSession()
        }
        // Do any additional setup after loading the view.
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        captureQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.cameraSession.startRunning()
                self.isSessionRunning = self.cameraSession.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("AVCam doesn't have permission to use the camera, please change privacy settings", comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .`default`, handler: { action in
                        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async { [unowned self] in
                    let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        captureQueue.async { [unowned self] in
            if self.setupResult == .success {
                self.cameraSession.stopRunning()
                self.isSessionRunning = self.cameraSession.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destinationViewController.
     // Pass the selected object to the new view controller.
     }
     */
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        cameraSession.beginConfiguration()
        
        /*
         We do not create an AVCaptureMovieFileOutput when setting up the session because the
         AVCaptureMovieFileOutput does not support movie recording with AVCaptureSessionPresetPhoto.
         */
        cameraSession.sessionPreset = AVCaptureSessionPresetPhoto
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera if available, otherwise default to a wide angle camera.
            if let dualCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInDuoCamera, mediaType: AVMediaTypeVideo, position: .back) {
                defaultVideoDevice = dualCameraDevice
            }
            else if let backCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back) {
                // If the back dual camera is not available, default to the back wide angle camera.
                defaultVideoDevice = backCameraDevice
            }
            else if let frontCameraDevice = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .front) {
                // In some cases where users break their phones, the back wide angle camera is not available. In this case, we should default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            
            self.currentDevice = defaultVideoDevice
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: defaultVideoDevice)
            
            if cameraSession.canAddInput(videoDeviceInput) {
                cameraSession.addInput(videoDeviceInput)
                self.cameraInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    /*
                     Why are we dispatching this to the main queue?
                     Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
                     can only be manipulated on the main thread.
                     Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                     on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                     
                     Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
                     handled by CameraViewController.viewWillTransition(to:with:).
                     */
                    let statusBarOrientation = UIApplication.shared.statusBarOrientation
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if statusBarOrientation != .unknown {
                        if let videoOrientation = statusBarOrientation.videoOrientation {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    
                    self.cameraPreview.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation
                }
            }
            else {
                print("Could not add video device input to the session")
                setupResult = .configurationFailed
                cameraSession.commitConfiguration()
                return
            }
        }
        catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            cameraSession.commitConfiguration()
            return
        }
        
        // Add audio input.
        do {
            let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            
            if cameraSession.canAddInput(audioDeviceInput) {
                cameraSession.addInput(audioDeviceInput)
            }
            else {
                print("Could not add audio device input to the session")
            }
        }
        catch {
            print("Could not create audio device input: \(error)")
        }
        
        // Add output.
        #if false
            if cameraSession.canAddOutput(metadataOutput) {
                cameraSession.addOutput(metadataOutput)
                metadataOutput.metadataObjectTypes = [AVMetadataObjectTypeQRCode]
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                
                let windowSize = UIScreen.main.bounds.size
                let scanSize = CGSize(width:windowSize.width*3/4, height:windowSize.width*3/4)
                var scanRect = CGRect(x:(windowSize.width-scanSize.width)/2,
                                      y:(windowSize.height-scanSize.height)/2,
                                      width:scanSize.width, height:scanSize.height)
                //计算rectOfInterest 注意x,y交换位置
                scanRect = CGRect(x:scanRect.origin.y/windowSize.height,
                                  y:scanRect.origin.x/windowSize.width,
                                  width:scanRect.size.height/windowSize.height,
                                  height:scanRect.size.width/windowSize.width);
                //设置可探测区域
                metadataOutput.rectOfInterest = scanRect
                
                DispatchQueue.main.async {
                    let scanView = UIView()
                    self.view.addSubview(scanView)
                    scanView.frame = CGRect(x: 0, y: 0, width: scanSize.width, height: scanSize.height)
                    scanView.center = CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
                    scanView.layer.borderWidth = 1
                    scanView.layer.borderColor = UIColor.green.cgColor
                    self.view.bringSubview(toFront: scanView)
                }
                
            }
        #endif
        if cameraSession.canAddOutput(photoOutput) {
            cameraSession.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled      = photoOutput.isLivePhotoCaptureSupported
            self.livePhotoMode = photoOutput.isLivePhotoCaptureSupported ? .on : .off
        }
        else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            cameraSession.commitConfiguration()
            return
        }
        
        cameraSession.commitConfiguration()
    }
    
    private var sessionRunningObserveContext = 0
    private func addObservers() {
        cameraSession.addObserver(self, forKeyPath: "running", options: .new, context: &sessionRunningObserveContext)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: Notification.Name("AVCaptureSessionRuntimeErrorNotification"), object: cameraSession)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: cameraSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: Notification.Name("AVCaptureSessionInterruptionEndedNotification"), object: cameraSession)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        cameraSession.removeObserver(self, forKeyPath: "running", context: &sessionRunningObserveContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &sessionRunningObserveContext {
            let newValue = change?[.newKey] as AnyObject?
            guard let isSessionRunning = newValue?.boolValue else { return }
            
            DispatchQueue.main.async { [unowned self] in
                // Only enable the ability to change camera if the device has more than one camera.
            }
        }
        else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            captureQueue.async { [unowned self] in
                if self.isSessionRunning {
                    self.cameraSession.startRunning()
                    self.isSessionRunning = self.cameraSession.isRunning
                }
                else {
                    DispatchQueue.main.async { [unowned self] in
                    }
                }
            }
        }
        else {
            
        }
    }
    
    func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios we want to enable the user to resume the session running.
         For example, if music playback is initiated via control center while
         using AVCam, then the user can let AVCam resume
         the session running, which will stop music playback. Note that stopping
         music playback in control center will not automatically resume the session
         running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reasonIntegerValue = userInfoValue.integerValue, let reason = AVCaptureSessionInterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            var showResumeButton = false
            
            if reason == AVCaptureSessionInterruptionReason.audioDeviceInUseByAnotherClient || reason == AVCaptureSessionInterruptionReason.videoDeviceInUseByAnotherClient {
                showResumeButton = true
            }
            else if reason == AVCaptureSessionInterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                UIView.animate(withDuration: 0.25) { [unowned self] in
                }
            }
            
            if showResumeButton {
                // Simply fade-in a button to enable the user to try to resume the session running.
                UIView.animate(withDuration: 0.25) { [unowned self] in
                }
            }
        }
    }
    
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
    }
    
    // MARK : AVMetadataObjectDelegate
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [Any]!, from connection: AVCaptureConnection!) {
        var stringValue:String?
        if metadataObjects.count > 0 {
            let metadataObject = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
            stringValue = metadataObject.stringValue
            
            if stringValue != nil{
                self.cameraSession.stopRunning()
            }
        }
        self.cameraSession.stopRunning()
        //输出结果
        let alertController = UIAlertController(title: "二维码",
                                                message: stringValue,preferredStyle: .alert)
        let okAction = UIAlertAction(title: "继续", style: .default, handler: {
            action in
            //继续扫描
            self.cameraSession.startRunning()
        })
        
        let cancelAction = UIAlertAction(title: "取消", style: .destructive) { (action) in
            self.dismiss(animated: false, completion: nil)
        }
        
        alertController.addAction(okAction)
        alertController.addAction(cancelAction)
        self.present(alertController, animated: true, completion: nil)
    }
    
    @IBAction func changeCamera(_ sender: Any) {
        let alertViewController = UIAlertController(title: "Choose a camera", message: "", preferredStyle: .actionSheet)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (action) in
            alertViewController.dismiss(animated: true, completion: nil)
        }
        
        alertViewController.addAction(cancelAction)
        
        for device in self.videoDeviceDiscoverySession.devices {
            let action = UIAlertAction(title: device.localizedName, style: .default, handler: { (action) in
                self.changeDevice(device: device)
            })
            alertViewController.addAction(action)
        }
        
        self.present(alertViewController, animated: true, completion: nil)
    }
    
    
    private func changeDevice(device:AVCaptureDevice) {
        if device == self.currentDevice! {
            return
        }
        
        self.captureQueue.async {
            let newInput = try! AVCaptureDeviceInput(device: device)
            self.cameraSession.beginConfiguration()
            
            self.cameraSession.removeInput(self.cameraInput!)
            
            if self.cameraSession.canAddInput(newInput) {
                self.cameraSession.addInput(newInput)
                self.cameraInput = newInput
                self.currentDevice = device
            } else {
                self.cameraSession.addInput(self.cameraInput)
            }
            
            
            self.cameraSession.commitConfiguration()
        }
        
    }
    @IBAction func takePicture(_ sender: Any) {
        /*
         Retrieve the video preview layer's video orientation on the main queue before
         entering the session queue. We do this to ensure UI elements are accessed on
         the main thread and session configuration is done on the session queue.
         */
        let videoPreviewLayerOrientation = cameraPreview.videoPreviewLayer.connection.videoOrientation
        
        captureQueue.async {
            // Update the photo output's connection to match the video orientation of the video preview layer.
            if let photoOutputConnection = self.photoOutput.connection(withMediaType: AVMediaTypeVideo) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation
            }
            
            // Capture a JPEG photo with flash set to auto and high resolution photo enabled.
            let photoSettings = AVCapturePhotoSettings()
            photoSettings.flashMode = .auto
            photoSettings.isHighResolutionPhotoEnabled = true
            if photoSettings.availablePreviewPhotoPixelFormatTypes.count > 0 {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String : photoSettings.availablePreviewPhotoPixelFormatTypes.first!]
            }
            
            if self.livePhotoMode == .on && self.photoOutput.isLivePhotoCaptureSupported { // Live Photo capture is not supported in movie mode.
                let livePhotoMovieFileName = NSUUID().uuidString
                let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
                photoSettings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
            }
            
            // Use a separate object for the photo capture delegate to isolate each capture life cycle.
            let photoCaptureDelegate = PhotoCaptureDelegate(with: photoSettings, willCapturePhotoAnimation: {
                DispatchQueue.main.async { [unowned self] in
                    self.cameraPreview.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) { [unowned self] in
                        self.cameraPreview.videoPreviewLayer.opacity = 1
                    }
                }
            }, capturingLivePhoto: { capturing in
                /*
                 Because Live Photo captures can overlap, we need to keep track of the
                 number of in progress Live Photo captures to ensure that the
                 Live Photo label stays visible during these captures.
                 */
                self.captureQueue.async { [unowned self] in
                    if capturing {
                        self.inProgressLivePhotoCapturesCount += 1
                    }
                    else {
                        self.inProgressLivePhotoCapturesCount -= 1
                    }
                    
                    let inProgressLivePhotoCapturesCount = self.inProgressLivePhotoCapturesCount
                    DispatchQueue.main.async { [unowned self] in
                        if inProgressLivePhotoCapturesCount > 0 {
                            //
                        }
                        else if inProgressLivePhotoCapturesCount == 0 {
                            //
                        }
                        else {
                            print("Error: In progress live photo capture count is less than 0");
                        }
                    }
                }
            }, completed: { [unowned self] photoCaptureDelegate in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.captureQueue.async { [unowned self] in
                    self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = nil
                }
                }
            )
            
            /*
             The Photo Output keeps a weak reference to the photo capture delegate so
             we store it in an array to maintain a strong reference to this object
             until the capture is completed.
             */
            self.inProgressPhotoCaptureDelegates[photoCaptureDelegate.requestedPhotoSettings.uniqueID] = photoCaptureDelegate
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureDelegate)
        }
    }
    
    
    func recordMoive() -> Void {
        self.movieFileOutput = AVCaptureMovieFileOutput()
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        /*
         Disable the Camera button until recording finishes, and disable
         the Record button until recording starts or finishes.
         
         See the AVCaptureFileOutputRecordingDelegate methods.
         
         Retrieve the video preview layer's video orientation on the main queue
         before entering the session queue. We do this to ensure UI elements are
         accessed on the main thread and session configuration is done on the session queue.
         */
        let videoPreviewLayerOrientation = cameraPreview.videoPreviewLayer.connection.videoOrientation
        
        captureQueue.async { [unowned self] in
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    /*
                     Setup background task.
                     This is needed because the `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)`
                     callback is not received until AVCam returns to the foreground unless you request background execution time.
                     This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                     To conclude this background execution, endBackgroundTask(_:) is called in
                     `capture(_:, didFinishRecordingToOutputFileAt:, fromConnections:, error:)` after the recorded file has been saved.
                     */
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before starting recording.
                let movieFileOutputConnection = self.movieFileOutput?.connection(withMediaType: AVMediaTypeVideo)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation
                
                // Start recording to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(toOutputFileURL: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            }
            else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    // MARK:AVCaptureFileOutputRecordingDelegate
    func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
        // Enable the Record button to let the user stop the recording.
        DispatchQueue.main.async { [unowned self] in
            //
        }
    }
    
    func capture(_ captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAt outputFileURL: URL!, fromConnections connections: [Any]!, error: Error!) {
        /*
         Note that currentBackgroundRecordingID is used to end the background task
         associated with this recording. This allows a new recording to be started,
         associated with a new UIBackgroundTaskIdentifier, once the movie file output's
         `isRecording` property is back to false — which happens sometime after this method
         returns.
         
         Note: Since we use a unique file path for each recording, a new recording will
         not overwrite a recording currently being saved.
         */
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                }
                catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskInvalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskInvalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            print("Movie file finishing error: \(error)")
            success = (((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success {
            // Check authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    }, completionHandler: { success, error in
                        if !success {
                            print("Could not save movie to photo library: \(String(describing: error?.localizedDescription))")
                        }
                        cleanup()
                    }
                    )
                }
                else {
                    cleanup()
                }
            }
        }
        else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async { [unowned self] in
            // Only enable the ability to change camera if the device has more than one camera.
        }
    }

    
    let videoSetting: [String : Any] = [
        AVVideoCodecKey: AVVideoCodecH264,
        AVVideoWidthKey: 320,
        AVVideoHeightKey: 240,
        AVVideoCompressionPropertiesKey: [
            AVVideoPixelAspectRatioKey: [
                AVVideoPixelAspectRatioHorizontalSpacingKey: 1,
                AVVideoPixelAspectRatioVerticalSpacingKey: 1
            ],
            AVVideoMaxKeyFrameIntervalKey: 1,
            AVVideoAverageBitRateKey: 1280000
        ]
    ]
    
    let audioSetting: [String: Any] = [
        AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC),
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: 22050
    ]
    
    
    func processVideo() -> Void {
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput?.setSampleBufferDelegate(self, queue: self.captureQueue)
        videoDataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable:videoDataOutput!.availableVideoCVPixelFormatTypes.first!, AVVideoCodecKey:videoDataOutput!.availableVideoCodecTypes.first!]
        videoDataOutput?.alwaysDiscardsLateVideoFrames = false // 保证不漏帧
        
        cameraSession.beginConfiguration()
        
        if cameraSession.canAddOutput(videoDataOutput!) {
            cameraSession.addOutput(videoDataOutput!)
        }
        
        cameraSession.commitConfiguration()
        
    }
    
    //MARK:AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        // new frame
        objc_sync_enter(self)
        if let assetWriter = assetWriter {
            if assetWriter.status != .writing && assetWriter.status != .unknown {
                return
            }
        }
        
        if let assetWriter = assetWriter, assetWriter.status == .unknown {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        
        captureQueue.async { 
            if let videoWriterInput = self.videoWriterInput, self.videoWriterInput!.isReadyForMoreMediaData {
                videoWriterInput.append(sampleBuffer)
            }
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didDrop sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        // discard
    }
    
    fileprivate var tmpFileURL:URL
    func startVideoRecording() {
        tmpFileURL = NSURL.fileURL(withPath: "\(NSTemporaryDirectory())tmp\(arc4random()).mp4")
        do {
            assetWriter = try AVAssetWriter(outputURL: tmpFileURL, fileType: AVFileTypeMPEG4)
            videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSetting)
            videoWriterInput?.expectsMediaDataInRealTime = true
            videoWriterInput?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
            if assetWriter!.canAdd(videoWriterInput!) {
                assetWriter!.add(videoWriterInput!)
            }
//            audioWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSetting)
//            audioWriterInput?.expectsMediaDataInRealTime = true
//            if assetWriter!.canAddInput(audioWriterInput!) {
//                assetWriter!.addInput(audioWriterInput!)
//            }
        }
        catch _ {
            
        }
    }
    
    func endRecording() {
        if let assetWriter = assetWriter {
            if let videoWriterInput = videoWriterInput {
                videoWriterInput.markAsFinished()
            }
//            if let audioWriterInput = audioWriterInput {
//                audioWriterInput.markAsFinished()
//            }
            assetWriter.finishWriting(completionHandler: { () -> Void in
            })
        }
    }
}
