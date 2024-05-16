#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent          buffer ufPrefixSum      {uint prefixSum[]; };
layout(set = 0, binding = 1, std430) restrict coherent readonly buffer ufParameters
{
    uint _length;
    uint _step;
};

// The code we want to execute in each invocation
void main(){
    uint id        = gl_WorkGroupID.x;
    uint readAt;
    uint writeAt;
    uint mask;

    // take initial values
    mask    = (1 << _step) - 1;
    readAt  = ((id >> _step) << (_step + 1) ) + mask;
    writeAt = readAt + 1 + (id & mask);

    if(writeAt < _length) // Write if we can.
    {
        // Accumulate the read data into the sum.
        prefixSum[writeAt] += prefixSum[readAt];
    }
}