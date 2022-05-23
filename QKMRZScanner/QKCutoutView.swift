//
//  QKCutoutView.swift
//  QKMRZScanner
//
//  Created by Matej Dorcak on 05/10/2018.
//

import UIKit

class QKCutoutView: UIView {
    fileprivate(set) var cutoutRect: CGRect!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.8)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Orientation or the view's size could change
        recalculateCutoutRect()
        addBorderAroundCutout()
        
        let overlayTag = 563_139_562
        let overlay = createOverlayView()
        overlay.tag = overlayTag
        
        // Add to superview as we can't to self as it's being masked
        self.superview?.viewWithTag(overlayTag)?.removeFromSuperview()
        self.superview?.addSubview(overlay)
    }
    
    private func createOverlayView() -> UIView {
        let view = UIView(frame: bounds)
        view.tag = 1001
        view.backgroundColor = .clear
        
        let horizontalLineY = cutoutRect.minY + (cutoutRect.height * 0.71)
        
        // 1. Add horizontal line layer
        view.layer.addSublayer({
            let lineLayer = CAShapeLayer()
            lineLayer.lineWidth = 2
            lineLayer.strokeColor = UIColor.white.cgColor
            lineLayer.frame = bounds
            lineLayer.path = {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: cutoutRect.minX, y: horizontalLineY))
                path.addLine(to: CGPoint(x: cutoutRect.maxX, y: horizontalLineY))
                
                return path.cgPath
            }()
            
            return lineLayer
        }())
        
        // 2. Add 2 lines of "<<<<" text
        view.layer.addSublayer({
            let fontSize: CGFloat = 20
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let bottomBox = cutoutRect.maxY - horizontalLineY
            let stringCount = calculateMrzText(maxWidth: cutoutRect.width - 40, font: font)
            let text = String(repeating: "<", count: stringCount) + "\n" + String(repeating: "<", count: stringCount)
            let textSize = NSAttributedString(string: text, attributes: [.font: font]).size()
            
            let textLayer = CATextLayer()
            textLayer.alignmentMode = .center
            textLayer.string = text
            textLayer.font = font
            textLayer.fontSize = fontSize
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.frame = CGRect(
                x: cutoutRect.minX,
                y: horizontalLineY + ((bottomBox - textSize.height) * 0.5),
                width: cutoutRect.width,
                height: textSize.height)
            
            return textLayer
        }())
        
        return view
    }
    
    private func calculateMrzText(maxWidth: CGFloat, font: UIFont) -> Int {
        for i in (1...40).reversed() {
            let size = NSAttributedString(
                string: String(repeating: "<", count: i),
                attributes: [.font: font]
            ).size()
            
            if size.width < maxWidth {
                return i
            }
        }
        
        return 1
    }
    
    // MARK: Private
    fileprivate func recalculateCutoutRect() {
        let documentFrameRatio = CGFloat(1.42) // Passport's size (ISO/IEC 7810 ID-3) is 125mm × 88mm
        let (width, height): (CGFloat, CGFloat)

        if bounds.height > bounds.width {
            width = (bounds.width * 0.9) // Fill 90% of the width
            height = (width / documentFrameRatio)
        }
        else {
            height = (bounds.height * 0.75) // Fill 75% of the height
            width = (height * documentFrameRatio)
        }

        let topOffset = (bounds.height - height) / 2
        let leftOffset = (bounds.width - width) / 2

        cutoutRect = CGRect(x: leftOffset, y: topOffset, width: width, height: height)
    }

    fileprivate func addBorderAroundCutout() {
        let maskLayer = CAShapeLayer()
        let path = CGMutablePath()
        let cornerRadius = CGFloat(20)
        
        path.addRoundedRect(in: cutoutRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        path.addRect(bounds)
        
        maskLayer.path = path
        maskLayer.fillRule = CAShapeLayerFillRule.evenOdd
        
        layer.mask = maskLayer
        
        // Add border around the cutout
        let borderLayer = CAShapeLayer()
        
        borderLayer.path = UIBezierPath(roundedRect: cutoutRect, cornerRadius: cornerRadius).cgPath
        borderLayer.lineWidth = 3
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.frame = bounds
        
        layer.sublayers = [borderLayer]
    }
}
