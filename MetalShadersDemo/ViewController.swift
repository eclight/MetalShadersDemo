
import UIKit
import Metal
import MetalKit

class ViewController: UIViewController {
    var metalLayer: CAMetalLayer!
    var renderer: SurfaceRenderer!
    var timer: CADisplayLink!
    var drops: [Drop] = []
    
    var tapRecognizer: UITapGestureRecognizer!
    var dragRecognizer: UIPanGestureRecognizer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        dragRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleTap))
        
        view.addGestureRecognizer(tapRecognizer)
        view.addGestureRecognizer(dragRecognizer)
        
        let device = MTLCreateSystemDefaultDevice()!
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = view.layer.frame
        view.layer.addSublayer(metalLayer)
        
        let backgroundImage = UIImage(named: "Background")!
        let w = metalLayer.bounds.width * metalLayer.contentsScale * 3
        let h = metalLayer.bounds.height * metalLayer.contentsScale * 3
        let croppedBackgroundImage = backgroundImage.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: w, height: h))!
        
        let aspect = Float(view.frame.height / view.frame.width);
        let height: Int = 256
        renderer = SurfaceRenderer(device: device, backgroundImage: croppedBackgroundImage, gridSize: (Int(Float(height) / aspect + 0.5), height))
        
        timer = CADisplayLink(target: self, selector: #selector(drawFrame))
        timer.add(to: RunLoop.main, forMode: .default)
    }
    
    func render() {
        guard let drawable = metalLayer?.nextDrawable() else { return }
        renderer.render(drawable: drawable, drops: drops)
        drops.removeAll()
    }
    
    @objc func drawFrame() {
        autoreleasepool {
            render()
        }
    }
    
    @objc
    func handleTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended || sender.state == .changed {
            let location = sender.location(in: view)
            let drop = Drop(
                x: Float(location.x / view.frame.width),
                y: Float(view.frame.height / view.frame.width) - Float(location.y / view.frame.width),
                radius: 0.04,
                strength: 0.0009)
            
            drops.append(drop)
        }
    }
}

