#[compute]
#version 450

// Make sure the compute keyword is uncommented, and that it doesn't have a comment on the same line.
// Also, the linting plugin only works if the first line is commented, and the file extension is .comp
// Godot only works when the first line is NOT commented and the file extension is .glsl
// What a pain.

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict coherent          buffer ufTetra          {uint  tetra[];         };
layout(set = 0, binding = 1, std430) restrict coherent          buffer ufTetraToFace    {uint  tetraToFace[];   };
layout(set = 0, binding = 2, std430) restrict coherent          buffer ufTetraToEdge    {uint  tetraToEdge[];   };

layout(set = 0, binding = 3, std430) restrict coherent          buffer ufFace           {uint  face[];          };
layout(set = 0, binding = 4, std430) restrict coherent          buffer ufFaceToTetra    {uint  faceToTetra[];   };

layout(set = 0, binding = 5, std430) restrict coherent          buffer ufEdge           {uint  edge[];          };

layout(set = 0, binding = 6, std430) restrict coherent          buffer ufTetraIsSplitBy {uint tetraIsSplitBy[]; };
layout(set = 0, binding = 7, std430) restrict coherent          buffer ufSplittingTetra {uint splittingTetra[]; };

layout(set = 0, binding = 8, std430) restrict coherent          buffer ufFreedTetra     {uint freedTetra[];     };
layout(set = 0, binding = 9, std430) restrict coherent          buffer ufFreedFaces     {uint freedFaces[];     };
layout(set = 0, binding = 10, std430) restrict coherent         buffer ufFreedEdges     {uint freedEdges[];     };

layout(set = 0, binding = 12, std430) restrict coherent         buffer ufActiveFace     {uint ActiveFace[];     };

layout(set = 0, binding = 13, std430) restrict coherent         buffer ufParam
{
    uint lastTetra;
    uint lastFace;
    uint lastEdge;
    uint numFreedTetra;
    uint numFreedFaces;
    uint numFreedEdges;
    uint numSplitTetra;
};

// The code we want to execute in each invocation
void main(){
    uint id = gl_WorkGroupID.x; // one thread per splitting tetra.
    
    // Get the tetra index, and the index of the point to split with, denote it e.
    uint tet_index          = splittingTetra[ id ];
    uint e                  = tetraIsSplitBy[ id ]; // The index of the point to add.

    // Get point indices of this tetra, denoted [a,b,c,d]
    uint a = tetra[4*tet_index + 0];
    uint b = tetra[4*tet_index + 1];
    uint c = tetra[4*tet_index + 2];
    uint d = tetra[4*tet_index + 3];


    // ---------------------------------------------------- TETRAHEDRON:  ----------------------------------------------------
    // Indices of the four new tetrahedra:
    uint tetraExpansionOffset = lastTetra + 1; // The index of the first empty space in the expanded space
    
    uint tA = tet_index; uint tB;uint tC; uint tD; // The first tetra takes the place of the old tetrahedron.
    
    if( id * 3 + 0 < numFreedTetra ){ tB = freedTetra[ (numFreedTetra - 1) - (3 * id + 0) ]; } else { tB = tetraExpansionOffset + ( (id * 3 + 0) - numFreedTetra ); }
    if( id * 3 + 1 < numFreedTetra ){ tC = freedTetra[ (numFreedTetra - 1) - (3 * id + 1) ]; } else { tC = tetraExpansionOffset + ( (id * 3 + 1) - numFreedTetra ); }
    if( id * 3 + 2 < numFreedTetra ){ tD = freedTetra[ (numFreedTetra - 1) - (3 * id + 2) ]; } else { tD = tetraExpansionOffset + ( (id * 3 + 2) - numFreedTetra ); }

    // Add the four new tetra, overwriting the original tetrahedron with tetA.
    // ~~~~~~~~~~ tet A
        tetra[ 4*tA + 0 ] = e;
        tetra[ 4*tA + 1 ] = c;
        tetra[ 4*tA + 2 ] = d;
        tetra[ 4*tA + 3 ] = b;
    // ~~~~~~~~~~ tet B
        tetra[ 4*tB + 0 ] = a;
        tetra[ 4*tB + 1 ] = e;
        tetra[ 4*tB + 2 ] = c;
        tetra[ 4*tB + 3 ] = d;
    // ~~~~~~~~~~ tet C
        tetra[ 4*tC + 0 ] = a;
        tetra[ 4*tC + 1 ] = b;
        tetra[ 4*tC + 2 ] = e;
        tetra[ 4*tC + 3 ] = d;
    // ~~~~~~~~~~ tet D
        tetra[ 4*tD + 0 ] = c;
        tetra[ 4*tD + 1 ] = a;
        tetra[ 4*tD + 2 ] = b;
        tetra[ 4*tD + 3 ] = e;

    // ------------------------------------------ FACES, FACE TO TETRA, TETRA TO FACE: ------------------------------------------
    // Remember that the faces are identified up to a rotation

    // Indicies
    uint faceExpansionOffset = (lastFace + 1); // The index of the first empty space in the expanded space

    uint fABE; uint fAEC; uint fAED; uint fBEC; uint fBED; uint fCDE;

    if( id * 6 + 0 < numFreedFaces ){ fABE = freedFaces[ (numFreedFaces - 1) - (6 * id + 0) ]; } else { fABE = faceExpansionOffset + ( (id * 6 + 0) - numFreedFaces ); }
    if( id * 6 + 1 < numFreedFaces ){ fAEC = freedFaces[ (numFreedFaces - 1) - (6 * id + 1) ]; } else { fAEC = faceExpansionOffset + ( (id * 6 + 1) - numFreedFaces ); }
    if( id * 6 + 2 < numFreedFaces ){ fAED = freedFaces[ (numFreedFaces - 1) - (6 * id + 2) ]; } else { fAED = faceExpansionOffset + ( (id * 6 + 2) - numFreedFaces ); }
    if( id * 6 + 3 < numFreedFaces ){ fBEC = freedFaces[ (numFreedFaces - 1) - (6 * id + 3) ]; } else { fBEC = faceExpansionOffset + ( (id * 6 + 3) - numFreedFaces ); }
    if( id * 6 + 4 < numFreedFaces ){ fBED = freedFaces[ (numFreedFaces - 1) - (6 * id + 4) ]; } else { fBED = faceExpansionOffset + ( (id * 6 + 4) - numFreedFaces ); }
    if( id * 6 + 5 < numFreedFaces ){ fCDE = freedFaces[ (numFreedFaces - 1) - (6 * id + 5) ]; } else { fCDE = faceExpansionOffset + ( (id * 6 + 5) - numFreedFaces ); }

    // the face between edge ab and point e:
    face[3*fABE + 0] = a;
    face[3*fABE + 1] = b;
    face[3*fABE + 2] = e;
    // the face between edge ac and point e:
    face[3*fAEC + 0] = a;
    face[3*fAEC + 1] = e;
    face[3*fAEC + 2] = c;
    // the face between edge ad and point e:
    face[3*fAED + 0] = a;
    face[3*fAED + 1] = e;
    face[3*fAED + 2] = d;
    // the face between edge bc and point e:
    face[3*fBEC + 0] = b;
    face[3*fBEC + 1] = e;
    face[3*fBEC + 2] = c;
    // the face between edge bd and point e:
    face[3*fBED + 0] = b;
    face[3*fBED + 1] = e;
    face[3*fBED + 2] = d;
    // the face between edge cd and point e:
    face[3*fCDE + 0] = c;
    face[3*fCDE + 1] = d;
    face[3*fCDE + 2] = e;

    // We fill out the face to tetra data for all the new faces. There is space reserved for this.
    // 2*index + 0,  positivly oriented: normal facing outside the tetrahedron.
    // 2*index + 1, negatively oriented: normal facing  inside the tetrahedron.
    // The tetrahedron of face ABE
    faceToTetra[2*fABE + 0] = tD;
    faceToTetra[2*fABE + 1] = tC;
    // The tetrahedron of face AEC
    faceToTetra[2*fAEC + 0] = tD;
    faceToTetra[2*fAEC + 1] = tB;
    // The tetrahedron of face AED
    faceToTetra[2*fAED + 0] = tB;
    faceToTetra[2*fAED + 1] = tC;
    // The tetrahedron of face BEC
    faceToTetra[2*fBEC + 0] = tA;
    faceToTetra[2*fBEC + 1] = tD;
    // The tetrahedron of face BED
    faceToTetra[2*fBED + 0] = tC;
    faceToTetra[2*fBED + 1] = tA;
    // The tetrahedron of face CDE
    faceToTetra[2*fCDE + 0] = tB;
    faceToTetra[2*fCDE + 1] = tA;

    // get indices of the faces of the original tetrahedron. We are new free to overwrite tetraToFace at tA:
    uint fA = tetraToFace[4*tet_index + 0]; // the face that does not include a
    uint fB = tetraToFace[4*tet_index + 1]; // the face that does not include b
    uint fC = tetraToFace[4*tet_index + 2]; // the face that does not include c
    uint fD = tetraToFace[4*tet_index + 3]; // the face that does not include d

    // Old face to tet data should have been copied over.
    faceToTetra[2*fA + 0] = tA;
    faceToTetra[2*fB + 1] = tB;
    faceToTetra[2*fC + 0] = tC;
    faceToTetra[2*fD + 1] = tD; // faceToTetra is now updated.

    // the faces of tetrahedron tA:
    tetraToFace[ 4*tA + 0 ] = fA;    // the original face without A
    tetraToFace[ 4*tA + 1 ] = fBED;  // none of these have point A
    tetraToFace[ 4*tA + 2 ] = fBEC;
    tetraToFace[ 4*tA + 3 ] = fCDE;
    // the faces of tetrahedron tB:
    tetraToFace[ 4*tB + 0 ] = fCDE;
    tetraToFace[ 4*tB + 1 ] = fB;
    tetraToFace[ 4*tB + 2 ] = fAED;
    tetraToFace[ 4*tB + 3 ] = fAEC;
    // the faces of tetrahedron tC:
    tetraToFace[ 4*tC + 0 ] = fBED;
    tetraToFace[ 4*tC + 1 ] = fAED;
    tetraToFace[ 4*tC + 2 ] = fC;
    tetraToFace[ 4*tC + 3 ] = fABE;
    // the faces of tetrahedron tD:
    tetraToFace[ 4*tD + 0 ] = fABE;
    tetraToFace[ 4*tD + 1 ] = fBEC;
    tetraToFace[ 4*tD + 2 ] = fAEC;
    tetraToFace[ 4*tD + 3 ] = fD;

    // ------------------------------------------ EDGES, TETRA TO EDGES: ------------------------------------------
    
    // Indicies
    uint edgeExpansionOffset = (lastEdge + 1);

    uint eAE; uint eBE; uint eCE; uint eDE;

    if( id * 4 + 0 < numFreedEdges ){ eAE = freedEdges[ (numFreedEdges - 1) - (4 * id + 0) ]; } else { eAE = edgeExpansionOffset + ( (id * 4 + 0) - numFreedEdges ); }
    if( id * 4 + 1 < numFreedEdges ){ eBE = freedEdges[ (numFreedEdges - 1) - (4 * id + 1) ]; } else { eBE = edgeExpansionOffset + ( (id * 4 + 1) - numFreedEdges ); }
    if( id * 4 + 2 < numFreedEdges ){ eCE = freedEdges[ (numFreedEdges - 1) - (4 * id + 2) ]; } else { eCE = edgeExpansionOffset + ( (id * 4 + 2) - numFreedEdges ); }
    if( id * 4 + 3 < numFreedEdges ){ eDE = freedEdges[ (numFreedEdges - 1) - (4 * id + 3) ]; } else { eDE = edgeExpansionOffset + ( (id * 4 + 3) - numFreedEdges ); }

    // All the edges are new and have their location reserved, so we are free to simply write them.
    // the new edge between a and e
    edge[2*eAE + 0] = a;
    edge[2*eAE + 1] = e;
    // the new edge between a and e
    edge[2*eBE + 0] = b;
    edge[2*eBE + 1] = e;
    // the new edge between a and e
    edge[2*eCE + 0] = c;
    edge[2*eCE + 1] = e;
    // the new edge between a and e
    edge[2*eDE + 0] = d;
    edge[2*eDE + 1] = e;

    // get indices of the edges of the original tetrahedron. We are new free to overwrite tetraToEdge at tA:
    uint eAB = tetraToEdge[ 6*tet_index + 0];
    uint eAC = tetraToEdge[ 6*tet_index + 1];
    uint eAD = tetraToEdge[ 6*tet_index + 2];
    uint eBC = tetraToEdge[ 6*tet_index + 3];
    uint eBD = tetraToEdge[ 6*tet_index + 4];
    uint eCD = tetraToEdge[ 6*tet_index + 5];

    // tet=[0,1,2,3], edges[ (0,1), (0,2), (0,3), (1,2), (1,3), (2,3) ]

    // the edges of tetrahedron A=[e,c,d,b]:
    tetraToEdge[ 6*tA + 0 ] = eCE;
    tetraToEdge[ 6*tA + 1 ] = eDE;
    tetraToEdge[ 6*tA + 2 ] = eBE;
    tetraToEdge[ 6*tA + 3 ] = eCD;
    tetraToEdge[ 6*tA + 4 ] = eBC;
    tetraToEdge[ 6*tA + 5 ] = eBD;
    // the edges of tetrahedron B=[a,e,c,d]:
    tetraToEdge[ 6*tB + 0 ] = eAE;
    tetraToEdge[ 6*tB + 1 ] = eAC;
    tetraToEdge[ 6*tB + 2 ] = eAD;
    tetraToEdge[ 6*tB + 3 ] = eCE;
    tetraToEdge[ 6*tB + 4 ] = eDE;
    tetraToEdge[ 6*tB + 5 ] = eCD;
    // the edges of tetrahedron C=[a,b,e,d]:
    tetraToEdge[ 6*tC + 0 ] = eAB;
    tetraToEdge[ 6*tC + 1 ] = eAE;
    tetraToEdge[ 6*tC + 2 ] = eAD;
    tetraToEdge[ 6*tC + 3 ] = eBE;
    tetraToEdge[ 6*tC + 4 ] = eBD;
    tetraToEdge[ 6*tC + 5 ] = eDE;
    // the edges of tetrahedron D=[c,a,b,e]:
    tetraToEdge[ 6*tD + 0 ] = eAC;
    tetraToEdge[ 6*tD + 1 ] = eBC;
    tetraToEdge[ 6*tD + 2 ] = eCE;
    tetraToEdge[ 6*tD + 3 ] = eAB;
    tetraToEdge[ 6*tD + 4 ] = eAE;
    tetraToEdge[ 6*tD + 5 ] = eBE;

    // -------- MARK ACTIVE EXTERIOR FACES:  --------

    // 2*index + 0,  positivly oriented: normal facing outside the tetrahedron.
    // 2*index + 1, negatively oriented: normal facing  inside the tetrahedron.

    // TODO: sus
    // For each exterior face, check if it's a boundary face, and if it's already active. If it isn't active, make it so.
    if( (fA > 3) && ( ActiveFace[ fA ] == 0 ) ){ atomicMax( ActiveFace[ fA ], 1 ); }
    if( (fB > 3) && ( ActiveFace[ fB ] == 0 ) ){ atomicMax( ActiveFace[ fB ], 1 ); }
    if( (fC > 3) && ( ActiveFace[ fC ] == 0 ) ){ atomicMax( ActiveFace[ fC ], 1 ); }
    if( (fD > 3) && ( ActiveFace[ fD ] == 0 ) ){ atomicMax( ActiveFace[ fD ], 1 ); }

}