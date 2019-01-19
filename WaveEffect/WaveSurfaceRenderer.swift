//
//  WaterSurface.swift
//  WaveEffect
//
//  Created by Oleg on 1/18/19.
//  Copyright © 2019 eclight. All rights reserved.
//

import Metal
import MetalKit
import UIKit

struct Drop {
    var x: Float
    var y: Float
    var radius: Float
    var strength: Float
}

class WaveSurfaceRenderer {
    private let device: MTLDevice
    private let vertexBuffer: MTLBuffer
    private let dropBuffer: MTLBuffer
    private var frontHeightMap: MTLTexture
    private var backHeightMap: MTLTexture
    private let normalMap: MTLTexture
    private let backgroundMap: MTLTexture
    private let updateHeightmapPipelineState: MTLComputePipelineState
    private let addDropPipleineState: MTLComputePipelineState
    private let computeNormalsPipelineState: MTLComputePipelineState
    private let renderPipelineState: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue
    private let threadsPerThreadgroup: MTLSize
    private let threadGroupsPerGrid: MTLSize
    
    private let vertexData: [Float] = [
        -1.0, -1.0, 0.0, 0.0,
        -1.0,  1.0, 0.0, 1.0,
        1.0, -1.0, 1.0, 0.0,
        
        -1.0,  1.0, 0.0, 1.0,
        1.0,  1.0, 1.0, 1.0,
        1.0, -1.0, 1.0, 0.0
    ]
    
    init(device: MTLDevice, backgroundImage: CGImage, gridSize: (Int, Int)) {
        self.device = device
        
        let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])!
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let fragmentProgram = defaultLibrary.makeFunction(name: "basic_fragment")
        let vertexProgram = defaultLibrary.makeFunction(name: "basic_vertex")
        
        dropBuffer = device.makeBuffer(length: MemoryLayout<Drop>.size)!
        
        let gridTextureDescriptor = MTLTextureDescriptor()
        let (width, height) = gridSize
        gridTextureDescriptor.pixelFormat = .rg32Float
        gridTextureDescriptor.width = width
        gridTextureDescriptor.height = height
        gridTextureDescriptor.usage = [.shaderWrite, .shaderRead]
        
        backHeightMap = device.makeTexture(descriptor: gridTextureDescriptor)!
        frontHeightMap = device.makeTexture(descriptor: gridTextureDescriptor)!
        normalMap = device.makeTexture(descriptor: gridTextureDescriptor)!
        
        let loader = MTKTextureLoader(device: device)
        backgroundMap = try! loader.newTexture(cgImage: backgroundImage, options: [MTKTextureLoader.Option.SRGB: false])
        
        let updateHeightmapFunction = defaultLibrary.makeFunction(name: "update_heightmap")
        updateHeightmapPipelineState = try! device.makeComputePipelineState(function: updateHeightmapFunction!)
        
        let addDropFunction = defaultLibrary.makeFunction(name: "add_drop")
        addDropPipleineState = try! device.makeComputePipelineState(function: addDropFunction!)
        
        let computeNormalsFunction = defaultLibrary.makeFunction(name: "compute_normals")
        computeNormalsPipelineState = try! device.makeComputePipelineState(function: computeNormalsFunction!)
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
        commandQueue = device.makeCommandQueue()!
        
        let w = updateHeightmapPipelineState.threadExecutionWidth
        let h = updateHeightmapPipelineState.maxTotalThreadsPerThreadgroup / w
        threadsPerThreadgroup = MTLSizeMake(w, h, 1)
        threadGroupsPerGrid = MTLSizeMake((frontHeightMap.width + w - 1) / w,
                                          (frontHeightMap.height + h - 1) / h, 1)
    }
    
    func render(drawable: CAMetalDrawable, drops: [Drop]) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        for tap in drops {
            computeEncoder.setComputePipelineState(addDropPipleineState)
            computeEncoder.setTexture(frontHeightMap, index: 0)
            computeEncoder.setBuffer(dropBuffer, offset: 0, index: 0)
            writeDropData(drop: tap, buffer: dropBuffer)
            computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        }

        computeEncoder.setComputePipelineState(updateHeightmapPipelineState)
        
        for _ in 0..<3 {
            computeEncoder.setTexture(frontHeightMap, index: 0)
            computeEncoder.setTexture(backHeightMap, index: 1)
            computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            
            swap(&frontHeightMap, &backHeightMap)
        }
        
        computeEncoder.setComputePipelineState(computeNormalsPipelineState)
        computeEncoder.setTexture(frontHeightMap, index: 0)
        computeEncoder.setTexture(normalMap, index: 1)
        computeEncoder.dispatchThreadgroups(threadGroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        computeEncoder.endEncoding()
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        renderEncoder.setFragmentTexture(normalMap, index: 0)
        renderEncoder.setFragmentTexture(backgroundMap, index: 1)
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 1)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func writeDropData(drop: Drop, buffer: MTLBuffer) {
        let bufferDataPointer = buffer.contents()
        bufferDataPointer.storeBytes(of: drop, as: Drop.self)
    }
}
