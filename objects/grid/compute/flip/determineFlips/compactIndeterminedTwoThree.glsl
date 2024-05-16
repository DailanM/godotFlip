#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent buffer ufFlipInfo                {uint flipInfo[];             };
layout(set = 0, binding = 1, std430) restrict coherent buffer ufPrefixSum               {uint prefixSum[];            };
layout(set = 0, binding = 2, std430) restrict coherent buffer bfIndeterminedTwoThree    {uint indeterminedTwoThree[]; };
layout(set = 0, binding = 3, std430) restrict coherent buffer bfNonconvexBadFaces       {uint nonconvexBadFaces[];    };
layout(set = 0, binding = 4, std430) restrict coherent buffer ufLengthParam
{
    uint numNonconvexBadFaces;
};

// The code we want to execute in each invocation
void main(){
    uint id             = gl_WorkGroupID.x;
    uint sumLength      = numNonconvexBadFaces + 1;
    
    // Each invocation is responsible for the content of up to two elements of each output array.
    uint ABad = 0; uint ABadFace; uint AInfo;
    uint BBad = 0; uint BBadFace; uint BInfo;

    // The first index
    // if( id * 2 < sumLength ){ // If the write flipInfo doesn't run off the summation array,
        if( id * 2 < numNonconvexBadFaces ){ // If the read flipInfo doesn't run off the input array,
            ABadFace   = nonconvexBadFaces[ id * 2 + 0 ];
            AInfo = flipInfo[ ABadFace ];
            ABad = (( AInfo >> 0 ) & 1 ) | (( AInfo >> 1 ) & 1 ) | (( AInfo >> 2 ) & 1 ); // evaluates to 1 if any one of the checks failed.
        }
        prefixSum[ id * 2 + 0 ] = ABad;
    //}

    // The second index 
    if( id * 2 + 1 < sumLength ){ // If the write flipInfo doesn't run off the summation array,
        if( id * 2 + 1 < numNonconvexBadFaces ){ // If the read flipInfo doesn't run off the input array,
            BBadFace = nonconvexBadFaces[ id * 2 + 1 ];
            BInfo = flipInfo[ BBadFace ];
            BBad = (( AInfo >> 0 ) & 1 ) | (( AInfo >> 1 ) & 1 ) | (( AInfo >> 2 ) & 1 ); // evaluates to 1 if any one of the checks failed.
        }
        prefixSum[ id * 2 + 1 ] = BBad;
    }

    // Synchronize to make sure that everyone has initialized their elements.
    barrier();
    //------------------------------------------------------------------------------------//
    
    uint readAt;
    uint writeAt;
    uint mask;

    // take initial values
    uint step = 0;
    uint MaxSteps = uint(log2( sumLength - 1 ) + 1);
    mask    = (1 << step) - 1;
    readAt  = ((id >> step) << (step + 1) + mask);
    writeAt = readAt + 1 + (id & mask);

    // For each potential step,
    for(uint j = 0; j < MaxSteps; j++)
    {
        if(writeAt < sumLength) // Write if we can.
        {
            // Accumulate the read data into the sum.
            prefixSum[writeAt] += prefixSum[readAt];

            // Increment the step
            step++;
            mask = (1 << step) - 1;
            readAt = ((id >> step) << (step + 1) + mask);
            writeAt = readAt + 1 + (id & mask);
        }
        // Synchronize again to make sure that everyone has caught up.

        barrier();  //( Every thread needs to hit this on every iteration of the for loop )//
    }
    //------------------------------------------------------------------------------------//
    // Now we have the partial sum, so use it to find the index of the split of the tetra

    uint AWriteIndex;
    uint BWriteIndex;

    // make sure our indices correspond to a tetrahedron getting split.
    if( ABad == 1 ){
        AWriteIndex = prefixSum[ id * 2 + 0 ];
        indeterminedTwoThree[ AWriteIndex ] = ABadFace;
    }

    if( BBad == 1 ){
        BWriteIndex = prefixSum[ id * 2 + 1 ];
        indeterminedTwoThree[ BWriteIndex ] = BBadFace;
    }
}