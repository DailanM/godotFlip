#[compute]
#version 450

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict readonly  coherent buffer ufInData    {uint inData[];     };
layout(set = 0, binding = 1, std430) restrict readonly  coherent buffer ufWriteData {uint writeData[];  };
layout(set = 0, binding = 2, std430) restrict readonly  coherent buffer ufSummedData   {uint summedData[];    };
layout(set = 0, binding = 3, std430) restrict writeonly coherent buffer ufOutData   {uint outData[];    };

void main(){
    uint id = gl_WorkGroupID.x;
    if( uint( inData[ id ] > 0) == 1){
        outData[ 6 * (summedData[ id ] - 1) + 0 ] = writeData[ 6 * id + 0 ];
        outData[ 6 * (summedData[ id ] - 1) + 1 ] = writeData[ 6 * id + 1 ];
        outData[ 6 * (summedData[ id ] - 1) + 2 ] = writeData[ 6 * id + 2 ];
        outData[ 6 * (summedData[ id ] - 1) + 3 ] = writeData[ 6 * id + 3 ];
        outData[ 6 * (summedData[ id ] - 1) + 4 ] = writeData[ 6 * id + 4 ];
        outData[ 6 * (summedData[ id ] - 1) + 5 ] = writeData[ 6 * id + 5 ];
    }
}