//
//  Shaders.metal
//  WaveEffect
//
//  Created by Oleg on 12/27/18.
//  Copyright © 2018 eclight. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

typedef struct
{
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} VertexOut;

typedef struct
{
    packed_float2 dropCenter;
    float radius;
    float strength;
} AddDropUniforms;

vertex VertexOut
basic_vertex(const device packed_float4* vertex_array [[ buffer(0) ]],
             unsigned int vid [[ vertex_id ]])
{
    float4 vert = vertex_array[vid];
    return VertexOut { float4(vert.xy, 1.0), vert.zw };
}

fragment float4
basic_fragment(VertexOut in [[ stage_in ]],
               texture2d<float,
               access::sample> normalMap [[ texture(0) ]],
               texture2d<float, access::sample> backgroundMap [[ texture(1) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    const float2 normal = normalMap.sample(textureSampler, in.textureCoordinate).xy;
    return backgroundMap.sample(textureSampler, in.textureCoordinate + 2 * float2(normal));
}

kernel void
add_drop(texture2d<float, access::read_write> output [[texture(0)]],
         constant AddDropUniforms& uniforms [[buffer(0)]],
         uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    const float2 coords { float(gid.x) / float(output.get_width()), float(gid.y) / float(output.get_width()) };
    
    float drop = max(0.0, 1.0 - distance(float2(uniforms.dropCenter), coords) / uniforms.radius);
    drop = 0.5 - cos(drop * M_PI_H) * 0.5;
    
    const float4 cell = output.read(gid);
    cell.x += drop * uniforms.strength;
    output.write(cell, gid);
}

kernel void
update_heightmap(texture2d<float, access::read> input [[texture(0)]],
                 texture2d<float, access::write> output [[texture(1)]],
                 uint2 gid [[thread_position_in_grid]])
{
    const uint w = output.get_width();
    const uint h = output.get_height();
    
    if (gid.x >= w || gid.y >= h) {
        return;
    }
        
    float4 cell = input.read(gid);
    
    const uint2 left   { uint(max(0, int(gid.x - 1))), gid.y };
    const uint2 right  { uint(min(int(w), int(gid.x + 1))), gid.y };
    const uint2 top    { gid.x, uint(min(int(h), int(gid.y + 1))) };
    const uint2 bottom { gid.x, uint(max(0, int(gid.y - 1))) };
    
    const float average = 0.25 * (input.read(left).x + input.read(right).x + input.read(top).x + input.read(bottom).x);
    cell.y += (average - cell.x) * 2;
    cell.y *= 0.995;
    cell.x += cell.y;
    
    output.write(cell, gid);
}

kernel void
compute_normals(texture2d<float, access::read> input [[texture(0)]],
                texture2d<float, access::write> output [[texture(1)]],
                uint2 gid [[thread_position_in_grid]])
{
    const uint w = output.get_width();
    const uint h = output.get_height();
    
    if (gid.x >= w || gid.y >= h) {
        return;
    }
    
    const uint2 right { uint(min(int(w), int(gid.x + 1))), gid.y };
    const uint2 top   { gid.x, uint(min(int(h), int(gid.y + 1))) };
    
    const float height = input.read(gid).x;
    const float dhx = input.read(right).x - height;
    const float dhy = input.read(top).x - height;
    const float3 vx { 1.0 / w, 0, dhx };
    const float3 vy { 0, 1.0 / h, dhy };
    const float3 normal = normalize(cross(vx, vy));
    
    output.write(float4(normal.x, normal.y, 0.0, 1.0), gid);
}
