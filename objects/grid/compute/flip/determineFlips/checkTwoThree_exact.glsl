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

layout(set = 0, binding = 0, std430) restrict coherent buffer ufActiveFace           {uint activeFace[];           };
layout(set = 0, binding = 1, std430) restrict coherent buffer ufPoints               {REALTYPE points[];           };
layout(set = 0, binding = 2, std430) restrict coherent buffer ufTetra                {uint tetra[];                };
layout(set = 0, binding = 3, std430) restrict coherent buffer ufFaceToTetra          {uint faceToTetra[];          };
layout(set = 0, binding = 4, std430) restrict coherent buffer ufTetraToFace          {uint tetraToFace[];          };
layout(set = 0, binding = 5, std430) restrict coherent buffer ufFlipInfo             {uint flipInfo[];             };
layout(set = 0, binding = 6, std430) restrict coherent buffer ufBadFaces             {uint badFaces[];             };
layout(set = 0, binding = 7, std430) restrict coherent buffer ufIndeterminedTwoThree {uint indeterminedTwoThree[]; };
layout(set = 0, binding = 8, std430) restrict coherent buffer ufPredConsts           {REALTYPE predConsts[];       };

// ---- Predicates ----

/* Which of the following two methods of finding the absolute values is      */
/*   fastest is compiler-dependent.  A few compilers can inline and optimize */
/*   the fabs() call; but most will incur the overhead of a function call,   */
/*   which is disastrously slow.  A faster way on IEEE machines might be to  */
/*   mask the appropriate bit, but that's difficult to do in C.              */

#define Absolute(a)  ((a) >= 0.0 ? (a) : -(a))
/* #define Absolute(a)  fabs(a) */

/* Many of the operations are broken up into two pieces, a main part that    */
/*   performs an approximate operation, and a "tail" that computes the       */
/*   roundoff error of that operation.                                       */
/*                                                                           */
/* The operations Fast_Two_Sum(), Fast_Two_Diff(), Two_Sum(), Two_Diff(),    */
/*   Split(), and Two_Product() are all implemented as described in the      */
/*   reference.  Each of these macros requires certain variables to be       */
/*   defined in the calling routine.  The variables `bvirt', `c', `abig',    */
/*   `_i', `_j', `_k', `_l', `_m', and `_n' are declared `INEXACT' because   */
/*   they store the result of an operation that may incur roundoff error.    */
/*   The input parameter `x' (or the highest numbered `x_' parameter) must   */
/*   also be declared `INEXACT'.                                             */


#define Fast_Two_Sum_Tail(a, b, x, y) \
  bvirt = x - a; \
  y = b - bvirt

#define Fast_Two_Sum(a, b, x, y) \
  x = REALCAST(a + b); \
  Fast_Two_Sum_Tail(a, b, x, y)

#define Fast_Two_Diff_Tail(a, b, x, y) \
  bvirt = a - x; \
  y = bvirt - b

#define Fast_Two_Diff(a, b, x, y) \
  x = REALCAST(a - b); \
  Fast_Two_Diff_Tail(a, b, x, y)

#define Two_Sum_Tail(a, b, x, y) \
  bvirt = REALCAST(x - a); \
  avirt = x - bvirt; \
  bround = b - bvirt; \
  around = a - avirt; \
  y = around + bround

#define Two_Sum(a, b, x, y) \
  x = REALCAST(a + b); \
  Two_Sum_Tail(a, b, x, y)

#define Two_Diff_Tail(a, b, x, y) \
  bvirt = REALCAST(a - x); \
  avirt = x + bvirt; \
  bround = bvirt - b; \
  around = a - avirt; \
  y = around + bround

#define Two_Diff(a, b, x, y) \
  x = REALCAST(a - b); \
  Two_Diff_Tail(a, b, x, y)

#define Split(a, ahi, alo) \
  c = (predConsts[ 1 ] * a); \
  abig = (c - a); \
  ahi = c - abig; \
  alo = a - ahi

#define Two_Product_Tail(a, b, x, y) \
  Split(a, ahi, alo); \
  Split(b, bhi, blo); \
  err1 = x - (ahi * bhi); \
  err2 = err1 - (alo * bhi); \
  err3 = err2 - (ahi * blo); \
  y = (alo * blo) - err3

#define Two_Product(a, b, x, y) \
  x = (a * b); \
  Two_Product_Tail(a, b, x, y)

// Two_Product_Presplit() is Two_Product() where one of the inputs has       
//   already been split.  Avoids redundant splitting.                        

#define Two_Product_Presplit(a, b, bhi, blo, x, y) \
  x = REALCAST(a * b); \
  Split(a, ahi, alo); \
  err1 = x - (ahi * bhi); \
  err2 = err1 - (alo * bhi); \
  err3 = err2 - (ahi * blo); \
  y = (alo * blo) - err3

// Two_Product_2Presplit() is Two_Product() where both of the inputs have    
//   already been split.  Avoids redundant splitting.                        

#define Two_Product_2Presplit(a, ahi, alo, b, bhi, blo, x, y) \
  x = REALCAST(a * b); \
  err1 = x - (ahi * bhi); \
  err2 = err1 - (alo * bhi); \
  err3 = err2 - (ahi * blo); \
  y = (alo * blo) - err3

// Square() can be done more quickly than Two_Product().                     

#define Square_Tail(a, x, y) \
  Split(a, ahi, alo); \
  err1 = x - (ahi * ahi); \
  err3 = err1 - ((ahi + ahi) * alo); \
  y = (alo * alo) - err3

#define Square(a, x, y) \
  x = REALCAST(a * a); \
  Square_Tail(a, x, y)


// Macros for summing expansions of various fixed lengths.  These are all    
//   unrolled versions of Expansion_Sum().                                   

#define Two_One_Sum(a1, a0, b, x2, x1, x0) \
  Two_Sum(a0, b , _i, x0); \
  Two_Sum(a1, _i, x2, x1)

#define Two_One_Diff(a1, a0, b, x2, x1, x0) \
  Two_Diff(a0, b , _i, x0); \
  Two_Sum( a1, _i, x2, x1)

#define Two_Two_Sum(a1, a0, b1, b0, x3, x2, x1, x0) \
  Two_One_Sum(a1, a0, b0, _j, _0, x0); \
  Two_One_Sum(_j, _0, b1, x3, x2, x1)

#define Two_Two_Diff(a1, a0, b1, b0, x3, x2, x1, x0) \
  Two_One_Diff(a1, a0, b0, _j, _0, x0); \
  Two_One_Diff(_j, _0, b1, x3, x2, x1)

#define Four_One_Sum(a3, a2, a1, a0, b, x4, x3, x2, x1, x0) \
  Two_One_Sum(a1, a0, b , _j, x1, x0); \
  Two_One_Sum(a3, a2, _j, x4, x3, x2)

#define Four_Two_Sum(a3, a2, a1, a0, b1, b0, x5, x4, x3, x2, x1, x0) \
  Four_One_Sum(a3, a2, a1, a0, b0, _k, _2, _1, _0, x0); \
  Four_One_Sum(_k, _2, _1, _0, b1, x5, x4, x3, x2, x1)

#define Four_Four_Sum(a3, a2, a1, a0, b4, b3, b1, b0, x7, x6, x5, x4, x3, x2, \
                      x1, x0) \
  Four_Two_Sum(a3, a2, a1, a0, b1, b0, _l, _2, _1, _0, x1, x0); \
  Four_Two_Sum(_l, _2, _1, _0, b4, b3, x7, x6, x5, x4, x3, x2)

#define Eight_One_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b, x8, x7, x6, x5, x4, \
                      x3, x2, x1, x0) \
  Four_One_Sum(a3, a2, a1, a0, b , _j, x3, x2, x1, x0); \
  Four_One_Sum(a7, a6, a5, a4, _j, x8, x7, x6, x5, x4)

#define Eight_Two_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b1, b0, x9, x8, x7, \
                      x6, x5, x4, x3, x2, x1, x0) \
  Eight_One_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b0, _k, _6, _5, _4, _3, _2, \
                _1, _0, x0); \
  Eight_One_Sum(_k, _6, _5, _4, _3, _2, _1, _0, b1, x9, x8, x7, x6, x5, x4, \
                x3, x2, x1)

#define Eight_Four_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b4, b3, b1, b0, x11, \
                       x10, x9, x8, x7, x6, x5, x4, x3, x2, x1, x0) \
  Eight_Two_Sum(a7, a6, a5, a4, a3, a2, a1, a0, b1, b0, _l, _6, _5, _4, _3, \
                _2, _1, _0, x1, x0); \
  Eight_Two_Sum(_l, _6, _5, _4, _3, _2, _1, _0, b4, b3, x11, x10, x9, x8, \
                x7, x6, x5, x4, x3, x2)

// Macros for multiplying expansions of various fixed lengths.               

#define Two_One_Product(a1, a0, b, x3, x2, x1, x0) \
  Split(b, bhi, blo); \
  Two_Product_Presplit(a0, b, bhi, blo, _i, x0); \
  Two_Product_Presplit(a1, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x1); \
  Fast_Two_Sum(_j, _k, x3, x2)

#define Four_One_Product(a3, a2, a1, a0, b, x7, x6, x5, x4, x3, x2, x1, x0) \
  Split(b, bhi, blo); \
  Two_Product_Presplit(a0, b, bhi, blo, _i, x0); \
  Two_Product_Presplit(a1, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x1); \
  Fast_Two_Sum(_j, _k, _i, x2); \
  Two_Product_Presplit(a2, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x3); \
  Fast_Two_Sum(_j, _k, _i, x4); \
  Two_Product_Presplit(a3, b, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, x5); \
  Fast_Two_Sum(_j, _k, x7, x6)

#define Two_Two_Product(a1, a0, b1, b0, x7, x6, x5, x4, x3, x2, x1, x0) \
  Split(a0, a0hi, a0lo); \
  Split(b0, bhi, blo); \
  Two_Product_2Presplit(a0, a0hi, a0lo, b0, bhi, blo, _i, x0); \
  Split(a1, a1hi, a1lo); \
  Two_Product_2Presplit(a1, a1hi, a1lo, b0, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _k, _1); \
  Fast_Two_Sum(_j, _k, _l, _2); \
  Split(b1, bhi, blo); \
  Two_Product_2Presplit(a0, a0hi, a0lo, b1, bhi, blo, _i, _0); \
  Two_Sum(_1, _0, _k, x1); \
  Two_Sum(_2, _k, _j, _1); \
  Two_Sum(_l, _j, _m, _2); \
  Two_Product_2Presplit(a1, a1hi, a1lo, b1, bhi, blo, _j, _0); \
  Two_Sum(_i, _0, _n, _0); \
  Two_Sum(_1, _0, _i, x2); \
  Two_Sum(_2, _i, _k, _1); \
  Two_Sum(_m, _k, _l, _2); \
  Two_Sum(_j, _n, _k, _0); \
  Two_Sum(_1, _0, _j, x3); \
  Two_Sum(_2, _j, _i, _1); \
  Two_Sum(_l, _i, _m, _2); \
  Two_Sum(_1, _k, _i, x4); \
  Two_Sum(_2, _i, _k, x5); \
  Two_Sum(_m, _k, x7, x6)

// An expansion of length two can be squared more quickly than finding the   
//   product of two different expansions of length two, and the result is    
//   guaranteed to have no more than six (rather than eight) components.     

#define Two_Square(a1, a0, x5, x4, x3, x2, x1, x0) \
  Square(a0, _j, x0); \
  _0 = a0 + a0; \
  Two_Product(a1, _0, _k, _1); \
  Two_One_Sum(_k, _1, _j, _l, _2, x1); \
  Square(a1, _j, _1); \
  Two_Two_Sum(_j, _1, _l, _2, x5, x4, x3, x2)

//                                                                           
//  fast_expansion_sum_zeroelim()   Sum two expansions, eliminating zero     
//                                  components from the output expansion.    
//                                                                           
//  Sets h = e + f.  See the long version of my paper for details.           
//                                                                           
//  If round-to-even is used (as with IEEE 754), maintains the strongly      
//  nonoverlapping property.  (That is, if e is strongly nonoverlapping, h   
//  will be also.)  Does NOT maintain the nonoverlapping or nonadjacent      
//  properties.
//

// 12 * 4 bytes in function
#define FAST_EXPANSION_SUM_ZEROELIM_FC_INT \
REALTYPE Q; \
INEXACT REALTYPE Qnew; \
INEXACT REALTYPE hh; \
INEXACT REALTYPE bvirt; \
REALTYPE avirt, bround, around; \
int eindex, findex, hindex; \
REALTYPE enow, fnow; \
enow = e[0]; \
fnow = f[0]; \
eindex = findex = 0; \
if ((fnow > enow) == (fnow > -enow)) { \
  Q = enow; \
  enow = e[++eindex]; \
} else { \
  Q = fnow; \
  fnow = f[++findex]; \
} \
hindex = 0; \
if ((eindex < elen) && (findex < flen)) { \
  if ((fnow > enow) == (fnow > -enow)) { \
    Fast_Two_Sum(enow, Q, Qnew, hh); \
    enow = e[++eindex]; \
  } else { \
    Fast_Two_Sum(fnow, Q, Qnew, hh); \
    fnow = f[++findex]; \
  } \
  Q = Qnew; \
  if (hh != 0.0) { \
    h[hindex++] = hh; \
  } \
  while ((eindex < elen) && (findex < flen)) { \
    if ((fnow > enow) == (fnow > -enow)) { \
      Two_Sum(Q, enow, Qnew, hh); \
      enow = e[++eindex]; \
    } else { \
      Two_Sum(Q, fnow, Qnew, hh); \
      fnow = f[++findex]; \
    } \
    Q = Qnew; \
    if (hh != 0.0) { \
      h[hindex++] = hh; \
    } \
  } \
} \
while (eindex < elen) { \
  Two_Sum(Q, enow, Qnew, hh); \
  enow = e[++eindex]; \
  Q = Qnew; \
  if (hh != 0.0) { \
    h[hindex++] = hh; \
  } \
} \
while (findex < flen) { \
  Two_Sum(Q, fnow, Qnew, hh); \
  fnow = f[++findex]; \
  Q = Qnew; \
  if (hh != 0.0) { \
    h[hindex++] = hh; \
  } \
} \
if ((Q != 0.0) || (hindex == 0)) { \
  h[hindex++] = Q; \
} \
return hindex;

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[4], int flen, REALTYPE f[4], REALTYPE h[8])  // h cannot be e or f.
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[4], int flen, REALTYPE f[8], REALTYPE h[16])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[4], REALTYPE h[12])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[8], REALTYPE h[16])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[8], int flen, REALTYPE f[16], REALTYPE h[24])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[16], int flen, REALTYPE f[8], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[24], int flen, REALTYPE f[24], REALTYPE h[48])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[48], int flen, REALTYPE f[48], REALTYPE h[96])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[96], int flen, REALTYPE f[96], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[4], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[12], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[16], REALTYPE h[192])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[192], int flen, REALTYPE f[96], REALTYPE h[288])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[288], int flen, REALTYPE f[288], REALTYPE h[576])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[384], int flen, REALTYPE f[384], REALTYPE h[768])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[576], int flen, REALTYPE f[576], REALTYPE h[1152])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[768], int flen, REALTYPE f[384], REALTYPE h[1152])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[1152], int flen, REALTYPE f[1152], REALTYPE h[2304])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[2304], int flen, REALTYPE f[1152], REALTYPE h[3456])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }

int fast_expansion_sum_zeroelim(int elen, REALTYPE e[2304], int flen, REALTYPE f[3456], REALTYPE h[5760])
{ FAST_EXPANSION_SUM_ZEROELIM_FC_INT }


//
//  scale_expansion_zeroelim()   Multiply an expansion by a scalar,
//                               eliminating zero components from the
//                               output expansion.
//  
//  Sets h = be.  See either version of my paper for details.                
//  
//  Maintains the nonoverlapping property.  If round-to-even is used (as
//  with IEEE 754), maintains the strongly nonoverlapping and nonadjacent
//  properties as well.  (That is, if e has one of these properties, so
//  will h.)
//

// 21 * 4 bytes in function
#define SCALE_EXP_ZEROELIM_FC_INT \
INEXACT REALTYPE Q, sum; \
REALTYPE hh; \
INEXACT REALTYPE product1; \
REALTYPE product0; \
int eindex, hindex; \
REALTYPE enow; \
INEXACT REALTYPE bvirt; \
REALTYPE avirt, bround, around; \
INEXACT REALTYPE c; \
INEXACT REALTYPE abig; \
REALTYPE ahi, alo, bhi, blo; \
REALTYPE err1, err2, err3; \
Split(b, bhi, blo); \
Two_Product_Presplit(e[0], b, bhi, blo, Q, hh); \
hindex = 0; \
if (hh != 0) { \
  h[hindex++] = hh; \
} \
for (eindex = 1; eindex < elen; eindex++) { \
  enow = e[eindex]; \
  Two_Product_Presplit(enow, b, bhi, blo, product1, product0); \
  Two_Sum(Q, product0, sum, hh); \
  if (hh != 0) { \
    h[hindex++] = hh; \
  } \
  Fast_Two_Sum(product1, sum, Q, hh); \
  if (hh != 0) { \
    h[hindex++] = hh; \
  } \
} \
if ((Q != 0.0) || (hindex == 0)) { \
  h[hindex++] = Q; \
} \
return hindex;

// Added multiple overloads for different array sizes~
int scale_expansion_zeroelim(int elen, REALTYPE e[4], REALTYPE b, REALTYPE h[8])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[4], REALTYPE b, REALTYPE h[12])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[8], REALTYPE b, REALTYPE h[16])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[12], REALTYPE b, REALTYPE h[24])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[24], REALTYPE b, REALTYPE h[48])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[48], REALTYPE b, REALTYPE h[96])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[96], REALTYPE b, REALTYPE h[192])
{ SCALE_EXP_ZEROELIM_FC_INT }

int scale_expansion_zeroelim(int elen, REALTYPE e[192], REALTYPE b, REALTYPE h[384])
{ SCALE_EXP_ZEROELIM_FC_INT }

//                                                                           
//  estimate()   Produce a one-word estimate of an expansion's value.        
//                                                                           
//  See either version of my paper for details.                              
//

#define ESTIMATE_FC_INT \
REALTYPE Q; \
int eindex; \
Q = e[0]; \
for (eindex = 1; eindex < elen; eindex++) { \
  Q += e[eindex]; \
} \
return Q; \

REALTYPE estimate(int elen, REALTYPE e[192])
{ ESTIMATE_FC_INT }

REALTYPE estimate(int elen, REALTYPE e[1152])
{ ESTIMATE_FC_INT }

//                                                                           
//  orient3dfast()   Approximate 3D orientation test.  Nonrobust.            
//  orient3dexact()   Exact 3D orientation test.  Robust.                    
//  orient3dslow()   Another exact 3D orientation test.  Robust.             
//  orient3d()   Adaptive exact 3D orientation test.  Robust.                
//                                                                           
//               Return a positive value if the point pd lies below the      
//               plane passing through pa, pb, and pc; "below" is defined so 
//               that pa, pb, and pc appear in counterclockwise order when   
//               viewed from above the plane.  Returns a negative value if   
//               pd lies above the plane.  Returns zero if the points are    
//               coplanar.  The result is also a rough approximation of six  
//               times the signed volume of the tetrahedron defined by the   
//               four points.                                                
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

// This function has 1631 * 4 bytes of variables, including the worst function call.

REALTYPE orient3drobust(Rvec3 pa,Rvec3 pb,Rvec3 pc,Rvec3 pd )             // ( 4 *   3 * 4 byte)
{
  INEXACT REALTYPE adx, bdx, cdx, ady, bdy, cdy, adz, bdz, cdz;           // (       9 * 4 byte)
  REALTYPE det, permanent, errbound;                                      // (       3 * 4 byte)

  INEXACT REALTYPE bdxcdy1, cdxbdy1, cdxady1, adxcdy1, adxbdy1, bdxady1;  // (       6 * 4 byte)
          REALTYPE bdxcdy0, cdxbdy0, cdxady0, adxcdy0, adxbdy0, bdxady0;  // (       6 * 4 byte)
  REALTYPE bc[4], ca[4], ab[4];                                           // ( 3 *   4 * 4 byte)
  INEXACT REALTYPE bc3, ca3, ab3;                                         // (       3 * 4 byte)
  REALTYPE adet[8], bdet[8], cdet[8];                                     // ( 3 *   8 * 4 byte)
  int alen, blen, clen;                                                   // (       3 * 4 byte)
  REALTYPE abdet[16];                                                     // ( 1 *  16 * 4 byte)
  int ablen;                                                              // (       1 * 4 byte)
  REALTYPE finnow[192], finother[192], finswap[192];                      // ( 3 * 192 * 4 byte)
  REALTYPE fin1[192], fin2[192];                                          // ( 2 * 192 * 4 byte)
  int finlength;                                                          // (       1 * 4 byte)

  REALTYPE adxtail, bdxtail, cdxtail;                                     // (       3 * 4 byte)
  REALTYPE adytail, bdytail, cdytail;                                     // (       3 * 4 byte)
  REALTYPE adztail, bdztail, cdztail;                                     // (       3 * 4 byte)
  INEXACT REALTYPE at_blarge, at_clarge;                                  // (       2 * 4 byte)
  INEXACT REALTYPE bt_clarge, bt_alarge;                                  // (       2 * 4 byte)
  INEXACT REALTYPE ct_alarge, ct_blarge;                                  // (       2 * 4 byte)
  REALTYPE at_b[4], at_c[4], bt_c[4], bt_a[4], ct_a[4], ct_b[4];          // ( 6 *   4 * 4 byte)
  int at_blen, at_clen, bt_clen, bt_alen, ct_alen, ct_blen;               // (       6 * 4 byte)
  INEXACT REALTYPE bdxt_cdy1, cdxt_bdy1, cdxt_ady1;                       // (       3 * 4 byte)
  INEXACT REALTYPE adxt_cdy1, adxt_bdy1, bdxt_ady1;                       // (       3 * 4 byte)
  REALTYPE bdxt_cdy0, cdxt_bdy0, cdxt_ady0;                               // (       3 * 4 byte)
  REALTYPE adxt_cdy0, adxt_bdy0, bdxt_ady0;                               // (       3 * 4 byte)
  INEXACT REALTYPE bdyt_cdx1, cdyt_bdx1, cdyt_adx1;                       // (       3 * 4 byte)
  INEXACT REALTYPE adyt_cdx1, adyt_bdx1, bdyt_adx1;                       // (       3 * 4 byte)
  REALTYPE bdyt_cdx0, cdyt_bdx0, cdyt_adx0;                               // (       3 * 4 byte)
  REALTYPE adyt_cdx0, adyt_bdx0, bdyt_adx0;                               // (       3 * 4 byte)
  REALTYPE bct[8], cat[8], abt[8];                                        // ( 3 *   8 * 4 byte)
  int bctlen, catlen, abtlen;                                             // (       3 * 4 byte)
  INEXACT REALTYPE bdxt_cdyt1, cdxt_bdyt1, cdxt_adyt1;                    // (       3 * 4 byte)
  INEXACT REALTYPE adxt_cdyt1, adxt_bdyt1, bdxt_adyt1;                    // (       3 * 4 byte)
  REALTYPE bdxt_cdyt0, cdxt_bdyt0, cdxt_adyt0;                            // (       3 * 4 byte)
  REALTYPE adxt_cdyt0, adxt_bdyt0, bdxt_adyt0;                            // (       3 * 4 byte)
  REALTYPE u[4], v[12], w[16];                                            // ( (4 + 12 + 16) * 4 byte)
  INEXACT REALTYPE u3;                                                    // (       1 * 4 byte)
  int vlength, wlength;                                                   // (       2 * 4 byte)
  REALTYPE negate;                                                        // (       1 * 4 byte)

  INEXACT REALTYPE bvirt;                                                 // (       1 * 4 byte)
  REALTYPE avirt, bround, around;                                         // (       3 * 4 byte)
  INEXACT REALTYPE c;                                                     // (       1 * 4 byte)
  INEXACT REALTYPE abig;                                                  // (       1 * 4 byte)
  REALTYPE ahi, alo, bhi, blo;                                            // (       4 * 4 byte)
  REALTYPE err1, err2, err3;                                              // (       3 * 4 byte)
  INEXACT REALTYPE _i, _j, _k;                                            // (       3 * 4 byte)
  REALTYPE _0;                                                            // (       1 * 4 byte)

 //                                                                            // Total: 1217 * 4 bytes

  // Fast orient part

  adx = REALCAST(pa[0] - pd[0]);
  bdx = REALCAST(pb[0] - pd[0]);
  cdx = REALCAST(pc[0] - pd[0]);
  ady = REALCAST(pa[1] - pd[1]);
  bdy = REALCAST(pb[1] - pd[1]);
  cdy = REALCAST(pc[1] - pd[1]);
  adz = REALCAST(pa[2] - pd[2]);
  bdz = REALCAST(pb[2] - pd[2]);
  cdz = REALCAST(pc[2] - pd[2]);

  bdxcdy1 = bdx * cdy;
  cdxbdy1 = cdx * bdy;

  cdxady1 = cdx * ady;
  adxcdy1 = adx * cdy;

  adxbdy1 = adx * bdy;
  bdxady1 = bdx * ady;

  det = adz * (bdxcdy1 - cdxbdy1) 
      + bdz * (cdxady1 - adxcdy1)
      + cdz * (adxbdy1 - bdxady1);

  permanent = (Absolute(bdxcdy1) + Absolute(cdxbdy1)) * Absolute(adz)
            + (Absolute(cdxady1) + Absolute(adxcdy1)) * Absolute(bdz)
            + (Absolute(adxbdy1) + Absolute(bdxady1)) * Absolute(cdz);

  // Orient3d adapt part

  Two_Product(bdx, cdy, bdxcdy1, bdxcdy0);
  Two_Product(cdx, bdy, cdxbdy1, cdxbdy0);
  Two_Two_Diff(bdxcdy1, bdxcdy0, cdxbdy1, cdxbdy0, bc3, bc[2], bc[1], bc[0]);
  bc[3] = bc3;
  alen = scale_expansion_zeroelim(4, bc, adz, adet);                                    // (1 + 4 + 1 + 8 + 21) * 4 bytes

  Two_Product(cdx, ady, cdxady1, cdxady0);
  Two_Product(adx, cdy, adxcdy1, adxcdy0);
  Two_Two_Diff(cdxady1, cdxady0, adxcdy1, adxcdy0, ca3, ca[2], ca[1], ca[0]);
  ca[3] = ca3;
  blen = scale_expansion_zeroelim(4, ca, bdz, bdet);                                    // (1 + 4 + 1 + 8 + 21) * 4 bytes

  Two_Product(adx, bdy, adxbdy1, adxbdy0);
  Two_Product(bdx, ady, bdxady1, bdxady0);
  Two_Two_Diff(adxbdy1, adxbdy0, bdxady1, bdxady0, ab3, ab[2], ab[1], ab[0]);
  ab[3] = ab3;
  clen = scale_expansion_zeroelim(4, ab, cdz, cdet);                                    // (1 + 4 + 1 + 8 + 21) * 4 bytes

  ablen = fast_expansion_sum_zeroelim(alen, adet, blen, bdet, abdet);                   // ( 1 +  8 + 1 + 8 +  16 + 12 ) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(ablen, abdet, clen, cdet, fin1);              // ( 1 + 16 + 1 + 8 + 192 + 12 ) * 4 bytes

  det = estimate(finlength, fin1);                                                      // 1 * 4 bytes
  errbound = predConsts[ 7 ] * permanent;
  if ((det >= errbound) || (-det >= errbound)) {
    return det;
  }

  Two_Diff_Tail(pa[0], pd[0], adx, adxtail);
  Two_Diff_Tail(pb[0], pd[0], bdx, bdxtail);
  Two_Diff_Tail(pc[0], pd[0], cdx, cdxtail);
  Two_Diff_Tail(pa[1], pd[1], ady, adytail);
  Two_Diff_Tail(pb[1], pd[1], bdy, bdytail);
  Two_Diff_Tail(pc[1], pd[1], cdy, cdytail);
  Two_Diff_Tail(pa[2], pd[2], adz, adztail);
  Two_Diff_Tail(pb[2], pd[2], bdz, bdztail);
  Two_Diff_Tail(pc[2], pd[2], cdz, cdztail);

  if ((adxtail == 0.0) && (bdxtail == 0.0) && (cdxtail == 0.0)
      && (adytail == 0.0) && (bdytail == 0.0) && (cdytail == 0.0)
      && (adztail == 0.0) && (bdztail == 0.0) && (cdztail == 0.0)) {
    return det;
  }

  errbound = predConsts[ 8 ] * permanent + predConsts[ 2 ] * Absolute(det);
  det += (adz * ((bdx * cdytail + cdy * bdxtail)
                 - (bdy * cdxtail + cdx * bdytail))
          + adztail * (bdx * cdy - bdy * cdx))
       + (bdz * ((cdx * adytail + ady * cdxtail)
                 - (cdy * adxtail + adx * cdytail))
          + bdztail * (cdx * ady - cdy * adx))
       + (cdz * ((adx * bdytail + bdy * adxtail)
                 - (ady * bdxtail + bdx * adytail))
          + cdztail * (adx * bdy - ady * bdx));
  if ((det >= errbound) || (-det >= errbound)) {
    return det;
  }

  finnow = fin1;
  finother = fin2;

  if (adxtail == 0.0) {
    if (adytail == 0.0) {
      at_b[0] = 0.0;
      at_blen = 1;
      at_c[0] = 0.0;
      at_clen = 1;
    } else {
      negate = -adytail;
      Two_Product(negate, bdx, at_blarge, at_b[0]);
      at_b[1] = at_blarge;
      at_blen = 2;
      Two_Product(adytail, cdx, at_clarge, at_c[0]);
      at_c[1] = at_clarge;
      at_clen = 2;
    }
  } else {
    if (adytail == 0.0) {
      Two_Product(adxtail, bdy, at_blarge, at_b[0]);
      at_b[1] = at_blarge;
      at_blen = 2;
      negate = -adxtail;
      Two_Product(negate, cdy, at_clarge, at_c[0]);
      at_c[1] = at_clarge;
      at_clen = 2;
    } else {
      Two_Product(adxtail, bdy, adxt_bdy1, adxt_bdy0);
      Two_Product(adytail, bdx, adyt_bdx1, adyt_bdx0);
      Two_Two_Diff(adxt_bdy1, adxt_bdy0, adyt_bdx1, adyt_bdx0,
                   at_blarge, at_b[2], at_b[1], at_b[0]);
      at_b[3] = at_blarge;
      at_blen = 4;
      Two_Product(adytail, cdx, adyt_cdx1, adyt_cdx0);
      Two_Product(adxtail, cdy, adxt_cdy1, adxt_cdy0);
      Two_Two_Diff(adyt_cdx1, adyt_cdx0, adxt_cdy1, adxt_cdy0,
                   at_clarge, at_c[2], at_c[1], at_c[0]);
      at_c[3] = at_clarge;
      at_clen = 4;
    }
  }
  if (bdxtail == 0.0) {
    if (bdytail == 0.0) {
      bt_c[0] = 0.0;
      bt_clen = 1;
      bt_a[0] = 0.0;
      bt_alen = 1;
    } else {
      negate = -bdytail;
      Two_Product(negate, cdx, bt_clarge, bt_c[0]);
      bt_c[1] = bt_clarge;
      bt_clen = 2;
      Two_Product(bdytail, adx, bt_alarge, bt_a[0]);
      bt_a[1] = bt_alarge;
      bt_alen = 2;
    }
  } else {
    if (bdytail == 0.0) {
      Two_Product(bdxtail, cdy, bt_clarge, bt_c[0]);
      bt_c[1] = bt_clarge;
      bt_clen = 2;
      negate = -bdxtail;
      Two_Product(negate, ady, bt_alarge, bt_a[0]);
      bt_a[1] = bt_alarge;
      bt_alen = 2;
    } else {
      Two_Product(bdxtail, cdy, bdxt_cdy1, bdxt_cdy0);
      Two_Product(bdytail, cdx, bdyt_cdx1, bdyt_cdx0);
      Two_Two_Diff(bdxt_cdy1, bdxt_cdy0, bdyt_cdx1, bdyt_cdx0,
                   bt_clarge, bt_c[2], bt_c[1], bt_c[0]);
      bt_c[3] = bt_clarge;
      bt_clen = 4;
      Two_Product(bdytail, adx, bdyt_adx1, bdyt_adx0);
      Two_Product(bdxtail, ady, bdxt_ady1, bdxt_ady0);
      Two_Two_Diff(bdyt_adx1, bdyt_adx0, bdxt_ady1, bdxt_ady0,
                  bt_alarge, bt_a[2], bt_a[1], bt_a[0]);
      bt_a[3] = bt_alarge;
      bt_alen = 4;
    }
  }
  if (cdxtail == 0.0) {
    if (cdytail == 0.0) {
      ct_a[0] = 0.0;
      ct_alen = 1;
      ct_b[0] = 0.0;
      ct_blen = 1;
    } else {
      negate = -cdytail;
      Two_Product(negate, adx, ct_alarge, ct_a[0]);
      ct_a[1] = ct_alarge;
      ct_alen = 2;
      Two_Product(cdytail, bdx, ct_blarge, ct_b[0]);
      ct_b[1] = ct_blarge;
      ct_blen = 2;
    }
  } else {
    if (cdytail == 0.0) {
      Two_Product(cdxtail, ady, ct_alarge, ct_a[0]);
      ct_a[1] = ct_alarge;
      ct_alen = 2;
      negate = -cdxtail;
      Two_Product(negate, bdy, ct_blarge, ct_b[0]);
      ct_b[1] = ct_blarge;
      ct_blen = 2;
    } else {
      Two_Product(cdxtail, ady, cdxt_ady1, cdxt_ady0);
      Two_Product(cdytail, adx, cdyt_adx1, cdyt_adx0);
      Two_Two_Diff(cdxt_ady1, cdxt_ady0, cdyt_adx1, cdyt_adx0,
                   ct_alarge, ct_a[2], ct_a[1], ct_a[0]);
      ct_a[3] = ct_alarge;
      ct_alen = 4;
      Two_Product(cdytail, bdx, cdyt_bdx1, cdyt_bdx0);
      Two_Product(cdxtail, bdy, cdxt_bdy1, cdxt_bdy0);
      Two_Two_Diff(cdyt_bdx1, cdyt_bdx0, cdxt_bdy1, cdxt_bdy0,
                   ct_blarge, ct_b[2], ct_b[1], ct_b[0]);
      ct_b[3] = ct_blarge;
      ct_blen = 4;
    }
  }

  bctlen = fast_expansion_sum_zeroelim(bt_clen, bt_c, ct_blen, ct_b, bct);              // ( 1 +   4 + 1 +  4 + 8 + 12) * 4 bytes
  wlength = scale_expansion_zeroelim(bctlen, bct, adz, w);                              // ( 1 +   8 + 1 + 16 + 21) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);     // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
  finswap = finnow; finnow = finother; finother = finswap;

  catlen = fast_expansion_sum_zeroelim(ct_alen, ct_a, at_clen, at_c, cat);              // ( 1 +   4 + 1 +  4 + 8 + 12) * 4 bytes
  wlength = scale_expansion_zeroelim(catlen, cat, bdz, w);                              // ( 1 +   8 + 1 + 16 + 21) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);     // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
  finswap = finnow; finnow = finother; finother = finswap;

  abtlen = fast_expansion_sum_zeroelim(at_blen, at_b, bt_alen, bt_a, abt);              // ( 1 +   4 + 1 +  4 + 8 + 12) * 4 bytes
  wlength = scale_expansion_zeroelim(abtlen, abt, cdz, w);                              // ( 1 +   8 + 1 + 16 + 21) * 4 bytes
  finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);     // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
  finswap = finnow; finnow = finother; finother = finswap;

  if (adztail != 0.0) {
    vlength = scale_expansion_zeroelim(4, bc, adztail, v);                              // ( 1 +   4 + 1 + 12 + 21) * 4 bytes
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, vlength, v, finother);   // ( 1 + 192 + 1 + 12 + 192 + 12) * 4 bytes
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (bdztail != 0.0) {
    vlength = scale_expansion_zeroelim(4, ca, bdztail, v);                              // ( 1 +   4 + 1 + 12 + 21) * 4 bytes
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, vlength, v, finother);   // ( 1 + 192 + 1 + 12 + 192 + 12) * 4 bytes
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (cdztail != 0.0) {
    vlength = scale_expansion_zeroelim(4, ab, cdztail, v);                              // ( 1 +   4 + 1 + 12 + 21) * 4 bytes
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, vlength, v, finother);   // ( 1 + 192 + 1 + 12 + 192 + 12) * 4 bytes
    finswap = finnow; finnow = finother; finother = finswap;
  }

  if (adxtail != 0.0) {
    if (bdytail != 0.0) {
      Two_Product(adxtail, bdytail, adxt_bdyt1, adxt_bdyt0);
      Two_One_Product(adxt_bdyt1, adxt_bdyt0, cdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (cdztail != 0.0) {
        Two_One_Product(adxt_bdyt1, adxt_bdyt0, cdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
    if (cdytail != 0.0) {
      negate = -adxtail;
      Two_Product(negate, cdytail, adxt_cdyt1, adxt_cdyt0);
      Two_One_Product(adxt_cdyt1, adxt_cdyt0, bdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (bdztail != 0.0) {
        Two_One_Product(adxt_cdyt1, adxt_cdyt0, bdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
  }
  if (bdxtail != 0.0) {
    if (cdytail != 0.0) {
      Two_Product(bdxtail, cdytail, bdxt_cdyt1, bdxt_cdyt0);
      Two_One_Product(bdxt_cdyt1, bdxt_cdyt0, adz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (adztail != 0.0) {
        Two_One_Product(bdxt_cdyt1, bdxt_cdyt0, adztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
    if (adytail != 0.0) {
      negate = -bdxtail;
      Two_Product(negate, adytail, bdxt_adyt1, bdxt_adyt0);
      Two_One_Product(bdxt_adyt1, bdxt_adyt0, cdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (cdztail != 0.0) {
        Two_One_Product(bdxt_adyt1, bdxt_adyt0, cdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
  }
  if (cdxtail != 0.0) {
    if (adytail != 0.0) {
      Two_Product(cdxtail, adytail, cdxt_adyt1, cdxt_adyt0);
      Two_One_Product(cdxt_adyt1, cdxt_adyt0, bdz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (bdztail != 0.0) {
        Two_One_Product(cdxt_adyt1, cdxt_adyt0, bdztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
    if (bdytail != 0.0) {
      negate = -cdxtail;
      Two_Product(negate, bdytail, cdxt_bdyt1, cdxt_bdyt0);
      Two_One_Product(cdxt_bdyt1, cdxt_bdyt0, adz, u3, u[2], u[1], u[0]);
      u[3] = u3;
      finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);       // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
      finswap = finnow; finnow = finother; finother = finswap;
      if (adztail != 0.0) {
        Two_One_Product(cdxt_bdyt1, cdxt_bdyt0, adztail, u3, u[2], u[1], u[0]);
        u[3] = u3;
        finlength = fast_expansion_sum_zeroelim(finlength, finnow, 4, u, finother);     // ( 1 + 192 + 1 + 4 + 192 + 12) * 4 bytes
        finswap = finnow; finnow = finother; finother = finswap;
      }
    }
  }

  if (adztail != 0.0) {
    wlength = scale_expansion_zeroelim(bctlen, bct, adztail, w);
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);   // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (bdztail != 0.0) {
    wlength = scale_expansion_zeroelim(catlen, cat, bdztail, w);
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);   // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
    finswap = finnow; finnow = finother; finother = finswap;
  }
  if (cdztail != 0.0) {
    wlength = scale_expansion_zeroelim(abtlen, abt, cdztail, w);
    finlength = fast_expansion_sum_zeroelim(finlength, finnow, wlength, w, finother);   // ( 1 + 192 + 1 + 16 + 192 + 12) * 4 bytes       BIGGEST CALL
    finswap = finnow; finnow = finother; finother = finswap;
  }

  return finnow[finlength - 1];
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
  uint indeterminedNonconvexBadFace    = indeterminedTwoThree[ id ];
  uint indeterminedNonconvexActiveFace = badFaces[   indeterminedNonconvexBadFace    ];
  uint indeterminedNonconvexFaceId     = activeFace[ indeterminedNonconvexActiveFace ];

  // Now we get the far vertex of in A for the locally Delauney check, and for the 3-2 test, we also need the far index in B. The shared
  // face could be indexed in each face in any order WRT the face in B, so we construct and edge adjacency list in faceBToFaceA.
  uint AfarInd; Rvec3 Afar; 
  uint BfarInd; Rvec3 Bfar;

  uint twistFaceB[3];
  uint twistFaceA[3];

  // Get the tetrahedra
  uint tetA = faceToTetra[ 2*indeterminedNonconvexFaceId + 0 ]; // The tetra in which we are positively oriented.
  uint tetB = faceToTetra[ 2*indeterminedNonconvexFaceId + 1 ]; // The tetra in which we are negatively oriented.
  uint tetC;

  // ------------------------------ INFO ------------------------------

  // The non-convex faces became the faces to check, so the aggregate info now reads
  // ----------------------------------------------------------------------------------------------
  // | canFlip | isOfQ | isOfS | AfarIsa | BfarIsb | faceTwist | faceTwist | cantTwoThreeFlip | ...
  // ----------------------------------------------------------------------------------------------
  // ... | Face 2 can 3-2 over | Face 1 can 3-2 over | Face 0 can 3-2 over | Face 2 Indeterminant | ...
  // ----------------------------------------------------------------------------------------------
  //                                            ... | Face 1 Indeterminant | Face 0 Indeterminant |  Each space is a bit

  uint info = flipInfo[ indeterminedNonconvexBadFace ];

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
    if( ( ( (info >> (i + 3)) & 1 ) == 1) && (( (info >> i) & 1) == 1 ) ){ // We expect only one of these to evaluate to true, 
                                                                           // but there is still a small chance two evaluate to true.

      // The check is gaurenteed to be determinant.
      info -= (1 << i);

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

      // Reminder:  2*index + 0,  positivly oriented: ccw normal facing outside the tetrahedron.
      //            2*index + 1, negatively oriented: ccw normal facing  inside the tetrahedron.
      //
      //                     '(i + 1) & 1' is shorthand for mod( i + 1, 2)
      uint BOtherInFace = (BFaceInTet + 1) & 1 ;
      uint tetC = faceToTetra[ 2 * BFaceIndex + BOtherInFace ];
      
      // now we run an exact check to see if the union of the three complex is convex:

      // We check this by ensuring that the two points u, v of the middle edge lie on opposite
      // sides of a face drawn by both the far points and remaining point w of the active face.
      // (the three points form a face after a 3-2 flip, with the verticies of the edge the
      // finalizing the two tetrahedra.)

      uint wInB = twistFaceB[ i ]; uint wInd = tetra[ 4 * tetB + wInB ];
      Rvec3 w = pointOfIndex( wInd );
      
      REALTYPE orient_U = sign( orient3drobust(w, Bfar, Afar, u) );
      REALTYPE orient_V = sign( orient3drobust(w, Bfar, Afar, v) );

      if( ( !( orient_U == orient_V ) ) || ( ( orient_U == 0.0 ) && (orient_V == 0.0 ) ) ){

        // Sucess! They don't lie on the same side, so we've determined a flip and implicitely encoded it!

      } else { info -= (1 << (3 + i)); }

      // Every failing case sets 'Face i can 3-2' over to zero
    }

    // Right now we're allowing a 2-3 flip when all 5 points lie on a plane.
    // The star may still be convex then, but I don't know if that's optimal.
  }

  flipInfo[ indeterminedNonconvexBadFace ] = info;
}