#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly  coherent buffer ufInData                {uint inData[];  };
layout(set = 0, binding = 1, std430) restrict readonly  coherent buffer ufAtData                {uint atData[];  };
layout(set = 0, binding = 2, std430) restrict writeonly coherent buffer ufOutData               {uint outData[]; };
layout(set = 0, binding = 3, std430) restrict readonly  coherent buffer ufParam
{
    uint n;
};

// The code we want to execute in each invocation
void main(){
    uint id = gl_WorkGroupID.x;

    outData[ id ] = ((inData[ atData[ id ] ] >> ( n + 2 ) ) & 1) | ((inData[ atData[ id ] ] >> ( n + 1 ) ) & 1) | ((inData[ atData[ id ] ] >> ( n + 0 ) ) & 1);
}