#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// ufTetra, ufTetraToFace, ufTetraToEdge, ufFace, ufFaceToTetra, ufEdge, ufActiveFaces, ufFlipInfo, ufBadFaces, ufBadFacesToFlip, ufThreeTwoBeforeFlip, ufFreedTetra, ufFreedFaces, ufFreedEdges, ufFlipOffsets

layout(set = 0, binding =  0, std430) buffer ufTetra                 {uint tetra[];              };
layout(set = 0, binding =  1, std430) buffer ufTetraToFace           {uint tetraToFace[];        };
layout(set = 0, binding =  2, std430) buffer ufTetraToEdge           {uint tetraToEdge[];        };
layout(set = 0, binding =  3, std430) buffer ufFace                  {uint face[];               };
layout(set = 0, binding =  4, std430) buffer ufFaceToTetra           {uint faceToTetra[];        };
layout(set = 0, binding =  5, std430) buffer ufEdge                  {uint edge[];               };

layout(set = 0, binding =  6, std430) buffer ufActiveFaces           {uint activeFaces[];        };
layout(set = 0, binding =  7, std430) buffer ufFlipInfo              {uint flipInfo[];           };
layout(set = 0, binding =  8, std430) buffer ufBadFaces              {uint badFaces[];           };
layout(set = 0, binding =  9, std430) buffer ufBadFacesToFlip        {uint badFacesToFlip[];     };
layout(set = 0, binding = 10, std430) buffer ufThreeTwoAtFlip        {uint threeTwoAtFlip[];     };

layout(set = 0, binding = 11, std430) buffer ufFreedTetra            {uint freedTetra[];         };
layout(set = 0, binding = 12, std430) buffer ufFreedFaces            {uint freedFaces[];         };
layout(set = 0, binding = 13, std430) buffer ufFreedEdges            {uint freedEdges[];         };

layout(set = 0, binding = 14, std430) buffer ufNewActiveFaces    {uint newActiveFaces[]; };

layout(set = 0, binding = 15, std430) buffer ufFlipOffsets
{   uint lastTetra; // Not Updated yet for the simplices to be added this flip!
    uint lastFace;
    uint lastEdge;
    uint numFreedTetra;
    uint numFreedFaces;
    uint numFreedEdges;
};

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

void main() {
    uint id = gl_WorkGroupID.x;

    uint flippingBadFace    = badFacesToFlip[ id ];
    uint flippingActiveFace = badFaces[ flippingBadFace ];

    

    // The non-convex faces became the faces to check, so the aggregate info now reads
    // ----------------------------------------------------------------------------------------------
    // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
    // ----------------------------------------------------------------------------------------------
    // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
    // ----------------------------------------------------------------------------------------------
    //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit

    uint info               = flipInfo[ flippingBadFace ];
    uint flippingFace       = activeFaces[ flippingActiveFace ];

    // Old tetra
    uint tetA; uint tetB;

    // Old Faces
    uint faceAU; uint faceBU;
    uint faceAV; uint faceBV;
    uint faceAW; uint faceBW;

    // Old Edges
    uint edgeNearU; uint edgeFarBU; uint edgeFarAU;
    uint edgeNearV; uint edgeFarBV; uint edgeFarAV;
    uint edgeNearW; uint edgeFarBW; uint edgeFarAW;

    // Old Points

    uint Afar; uint Bfar;
    uint u; uint v; uint w;

    uint AfarIsa; uint BfarIsb; uint faceTwist;

    uint twistFaceB[3]; uint twistEdgeNearB[3]; uint twistEdgeFarB[3];
    uint twistFaceA[3]; /* uint twistEdgeNearA[3]; */ uint twistEdgeFarA[3];
    
    bool isThreeTwo; uint ThreeTwoOver; uint isOfQ; uint isOfS;

    uint writeIn[27];

    // indexing

    uint threeTwoFlipsAtFlip = threeTwoAtFlip[ id ];
 
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
    
    twistEdgeFarB[0] = _twistEdgeFarB[ 3 * (1 - BfarIsb) + 0 ];
    twistEdgeFarB[1] = _twistEdgeFarB[ 3 * (1 - BfarIsb) + 1 ];
    twistEdgeFarB[2] = _twistEdgeFarB[ 3 * (1 - BfarIsb) + 2 ];

    twistFaceA[0] = _twistA[ 3 * (1 - AfarIsa) +            faceTwist + 0        ];
    twistFaceA[1] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 1, 3 ) ) ];
    twistFaceA[2] = _twistA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 2, 3 ) ) ];

    twistEdgeFarA[0] = _twistEdgeFarA[ 3 * (1 - AfarIsa) +            faceTwist + 0        ];
    twistEdgeFarA[1] = _twistEdgeFarA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 1, 3 ) ) ];
    twistEdgeFarA[2] = _twistEdgeFarA[ 3 * (1 - AfarIsa) + uint( mod( faceTwist + 2, 3 ) ) ];

    // -------- 2 Tetra --------
    tetA = faceToTetra[ 2*flippingFace + 0 ]; // The tetra in which we are positively oriented.
    tetB = faceToTetra[ 2*flippingFace + 1 ]; // The tetra in which we are negatively oriented.

    // -------- 6 Faces --------

    // flippingFace gets deleted always

    faceAU = tetraToFace[ 4*tetA + twistFaceA[0] ]; faceBU = tetraToFace[ 4*tetB + twistFaceB[0] ];
    faceAV = tetraToFace[ 4*tetA + twistFaceA[1] ]; faceBV = tetraToFace[ 4*tetB + twistFaceB[1] ];
    faceAW = tetraToFace[ 4*tetA + twistFaceA[2] ]; faceBW = tetraToFace[ 4*tetB + twistFaceB[2] ];

    // -------- 9 Edges --------

    edgeNearU = tetraToEdge[ 6 * tetB + twistEdgeNearB[0] ];
    edgeNearV = tetraToEdge[ 6 * tetB + twistEdgeNearB[1] ];
    edgeNearW = tetraToEdge[ 6 * tetB + twistEdgeNearB[2] ];

    edgeFarBU = tetraToEdge[ 6 * tetB +  twistEdgeFarB[0] ];
    edgeFarBV = tetraToEdge[ 6 * tetB +  twistEdgeFarB[1] ];
    edgeFarBW = tetraToEdge[ 6 * tetB +  twistEdgeFarB[2] ];

    edgeFarAU = tetraToEdge[ 6 * tetA +  twistEdgeFarA[0] ];
    edgeFarAV = tetraToEdge[ 6 * tetA +  twistEdgeFarA[1] ];
    edgeFarAW = tetraToEdge[ 6 * tetA +  twistEdgeFarA[2] ];

    // -------- 5 Points --------
    Afar = tetra[ 4 * tetA + 0 + 2 * ( 1 - int(AfarIsa) ) ]; // spits out the a index of tetA if Afar Is a, spits out the c index of tetA if Afar is not a (since it must be c).
    Bfar = tetra[ 4 * tetB + 1 + 2 * ( 1 - int(BfarIsb) ) ]; // spits out the b index of tetB if Bfar Is b, spits out the d index of tetB if Bfar is not b (since it must be d).

    u = tetra[ 4 * tetB + twistFaceB[0] ];
    v = tetra[ 4 * tetB + twistFaceB[1] ];
    w = tetra[ 4 * tetB + twistFaceB[2] ];

    // -------- Pack into lookup table --------

    writeIn = uint[](
    // Reserved for any Flip
    // tetU, tetV,                           //  0,  1
        0, 0,

        faceAU, faceAV, faceAW,              //  2,  3,  4, OK
        faceBU, faceBV, faceBW,              //  5,  6,  7, OK
                                             //
        edgeNearU, edgeNearV, edgeNearW,     //  8,  9, 10, OK
        edgeFarBU, edgeFarBV, edgeFarBW,     // 11, 12, 13, OK
        edgeFarAU, edgeFarAV, edgeFarAW,     // 14, 15, 16, OK
                                             //
        Afar, Bfar, u, v, w,                 // 17, 18, 19, 20, 21

    // Reserved for Two-Three Flips
    // faceU, faceV, faceW, edgeAB, tetw     // 22, 23, 24, 25, 26
        
    // Reserved for Three-Two Flips          // OR
    // faceUfarInC, faceVfarInC, edgeC       // 22, 23, 24 rename faceCU faceCV

    0, 0, 0, 0, 0// 
    
    );

    // -------- Two-Three or Three-Two --------
    
    isThreeTwo   = ( ((info >> 5 ) & 1) == 1 ) || ( ((info >> 4 ) & 1) == 1 ) || ( ((info >> 3 ) & 1) == 1 ); // only one of these evaluate to true.
    
    if( !isThreeTwo ){  // ------------------------ Is Two Three ------------------------ // ~~~DONE!!!
                        // Delete 2 tetra and 1 face. Create 3 tetra, 3 faces, and 1 edge

        uint TwoThreeID = id - threeTwoFlipsAtFlip; //represents the number of threeTwoFlips left.

        // New simplices:
        uint tetU; uint tetV; uint tetW;    // The tetra away from u,v,w respectivly
        uint faceU; uint faceV; uint faceW; // The faces connected to u,v,w respectivly
        uint edgeAB;                        // The new edge connecting Afar and Bfar

        // Index
        tetU = tetA; tetV = tetB;
        if( 1 * TwoThreeID     < numFreedTetra ) { tetW   = freedTetra[ (numFreedTetra - 1) - (1 * TwoThreeID + 0) ] ; } // Pull freed simplices off the end
        else                                     { tetW   = (lastTetra + 1) + ( (1 * TwoThreeID + 0) - numFreedTetra); }

        faceU = flippingFace;
        if( 2 * TwoThreeID + 0 < numFreedFaces ) { faceV  = freedFaces[ (numFreedFaces - 1) - (2 * TwoThreeID + 0) ] ; }
        else                                     { faceV  = (lastFace  + 1) + ( (2 * TwoThreeID + 0) - numFreedFaces); }
        if( 2 * TwoThreeID + 1 < numFreedFaces ) { faceW  = freedFaces[ (numFreedFaces - 1) - (2 * TwoThreeID + 1) ] ; }
        else                                     { faceW  = (lastFace  + 1) + ( (2 * TwoThreeID + 1) - numFreedFaces); }

        if( 1 * TwoThreeID     < numFreedEdges ) { edgeAB = freedEdges[ (numFreedEdges - 1) - (1 * TwoThreeID + 0) ] ; }
        else                                     { edgeAB = (lastEdge  + 1) + ( (1 * TwoThreeID + 0) - numFreedEdges); }

        // -------- Pack into lookup table --------

        writeIn[0] = tetU; writeIn[1] = tetV; writeIn[26] = tetW;
        writeIn[22] = faceU; writeIn[23] = faceV; writeIn[24] = faceW;
        writeIn[25] = edgeAB;

        // ---------------------------------------------------- TETRAHEDRON Data:  ----------------------------------------------------
        // First write out the tetra in terms of Afar, Bfar, u, v, and w;
        tetra[ 4 * tetU + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  0 ] ];
        tetra[ 4 * tetU + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  1 ] ];
        tetra[ 4 * tetU + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  2 ] ];
        tetra[ 4 * tetU + 3 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  3 ] ];

        tetra[ 4 * tetV + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  4 ] ];
        tetra[ 4 * tetV + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  5 ] ];
        tetra[ 4 * tetV + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  6 ] ];
        tetra[ 4 * tetV + 3 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  7 ] ];

        tetra[ 4 * tetW + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  8 ] ];
        tetra[ 4 * tetW + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist +  9 ] ];
        tetra[ 4 * tetW + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 10 ] ];
        tetra[ 4 * tetW + 3 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 11 ] ];

        // write new tetToFace;
        tetraToFace[ 4 * tetU + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 12 ] ];
        tetraToFace[ 4 * tetU + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 13 ] ];
        tetraToFace[ 4 * tetU + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 14 ] ];
        tetraToFace[ 4 * tetU + 3 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 15 ] ];

        tetraToFace[ 4 * tetV + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 16 ] ];
        tetraToFace[ 4 * tetV + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 17 ] ];
        tetraToFace[ 4 * tetV + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 18 ] ];
        tetraToFace[ 4 * tetV + 3 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 19 ] ];

        tetraToFace[ 4 * tetW + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 20 ] ];
        tetraToFace[ 4 * tetW + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 21 ] ];
        tetraToFace[ 4 * tetW + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 22 ] ];
        tetraToFace[ 4 * tetW + 3 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 23 ] ];

        // and finally write out new tetraToEdge.
        tetraToEdge[ 6*tetU + 0] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 24 ] ];
        tetraToEdge[ 6*tetU + 1] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 25 ] ];
        tetraToEdge[ 6*tetU + 2] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 26 ] ];
        tetraToEdge[ 6*tetU + 3] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 27 ] ];
        tetraToEdge[ 6*tetU + 4] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 28 ] ];
        tetraToEdge[ 6*tetU + 5] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 29 ] ];

        tetraToEdge[ 6*tetV + 0] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 30 ] ];
        tetraToEdge[ 6*tetV + 1] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 31 ] ];
        tetraToEdge[ 6*tetV + 2] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 32 ] ];
        tetraToEdge[ 6*tetV + 3] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 33 ] ];
        tetraToEdge[ 6*tetV + 4] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 34 ] ];
        tetraToEdge[ 6*tetV + 5] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 35 ] ];

        tetraToEdge[ 6*tetW + 0] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 36 ] ];
        tetraToEdge[ 6*tetW + 1] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 37 ] ];
        tetraToEdge[ 6*tetW + 2] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 38 ] ];
        tetraToEdge[ 6*tetW + 3] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 39 ] ];
        tetraToEdge[ 6*tetW + 4] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 40 ] ];
        tetraToEdge[ 6*tetW + 5] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 41 ] ];

        // ----------------------------------------- FACE DATA: ----------------------------------------
        // For faceToTetra: 2*index + 0,  positivly oriented: ccw normal facing outside the tetrahedron.
        //                  2*index + 1, negatively oriented: ccw normal facing  inside the tetrahedron.

        // Write out new faces;
        face[ 3 * faceU + 0 ] = u;
        face[ 3 * faceU + 1 ] = Bfar;
        face[ 3 * faceU + 2 ] = Afar;

        face[ 3 * faceV + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 42 ] ];
        face[ 3 * faceV + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 43 ] ];
        face[ 3 * faceV + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 44 ] ];

        face[ 3 * faceW + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 45 ] ];
        face[ 3 * faceW + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 46 ] ];
        face[ 3 * faceW + 2 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 47 ] ];

        // write new faceToTetra;
        faceToTetra[ 2 * faceU + 0 ] = tetW; faceToTetra[ 2 * faceU + 1 ] = tetV;

        faceToTetra[ 2 * faceV + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 48 ] ];
        faceToTetra[ 2 * faceV + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 49 ] ];

        faceToTetra[ 2 * faceW + 0 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 50 ] ];
        faceToTetra[ 2 * faceW + 1 ] = writeIn[ _TwoThreeWriteOut[ 55 * faceTwist + 51 ] ];

        // update old faceToTetra;
        faceToTetra[ 2 * faceAU + _TwoThreeWriteOut[ 55 * faceTwist + 52 ] ] = tetU; faceToTetra[ 2 * faceBU + 0 ] = tetU;
        faceToTetra[ 2 * faceAV + _TwoThreeWriteOut[ 55 * faceTwist + 53 ] ] = tetV; faceToTetra[ 2 * faceBV + 0 ] = tetV;
        faceToTetra[ 2 * faceAW + _TwoThreeWriteOut[ 55 * faceTwist + 54 ] ] = tetW; faceToTetra[ 2 * faceBW + 1 ] = tetW;

        // ------------------------------------------------ EDGES, TETRA TO EDGES: -----------------------------------------------

        // write new edge;
        edge[ 2 * edgeAB + 0 ] = Afar; edge[ 2 * edgeAB + 1 ] = Bfar;

        // ------------------------------------------------ update activeFaces: -----------------------------------------------
        
        if( ( faceAU > 3 ) && ( newActiveFaces[faceAU] == 0 ) ){ atomicMax( newActiveFaces[faceAU], 1 ); }
        if( ( faceAV > 3 ) && ( newActiveFaces[faceAV] == 0 ) ){ atomicMax( newActiveFaces[faceAV], 1 ); }
        if( ( faceAW > 3 ) && ( newActiveFaces[faceAW] == 0 ) ){ atomicMax( newActiveFaces[faceAW], 1 ); }
        if( ( faceBU > 3 ) && ( newActiveFaces[faceBU] == 0 ) ){ atomicMax( newActiveFaces[faceBU], 1 ); }
        if( ( faceBV > 3 ) && ( newActiveFaces[faceBV] == 0 ) ){ atomicMax( newActiveFaces[faceBV], 1 ); }
        if( ( faceBW > 3 ) && ( newActiveFaces[faceBW] == 0 ) ){ atomicMax( newActiveFaces[faceBW], 1 ); }
        
    
    } else {            // ------------------------ Is Three Two ------------------------ //
                        // Delete 3 tetra, 3 faces, and 1 edge. Make 2 tetra and 1 face. Free 1 Tetra, 2 Faces, and 1 Edge.

        // Extra Needed Flip Data
        ThreeTwoOver = ( ((info >> 5 ) & 1)  * 2 )  + ( ((info >> 4 ) & 1)  * 1 )  + ( ((info >> 3 ) & 1)  * 0 );
        uint isQ = ( info >> 12 ) & 1;
        uint isS = ( info >> 11 ) & 1;
        uint threeConfig = (ThreeTwoOver * 3 + faceTwist) * 4 + isQ * 2 + isS;
        uint flipCase = _ThreeTwoAdapt[ 21 * threeConfig + 0 ];

        // Extra Data Needed
        // uint ABCEdge = tetraToEdge[ 6 * tetB + twistEdgeNearB[ ThreeTwoOver ] ];
        // uint ACFaceInTet = twistFaceA[ ThreeTwoOver ]; uint ACFace = tetraToFace[ 4 * tetB + ACFaceInTet ]; // The face between A and C
        uint BCFaceInTet = twistFaceB[ ThreeTwoOver ]; uint BCFace = tetraToFace[ 4 * tetB + BCFaceInTet ]; // The face between B and C

        uint BOtherInFace = (ThreeTwoOver + 1) & 1;
        uint tetC = faceToTetra[ 2 * BCFace + BOtherInFace ];

        uint faceUfarInC = tetraToFace[ 4 * tetC + _ThreeTwoTetCWriteIn[ 3 * threeConfig + 0 ] ];
        uint faceVfarInC = tetraToFace[ 4 * tetC + _ThreeTwoTetCWriteIn[ 3 * threeConfig + 1 ] ];

        uint edgeC = tetraToEdge[ 6 * tetC + _ThreeTwoTetCWriteIn[ 3 * threeConfig + 2 ]];

        // Adapt
        uint Ufar =     writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   1 ] ];
        uint Vfar =     writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   2 ] ];
        uint x =        writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   3 ] ];
        uint y =        writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   4 ] ];
        uint z =        writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   5 ] ];

        uint faceXinV = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   6 ] ]; // faceXinV means the face of the triple complex without either X or V. I fucked up my naming convension and confused myself.
        uint faceYinV = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   7 ] ];
        uint faceZinV = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   8 ] ];
        uint faceXinU = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +   9 ] ];
        uint faceYinU = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  10 ] ];
        uint faceZinU = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  11 ] ];

        uint edgeXY =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  12 ] ];
        uint edgeYZ =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  13 ] ];
        uint edgeZX =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  14 ] ];
        uint edgeXU =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  15 ] ];
        uint edgeYU =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  16 ] ];
        uint edgeZU =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  17 ] ];
        uint edgeXV =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  18 ] ];
        uint edgeYV =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  19 ] ];
        uint edgeZV =   writeIn[ _ThreeTwoAdapt[ 21 * threeConfig +  20 ] ];



        // New simplicies to write out
        uint tetU = tetA;   uint tetV = tetB;
        uint faceUV = flippingFace;

        // Pack data into lookup table
        writeIn[0] = tetU; writeIn[1] = tetV;
        writeIn[22] = faceUfarInC; writeIn[23] = faceVfarInC;
        writeIn[24] = edgeC;

        // ---------------------------------------------------- TETRAHEDRON:  ----------------------------------------------------
        // First write out the tetra in terms of Ufar, Vfar, x, y, and z.
        tetra[ 4 * tetU + 0 ] = Ufar; //
        tetra[ 4 * tetU + 1 ] =       writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  0 ] ] ];
        tetra[ 4 * tetU + 2 ] =       writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  1 ] ] ];
        tetra[ 4 * tetU + 3 ] =       writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  2 ] ] ];

        tetra[ 4 * tetV + 0 ] =    x; //
        tetra[ 4 * tetV + 1 ] =    y; //
        tetra[ 4 * tetV + 2 ] =    z; //
        tetra[ 4 * tetV + 3 ] = Vfar; //

        tetraToFace[ 4 * tetU + 0 ] = faceUV; //
        tetraToFace[ 4 * tetU + 1 ] = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  3 ] - 3 ] ];  // subtracting 3 is a hacky way of correcting my error in the table
        tetraToFace[ 4 * tetU + 2 ] = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  4 ] - 3 ] ];
        tetraToFace[ 4 * tetU + 3 ] = writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  5 ] - 3 ] ];

        tetraToFace[ 4 * tetV + 0 ] = faceXinU; // corrected?
        tetraToFace[ 4 * tetV + 1 ] = faceYinU; //
        tetraToFace[ 4 * tetV + 2 ] = faceZinU; //
        tetraToFace[ 4 * tetV + 3 ] = faceUV; //

        tetraToEdge[ 6*tetU + 0] =    writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  6 ] ] ];
        tetraToEdge[ 6*tetU + 1] =    writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  7 ] ] ];
        tetraToEdge[ 6*tetU + 2] =    writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  8 ] ] ];
        tetraToEdge[ 6*tetU + 3] =    writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase +  9 ] ] ];
        tetraToEdge[ 6*tetU + 4] =    writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase + 10 ] ] ];
        tetraToEdge[ 6*tetU + 5] =    writeIn[ _ThreeTwoAdapt[ 21 * threeConfig + _ThreeTwoTetUWriteout[ 15 * flipCase + 11 ] ] ];

        tetraToEdge[ 6*tetV + 0] = edgeXY; tetraToEdge[ 6*tetV + 1] = edgeZX; //
        tetraToEdge[ 6*tetV + 2] = edgeXV; tetraToEdge[ 6*tetV + 3] = edgeYZ; //
        tetraToEdge[ 6*tetV + 4] = edgeYV; tetraToEdge[ 6*tetV + 5] = edgeZV; //

        // ----------------------------------------- FACES, FACE TO TETRA, TETRA TO FACE: ----------------------------------------
        // For faceToTetra: 2*index + 0,  positivly oriented: ccw normal facing outside the tetrahedron.
        //                  2*index + 1, negatively oriented: ccw normal facing  inside the tetrahedron.
                    
        // New face
        face[ 3 * faceUV + 0 ] = x; //
        face[ 3 * faceUV + 1 ] = y; //
        face[ 3 * faceUV + 2 ] = z; //

        // Old faces (we got them above.)
        // uint faceUfarOfX; uint faceUfarOfY; uint faceUfarOfZ;
        // uint faceVfarOfX; uint faceVfarOfY; uint faceVfarOfZ;

        // new faceToTetra
        faceToTetra[ 2 * faceUV + 0 ] = tetU; faceToTetra[ 2 * faceUV + 1 ] = tetV; //

        // old faceToTetra update // I FLIPPED THESE TO SEE IF IT"D FIX THE ISSUE
        faceToTetra[ 2 * faceXinU + 0 ] = tetV; faceToTetra[ 2 * faceXinV + _ThreeTwoTetUWriteout[ 15 * flipCase + 12] ] = tetU; // left universal, right needs work
        faceToTetra[ 2 * faceYinU + 1 ] = tetV; faceToTetra[ 2 * faceYinV + _ThreeTwoTetUWriteout[ 15 * flipCase + 13] ] = tetU;
        faceToTetra[ 2 * faceZinU + 0 ] = tetV; faceToTetra[ 2 * faceZinV + _ThreeTwoTetUWriteout[ 15 * flipCase + 14] ] = tetU;

        // ------------------------------------------------ EDGES, TETRA TO EDGES: -----------------------------------------------
        // new edges: none

        // ------------------------------------------------ update activeFaces: -----------------------------------------------
        
        if( ( faceXinV > 3 ) && ( newActiveFaces[faceXinV] == 0 ) ){ atomicMax( newActiveFaces[faceXinV], 1 ); }
        if( ( faceYinV > 3 ) && ( newActiveFaces[faceYinV] == 0 ) ){ atomicMax( newActiveFaces[faceYinV], 1 ); }
        if( ( faceZinV > 3 ) && ( newActiveFaces[faceZinV] == 0 ) ){ atomicMax( newActiveFaces[faceZinV], 1 ); }
        if( ( faceXinU > 3 ) && ( newActiveFaces[faceXinU] == 0 ) ){ atomicMax( newActiveFaces[faceXinU], 1 ); }
        if( ( faceYinU > 3 ) && ( newActiveFaces[faceYinU] == 0 ) ){ atomicMax( newActiveFaces[faceYinU], 1 ); }
        if( ( faceZinU > 3 ) && ( newActiveFaces[faceZinU] == 0 ) ){ atomicMax( newActiveFaces[faceZinU], 1 ); }

    }
}