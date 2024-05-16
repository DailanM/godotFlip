#[compute]
#version 450


// Make sure the compute keyword is uncommented, and that it doesn't have a comment on the same line.
// Also, the linting plugin only works if the first line is commented, and the file extension is .comp
// Godot only works when the first line is NOT commented and the file extension is .glsl
// What a pain.

#define REAL precise float

// Invocations in the (x, y, z) dimension
layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// Output. To be reused whenever we implement robust predicates.
layout(set = 0, binding = 0, std430) writeonly buffer predicate_const_uniform {
    REAL data[];
} predConsts;


// there is only one invocation, it needs to be computed on the GPU so we get the right errors
void main()
{
    REAL _half = 0.5;
    REAL epsilon = 1.0;
    REAL splitter = 1.0;
    REAL check = 1.0;
    REAL lastcheck;
    bool every_other = true;

    /* Repeatedly divide `epsilon' by two until it is too small to add to    */
    /*   one without causing roundoff.  (Also check if the sum is equal to   */
    /*   the previous sum, for machines that round up instead of using exact */
    /*   rounding.  Not that this library will work on such machines anyway. */
    do
    {
        lastcheck   = check;
        epsilon     *= _half;

        if (every_other)
        {
            splitter *= 2.0;
        }

        every_other = !every_other;
        check       = 1.0 + epsilon;
    } while ((check != 1.0) && (check != lastcheck));

    /* Error bounds for orientation and incircle tests. */
    // Epsilon
    predConsts.data[ 0  ] = epsilon; 
    // Splitter
    predConsts.data[ 1  ] = splitter + 1.0;
    // Resulterrbound
    predConsts.data[ 2  ] = (3.0 + 8.0 * epsilon) * epsilon;
    // CcwerrboundA
    predConsts.data[ 3  ] = (3.0 + 16.0 * epsilon) * epsilon;
    // CcwerrboundB
    predConsts.data[ 4  ] = (2.0 + 12.0 * epsilon) * epsilon;
    // CcwerrboundC
    predConsts.data[ 5  ] = (9.0 + 64.0 * epsilon) * epsilon * epsilon;
    // O3derrboundA
    predConsts.data[ 6  ] = (7.0 + 56.0 * epsilon) * epsilon;
    // O3derrboundB
    predConsts.data[ 7  ] = (3.0 + 28.0 * epsilon) * epsilon;
    // O3derrboundC
    predConsts.data[ 8  ] = (26.0 + 288.0 * epsilon) * epsilon * epsilon;
    // IccerrboundA
    predConsts.data[ 9  ] = (10.0 + 96.0 * epsilon) * epsilon;
    // IccerrboundB
    predConsts.data[ 10 ] = (4.0 + 48.0 * epsilon) * epsilon;
    // IccerrboundC
    predConsts.data[ 11 ] = (44.0 + 576.0 * epsilon) * epsilon * epsilon;
    // IsperrboundA
    predConsts.data[ 12 ] = (16.0 + 224.0 * epsilon) * epsilon;
    // IsperrboundB
    predConsts.data[ 13 ] = (5.0 + 72.0 * epsilon) * epsilon;
    // IsperrboundC
    predConsts.data[ 14 ] = (71.0 + 1408.0 * epsilon) * epsilon * epsilon;
    // O3derrboundAlifted
    predConsts.data[ 15 ] = (11.0 + 112.0 * epsilon) * epsilon;
        //(10.0 + 112.0 * epsilon) * epsilon;
    // O2derrboundAlifted
    predConsts.data[ 16 ] = (6.0 + 48.0 * epsilon) * epsilon;
    // O1derrboundAlifted
    predConsts.data[ 17 ] = (3.0 + 16.0 * epsilon) * epsilon;

}