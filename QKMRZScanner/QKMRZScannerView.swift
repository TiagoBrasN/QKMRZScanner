//
//  QKMRZScannerView.swift
//  QKMRZScanner
//
//  Created by Matej Dorcak on 03/10/2018.
//

import UIKit
import AVFoundation
import SwiftyTesseract
import QKMRZParser
import AudioToolbox
import Vision
import Accelerate
import CoreGraphics

// MARK: - QKMRZScannerViewDelegate
public protocol QKMRZScannerViewDelegate: AnyObject {
    func mrzScannerView(_ mrzScannerView: QKMRZScannerView, didFind scanResult: QKMRZScanResult)
}

// MARK: - QKMRZScannerView
@IBDesignable
public class QKMRZScannerView: UIView {
    fileprivate let tesseract: Tesseract
    fileprivate let mrzParser = QKMRZParser(ocrCorrection: true)
    fileprivate let captureSession = AVCaptureSession()
    fileprivate let videoOutput = AVCaptureVideoDataOutput()
    fileprivate let videoPreviewLayer = AVCaptureVideoPreviewLayer()
    fileprivate let notificationFeedback = UINotificationFeedbackGenerator()
    fileprivate let cutoutView = QKCutoutView()
    fileprivate var isScanningPaused = false
    fileprivate var observer: NSKeyValueObservation?
    fileprivate var lockOrientation: Bool = false

    fileprivate var interfaceOrientation: UIInterfaceOrientation = .landscapeLeft

    // MARK: Public properties
    @objc public dynamic var isScanning = false
    public var vibrateOnResult = true
    public weak var delegate: QKMRZScannerViewDelegate?

    public var cutoutRect: CGRect {
        return cutoutView.cutoutRect
    }
    
    public init(
        dataSource: LanguageModelDataSource,
        orientation: UIInterfaceOrientation = .landscapeLeft,
        lockOrientation: Bool = false
    ) {
        self.tesseract = Tesseract(
            language: .custom("ocrb"),
            dataSource: dataSource,
            engineMode: .tesseractOnly)
        self.interfaceOrientation = orientation
        self.lockOrientation = lockOrientation
        self.cutoutView.alwaysDrawOverlayInLandscapeMode = lockOrientation
        super.init(frame: UIScreen.main.bounds)
        initialize()
    }

    // MARK: Initializers
    override public init(frame: CGRect) {
        self.tesseract = Tesseract(
            language: .custom("ocrb"),
            dataSource: Bundle.current.pathToTrainedData as! LanguageModelDataSource,
            engineMode: .tesseractOnly)
        super.init(frame: frame)
        initialize()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        self.tesseract = Tesseract(
            language: .custom("ocrb"),
            dataSource: Bundle.current.pathToTrainedData as! LanguageModelDataSource,
            engineMode: .tesseractOnly)
        super.init(coder: aDecoder)
        initialize()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Overriden methods
    override public func prepareForInterfaceBuilder() {
        setViewStyle()
        addCutoutView()
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        adjustVideoPreviewLayerFrame()
    }
    
    // MARK: Scanning
    public func startScanning() {
        guard !captureSession.inputs.isEmpty else {
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            self?.notificationFeedback.prepare()
            DispatchQueue.main.async { [weak self] in self?.adjustVideoPreviewLayerFrame() }
        }
    }
    
    public func stopScanning() {
        captureSession.stopRunning()
    }
    
    // MARK: MRZ
    fileprivate func mrz(from cgImage: CGImage) -> QKMRZResult? {
        let mrzTextImage = UIImage(cgImage: preprocessImage(cgImage))
        let recognizedString = try? tesseract.performOCR(on: mrzTextImage).get()
        
        if let string = recognizedString, let mrzLines = mrzLines(from: string) {
            return mrzParser.parse(mrzLines: mrzLines)
        }
        
        return nil
    }
    
    fileprivate func mrzLines(from recognizedText: String) -> [String]? {
        let mrzString = recognizedText.replacingOccurrences(of: " ", with: "")
        var mrzLines = mrzString.components(separatedBy: "\n").filter({ !$0.isEmpty })
        
        // Remove garbage strings located at the beginning and at the end of the result
        if !mrzLines.isEmpty {
            let averageLineLength = (mrzLines.reduce(0, { $0 + $1.count }) / mrzLines.count)
            mrzLines = mrzLines.filter({ $0.count >= averageLineLength })
        }
        
        return mrzLines.isEmpty ? nil : mrzLines
    }
    
    // MARK: Document Image from Photo cropping
    fileprivate func cutoutRect(for cgImage: CGImage) -> CGRect {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let rect = videoPreviewLayer.metadataOutputRectConverted(fromLayerRect: cutoutRect)
        let videoOrientation = videoPreviewLayer.connection!.videoOrientation
        
        if videoOrientation == .portrait || videoOrientation == .portraitUpsideDown {
            let width = (rect.height * imageWidth)
            
            return CGRect(
                x: (rect.minY * imageWidth),
                y: (rect.minX * imageHeight),
                width: width * 0.4,
                height: (rect.width * imageHeight))
        }
        else {
            let height = (rect.height * imageHeight)
            let factor: CGFloat = 0.4
            
            return CGRect(
                x: (rect.minX * imageWidth),
                y: (rect.minY * imageHeight) + (height * (1 - factor)),
                width: (rect.width * imageWidth),
                height: height * factor)
        }
    }
    
    fileprivate func documentImage(from cgImage: CGImage) -> CGImage {
        let croppingRect = cutoutRect(for: cgImage)
        let image = cgImage.cropping(to: croppingRect) ?? cgImage
        
        if lockOrientation {
            return UIImage(cgImage: image).rotatedImage(with: .pi * -0.5).cgImage ?? image
        } else {
            return image
        }
    }
    
    fileprivate func enlargedDocumentImage(from cgImage: CGImage) -> UIImage {
        var croppingRect = cutoutRect(for: cgImage)
        let margin = (0.05 * croppingRect.height) // 5% of the height
        croppingRect = CGRect(x: (croppingRect.minX - margin), y: (croppingRect.minY - margin), width: croppingRect.width + (margin * 2), height: croppingRect.height + (margin * 2))
        return UIImage(cgImage: cgImage.cropping(to: croppingRect)!)
    }
    
    // MARK: UIApplication Observers
    @objc fileprivate func appWillEnterForeground() {
        if isScanningPaused {
            isScanningPaused = false
            startScanning()
        }
    }
    
    @objc fileprivate func appDidEnterBackground() {
        if isScanning {
            isScanningPaused = true
            stopScanning()
        }
    }
    
    // MARK: Init methods
    fileprivate func initialize() {
        FilterVendor.registerFilters()
        setViewStyle()
        addCutoutView()
        initCaptureSession()
        addAppObservers()
    }
    
    fileprivate func setViewStyle() {
        backgroundColor = .black
    }
    
    fileprivate func addCutoutView() {
        cutoutView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cutoutView)
        
        NSLayoutConstraint.activate([
            cutoutView.topAnchor.constraint(equalTo: topAnchor),
            cutoutView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cutoutView.leftAnchor.constraint(equalTo: leftAnchor),
            cutoutView.rightAnchor.constraint(equalTo: rightAnchor)
        ])
    }
    
    fileprivate func initCaptureSession() {
        captureSession.sessionPreset = .hd1280x720
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Camera not accessible")
            return
        }
        
        guard let deviceInput = try? AVCaptureDeviceInput(device: camera) else {
            print("Capture input could not be initialized")
            return
        }
        
        observer = captureSession.observe(\.isRunning, options: [.new]) { [unowned self] (model, change) in
            // CaptureSession is started from the global queue (background). Change the `isScanning` on the main
            // queue to avoid triggering the change handler also from the global queue as it may affect the UI.
            DispatchQueue.main.async { [weak self] in self?.isScanning = change.newValue! }
        }
        
        if captureSession.canAddInput(deviceInput) && captureSession.canAddOutput(videoOutput) {
            captureSession.addInput(deviceInput)
            captureSession.addOutput(videoOutput)
            
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video_frames_queue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem))
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as [String : Any]
            videoOutput.connection(with: .video)!.videoOrientation = AVCaptureVideoOrientation(orientation: interfaceOrientation)
            
            videoPreviewLayer.session = captureSession
            videoPreviewLayer.videoGravity = .resizeAspectFill
            
            layer.insertSublayer(videoPreviewLayer, at: 0)
        }
        else {
            print("Input & Output could not be added to the session")
        }
    }
    
    fileprivate func addAppObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    // MARK: Misc
    fileprivate func adjustVideoPreviewLayerFrame() {
        videoOutput.connection(with: .video)?.videoOrientation = AVCaptureVideoOrientation(orientation: interfaceOrientation)
        videoPreviewLayer.connection?.videoOrientation = AVCaptureVideoOrientation(orientation: interfaceOrientation)
        videoPreviewLayer.frame = bounds
    }
    
    fileprivate func preprocessImage(_ image: CGImage) -> CGImage {
        var inputImage = CIImage(cgImage: image)
        let averageLuminance = inputImage.averageLuminance
        var exposure = 0.5
        let threshold = (1 - pow(1 - averageLuminance, 0.2))
        
        if averageLuminance > 0.8 {
            exposure -= ((averageLuminance - 0.5) * 2)
        }
        
        if averageLuminance < 0.35 {
            exposure += pow(2, (0.5 - averageLuminance))
        }
        
        inputImage = inputImage.applyingFilter("CIExposureAdjust", parameters: ["inputEV": exposure])
                               .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 2])
                               .applyingFilter("LuminanceThresholdFilter", parameters: ["inputThreshold": threshold])
        
        return CIContext.shared.createCGImage(inputImage, from: inputImage.extent)!
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension QKMRZScannerView: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let cgImage = CMSampleBufferGetImageBuffer(sampleBuffer)?.cgImage else {
            return
        }
        
        let documentImage = self.documentImage(from: cgImage)
        let imageRequestHandler = VNImageRequestHandler(cgImage: documentImage, options: [:])
        
        let detectTextRectangles = VNDetectTextRectanglesRequest { [unowned self] request, error in
            guard error == nil else {
                return
            }
            
            guard let results = request.results as? [VNTextObservation] else {
                return
            }
            
            let imageWidth = CGFloat(documentImage.width)
            let imageHeight = CGFloat(documentImage.height)
            let transform = CGAffineTransform.identity.scaledBy(x: imageWidth, y: -imageHeight).translatedBy(x: 0, y: -1)
            let mrzTextRectangles = results.map({ $0.boundingBox.applying(transform) }).filter({ $0.width > (imageWidth * 0.8) })
            let mrzRegionRect = mrzTextRectangles.reduce(into: CGRect.null, { $0 = $0.union($1) })
            
            guard mrzRegionRect.height <= (imageHeight * 0.5) else { // Avoid processing the full image (can occur if there is a long text in the header)
                return
            }
            
            if let mrzTextImage = documentImage.cropping(to: mrzRegionRect) {
                if let mrzResult = self.mrz(from: mrzTextImage), mrzResult.allCheckDigitsValid {
                    self.stopScanning()
                    
                    DispatchQueue.main.async {
                        let enlargedDocumentImage = self.enlargedDocumentImage(from: cgImage)
                        let scanResult = QKMRZScanResult(mrzResult: mrzResult, documentImage: enlargedDocumentImage)
                        self.delegate?.mrzScannerView(self, didFind: scanResult)

                        if self.vibrateOnResult {
                            self.notificationFeedback.notificationOccurred(.success)
                        }
                    }
                }
            }
        }
        
        try? imageRequestHandler.perform([detectTextRectangles])
    }
}

extension UIImage {
    func rotatedImage(with angle: CGFloat = CGFloat.pi * 0.5) -> UIImage {
        let updatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: angle))
            .size
        
        return UIGraphicsImageRenderer(size: updatedSize)
            .image { _ in
                let context = UIGraphicsGetCurrentContext()
                context?.translateBy(x: updatedSize.width / 2.0, y: updatedSize.height / 2.0)
                context?.rotate(by: angle)
                
                draw(in: CGRect(
                    x: -size.width / 2.0,
                    y: -size.height / 2.0,
                    width: size.width,
                    height: size.height))
            }
            .withRenderingMode(renderingMode)
    }
    
}

extension Bundle {
    private class CurrentBundleClass {}
    
    static let current = Bundle(for: CurrentBundleClass.self)
}
