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
layout(set = 0, binding = 1, std430) restrict coherent buffer ufPoints           {REALTYPE points[];     };
layout(set = 0, binding = 2, std430) restrict coherent buffer ufTetra            {uint tetra[];          };
layout(set = 0, binding = 3, std430) restrict coherent buffer ufFaceToTetra      {uint faceToTetra[];    };
layout(set = 0, binding = 4, std430) restrict coherent buffer ufTetraToFace      {uint tetraToFace[];    };
layout(set = 0, binding = 5, std430) restrict coherent buffer ufFlipInfo         {uint flipInfo[];       };
layout(set = 0, binding = 6, std430) restrict coherent buffer ufBadFaces         {uint badFaces[]; };
layout(set = 0, binding = 7, std430) restrict coherent buffer ufPredConsts       {REALTYPE predConsts[]; };



/* Which of the following two methods of finding the absolute values is      */
/*   fastest is compiler-dependent.  A few compilers can inline and optimize */
/*   the fabs() call; but most will incur the overhead of a function call,   */
/*   which is disastrously slow.  A faster way on IEEE machines might be to  */
/*   mask the appropriate bit, but that's difficult to do in C.              */

#define Absolute(a)  ((a) >= 0.0 ? (a) : -(a))
/* #define Absolute(a)  fabs(a) */
      
//  orient3d_fast()   Adaptive exact 3D orientation test.  Robust.                
//                                                                           
//               Return a positive value if the point pd lies below the      
//               plane passing through pa, pb, and pc; "below" is defined so 
//               that pa, pb, and pc appear in counterclockwise order when   
//               viewed from above the plane.  Returns a negative value if   
//               pd lies above the plane.  Returns zero if the points are    
//               'nearly' coplanar.
//                                                                           
//  Only the first and last routine should be used; the middle two are for   
//  timings.                                                                 
//                                                                           
//  The last three use exact arithmetic to ensure a correct answer.  The     
//  result returned is the determinant of a matrix.  In orient3d() only,     
//  this determinant is computed adaptively, in the sense that exact         
//  arithmetic is used only to the degree it is needed to ensure that the    
//  returned value has the correct sign.  Hence, orient3d() is usually quite 
//  fast, but will run more slowly when the input points are coplanar or     
//  nearly so.                                                               
//                                                                           

REALTYPE orient3d_fast(Rvec3 pa,Rvec3 pb,Rvec3 pc,Rvec3 pd)
{
  REALTYPE adx, bdx, cdx, ady, bdy, cdy, adz, bdz, cdz;
  REALTYPE bdxcdy, cdxbdy, cdxady, adxcdy, adxbdy, bdxady;
  REALTYPE det;
  REALTYPE permanent, errbound;

  adx = pa[0] - pd[0];
  bdx = pb[0] - pd[0];
  cdx = pc[0] - pd[0];
  ady = pa[1] - pd[1];
  bdy = pb[1] - pd[1];
  cdy = pc[1] - pd[1];
  adz = pa[2] - pd[2];
  bdz = pb[2] - pd[2];
  cdz = pc[2] - pd[2];

  bdxcdy = bdx * cdy;
  cdxbdy = cdx * bdy;

  cdxady = cdx * ady;
  adxcdy = adx * cdy;

  adxbdy = adx * bdy;
  bdxady = bdx * ady;

  det = adz * (bdxcdy - cdxbdy) 
      + bdz * (cdxady - adxcdy)
      + cdz * (adxbdy - bdxady);

  permanent = (Absolute(bdxcdy) + Absolute(cdxbdy)) * Absolute(adz)
            + (Absolute(cdxady) + Absolute(adxcdy)) * Absolute(bdz)
            + (Absolute(adxbdy) + Absolute(bdxady)) * Absolute(cdz);
  errbound = predConsts[ 6 ] * permanent;
  if ((det > errbound) || (-det > errbound)) {
    return det;
  }

  return 0;
}

Rvec3 pointOfIndex( uint n )
{
  return Rvec3( points[ 3 * n + 0 ], points[ 3 * n + 1 ], points[ 3 * n + 2 ] );
}

// Lookup

uint _twistA[] = {  2, 3, 1,    // applying the offset, we get (when afar is a), 0 -> {2, 3, 1}, 1 -> {3, 1, 2}, 2 -> {1, 2, 3}
                    0, 1, 3 };  //                          or (when afar is c), 0 -> {0, 1, 3}, 1 -> {1, 3, 0}, 2 -> {3, 0, 1}
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

  // Get the tetrahedra
  uint tetA = faceToTetra[ 2*badFaceInd + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra[ 2*badFaceInd + 1 ]; // The tetra in which we are negatively oriented.

  // ------------------------------ INFO ------------------------------

  // Aggregate info, to pass to subsiquent shaders.
  // ----------------------------------------------------------------------------------------------
  // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
  // ----------------------------------------------------------------------------------------------
  // ... | Face 2 check 3-2  |   Face 1 check 3-2  | Face 0 check 3-2  | Face 2 Indeterminant | ...
  // ----------------------------------------------------------------------------------------------
  //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit
  uint info = 0;

  // We either flip over the bad face, or around an edge of the bad face. The way that
  // tetrahedron are oriented in relation to each are stored in the following variables.
  uint AfarIsa; uint BfarIsb; uint faceTwist;
  // Here we mean the star in the sense of a subcomplex of the triangulation seen as a simplicial complex.

  // ------------------------------ Determine faceStarInfo ------------------------------

  // Determine faceStarInfo
  AfarIsa   = uint( badFaceInd == tetraToFace[4 * tetA + 0]); // int( bool ) sends false -> 0, true -> 1.
  BfarIsb   = uint( badFaceInd == tetraToFace[4 * tetB + 1]);

  // to read this correctly, note that only one of these equality checks can be true, so that this assigns the first offset value over which the twisted faces agree.
  faceTwist = ( 3 - 2 * uint( tetra[ 4 * tetA + _twistA[ 3 * (1 - AfarIsa) + 0 ] ] == tetra[ 4 * tetB + _twistB[ 3 * (1 - BfarIsb) + 0 ] ] )
                  - 1 * uint( tetra[ 4 * tetA + _twistA[ 3 * (1 - AfarIsa) + 1 ] ] == tetra[ 4 * tetB + _twistB[ 3 * (1 - BfarIsb) + 0 ] ] ) ) - 1;
      // Should be 0 if the 0th twist point in tetA is the 0th twist point in tetB,
      //           1 if the 1st twist point in tetA is the 0th twist point in tetB,
      //        or 2 if the 2nd twist point in tetA is the 0th twist point in tetB.
      //
      // Will become the offset for _twistA.

  info += (AfarIsa   << 10 );
  info += (BfarIsb   <<  9 );
  info += (faceTwist <<  7 );

  AfarInd = tetra[ 4 * tetA + 0 + 2 * ( 1 - int(AfarIsa) ) ]; // spits out AaInd if Afar Is a, spits out AcInd if Afar is not a ( so that it must be c ).
  BfarInd = tetra[ 4 * tetB + 1 + 2 * ( 1 - int(BfarIsb) ) ]; // spits out BbInd if Bfar Is b, spits out BdInd if Bfar is not b ( so that it must be d ).

  Afar = pointOfIndex( AfarInd );
  Bfar = pointOfIndex( BfarInd );

  // twistFaceA and twistFaceB are connected via the shared face between tetA and tetB.
  // It will help to think of the array as cyclic, which explains the all of the mod(X, 3) offsets.
  twistFaceB[0] = _twistB[ 3 * (1 - BfarIsb) + 0 ];
  twistFaceB[1] = _twistB[ 3 * (1 - BfarIsb) + 1 ];
  twistFaceB[2] = _twistB[ 3 * (1 - BfarIsb) + 2 ];

  // ------------------------------ CHECK 3-2 ------------------------------
  // We can only perform a simple 2-3 if the star of the face is convex. We can
  // check convexity by assuring that the point Afar lies underneath every face
  // in B. If any face fails this check, then the bad face can only be involved
  // in a flip if it's a 3-2 flip with the third tetrahedron located on the other
  // side of the failed face. (A picture would be very helpful here.)
  
  // we check each face in a loop, marking the faces that need a more precise check:
  for(uint i = 0; i < 3; i++){
    // We check convexity of the face obtained by removing the ith point in B.
    // Rather than grabbing the face directly, we fix the orientation by the twist of the face.
    uint uInBInd = twistFaceB[ uint( mod(i + 1, 3) ) ]; // The initial point of the edge in b
    uint vInBInd = twistFaceB[ uint( mod(i + 2, 3) ) ]; // The final   point of the edge in b

    uint uInd    = tetra[ 4 * tetB + uInBInd];      // We get the actual point indicies.
    uint vInd    = tetra[ 4 * tetB + vInBInd];      //

    Rvec3 u = pointOfIndex( uInd );                 // Then we grab the points.
    Rvec3 v = pointOfIndex( vInd );                 //

    // Now we check whether we fail the convexity test!
    float faceOrient = sign( orient3d_fast( u, v, Bfar, Afar) );

    if(        faceOrient <  0.0 ){ // We fail! We know we can't 2-3 flip. We'll later check for a three-two flip around this edge.
      
      info |= (1 << (6    )); // can't two three
      info |= (1 << (3 + i)); // need to check this face for 3-2 flip

    } else if( faceOrient == 0.0 ){ // Our check was indeterminant! We need to apply exact arithmetic in this case, assuming we can't find another suitable case.
      
      info |= (1 << (0 + i)); // need to check the convexity of this face again.

    }
  }

  flipInfo[id] = info;
}



























































//not as old!
/*
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
  uint AOtherInFace;
  uint BOtherInFace;

  // To probe the points of tetC later.
  uint CtestPoints[2];

  // Get the tetrahedra
  uint tetA = faceToTetra[ 2*badFaceInd + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra[ 2*badFaceInd + 1 ]; // The tetra in which we are negatively oriented.
  uint tetC;

  // ------------------------------ INFO ------------------------------

  // Aggregate info, to pass to subsiquent shaders.
  uint info = 0;

  // The above decomposes into:
  // We either flip over the bad face, or around an edge of the bad face. The way that
  // tetrahedron are oriented in relation to each are stored in the following variables.
  uint faceStarInfo = 0; uint AfarIsa; uint BfarIsb; uint faceTwist;
  // Here we mean the star in the sense of a subcomplex of the triangulation seen as a simplicial complex.

  // uint edgeStarInfo = 0; uint partialDetermination = 0;

  // ------------------------------ Control Flow ------------------------------

  // keeps track of whether we can perform a 2-3 flip, and is false if we fail any convexity test.
  bool canTwoThreeFlip;
  //bool flipNotDetermined;

  // ------------------------------ Determine faceStarInfo ------------------------------

  // Determine faceStarInfo
  AfarIsa   = uint( badFaceInd == tetraToFace[4 * tetA + 0]); // int( bool ) sends false -> 0, true -> 1.
  BfarIsb   = uint( badFaceInd == tetraToFace[4 * tetB + 1]);
      // to read this correctly, note that only one of these equality checks can be true, then this assigns the first offset value over which the twisted faces agree.
  faceTwist = ( 3 - 2 * uint( tetra[ 4 * tetA + _twistA[ 3 * (1 - AfarIsa) + 0 ] ] == tetra[ 4 * tetB + _twistB[ 3 * (1 - BfarIsb) + 0 ] ] )
                  - 1 * uint( tetra[ 4 * tetA + _twistA[ 3 * (1 - AfarIsa) + 1 ] ] == tetra[ 4 * tetB + _twistB[ 3 * (1 - BfarIsb) + 0 ] ] ) ) - 1;
      // Should be 0 if the 0th twist point in tetA is the 0th twist point in tetB,
      //           1 if the 1st twist point in tetA is the 0th twist point in tetB,
      //        or 2 if the 2nd twist point in tetA is the 0th twist point in tetB.
      //
      // Will become the offset for _twistA.

  // Would it be better to name this variable something like "4bitPartialInfo"? it's not at all clear that I'm going to combine it with another variable.
  faceStarInfo = ( faceTwist << 2 ) & ( BfarIsb << 1 ) & ( AfarIsa << 0 ); // takes up 4 bits.

  AfarInd = tetra[ 4 * tetA + 0 + 2 * ( 1 - int(AfarIsa) ) ]; // spits out AaInd if Afar Is a, spits out AcInd if Afar is not a ( so that it must be c ).
  BfarInd = tetra[ 4 * tetB + 1 + 2 * ( 1 - int(BfarIsb) ) ]; // spits out BbInd if Bfar Is b, spits out BdInd if Bfar is not b ( so that it must be d ).

  // twistFaceA and twistFaceB are connected via the shared face between tetA and tetB.
  // It will help to think of the array as cyclic, which explains the all of the mod(X, 3) offsets.
  twistFaceB[0] = _twistB[ 3 * (1 - BfarIsb) + 0 ];
  twistFaceB[1] = _twistB[ 3 * (1 - BfarIsb) + 1 ];
  twistFaceB[2] = _twistB[ 3 * (1 - BfarIsb) + 2 ];

  twistFaceA[0] = _twistA[ 3 * (1 - AfarIsa) +            faceTwist + 0        ];
  twistFaceA[1] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 1, 3 ) ) ];
  twistFaceA[2] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 2, 3 ) ) ];

  // ------------------------------ CHECK 3-2 ------------------------------
  // We can only perform a simple 2-3 if the star of the face is convex. We can
  // check convexity by assuring that the point Afar lies underneath every face
  // in B. If any face fails this check, then the bad face can only be involved
  // in a flip if it's a 3-2 flip with the third tetrahedron located on the other
  // side of the failed face. (A picture would be very helpful here.)

  canTwoThreeFlip = true;
  // flipNotDetermined = true;
  
  // we check each face in a loop, marking the faces that need a more precise check:
  for(uint i = 0; i < 3; i++){
    // We check convexity of the face obtained by removing the ith point in B.
    // Rather than grabbing the face directly, we fix the orientation by the twist of the face.
    uint uInBInd = twistFaceB[ uint( mod(i + 1, 3) ) ]; // The initial point of the edge in b
    uint vInBInd = twistFaceB[ uint( mod(i + 2, 3) ) ]; // The final   point of the edge in b

    uint uInd    = tetra[ 4 * tetB + uInBInd];      // We get the actual point indicies.
    uint vInd    = tetra[ 4 * tetB + vInBInd];      //

    Rvec3 u = pointOfIndex( uInd );                 // Then we grab the points.
    Rvec3 v = pointOfIndex( vInd );                 //

    // Now we check whether we fail the convexity test!
    float faceOrient = sign( orient3d( u, v, Bfar, Afar) );

    if(        faceOrient <  0.0 ){ // We fail! We know we can't 2-3 flip, so check for a three-two flip across this edge.
      canTwoThreeFlip = false;

    } else if( faceOrient == 0.0 ){ // Our check was indeterminant! We need to apply exact arithmetic in this case, assuming we can't find another suitable case.
      // TODO: Mark for an exact check.
      
    }
    



      // First get the faces in A and B that share the edge uv.
      uint BFaceInTet = twistFaceB[ i ]; uint BFaceIndex = tetraToFace[ 4 * tetB + BFaceInTet ];
      uint AFaceInTet = twistFaceA[ i ]; uint AFaceIndex = tetraToFace[ 4 * tetB + AFaceInTet ];

      // Reminder:  2*index + 0,  positivly oriented: ccw normal facing outside the tetrahedron.
      //            2*index + 1, negatively oriented: ccw normal facing  inside the tetrahedron.
      //
      //                     '(i + 1) & 1' is shorthand for mod( i + 1, 2)
      BOtherInFace = (BFaceInTet + 1) & 1 ;uint BOtherTet = faceToTetra[ 2 * BFaceIndex + BOtherInFace ];
      AOtherInFace = (AFaceInTet + 1) & 1 ;uint AOtherTet = faceToTetra[ 2 * AFaceIndex + AOtherInFace ];

      if( BOtherTet == AOtherTet ){ // There is a third tetrahedron that shares this edge and both faces! Now we check that the 3-2 flip is valid.
        tetC = BOtherTet;

        CtestPoints[ 0 ] = tetra[ 4 * tetC + 0 ]; // Ca
        CtestPoints[ 1 ] = tetra[ 4 * tetC + 1 ]; // Cb
        
        // We run two checks
        uint isQ = uint( AfarInd == CtestPoints[ 1 - uint( i == 2 ) ] );
        uint isS = uint( BfarInd == CtestPoints[ 0 + uint( i == 2 ) ] );

        uint threeConfig = (i*3 + faceTwist) * 4 + isQ * 2 + isS;

        bool invalidConfig =    ( threeConfig ==  8 )
                             || ( threeConfig == 11 )
                             || ( threeConfig == 13 )
                             || ( threeConfig == 14 );
        
        if(!invalidConfig){
          // Horray! Only one thing left to check!

          // TODO: FIX THIS LINE!
          // We check this by ensuring that the two points of the edge lie on opposite
          // sides of a face drawn by the far points and remaining point of the active face.

          uint wInB = twistFaceB[ i ]; uint wInd = tetra.data[ 4 * tetB + wInB ];
          Rvec3 w = pointOfIndex( wInd );
          
          if( is_valid && !( orient3d(w, Bfar, Afar, u) == orient3d(w, Bfar, Afar, v) ) ){
            // Sucess! We've determined a flip!
            flipNotDetermined = false;
          }

        }
        
      }



  // the point Afar fails the convexity test with face i!
        canTwoThreeFlip = false;

        // Now we check for a 3-2 flip across face i. We first need to check
        // whether the corresponding face in A across the edge is connected
        // to the same third tetrahedron.

        

        

        // We can only continue the 3-2 flip if there is a third tetrahedron across the faces of this edge.
        // TODO: check that the upper faces aren't faces 1,2,3,4.
        if( BOtherTet == AOtherTet ){
          // We now refer to this tetrahedron as tetC
          tetC = BOtherTet;
          
          // A 3-2 flip is valid if we have a valid orientation of the 3-complex,
          // and if the union of the three tetrahedra is convex.

          // we first check whether the 3 complex has a valid orientation. There are 28 possible orientations, 24 of which are valid.
          uint twoThreeInfo = 0;
          bool is_valid = true;

          uint CaInd = tetra.data[ 4 * tetB + 0 ];
          uint CbInd = tetra.data[ 4 * tetB + 1 ];
          uint CcInd = tetra.data[ 4 * tetB + 2 ];
          uint CdInd = tetra.data[ 4 * tetB + 3 ];





          /
        }
      }

      i++; 
    }

    // We break from the loop, and have either found a 3-2 flip, or have checked every face to see if the 2-3 flip is valid.
    if( canTwoThreeFlip ){
      // Success! All faces pass for a 2-3 flip, so we encode it.
    }


}
*/


//old!
  /*
  // We iterate on the active faces.
  uint activeFaceIndex = ActiveFace.data[ gl_WorkGroupID.x ];
  // This integer will store all the info about the flip.
  uint info = 0;

  // Get the tetrahedra
  uint tetA = faceToTetra.data[ 2*activeFaceIndex + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra.data[ 2*activeFaceIndex + 1 ]; // The tetra in which we are negatively oriented.
  uint tetC;

  // We need all the points in tetB and tetA
  uint BaInd = tetra.data[ 4 * tetB + 0 ];  Rvec3 Ba = pointOfIndex( BaInd );
  uint BbInd = tetra.data[ 4 * tetB + 1 ];  Rvec3 Bb = pointOfIndex( BbInd );
  uint BcInd = tetra.data[ 4 * tetB + 2 ];  Rvec3 Bc = pointOfIndex( BcInd );
  uint BdInd = tetra.data[ 4 * tetB + 3 ];  Rvec3 Bd = pointOfIndex( BdInd );

  uint AaInd = tetra.data[ 4 * tetA + 0 ];  Rvec3 Aa = pointOfIndex( AaInd );
  uint AbInd = tetra.data[ 4 * tetA + 1 ];  Rvec3 Ab = pointOfIndex( AbInd );
  uint AcInd = tetra.data[ 4 * tetA + 2 ];  Rvec3 Ac = pointOfIndex( AcInd );
  uint AdInd = tetra.data[ 4 * tetA + 3 ];  Rvec3 Ad = pointOfIndex( AdInd );

  // Now we get the far vertex of in A for the locally Delauney check,
  // and for the 3-2 test, we also need the far index in B. The shared
  // face could be indexed in each face in any order WRT the face in B,
  // so we construct and edge adjacency list in faceBToFaceA.
  uint AfarInA; uint AfarInd; Rvec3 Afar; 
  uint BfarInB; uint BfarInd; Rvec3 Bfar;
  uint twistFaceB[3];
  uint twistFaceA[3];
  uint AOtherInFace;
  uint BOtherInFace;
    

  // TODO: I'm changing twistfaceB in the case where the far index is d. idk if that will break anything later.
  if( activeFaceIndex == tetraToFace.data[4 * tetA + 0] ){
    // WRT A the active face is [b,c,d] and the far index is 'a.'
    AfarInA = 0;
    Set_Afar_Is_A( info );

      if( activeFaceIndex == tetraToFace.data[4 * tetB + 1] ){
        // WRT B the active face is [a,c,d] and the far index is 'b.'
        BfarInB = 1;
        Set_Bfar_Is_B( info );
        twistFaceB = uint[]( 0, 2, 3 );

        // Now tetA could be glued to tetB in 3 different ways:
        if(      BaInd == AcInd){ twistFaceA = uint[]( 2, 3, 1 ); Set_Twist_Flip_0( info ); }
        else if( BaInd == AdInd){ twistFaceA = uint[]( 3, 1, 2 ); Set_Twist_Flip_1( info ); }
        else                    { twistFaceA = uint[]( 1, 2, 3 ); Set_Twist_Flip_2( info ); }
        
      }else{
        // WRT B the active face is [a,b,c] and the far index is 'd.'
        BfarInB = 3;
        Set_Bfar_Is_D( info );
        twistFaceB = uint[]( 2, 0 ,1 );

        // Now tetA could be glued to tetB in 3 different ways:
        if(      BaInd == AdInd){ twistFaceA = uint[]( 2, 3, 1 ); Set_Twist_Flip_0( info ); }
        else if( BaInd == AbInd){ twistFaceA = uint[]( 3, 1, 2 ); Set_Twist_Flip_1( info ); }
        else                    { twistFaceA = uint[]( 1, 2, 3 ); Set_Twist_Flip_2( info ); }
      }
  } else{
    // WRT A the active face is [a,b,d] and the far index is 'c.'
    AfarInA = 2;
    Set_Afar_Is_C( info );

      if( activeFaceIndex == tetraToFace.data[4 * tetB + 1] ){
        // WRT B the active face is [a,c,d] and the far index is 'b.'
        BfarInB = 1;
        Set_Bfar_Is_B( info );
        twistFaceB = uint[]( 0, 2, 3 );

        // Now tetA could be glued to tetB in 3 different ways:
        if(      BaInd == AaInd){ twistFaceA = uint[]( 0, 1, 3 ); Set_Twist_Flip_0( info ); }
        else if( BaInd == AbInd){ twistFaceA = uint[]( 1, 3, 0 ); Set_Twist_Flip_1( info ); }
        else                    { twistFaceA = uint[]( 3, 0, 1 ); Set_Twist_Flip_2( info ); }
      }else{
        // WRT B the active face is [a,b,c] and the far index is 'd.'
        BfarInB = 3;
        Set_Bfar_Is_D( info );
        twistFaceB = uint[]( 2, 0, 1 );

        // Now tetA could be glued to tetB in 3 different ways:
        if(      BaInd == AbInd){ twistFaceA = uint[]( 0, 1, 3 ); Set_Twist_Flip_0( info ); }
        else if( BaInd == AdInd){ twistFaceA = uint[]( 1, 3, 0 ); Set_Twist_Flip_1( info ); }
        else                    { twistFaceA = uint[]( 3, 0, 1 ); Set_Twist_Flip_2( info ); }
      }
  }

  // Now check to see if the face is locally Delauney: Check if we fail
  // the locally Delauney property. If we pass, then we don't flip.

  // Get the far index in A.
  AfarInd = tetra.data[ 4 * tetA + AfarInA]; Afar = pointOfIndex( AfarInd );
  BfarInd = tetra.data[ 4 * tetB + BfarInB]; Bfar = pointOfIndex( BfarInd );

  if( sign( insphere(Ba, Bb, Bc, Bd, Afar) ) == 1.0 )
  {
    // We fail! Now we'll check for a 2-3 flip, or a 3-2 flip if that fails.

    // A break.
    bool flipNotDetermined = true;
    // Observes failure.
    bool canTwoThreeFlip = true;

    // We loop over the 3 edges of the active face, and check if any face fails the convexity test.
    uint i = 0;
    while( (flipNotDetermined) && (i < 3) )
    { 
      // We remove the point i in the face of tetB
      uint uInB    = twistFaceB[ uint(mod(i + 1, 3)) ]; // initial point of edge in b
      uint vInB    = twistFaceB[ uint(mod(i + 2, 3)) ]; // final   point of edge in b
      uint uInd    = tetra.data[ 4 * tetB + uInB];
      uint vInd    = tetra.data[ 4 * tetB + vInB];

      Rvec3 u = pointOfIndex( uInd );
      Rvec3 v = pointOfIndex( vInd );

      if( sign( orient3d( u, v, Bfar, Afar) ) < 0.0 ) // TODO: seperate this into a kernel for the fast check, and a kernel for the exact check.
      {
        // the point Afar fails the convexity test with face i!
        canTwoThreeFlip = false;

        // Now we check for a 3-2 flip across face i. We first need to check
        // whether the corresponding face in A across the edge is connected
        // to the same third tetrahedron.

        uint BFaceInTet   = twistFaceB[ i ]; uint BFaceIndex = tetraToFace.data[ 4 * tetB + BFaceInTet ];
        uint AFaceInTet   = twistFaceA[ i ]; uint AFaceIndex = tetraToFace.data[ 4 * tetB + AFaceInTet ];

        // 2*index + 0,  positivly oriented: ccw normal facing outside the tetrahedron.
        // 2*index + 1, negatively oriented: ccw normal facing  inside the tetrahedron.
        BOtherInFace = (BFaceInTet + 1) & 1 ;uint BOtherTet = faceToTetra.data[ 2 * BFaceIndex + BOtherInFace ];
        AOtherInFace = (AFaceInTet + 1) & 1 ;uint AOtherTet = faceToTetra.data[ 2 * AFaceIndex + AOtherInFace ];

        // We can only continue the 3-2 flip if there is a third tetrahedron across the faces of this edge.
        // TODO: check that the upper faces aren't faces 1,2,3,4.
        if( BOtherTet == AOtherTet ){
          // We now refer to this tetrahedron as tetC
          tetC = BOtherTet;
          
          // A 3-2 flip is valid if we have a valid orientation of the 3-complex,
          // and if the union of the three tetrahedra is convex.

          // we first check whether the 3 complex has a valid orientation. There are 28 possible orientations, 24 of which are valid.
          uint twoThreeInfo = 0;
          bool is_valid = true;

          uint CaInd = tetra.data[ 4 * tetB + 0 ];
          uint CbInd = tetra.data[ 4 * tetB + 1 ];
          uint CcInd = tetra.data[ 4 * tetB + 2 ];
          uint CdInd = tetra.data[ 4 * tetB + 3 ];

          if(        i == 0 ) {
                                // We record the face
                                Set_ThreeTwo_Of_0( twoThreeInfo );
                                // Three cases for twist of tetA
                                if(      Twist_Of( info ) == 0 ){
                                                                  if(     AfarInd == CbInd ){ Set_TetC_Of_Q( twoThreeInfo ); }
                                                                  else /* AfarInd == CdInd*//*{ Set_TetC_Of_R( twoThreeInfo ); } }
                                else if( Twist_Of( info ) == 1 ){
                                                                  if(     AfarInd == CbInd ){ Set_TetC_Of_Q( twoThreeInfo ); }
                                                                  else /* AfarInd == CdInd*//*{ Set_TetC_Of_R( twoThreeInfo ); }
                                                                  if(     BfarInd == CaInd ){ Set_TetC_Of_S( twoThreeInfo ); }
                                                                  else /* BfarInd == CcInd*//*{ Set_TetC_Of_T( twoThreeInfo ); } }
                                else   /*Twist_Of( info ) == 2*//*{
                                                                  if(     AfarInd == CbInd ){ Set_TetC_Of_Q( twoThreeInfo ); if(     BfarInd == CaInd ){ /*Set_TetC_Of_S( twoThreeInfo );*//* is_valid = false; }
                                                                                                                            else /* BfarInd == CcInd*//*{   Set_TetC_Of_T( twoThreeInfo ); } }
                                                                  else /* AfarInd == CdInd*//*{ Set_TetC_Of_R( twoThreeInfo ); if(     BfarInd == CaInd ){   Set_TetC_Of_S( twoThreeInfo ); }
                                                                                                                            else /* BfarInd == CcInd*//*{ /*Set_TetC_Of_T( twoThreeInfo );*//* is_valid = false; } } }
          } else if( i == 1 ) {
                                // We record the face
                                Set_ThreeTwo_Of_1( twoThreeInfo );
                                // Three cases for twist of tetA
                                if(      Twist_Of( info ) == 0 ){
                                                                  if(     AfarInd == CbInd ){ Set_TetC_Of_Q( twoThreeInfo ); if(     BfarInd == CaInd ){   Set_TetC_Of_S( twoThreeInfo ); }
                                                                                                                            else /* BfarInd == CcInd*//*{ /*Set_TetC_Of_T( twoThreeInfo );*//* is_valid = false; } }
                                                                  else /* AfarInd == CdInd*//*{ Set_TetC_Of_R( twoThreeInfo ); if(     BfarInd == CaInd ){ /*Set_TetC_Of_S( twoThreeInfo );*//* is_valid = false; }
                                                                                                                            else /* BfarInd == CcInd*//*{   Set_TetC_Of_T( twoThreeInfo ); } } }
                                else if( Twist_Of( info ) == 1 ){
                                                                  if(     AfarInd == CbInd ){ Set_TetC_Of_Q( twoThreeInfo ); }
                                                                  else /* AfarInd == CdInd*//*{ Set_TetC_Of_R( twoThreeInfo ); }
                                                                  if(     BfarInd == CaInd ){ Set_TetC_Of_S( twoThreeInfo ); }
                                                                  else /* BfarInd == CcInd*//*{ Set_TetC_Of_T( twoThreeInfo ); } }
                                else   /*Twist_Of( info ) == 2*//*{
                                                                  if(     AfarInd == CbInd ){ Set_TetC_Of_Q( twoThreeInfo ); }
                                                                  else /* AfarInd == CdInd*//*{ Set_TetC_Of_R( twoThreeInfo ); } }
          } else /*  i == 2*//* {
                                // We record the face
                                Set_ThreeTwo_Of_2( twoThreeInfo );
                                // Three cases for twist of tetA
                                if(      Twist_Of( info ) == 0 ){
                                                                  if(     AfarInd == CaInd ){ Set_TetC_Of_Q( twoThreeInfo ); }
                                                                  else /* AfarInd == CcInd*//*{ Set_TetC_Of_R( twoThreeInfo ); } }
                                else if( Twist_Of( info ) == 1 ){
                                                                  if(     AfarInd == CaInd ){ Set_TetC_Of_Q( twoThreeInfo ); }
                                                                  else /* AfarInd == CcInd*//*{ Set_TetC_Of_R( twoThreeInfo ); }
                                                                  if(     BfarInd == CbInd ){ Set_TetC_Of_S( twoThreeInfo ); }
                                                                  else /* BfarInd == CdInd*//*{ Set_TetC_Of_T( twoThreeInfo ); } }
                                else   /*Twist_Of( info ) == 2*//*{
                                                                  if(     AfarInd == CaInd ){ Set_TetC_Of_Q( twoThreeInfo ); }
                                                                  else /* AfarInd == CcInd*//*{ Set_TetC_Of_R( twoThreeInfo ); } } } //TODO: write out info if we pass or whatever.

          // We check this by ensuring that the two points of the edge lie on opposite
          // sides of a face drawn by the far points and remaining point of the active face.

          uint wInB = twistFaceB[ i ]; uint wInd = tetra.data[ 4 * tetB + wInB ];
          Rvec3 w = pointOfIndex( wInd );
          
          if( is_valid && !( orient3d(w, Bfar, Afar, u) == orient3d(w, Bfar, Afar, w) ) ){
            // Sucess! We've determined a flip!
            flipNotDetermined = false;
          }
        }
      }

      i++; 
    }

    // We break from the loop, and have either found a 3-2 flip, or have checked every face to see if the 2-3 flip is valid.
    if( canTwoThreeFlip ){
      // Success! All faces pass for a 2-3 flip, so we encode it.
    }

  }

  // Max the flip in tetra for the tetra of our potential flip.
  if( Is_TwoThree( info ) ){
    if(tetraMarkFlip.data[ tetA ] != uint(0) - uint(1)) //I want the max uint. is this correct?
    {
      atomicMax(tetraMarkFlip.data[ tetA ], uint(0) - uint(1));
      atomicMax(tetraMarkFlip.data[ tetB ], uint(0) - uint(1));
    }
  } else {
    if(tetraMarkFlip.data[ tetA ] != uint(0) - uint(1)) //?
    {
      atomicMax(tetraMarkFlip.data[ tetA ], uint(0) - uint(1));
      atomicMax(tetraMarkFlip.data[ tetB ], uint(0) - uint(1));
      atomicMax(tetraMarkFlip.data[ tetC ], uint(0) - uint(1));
    }
  }

  barrier();

  // After we set the index to the max index, we can begin voting for the flip.

  bool canidate = false;
  if( Is_TwoThree( info ) )
  {
    canidate =             ( activeFaceIndex + 1 == atomicMin( tetraMarkFlip.data[ tetA ] , activeFaceIndex + 1) );
    canidate = canidate && ( activeFaceIndex + 1 == atomicMin( tetraMarkFlip.data[ tetB ] , activeFaceIndex + 1) );
  } else
  {
    canidate =             ( activeFaceIndex + 1 == atomicMin( tetraMarkFlip.data[ tetA ] , activeFaceIndex + 1) );
    canidate = canidate && ( activeFaceIndex + 1 == atomicMin( tetraMarkFlip.data[ tetB ] , activeFaceIndex + 1) );
    canidate = canidate && ( activeFaceIndex + 1 == atomicMin( tetraMarkFlip.data[ tetC ] , activeFaceIndex + 1) );
  }

  barrier();

  // If all the involved tetra have retained our vote, we will indeed flip. If not, we don't flip.
  bool winner = false;
  if( canidate )
  {
    if( Is_TwoThree( info ) )
    {
      winner =           ( activeFaceIndex + 1 == tetraMarkFlip.data[ tetA ] );
      winner = winner && ( activeFaceIndex + 1 == tetraMarkFlip.data[ tetB ] );
    } else {
      winner =           ( activeFaceIndex + 1 == tetraMarkFlip.data[ tetA ] );
      winner = winner && ( activeFaceIndex + 1 == tetraMarkFlip.data[ tetB ] );
      winner = winner && ( activeFaceIndex + 1 == tetraMarkFlip.data[ tetC ] );
    }
  }

  if( !winner )
  {
    Set_No_Flip( info ); // TODO: Make sure this actually sets it as NOFLIP
  }

  flipInfo.data[ gl_WorkGroupID.x ] = info; // TODO: double check that we actually got all the info.



  // maybe it makes more sense to only write the flip info if we won. Is flip info 0 a valid flip?
  //  if( Is_TwoThree( info ) ){
  //    set_if
  //
  //    flipInfo.data[ gl_WorkGroupID.x ] = info; // More info will need to be passed to the flipTet kernel.
  //  } else {
  //
  //    flipInfo.data[ gl_WorkGroupID.x ] = info; // More info will need to be passed to the flipTet kernel.
  //  }
  //} else {
  //  flipAtActiveFace.data[ gl_WorkGroupID.x ] = 0;
  //}

  */





/* old
void main()
{   
  // We iterate on the active faces.
  uint activeFaceIndex = ActiveFace.data[ gl_WorkGroupID.x ];
  // This integer will store all the info about the flip.
  // We initally zero to indicate that no flip will occer,
  // and try to find a flip as an exception.
  uint flipAtThisIndex = 0;

  // Get the tetrahedra
  uint tetA = faceToTetra.data[ 2*activeFaceIndex + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra.data[ 2*activeFaceIndex + 1 ]; // The tetra in which we are negatively oriented.

  uint BaInd = tetra.data[ 4 * tetB + 0 ];
  uint BbInd = tetra.data[ 4 * tetB + 1 ];
  uint BcInd = tetra.data[ 4 * tetB + 2 ];
  uint BdInd = tetra.data[ 4 * tetB + 3 ];

  Rvec3 Ba = Rvec3(points.data[ 3 * BaInd + 0 ], points.data[ 3 * BaInd + 1 ], points.data[ 3 * BaInd + 2 ]);
  Rvec3 Bb = Rvec3(points.data[ 3 * BbInd + 0 ], points.data[ 3 * BbInd + 1 ], points.data[ 3 * BbInd + 2 ]);
  Rvec3 Bc = Rvec3(points.data[ 3 * BcInd + 0 ], points.data[ 3 * BcInd + 1 ], points.data[ 3 * BcInd + 2 ]);
  Rvec3 Bd = Rvec3(points.data[ 3 * BdInd + 0 ], points.data[ 3 * BdInd + 1 ], points.data[ 3 * BdInd + 2 ]);

  // The face is locally Delauney if the circumsphere of one of its tetrahedra does not contain
  // the far point of the opposite tetrahedra. This property is symmetric, so we let B play the
  // part of the circumscribed tetra, and test the far point of A.
  uint AfarInd;
  Rvec3 Afar;
  if( activeFaceIndex == tetraToFace.data[4 * tetA + 0] )
  {
    // WRT A the active face is [b,c,d] and the far index is 'a.'
    AfarInd = tetra.data[4 * tetA + 0];
    Afar = Rvec3(points.data[ 3 * AfarInd + 0 ], points.data[ 3 * AfarInd + 1 ], points.data[ 3 * AfarInd + 2 ]);
  }
  else
  {
    // In this case, WRT A the active face is [a,b,d] and the far index is 'c.'
    AfarInd = tetra.data[4 * tetA + 2];
    Afar = Rvec3(points.data[ 3 * AfarInd + 0 ], points.data[ 3 * AfarInd + 1 ], points.data[ 3 * AfarInd + 2 ]);
  }
  // For the 3-2 test, we also need the far index in B.
  
  // Since the active face is a positively oriented face in A, it either has index 0 or 2 in A,
  // and so the far index is either point a or c.
  if( activeFaceIndex == tetraToFace.data[4 * tetA + 0] )
  {
    // WRT A the active face is [b,c,d] and the far index is 'a.'
    AfarInd = tetra.data[4 * tetA + 0];
    Afar = Rvec3(points.data[ 3 * AfarInd + 0 ], points.data[ 3 * AfarInd + 1 ], points.data[ 3 * AfarInd + 2 ]);

    // Check if we fail the locally Delauney property. If we pass, then we don't flip.
    if( sign( insphere(Ba, Bb, Bc, Bd, Afar) ) == 1.0 )
    {
      // Now we can proform a 2-3 flip if the union of the two tetrahedra is convex,
      // and 3-2 flip across a failing face if there is a single tetrahedron across
      // the shared edge of the active and failing face.
      bool canTwoThreeFlip = true;
      bool flipDetermined = false;

      // Find the index of the active face in B for the 3-2 flip tests.
      uint BfarInd;
      Rvec3 Bfar;
      if( activeFaceIndex == tetraToFace.data[4 * tetB + 1] )
      {
        // WRT B the active face is [a,c,d] and the far index is 'b.'
        BfarInd = tetra.data[4 * tetA + 1];
      
        // A positive face returns a positive value in Orient3d if it lies below the face wrt the ccw normal.
        // therefore, we need to ensure that the positive faces are positive, and similarly that the negative
        // are negative.

        // Now we check the face [b,c,d], of positive orientation.
        if( sign( orient3d( Bb, Bc, Bd, Afar)) < 0.0 )
        {
          // We fail a 2-3 flip here.
          canTwoThreeFlip = false;

          // So check for a 3-2 flip! We can make a 3-2 flip if there is a third tetrahedron connecting to the tetrahedra
          // sharing the active face across the failed edge, and if both points of the shared edge lies on opposite
          // sides of a plane drawn by the far points of A and B, and the far point in the active face from the shared edge

          //First we check for a shared face: 
          REALTYPE threeTwoOrientBc = sign( orient3d( Ba, Bfar, Afar, Bc) );
          REALTYPE threeTwoOrientBd = sign( orient3d( Ba, Bfar, Afar, Bd) );

          if( ( threeTwoOrientBc != threeTwoOrientBd ) && ( threeTwoOrientBc != 0.0 ) && ( threeTwoOrientBd != 0.0 ) )
          {
            // We've determined a flip! Now we need to encode it.
            flipDetermined = true;
            // flipAtThisIndex = something;
          }
        }

        // Now we check the face [a,b,d], of positive orientation, if needed.
        if( !flipDetermined )
        {
          if( sign( orient3d( Ba, Bb, Bd, Afar)) < 0.0 )
          {
            // We fail a 2-3 flip here.
            canTwoThreeFlip = false;

            // So check for a 3-2 flip!
            REALTYPE threeTwoOrientBa = sign( orient3d( Bc, Bfar, Afar, Ba) );
            REALTYPE threeTwoOrientBd = sign( orient3d( Bc, Bfar, Afar, Bd) );

            if( ( threeTwoOrientBa != threeTwoOrientBd ) && ( threeTwoOrientBa != 0.0 ) && ( threeTwoOrientBd != 0.0 ) )
            {
              // We've determined a flip! Now we need to encode it.
              flipDetermined = true;
              // flipAtThisIndex = something;
            }
          }

          // Now we check the face [a,b,c], of negative orientation, if needed.
          if( !flipDetermined )
          {
            if( sign( orient3d( Ba, Bb, Bc, Afar)) > 0.0 )
            {
              // We fail a 2-3 flip here.
              canTwoThreeFlip = false;

              // So check for a 3-2 flip!
              REALTYPE threeTwoOrientBa = sign( orient3d( Bd, Bfar, Afar, Ba) );
              REALTYPE threeTwoOrientBc = sign( orient3d( Bd, Bfar, Afar, Bc) );

              if( ( threeTwoOrientBa != threeTwoOrientBc ) && ( threeTwoOrientBa != 0.0 ) && ( threeTwoOrientBc != 0.0 ) )
              {
                // We've determined a flip! Now we need to encode it.
                flipDetermined = true;
                // flipAtThisIndex = something;
              }
            }
          }
        }
      }
      else
      {
        // WRT B the active face is [a,b,c] and the far index is 'd.'
        BfarInd = tetra.data[4 * tetA + 3];

      }
    }
  }
  else // same as above
  {
    // In this case, WRT A the active face is [a,b,d] and the far index is 'c.'
    AfarInd = tetra.data[4 * tetA + 2];
    Afar = Rvec3(points.data[ 3 * AfarInd + 0 ], points.data[ 3 * AfarInd + 1 ], points.data[ 3 * AfarInd + 2 ]);

    // Check if we fail the locally Delauney property. If we pass, then we don't flip.
    if( sign( insphere(Ba, Bb, Bc, Bd, Afar) ) == 1.0 )
    {
      // Now we can proform a 2-3 flip if the union of the two tetrahedra is convex,
      // and 3-2 flip across a failing face if there is a single tetrahedron across
      // the shared edge of the active and failing face.
      bool canTwoThreeFlip = true;
      bool flipDetermined = false;

      // Find the index of the active face in B for the 3-2 flip tests.
      uint BfarInd;
      uint Bfar;
      if( activeFaceIndex == tetraToFace.data[4 * tetB + 1] )
      {
        // WRT B the active face is [a,c,d] and the far index is 'b.'
        BfarInd = tetra.data[4 * tetA + 1];
      }
      else
      {
        // WRT B the active face is [a,b,c] and the far index is 'd.'
        BfarInd = tetra.data[4 * tetA + 3];
      }


      
    }
  }





    if 

      // If any of the faces fail, then we will not be able to perform a 2-3 flip, so
      // we check to see if we can perform a 3-2 flip across the failing face instead.

      // We check the two positively oriented faces in B first.
      if( !flipDetermined ) // (does nothing here)
      {
        // Face 0: [b,c,d]
        REALTYPE bFaceA_Orient = orient3d( Bb, Bc, Bd, Afar);  // needs to be positive
        if( sign( bFaceA_Orient ) < 0.0 )
        { 
          // If the test fails, then we can't do a 2-3 flip.the check for a 3-2 flip, check for a shared tetrahedron across this face.

          canTwoThreeFlip = false;
          
          //stuff

        }
      }
  
  if( sign( insphere(Ba, Bb, Bc, Bd, Afar) ) == 1.0 )
  { 
    // If the face fails the insphere test, we'll try to find a valid flip:
    bool flipDetermined = false;
    

    // A positive face returns a positive value in Orient3d if it lies below the face wrt the ccw normal.
    // therefore, we need to ensure that the positive faces aren't negative, and similarly that the negative
    // faces aren't positive.

    // Face 0: [b,c,d]
    REALTYPE bFaceA_Orient = orient3d( Bb, Bc, Bd, Afar);  // needs to be positive
    if( sign( bFaceA_Orient ) < 0.0 )
    { 
      two_ThreeFlip = false;
      // If the test fails the check for a 3-2 flip, check for a shared tetrahedron across this face.

      //stuff

    }

    // Face 2: [a,b,d]
    if( !three_TwoFlip )
    {
      REALTYPE bFaceC_Orient = orient3d( Ba, Bb, Bd, Afar); // needs to be positive
      if( sign( bFaceC_Orient ) < 0.0 )
      {
        two_ThreeFlip = false;
        //If the test fails the check for a 3-2 flip, check for a shared tetrahedron across this face.

        if()

      }
    }

    // Odd face:
    if( !three_TwoFlip )
    {
      // Now we need to ensure that the point lies under the odd face in tetB which isn't the flipping face,
      // but we first need to determine what face that actually is:
      REALTYPE bFaceEven_Orient; // Needs to be negative.

      if( activeFaceIndex == tetraToFace.data[4 * tetB + 1] ) // Face 3: [a,b,c]
      {
        bFaceEven_Orient = orient3d( Ba, Bb, Bc, Afar);
        if( bFaceEven_Orient > 0.0 )
        {
          two_ThreeFlip = false;
          // If the test fails the check for a 3-2 flip, check for a shared tetrahedron across this face.

          //stuff

        }


      } 
      else                                                    // Face 1: [a,c,d]
      {
        bFaceEven_Orient = orient3d( Ba, Bc, Bd, Afar);
        if( bFaceEven_Orient > 0.0 )
        {
          two_ThreeFlip = false;
          // If the test fails the check for a 3-2 flip, check for a shared tetrahedron across this face.

          //stuff

        }


      }
    }
*/

/* old old
void main() // go back to per
{
    uint tetIndex = gl_WorkGroupID.x;

    uint aInd = tetra.data[ 4 * tetIndex + 0 ];
    uint bInd = tetra.data[ 4 * tetIndex + 1 ];
    uint cInd = tetra.data[ 4 * tetIndex + 2 ];
    uint dInd = tetra.data[ 4 * tetIndex + 3 ];

    uint fAInd = tetraToFace.data[ 4 * tetIndex + 0 ];
    uint fBInd = tetraToFace.data[ 4 * tetIndex + 1 ];
    uint fCInd = tetraToFace.data[ 4 * tetIndex + 2 ];
    uint fDInd = tetraToFace.data[ 4 * tetIndex + 3 ];

    // We know the orientation of these edges implicitly, so we can just grab the right tetrahedron.
    uint adjTetA = faceToTetra.data[ 2 * fAInd + 1 ];
    uint adjTetB = faceToTetra.data[ 2 * fAInd + 0 ];
    uint adjTetC = faceToTetra.data[ 2 * fAInd + 1 ];
    uint adjTetD = faceToTetra.data[ 2 * fAInd + 0 ];




    uint tetA = splitFaceToTetra.data[ 2*faceIndex + 0 ];
    uint tetB = splitFaceToTetra.data[ 2*faceIndex + 1 ];

    uint aIndex = splitTetra.data[ 4 * tetA + 0 ];
    uint bIndex = splitTetra.data[ 4 * tetA + 1 ];
    uint cIndex = splitTetra.data[ 4 * tetA + 2 ];
    uint dIndex = splitTetra.data[ 4 * tetA + 3 ];

    uint faIndex = splitFace.data[ 3 * faceIndex + 0 ];
    uint fbIndex = splitFace.data[ 3 * faceIndex + 1 ];
    uint fcIndex = splitFace.data[ 3 * faceIndex + 2 ];

    uint eIndex;
    for(uint i = 0; i < 4; i++)
    {   
        uint dtest = splitTetra.data[ 4 * tetA + i ];
        if( (dtest != faIndex) && (dtest != fbIndex) && (dtest != fcIndex) )
        {
            dIndex = dtest;
        }
    }

    Rvec3 a = Rvec3(gridPoint.data[ 3 * aIndex + 0 ], gridPoint.data[ 3 * aIndex + 1 ], gridPoint.data[ 3 * aIndex + 2 ]);
    Rvec3 b = Rvec3(gridPoint.data[ 3 * bIndex + 0 ], gridPoint.data[ 3 * bIndex + 1 ], gridPoint.data[ 3 * bIndex + 2 ]);
    Rvec3 c = Rvec3(gridPoint.data[ 3 * cIndex + 0 ], gridPoint.data[ 3 * cIndex + 1 ], gridPoint.data[ 3 * cIndex + 2 ]);
    Rvec3 d = Rvec3(gridPoint.data[ 3 * dIndex + 0 ], gridPoint.data[ 3 * dIndex + 1 ], gridPoint.data[ 3 * dIndex + 2 ]);
    Rvec3 e = Rvec3(gridPoint.data[ 3 * eIndex + 0 ], gridPoint.data[ 3 * eIndex + 1 ], gridPoint.data[ 3 * eIndex + 2 ]);

    if( sign( insphere(a, b, c, d, e) ) == 1.0 )
    { // Potentially flippable.
        
    }
    */