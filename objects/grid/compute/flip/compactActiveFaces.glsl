#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding =  0, std430) restrict coherent buffer bfActiveFaces      {uint activeFace[]; };
layout(set = 0, binding =  1, std430) restrict coherent buffer prefixParamBuffer
{
    uint faceIsActiveLength;
};

void main(){
    uint id = gl_WorkGroupID.x;
    uint sumLength = faceIsActiveLength;
    uint numFaces = faceIsActiveLength - 1;
    
    // Each invocation is responsible for the content of up to two elements of each output array.
    uint AActive = 0;
    uint BActive = 0;

    // The first index
    //if( id * 2 < sumLength ){ // If the write location doesn't run off the summation array,
        //if( id * 2 < numFaces ){ // If the read location doesn't run off the input array,
            AActive = activeFace[ id * 2 + 0 ]; // use positiveMark instead. Then we can optimize when we mark a face as active.
        //}
    //}

    // The second index 
    //if( id * 2 + 1 < sumLength ){ // If the write location doesn't run off the summation array,
        if( id * 2 + 1 < numFaces ){ // If the read location doesn't run off the input array,
            BActive = activeFace[ id * 2 + 1 ];
        }
    //}

    // Synchronize to make sure that everyone has initialized their elements.
    barrier();
    //------------------------------------------------------------------------------------//
    
    uint readAt;
    uint writeAt;
    uint mask;

    // take initial values
    uint step = 0;
    uint MaxSteps = uint(log2( sumLength - 1 ) + 1);
    mask = (1 << step) - 1;
    readAt = ((id >> step) << (step + 1) + mask);
    writeAt = readAt + 1 + (id & mask);

    // For each potential step,
    for(uint j = 0; j < MaxSteps; j++)
    {
        if(writeAt < sumLength) // Write if we can.
        {
            // Accumulate the read data into the sum.
            activeFace[writeAt] += activeFace[readAt];

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
    if( AActive == 1 ){ AWriteIndex = activeFace[id * 2 + 0]; }
    if( BActive == 1 ){ BWriteIndex = activeFace[id * 2 + 1]; }

    barrier();
    //------------------------------------------------------------------------------------//

    if( AActive == 1 ){ activeFace[ AWriteIndex ] = id * 2 + 0; }
    if( BActive == 1 ){ activeFace[ BWriteIndex ] = id * 2 + 1; }
}

// old
/*void main(){
    uint id = gl_WorkGroupID.x;
    uint readAt;
    uint writeAt;
    uint mask;
    
    // Each invocation is responsible for the content of up to two elements of the output array.
    uint A;
    uint B;
    if(    activeExtFace.data[id * 2     ] > 0) {A = 1;} else {A = 0;} // isn't there a fancy way to do this?
    compactActiveExtFace.data[id * 2     ] = A;

    if( id * 2 + 1 < compactActiveExtFaceLength )
    {
        if(    activeExtFace.data[id * 2 + 1 ] > 0) {B = 1;} else {B = 0;}
        compactActiveExtFace.data[id * 2 + 1 ] = B;
    }

    // Synchronize to make sure that everyone has initialized their elements.
    barrier();

    // take initial values
    uint step = 0;
    uint MaxSteps = uint(log2(compactActiveExtFaceLength -1) + 1);
    mask = (1 << step) - 1;
    readAt = ((id >> step) << (step + 1) + mask);
    writeAt = readAt + 1 + (id & mask);

    // For each potential step,
    for(uint j = 0; j < MaxSteps; j++)
    {
        if(writeAt < compactActiveExtFaceLength)
        {
            // Accumulate the read data into our element
            compactActiveExtFace.data[writeAt] += compactActiveExtFace.data[readAt];

            //increment the step
            step++;
            mask = (1 << step) - 1;
            readAt = ((id >> step) << (step + 1) + mask);
            writeAt = readAt + 1 + (id & mask);
        }
        // Synchronize again to make sure that everyone has caught up.
        barrier();  // Every thread needs to hit this.
    }

    uint posA;
    uint posB;
    // Now we have the partial ith partial sum, we check whether the indicies that we are in charge of are marked. If we are, we read their new position.
    if(               activeExtFace.data[id * 2 ] == 1 ) {
        posA = compactActiveExtFace.data[id * 2 ] - 1;
    }
    if( id * 2 + 1 < compactActiveExtFaceLength )
    {
        if(               activeExtFace.data[id * 2 + 1 ] == 1){
            posB = compactActiveExtFace.data[id * 2 + 1 ] - 1;
        }
    }

    barrier(); // make sure that everyone has their position before we overwrite everything.

    if(        activeExtFace.data[ id * 2 ] == 1 ) {
        compactActiveExtFace.data[ posA ] = id * 2;
    }
    if( id * 2 + 1 < compactActiveExtFaceLength )
    {
        if(        activeExtFace.data[ id * 2 + 1 ] == 1){
            compactActiveExtFace.data[ posB ] = id * 2 + 1;
        }
    }

    // And we're done!
}*/