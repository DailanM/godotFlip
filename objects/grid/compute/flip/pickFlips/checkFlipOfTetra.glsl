#[compute]
#version 450

// Make sure the compute keyword is uncommented, and that it doesn't have a comment on the same line.
// Also, the linting plugin only works if the first line is commented, and the file extension is .comp
// Godot only works when the first line is NOT commented and the file extension is .glsl
// What a pain.

#define REAL float            // float or double
#define Rvec3 vec3            // vec3 or dvec3
#define REALTYPE highp REAL
#define REALCAST REAL
#define INEXACT               // nothing

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent buffer ufActiveFace       {uint activeFace[];     };
layout(set = 0, binding = 2, std430) restrict coherent buffer ufTetra            {uint tetra[];          };
layout(set = 0, binding = 3, std430) restrict coherent buffer ufFaceToTetra      {uint faceToTetra[];    };
layout(set = 0, binding = 4, std430) restrict coherent buffer ufTetraToFace      {uint tetraToFace[];    };
layout(set = 0, binding = 5, std430) restrict coherent buffer ufFlipInfo         {uint flipInfo[];       };
layout(set = 0, binding = 6, std430) restrict coherent buffer ufBadFaces         {uint badFaces[];       };
layout(set = 0, binding = 7, std430) restrict coherent buffer ufTetraMarkFlip    {uint tetraMarkFlip[];  };

// ---- Lookup ----

uint _twistA[] = {  2, 3, 1,    // applying the offset, we get (when afar is a), 0 -> {2, 3, 1}, 1 -> {3, 1, 2}, 2 1 -> {1, 2, 3}
                    0, 1, 3 };  //                          or (when afar is c), 0 -> {0, 1, 3}, 1 -> {1, 3, 0}, 2 1 -> {3, 0, 1}
uint _twistB[] = {  0, 2, 3,    // Never has an offset.        (when bfar is b), it's {0, 2, 3}
                    2, 0, 1 };  //                          or (when bfar is d), it's {2, 0, 1}

void main()
{
    uint id = gl_WorkGroupID.x;

    // ------------------------------ INDX ------------------------------

    // We iterate over the bad faces.
    uint BadFaceInActiveFace = badFaces[ id ];
    uint badFaceInd = activeFace[ BadFaceInActiveFace ];

    // Now we get the far vertex of in A for the locally Delauney check, and for the 3-2 test, we also need the far index in B. The shared
    // face could be indexed in each face in any order WRT the face in B, so we construct and edge adjacency list in faceBToFaceA.
    uint AfarInd; Rvec3 Afar; 
    uint BfarInd; Rvec3 Bfar;

    uint twistFaceB[3];
    uint twistFaceA[3];
    uint BOtherInFace;

    // Get the tetrahedra
    uint tetA = faceToTetra[ 2*badFaceInd + 0 ]; // The tetra in which we are positively oriented.
    uint tetB = faceToTetra[ 2*badFaceInd + 1 ]; // The tetra in which we are negatively oriented.
    uint tetC;

    // ------------------------------ INFO ------------------------------

    // ------------------------------ INFO ------------------------------

    // The first three indices are now unused, so the aggregate info now reads
    // ----------------------------------------------------------------------------------------------
    // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
    // ----------------------------------------------------------------------------------------------
    // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
    // ----------------------------------------------------------------------------------------------
    //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit

    uint info = flipInfo[ id ];

    // We either flip over the bad face, or around an edge of the bad face. The way that
    // tetrahedron are oriented in relation to each are stored in the following variables.
    uint AfarIsa; uint BfarIsb; uint faceTwist;

    // ------------------------------ Get faceStarInfo ------------------------------

    // Determine faceStarInfo
    AfarIsa   = ( info >> 10 ) & 1;
    BfarIsb   = ( info >>  9 ) & 1;
    faceTwist = ( info >>  7 ) & 3;

    //AfarInd = tetra[ 4 * tetA + 0 + 2 * ( 1 - int(AfarIsa) ) ]; // spits out AaInd if Afar Is a, spits out AcInd if Afar is not a ( so that it must be c ).
    //BfarInd = tetra[ 4 * tetB + 1 + 2 * ( 1 - int(BfarIsb) ) ]; // spits out BbInd if Bfar Is b, spits out BdInd if Bfar is not b ( so that it must be d ).

    // twistFaceA and twistFaceB are connected via the shared face between tetA and tetB.
    // It will help to think of the array as cyclic, which explains the all of the mod(X, 3) offsets.
    twistFaceB[0] = _twistB[ 3 * (1 - BfarIsb) + 0 ];
    twistFaceB[1] = _twistB[ 3 * (1 - BfarIsb) + 1 ];
    twistFaceB[2] = _twistB[ 3 * (1 - BfarIsb) + 2 ];

    //twistFaceA[0] = _twistA[ 3 * (1 - AfarIsa) +            faceTwist + 0        ];
    //twistFaceA[1] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 1, 3 ) ) ];
    //twistFaceA[2] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 2, 3 ) ) ];

    if( !( ( (info >> 6) & 1 ) == 1 ) ){ // We can two-three flip!
    
        if( (tetraMarkFlip[ tetA ] == id + 1) && (tetraMarkFlip[ tetB ] == id + 1) ){ // Success!
            
            info |= ( 1 << 13 ) ;
        }

    } else { // See if any 3-2 flip works.
        uint j = 3;

        for(uint i = 0; i < 3; i++){
            if( ( ( (info >> (i + 3)) & 1 ) == 1) ){
                // We expect only one of these to evaluate to true, but there is still a small chance two evaluate to true.
                // For now, we just take the last one. Maybe later I'll deal with a second possible 3-2 flip, but that case is degenerate, so it doesn't matter.
                j = i; 
            }
        }

        if( !(j == 3) ){
            // If we found a possible 3-2 flip, we check if it has claimed it's tetra.

            // First get the faces in A and B that share the edge uv.
            uint BFaceInTet = twistFaceB[ j ]; uint BFaceIndex = tetraToFace[ 4 * tetB + BFaceInTet ];

            // Reminder:  2*index + 0,  positivly oriented: ccw normal facing outside the tetrahedron.
            //            2*index + 1, negatively oriented: ccw normal facing  inside the tetrahedron.
            //
            //                     '(i + 1) & 1' is shorthand for mod( i + 1, 2)
            uint BOtherInFace = (BFaceInTet + 1) & 1 ;
            uint tetC = faceToTetra[ 2 * BFaceIndex + BOtherInFace ];

            if( (tetraMarkFlip[ tetA ] == id + 1) && (tetraMarkFlip[ tetB ] == id + 1) && (tetraMarkFlip[ tetC ] == id + 1) ){ // Success!
                info += ( 1 << 13 );
            } else {
                // If not, reset the 3-2 flip info.   
                info |= (1 << 3) + (1 << 4) + (1 << 5);
                info -= (1 << 3) + (1 << 4) + (1 << 5);
            }
        }
    }

    flipInfo[ id ] = info;
}