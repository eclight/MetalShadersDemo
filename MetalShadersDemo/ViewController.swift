
import Metal
import MetalKit
import UIKit

final class ViewController: UIViewController {
    var metalLayer: CAMetalLayer!
    var renderer: SurfaceRenderer!
    var timer: CADisplayLink!
    var drops: [Drop] = []

    var tapRecognizer: UITapGestureRecognizer!
    var dragRecognizer: UIPanGestureRecognizer!
    
    let timeStep = 0.008
    var lastTime: CFTimeInterval = 0
    var timeRemainder: CFTimeInterval = 0

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
        metalLayer.contentsScale = UIScreen.main.scale
        view.layer.addSublayer(metalLayer)

        let aspect = Float(view.frame.height / view.frame.width)
        let height: Int = 256
        renderer = SurfaceRenderer(device: device, backgroundImage: prepareBackgroundImage(renderLayer: metalLayer)!, gridSize: (Int(Float(height) / aspect + 0.5), height))

        timer = CADisplayLink(target: self, selector: #selector(drawFrame))
        timer.add(to: RunLoop.main, forMode: .common)
        
        lastTime = CACurrentMediaTime()
    }
    
    func render() {
        guard let drawable = metalLayer?.nextDrawable() else { return }

        let currentTime = CACurrentMediaTime()

        var delta = currentTime - lastTime + timeRemainder

        if delta < timeStep {
            return
        }

        if delta > timeStep * 10 {
            delta = timeStep
        }

        lastTime = currentTime
        let updateIterations = Int(delta / timeStep)
        timeRemainder = delta.truncatingRemainder(dividingBy: timeStep)
        
        renderer.render(drawable: drawable, drops: drops, updateIterations: updateIterations)
        drops.removeAll()
    }

    @objc func drawFrame(displayLink: CADisplayLink) {
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
                strength: 0.0005
            )

            drops.append(drop)
        }
    }
    
    private func cropToAspect(source: CGSize, aspect: CGFloat) -> CGRect {
        let h = source.width / aspect
        
        if h <= source.height {
            return CGRect(x: 0.0, y: 0.5 * (source.height - h), width: source.width, height: h)
        } else {
            let w = source.height * aspect
            return CGRect(x: 0.5 * (source.width - w), y: 0.0, width: w, height: source.height)
        }
    }
    
    private func prepareBackgroundImage(renderLayer: CALayer) -> CGImage? {
        let backgroundImage = UIImage(named: "Background")!
        
        let croppedRect = cropToAspect(source: backgroundImage.size, aspect: renderLayer.bounds.width / renderLayer.bounds.height)
        guard let croppedBackgroundImage = backgroundImage.cgImage?.cropping(to: croppedRect) else {
            return nil
        }
        
        let newSize = CGSize(width: renderLayer.frame.width * renderLayer.contentsScale,
                             height: renderLayer.frame.height * renderLayer.contentsScale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let finalImage = renderer.image { _ in
            UIImage(cgImage: croppedBackgroundImage).draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return finalImage.cgImage
    }
}
