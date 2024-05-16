#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// ufTetra, ufTetraToFace, ufTetraToEdge, ufFace, ufFaceToTetra, ufEdge, ufActiveFaces, ufFlipInfo, ufBadFaces, ufBadFacesToFlip, ufThreeTwoBeforeFlip, ufFreedTetra, ufFreedFaces, ufFreedEdges, ufFlipOffsets

layout(set = 0, binding =  0, std430) buffer ufTetraToFace              {uint tetraToFace[];               };
layout(set = 0, binding =  1, std430) buffer ufTetraToEdge              {uint tetraToEdge[];               };
layout(set = 0, binding =  2, std430) buffer ufFaceToTetra              {uint faceToTetra[];               };

layout(set = 0, binding =  3, std430) buffer ufActiveFaces              {uint activeFaces[];               };
layout(set = 0, binding =  4, std430) buffer ufFlipInfo                 {uint flipInfo[];                  };
layout(set = 0, binding =  5, std430) buffer ufBadFaces                 {uint badFaces[];                  };
layout(set = 0, binding =  6, std430) buffer ufBadFacesToTwoThreeFlip   {uint badFacesToTwoThreeFlip[];    };

layout(set = 0, binding =  7, std430) buffer ufFreedTetra               {uint freedTetra[];                };
layout(set = 0, binding =  8, std430) buffer ufFreedFaces               {uint freedFaces[];                };
layout(set = 0, binding =  9, std430) buffer ufFreedEdges               {uint freedEdges[];                };

layout(set = 0, binding = 10, std430) buffer ufFreeOffsets
{   uint lastTetra; // Not Updated yet for the simplices to be added this flip!
    uint lastFace;
    uint lastEdge;
    uint numFreedTetra;
    uint numFreedFaces;
    uint numFreedEdges;
};

// Lookup

uint _twistA[] = {  2, 3, 1,    // applying the offset, we get (when afar is a), 0 -> {2, 3, 1}, 1 -> {3, 1, 2}, 2 1 -> {1, 2, 3}
                    0, 1, 3 };  //                          or (when afar is c), 0 -> {0, 1, 3}, 1 -> {1, 3, 0}, 2 1 -> {3, 0, 1}
uint _twistB[] = {  0, 2, 3,    // Never has an offset.        (when bfar is b), it's {0, 2, 3}
                    2, 0, 1 };  //                             (when bfar is d), it's {2, 0, 1}

uint _twistEdgeNearB[] = uint[]( 5, 2, 1,   // Never has an offset. (when bfar is b), it's {5, 2, 1}
                                 0, 3, 1 ); //                      (when bfar is d), it's {0, 3, 1}

void main() {
    uint id = gl_WorkGroupID.x;

    uint flippingBadFace    = badFacesToTwoThreeFlip[ id ];
    uint flippingActiveFace = badFaces[ flippingBadFace ];

    

    // The non-convex faces become the faces to check, so the aggregate info now reads
    // ----------------------------------------------------------------------------------------------
    // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
    // ----------------------------------------------------------------------------------------------
    // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
    // ----------------------------------------------------------------------------------------------
    //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit

    uint info               = flipInfo[ flippingBadFace ];
    uint flippingFace       = activeFaces[ flippingActiveFace ];

    // Old tetra
    uint tetA; uint tetB; uint tetC;

    uint AfarIsa; uint BfarIsb; uint faceTwist;

    uint twistFaceB[3]; uint twistEdgeNearB[3];
    uint twistFaceA[3];
    
    uint ThreeTwoOver;
 
    // -------- Grab data --------
    AfarIsa   = ( info >> 10 ) & 1;
    BfarIsb   = ( info >>  9 ) & 1;
    faceTwist = ( info >>  7 ) & 3;

    // twistFaceA and twistFaceB are connected via the shared face between tetA and tetB.
    // It will help to think of the array as cyclic, which explains the all of the mod(X, 3) when applying offsets.
    twistFaceB[0] = _twistB[ 3 * (1 - BfarIsb) + 0 ];
    twistFaceB[1] = _twistB[ 3 * (1 - BfarIsb) + 1 ];
    twistFaceB[2] = _twistB[ 3 * (1 - BfarIsb) + 2 ];

    twistEdgeNearB[0] = _twistEdgeNearB[ 3 * (1 - BfarIsb) + 0 ];
    twistEdgeNearB[1] = _twistEdgeNearB[ 3 * (1 - BfarIsb) + 1 ];
    twistEdgeNearB[2] = _twistEdgeNearB[ 3 * (1 - BfarIsb) + 2 ];
    
    twistFaceA[0] = _twistA[ 3 * (1 - AfarIsa) +            faceTwist + 0        ];
    twistFaceA[1] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 1, 3 ) ) ];
    twistFaceA[2] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 2, 3 ) ) ];

    // -------- 2 Tetra --------
    tetA = faceToTetra[ 2*flippingFace + 0 ]; // The tetra in which we are positively oriented.
    tetB = faceToTetra[ 2*flippingFace + 1 ]; // The tetra in which we are negatively oriented.

    // ------------------------ Is Three Two ------------------------ //
    // Free 1 Tetra, 2 Faces, and 1 Edge.

    ThreeTwoOver = ( ((info >> 5 ) & 1)  * 2 )  + ( ((info >> 4 ) & 1)  * 1 )  + ( ((info >> 3 ) & 1)  * 0 );

    // The other old simplex
    uint ACFaceInTet = twistFaceA[ ThreeTwoOver ]; uint ACFace = tetraToFace[ 4 * tetA + ACFaceInTet ]; // The face between A and C TO DELETE
    uint BCFaceInTet = twistFaceB[ ThreeTwoOver ]; uint BCFace = tetraToFace[ 4 * tetB + BCFaceInTet ]; // The face between B and C TO DELETE

    uint ABCEdge = tetraToEdge[ 6 * tetB + twistEdgeNearB[ ThreeTwoOver ] ];                            // THE EDGE TO DELETE!!!

    uint BOtherInFace = (BCFaceInTet + 1) & 1 ;
    tetC = faceToTetra[ 2 * BCFace + BOtherInFace ];                                               // THE TETRA TO DELETE

                // Indexing backwards
    freedTetra[ (numFreedTetra - 1) - ( 1 * id + 0 ) ] = tetC;

    freedFaces[ (numFreedFaces - 1) - ( 2 * id + 0 ) ] = ACFace;
    freedFaces[ (numFreedFaces - 1) - ( 2 * id + 1 ) ] = BCFace;

    freedEdges[ (numFreedEdges - 1) - ( 1 * id + 0 ) ] = ABCEdge;

}