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

layout(set = 0, binding = 0, std430) restrict coherent buffer ufActiveFace          {uint activeFace[];       };
layout(set = 0, binding = 1, std430) restrict coherent buffer ufPoints              {REALTYPE points[];       };
layout(set = 0, binding = 2, std430) restrict coherent buffer ufTetra               {uint tetra[];            };
layout(set = 0, binding = 3, std430) restrict coherent buffer ufFaceToTetra         {uint faceToTetra[];      };
layout(set = 0, binding = 4, std430) restrict coherent buffer ufTetraToFace         {uint tetraToFace[];      };
layout(set = 0, binding = 5, std430) restrict coherent buffer ufFlipInfo            {uint flipInfo[];         };
layout(set = 0, binding = 6, std430) restrict coherent buffer ufBadFaces            {uint badFaces[];         };
layout(set = 0, binding = 7, std430) restrict coherent buffer ufNonconvexBadFaces   {uint nonconvexBadFaces[];};
layout(set = 0, binding = 8, std430) restrict coherent buffer ufPredConsts          {REALTYPE predConsts[];   };

// ---- Predicates ----

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

// ---- Functions for readability ----

Rvec3 pointOfIndex( uint n )
{
  return Rvec3( points[ 3 * n + 0 ], points[ 3 * n + 1 ], points[ 3 * n + 2 ] );
}

// ---- Lookup ----

uint _twistA[] = {  2, 3, 1,    // applying the offset, we get (when afar is a), 0 -> {2, 3, 1}, 1 -> {3, 1, 2}, 2 1 -> {1, 2, 3}
                    0, 1, 3 };  //                          or (when afar is c), 0 -> {0, 1, 3}, 1 -> {1, 3, 0}, 2 1 -> {3, 0, 1}
uint _twistB[] = {  0, 2, 3,    // Never has an offset.        (when bfar is b), it's {0, 2, 3}
                    2, 0, 1 };  //                          or (when bfar is d), it's {2, 0, 1}

// ---- Main ----

void main()
{
  uint id = gl_WorkGroupID.x;
  
  // ------------------------------ INDX ------------------------------

  // We iterate over the nonconvex stars amoung the bad faces.
  uint nonconvexBadFace = nonconvexBadFaces[ id ];
  uint nonconvexActiveFace = badFaces[ nonconvexBadFace ];
  uint nonconvexFaceId = activeFace[ nonconvexActiveFace ];

  // Now we get the far vertex of in A for the locally Delauney check, and for the 3-2 test, we also need the far index in B. The shared
  // face could be indexed in each face in any order WRT the face in B, so we construct and edge adjacency list in faceBToFaceA.
  uint AfarInd; Rvec3 Afar; 
  uint BfarInd; Rvec3 Bfar;

  uint twistFaceB[3];
  uint twistFaceA[3];

  // Get the tetrahedra
  uint tetA = faceToTetra[ 2*nonconvexFaceId + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra[ 2*nonconvexFaceId + 1 ]; // The tetra in which we are negatively oriented.
  uint tetC;

  // ------------------------------ INFO ------------------------------

  // Aggregate info, to pass to subsiquent shaders.
  // ----------------------------------------------------------------------------------------------
  // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
  // ----------------------------------------------------------------------------------------------
  // ... | Face 2 Not Convex |   Face 1 Not Convex | Face 0 Not Convex | Face 2 Indeterminant | ...
  // ----------------------------------------------------------------------------------------------
  //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit

  uint info = flipInfo[ nonconvexBadFace ];

  // We're going to reuse the face i indeterminant bits, set we set them to zero:
  info |= (1 << 0) + (1 << 1) + (1 << 2);
  info -= (1 << 0) + (1 << 1) + (1 << 2);

  // The non-convex faces become the faces to check, so the aggregate info now reads
  // ----------------------------------------------------------------------------------------------
  // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
  // ----------------------------------------------------------------------------------------------
  // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
  // ----------------------------------------------------------------------------------------------
  //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit

  // We either flip over the bad face, or around an edge of the bad face. The way that
  // tetrahedron are oriented in relation to each are stored in the following variables.
  uint AfarIsa; uint BfarIsb; uint faceTwist;

  // ------------------------------ Get faceStarInfo ------------------------------

  // Determine faceStarInfo
  AfarIsa   = ( info >> 10 ) & 1;
  BfarIsb   = ( info >>  9 ) & 1;
  faceTwist = ( info >>  7 ) & 3;

  AfarInd = tetra[ 4 * tetA + 0 + 2 * ( 1 - int(AfarIsa) ) ]; // spits out AaInd if Afar Is a, spits out AcInd if Afar is not a ( so that it must be c ).
  BfarInd = tetra[ 4 * tetB + 1 + 2 * ( 1 - int(BfarIsb) ) ]; // spits out BbInd if Bfar Is b, spits out BdInd if Bfar is not b ( so that it must be d ).

  Afar = pointOfIndex( AfarInd );
  Bfar = pointOfIndex( BfarInd );

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
  
  // we check each face in a loop, marking the faces that need a more precise check:
  for(uint i = 0; i < 3; i++){
    if( ( (info >> (i + 3)) & 1 ) == 1 ){ // We expect only one of these to evaluate to true, 
                                          // but there is a small chance two evaluate to true.

      // We check convexity of the face obtained by removing the ith point in B.
      // Rather than grabbing the face directly, we fix the orientation by the twist of the face.
      uint uInBInd = twistFaceB[ uint( mod(i + 1, 3) ) ]; // The initial point of the edge in b
      uint vInBInd = twistFaceB[ uint( mod(i + 2, 3) ) ]; // The final   point of the edge in b

      uint uInd    = tetra[ 4 * tetB + uInBInd];      // We get the actual point indicies.
      uint vInd    = tetra[ 4 * tetB + vInBInd];      //

      Rvec3 u = pointOfIndex( uInd );                 // Then we grab the points.
      Rvec3 v = pointOfIndex( vInd );                 //

      // First get the faces in A and B that share the edge uv.
      uint BFaceInTet = twistFaceB[ i ]; uint BFaceIndex = tetraToFace[ 4 * tetB + BFaceInTet ];
      uint AFaceInTet = twistFaceA[ i ]; uint AFaceIndex = tetraToFace[ 4 * tetA + AFaceInTet ];

      // Reminder:  2*index + 0,  positivly oriented: ccw normal facing outside the tetrahedron.
      //            2*index + 1, negatively oriented: ccw normal facing  inside the tetrahedron.
      //
      //                     '(i + 1) & 1' is shorthand for mod( i + 1, 2)
      uint BOtherInFace = (BFaceInTet + 1) & 1 ;uint BOtherTet = faceToTetra[ 2 * BFaceIndex + BOtherInFace ];
      uint AOtherInFace = (AFaceInTet + 1) & 1 ;uint AOtherTet = faceToTetra[ 2 * AFaceIndex + AOtherInFace ];

      // First we filter out the 3-2 flips options combinatorially.
      if( ( BOtherTet == AOtherTet ) && (BFaceIndex > 3) && (AFaceIndex > 3) ){ // There is a third tetrahedron that makes this a 3 tetra complex. (WE SHOULD BE FAILING THIS CHECK BUT WE"RE NOT!!!)

        // Start encoding this tetrahedron.
        tetC = BOtherTet;
        uint CtestPoints[2]; // [Ca, Cb]
          
        CtestPoints[ 0 ] = tetra[ 4 * tetC + 0 ]; // Ca
        CtestPoints[ 1 ] = tetra[ 4 * tetC + 1 ]; // Cb

        // Two orientation checks to determine the configuration of the complex
        uint isQ = uint( AfarInd == CtestPoints[ 1 - uint( i == 2 ) ] );
        uint isS = uint( BfarInd == CtestPoints[ 0 + uint( i == 2 ) ] );

        info += isQ << 12;
        info += isS << 11;

        uint threeConfig = (i*3 + faceTwist) * 4 + isQ * 2 + isS;
        bool invalidConfig =    ( threeConfig ==  8 )  // Check to be sure it isn't one of the four invalid configs
                             || ( threeConfig == 11 )  // that would break the orientation condition on the complex.
                             || ( threeConfig == 13 )
                             || ( threeConfig == 14 );
        
        if(!invalidConfig){
          // Horray! Only one thing left to check; that the union of the three complex is convex,
          // so that we could make two tetra of non-negative volume.

          // We check this by ensuring that the two points u, v of the middle edge lie on opposite
          // sides of a face drawn by both the far points and remaining point w of the active face.
          // (the three points form a face after a 3-2 flip, with the verticies of the edge the
          // finalizing the two tetrahedra.)

          uint wInB = twistFaceB[ i ]; uint wInd = tetra[ 4 * tetB + wInB ];
          Rvec3 w = pointOfIndex( wInd );
          
          REALTYPE orient_U = orient3d_fast(w, Bfar, Afar, u);
          REALTYPE orient_V = orient3d_fast(w, Bfar, Afar, v);

          if( (orient_U == 0.0) || (orient_V == 0.0) )
          {
            // The check is indeterminant! We need to check again in another kernel with a more memory intensive method.
            info |= (1 << i);
          
          } else {
            if( !( sign( orient_U ) == sign( orient_V ) ) ){
              
              // Sucess! They don't lie on the same side, so we've determined a flip and implicitely encoded it!

            } else { info -= (1 << (3 + i)); }

          }

        } else { info -= (1 << (3 + i)); } 

      } else { info -= (1 << (3 + i)); }

      // Every failing case sets 'Face i can 3-2' over to zero
    }

    // TODO: we can optionally decide not to do any exact check if we have a single valid 3-2 config here.
    //       this might improve performance slightly.

    // Right now we're allowing a 2-3 flip when the the 4 points of a side points lie on a plane.
    // The star will still be convex then, but I don't know if that's optimal.
  }

  flipInfo[ nonconvexBadFace ] = info;
}