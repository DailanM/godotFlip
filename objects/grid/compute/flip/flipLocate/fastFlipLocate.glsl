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
#define INEXACT                          /* Nothing */
/* #define INEXACT volatile */

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding =  0, std430) buffer coherent readonly ufPoints          { REALTYPE point[];       };
layout(set = 0, binding =  1, std430) buffer coherent readonly ufPointsToAdd     { uint pointsToAdd[];     };
layout(set = 0, binding =  2, std430) restrict coherent buffer ufTetOfPoints     { uint tetOfPoints[];     };

layout(set = 0, binding =  3, std430)                   buffer ufPointsInFlip    { uint pointsInFlip[];    };
layout(set = 0, binding =  4, std430) restrict coherent buffer ufTetraMarkedFlip { uint tetraMarkedFlip[]; };
layout(set = 0, binding =  5, std430)                   buffer ufLocations       { uint locations[];       };

layout(set = 0, binding =  6, std430)                   buffer ufTetra           { uint tetra[];           };
layout(set = 0, binding =  7, std430)                   buffer ufFaceToTetra     { uint faceToTetra[];     };

layout(set = 0, binding =  8, std430)                   buffer ufActiveFaces     { uint activeFaces[];     };
layout(set = 0, binding =  9, std430)                   buffer ufFlipInfo        { uint flipInfo[];        };
layout(set = 0, binding = 10, std430)                   buffer ufBadFaces        { uint badFaces[];        };
layout(set = 0, binding = 11, std430)                   buffer ufFlipPrefixSum   { uint flipPrefixSum[];   };

layout(set = 0, binding = 12, std430)                   buffer ufThreeTwoAtFlip  { uint threeTwoAtFlip[];  };

layout(set = 0, binding = 13, std430)                   buffer ufFreedTetra      { uint freedTetra[];      };

layout(set = 0, binding = 14, std430)                   buffer bfPredConsts      { REALTYPE predConsts[];  };
layout(set = 0, binding = 15, std430)                   buffer ufFlipOffsets
{   uint lastTetra; // Not Updated yet for the simplices to be added this flip!
    uint lastFace;
    uint lastEdge;
    uint numFreedTetra;
    uint numFreedFaces;
    uint numFreedEdges;
};

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

// Lookup

// Double checking
// If I write OK then I'm garenteeing that the line is correct.

uint _twistA[] = {  2, 3, 1,    // applying the offset, we get (when afar is a), 0 -> {2, 3, 1}, 1 -> {3, 1, 2}, 2 1 -> {1, 2, 3} OK
                    0, 1, 3 };  //                          or (when afar is c), 0 -> {0, 1, 3}, 1 -> {1, 3, 0}, 2 1 -> {3, 0, 1} OK
uint _twistB[] = {  0, 2, 3,    // Never has an offset.        (when bfar is b), it's {0, 2, 3} OK
                    2, 0, 1 };  //                             (when bfar is d), it's {2, 0, 1} OK

uint _twistEdgeNearB[] = uint[]( 5, 2, 1,   // Never has an offset. (when bfar is b), it's {5, 2, 1} OK
                                 0, 3, 1 ); //                      (when bfar is d), it's {0, 3, 1} OK
uint _twistEdgeFarB[]  = uint[]( 0, 3, 4,   // Never has an offset. (when bfar is b), it's {0, 3, 4} OK
                                 5, 2, 4 ); //                      (when bfar is d), it's {5, 2, 4} OK

uint _twistEdgeFarA[]  = uint[]( 1, 2, 0,   // applying the offset, (when afar is a), 0 -> {1, 2, 0}, 1 -> {2, 0, 1}, 2 1 -> {0, 1, 2}
                                 1, 3, 5 ); //                   or (when afar is c), 0 -> {1, 3, 5}, 1 -> {3, 5, 1}, 2 1 -> {5, 1, 3}

uint _TwoThreeWriteOut[] = {                                                                    // + 55 * faceTwist // indexes writeIn (TODO: remove common assignments between faceTwist)
// ---------------------------------------------------------------------------------------------------------------- //
//       tetU:  0   1   2   3          tetV:  4   5   6   7          tetW:  8   9  10  11               // + 55 * 0 //
               17, 21, 18, 20,               17, 21, 19, 18,               19, 18, 20, 17,                          //
// tetToFaceU: 12  13  14  15    tetToFaceV: 16  17  18  19    tetToFaceW: 20  21  22  23                           //
                5, 23,  2, 24,                6, 22, 24,  3,               23,  4, 22,  7,                          //
// tetToEdgeU: 24  25  26  27  28  29  tetToEdgeV: 30  31  32  33  34  35  tetToEdgeW: 36  37  38  39  40  41       //
               16, 25, 15, 13,  8, 12,             16, 14, 25,  9, 13, 11,             11, 10, 14, 12, 25, 15,      //
// faceV: 42  43  44  faceW: 45  46  47  faceToTetraV: 48  49  faceToTetraW: 50  51  AOldFaceOffsets: 52  53  54    //
          20, 17, 18,        21, 18, 17,                0, 26,                1,  0,                   0,  1,  1,   //
// ---------------------------------------------------------------------------------------------------------------- //
//       tetU:  0   1   2   3          tetV:  4   5   6   7          tetW:  8   9  10  11               // + 55 * 1 //
               17, 20, 21, 18,               17, 21, 19, 18,               18, 17, 20, 19,                          //
// tetToFaceU: 12  13  14  15    tetToFaceV: 16  17  18  19    tetToFaceW: 20  21  22  23                           //
                5, 24, 23,  2,                6, 22, 24,  3,                4,  7, 22, 23,                          //
// tetToEdgeU: 24  25  26  27  28  29  tetToEdgeV: 30  31  32  33  34  35  tetToEdgeW: 36  37  38  39  40  41       //
               15, 16, 25,  8, 12, 13,             16, 14, 25,  9, 13, 11,             25, 12, 11, 15, 14, 10,      //
// faceV: 42  43  44  faceW: 45  46  47  faceToTetraV: 48  49  faceToTetraW: 50  51  AOldFaceOffsets: 52  53  54    //
          20, 18, 17,        21, 18, 17,               26,  0,               1,   0,                   1,  1,  0,   //
// ---------------------------------------------------------------------------------------------------------------- //
//       tetU:  0   1   2   3          tetV:  4   5   6   7          tetW:  8   9  10  11               // + 55 * 2 //
               17, 18, 20, 21,               17, 19, 18, 21,               19, 18, 20, 17,                          //
// tetToFaceU: 12  13  14  15    tetToFaceV: 16  17  18  19    tetToFaceW: 20  21  22  23                           //
                5,  2, 24, 23,                6, 24,  3, 22,               23,  4, 22,  7,                          //
// tetToEdgeU: 24  25  26  27  28  29  tetToEdgeV: 30  31  32  33  34  35  tetToEdgeW: 36  37  38  39  40  41       //
               25, 15, 16, 12, 13,  8,             14, 25, 16, 11,  9, 13,             11, 10, 14, 12, 25, 15,      //
// faceV: 42  43  44  faceW: 45  46  47  faceToTetraV: 48  49  faceToTetraW: 50  51  AOldFaceOffsets: 52  53  54    //
          20, 17, 18,        21, 17, 18,                0, 26,                0,  1,                   1,  0,  1    //
// ---------------------------------------------------------------------------------------------------------------- //
};

uint _ThreeTwoTetUWriteout[] = {                            // + 15 * case-i // indexes ThreeTwoAdapt
// ------------------------------------------------------------------------- //
// tetU: Ufar, 0  1  2     tetToFace: faceIndUV,  3   4   5                  //
               5, 3, 4,                          11,  9, 10,                 //
// tetToEdge:  6   7   8   9  10  11                                         //
              17, 15, 16, 14, 13, 12,                                        //
// faceToTetra offsets: 12  13  14                                           //
                         0,  1,  1,                          // + 15 * 0 (L) // DONE
// ------------------------------------------------------------------------- //
// tetU: Ufar, 0  1  2     tetToFace: faceIndUV,  3   4   5                  //
               3, 4, 5,                           9, 10, 11,                 //
// tetToEdge:  6   7   8   9  10  11                                         //
              15, 16, 17, 12, 14, 13,                                        //
// faceToTetra offsets: 12  13  14                                           //
                         1,  0,  1,                          // + 15 * 1 (M) // DONE
// ------------------------------------------------------------------------- //
// tetU: Ufar, 0  1  2     tetToFace: faceIndUV,  3   4   5                  //
               4, 5, 3,                          10, 11,  9,                 //
// tetToEdge:  6   7   8   9  10  11                                         //
              16, 17, 15, 13, 12, 14,                                        //
// faceToTetra offsets: 12  13  14                                           //
                         1,  1,  0                           // + 15 * 2 (N) // DONE
// ------------------------------------------------------------------------- //
};

uint _ThreeTwoAdapt[] = {                        // num - [threeTwoOver][faceTwist][isQ][isS] // indexes writeIn
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                // 0,
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        // 1, 2, 3, 4, 5,
           20,   21,   19,   18,   17,                                                        //
//     faceXinV, faceYinV, faceZinV, faceXinU, faceYinU, faceZinU,                            // 6, 7, 8, 9, 10, 11
            22,         4,        7,       23,        3,        6,                            //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                // 12, 13, 14, 15, 16, 17, 18, 19, 20
           11,     24,     14,     10,      12,    15,      9,     13,     16,  //  0 - 0000  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        // + 21 * threeConfig
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  //  1 - 0001  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   19,   18,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             22,          4,          7,         23,          3,          6,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           11,     24,     14,     10,     12,     15,      9,     13,     16,  //  2 - 0010  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  //  3 - 0011  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   19,   18,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             22,          4,          7,         23,          3,          6,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           11,     24,     14,     10,      4,     15,      9,     13,     16,  //  4 - 0100  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   20,   19,   17,   18,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             22,          6,          3,         23,          7,          4,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     24,     11,      9,     16,     13,     10,     15,     12,  //  5 - 0101  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   20,   19,   17,   18,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             22,          6,          3,         23,          7,          4,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     24,     11,      9,     16,     13,     10,     15,     12,  //  6 - 0110  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   19,   18,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             22,          4,          7,         23,          3,          6,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           11,     24,     14,     10,     12,     15,      9,     13,     16,  //  7 - 0111  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  //  8 - 0200  // bad
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   17,   19,   18,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              7,         22,          4,          6,         23,          3,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     11,     24,     15,     10,     12,     16,      9,     13,  //  9 - 0201  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   21,   17,   19,   18,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             13,         22,          4,          6,         23,          3,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           14,     11,     24,     15,     10,     12,     16,      9,     13,  // 10 - 0210  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 11 - 0211  // bad
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   18,   20,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              4,         22,          7,          2,         23,          5,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           12,     15,     24,     11,     10,     14,     13,      8,     16,  // 12 - 1000  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 13 - 1001  // bad
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 14 - 1010  // bad
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   18,   20,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              4,         22,          7,          2,         23,          5,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           12,     15,     24,     11,     10,     14,     13,      8,     16,  // 15 - 1011  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   19,   18,   17,   20,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              2,          5,         22,          4,          7,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     15,     12,     13,     16,      8,     11,     14,     10,  // 16 - 1100  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              7,          4,         22,          5,          2,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 17 - 1101  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              7,          4,         22,          5,          2,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 18 - 1110  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            1,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           21,   19,   18,   17,   20,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              2,          5,         22,          4,          7,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     15,     12,     13,     16,      8,     11,     14,     10,  // 19 - 1111  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              7,          4,         22,          5,          2,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 20 - 1200  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 21 - 1201  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   21,   17,   18,   20,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              7,          4,         22,          5,          2,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     12,     15,     14,     11,     10,     16,     13,      8,  // 22 - 1210  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 23 - 1211  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   17,   21,   18,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              6,         23,          3,          5,         22,          2,                  //        "CORRECTED" (wrong for real) (now fixed?)
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           16,     13,     24,     14,      9,     11,     15,      8,     12,  // 24 - 2000  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 25 - 2001  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   17,   21,   18,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              6,         22,          3,          5,         23,          2,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           16,     13,     24,     14,      9,     11,     15,      8,     12,  // 26 - 2010  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 27 - 2011  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   17,   18,   21,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              5,          2,         22,          6,          3,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     13,     16,     15,     12,      8,     14,     11,     23,  // 28 - 2100  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   21,   18,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             22,          3,          6,         23,          2,          5,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     24,     16,      9,     11,     14,      8,     12,     15,  // 29 - 2101  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           19,   20,   21,   18,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             22,          3,          6,         23,          2,          5,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     24,     16,      9,     11,     14,      8,     12,     15,  // 30 - 2110  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            0,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   17,   18,   21,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
             11,          2,         22,          6,          3,         23,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           24,     13,     16,     15,     12,      8,     14,     11,      9,  // 31 - 2111  // DONE
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   18,   21,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              2,         22,          5,          3,         23,          6,                  //
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     16,     24,     12,      8,     15,     11,      9,     14,  // 32 - 2200  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0,  // 33 - 2201  // unused
// ------------------------------------------------------------------------------------------ //
//       case,                                                                                //
            2,                                                                                //
//       Ufar, Vfar,    x,    y,    z,                                                        //
           20,   19,   18,   21,   17,                                                        //
//     faceXinV,   faceYinV,   faceZinV,   faceXinU,   faceYinU,   faceZinU,                  //
              2,         22,          5,          3,         23,          6,                  // "WRONG" (right for real)
//     edgeXY, edgeYZ, edgeZX, edgeXU, edgeYU, edgeZU, edgeXV, edgeYV, edgeZV,                //
           13,     16,     24,     12,      8,     15,     11,      9,     14,  // 34 - 2210  // DONE
// ------------------------------------------------------------------------------------------ //
            0,                                                                                //
            0,    0,    0,    0,    0,                                                        //
            0,        0,        0,        0,        0,        0,                              //
            0,      0,      0,      0,      0,      0,      0,      0,      0   // 35 - 2211  // unused
// ------------------------------------------------------------------------------------------ //
};

uint _ThreeTwoTetCWriteIn[] = {                    // num - [threeTwoOver][faceTwist][isQ][isS] //
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             0,           2,     4,  //  0 - 0000  // DONE
// ----------------------------------------------- //
             0,           0,     0,  //  1 - 0001  // unused
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             2,           0,     4,  //  2 - 0010  // DONE
// ----------------------------------------------- //
             0,           0,     0,  //  3 - 0011  // unused
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           0,     5,  //  4 - 0100  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           2,     2,  //  5 - 0101  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           0,     3,  //  6 - 0110  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           2,     0,  //  7 - 0111  // DONE
// ----------------------------------------------- //
             0,           0,     0,  //  8 - 0200  // bad
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             2,           1,     2,  //  9 - 0201  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             0,           3,     3,  // 10 - 0210  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 11 - 0211  // bad
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             0,           1,     5,  // 12 - 1000  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 13 - 1001  // bad
// ----------------------------------------------- //
             0,           0,     0,  // 14 - 1010  // bad
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             2,           3,     0,  // 15 - 1011  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           0,     5,  // 16 - 1100  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           2,     2,  // 17 - 1101  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           0,     3,  // 18 - 1110  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           2,     0,  // 19 - 1111  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             2,           0,     4,  // 20 - 1200  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 21 - 1201  // unused
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             0,           2,     4,  // 22 - 1210  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 23 - 1211  // unused
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           3,     1,  // 24 - 2000  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 25 - 2001  // unused
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           1,     1,  // 26 - 2010  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 27 - 2011  // unused
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           0,     5,  // 28 - 2100  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           0,     3,  // 29 - 2101  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           2,     2,  // 30 - 2110  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           2,     0,  // 31 - 2111  // DONE
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             3,           1,     1,  // 32 - 2200  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 33 - 2201  // unused
// ----------------------------------------------- //
// faceUfarInC, faceVfarInC, edgeC,                //
             1,           3,     1,  // 34 - 2210  // DONE
// ----------------------------------------------- //
             0,           0,     0,  // 35 - 2211  // unused
// ----------------------------------------------- //
};


#define pointOfInd( Ind ) Rvec3(point[ 3 * Ind + 0 ], point[ 3 * Ind + 1 ], point[ 3 * Ind + 2 ] )

void main() {
    uint id = gl_WorkGroupID.x;

    uint pointInFlip = pointsInFlip[ id ];
    uint tetOfPoint  = tetOfPoints[  pointInFlip ];
    uint badFaceOfFlip = tetraMarkedFlip[ tetOfPoint ] - 1;
    uint flipID = flipPrefixSum[ badFaceOfFlip ] - 1;

    uint flippingFaceInActiveFace = badFaces[ badFaceOfFlip ];
    uint flippingFace = activeFaces[ flippingFaceInActiveFace ];

    uint pointIndex  = pointsToAdd[ pointInFlip ];
    Rvec3 pTest = pointOfInd( pointIndex );

    // The non-convex faces became the faces to check, so the aggregate info now reads
    // ----------------------------------------------------------------------------------------------
    // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
    // ----------------------------------------------------------------------------------------------
    // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
    // ----------------------------------------------------------------------------------------------
    //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit
    uint info = flipInfo[ badFaceOfFlip ];
    uint located = 0; // marks indeterminant faces if we don't locate a point.

    uint writeIn[27];

    uint threeTwoFlipsAtFlip = threeTwoAtFlip[ flipID ];
    
    uint tetA; uint tetB;

    uint AfarInd; uint BfarInd;
    uint uInd; uint vInd; uint wInd;

    uint AfarIsa; uint BfarIsb; uint faceTwist;

    uint twistFaceB[3]; // uint twistEdgeNearB[3]; uint twistEdgeFarB[3];
    // uint twistFaceA[3]; /* uint twistEdgeNearA[3]; */ uint twistEdgeFarA[3];

    // -------- Grab data --------
    AfarIsa   = ( info >> 10 ) & 1;
    BfarIsb   = ( info >>  9 ) & 1;
    faceTwist = ( info >>  7 ) & 3;

    // twistFaceA and twistFaceB are connected via the shared face between tetA and tetB.
    // It will help to think of the array as cyclic, which explains the all of the mod(X, 3) when applying offsets.
    twistFaceB[0] = _twistB[ 3 * (1 - BfarIsb) + 0 ];
    twistFaceB[1] = _twistB[ 3 * (1 - BfarIsb) + 1 ];
    twistFaceB[2] = _twistB[ 3 * (1 - BfarIsb) + 2 ];

    // -------- 2 Tetra --------
    tetA = faceToTetra[ 2*flippingFace + 0 ]; // The tetra in which we are positively oriented.
    tetB = faceToTetra[ 2*flippingFace + 1 ]; // The tetra in which we are negatively oriented.

    // -------- 5 Points --------
    AfarInd = tetra[ 4 * tetA + 0 + 2 * ( 1 - int(AfarIsa) ) ]; // spits out the a index of tetA if Afar Is a, spits out the c index of tetA if Afar is not a (since it must be c).
    BfarInd = tetra[ 4 * tetB + 1 + 2 * ( 1 - int(BfarIsb) ) ]; // spits out the b index of tetB if Bfar Is b, spits out the d index of tetB if Bfar is not b (since it must be d).

    uInd = tetra[ 4 * tetB + twistFaceB[0] ];
    vInd = tetra[ 4 * tetB + twistFaceB[1] ];
    wInd = tetra[ 4 * tetB + twistFaceB[2] ];

    writeIn = uint[](
    // Reserved for any Flip
    // tetU, tetV,                           //  0,  1
        0, 0,

        0, 0, 0, 0, 0, 0,
    //    faceAU, faceAV, faceAW,              //  2,  3,  4,
    //    faceBU, faceBV, faceBW,              //  5,  6,  7,
                                             //
        0, 0, 0, 0, 0, 0, 0, 0, 0,
    //    edgeNearU, edgeNearV, edgeNearW,     //  8,  9, 10,
    //    edgeFarBU, edgeFarBV, edgeFarBW,     // 11, 12, 13,
    //    edgeFarAU, edgeFarAV, edgeFarAW,     // 14, 15, 16,
                                             //
        AfarInd, BfarInd, uInd, vInd, wInd,                 // 17, 18, 19, 20, 21

    // Reserved for Two-Three Flips
    // faceU, faceV, faceW, edgeAB, tetw           // 22, 23, 24, 25, 26
        
    // Reserved for Three-Two Flips
    // faceUfarInC, faceVfarInC, edgeC // 22, 23, 24 rename faceCU faceCV

    0, 0, 0, 0, 0// 
    
    );


    bool isThreeTwo   = ( ((info >> 5 ) & 1) == 1 ) || ( ((info >> 4 ) & 1) == 1 ) || ( ((info >> 3 ) & 1) == 1 ); // only one of these evaluate to true.
    
    if( !isThreeTwo ){  // ------------------------ Is Two Three ------------------------ //

        uint tetU; uint tetV; uint tetW;

        uint TwoThreeID = flipID - threeTwoFlipsAtFlip; //represents the number of threeTwoFlips left at this flip

        tetU = tetA; tetV = tetB;
        if( 1 * TwoThreeID     < numFreedTetra ) { tetW   = freedTetra[ (numFreedTetra - 1) - (1 * TwoThreeID + 0) ] ; } // Pull freed simplices off the end
        else                                     { tetW   = (lastTetra + 1) + ( (1 * TwoThreeID + 0) - numFreedTetra); }

        // check orientation across each new face.
        REALTYPE orFaceU = orient3d_fast( pointOfInd(uInd), pointOfInd(BfarInd), pointOfInd(AfarInd), pTest );

        REALTYPE orFaceV = orient3d_fast(   pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 42 ] ] ),
                                            pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 43 ] ] ),
                                            pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 44 ] ] ),
                                            pTest );

        // encode.
        located += ( int(sign( orFaceU )) + 1 ) * ( uint(pow(3,0)) );
        located += ( int(sign( orFaceV )) + 1 ) * ( uint(pow(3,1)) );
        
        if(
            ( (faceTwist == 2) && ( orFaceU > 0 ) && (orFaceV > 0) ) ||
            ( (faceTwist == 1) && ( orFaceU > 0 ) && (orFaceV < 0) ) ||
            ( (faceTwist == 0) && ( orFaceU > 0 ) && (orFaceV > 0) )    )
        {
            // We lie in tetW!
            tetOfPoints[ pointInFlip ] = tetW;
            located = (located << 1) + 0;

        } else  {

            REALTYPE orFaceW = orient3d_fast(   pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 45 ] ] ),
                                            pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 46 ] ] ),
                                            pointOfInd( writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 47 ] ] ),
                                            pTest );

            // encode.
            located += ( int(sign( orFaceW )) + 1 ) * ( uint(pow(3,2)) );

            if(
                ( (faceTwist == 2) && ( orFaceU < 0 ) && (orFaceW < 0) ) ||
                ( (faceTwist == 1) && ( orFaceU < 0 ) && (orFaceW > 0) ) ||
                ( (faceTwist == 0) && ( orFaceU < 0 ) && (orFaceW > 0) )    )
            {
                // We lie in tetV!
                tetOfPoints[ pointInFlip ] = tetV;
                located = (located << 1) + 0;

            } else if(
                ( (faceTwist == 2) && ( orFaceV < 0 ) && (orFaceW > 0) ) ||
                ( (faceTwist == 1) && ( orFaceV > 0 ) && (orFaceW < 0) ) ||
                ( (faceTwist == 0) && ( orFaceV < 0 ) && (orFaceW < 0) )    )
            {
                // We lie in tetU!
                tetOfPoints[ pointInFlip ] = tetU;
                located = (located << 1) + 0;

            } else {
                // we fail!
                located = (located << 1) + 1;
            }
        }

        locations[ id ] = located;

    } else {            // ------------------------ Is Three Two ------------------------ //

        uint tetU; uint tetV;
        tetU = tetA; tetV = tetB;

        uint ThreeTwoOver = ( ((info >> 5 ) & 1)  * 2 )  + ( ((info >> 4 ) & 1)  * 1 )  + ( ((info >> 3 ) & 1)  * 0 );
        uint isQ = ( info >> 12 ) & 1;
        uint isS = ( info >> 11 ) & 1;
        uint threeConfig = (ThreeTwoOver * 3 + faceTwist) * 4 + isQ * 2 + isS;

        uint xInd = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   3 ] ];
        uint yInd = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   4 ] ];
        uint zInd = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   5 ] ];

        // check orientation across xyz face

        REALTYPE orFaceUV = orient3d_fast( pointOfInd(xInd), pointOfInd(yInd), pointOfInd(zInd), pTest );

        if( orFaceUV < 0 ){
            tetOfPoints[ pointInFlip ] =  tetU;
        } else if( orFaceUV > 0) {
            tetOfPoints[ pointInFlip ] = tetV;
        } else {
            located = 1;
        }

        locations[ id ] = located;
        
    }
}
