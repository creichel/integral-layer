local w, h, nClasses = ...
assert(w)
assert(h)
assert(nClasses)

require 'nn'
require 'cudnn'

local SpatialConvolution = cudnn.SpatialConvolution
local SpatialDilatedConvolution = nn.SpatialDilatedConvolution
local SpatialFullConvolution = cudnn.SpatialFullConvolution
local ReLU = cudnn.ReLU
local SpatialBatchNormalization = cudnn.SpatialBatchNormalization
local SpatialMaxPooling = cudnn.SpatialMaxPooling

collectgarbage()

local function downsampler(inChannels, outChannels, dropoutProb)
    dropoutProb = dropoutProb or 0

    return nn.Sequential()
        :add(nn.Concat(2)
            :add(SpatialMaxPooling(2,2, 2,2, 0,0))
            :add(SpatialConvolution(inChannels, outChannels-inChannels, 3,3, 2,2, 1,1)))
        :add(SpatialBatchNormalization(outChannels))
        :add(dropoutProb ~= 0 and nn.SpatialDropout(dropoutProb) or nn.Identity())
        :add(ReLU(true))
end

local function upsampler(inChannels, outChannels)
    return nn.Sequential()
        :add(SpatialFullConvolution(inChannels, outChannels, 3,3, 2,2, 1,1, 1,1))
        :add(ReLU(true))
        :add(SpatialBatchNormalization(outChannels))
end

local function nonBt1D(inChannels, dropoutProb, dilation)
    dilation = dilation or 1
    dropoutProb = dropoutProb or 0

    local convs = nn.Sequential()
        :add(SpatialConvolution(inChannels, inChannels, 3,1, 1,1, 1,0))
        :add(ReLU(true))
        :add(SpatialConvolution(inChannels, inChannels, 1,3, 1,1, 0,1))
        :add(SpatialBatchNormalization(inChannels))
        :add(ReLU(true))

    if dilation == 1 then convs
        :add(SpatialConvolution(inChannels, inChannels, 3,1, 1,1, 1,0))
        :add(ReLU(true))
        :add(SpatialConvolution(inChannels, inChannels, 1,3, 1,1, 0,1))
    else convs
        :add(SpatialDilatedConvolution(inChannels, inChannels, 3,1, 1,1, dilation,0, dilation,dilation))
        :add(ReLU(true))
        :add(SpatialDilatedConvolution(inChannels, inChannels, 1,3, 1,1, 0,dilation, dilation,dilation))
    end

    convs
        :add(SpatialBatchNormalization(inChannels))
        :add(dropoutProb ~= 0 and nn.SpatialDropout(dropoutProb) or nn.Identity())

    return nn.Sequential()
        :add(nn.ConcatTable()
            :add(nn.Identity())
            :add(convs))
        :add(nn.CAddTable())
        :add(ReLU(true))
end

local model = nn.Sequential()

model:add(downsampler( 3, 16, 0.0 ))
model:add(downsampler(16, 32, 0.03))

model:add(nonBt1D(32, 0.03))

model:add(downsampler(32, 64, 0.3))

-- convs go here
-- 64x128

model:add(upsampler(64, 32))

model:add(nonBt1D(32))

model:add(upsampler(32, 16))

model:add(nonBt1D(16))

model:add(SpatialFullConvolution(16, nClasses, 3,3, 2,2, 1,1, 1,1))

model:add(nn.View(nClasses, w*h):setNumInputDims(3))
model:add(nn.Transpose({2, 1}):setNumInputDims(2))

return model