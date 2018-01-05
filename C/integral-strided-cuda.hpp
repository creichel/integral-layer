namespace strided {

void forwardNoNormReplicateCuda(
    const float *intData, const int intDataStrideChannel, float *outData,
    const int h, const int w, const int nInputPlane, const int nWindows,
    const float *xMin, const float *xMax, const float *yMin, const float *yMax,
    const int strideH, const int strideW);

void forwardNoNormReplicateFracCuda(
    const float *intData, const int intDataStrideChannel, float *outData,
    const int h, const int w, const int nInputPlane, const int nWindows,
    const float *xMin, const float *xMax, const float *yMin, const float *yMax,
    const float *inData, const int inDataStrideRow, const int inDataStrideChannel,
    const int strideH, const int strideW);

void updateGradInputCuda(
    const float *gradOutputIntData, float * const gradInputData,
    const int h, const int w, const int nWindows,
    const float * const xMin, const float * const xMax,
    const float * const yMin, const float * const yMax,
    const int strideH, const int strideW);

void updateGradInputFracCuda(
    const float *gradOutputIntData, float * const gradInputData,
    const int h, const int w, const int nWindows,
    const float *xMin, const float *xMax, const float *yMin, float *yMax,
    const float *gradOutputData, const int gradOutputStrideRow,
    const int gradOutputStrideChannel,
    const int strideH, const int strideW);

void backwardFracCuda(
    const float *intData, float *tmpArray,
    const int nWindows, const int h, const int w,
    const float * const xMin, const float * const xMax,
    const float * const yMin, const float * const yMax,
    const float *inData, const int inDataStrideRow,
    const int strideH, const int strideW);

void backwardCuda(
    const float *intData, float *tmpArray,
    const int nWindows, const int h, const int w,
    const float * const xMin, const float * const xMax,
    const float * const yMin, const float * const yMax,
    const int strideH, const int strideW);

}
