using Godot;
using System;
using System.Numerics;

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
	// Kernels
		// -----------  Common   -----------
		Rid _genPredConsts; Rid _incrementalFill; Rid _zeroFill; Rid _constFill; Rid _maxFill; Rid _copyFill;
		// -----------  Compact  -----------
		Rid _PFS_SklanskyInclusive;
		Rid _atUnMark;
		Rid _bitwiseMark; Rid _bitwiseWriteID; Rid _bitwiseWriteOther; //Rid _bitwiseWriteSelf;
		Rid _nonmaxMark; Rid _nonmaxWriteID; Rid _nonmaxWriteSelf;
		Rid _nonpositiveMark; /* Rid _nonpositiveWriteID;*/  Rid _nonpositiveWriteOther; /* Rid _nonpositiveWriteSelf;*/
		Rid _positiveMark; Rid _positiveWriteID; /*Rid _positiveWriteSelf;*/ Rid _positiveWriteOther;
		Rid _tripleBitwiseMark; Rid _tripleBitwiseWriteID; /* Rid _tripleBitwiseWriteOther; *//* Rid _tripleBitwiseWriteSelf;*/
		Rid _tripleBitwiseMarkAt; Rid _tripleBitwiseWriteAtIDAt;
		Rid _dubletPositiveWriteOther; Rid _tripletPositiveWriteOther; Rid _quadrupletPositiveWriteOther; Rid _sixtupletPositiveWriteOther;
		Rid _updateCompactedIndex;
		// -----------  split  -----------=
		Rid _checkDistance; Rid _checkDistanceMinimal; Rid _markSplittingPoints;
		Rid _splitTetra;
		Rid _fastSplitLocate; Rid _exactSplitLocate;
		// -----------  flip   -----------
		Rid _checkLocalDelaunayFast; Rid _checkLocalDelaunayAdapt; Rid _checkLocalDelaunayExact;
		Rid _checkConvexFast; Rid _checkConvexExact;
		Rid _checkTwoThreeFast; Rid _checkTwoThreeExact;
		Rid _markFlipOfTetra; Rid _checkFlipOfTetra;
		Rid _finalizeTetraMarkedFlip;
		Rid _markPointsInFlips; Rid _compactPointsInFlips;
		//replaced with
		Rid _writePointsInFlips;
		Rid _freeSimplices; Rid _flipLocate_fast; Rid _flipLocate_exact;
		Rid _flipTetra;

	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                                 Compute Shader Management                                                 */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */

	private void initRenderDevice(){
		_rd = RenderingServer.CreateLocalRenderingDevice();
	}

	private void loadShaders(){
		// -------	general	-------
		_genPredConsts 					= loadShader( "res://objects/grid/compute/common/generatePredicateConst.glsl"	);
		_copyFill						= loadShader( "res://objects/grid/compute/common/copyFill.glsl"					);
		_incrementalFill				= loadShader( "res://objects/grid/compute/common/incrementalFill.glsl"			);
		_constFill						= loadShader( "res://objects/grid/compute/common/constFill.glsl"					);
		_zeroFill						= loadShader( "res://objects/grid/compute/common/zeroFill.glsl"					);
		_maxFill						= loadShader( "res://objects/grid/compute/common/maxFill.glsl"					);
		// -------	Compacting	-------
		_PFS_SklanskyInclusive			= loadShader( "res://objects/grid/compute/common/compacting/PFS_SklanskyInclusive.glsl"		);
		_atUnMark						= loadShader( "res://objects/grid/compute/common/compacting/atUnMark.glsl"					);
		_bitwiseMark					= loadShader( "res://objects/grid/compute/common/compacting/bitwiseMark.glsl"				);
		_bitwiseWriteID					= loadShader( "res://objects/grid/compute/common/compacting/bitwiseWriteID.glsl"			);
		_bitwiseWriteOther				= loadShader( "res://objects/grid/compute/common/compacting/bitwiseWriteOther.glsl"			);
		// _bitwiseWriteSelf			= loadShader( "res://objects/grid/compute/common/compacting/bitwiseWriteSelf.glsl"			);
		_nonmaxMark						= loadShader( "res://objects/grid/compute/common/compacting/nonmaxMark.glsl"				);
		_nonmaxWriteID					= loadShader( "res://objects/grid/compute/common/compacting/nonmaxWriteID.glsl"				);
		_nonmaxWriteSelf				= loadShader( "res://objects/grid/compute/common/compacting/nonmaxWriteSelf.glsl"			);
		_nonpositiveMark				= loadShader( "res://objects/grid/compute/common/compacting/nonpositiveMark.glsl"			);
		//_nonpositiveWriteID			= loadShader( "res://objects/grid/compute/common/compacting/nonpositiveWriteID.glsl"		);
		_nonpositiveWriteOther			= loadShader( "res://objects/grid/compute/common/compacting/nonpositiveWriteOther.glsl"		);
		//_nonpositiveWriteSelf			= loadShader( "res://objects/grid/compute/common/compacting/nonpositiveWriteSelf.glsl"		);
		_positiveMark					= loadShader( "res://objects/grid/compute/common/compacting/positiveMark.glsl"				);
		_positiveWriteID				= loadShader( "res://objects/grid/compute/common/compacting/positiveWriteID.glsl"			);
		_positiveWriteOther				= loadShader( "res://objects/grid/compute/common/compacting/positiveWriteOther.glsl"		);
		//_positiveWriteSelf			= loadShader( "res://objects/grid/compute/common/compacting/positiveWriteSelf.glsl"			);
		_tripleBitwiseMark				= loadShader( "res://objects/grid/compute/common/compacting/tripleBitwiseMark.glsl"			);
		_tripleBitwiseMarkAt			= loadShader( "res://objects/grid/compute/common/compacting/tripleBitwiseMarkAt.glsl"		);
		_tripleBitwiseWriteAtIDAt		= loadShader( "res://objects/grid/compute/common/compacting/tripleBitwiseWriteAtIDAt.glsl"	);
		_tripleBitwiseWriteID			= loadShader( "res://objects/grid/compute/common/compacting/tripleBitwiseWriteID.glsl"		);
		//_tripleBitwiseWriteOther		= loadShader( "res://objects/grid/compute/common/compacting/tripleBitwiseWriteOther.glsl"	);
		//_tripleBitwiseWriteSelf		= loadShader( "res://objects/grid/compute/common/compacting/tripleBitwiseWriteSelf.glsl"	);

		_dubletPositiveWriteOther 		= loadShader( "res://objects/grid/compute/common/compacting/dubletPositiveWriteOther.glsl"	);
		_tripletPositiveWriteOther 		= loadShader( "res://objects/grid/compute/common/compacting/tripletPositiveWriteOther.glsl"	);
		_quadrupletPositiveWriteOther 	= loadShader( "res://objects/grid/compute/common/compacting/quadrupletPositiveWriteOther.glsl"	);
		_sixtupletPositiveWriteOther 	= loadShader( "res://objects/grid/compute/common/compacting/sixtupletPositiveWriteOther.glsl"	);

		_updateCompactedIndex			= loadShader( "res://objects/grid/compute/common/compacting/updateCompactedIndex.glsl"		);
		// -------	split	-------
		_checkDistance					= loadShader( "res://objects/grid/compute/split/determineSplit/checkDistance.glsl"			);
		_checkDistanceMinimal			= loadShader( "res://objects/grid/compute/split/determineSplit/checkDistanceMinimal.glsl"	);
		_markSplittingPoints			= loadShader( "res://objects/grid/compute/split/determineSplit/markSplittingPoints.glsl"	);
		_splitTetra 					= loadShader( "res://objects/grid/compute/split/splitTetra.glsl" 				);
		_fastSplitLocate				= loadShader( "res://objects/grid/compute/split/fastSplitLocate.glsl" 			);
		_exactSplitLocate				= loadShader( "res://objects/grid/compute/split/exactSplitLocate.glsl" 			);
		// -------	flip	-------
		_checkLocalDelaunayFast		    = loadShader( "res://objects/grid/compute/flip/checkLocalDelaunay/checkLocalDelaunay_fast.glsl"		);
		_checkLocalDelaunayAdapt		= loadShader( "res://objects/grid/compute/flip/checkLocalDelaunay/checkLocalDelaunay_adapt.glsl"	);
		_checkLocalDelaunayExact		= loadShader( "res://objects/grid/compute/flip/checkLocalDelaunay/checkLocalDelaunay_exact.glsl"	);
			
			// --	dtmnFlips		---
		_checkConvexFast				= loadShader( "res://objects/grid/compute/flip/determineFlips/checkConvex_fast.glsl"					);
		_checkConvexExact				= loadShader( "res://objects/grid/compute/flip/determineFlips/checkConvex_exact.glsl"				);
		_checkTwoThreeFast				= loadShader( "res://objects/grid/compute/flip/determineFlips/checkTwoThree_fast.glsl"				);
		_checkTwoThreeExact				= loadShader( "res://objects/grid/compute/flip/determineFlips/checkTwoThree_exact.glsl"				);
			// --	pickFlips		---
		_markFlipOfTetra				= loadShader( "res://objects/grid/compute/flip/pickFlips/markFlipOfTetra.glsl"		);
		_checkFlipOfTetra				= loadShader( "res://objects/grid/compute/flip/pickFlips/checkFlipOfTetra.glsl"		);

		_finalizeTetraMarkedFlip		= loadShader( "res://objects/grid/compute/flip/finalizeTetraMarkedFlip.glsl"		);
		_freeSimplices					= loadShader( "res://objects/grid/compute/flip/freeSimplices.glsl"					);
		_markPointsInFlips				= loadShader( "res://objects/grid/compute/flip/flipLocate/markPointsInFlips.glsl"	);
		_writePointsInFlips				= loadShader( "res://objects/grid/compute/flip/flipLocate/writePointsInFlips.glsl"	);
		_flipLocate_fast				= loadShader( "res://objects/grid/compute/flip/flipLocate/fastFlipLocate.glsl"		);
		_flipLocate_exact				= loadShader( "res://objects/grid/compute/flip/flipLocate/exactFlipLocate.glsl"		);
		_flipTetra						= loadShader( "res://objects/grid/compute/flip/flipTetra.glsl"						);
	}

    	private void freeShaders(){
		// -------	general	-------
		_rd.FreeRid(_genPredConsts);
        _rd.FreeRid(_copyFill);
        _rd.FreeRid(_incrementalFill);
        _rd.FreeRid(_constFill);
        _rd.FreeRid(_zeroFill);
        _rd.FreeRid(_maxFill);
        // -------	Compacting	-------
        _rd.FreeRid(_PFS_SklanskyInclusive);
        _rd.FreeRid(_atUnMark);
        _rd.FreeRid(_bitwiseMark);
        _rd.FreeRid(_bitwiseWriteID);
        _rd.FreeRid(_bitwiseWriteOther);
        // _rd.FreeRid(_bitwiseWriteSelf);
        _rd.FreeRid(_nonmaxMark);
        _rd.FreeRid(_nonmaxWriteID);
        _rd.FreeRid(_nonmaxWriteSelf);
        _rd.FreeRid(_nonpositiveMark);
        // _rd.FreeRid(_nonpositiveWriteID);
        _rd.FreeRid(_nonpositiveWriteOther);
        // _rd.FreeRid(_nonpositiveWriteSelf);
        _rd.FreeRid(_positiveMark);
        _rd.FreeRid(_positiveWriteID);
        _rd.FreeRid(_positiveWriteOther);
        // _rd.FreeRid(_positiveWriteSelf);
        _rd.FreeRid(_tripleBitwiseMark);
        _rd.FreeRid(_tripleBitwiseMarkAt);
        _rd.FreeRid(_tripleBitwiseWriteAtIDAt);
        _rd.FreeRid(_tripleBitwiseWriteID);
        // _rd.FreeRid(_tripleBitwiseWriteOther);
        // _rd.FreeRid(_tripleBitwiseWriteSelf);

        _rd.FreeRid(_dubletPositiveWriteOther);
        _rd.FreeRid(_tripletPositiveWriteOther);
        _rd.FreeRid(_quadrupletPositiveWriteOther);
        _rd.FreeRid(_sixtupletPositiveWriteOther);

        _rd.FreeRid(_updateCompactedIndex);
        // -------	split	-------
        _rd.FreeRid(_checkDistance);
        _rd.FreeRid(_checkDistanceMinimal);
        _rd.FreeRid(_markSplittingPoints);
        _rd.FreeRid(_splitTetra);
        _rd.FreeRid(_fastSplitLocate);
        _rd.FreeRid(_exactSplitLocate);
        // -------	flip	-------
        _rd.FreeRid(_checkLocalDelaunayFast);
        _rd.FreeRid(_checkLocalDelaunayAdapt);
        _rd.FreeRid(_checkLocalDelaunayExact);

        // --	dtmnFlips		---
        _rd.FreeRid(_checkConvexFast);
        _rd.FreeRid(_checkConvexExact);
        _rd.FreeRid(_checkTwoThreeFast);
        _rd.FreeRid(_checkTwoThreeExact);
        // --	pickFlips		---
        _rd.FreeRid(_markFlipOfTetra);
        _rd.FreeRid(_checkFlipOfTetra);

        _rd.FreeRid(_finalizeTetraMarkedFlip);
        _rd.FreeRid(_freeSimplices);
        _rd.FreeRid(_markPointsInFlips);
        _rd.FreeRid(_writePointsInFlips);
        _rd.FreeRid(_flipLocate_fast);
        _rd.FreeRid(_flipLocate_exact);
        _rd.FreeRid(_flipTetra);
	}

	private Rid loadShader( String File)
	{
		RDShaderFile file = GD.Load<RDShaderFile>(File);
		RDShaderSpirV precompile = file.GetSpirV();
		Rid compiledShader = _rd.ShaderCreateFromSpirV(precompile);
		return compiledShader;
	}

	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                         Prefix Sum and Compacting Compute Shaders                                         */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */
	
	private uint PFS_SklanskyInclusive( uint length, uint startingStep, Rid bfSumData){ // Lots of room for improvement.
	// The naive Sklansky Prefix sum. No memory block or warp level optimizations.
		uint[] parameters = new uint[] { length, startingStep};
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufSumData.AddId(    bfSumData    );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufParameters.AddId( bfParameters );
		Rid usSklanskyInclusive = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufSumData, ufParameters}, _PFS_SklanskyInclusive, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		
		// ---------------------------------------	Compute!	---------------------------------------
		byte[] stepBytes = new byte[4];
		for(uint i = startingStep; i < BitOperations.Log2(length - 1) + 1;){

			// TODO: figure out how to reuse elements of the compute pipline, since it's the same for each step.
			// TODO: we should be able to make a better count of the number of groups, and avoid the if statement in the shader.
			Rid  plSklanskyInclusive = _rd.ComputePipelineCreate( _PFS_SklanskyInclusive );
			long clSklanskyInclusive = 	_rd.ComputeListBegin();	// ----------------------------------------------
			_rd.ComputeListBindComputePipeline( clSklanskyInclusive, plSklanskyInclusive);
			_rd.ComputeListBindUniformSet(		clSklanskyInclusive, usSklanskyInclusive, 0);
			_rd.ComputeListDispatch(			clSklanskyInclusive,	xGroups: ( length + 1 ) / 2 , yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
			
			_rd.Submit();
			_rd.Sync();

			i++; parameters[1]= i;
			Buffer.BlockCopy(parameters, 4, stepBytes, 0, 4 );
			_rd.BufferUpdate(bfParameters, 4, 4, stepBytes );
									
		}
		// ---------------------------------------	Cleanup!	---------------------------------------
		_rd.FreeRid( bfParameters );
		uint total = nthPlaceOfBuffer( length - 1, bfSumData);
		return total;
	}

	private void uintAtUnMark( uint length, Rid bfInData, Rid bfOutData ){
		//Assumes both buffers are uint buffers. Write 1 in position InData[i] of OutData.
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId(     bfInData     );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufOutData.AddId(    bfOutData    );
		Rid usAtUnMark = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufOutData}, _atUnMark, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plAtUnMark = _rd.ComputePipelineCreate( _atUnMark );
		long clAtUnMark = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clAtUnMark, plAtUnMark);
		_rd.ComputeListBindUniformSet(		clAtUnMark, usAtUnMark, 0);
		_rd.ComputeListDispatch(			clAtUnMark,	xGroups: length, yGroups: 1, zGroups: 1);
								_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void uintBitwiseMark( uint length, uint n, Rid bfInData, Rid bfOutData){ // used by compactBadPoints, compactBadFaces, compactFlips (firstPrefixSum), compactNonConvexFaces, compactIndeterminedDelaunay
		//Assumes both buffers are uint buffers. If the nth bit of 'in' in the ith index is 1, write 1 to the ith index of out.
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId(     bfInData     );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufOutData.AddId(    bfOutData    );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufParameters.AddId( bfParameters );
		Rid usBitwiseMark = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufOutData, ufParameters}, _bitwiseMark, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plBitwiseMark = _rd.ComputePipelineCreate( _bitwiseMark );
		long clBitwiseMark = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clBitwiseMark, plBitwiseMark);
		_rd.ComputeListBindUniformSet(		clBitwiseMark, usBitwiseMark, 0);
		_rd.ComputeListDispatch(			clBitwiseMark,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void uintBitwiseWriteID( uint length, uint n, Rid bfInData, Rid bfSumData, Rid bfOutData){
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId(     bfInData     );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId(    bfSumData    );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId(    bfOutData    );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufParameters.AddId( bfParameters );
		Rid usBitwiseWriteID = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData, ufParameters}, _bitwiseWriteID, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plBitwiseWriteID = _rd.ComputePipelineCreate( _bitwiseWriteID );
		long clBitwiseWriteID = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clBitwiseWriteID, plBitwiseWriteID);
		_rd.ComputeListBindUniformSet(		clBitwiseWriteID, usBitwiseWriteID, 0);
		_rd.ComputeListDispatch(			clBitwiseWriteID,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void uintBitwiseWriteOther( uint length, uint n, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId(     bfInData     );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId(  bfWriteData  );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId(    bfSumData    );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId(    bfOutData    );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufParameters.AddId( bfParameters );
		Rid usBitwiseWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData, ufParameters}, _bitwiseWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plBitwiseWriteOther = _rd.ComputePipelineCreate( _bitwiseWriteOther );
		long clBitwiseWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clBitwiseWriteOther, plBitwiseWriteOther);
		_rd.ComputeListBindUniformSet(		clBitwiseWriteOther, usBitwiseWriteOther, 0);
		_rd.ComputeListDispatch(			clBitwiseWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	/*
	private void uintBitwiseWriteSelf( uint length, uint n, Rid bfInData, Rid bfSumData, Rid bfOutData){
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId(     bfInData     );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId(    bfSumData    );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId(    bfOutData    );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufParameters.AddId( bfParameters );
		Rid usBitwiseWriteSelf = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData, ufParameters}, _bitwiseWriteSelf, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plBitwiseWriteSelf = _rd.ComputePipelineCreate( _bitwiseWriteSelf );
		long clBitwiseWriteSelf = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clBitwiseWriteSelf, plBitwiseWriteSelf);
		_rd.ComputeListBindUniformSet(		clBitwiseWriteSelf, usBitwiseWriteSelf, 0);
		_rd.ComputeListDispatch(			clBitwiseWriteSelf,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	*/

	private void uintNonmaxMark( uint length, Rid bfInData, Rid bfOutData){
		// Assumes that both buffers are uint buffers. If the uint at index i is less than (0-1), write 1 to the ith place of out.
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufOutData.AddId( bfOutData );
		Rid usNonmaxMark = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufOutData}, _nonmaxMark, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plNonmaxMark = _rd.ComputePipelineCreate( _nonmaxMark );
		long clNonmaxMark = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clNonmaxMark, plNonmaxMark);
		_rd.ComputeListBindUniformSet(		clNonmaxMark, usNonmaxMark, 0);
		_rd.ComputeListDispatch(			clNonmaxMark,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void uintNonmaxWriteID( uint length, Rid bfInData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		Rid usNonmaxWriteID = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData}, _nonmaxWriteID, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plNonmaxWriteID = _rd.ComputePipelineCreate( _nonmaxWriteID );
		long clNonmaxWriteID = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clNonmaxWriteID, plNonmaxWriteID);
		_rd.ComputeListBindUniformSet(		clNonmaxWriteID, usNonmaxWriteID, 0);
		_rd.ComputeListDispatch(			clNonmaxWriteID,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void uintNonmaxWriteSelf( uint length, Rid bfInData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		Rid usNonmaxWriteSelf = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData}, _nonmaxWriteSelf, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plNonmaxWriteSelf = _rd.ComputePipelineCreate( _nonmaxWriteSelf );
		long clNonmaxWriteSelf = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clNonmaxWriteSelf, plNonmaxWriteSelf);
		_rd.ComputeListBindUniformSet(		clNonmaxWriteSelf, usNonmaxWriteSelf, 0);
		_rd.ComputeListDispatch(			clNonmaxWriteSelf,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void uintNonpositiveMark( uint length, Rid bfInData, Rid bfOutData){
		// Assumes that both buffers are uint buffers. If the uint at index i is 0, write 1 to the ith place of out.
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufOutData.AddId( bfOutData );
		Rid usNonpositiveMark = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufOutData}, _nonpositiveMark, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plNonpositiveMark = _rd.ComputePipelineCreate( _nonpositiveMark );
		long clNonpositiveMark = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clNonpositiveMark, plNonpositiveMark);
		_rd.ComputeListBindUniformSet(		clNonpositiveMark, usNonpositiveMark, 0);
		_rd.ComputeListDispatch(			clNonpositiveMark,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	/*
	private void uintNonpositiveWriteID( uint length, Rid bfInData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		Rid usNonpositiveWriteID = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData}, _nonpositiveWriteID, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plNonpositiveWriteID = _rd.ComputePipelineCreate( _nonpositiveWriteID );
		long clNonpositiveWriteID = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clNonpositiveWriteID, plNonpositiveWriteID);
		_rd.ComputeListBindUniformSet(		clNonpositiveWriteID, usNonpositiveWriteID, 0);
		_rd.ComputeListDispatch(			clNonpositiveWriteID,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	*/

	private void uintNonpositiveWriteOther( uint length, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId( bfWriteData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		Rid usNonpositiveWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData}, _nonpositiveWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plNonpositiveWriteOther = _rd.ComputePipelineCreate( _nonpositiveWriteOther );
		long clNonpositiveWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clNonpositiveWriteOther, plNonpositiveWriteOther);
		_rd.ComputeListBindUniformSet(		clNonpositiveWriteOther, usNonpositiveWriteOther, 0);
		_rd.ComputeListDispatch(			clNonpositiveWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	/*
	private void uintNonpositiveWriteSelf( uint length, Rid bfInData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		Rid usNonpositiveWriteSelf = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData}, _nonpositiveWriteSelf, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plNonpositiveWriteSelf = _rd.ComputePipelineCreate( _nonpositiveWriteSelf );
		long clNonpositiveWriteSelf = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clNonpositiveWriteSelf, plNonpositiveWriteSelf);
		_rd.ComputeListBindUniformSet(		clNonpositiveWriteSelf, usNonpositiveWriteSelf, 0);
		_rd.ComputeListDispatch(			clNonpositiveWriteSelf,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	*/
	
	private void uintPositiveMark( uint length, Rid bfInData, Rid bfOutData){ //compactSplit, ActiveFaces, compactPointsInFlip
		//Assumes that both buffers are uint buffers. If the uint at index i is positive, write 1 to the ith place of out.
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufOutData.AddId( bfOutData );
		Rid usPositiveMark = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufOutData}, _positiveMark, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plPositiveMark = _rd.ComputePipelineCreate( _positiveMark );
		long clPositiveMark = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clPositiveMark, plPositiveMark);
		_rd.ComputeListBindUniformSet(		clPositiveMark, usPositiveMark, 0);
		_rd.ComputeListDispatch(			clPositiveMark,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	

	private void uintPositiveWriteID( uint length, Rid bfInData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		Rid usPositiveWriteID = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData}, _positiveWriteID, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plPositiveWriteID = _rd.ComputePipelineCreate( _positiveWriteID );
		long clPositiveWriteID = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clPositiveWriteID, plPositiveWriteID);
		_rd.ComputeListBindUniformSet(		clPositiveWriteID, usPositiveWriteID, 0);
		_rd.ComputeListDispatch(			clPositiveWriteID,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	
	/*
	private void uintPositiveWriteSelf( uint length, Rid bfInData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		Rid usPositiveWriteSelf = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData}, _positiveWriteSelf, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plPositiveWriteSelf = _rd.ComputePipelineCreate( _positiveWriteSelf );
		long clPositiveWriteSelf = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clPositiveWriteSelf, plPositiveWriteSelf);
		_rd.ComputeListBindUniformSet(		clPositiveWriteSelf, usPositiveWriteSelf, 0);
		_rd.ComputeListDispatch(			clPositiveWriteSelf,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	*/
	
	private void uintPositiveWriteOther( uint length, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId( bfWriteData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		Rid usPositiveWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData}, _positiveWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plPositiveWriteOther = _rd.ComputePipelineCreate( _positiveWriteOther );
		long clPositiveWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clPositiveWriteOther, plPositiveWriteOther);
		_rd.ComputeListBindUniformSet(		clPositiveWriteOther, usPositiveWriteOther, 0);
		_rd.ComputeListDispatch(			clPositiveWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	

	private void uintTripleBitwiseMark( uint length, uint n, Rid bfInData, Rid bfOutData){ //compactFlips (secondPrefixSum), compactIndeterminedConvexity, compactIndeterminedTwoThree FIXME!
		//Assumes both buffers are uint buffers. If the nth bit of 'in' in the ith index is 1, write 1 to the ith index of out.
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufOutData.AddId( bfOutData );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufParameters.AddId( bfParameters );
		Rid usTripleBitwiseMark = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufOutData, ufParameters}, _tripleBitwiseMark, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plTripleBitwiseMark = _rd.ComputePipelineCreate( _tripleBitwiseMark );
		long clTripleBitwiseMark = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clTripleBitwiseMark, plTripleBitwiseMark);
		_rd.ComputeListBindUniformSet(		clTripleBitwiseMark, usTripleBitwiseMark, 0);
		_rd.ComputeListDispatch(			clTripleBitwiseMark,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

		private void uintTripleBitwiseMarkAt( uint length, uint n, Rid bfInData, Rid bfAtData , Rid bfOutData){ //compactFlips (secondPrefixSum), compactIndeterminedConvexity, compactIndeterminedTwoThree FIXME!
		//Assumes both buffers are uint buffers. If the nth bit of 'in' in the ith index is 1, write 1 to the ith index of out.
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufAtData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufAtData.AddId( bfAtData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufParameters.AddId( bfParameters );
		Rid usTripleBitwiseMarkAt = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufAtData, ufOutData, ufParameters}, _tripleBitwiseMarkAt, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plTripleBitwiseMarkAt = _rd.ComputePipelineCreate( _tripleBitwiseMarkAt );
		long clTripleBitwiseMarkAt = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clTripleBitwiseMarkAt, plTripleBitwiseMarkAt);
		_rd.ComputeListBindUniformSet(		clTripleBitwiseMarkAt, usTripleBitwiseMarkAt, 0);
		_rd.ComputeListDispatch(			clTripleBitwiseMarkAt,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void uintTripleBitwiseWriteID( uint length, uint n, Rid bfInData, Rid bfSumData, Rid bfOutData){
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufParameters.AddId( bfParameters );
		Rid usTripleBitwiseWriteID = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData, ufParameters}, _tripleBitwiseWriteID, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plTripleBitwiseWriteID = _rd.ComputePipelineCreate( _tripleBitwiseWriteID );
		long clTripleBitwiseWriteID = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clTripleBitwiseWriteID, plTripleBitwiseWriteID);
		_rd.ComputeListBindUniformSet(		clTripleBitwiseWriteID, usTripleBitwiseWriteID, 0);
		_rd.ComputeListDispatch(			clTripleBitwiseWriteID,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void uintTripleBitwiseWriteAtIDAt( uint length, uint n, Rid bfInData, Rid bfAtData, Rid bfSumData, Rid bfOutData){
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufAtData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufAtData.AddId( bfAtData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufParameters.AddId( bfParameters );
		Rid usTripleBitwiseWriteAtIDAt = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufAtData, ufSumData, ufOutData, ufParameters}, _tripleBitwiseWriteAtIDAt, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plTripleBitwiseWriteAtIDAt = _rd.ComputePipelineCreate( _tripleBitwiseWriteAtIDAt );
		long clTripleBitwiseWriteAtIDAt = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clTripleBitwiseWriteAtIDAt, plTripleBitwiseWriteAtIDAt);
		_rd.ComputeListBindUniformSet(		clTripleBitwiseWriteAtIDAt, usTripleBitwiseWriteAtIDAt, 0);
		_rd.ComputeListDispatch(			clTripleBitwiseWriteAtIDAt,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	/*
	private void uintTripleBitwiseWriteOther( uint length, uint n, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId( bfWriteData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufParameters.AddId( bfParameters );
		Rid usTripleBitwiseWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData, ufParameters}, _tripleBitwiseWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plTripleBitwiseWriteOther = _rd.ComputePipelineCreate( _tripleBitwiseWriteOther );
		long clTripleBitwiseWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clTripleBitwiseWriteOther, plTripleBitwiseWriteOther);
		_rd.ComputeListBindUniformSet(		clTripleBitwiseWriteOther, usTripleBitwiseWriteOther, 0);
		_rd.ComputeListDispatch(			clTripleBitwiseWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	*/
	/*
	private void uintTripleBitwiseWriteSelf( uint length, uint n, Rid bfInData, Rid bfSumData, Rid bfOutData){
		uint[] parameters = new uint[] { n };
		Rid bfParameters = toBuffer(parameters);
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufOutData.AddId( bfOutData );
		RDUniform ufParameters 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufParameters.AddId( bfParameters );
		Rid usTripleBitwiseWriteSelf = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufSumData, ufOutData, ufParameters}, _tripleBitwiseWriteSelf, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plTripleBitwiseWriteSelf = _rd.ComputePipelineCreate( _tripleBitwiseWriteSelf );
		long clTripleBitwiseWriteSelf = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clTripleBitwiseWriteSelf, plTripleBitwiseWriteSelf);
		_rd.ComputeListBindUniformSet(		clTripleBitwiseWriteSelf, usTripleBitwiseWriteSelf, 0);
		_rd.ComputeListDispatch(			clTripleBitwiseWriteSelf,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}
	*/

	private void pointInFlipMark( Rid bfTetraMarkedFlip, Rid bfFlipInfo, Rid bfPointInFlipSum ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufTetOfPoints = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufTetOfPoints.AddId( _bfTetraOfPoints );
		RDUniform ufPointInFlipSum = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPointInFlipSum.AddId( bfPointInFlipSum );
		RDUniform ufTetraMarkedFlip = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetraMarkedFlip.AddId( bfTetraMarkedFlip );
		//RDUniform ufFlipInfo = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFlipInfo.AddId( bfFlipInfo );
		Rid usMarkPointsInFlip = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufTetOfPoints, ufPointInFlipSum, ufTetraMarkedFlip}, _markPointsInFlips, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plMarkPointsInFlip = _rd.ComputePipelineCreate( _markPointsInFlips );
		long clMarkPointsInFlip = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clMarkPointsInFlip, plMarkPointsInFlip);
		_rd.ComputeListBindUniformSet(		clMarkPointsInFlip, usMarkPointsInFlip, 0);
		_rd.ComputeListDispatch(			clMarkPointsInFlip,	xGroups: _numPointsRemaining, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void pointInFlipWrite( Rid bfTetraMarkedFlip, Rid bfFlipInfo, Rid bfPointInFlipSum, Rid bfPointsInFlips){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufTetOfPoints = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufTetOfPoints.AddId( _bfTetraOfPoints );
		RDUniform ufPointInFlipSum = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPointInFlipSum.AddId( bfPointInFlipSum );
		RDUniform ufTetraMarkedFlip = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetraMarkedFlip.AddId( bfTetraMarkedFlip );
		//RDUniform ufFlipInfo = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufPointsInFlips = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufPointsInFlips.AddId( bfPointsInFlips );
		Rid usWritePointsInFlip = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufTetOfPoints, ufTetraMarkedFlip, ufPointInFlipSum, ufPointsInFlips}, _writePointsInFlips, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plWritePointsInFlip = _rd.ComputePipelineCreate( _writePointsInFlips );
		long clWritePointsInFlip = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clWritePointsInFlip, plWritePointsInFlip);
		_rd.ComputeListBindUniformSet(		clWritePointsInFlip, usWritePointsInFlip, 0);
		_rd.ComputeListDispatch(			clWritePointsInFlip,	xGroups: _numPointsRemaining, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void dubletPositiveWriteOther( uint length, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId( bfWriteData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		Rid usDubletPositiveWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData}, _dubletPositiveWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plDubletPositiveWriteOther = _rd.ComputePipelineCreate( _dubletPositiveWriteOther );
		long clDubletPositiveWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clDubletPositiveWriteOther, plDubletPositiveWriteOther);
		_rd.ComputeListBindUniformSet(		clDubletPositiveWriteOther, usDubletPositiveWriteOther, 0);
		_rd.ComputeListDispatch(			clDubletPositiveWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void tripletPositiveWriteOther( uint length, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId( bfWriteData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		Rid usTripletPositiveWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData}, _tripletPositiveWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plTripletPositiveWriteOther = _rd.ComputePipelineCreate( _tripletPositiveWriteOther );
		long clTripletPositiveWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clTripletPositiveWriteOther, plTripletPositiveWriteOther);
		_rd.ComputeListBindUniformSet(		clTripletPositiveWriteOther, usTripletPositiveWriteOther, 0);
		_rd.ComputeListDispatch(			clTripletPositiveWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void quadrupletPositiveWriteOther( uint length, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId( bfWriteData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		Rid usQuadrupletPositiveWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData}, _quadrupletPositiveWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plQuadrupletPositiveWriteOther = _rd.ComputePipelineCreate( _quadrupletPositiveWriteOther );
		long clQuadrupletPositiveWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clQuadrupletPositiveWriteOther, plQuadrupletPositiveWriteOther);
		_rd.ComputeListBindUniformSet(		clQuadrupletPositiveWriteOther, usQuadrupletPositiveWriteOther, 0);
		_rd.ComputeListDispatch(			clQuadrupletPositiveWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void sixtupletPositiveWriteOther( uint length, Rid bfInData, Rid bfWriteData, Rid bfSumData, Rid bfOutData){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufInData 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufInData.AddId( bfInData );
		RDUniform ufWriteData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufWriteData.AddId( bfWriteData );
		RDUniform ufSumData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufSumData.AddId( bfSumData );
		RDUniform ufOutData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufOutData.AddId( bfOutData );
		Rid usSixtupletPositiveWriteOther = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufInData, ufWriteData, ufSumData, ufOutData}, _sixtupletPositiveWriteOther, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plSixtupletPositiveWriteOther = _rd.ComputePipelineCreate( _sixtupletPositiveWriteOther );
		long clSixtupletPositiveWriteOther = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clSixtupletPositiveWriteOther, plSixtupletPositiveWriteOther);
		_rd.ComputeListBindUniformSet(		clSixtupletPositiveWriteOther, usSixtupletPositiveWriteOther, 0);
		_rd.ComputeListDispatch(			clSixtupletPositiveWriteOther,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void updateCompactedIndex( uint length, Rid bfData, Rid bfSumData ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufData 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufData.AddId( bfData );
		RDUniform ufSumData = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufSumData.AddId( bfSumData );
		Rid usUpdateCompactedIndex = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ufData, ufSumData}, _updateCompactedIndex, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plUpdateCompactedIndex = _rd.ComputePipelineCreate( _updateCompactedIndex );
		long clUpdateCompactedIndex = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clUpdateCompactedIndex, plUpdateCompactedIndex);
		_rd.ComputeListBindUniformSet(		clUpdateCompactedIndex, usUpdateCompactedIndex, 0);
		_rd.ComputeListDispatch(			clUpdateCompactedIndex,	xGroups: length, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                              General Compute Shader Bindings                                              */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */


    private void incrementalFill( Rid bfData, uint size, uint start){
		if( size == 0 ){ return; }
		uint[] param = { start };
		Rid bfParam = toBuffer( param );
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufData  = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufData.AddId( bfData);
		RDUniform ufParam = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufParam.AddId( bfParam);
		Rid ufsetIncrementalFill = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{ ufData, ufParam }, _incrementalFill, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plIncrementalFill = _rd.ComputePipelineCreate( _incrementalFill );
		long clIncrementalFill =		_rd.ComputeListBegin();	// ----------------------------------------------
			_rd.ComputeListBindComputePipeline(	clIncrementalFill, 	plIncrementalFill);
			_rd.ComputeListBindUniformSet(		clIncrementalFill,	ufsetIncrementalFill, 	0);
			_rd.ComputeListDispatch(			clIncrementalFill,	xGroups: size,	yGroups: 1,	zGroups: 1 );
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
		// ---------------------------------------	Cleanup!	---------------------------------------
		_rd.FreeRid( bfParam); //_rd.FreeRid( ufsetIncrementalFill ); _rd.FreeRid( plIncrementalFill ); we don't need to free these!
    }


	private void zeroFill( Rid bfData, uint size ){
		if( size == 0 ){ return; }
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufData  = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufData.AddId( bfData);
		Rid usZeroFill = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{ ufData }, _zeroFill, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plZeroFill = _rd.ComputePipelineCreate( _zeroFill );
		long clZeroFill =				_rd.ComputeListBegin();	// ----------------------------------------------
			_rd.ComputeListBindComputePipeline(	clZeroFill, plZeroFill);
			_rd.ComputeListBindUniformSet(		clZeroFill,	usZeroFill, 0);
			_rd.ComputeListDispatch(			clZeroFill,	xGroups: size,	yGroups: 1,	zGroups: 1 );
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
    }

	private void constFill( Rid bfData, uint size, uint value ){
		if( size == 0 ){ return; }
		uint[] param = { value };
		Rid bfParam = toBuffer( param );
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufData  = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufData.AddId( bfData);
		RDUniform ufParam = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufParam.AddId( bfParam);
		Rid usConstFill = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{ ufData, ufParam }, _constFill, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plConstFill = _rd.ComputePipelineCreate( _constFill );
		long clConstFill =				_rd.ComputeListBegin();	// ----------------------------------------------
			_rd.ComputeListBindComputePipeline(	clConstFill, plConstFill);
			_rd.ComputeListBindUniformSet(		clConstFill,	usConstFill, 0);
			_rd.ComputeListDispatch(			clConstFill,	xGroups: size,	yGroups: 1,	zGroups: 1 );
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
		// ---------------------------------------	Cleanup!	---------------------------------------
		_rd.FreeRid( bfParam);
    }


	private void copyFill( Rid bfOld, Rid bfNew, uint numToFill ){
		if( numToFill == 0 ){ return; }
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufOld = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufOld.AddId(bfOld);
		RDUniform ufNew = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufNew.AddId(bfNew);
		Rid usCopyFill = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{ ufOld, ufNew }, _copyFill, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plCopyFill = _rd.ComputePipelineCreate( _copyFill );
		long clCopyFill = 			_rd.ComputeListBegin();	// ----------------------------------------------
			_rd.ComputeListBindComputePipeline(	clCopyFill, plCopyFill);
			_rd.ComputeListBindUniformSet(		clCopyFill, usCopyFill, 0);
			_rd.ComputeListDispatch(			clCopyFill,	xGroups: numToFill, yGroups: 1, zGroups: 1 );
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void maxFill( Rid bffrData, uint size ){
		if( size == 0 ){ return; }
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufData  = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufData.AddId( bffrData);
		Rid usMaxFill = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{ ufData }, _maxFill, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plMaxFill = _rd.ComputePipelineCreate( _maxFill );
		long clMaxFill =				_rd.ComputeListBegin();	// ----------------------------------------------
			_rd.ComputeListBindComputePipeline(	clMaxFill, plMaxFill);
			_rd.ComputeListBindUniformSet(		clMaxFill,	usMaxFill, 0);
			_rd.ComputeListDispatch(			clMaxFill,	xGroups: size,	yGroups: 1,	zGroups: 1 );
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
		// ---------------------------------------	Cleanup!	---------------------------------------
		//_rd.FreeRid( usZeroFill ); _rd.FreeRid( plZeroFill );
    }


	private void genPredConsts(){
		_bfPredConsts = _rd.StorageBufferCreate( 18 * 4 ); // four bytes per float
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPredConsts = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufPredConsts.AddId(_bfPredConsts);
		Rid usGenPredConsts = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufPredConsts }, _genPredConsts, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plGenPredConsts = _rd.ComputePipelineCreate(_genPredConsts);
		long clGenPredConsts =		_rd.ComputeListBegin();	// ----------------------------------------------
			_rd.ComputeListBindComputePipeline(clGenPredConsts, plGenPredConsts);
			_rd.ComputeListBindUniformSet(clGenPredConsts, usGenPredConsts, 0);
			_rd.ComputeListDispatch(	clGenPredConsts,	xGroups: 1, yGroups: 1, zGroups: 1 );
			// This kernel has been tested across invocations on my GPU, and seems consistant.
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
		if( DEBUG_COMPLEX ){
				debugLogAddLine( "predicate constants generated!");
				debugLogAddLine( "_bfPredConsts: "  + singleToString( bfToFloat( _bfPredConsts , 18) ) );
			}
		// ---------------------------------------	Cleanup!	---------------------------------------
		//_rd.FreeRid( usGenPredConsts ); _rd.FreeRid( plGenPredConsts );
		_predConstsGenerated = true;
	}


	/* ------------------------------------------------------------------------------------------------------------------------- */
	/*                                                                                                                           */
	/*                                             Geometry Compute Shader Bindings                                              */
	/*                                                                                                                           */
	/* ------------------------------------------------------------------------------------------------------------------------- */

	private void checkDistance( Rid bfTetraIsSplitBy, Rid bfCircDistance ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPoints = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufPoints.AddId( _bfPoints );
		RDUniform ufPointsToAdd = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPointsToAdd.AddId( _bfPointsToAdd );
		RDUniform ufTetOfPoints = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetOfPoints.AddId( _bfTetraOfPoints );
		RDUniform ufTetra = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufTetra.AddId(_bfTetra);
		RDUniform ufTetraOfSplit = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraOfSplit.AddId(bfTetraIsSplitBy);
		RDUniform ufCircDistance = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufCircDistance.AddId(bfCircDistance);
		Rid usCheckDistance = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{
			ufPoints, ufPointsToAdd, ufTetOfPoints, ufTetra, ufTetraOfSplit, ufCircDistance }, _checkDistance, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plCheckDistance = _rd.ComputePipelineCreate(_checkDistance);
		long clCheckDistance = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clCheckDistance, plCheckDistance);
		_rd.ComputeListBindUniformSet(		clCheckDistance, usCheckDistance, 0);
		_rd.ComputeListDispatch(			clCheckDistance, xGroups: _numPointsRemaining, yGroups: 1, zGroups: 1);
								_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void checkDistanceMinimal( Rid bfTetraIsSplitBy, Rid bfCircDistance ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPointsToAdd = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPointsToAdd.AddId( _bfPointsToAdd );
		RDUniform ufTetOfPoints = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetOfPoints.AddId( _bfTetraOfPoints );
		RDUniform ufTetraOfSplit = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraOfSplit.AddId(bfTetraIsSplitBy);
		RDUniform ufCircDistance = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufCircDistance.AddId(bfCircDistance);
		Rid usCheckDistanceMinimal = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{
			ufPointsToAdd, ufTetOfPoints, ufTetraOfSplit, ufCircDistance }, _checkDistanceMinimal, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plCheckDistanceMinimal = _rd.ComputePipelineCreate(_checkDistanceMinimal);
		long clCheckDistanceMinimal = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clCheckDistanceMinimal, plCheckDistanceMinimal);
		_rd.ComputeListBindUniformSet(		clCheckDistanceMinimal, usCheckDistanceMinimal, 0);
		_rd.ComputeListDispatch(			clCheckDistanceMinimal, xGroups: _numPointsRemaining, yGroups: 1, zGroups: 1);
								_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void markSplittingPoint( Rid bfTetraIsSplitBy, Rid bfPointsIsSplitting ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPointsToAdd = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPointsToAdd.AddId( _bfPointsToAdd );
		RDUniform ufTetOfPoints = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetOfPoints.AddId( _bfTetraOfPoints );
		RDUniform ufTetraOfSplit = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraOfSplit.AddId(bfTetraIsSplitBy);
		RDUniform ufPointsIsSplitting = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufPointsIsSplitting.AddId(bfPointsIsSplitting);
		Rid usMarkSplittingPoints = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{
			ufPointsToAdd, ufTetOfPoints, ufTetraOfSplit, ufPointsIsSplitting }, _markSplittingPoints, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plMarkSplittingPoints = _rd.ComputePipelineCreate( _markSplittingPoints );
		long clMarkSplittingPoints = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clMarkSplittingPoints, plMarkSplittingPoints);
		_rd.ComputeListBindUniformSet(		clMarkSplittingPoints, usMarkSplittingPoints, 0);
		_rd.ComputeListDispatch(			clMarkSplittingPoints,	xGroups: _numPointsRemaining, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void SplitTetra( uint numSplitTetra, Rid bfTetraIsSplitBy, Rid bfSplittingTetra, Rid bfActiveFaces, Rid bfOffset){
		RDUniform ufTetra			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  0}; ufTetra.AddId( _bfTetra );
		RDUniform ufTetraToFace		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  1}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufTetraToEdge 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  2}; ufTetraToEdge.AddId( _bfTetraToEdge );
		RDUniform ufFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  3}; ufFace.AddId( _bfFace );
		RDUniform ufFaceToTetra		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  4}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufEdge			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  5}; ufEdge.AddId( _bfEdge );
		RDUniform ufTetraIsSplitBy	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  6}; ufTetraIsSplitBy.AddId( bfTetraIsSplitBy );
		RDUniform ufSplittingTetra 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  7}; ufSplittingTetra.AddId( bfSplittingTetra );
		RDUniform ufFreedTetra		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  8}; ufFreedTetra.AddId( _bfFreedTetra );
		RDUniform ufFreedFaces		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  9}; ufFreedFaces.AddId( _bfFreedFaces );
		RDUniform ufFreedEdges		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 10}; ufFreedEdges.AddId( _bfFreedEdges );
		RDUniform ufActiveFaces 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 12}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufOffset 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 13}; ufOffset.AddId( bfOffset );
		Rid usSplitTetra = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{
			ufTetra, ufTetraToFace, ufTetraToEdge, ufFace, ufFaceToTetra, ufEdge, ufTetraIsSplitBy, ufSplittingTetra, ufFreedTetra, ufFreedFaces, ufFreedEdges, ufActiveFaces, ufOffset }, _splitTetra, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plSplitTetra = _rd.ComputePipelineCreate( _splitTetra );
		long clsplitTetra = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clsplitTetra, plSplitTetra);
		_rd.ComputeListBindUniformSet(		clsplitTetra, usSplitTetra, 0);
		_rd.ComputeListDispatch(			clsplitTetra,	xGroups: numSplitTetra, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private Rid relocatePointsFast( Rid bfTetraToSplit, Rid bfOffset){
		Rid bfLocations = newBuffer(_numPointsRemaining); // One for each point to sort.
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPoints		 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufPoints.AddId( _bfPoints );
		RDUniform ufPointsToAdd  = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPointsToAdd.AddId( _bfPointsToAdd );
		RDUniform ufTetOfPoints  = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetOfPoints.AddId( _bfTetraOfPoints ); 	// updating this
		RDUniform ufTetraToSplit = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufTetraToSplit.AddId( bfTetraToSplit ); // from past tetra to the new split.
		RDUniform ufFace 		 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufFace.AddId( _bfFace ); 				// we grab points using this
		RDUniform ufLocations 	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufLocations.AddId( bfLocations ); 
		RDUniform ufFreedTetra	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufFreedTetra.AddId( _bfFreedTetra );
		RDUniform ufFreedFaces	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 7}; ufFreedFaces.AddId( _bfFreedFaces );
		RDUniform ufPredConsts 	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 8}; ufPredConsts.AddId( _bfPredConsts ); 
		RDUniform ufOffset 		 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 9}; ufOffset.AddId( bfOffset );
		Rid usFastSplitLocate = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufPoints, ufPointsToAdd, ufTetOfPoints, ufTetraToSplit, ufFace, ufLocations, ufFreedTetra, ufFreedFaces, ufPredConsts, ufOffset}, _fastSplitLocate, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plFastSplitLocate = _rd.ComputePipelineCreate( _fastSplitLocate );
		long clFastSplitLocate = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clFastSplitLocate, plFastSplitLocate);
		_rd.ComputeListBindUniformSet(		clFastSplitLocate, usFastSplitLocate, 0);
		_rd.ComputeListDispatch(			clFastSplitLocate,	xGroups: _numPointsRemaining, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
		return bfLocations;
	}




	private void relocatePointsExact( Rid bfBadPoints, Rid bfLocations, Rid bfTetraToSplit, Rid bfOffset, uint numBadPoints ){
		// Todo: run in multiple interations to save GPU memory?
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPoints		 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  0}; ufPoints.AddId( _bfPoints );
		RDUniform ufBadPoints	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  1}; ufBadPoints.AddId( bfBadPoints );
		RDUniform ufPointsToAdd  = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  2}; ufPointsToAdd.AddId( _bfPointsToAdd );
		RDUniform ufTetOfPoints  = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  3}; ufTetOfPoints.AddId( _bfTetraOfPoints ); 	// updating this
		RDUniform ufTetraToSplit = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  4}; ufTetraToSplit.AddId( bfTetraToSplit ); // from past tetra to the new split.
		RDUniform ufFace 		 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  5}; ufFace.AddId( _bfFace ); 				// we grab points using this
		RDUniform ufLocations 	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  6}; ufLocations.AddId( bfLocations );
		RDUniform ufFreedTetra	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  7}; ufFreedTetra.AddId( _bfFreedTetra );
		RDUniform ufFreedFaces	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  8}; ufFreedFaces.AddId( _bfFreedFaces );
		RDUniform ufPredConsts 	 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  9}; ufPredConsts.AddId( _bfPredConsts ); 
		RDUniform ufOffset 		 = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 10}; ufOffset.AddId( bfOffset );
		Rid usExactSplitLocate = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{
			ufPoints, ufBadPoints, ufPointsToAdd, ufTetOfPoints, ufTetraToSplit, ufFace, ufLocations, ufFreedTetra, ufFreedFaces, ufPredConsts, ufOffset}, _exactSplitLocate, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plExactSplitLocate = _rd.ComputePipelineCreate( _exactSplitLocate );
		long clExactSplitLocate = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clExactSplitLocate, plExactSplitLocate);
		_rd.ComputeListBindUniformSet(		clExactSplitLocate, usExactSplitLocate, 0);
		_rd.ComputeListDispatch(			clExactSplitLocate,	xGroups: numBadPoints, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void checkLocalDelaunayFast( uint numActiveFaces, Rid bfActiveFaces, Rid bfFlipInfo ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFaces = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufPoints = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPoints.AddId( _bfPoints );
		RDUniform ufTetra = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufPredConsts = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 6}; ufPredConsts.AddId( _bfPredConsts );
		Rid usCheckLocalDelaunayFast = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{
				ufActiveFaces, ufPoints, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufPredConsts }, _checkLocalDelaunayFast, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plCheckLocalDelaunayFast = 	_rd.ComputePipelineCreate( _checkLocalDelaunayFast );
		long clCheckLocalDelaunayFast = _rd.ComputeListBegin();
		_rd.ComputeListBindComputePipeline(clCheckLocalDelaunayFast, plCheckLocalDelaunayFast);
		_rd.ComputeListBindUniformSet(clCheckLocalDelaunayFast, usCheckLocalDelaunayFast, 0);
		_rd.ComputeListDispatch(	clCheckLocalDelaunayFast,	xGroups:   numActiveFaces , yGroups: 1, zGroups: 1 );
									_rd.ComputeListEnd();
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void checkLocalDelaunayAdapt( uint numIndetrmndFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfIndetrmndFaces){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFaces = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufPoints = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPoints.AddId( _bfPoints );
		RDUniform ufTetra = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufIndetrmndFaces = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 6}; ufIndetrmndFaces.AddId( bfIndetrmndFaces );
		RDUniform ufPredConsts = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 7}; ufPredConsts.AddId( _bfPredConsts );
		Rid usCheckLocalDelaunayAdapt = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{
				ufActiveFaces, ufPoints, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufIndetrmndFaces, ufPredConsts }, _checkLocalDelaunayAdapt, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plCheckLocalDelaunayAdapt = 	_rd.ComputePipelineCreate( _checkLocalDelaunayAdapt );
		long clCheckLocalDelaunayAdapt = _rd.ComputeListBegin();
		_rd.ComputeListBindComputePipeline(clCheckLocalDelaunayAdapt, plCheckLocalDelaunayAdapt);
		_rd.ComputeListBindUniformSet( clCheckLocalDelaunayAdapt, usCheckLocalDelaunayAdapt, 0 );
		_rd.ComputeListDispatch(	clCheckLocalDelaunayAdapt,	xGroups:   numIndetrmndFaces , yGroups: 1, zGroups: 1 );
									_rd.ComputeListEnd();
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void checkLocalDelaunayExact( uint numIndetrmndFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfIndetrmndFaces){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFaces = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufPoints = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPoints.AddId( _bfPoints );
		RDUniform ufTetra = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace = new RDUniform{ UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufIndetrmndFaces = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 6}; ufIndetrmndFaces.AddId( bfIndetrmndFaces );
		RDUniform ufPredConsts = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer,	Binding = 7}; ufPredConsts.AddId( _bfPredConsts );
		Rid usCheckLocalDelaunayExact = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{
				ufActiveFaces, ufPoints, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufPredConsts }, _checkLocalDelaunayExact, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid plCheckLocalDelaunayExact = 	_rd.ComputePipelineCreate( _checkLocalDelaunayExact );
		long clCheckLocalDelaunayExact = _rd.ComputeListBegin();
		_rd.ComputeListBindComputePipeline(clCheckLocalDelaunayExact, plCheckLocalDelaunayExact);
		_rd.ComputeListBindUniformSet( clCheckLocalDelaunayExact, usCheckLocalDelaunayExact, 0 );
		_rd.ComputeListDispatch(	clCheckLocalDelaunayExact,	xGroups:   numIndetrmndFaces , yGroups: 1, zGroups: 1 );
									_rd.ComputeListEnd();
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	
	private void checkConvexFast( uint numbadFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFace	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFace.AddId( bfActiveFaces );
		RDUniform ufPoints 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPoints.AddId( _bfPoints );
		RDUniform ufTetra 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufPredConsts 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 7}; ufPredConsts.AddId( _bfPredConsts );
		Rid usCheckConvexFast = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufActiveFace, ufPoints, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufBadFaces, ufPredConsts}, _checkConvexFast, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plCheckConvexFast = _rd.ComputePipelineCreate( _checkConvexFast );
		long clCheckConvexFast = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clCheckConvexFast, plCheckConvexFast);
		_rd.ComputeListBindUniformSet(		clCheckConvexFast, usCheckConvexFast, 0);
		_rd.ComputeListDispatch(			clCheckConvexFast,	xGroups: numbadFaces, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void checkConvexExact( uint numbadFaces, Rid bfIndeterminedFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFace.AddId( bfActiveFaces );
		RDUniform ufPoints 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufPoints.AddId( _bfPoints );
		RDUniform ufTetra 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufIndeterminedFaces 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 7}; ufIndeterminedFaces.AddId( bfIndeterminedFaces );
		RDUniform ufPredConsts 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 8}; ufPredConsts.AddId( _bfPredConsts );
		Rid usCheckConvexExact = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufActiveFace, ufPoints, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufBadFaces, ufPredConsts}, _checkConvexExact, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plCheckConvexExact = _rd.ComputePipelineCreate( _checkConvexExact );
		long clCheckConvexExact = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clCheckConvexExact, plCheckConvexExact);
		_rd.ComputeListBindUniformSet(		clCheckConvexExact, usCheckConvexExact, 0);
		_rd.ComputeListDispatch(			clCheckConvexExact,	xGroups: numbadFaces, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void checkThreeTwoFast( uint numNonconvexBadFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfNonconvexBadFaces ){
		// Change this
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFace.AddId( bfActiveFaces );
		RDUniform ufPoints 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPoints.AddId( _bfPoints );
		RDUniform ufTetra 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufNonconvexBadFaces 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 7}; ufNonconvexBadFaces.AddId( bfNonconvexBadFaces );
		RDUniform ufPredConsts 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 8}; ufPredConsts.AddId( _bfPredConsts );
		Rid usCheckConvexFast = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufActiveFace, ufPoints, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufBadFaces, ufNonconvexBadFaces, ufPredConsts}, _checkTwoThreeFast, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plCheckConvexFast = _rd.ComputePipelineCreate( _checkTwoThreeFast );
		long clCheckConvexFast = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clCheckConvexFast, plCheckConvexFast);
		_rd.ComputeListBindUniformSet(		clCheckConvexFast, usCheckConvexFast, 0);
		_rd.ComputeListDispatch(			clCheckConvexFast,	xGroups: numNonconvexBadFaces, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void checkThreeTwoExact( uint numIndeterminedNonconvexBadFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfNonconvexBadFaces ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFace.AddId( bfActiveFaces );
		RDUniform ufPoints 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufPoints.AddId( _bfPoints );
		RDUniform ufTetra 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufNonconvexBadFaces 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 7}; ufNonconvexBadFaces.AddId( bfNonconvexBadFaces );
		RDUniform ufPredConsts 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 8}; ufPredConsts.AddId( _bfPredConsts );
		Rid usCheckConvexExact = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufActiveFace, ufPoints, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufBadFaces, ufNonconvexBadFaces, ufPredConsts}, _checkTwoThreeExact, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plCheckConvexExact = _rd.ComputePipelineCreate( _checkTwoThreeExact );
		long clCheckConvexExact = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clCheckConvexExact, plCheckConvexExact);
		_rd.ComputeListBindUniformSet(		clCheckConvexExact, usCheckConvexExact, 0);
		_rd.ComputeListDispatch(			clCheckConvexExact,	xGroups: numIndeterminedNonconvexBadFaces, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void markFlipOfTetra( uint numbadFaces, Rid  bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfTetraMarkFlip ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFace		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFace.AddId( bfActiveFaces );
		RDUniform ufTetra 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufTetraMarkFlip 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 7}; ufTetraMarkFlip.AddId( bfTetraMarkFlip );
		RDUniform ufPredConsts 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 8}; ufPredConsts.AddId( _bfPredConsts );
		Rid usMarkFlipOfTetra = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufActiveFace, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufBadFaces,ufTetraMarkFlip}, _markFlipOfTetra, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plMarkFlipOfTetra = _rd.ComputePipelineCreate( _markFlipOfTetra );
		long clMarkFlipOfTetra = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clMarkFlipOfTetra, plMarkFlipOfTetra);
		_rd.ComputeListBindUniformSet(		clMarkFlipOfTetra, usMarkFlipOfTetra, 0);
		_rd.ComputeListDispatch(			clMarkFlipOfTetra,	xGroups: numbadFaces, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void checkFlipOfTetra( uint numbadFaces, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfTetraMarkFlip ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufActiveFace		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufActiveFace.AddId( bfActiveFaces );
		RDUniform ufTetra 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 2}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 3}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufTetraToFace		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 4}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufFlipInfo 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 5}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 6}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufTetraMarkFlip 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 7}; ufTetraMarkFlip.AddId( bfTetraMarkFlip );
		Rid usCheckFlipOfTetra = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufActiveFace, ufTetra, ufFaceToTetra, ufTetraToFace, ufFlipInfo, ufBadFaces,ufTetraMarkFlip}, _checkFlipOfTetra, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plCheckFlipOfTetra = _rd.ComputePipelineCreate( _checkFlipOfTetra );
		long clCheckFlipOfTetra = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clCheckFlipOfTetra, plCheckFlipOfTetra);
		_rd.ComputeListBindUniformSet(		clCheckFlipOfTetra, usCheckFlipOfTetra, 0);
		_rd.ComputeListDispatch(			clCheckFlipOfTetra,	xGroups: numbadFaces, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void finalizeTetraMarkedFlip( Rid bfTetraMarkedFlip, Rid bfFlipInfo){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufTetraMarkedFlip = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 0}; ufTetraMarkedFlip.AddId( bfTetraMarkedFlip );
		RDUniform ufFlipInfo = new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 1}; ufFlipInfo.AddId( bfFlipInfo );
		Rid usFinalizeTetraMarkedFlip = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{ ufTetraMarkedFlip, ufFlipInfo }, _finalizeTetraMarkedFlip, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plFinalizeTetraMarkedFlip = _rd.ComputePipelineCreate( _finalizeTetraMarkedFlip );
		long clFinalizeTetraMarkedFlip = 	_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clFinalizeTetraMarkedFlip, plFinalizeTetraMarkedFlip);
		_rd.ComputeListBindUniformSet(		clFinalizeTetraMarkedFlip, usFinalizeTetraMarkedFlip, 0);
		_rd.ComputeListDispatch(			clFinalizeTetraMarkedFlip,	xGroups: _lastTetra + 1, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}


	private void freeSimplices(uint numThreeTwoFlips, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfBadFacesToThreeTwoFlip, Rid bfFreeOffsets ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufTetraToFace				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  0}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufTetraToEdge 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  1}; ufTetraToEdge.AddId( _bfTetraToEdge );
		RDUniform ufFaceToTetra				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  2}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufActiveFaces				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  3}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufFlipInfo 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  4}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  5}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufBadFacesToTwoThreeFlip	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  6}; ufBadFacesToTwoThreeFlip.AddId( bfBadFacesToThreeTwoFlip );
		RDUniform ufFreedTetra				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  7}; ufFreedTetra.AddId( _bfFreedTetra );
		RDUniform ufFreedFaces				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  8}; ufFreedFaces.AddId( _bfFreedFaces );
		RDUniform ufFreedEdges				= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  9}; ufFreedEdges.AddId( _bfFreedEdges );
		RDUniform ufFreeOffsets 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 10}; ufFreeOffsets.AddId( bfFreeOffsets );
		Rid usFreeSimplices = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{
			ufTetraToFace, ufTetraToEdge, ufFaceToTetra, ufActiveFaces, ufFlipInfo, ufBadFaces, ufBadFacesToTwoThreeFlip, ufFreedTetra, ufFreedFaces, ufFreedEdges, ufFreeOffsets }, _freeSimplices, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plFreeSimplices = _rd.ComputePipelineCreate( _freeSimplices );
		long clFreeSimplices = 			_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clFreeSimplices, plFreeSimplices);
		_rd.ComputeListBindUniformSet(		clFreeSimplices, usFreeSimplices, 0);
		_rd.ComputeListDispatch(			clFreeSimplices,	xGroups: numThreeTwoFlips, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}






private void locatePointInFlipFast( uint numPointsInFlips, Rid bfPointsInFlips, Rid bfTetraMarkedFlip, Rid bfLocations, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfFlipPrefixSum, Rid bfThreeTwoAtFlip, Rid bfFlipOffsets ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPoints 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  0}; ufPoints.AddId( _bfPoints );
		RDUniform ufPointsToAdd 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  1}; ufPointsToAdd.AddId( _bfPointsToAdd );
		RDUniform ufTetOfPoints 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  2}; ufTetOfPoints.AddId( _bfTetraOfPoints );
		RDUniform ufPointsInFlips	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  3}; ufPointsInFlips.AddId( bfPointsInFlips );
		RDUniform ufTetraMarkedFlip	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  4}; ufTetraMarkedFlip.AddId( bfTetraMarkedFlip );
		RDUniform ufLocations		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  5}; ufLocations.AddId( bfLocations );
		RDUniform ufTetra 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  6}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  7}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufActiveFaces		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  8}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufFlipInfo 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  9}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 10}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufFlipPrefixSum 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 11}; ufFlipPrefixSum.AddId( bfFlipPrefixSum );
		RDUniform ufThreeTwoAtFlip 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 12}; ufThreeTwoAtFlip.AddId( bfThreeTwoAtFlip );
		RDUniform ufFreedTetra		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 13}; ufFreedTetra.AddId( _bfFreedTetra );
		RDUniform ufPredConsts 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 14}; ufPredConsts.AddId( _bfPredConsts );
		RDUniform ufFlipOffsets 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 15}; ufFlipOffsets.AddId( bfFlipOffsets );
		Rid usFlipLocate_Fast = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{
			ufPoints, ufPointsToAdd, ufTetOfPoints, ufPointsInFlips, ufTetraMarkedFlip, ufLocations, ufTetra, ufFaceToTetra, ufActiveFaces, ufFlipInfo, ufBadFaces, ufFlipPrefixSum, ufThreeTwoAtFlip, ufFreedTetra, ufPredConsts, ufFlipOffsets}, _flipLocate_fast, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plFlipLocate_Fast = _rd.ComputePipelineCreate( _flipLocate_fast );
		long clFlipLocate_Fast = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clFlipLocate_Fast, plFlipLocate_Fast);
		_rd.ComputeListBindUniformSet(		clFlipLocate_Fast, usFlipLocate_Fast, 0);
		_rd.ComputeListDispatch(			clFlipLocate_Fast,	xGroups: numPointsInFlips, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void locatePointInFlipExact( uint numPointsInFlips, Rid bfBadPoints, Rid bfPointsInFlips, Rid bfTetraMarkedFlip, Rid bfLocations, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfFlipPrefixSum, Rid bfThreeTwoAtFlip, Rid bfFlipOffsets ){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufPoints 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  0}; ufPoints.AddId( _bfPoints );
		RDUniform ufPointsToAdd 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  1}; ufPointsToAdd.AddId( _bfPointsToAdd );
		RDUniform ufTetOfPoints 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  2}; ufTetOfPoints.AddId( _bfTetraOfPoints );
		RDUniform ufBadPoints 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  3}; ufBadPoints.AddId( bfBadPoints );
		RDUniform ufPointsInFlips	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  4}; ufPointsInFlips.AddId( bfPointsInFlips );
		RDUniform ufTetraMarkedFlip	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  5}; ufTetraMarkedFlip.AddId( bfTetraMarkedFlip );
		RDUniform ufLocations		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  6}; ufLocations.AddId( bfLocations );
		RDUniform ufTetra 			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  7}; ufTetra.AddId( _bfTetra );
		RDUniform ufFaceToTetra 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  8}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufActiveFaces		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  9}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufFlipInfo 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 10}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 11}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufFlipPrefixSum 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 12}; ufFlipPrefixSum.AddId( bfFlipPrefixSum );
		RDUniform ufThreeTwoAtFlip 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 13}; ufThreeTwoAtFlip.AddId( bfThreeTwoAtFlip );
		RDUniform ufFreedTetra		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 14}; ufFreedTetra.AddId( _bfFreedTetra );
		RDUniform ufPredConsts 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 15}; ufPredConsts.AddId( _bfPredConsts );
		RDUniform ufFlipOffsets 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 16}; ufFlipOffsets.AddId( bfFlipOffsets );
		Rid usFlipLocateExact = _rd.UniformSetCreate( new Godot.Collections.Array<RDUniform>{
			ufPoints, ufPointsToAdd, ufTetOfPoints, ufBadPoints, ufPointsInFlips, ufTetraMarkedFlip, ufLocations, ufTetra, ufFaceToTetra, ufActiveFaces, ufFlipInfo, ufBadFaces, ufFlipPrefixSum, ufThreeTwoAtFlip, ufFreedTetra, ufPredConsts, ufFlipOffsets}, _flipLocate_exact, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plFlipLocateExact = _rd.ComputePipelineCreate( _flipLocate_exact );
		long clFlipLocateExact = 		_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clFlipLocateExact, plFlipLocateExact);
		_rd.ComputeListBindUniformSet(		clFlipLocateExact, usFlipLocateExact, 0);
		_rd.ComputeListDispatch(			clFlipLocateExact,	xGroups: numPointsInFlips, yGroups: 1, zGroups: 1);
										_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

	private void flipTetra(uint numFlips, Rid bfActiveFaces, Rid bfFlipInfo, Rid bfBadFaces, Rid bfBadFacesToFlip, Rid bfThreeTwoAtFlip, Rid bfNewActiveFaces, Rid bfFlipOffsets){
		// ---------------------------------------	uniforms	---------------------------------------
		RDUniform ufTetra			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  0}; ufTetra.AddId( _bfTetra );
		RDUniform ufTetraToFace		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  1}; ufTetraToFace.AddId( _bfTetraToFace );
		RDUniform ufTetraToEdge 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  2}; ufTetraToEdge.AddId( _bfTetraToEdge );
		RDUniform ufFace			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  3}; ufFace.AddId( _bfFace );
		RDUniform ufFaceToTetra		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  4}; ufFaceToTetra.AddId( _bfFaceToTetra );
		RDUniform ufEdge			= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  5}; ufEdge.AddId( _bfEdge );
		RDUniform ufActiveFaces		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  6}; ufActiveFaces.AddId( bfActiveFaces );
		RDUniform ufFlipInfo 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  7}; ufFlipInfo.AddId( bfFlipInfo );
		RDUniform ufBadFaces 		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  8}; ufBadFaces.AddId( bfBadFaces );
		RDUniform ufBadFacesToFlip 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding =  9}; ufBadFacesToFlip.AddId( bfBadFacesToFlip );
		RDUniform ufThreeTwoAtFlip 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 10}; ufThreeTwoAtFlip.AddId( bfThreeTwoAtFlip );
		RDUniform ufFreedTetra		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 11}; ufFreedTetra.AddId( _bfFreedTetra );
		RDUniform ufFreedFaces		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 12}; ufFreedFaces.AddId( _bfFreedFaces );
		RDUniform ufFreedEdges		= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 13}; ufFreedEdges.AddId( _bfFreedEdges );
		RDUniform ufNewActiveFaces	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 14}; ufNewActiveFaces.AddId( bfNewActiveFaces );
		RDUniform ufFlipOffsets 	= new RDUniform{UniformType = RenderingDevice.UniformType.StorageBuffer, Binding = 15}; ufFlipOffsets.AddId( bfFlipOffsets );
		Rid usFlipTetra = _rd.UniformSetCreate(new Godot.Collections.Array<RDUniform>{
			ufTetra, ufTetraToFace, ufTetraToEdge, ufFace, ufFaceToTetra, ufEdge, ufActiveFaces, ufFlipInfo, ufBadFaces,
            ufBadFacesToFlip, ufThreeTwoAtFlip, ufFreedTetra, ufFreedFaces, ufFreedEdges, ufNewActiveFaces, ufFlipOffsets }, _flipTetra, 0);
		// ---------------------------------------	pipeline	---------------------------------------
		Rid  plFlipTetra = _rd.ComputePipelineCreate( _flipTetra );
		long clFlipTetra = 			_rd.ComputeListBegin();	// ----------------------------------------------
		_rd.ComputeListBindComputePipeline( clFlipTetra, plFlipTetra);
		_rd.ComputeListBindUniformSet(		clFlipTetra, usFlipTetra, 0);
		_rd.ComputeListDispatch(			clFlipTetra,	xGroups: numFlips, yGroups: 1, zGroups: 1);
									_rd.ComputeListEnd();	// ----------------------------------------------
		// ---------------------------------------	Compute!	---------------------------------------
		_rd.Submit();
		_rd.Sync();
	}

}