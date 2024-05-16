using Godot;
using System;

#pragma warning disable IDE0017
#pragma warning disable IDE0090
#pragma warning disable IDE0056
#pragma warning disable IDE1006
#pragma warning disable CA1050

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// 						Node Begin
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

public partial class NearDelauney : Node3D
{
	uint _numPointsRemaining;
	
	Rid _bfPointsToAdd;  Rid _bfTetraOfPoints;
	Rid _bfActiveFaces;

	// Debug
	Rid _bfDelauneyFaces; Rid _bfNonDelauneyFaces;
	uint _numDelauneyFaces; uint _numNonDelauneyFaces;

	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                                          gFlip3D                                                          */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */

	private partial int gdFlip3D( bool Flipping )
	{	
		InitComplexBuffers(); // Sizes the buffers and writes out the initial complex of one tetrahedron.

		if( DEBUG_COMPLEX ){
			debugLogAddLine( "----------------------------- INIT! -----------------------------" );
			debugLogAddLine( "bfTetra: " + quadrupletToString( bfToUint( _bfTetra, 4 ) ) );
			debugLogAddLine( "bfFace: " + tripletToString( bfToUint( _bfFace, 3 * 4 ) ) );
			debugLogAddLine( "bfEdge: " + doubletToString( bfToUint( _bfEdge, 2 * 6 ) ) );
		}


		uint splitLoopCounter = 0;
		// --------------- 	start splitting!	---------------
		while( (_numPointsRemaining > 0) ) { // There are still points left to split with!

			string DEBUG_STRING = "";
			if( DEBUG ){
				DEBUG_STRING += "Split: ptsToAdd: " + _numPointsRemaining;
			}

			splitLoopCounter++;
			if( DEBUG_COMPLEX ){
					debugLogAddLine( "----------- check for split: loop number " + splitLoopCounter + " -----------");
			}

			if( DEBUG_COMPLEX ){
				debugLogAddLine( "----------------------------- DETERMINE SPLIT! -----------------------------");
				debugLogAddLine( "numPointsRemaining: " + _numPointsRemaining + " with ");
				debugLogAddLine( "pointsToAdd:      "  + singleToString( bfToUint( _bfPointsToAdd , _numPointsRemaining) ) );
				debugLogAddLine( "tetraOfPoint:     "  + singleToString( bfToUint( _bfTetraOfPoints , _numPointsRemaining) ) );
			}

			// ----- Determine Which point will split which tetra -----
			Rid bfPointIsSplitting	= newBuffer( _numPointsRemaining );
			Rid bfTetraIsSplitBy	= newBuffer( _lastTetra + 1 ); maxFill( bfTetraIsSplitBy, _lastTetra + 1 ); // Will contain the index of the point splitting the tetra if splitting. If not, it contains the max uint.
			DetermineSplit( bfTetraIsSplitBy, bfPointIsSplitting );

			// ----- Compact Split Info ----- 
			Rid bfSplittingTetraSum = newBuffer( _lastTetra + 1 ); 	// The id _of the split_ at the index of a splitting tetra. (a prefix sum w/ extra space for max)
			Rid bfSplittingTetra = newBuffer( _lastTetra + 1 ); 	// A compact list of tetrahedra that will be split at the splitting id.

			//TODO: DEBUG THIS SECTION 
			bfTetraIsSplitBy = compactSplit( bfTetraIsSplitBy, bfSplittingTetraSum, bfSplittingTetra);
			if( DEBUG_COMPLEX ){
				debugLogAddLine( "splittingTetraSum:"  + singleToString( bfToUint( bfSplittingTetraSum , _lastTetra + 1) ) );
			}
			uint numSplitTetra = nthPlaceOfBuffer(_lastTetra, bfSplittingTetraSum);

			if( DEBUG_COMPLEX ){
				debugLogAddLine( "pointIsSplitting: "  + singleToString( bfToUint( bfPointIsSplitting , _numPointsRemaining) ) );
				debugLogAddLine( "SplittingTetra:   " 	+ singleToString( bfToUint( bfSplittingTetra , numSplitTetra) ) );
				debugLogAddLine( "tetIsSplitBy:     " 	+ singleToString( bfToUint( bfTetraIsSplitBy , numSplitTetra) ) );
				debugLogAddLine( "tetraToSplit:     " 	+ singleToString( bfToUint( bfSplittingTetraSum , _numTetra) ) );
			}

			// ----- Expand buffers if needed -----
			ExpandForSplit( numSplitTetra ); // TODO: we sometimes don't need to reserve as much space now that we have the offsets.

			if( DEBUG_COMPLEX ){
				debugLogAddLine( "New buffer sizes: bftetra = " + _bfTetraSize +  ", bfFace = " + _bfFaceSize + ", bfEdge = " + _bfEdgeSize );
				debugLogAddLine( "Using these numFreedtetra = " + _numFreedTetra + ", numFreedFace = " + _numFreedFaces + ", numFreedEdge = " + _numFreedEdges );
				debugLogAddLine( "FreedTetra: " + singleToString( bfToUint( _bfFreedTetra, _numFreedTetra ) ) );
				debugLogAddLine( "FreedFaces: " + singleToString( bfToUint( _bfFreedFaces, _numFreedFaces ) ) );
				debugLogAddLine( "FreedEdges: " + singleToString( bfToUint( _bfFreedEdges, _numFreedEdges ) ) );
			}

			// ----- Split -----
			uint[] offset = { _lastTetra, _lastFace, _lastEdge, _numFreedTetra, _numFreedFaces, _numFreedEdges, numSplitTetra };
			Rid bfOffset = toBuffer( offset );

			_bfActiveFaces = newBuffer( _numFaces ); zeroFill( _bfActiveFaces, _numFaces ); // marked with 1
			uint activeFacesSize = _numFaces;
			SplitTetra( numSplitTetra, bfTetraIsSplitBy, bfSplittingTetra, _bfActiveFaces, bfOffset);

			// update complex memory management info.
			uint numTetraAdded = 3 * numSplitTetra; _numTetra += numTetraAdded;
			uint numFacesAdded = 6 * numSplitTetra; _numFaces += numFacesAdded;
			uint numEdgesAdded = 4 * numSplitTetra; _numEdges += numEdgesAdded;
			if( numTetraAdded > _numFreedTetra ){ _numFreedTetra = 0; _lastTetra = _numTetra - 1; } else { _numFreedTetra -= numTetraAdded; /* _lastTetra unchanged */ }
			if( numFacesAdded > _numFreedFaces ){ _numFreedFaces = 0;  _lastFace = _numFaces - 1; } else { _numFreedFaces -= numFacesAdded; /* _lastFace  unchanged */ }
			if( numEdgesAdded > _numFreedEdges ){ _numFreedEdges = 0;  _lastEdge = _numEdges - 1; } else { _numFreedEdges -= numEdgesAdded; /* _lastEdge  unchanged */ }


			_rd.FreeRid( bfTetraIsSplitBy );
			_rd.FreeRid( bfSplittingTetra );

			if( DEBUG_COMPLEX ){
				debugLogAddLine( "----------------------------- SPLIT! -----------------------------" );
				debugLogAddLine( "# tetra: " + _numTetra + " # face: " + _numFaces + " # edge: " + _numEdges );
				debugLogAddLine( "bfTetra:              " + quadrupletToString( bfToUint( _bfTetra, 4 * (_lastTetra + 1) ) ) );
				debugLogAddLine( "bfTetraToFace:        " + quadrupletToString( bfToUint( _bfTetraToFace, 4 * (_lastTetra + 1) ) ) );
				debugLogAddLine( "bfTetraToEdge:        " + quadrupletToString( bfToUint( _bfTetraToEdge, 6 * (_lastTetra + 1) ) ) );
				debugLogAddLine( "bfFace:               " + tripletToString( bfToUint( _bfFace, 3 * (_lastFace + 1) ) ) );
				debugLogAddLine( "bfFaceToTetra:        " + doubletToString( bfToUint( _bfFaceToTetra, 2 * (_lastFace + 1) ) ) );
				debugLogAddLine( "bfEdge:               " + doubletToString( bfToUint( _bfEdge, 2 * (_lastEdge + 1) ) ) );
			}

			if( DEBUG ){
				DEBUG_STRING += " (t,f,e): (" + _numTetra + ", " + _numFaces + ", " + _numEdges + ") "  + " | ";
			}
			

			// ----- Compact and update _bfPointsToAdd and _bfTetOfPoints -----
			if( ( _numPointsRemaining - numSplitTetra ) > 0){ UpdatePointsRemaining( numSplitTetra, bfPointIsSplitting, bfSplittingTetraSum, bfOffset); }
			else{ _numPointsRemaining = 0; }

			_rd.FreeRid( bfPointIsSplitting );
			_rd.FreeRid( bfSplittingTetraSum );
			_rd.FreeRid( bfOffset );

			// --------------- 	start flipping!	---------------

			// ----- Compact active faces -----
			if(DEBUG_COMPLEX){
				debugLogAddLine( "(mark) bfActiveFaces:           " + singleToString( bfToUint( _bfActiveFaces, activeFacesSize ) ) );
			}

			uint numActiveFaces = compactActiveFaces( activeFacesSize ); // TODO: check that this will work on the first iteration.

			

			uint flipLoopCounter = 0;
			while( Flipping && ( numActiveFaces > 0) ){
				flipLoopCounter++;

				// if( (flipLoopCounter == 2) && (splitLoopCounter == 2) ){ break; } // TODO: remove this line. (It's just for debugging).

				if( DEBUG_COMPLEX ){
					debugLogAddLine( "----------- check for flip: loop number " + flipLoopCounter + " -----------");
				}

				if( DEBUG_COMPLEX ){
				debugLogAddLine( "#active: " + numActiveFaces + " (cpct) bfActiveFaces:" + singleToString( bfToUint( _bfActiveFaces, numActiveFaces ) ) );
				}

				if( DEBUG ){
					DEBUG_STRING += "FLIP: #Active: " + numActiveFaces + ", ";
				}

				Rid bfFlipInfo = newBuffer( numActiveFaces ); 
				
				// Determine which active faces need to be flipped (In three steps for exactness)
				checkLocalDelaunay( numActiveFaces, _bfActiveFaces, bfFlipInfo );

				
				Rid bfBadFaces = newBuffer(numActiveFaces);

				// Compact the faces that fail the local Delaunay check.
				uint numbadFaces = CompactBadFaces( numActiveFaces, bfFlipInfo, bfBadFaces ); // Notice: implicitly pairs flipInfo with activeFaces

				if(DEBUG_COMPLEX){
					debugLogAddLine( "              final bfFlipInfo: " + singleToString( bfToUint( bfFlipInfo, numActiveFaces ) ) );
					debugLogAddLine( "#bad: " + numbadFaces + "             bfBadFaces: " + singleToString( bfToUint( bfBadFaces, numbadFaces ) ) );
				}

				if( numbadFaces == 0 ){
					if( DEBUG ){
					DEBUG_STRING += " toFlip: " + 0 + ", (" + _numTetra + ", " + _numFaces + ", " + _numEdges + ") "  + " | ";
					}
					break; // NOT for debugging. TODO: ensure there are no memory leaks here.
				}
				
				// Determine the flips which would erase (most of) the offending faces.
				determineFlips( numbadFaces, _bfActiveFaces, bfFlipInfo, bfBadFaces ); // Notice: implicitly overwrites and pairs flipInfo with badFaces

				// Now decide which flips to actually undertake, and ensure there is no conflict across flips.
				Rid bfTetraMarkedFlip = newBuffer(_lastTetra + 1); zeroFill(bfTetraMarkedFlip, _lastTetra + 1);  // TODO: Im' debugging and this should be empty when it's not??
				pickFlips( numbadFaces, _bfActiveFaces, bfFlipInfo, bfBadFaces, bfTetraMarkedFlip);

				if(DEBUG_COMPLEX){
					debugLogAddLine( "                   bfTetraMarkedFlip: " + singleToString( bfToUint( bfTetraMarkedFlip, _lastTetra + 1 ) ) );
					debugLogAddLine( " (13 GOOD) Final -Marked- bfFlipInfo: " + singleToString( bfToByte( bfFlipInfo, numbadFaces ) ) );
				}

				// independant of finalizeTetraMarkedFlip
				// Now that flips the number of flips is determined, ensure that we have enough space to write out the new complex.
				Rid bfBadFacesToFlip = newBuffer( numbadFaces );
				Rid bfThreeTwoAtFlip = newBuffer( numbadFaces );
				Rid bfBadFacesToThreeTwoFlip = newBuffer( numbadFaces );
				Rid bfFlipPrefixSum = newBuffer( numbadFaces );
				uint[] countFlips = compactFlips(numbadFaces, bfFlipInfo, bfFlipPrefixSum, bfBadFacesToFlip, bfThreeTwoAtFlip, bfBadFacesToThreeTwoFlip);
				uint numFlips = countFlips[0];
				uint numThreeTwoFlips = countFlips[1];
				uint numTwoThreeFlips = numFlips - numThreeTwoFlips;

				if(DEBUG_COMPLEX){
					debugLogAddLine( "              final bfFlipInfo: " + singleToString( bfToByte( bfFlipInfo, numbadFaces ) ) );
					debugLogAddLine( "#flip: " + numFlips + ", " + numThreeTwoFlips + " bfBadFacesToFlip: " + singleToString( bfToUint( bfBadFacesToFlip, numFlips ) ) );
				}

				if( numFlips == 0 ){
					if( DEBUG ){
					DEBUG_STRING += " toFlip: " + 0 + ", (" + _numTetra + ", " + _numFaces + ", " + _numEdges + ") "  + " | ";
					}
					break;
				}

				if( DEBUG ){
					DEBUG_STRING += " toFlip: " + numFlips;
				}

				// I need to think a little harder about whether this is even needed at all.
				finalizeTetraMarkedFlip( bfTetraMarkedFlip, bfFlipInfo); // Iterates over the tetrahedra
				
				expandForFlip(numFlips, numThreeTwoFlips);	// Use the number of ThreeTwo Flips to determine how many old indicies need to be stored.
															// Updates numFreedTetra to incorperate tetra to be freed by flipping.
				
				uint[] flipOffsets = {_lastTetra, _lastFace, _lastEdge, _numFreedTetra, _numFreedFaces, _numFreedEdges };
				Rid bfFlipOffsets = toBuffer( flipOffsets );
				if( numThreeTwoFlips > 0 ){
					freeSimplices(numThreeTwoFlips, _bfActiveFaces, bfFlipInfo, bfBadFaces, bfBadFacesToThreeTwoFlip, bfFlipOffsets );
					debugLogAddLine( "freedTetra: " + singleToString( bfToUint( _bfFreedTetra, _numFreedTetra ) ) );
					debugLogAddLine( "freedFaces: " + singleToString( bfToUint( _bfFreedFaces, _numFreedFaces ) ) );
					debugLogAddLine( "freedEdges: " + singleToString( bfToUint( _bfFreedEdges, _numFreedEdges ) ) );
				}
				_rd.FreeRid( bfBadFacesToThreeTwoFlip );

				if(_numPointsRemaining > 0){ flipLocate( bfTetraMarkedFlip, _bfActiveFaces, bfFlipInfo, bfBadFaces, bfFlipPrefixSum, bfThreeTwoAtFlip, bfFlipOffsets); }

				_rd.FreeRid( bfTetraMarkedFlip );
				_rd.FreeRid( bfFlipPrefixSum );

				activeFacesSize = _numFaces;
				Rid bfNewActiveFaces = newBuffer( activeFacesSize ); zeroFill(bfNewActiveFaces, activeFacesSize );
				flipTetra(numFlips, _bfActiveFaces, bfFlipInfo, bfBadFaces, bfBadFacesToFlip, bfThreeTwoAtFlip, bfNewActiveFaces, bfFlipOffsets );
				_rd.FreeRid( bfFlipInfo ); _rd.FreeRid( bfBadFaces ); _rd.FreeRid( bfBadFacesToFlip );
				_rd.FreeRid( bfThreeTwoAtFlip ); _rd.FreeRid( bfFlipOffsets );

				// Update memory management info.
				uint netTetraFromFlip = 1 * ( numTwoThreeFlips - numThreeTwoFlips ); _numTetra += netTetraFromFlip;
				uint netFacesFromFlip = 2 * ( numTwoThreeFlips - numThreeTwoFlips ); _numFaces += netFacesFromFlip;
				uint netEdgesFromFlip = 1 * ( numTwoThreeFlips - numThreeTwoFlips ); _numEdges += netEdgesFromFlip;

				uint newTetraFromFlip = 1 * numTwoThreeFlips;
				uint newFacesFromFlip = 2 * numTwoThreeFlips;
				uint newEdgesFromFlip = 1 * numTwoThreeFlips;
				if( newTetraFromFlip > _numFreedTetra ){ _numFreedTetra = 0; _lastTetra = _numTetra - 1; } else { _numFreedTetra -= newTetraFromFlip; } // We added the simplices removed to freedSimplex already.
				if( newFacesFromFlip > _numFreedFaces ){ _numFreedFaces = 0;  _lastFace = _numFaces - 1; } else { _numFreedFaces -= newFacesFromFlip; } // The last tetra doesn't change unless we add simplicies exceeding the number of freedSimplices.
				if( newEdgesFromFlip > _numFreedEdges ){ _numFreedEdges = 0;  _lastEdge = _numEdges - 1; } else { _numFreedEdges -= newEdgesFromFlip; }

				if( DEBUG_COMPLEX ){
					debugLogAddLine( "----------------------------- Flip! -----------------------------" );
					debugLogAddLine( "# flips: " + numFlips + " # tetra: " + _numTetra + " # face: " + _numFaces + " # edge: " + _numEdges );
					debugLogAddLine( "bfTetra:              " + quadrupletToString( bfToUint( _bfTetra, 4 * (_lastTetra + 1) ) ) );
					debugLogAddLine( "bfTetraToFace:        " + quadrupletToString( bfToUint( _bfTetraToFace, 4 * (_lastTetra + 1) ) ) );
					debugLogAddLine( "bfTetraToEdge:        " + quadrupletToString( bfToUint( _bfTetraToEdge, 6 * (_lastTetra + 1) ) ) );
					debugLogAddLine( "bfFace:               " + tripletToString( bfToUint( _bfFace, 3 * (_lastFace + 1) ) ) );
					debugLogAddLine( "bfFaceToTetra:        " + doubletToString( bfToUint( _bfFaceToTetra, 2 * (_lastFace + 1) ) ) );
					debugLogAddLine( "bfEdge:               " + doubletToString( bfToUint( _bfEdge, 2 * (_lastEdge + 1) ) ) );
				}

				if( DEBUG_COMPLEX ){
				debugLogAddLine( "New buffer sizes: bftetra = " + _bfTetraSize +  ", bfFace = " + _bfFaceSize + ", bfEdge = " + _bfEdgeSize );
				debugLogAddLine( "Using these numFreedtetra = " + _numFreedTetra + ", numFreedFace = " + _numFreedFaces + ", numFreedEdge = " + _numFreedEdges );
				debugLogAddLine( "FreedTetra: " + singleToString( bfToUint( _bfFreedTetra, _numFreedTetra ) ) );
				debugLogAddLine( "FreedFaces: " + singleToString( bfToUint( _bfFreedFaces, _numFreedFaces ) ) );
				debugLogAddLine( "FreedEdges: " + singleToString( bfToUint( _bfFreedEdges, _numFreedEdges ) ) );
				}

				if( DEBUG ){
					DEBUG_STRING += ", (" + _numTetra + ", " + _numFaces + ", " + _numEdges + ") "  + " | ";
				}

				_rd.FreeRid( _bfActiveFaces ); _bfActiveFaces = bfNewActiveFaces;

				if(DEBUG_COMPLEX){
					debugLogAddLine( "(mark) bfActiveFaces:          " + singleToString( bfToUint( _bfActiveFaces, activeFacesSize ) ) );
				}
				numActiveFaces = compactActiveFaces( activeFacesSize );
				if( DEBUG_COMPLEX ){
					debugLogAddLine( "#active: " + numActiveFaces + " (cpct) bfActiveFaces:" + singleToString( bfToUint( _bfActiveFaces, numActiveFaces ) ) );
				}
			}

			if( DEBUG ){
				debugLogAddLine( DEBUG_STRING );
			}


			_rd.FreeRid( _bfActiveFaces );

			// if(splitLoopCounter == 4 ){ break; }

		}

		// TODO: This would be a good place to remove the initial simplex from the complex also.
		compactComplex();

		sortFacesDelauney();

		if( DEBUG_COMPLEX ){
					debugLogAddLine( "----------------------------- Final! -----------------------------" );
					debugLogAddLine( "# tetra: " + _numTetra + " # face: " + _numFaces + " # edge: " + _numEdges );
					debugLogAddLine( "bfTetra:              " + quadrupletToString( bfToUint( _bfTetra, 4 * _numTetra ) ) );
					debugLogAddLine( "bfTetraToFace:        " + quadrupletToString( bfToUint( _bfTetraToFace, 4 * _numTetra ) ) );
					debugLogAddLine( "bfTetraToEdge:        " + quadrupletToString( bfToUint( _bfTetraToEdge, 6 * _numTetra ) ) );
					debugLogAddLine( "bfFace:               " + tripletToString( bfToUint( _bfFace, 3 * _numFaces ) ) );
					debugLogAddLine( "bfFaceToTetra:        " + doubletToString( bfToUint( _bfFaceToTetra, 2 * _numFaces ) ) );
					debugLogAddLine( "bfEdge:               " + doubletToString( bfToUint( _bfEdge, 2 * _numEdges ) ) );
				}

		debugLogFlush();

		return 1;
	}

	private void DetermineSplit( Rid bfTetraIsSplitBy, Rid bfPointsIsSplitting ){
		Rid bfCircDistance = newBuffer( _numPointsRemaining );
		checkDistance( bfTetraIsSplitBy, bfCircDistance );

		checkDistanceMinimal( bfTetraIsSplitBy, bfCircDistance ); _rd.FreeRid( bfCircDistance );

		markSplittingPoint( bfTetraIsSplitBy, bfPointsIsSplitting );
	}
	

	private void UpdatePointsRemaining( uint numSplitTetra, Rid bfPointIsSplitting, Rid bfTetraToSplit, Rid bfOffset){
		
		if( DEBUG_COMPLEX ){
			debugLogAddLine( "------------ compacting pointsToAdd! ------------" );
			debugLogAddLine( "bfPointsToAdd:          " + singleToString( bfToUint( _bfPointsToAdd , _numPointsRemaining) ) );
			debugLogAddLine( "bfPointIsSplitting:     " + singleToString( bfToUint( bfPointIsSplitting , _numPointsRemaining) ) );
		}

		// Compact remaining points in a kernel
		compactPointsRemaining( bfPointIsSplitting );
		_numPointsRemaining -= numSplitTetra;

		if( DEBUG_COMPLEX ){
			debugLogAddLine( "New bfPointsToAdd:      " + singleToString( bfToUint( _bfPointsToAdd , _numPointsRemaining) ) );
		}

		// Attempt to relocate every point in the split tetra, using a fast but inexact method.
		// This method is particularly bad around the coordinate axis, so we should expect it
		// to perform poorly on the first few iterations.
		Rid bfLocations = relocatePointsFast( bfTetraToSplit, bfOffset);

		if( DEBUG_COMPLEX ){
			debugLogAddLine( "New TetOfPoints:        " + singleToString( bfToUint( _bfTetraOfPoints, _numPointsRemaining) ) );
			
			uint[] locations = bfToUint( bfLocations, _numPointsRemaining);
			String locationsString = "[ " + System.Environment.NewLine;
			for(uint i = 0; i < locations.Length; i++){
				if( !(i == 0) ){ locationsString += ", " + System.Environment.NewLine; }
				String base3Expansion = "";
				uint j = 0;
				while( j <= 6 ){
					base3Expansion = ( (uint)(( locations[i] >> 1 ) % uintPow(3, j + 1)  / uintPow(3, j))  ).ToString() + "*3^" + j + " " + base3Expansion;
					j++;
				}
				locationsString += "bad: " + (locations[i] & 1) + " exp: " + base3Expansion;
			}
			locationsString += System.Environment.NewLine + " ]";

			debugLogAddLine( "bfLocations:        " + locationsString );
		}

		// Call points that could not be located quickly bad points. We compact them here.
		Rid bfBadPoints = newBuffer(_numPointsRemaining);
		uint numBadPoints = compactBadPoints( bfLocations, bfBadPoints);

		if( DEBUG_COMPLEX ){
			debugLogAddLine( "#bad: " + numBadPoints + " bfBadPoints:" + singleToString( bfToUint( bfBadPoints, numBadPoints) ) );
		}

		if( numBadPoints > 0){
			// For all the points that fail the fast check, if any, run the memory intensive exact check.
			relocatePointsExact( bfBadPoints, bfLocations, bfTetraToSplit, bfOffset, numBadPoints );

			if( DEBUG_COMPLEX ){
			uint[] locations = bfToUint( bfLocations, _numPointsRemaining);
			String locationsString = "[ " + System.Environment.NewLine;
			for(uint i = 0; i < locations.Length; i++){
				if( !(i == 0) ){ locationsString += ", " + System.Environment.NewLine; }
				String base3Expansion = "";
				uint j = 0;
				while( j <= 6 ){
					base3Expansion = ( (uint)(( locations[i] >> 1 ) % uintPow(3, j + 1)  / uintPow(3, j))  ).ToString() + "*3^" + j + " " + base3Expansion;
					j++;
				}
				locationsString += "bad: " + (locations[i] & 1) + " exp: " + base3Expansion;
			}
			locationsString += System.Environment.NewLine + " ]";

			debugLogAddLine( "new bfLocations:    " + locationsString );
			}
			
			_rd.FreeRid( bfLocations ); _rd.FreeRid( bfBadPoints );
		}

		if( DEBUG_COMPLEX ){
			debugLogAddLine( "Final TetOfPoints:  " + singleToString( bfToUint( _bfTetraOfPoints, _numPointsRemaining) ) );
		}
	}


	private void checkLocalDelaunay( uint numActiveFaces, Rid bfActiveFaces, Rid bfFlipInfo ){
		checkLocalDelaunayFast( numActiveFaces, bfActiveFaces, bfFlipInfo );
		Rid bfIndetrmndFaces = newBuffer( numActiveFaces );
		uint numIndetrmndFaces = compactIndeterminedFaces( numActiveFaces,  bfFlipInfo, bfIndetrmndFaces);

		if(DEBUG_COMPLEX){
				debugLogAddLine( "                    bfFlipInfo: " + singleToString( bfToUint( bfFlipInfo, numActiveFaces ) ) );
				debugLogAddLine( "#indtrmnd: " + numIndetrmndFaces + "  bfIndetrmndFaces: " + singleToString( bfToUint( bfIndetrmndFaces, numIndetrmndFaces ) ) );
		}
		
		if( numIndetrmndFaces > 0 ){
			checkLocalDelaunayAdapt( numIndetrmndFaces, bfActiveFaces, bfFlipInfo, bfIndetrmndFaces);
			numIndetrmndFaces = compactIndeterminedFaces( numActiveFaces,  bfFlipInfo, bfIndetrmndFaces);

			if(DEBUG_COMPLEX){
				debugLogAddLine( "                    bfFlipInfo: " + singleToString( bfToUint( bfFlipInfo, numActiveFaces ) ) );
				debugLogAddLine( "#indtrmnd: " + numIndetrmndFaces + " bfIndetrmndFaces: " + singleToString( bfToUint( bfIndetrmndFaces, numIndetrmndFaces ) ) );
			}
			
			if( numIndetrmndFaces > 0 ){
				checkLocalDelaunayExact( numIndetrmndFaces, bfActiveFaces, bfFlipInfo, bfIndetrmndFaces);
			}
		}
		_rd.FreeRid( bfIndetrmndFaces );
	}


	private void determineFlips( uint numbadFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces ){

		// ------ First we check the convexity condition. ------
		// fast check
		checkConvexFast( numbadFaces, bfActiveFaces, bfFlipInfo, bfBadFaces); //Here is where we implicitly overwrite flipInfo, pairing it to badFaces.

		if(DEBUG_COMPLEX){
				debugLogAddLine( "                          bfFlipInfo: " + singleToString( bfToByte( bfFlipInfo, numbadFaces ) ) );
		}

		// compact indeterminant faces
		Rid bfIndeterminedConvexity = newBuffer( numbadFaces ); // TODO: optionally reuse this buffer for indetermined TwoThree
		uint numIndeterminedConvexity = compactIndeterminedConvexity( numbadFaces, bfFlipInfo, bfIndeterminedConvexity);

		if(DEBUG_COMPLEX){
				debugLogAddLine( "                          bfFlipInfo: " + singleToString( bfToByte( bfFlipInfo, numbadFaces ) ) );
				debugLogAddLine( "#indtrmnd: " + numIndeterminedConvexity + " bfIndeterminedConvexity: " + singleToString( bfToUint( bfIndeterminedConvexity, numIndeterminedConvexity ) ) );
		}

		// exact check
		if(numIndeterminedConvexity > 0){
			checkConvexExact( numbadFaces, bfIndeterminedConvexity, bfActiveFaces, bfFlipInfo, bfBadFaces);
		}

		if(DEBUG_COMPLEX){
			debugLogAddLine( "      finalized convexity bfFlipInfo: " + singleToString( bfToByte( bfFlipInfo, numbadFaces ) ) );
		}

		_rd.FreeRid( bfIndeterminedConvexity );

		// ------ For those faces that fail the convexity condition, check for a 3-2 flip ------
		Rid bfNonconvexBadFaces = newBuffer(numbadFaces); // contains indexes of badfaces.
		uint numNonconvexBadFaces = compactNonconvexFaceStar( numbadFaces, bfFlipInfo, bfNonconvexBadFaces);

		if(DEBUG_COMPLEX){
			debugLogAddLine( "#nonCvx: " + numNonconvexBadFaces + "       bfNonconvexBadFaces: " + singleToString( bfToUint( bfNonconvexBadFaces, numNonconvexBadFaces ) ) );
		}

		if(numNonconvexBadFaces > 0){
			checkThreeTwoFast( numNonconvexBadFaces, bfActiveFaces, bfFlipInfo, bfBadFaces, bfNonconvexBadFaces );

			if(DEBUG_COMPLEX){
				debugLogAddLine( "                 ThreeTwo bfFlipInfo: " + singleToString( bfToByte( bfFlipInfo, numbadFaces ) ) );
			}

			Rid bfIndeterminedBadFaceThreeTwo = newBuffer( numNonconvexBadFaces ); // Contains the active faces that need an exact check.
			uint numIndeterminedBadFacesThreeTwo = compactIndeterminedThreeTwo( numNonconvexBadFaces, bfFlipInfo, bfNonconvexBadFaces, bfIndeterminedBadFaceThreeTwo);
			
			if(DEBUG_COMPLEX){
				debugLogAddLine( "#indtrmnd: " + numIndeterminedBadFacesThreeTwo + " IndtrmndBadFaceThreeTwo: " + singleToString( bfToUint( bfIndeterminedBadFaceThreeTwo, numIndeterminedBadFacesThreeTwo ) ) );
			}

			_rd.FreeRid( bfNonconvexBadFaces );

			if( numIndeterminedBadFacesThreeTwo > 0 ){
				// run exact check
				checkThreeTwoExact( numIndeterminedBadFacesThreeTwo, bfActiveFaces, bfFlipInfo, bfBadFaces, bfIndeterminedBadFaceThreeTwo );
			}

			if(DEBUG_COMPLEX){
				debugLogAddLine( "           Final ThreeTwo bfFlipInfo: " + singleToString( bfToByte( bfFlipInfo, numbadFaces ) ) );
			}

			_rd.FreeRid( bfIndeterminedBadFaceThreeTwo );
		}
	}


	private void pickFlips( uint numbadFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfTetraMarkFlip){
		// For each badFace, if it's flipping mark the tetrahedron involved with the flip.
		markFlipOfTetra( numbadFaces, bfActiveFaces, bfFlipInfo, bfBadFaces, bfTetraMarkFlip );
		checkFlipOfTetra( numbadFaces, bfActiveFaces, bfFlipInfo, bfBadFaces, bfTetraMarkFlip );
	}


	private void flipLocate( Rid bfTetraMarkedFlip, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfFlipPrefixSum , Rid bfThreeTwoAtFlip, Rid bfFlipOffsets){ //TODO: there are bugs here.
		if(DEBUG_COMPLEX){
			debugLogAddLine( "---- relocating point in tetra involved in a flip: " );
		}

		Rid bfPointInFlipSum = newBuffer( _numPointsRemaining ); zeroFill(bfPointInFlipSum, _numPointsRemaining);
		Rid bfPointsInFlips = newBuffer( _numPointsRemaining );

		pointInFlipMark( bfTetraMarkedFlip, bfFlipInfo, bfPointInFlipSum);

		if(DEBUG_COMPLEX){
			debugLogAddLine( "pointsToAdd:      "  + singleToString( bfToUint( _bfPointsToAdd , _numPointsRemaining) ) );
			debugLogAddLine( "tetraOfPoint:     "  + singleToString( bfToUint( _bfTetraOfPoints , _numPointsRemaining) ) );
			debugLogAddLine( "PointInFlipMark:  "  + singleToString( bfToUint( bfPointInFlipSum , _numPointsRemaining) ) );
		}

		PFS_SklanskyInclusive( _numPointsRemaining, 0, bfPointInFlipSum);

		if(DEBUG_COMPLEX){
			debugLogAddLine( "PointInFlipSum:   "  + singleToString( bfToUint( bfPointInFlipSum , _numPointsRemaining) ) );
		}

		pointInFlipWrite( bfTetraMarkedFlip, bfFlipInfo, bfPointInFlipSum, bfPointsInFlips);
		uint numPointsInFlips = nthPlaceOfBuffer(_numPointsRemaining - 1, bfPointInFlipSum);

		if(DEBUG_COMPLEX){
			debugLogAddLine( numPointsInFlips + " PointsInFlips:  "  + singleToString( bfToUint( bfPointsInFlips , numPointsInFlips) ) );
		}

		_rd.FreeRid( bfPointInFlipSum );

		if(numPointsInFlips > 0 ){
			if(DEBUG_COMPLEX){
				debugLogAddLine( "--------------- relocating ---------------");
			}

			if(DEBUG_COMPLEX){
				debugLogAddLine( "(old) pointsToAdd: "  + singleToString( bfToUint( _bfPointsToAdd , _numPointsRemaining) ) );
			}

			Rid bfLocations = newBuffer(numPointsInFlips); zeroFill(bfLocations, numPointsInFlips);
			locatePointInFlipFast( numPointsInFlips, bfPointsInFlips, bfTetraMarkedFlip, bfLocations, bfActiveFaces, bfFlipInfo, bfBadFaces, bfFlipPrefixSum, bfThreeTwoAtFlip, bfFlipOffsets );

			Rid bfBadPoints = newBuffer(_numPointsRemaining);
			uint numBadPoints = compactBadPoints( bfLocations, bfBadPoints);

			if(DEBUG_COMPLEX){
				debugLogAddLine( " new tetraOfPoint: "  + singleToString( bfToUint( _bfTetraOfPoints , _numPointsRemaining) ) );
				debugLogAddLine( "#bad " + numBadPoints + " bfBadPoints:"  + singleToString( bfToUint( bfBadPoints , numBadPoints) ) );
			}

			if( numBadPoints > 0 ){
				locatePointInFlipExact( numBadPoints, bfBadPoints, bfPointsInFlips, bfTetraMarkedFlip, bfLocations, bfActiveFaces, bfFlipInfo, bfBadFaces, bfFlipPrefixSum, bfThreeTwoAtFlip, bfFlipOffsets );
			}

			if(DEBUG_COMPLEX){
				debugLogAddLine( "(old) pointsToAdd: "  + singleToString( bfToUint( _bfPointsToAdd , _numPointsRemaining) ) );
				debugLogAddLine( " new tetraOfPoint: "  + singleToString( bfToUint( _bfTetraOfPoints , _numPointsRemaining) ) );
			}
			
			_rd.FreeRid( bfLocations );
			_rd.FreeRid( bfBadPoints );
		}

		_rd.FreeRid( bfPointsInFlips );		
	}

	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                                         Compaction                                                        */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */
	
	private Rid compactSplit( Rid bfTetraIsSplitBy, Rid bfSplittingTetraSum, Rid bfSplittingTetra){ // TODO: tetToSplit probably should be renamed to splitOfTetra. It's a correspondance, not a list of tetra as the name might imply.
		// use positive mark on bfTetraIsSplitBy, length _numTetra, to compact bfTetraIsSplitBy and ID
		uintNonmaxMark( _lastTetra + 1, bfTetraIsSplitBy, bfSplittingTetraSum );

		PFS_SklanskyInclusive( _lastTetra + 1, 0, bfSplittingTetraSum);

		Rid bfCompactTetraIsSplitBy = newBuffer( _lastTetra + 1 );
		uintNonmaxWriteSelf(_lastTetra + 1, bfTetraIsSplitBy, bfSplittingTetraSum, bfCompactTetraIsSplitBy );
		uintNonmaxWriteID(_lastTetra + 1, bfTetraIsSplitBy, bfSplittingTetraSum, bfSplittingTetra); // SOMETHING IS WRONG WITH TETRA TO SPLIT!!??? FIX MEEEEE!!!!
		
		_rd.FreeRid(bfTetraIsSplitBy);
		return bfCompactTetraIsSplitBy; // resolves to: bfTetraIsSplitBy = bfCpctTetraIsSplitBy
	}

	private void compactPointsRemaining(Rid bfPointIsSplitting){ //working
		// use nonpositive mark on bfPointsIsSplitting, length _numPointsRemaining, to compact _bfPointsToAdd and _bfTetraOfPoints
		Rid bfPrefixSum = newBuffer( _numPointsRemaining );

		uintNonpositiveMark(_numPointsRemaining, bfPointIsSplitting, bfPrefixSum);
		PFS_SklanskyInclusive(_numPointsRemaining, 0, bfPrefixSum);

		if( DEBUG_COMPLEX ){
				debugLogAddLine( "bfPrefixSum:            "  + singleToString( bfToUint( bfPrefixSum , _numPointsRemaining) ) );
		}

		Rid bfCompactPointsToAdd 	= newBuffer(_numPointsRemaining);
		Rid bfCompactTetraOfPoints	= newBuffer(_numPointsRemaining);

		uintNonpositiveWriteOther( _numPointsRemaining, bfPointIsSplitting, _bfPointsToAdd, bfPrefixSum, bfCompactPointsToAdd);
		uintNonpositiveWriteOther( _numPointsRemaining, bfPointIsSplitting, _bfTetraOfPoints, bfPrefixSum, bfCompactTetraOfPoints);

		//if( DEBUG ){
		//		debugLogAddLine( "bfCompactPointsToAdd:        "  + singleToString( bfToUint( bfCompactPointsToAdd , _numPointsRemaining) ) );
		//		debugLogAddLine( "bfCompactTetraOfPoints:      "  + singleToString( bfToUint( bfCompactTetraOfPoints , _numPointsRemaining) ) );
		//}

		_rd.FreeRid(_bfPointsToAdd); _rd.FreeRid(_bfTetraOfPoints); _rd.FreeRid(bfPrefixSum);

		_bfPointsToAdd = bfCompactPointsToAdd;
		_bfTetraOfPoints = bfCompactTetraOfPoints;

		return;
	}

	private uint compactBadPoints( Rid bfLocations, Rid bfBadPoints ){
		// use bitewiseMark, n = 0, on bfLocations, length _numPointsRemaining, to compact ID
		Rid bfPrefixSum = newBuffer( _numPointsRemaining );

		uintBitwiseMark(_numPointsRemaining, 0, bfLocations, bfPrefixSum);
		PFS_SklanskyInclusive(_numPointsRemaining, 0, bfPrefixSum);

		uintBitwiseWriteID(_numPointsRemaining, 0, bfLocations, bfPrefixSum, bfBadPoints);

		uint numBadPoints = nthPlaceOfBuffer(_numPointsRemaining - 1, bfPrefixSum);
		_rd.FreeRid(bfPrefixSum);
		return numBadPoints;
	}

	private uint compactActiveFaces( uint activeFacesSize){
		// ActiveFaces is a mark already. We just need to copy it, length activeFacesSize. Use this mark to compact ID.
		Rid bfPrefixSum = newBuffer( activeFacesSize ); copyFill( _bfActiveFaces, bfPrefixSum, activeFacesSize );
		PFS_SklanskyInclusive(activeFacesSize, 0, bfPrefixSum);

		if(DEBUG_COMPLEX){
				debugLogAddLine( "bfPrefixSum:                    " + singleToString( bfToUint( bfPrefixSum, activeFacesSize ) ) );
		}

		Rid bfCompactActiveFaces = newBuffer( activeFacesSize );
		// We are really just looking for the mark of activeFaces to be 1.
		uintPositiveWriteID( activeFacesSize, _bfActiveFaces, bfPrefixSum, bfCompactActiveFaces);

		uint numActiveFaces = nthPlaceOfBuffer(activeFacesSize - 1, bfPrefixSum);
		_rd.FreeRid(_bfActiveFaces); _rd.FreeRid(bfPrefixSum);
		_bfActiveFaces = bfCompactActiveFaces;

		return numActiveFaces;
	}

	private uint compactIndeterminedFaces( uint numActiveFaces, Rid bfFlipInfo, Rid bfIndetrmndFaces ){
		// use bitwise mark n = 1 on bfFlipInfo, length numActiveFaces, to compact ID
		Rid bfPrefixSum = newBuffer( numActiveFaces );
		uintBitwiseMark(numActiveFaces, 1, bfFlipInfo, bfPrefixSum);

		PFS_SklanskyInclusive(numActiveFaces, 0, bfPrefixSum);
		uintBitwiseWriteID(numActiveFaces, 1, bfFlipInfo, bfPrefixSum, bfIndetrmndFaces);

		uint numIndetrmndFaces = nthPlaceOfBuffer(numActiveFaces - 1, bfPrefixSum);
		_rd.FreeRid(bfPrefixSum);
		return numIndetrmndFaces;
	}

	private uint CompactBadFaces( uint numActiveFaces, Rid bfFlipInfo, Rid bfBadFaces ){
		// use bitwise mark n = 0 on bfFlipInfo, length numActiveFaces, to compact ID
		Rid bfPrefixSum = newBuffer( numActiveFaces );
		uintBitwiseMark(numActiveFaces, 0, bfFlipInfo, bfPrefixSum);
		
		PFS_SklanskyInclusive(numActiveFaces, 0, bfPrefixSum);
		uintBitwiseWriteID(numActiveFaces, 0, bfFlipInfo, bfPrefixSum, bfBadFaces);

		uint numBadFaces = nthPlaceOfBuffer(numActiveFaces - 1, bfPrefixSum);
		_rd.FreeRid(bfPrefixSum);
		return numBadFaces;
	}

	private uint compactIndeterminedConvexity( uint numbadFaces, Rid bfFlipInfo, Rid bfIndeterminedConvexity){
		// use uintTripleBitwiseMark n = 0 on bfFlipInfo, length numBadFaces, to compact ID
		Rid bfPrefixSum = newBuffer( numbadFaces );
		uintTripleBitwiseMark(numbadFaces, 0, bfFlipInfo, bfPrefixSum);
		PFS_SklanskyInclusive(numbadFaces, 0, bfPrefixSum);
		uintTripleBitwiseWriteID(numbadFaces, 0, bfFlipInfo, bfPrefixSum, bfIndeterminedConvexity);

		uint numIndeterminedFaces = nthPlaceOfBuffer(numbadFaces - 1, bfPrefixSum);
		_rd.FreeRid(bfPrefixSum);
		return numIndeterminedFaces;
	}


	private uint compactNonconvexFaceStar( uint numbadFaces, Rid bfFlipInfo, Rid bfNonconvexBadFaces){
		// use uintBitwiseMark n = 6 on bfFlipInfo, length numBadFaces, to compact ID
		Rid bfPrefixSum = newBuffer( numbadFaces );
		uintBitwiseMark(numbadFaces, 6, bfFlipInfo, bfPrefixSum);
		PFS_SklanskyInclusive(numbadFaces, 0, bfPrefixSum);
		uintBitwiseWriteID(numbadFaces, 6, bfFlipInfo, bfPrefixSum, bfNonconvexBadFaces);

		uint numNonconvexBadFaces = nthPlaceOfBuffer(numbadFaces - 1, bfPrefixSum);
		_rd.FreeRid(bfPrefixSum);
		return numNonconvexBadFaces;
	}

	private uint compactIndeterminedThreeTwo( uint numNonconvexBadFaces, Rid bfFlipInfo, Rid bfNonconvexBadFaces, Rid bfIndeterminedTwoThree){ // TODO: fix 
		// use uintTripleBitwiseMark n = 0 on bfFlipInfo, length numNonconvexBadFaces, to compact ID

		Rid bfPrefixSum = newBuffer( numNonconvexBadFaces );
		uintTripleBitwiseMarkAt(numNonconvexBadFaces, 0, bfFlipInfo, bfNonconvexBadFaces, bfPrefixSum);
		PFS_SklanskyInclusive(numNonconvexBadFaces, 0, bfPrefixSum);
		uintTripleBitwiseWriteAtIDAt(numNonconvexBadFaces, 0, bfFlipInfo, bfNonconvexBadFaces, bfPrefixSum, bfIndeterminedTwoThree);

		uint numIndeterminedTwoThree = nthPlaceOfBuffer(numNonconvexBadFaces - 1, bfPrefixSum);
		_rd.FreeRid(bfPrefixSum);
		return numIndeterminedTwoThree;
	}

	private uint[] compactFlips(uint numbadFaces, Rid bfFlipInfo, Rid bfFlipPrefixSum, Rid bfBadFacesToFlip, Rid bfThreeTwoBeforeFlip, Rid bfBadFacesToThreeTwoFlip){
		// Use uintTripleBitwiseMark n = 3 on bfFlipInfo, length numBadFaces, to compact ID in bfBadFacesToThreeTwoFlip.
		// Then use uintBitwiseMark n = 13 on bfFlipInfo, length numBadFaces, to compact ID in bfBadFacesToFlip, and compact the first prefix sum to bfThreeTwoBeforeFlip.

		Rid bfThreeTwoPrefixSum = newBuffer( numbadFaces );
		uintTripleBitwiseMark(numbadFaces, 3, bfFlipInfo, bfThreeTwoPrefixSum);
		PFS_SklanskyInclusive(numbadFaces, 0, bfThreeTwoPrefixSum);
		uintTripleBitwiseWriteID(numbadFaces, 3, bfFlipInfo, bfThreeTwoPrefixSum, bfBadFacesToThreeTwoFlip);

		if(DEBUG_COMPLEX){
				debugLogAddLine( "bfFirstPrefixSum (3-2):            " + singleToString( bfToUint( bfThreeTwoPrefixSum, numbadFaces ) ) );
		}

		uintBitwiseMark(numbadFaces, 13, bfFlipInfo, bfFlipPrefixSum);
		PFS_SklanskyInclusive(numbadFaces, 0, bfFlipPrefixSum);	
		uintBitwiseWriteID(numbadFaces, 13, bfFlipInfo, bfFlipPrefixSum, bfBadFacesToFlip);
		uintBitwiseWriteOther(numbadFaces, 13, bfFlipInfo, bfThreeTwoPrefixSum, bfFlipPrefixSum, bfThreeTwoBeforeFlip);

		uint numThreeTwo = nthPlaceOfBuffer(numbadFaces - 1, bfThreeTwoPrefixSum);
		uint numFlips = nthPlaceOfBuffer(numbadFaces - 1, bfFlipPrefixSum);

		_rd.FreeRid(bfThreeTwoPrefixSum); 

		uint[] counts = new uint[2];
		counts[0] = numFlips; counts[1] = numThreeTwo;
		return counts;
	}


	private void compactComplex(){
		Rid bfCompactTetra;
		Rid bfCompactTetraToFace;
		Rid bfCompactTetraToEdge;

		if( _numFreedTetra > 0 ){
			Rid bfMarkedTetra = newBuffer( _lastTetra + 1 ); constFill(bfMarkedTetra, _lastTetra + 1, 1);
			uintAtUnMark( _numFreedTetra, _bfFreedTetra, bfMarkedTetra);
			Rid bfTetraSum = newBuffer( _lastTetra + 1 ); copyFill(bfMarkedTetra, bfTetraSum, _lastTetra + 1);
			PFS_SklanskyInclusive( _lastTetra + 1, 0, bfTetraSum);

			bfCompactTetra 			= newBuffer( 4 * (_lastTetra + 1 - _numFreedTetra) ); // The term on the right should agree with _numTetra.
			bfCompactTetraToFace 	= newBuffer( 4 * (_lastTetra + 1 - _numFreedTetra) );
			bfCompactTetraToEdge 	= newBuffer( 6 * (_lastTetra + 1 - _numFreedTetra) );
			quadrupletPositiveWriteOther( _lastTetra + 1, bfMarkedTetra, _bfTetra, 			bfTetraSum, bfCompactTetra);
			quadrupletPositiveWriteOther( _lastTetra + 1, bfMarkedTetra, _bfTetraToFace, 	bfTetraSum, bfCompactTetraToFace);
			sixtupletPositiveWriteOther(  _lastTetra + 1, bfMarkedTetra, _bfTetraToEdge, 	bfTetraSum, bfCompactTetraToEdge);
			_rd.FreeRid(bfMarkedTetra);

			_rd.FreeRid( _bfTetra ); _rd.FreeRid( _bfTetraToFace ); _rd.FreeRid( _bfTetraToEdge );
			_bfTetra = bfCompactTetra; _bfTetraToFace = bfCompactTetraToFace; _bfTetraToEdge = bfCompactTetraToEdge;
			
			// We update the indices of the tetra _before_ we compact the tetra to face buffer!
			updateCompactedIndex( 2 * ( _lastFace + 1 ), _bfFaceToTetra, bfTetraSum );
			_rd.FreeRid(bfTetraSum);
		}
		
		if( _numFreedFaces > 0 ){
			Rid bfMarkedFace = newBuffer( _lastFace + 1 ); constFill(bfMarkedFace, _lastFace + 1, 1);
			uintAtUnMark( _numFreedFaces, _bfFreedFaces, bfMarkedFace);
			Rid bfFaceSum = newBuffer( _lastFace + 1 ); copyFill(bfMarkedFace, bfFaceSum, _lastFace + 1);
			PFS_SklanskyInclusive( _lastFace + 1, 0, bfFaceSum);

			Rid bfCompactFace 			= newBuffer( 3 * _numFaces ); //(_lastFace + 1 - _numFreedFaces) ); // The term on the right should agree with _numFaces.
			Rid bfCompactFaceToTetra 	= newBuffer( 2 * _numFaces ); //(_lastFace + 1 - _numFreedFaces) );
			tripletPositiveWriteOther( _lastFace + 1, bfMarkedFace, _bfFace, 			bfFaceSum, bfCompactFace);
			dubletPositiveWriteOther(  _lastFace + 1, bfMarkedFace, _bfFaceToTetra, 	bfFaceSum, bfCompactFaceToTetra);
			_rd.FreeRid( bfMarkedFace );

			_rd.FreeRid( _bfFace ); _rd.FreeRid( _bfFaceToTetra );
			_bfFace = bfCompactFace; _bfFaceToTetra = bfCompactFaceToTetra;

			// Tetra should be compacted, so I'm free to update the indices.
			updateCompactedIndex( 4 * _numTetra, _bfTetraToFace, bfFaceSum );
			_rd.FreeRid( bfFaceSum );
		}
		
		if( _numFreedEdges > 0 ){
			Rid bfMarkedEdge = newBuffer( _lastEdge + 1 ); constFill(bfMarkedEdge, _lastEdge + 1, 1);
			uintAtUnMark( _numFreedEdges, _bfFreedEdges, bfMarkedEdge);
			Rid bfEdgeSum = newBuffer( _lastEdge + 1 ); copyFill(bfMarkedEdge, bfEdgeSum, _lastEdge + 1);
			PFS_SklanskyInclusive( _lastEdge + 1, 0, bfEdgeSum);

			Rid bfCompactEdge 			= newBuffer( 2 * (_lastEdge + 1 - _numFreedEdges) ); // The term on the right should agree with _numEdges.
			dubletPositiveWriteOther(  _lastEdge + 1, bfMarkedEdge, _bfEdge, bfEdgeSum, bfCompactEdge);
			_rd.FreeRid( bfMarkedEdge );

			_rd.FreeRid( _bfEdge );
			_bfEdge = bfCompactEdge;
			
			// Tetra should be compacted, so I'm free to update the indices.
			updateCompactedIndex( 6 * _numTetra, _bfTetraToEdge, bfEdgeSum );
			_rd.FreeRid( bfEdgeSum );
		}
	
	}

	private void sortFacesDelauney(){
		Rid bfFaceInfo = newBuffer( _numFaces - 4 ); // I'm assuming that the complex is compacted.
		Rid bfAllFaces = newBuffer( _numFaces - 4 ); incrementalFill(bfAllFaces, _numFaces, 4);
		checkLocalDelaunay( _numFaces - 4, bfAllFaces, bfFaceInfo);

		Rid bfIsDelauneySum = newBuffer( _numFaces - 4 ); uintNonpositiveMark( _numFaces - 4, bfFaceInfo, bfIsDelauneySum);
		Rid bfIsNotDelauneySum = newBuffer( _numFaces - 4 ); uintPositiveMark( _numFaces - 4, bfFaceInfo, bfIsNotDelauneySum);

		PFS_SklanskyInclusive( _numFaces - 4, 0, bfIsDelauneySum);
		PFS_SklanskyInclusive( _numFaces - 4, 0, bfIsNotDelauneySum);

		_numDelauneyFaces = nthPlaceOfBuffer( _numFaces - 5, bfIsDelauneySum);
		_numNonDelauneyFaces = nthPlaceOfBuffer( _numFaces - 5, bfIsNotDelauneySum);

		GD.Print( "numDelauneyFaces: " + (_numDelauneyFaces + 4) + " numNonDelauneyFaces: " + _numNonDelauneyFaces );
		
		_bfDelauneyFaces = newBuffer( _numFaces - 4 );
		_bfNonDelauneyFaces = newBuffer( _numFaces - 4 );

		uintNonpositiveWriteOther( _numFaces - 4, bfFaceInfo, bfAllFaces, bfIsDelauneySum, _bfDelauneyFaces );
		uintPositiveWriteOther( _numFaces - 4, bfFaceInfo, bfAllFaces, bfIsNotDelauneySum, _bfNonDelauneyFaces );

		GD.Print( "bfDelauneyFaces: " + singleToString( bfToUint( _bfDelauneyFaces, _numDelauneyFaces ) ) );
		GD.Print( "bfNonDelauneyFaces: " + singleToString( bfToUint( _bfNonDelauneyFaces, _numNonDelauneyFaces ) ) );
	}

	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                                Memory And Buffer Management                                               */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */


	private void ExpandForSplit( uint numSplit ){ // TODO: when we copy we need to copy up to the last simplex, not to _numSimplex.
		uint newTetra = 3 * numSplit; // A tetra splits into 4 new tetra, but that means there are only 3 more tetra than before the split.
		uint newFaces = 6 * numSplit;
		uint newEdges = 4 * numSplit;

		// resize Tetra buffers, if needed. TODO: we could alternativly try to make a better guess about how muuch biggger the buffers need to get here.
		if( _bfTetraSize < _numTetra + newTetra ){
			uint moreTetra = _numTetra + newTetra; 
			Rid bfMoreTetra = _rd.StorageBufferCreate( moreTetra * 4 * 4 ); copyFill( _bfTetra, bfMoreTetra, _bfTetraSize * 4 * 4 ); 					// 4 indx/tet * 4 byte/indx
			_rd.FreeRid( _bfTetra ); _bfTetra = bfMoreTetra;
			Rid bfMoreTetraToFace = _rd.StorageBufferCreate( moreTetra * 4 * 4 ); copyFill( _bfTetraToFace, bfMoreTetraToFace, _bfTetraSize * 4 * 4 );	// 4 indx/tet * 4 byte/indx
			_rd.FreeRid( _bfTetraToFace ); _bfTetraToFace = bfMoreTetraToFace;
			Rid bfMoreTetraToEdge = _rd.StorageBufferCreate( moreTetra * 6 * 4 ); copyFill( _bfTetraToEdge, bfMoreTetraToEdge, _bfTetraSize * 6 * 4 );	// 6 indx/tet * 4 byte/indx
			_rd.FreeRid( _bfTetraToEdge ); _bfTetraToEdge = bfMoreTetraToEdge;
			_bfTetraSize = moreTetra;
		}
		// resize Face buffers, if needed.
		if( _bfFaceSize < _numFaces + newFaces ){
			uint moreFaces = _numFaces + newFaces; // TODO: estimate?
			Rid bfMoreFace = _rd.StorageBufferCreate( moreFaces * 3 * 4 ); copyFill( _bfFace, bfMoreFace, _bfFaceSize * 3 * 4 );						// 3 indx/face * 4 byte/indx
			_rd.FreeRid( _bfFace ); _bfFace = bfMoreFace;
			Rid bfMoreFaceToTetra = _rd.StorageBufferCreate( moreFaces * 2 * 4 ); copyFill( _bfFaceToTetra, bfMoreFaceToTetra, _bfFaceSize * 2 * 4 );	// 2 indx/face * 4 byte/indx
			_rd.FreeRid( _bfFaceToTetra ); _bfFaceToTetra = bfMoreFaceToTetra;
			_bfFaceSize = moreFaces;
		}
		// resize Edge buffers, if needed.
		if( _bfEdgeSize < _numEdges + newEdges ){
			uint moreEdges = _numEdges + newEdges; // TODO: estimate?
			Rid bfMoreEdge = _rd.StorageBufferCreate( moreEdges * 2 * 4 ); copyFill( _bfEdge, bfMoreEdge, _bfEdgeSize * 2 * 4 ); 						// 2 indx/edge * 4 byte/indx
			_rd.FreeRid( _bfEdge ); _bfEdge = bfMoreEdge;
			_bfEdgeSize = moreEdges;
		}
		// Now all the buffers should be big enough to split.
		// Note: Here we don't update _num(Simplex) until we actually write out the new simplicies.
	}


	private void expandForFlip(uint numFlips, uint numThreeTwoFlips){ // TODO: when we copy we need to copy up to the last simplex, not to _numSimplex.
		uint numTwoThreeFlips = numFlips - numThreeTwoFlips;
		
		uint newTetra = 1 * ( numTwoThreeFlips - numThreeTwoFlips );
		uint newFaces = 2 * ( numTwoThreeFlips - numThreeTwoFlips );
		uint newEdges = 1 * ( numTwoThreeFlips - numThreeTwoFlips );

		uint newFreedTetra = 1 *  numThreeTwoFlips;
		uint newFreedFaces = 2 *  numThreeTwoFlips;
		uint newFreedEdges = 1 *  numThreeTwoFlips;

		// To tune, our goal should be for these to usually evaluate to false

		// resize Tetra buffers, if needed.
		if( _bfTetraSize < _numTetra + newTetra ){
			uint moreTetra = _numTetra + newTetra; 
			Rid bfMoreTetra = newBuffer( moreTetra * 4 ); copyFill( _bfTetra, bfMoreTetra, _bfTetraSize * 4 ); 						// 4 indx/tet
			_rd.FreeRid( _bfTetra ); _bfTetra = bfMoreTetra;
			Rid bfMoreTetraToFace = newBuffer( moreTetra * 4 ); copyFill( _bfTetraToFace, bfMoreTetraToFace, _bfTetraSize * 4 );	// 4 indx/tet
			_rd.FreeRid( _bfTetraToFace ); _bfTetraToFace = bfMoreTetraToFace;
			Rid bfMoreTetraToEdge = newBuffer( moreTetra * 6 ); copyFill( _bfTetraToEdge, bfMoreTetraToEdge, _bfTetraSize * 6 );	// 6 indx/tet
			_rd.FreeRid( _bfTetraToEdge ); _bfTetraToEdge = bfMoreTetraToEdge;
			_bfTetraSize = moreTetra;
		}
		// resize Face buffers, if needed.
		if( _bfFaceSize < _numFaces + newFaces ){
			uint moreFaces = _numFaces + newFaces; // TODO: estimate?
			Rid bfMoreFace = newBuffer( moreFaces * 3 ); copyFill( _bfFace, bfMoreFace, _bfFaceSize * 3 );							// 3 indx/face
			_rd.FreeRid( _bfFace ); _bfFace = bfMoreFace;
			Rid bfMoreFaceToTetra = newBuffer( moreFaces * 2); copyFill( _bfFaceToTetra, bfMoreFaceToTetra, _bfFaceSize * 2 );		// 2 indx/face 
			_rd.FreeRid( _bfFaceToTetra ); _bfFaceToTetra = bfMoreFaceToTetra;
			_bfFaceSize = moreFaces;
		}
		// resize Edge buffers, if needed.
		if( _bfEdgeSize < _numEdges + newEdges){
			uint moreEdges = _numEdges + newEdges; // TODO: estimate?
			Rid bfMoreEdge = newBuffer( moreEdges * 2 ); copyFill( _bfEdge, bfMoreEdge, _bfEdgeSize * 2 ); 							// 2 indx/edge
			_rd.FreeRid( _bfEdge ); _bfEdge = bfMoreEdge;
			_bfEdgeSize = moreEdges;
		}
		// resize FreedTetra buffer, if needed.
		_numFreedTetra += newFreedTetra;
		if( _bfFreedTetraSize < _numFreedTetra ){
			uint moreFreedTetra = _numFreedTetra; 
			Rid bfMoreFreedTetra = newBuffer( moreFreedTetra * 4 ); copyFill( _bfFreedTetra, bfMoreFreedTetra, _numFreedTetra - newFreedTetra );
			_rd.FreeRid( _bfFreedTetra ); _bfFreedTetra = bfMoreFreedTetra;
			_bfFreedTetraSize = moreFreedTetra;
		}
		// resize FreedFace buffer, if needed.
		_numFreedFaces += newFreedFaces;
		if( _bfFreedFacesSize < _numFreedFaces + newFreedFaces ){
			uint moreFreedFaces = _numFreedFaces + newFreedFaces; // TODO: estimate?
			Rid bfMoreFreedFaces = newBuffer( moreFreedFaces * 3 ); copyFill( _bfFreedFaces, bfMoreFreedFaces, _numFreedFaces - newFreedFaces);
			_rd.FreeRid( _bfFreedFaces ); _bfFreedFaces = bfMoreFreedFaces;
			_bfFreedFacesSize = moreFreedFaces;
		}

		// resize FreedEdge buffer, if needed.
		_numFreedEdges += newFreedEdges;
		if( _bfFreedEdgesSize < _numFreedEdges ){
			uint moreFreedEdges = _numFreedEdges + newFreedEdges; // TODO: estimate?
			Rid bfMoreFreedEdge = newBuffer( moreFreedEdges * 2 ); copyFill( _bfFreedEdges, bfMoreFreedEdge, _numFreedEdges - newFreedEdges);
			_rd.FreeRid( _bfFreedEdges ); _bfFreedEdges = bfMoreFreedEdge;
			_bfFreedEdgesSize = moreFreedEdges;
		}

		// Now all the buffers should be big enough to flip.
		// New freed simplicies are only 'unofficially' freed -- We still need to write
		// them out, and overwrite some of them in flipTetra.
	}


}