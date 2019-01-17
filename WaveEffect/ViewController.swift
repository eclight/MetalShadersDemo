//
//  ViewController.swift
//  WaveEffect
//
//  Created by Oleg on 12/27/18.
//  Copyright © 2018 eclight. All rights reserved.
//

import UIKit
import Metal
import MetalKit

struct Position {
    var X: Float
    var Y: Float
}

class ViewController: UIViewController {
    var device: MTLDevice!
    var metalLayer: CAMetalLayer!
    var vertexBuffer: MTLBuffer!
    var pipelineState: MTLRenderPipelineState!
    var commandQueue: MTLCommandQueue!
    var frontBuffer: MTLTexture!
    var backBuffer: MTLTexture!
    var normalMap: MTLTexture!
    var backgroundMap: MTLTexture!
    var updateHeightmapPipelineState: MTLComputePipelineState!
    var addDropPipleineState: MTLComputePipelineState!
    var computeNormalsPipelineState: MTLComputePipelineState!
    var uniformsBuffer: MTLBuffer!
    var timer: CADisplayLink!
    var taps: [Position] = []
    
    var recognizer: UITapGestureRecognizer!
    var dragRecognizer: UIPanGestureRecognizer!
    
    let vertexData: [Float] = [
        -1.0, -1.0, 0.0, 0.0,
        -1.0,  1.0, 0.0, 1.0,
         1.0, -1.0, 1.0, 0.0,
         
        -1.0,  1.0, 0.0, 1.0,
         1.0,  1.0, 1.0, 1.0,
         1.0, -1.0, 1.0, 0.0
    ]
    
    @objc
    func handleTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended || sender.state == .changed {
            let location = sender.location(in: view)
            let texturePosition = Position(X: Float(location.x / view.frame.width), Y: Float(view.frame.height / view.frame.width) - Float(location.y / view.frame.width))
            
            taps.append(texturePosition)
        }
    }
    
    func prepareBackground()
    {
        let image = UIImage(named: "Background")!
        
        let w = metalLayer.bounds.width * metalLayer.contentsScale * 3
        let h = metalLayer.bounds.height * metalLayer.contentsScale * 3
        
        let cropped = image.cgImage!.cropping(to: CGRect(x: 0, y: 0, width: w, height: h))!
        
        let loader = MTKTextureLoader(device: device)
        backgroundMap = try! loader.newTexture(cgImage: cropped, options: [MTKTextureLoader.Option.SRGB: false])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        dragRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleTap))
        
        self.view.addGestureRecognizer(recognizer)
        self.view.addGestureRecognizer(dragRecognizer)
        
        device = MTLCreateSystemDefaultDevice()
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = view.layer.frame
        view.layer.addSublayer(metalLayer)
        
        let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])

        let defaultLibrary = device.makeDefaultLibrary()!
        let fragmentProgram = defaultLibrary.makeFunction(name: "basic_fragment")
        let vertexProgram = defaultLibrary.makeFunction(name: "basic_vertex")
        
        let aspect = Float(view.frame.height / view.frame.width);
        
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 4)
        
        let height: Int = 512
        
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .rg32Float
        textureDescriptor.width = Int(Float(height) / aspect + 0.5)
        textureDescriptor.height =  height;
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        
        backBuffer = device.makeTexture(descriptor: textureDescriptor)
        frontBuffer = device.makeTexture(descriptor: textureDescriptor)
        normalMap = device.makeTexture(descriptor: textureDescriptor)
        
        let updateHeightmapFunction = defaultLibrary.makeFunction(name: "update_heightmap")
        updateHeightmapPipelineState = try! device.makeComputePipelineState(function: updateHeightmapFunction!)
        
        let addDropFunction = defaultLibrary.makeFunction(name: "add_drop")
        addDropPipleineState = try! device.makeComputePipelineState(function: addDropFunction!)
        
        let computeNormalsFunction = defaultLibrary.makeFunction(name: "compute_normals")
        computeNormalsPipelineState = try! device.makeComputePipelineState(function: computeNormalsFunction!)
        
        prepareBackground()
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)

        commandQueue = device.makeCommandQueue()
        
        timer = CADisplayLink(target: self, selector: #selector(drawFrame))
        timer.add(to: RunLoop.main, forMode: .default)
    }
    
    func writeDropUniforms(tapPos: Position, buffer: MTLBuffer) {
        var bufferDataPointer = uniformsBuffer.contents()
        
        // Tap position
        
        bufferDataPointer.storeBytes(of: tapPos, as: Position.self)
        bufferDataPointer = bufferDataPointer.advanced(by: MemoryLayout<Position>.stride)
        
        // Drop size
        
        bufferDataPointer.storeBytes(of: 0.04, as: Float.self)
        bufferDataPointer = bufferDataPointer.advanced(by: MemoryLayout<Float>.stride)
        
        // Strength
        
        bufferDataPointer.storeBytes(of: 0.0009, as: Float.self)
        bufferDataPointer = bufferDataPointer.advanced(by: MemoryLayout<Float>.size)
    }
    
    func render() {
        guard let drawable = metalLayer?.nextDrawable() else { return }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let w = updateHeightmapPipelineState.threadExecutionWidth
        let h = updateHeightmapPipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        let threadGroupsPerGrid = MTLSizeMake((frontBuffer.width + w - 1) / w,
                                              (frontBuffer.height + h - 1) / h,
                                              1)
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        for tap in taps {
            computeEncoder.setComputePipelineState(addDropPipleineState)
            computeEncoder.setTexture(frontBuffer, index: 0)
            computeEncoder.setBuffer(uniformsBuffer, offset: 0, index: 0)
            writeDropUniforms(tapPos: tap, buffer: uniformsBuffer)
            computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        }
        taps.removeAll()
        
        computeEncoder.setComputePipelineState(updateHeightmapPipelineState)
        
        for _ in 1...4 {
            computeEncoder.setTexture(frontBuffer, index: 0)
            computeEncoder.setTexture(backBuffer, index: 1)
            computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            
            swap(&frontBuffer, &backBuffer)
        }
        
        computeEncoder.setComputePipelineState(computeNormalsPipelineState)
        computeEncoder.setTexture(frontBuffer, index: 0)
        computeEncoder.setTexture(normalMap, index: 1)
        computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        computeEncoder.endEncoding()
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        renderEncoder.setFragmentTexture(normalMap, index: 0)
        renderEncoder.setFragmentTexture(backgroundMap, index: 1)
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    @objc func drawFrame() {
        autoreleasepool {
            self.render()
        }
    }
}

