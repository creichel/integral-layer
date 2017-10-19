local w, h, nClasses = ...
assert(w)
assert(h)
assert(nClasses)

require 'nn'
require 'cudnn'
require 'IntegralSmartNorm'

local SpatialConvolution = cudnn.SpatialConvolution
local SpatialDilatedConvolution = nn.SpatialDilatedConvolution
local SpatialFullConvolution = cudnn.SpatialFullConvolution
local ReLU = cudnn.ReLU
local SpatialBatchNormalization = cudnn.SpatialBatchNormalization
local SpatialMaxPooling = cudnn.SpatialMaxPooling

collectgarbage()

local model = nn.Sequential()

model
    :add(nn.Identity())
    :add(nn.Concat(2)
        :add(IntegralSmartNorm(3, 80, h, w))
        :add(nn.Sequential()
            :add(SpatialConvolution(3, 32, 3,3, 1,1, 1,1))
            :add(ReLU(true))))
    :add(SpatialBatchNormalization(3*80+32))
    :add(SpatialConvolution(3*80+32, 20, 1,1,1,1):noBias())
    :add(SpatialBatchNormalization(20))
    :add(ReLU(true))
    
    :add(nn.ConcatTable() -- 7
        :add(nn.Sequential()
            :add(nn.Concat(2)
                :add(IntegralSmartNorm(20, 18, h, w))
                :add(nn.Sequential()
                    :add(SpatialConvolution(20, 32, 3,3, 1,1, 1,1))
                    :add(ReLU(true))))
            :add(SpatialBatchNormalization(20*18+32))
            :add(SpatialConvolution(20*18+32, 20, 1,1,1,1):noBias()))
        :add(nn.Identity()))
    :add(nn.CAddTable())
    :add(SpatialBatchNormalization(20))
    :add(ReLU(true))

    :add(nn.ConcatTable() -- 11
        :add(nn.Sequential()
            :add(nn.Concat(2)
                :add(IntegralSmartNorm(20, 18, h, w))
                :add(nn.Sequential()
                    :add(SpatialConvolution(20, 32, 3,3, 1,1, 1,1))
                    :add(ReLU(true))))
            :add(SpatialBatchNormalization(20*18+32))
            :add(SpatialConvolution(20*18+32, 20, 1,1,1,1):noBias()))
        :add(nn.Identity()))
    :add(nn.CAddTable())
    :add(SpatialBatchNormalization(20))
    :add(ReLU(true))

    :add(nn.ConcatTable() -- 15
        :add(nn.Sequential()
            :add(nn.Concat(2)
                :add(IntegralSmartNorm(20, 18, h, w))
                :add(nn.Sequential()
                    :add(SpatialConvolution(20, 32, 3,3, 1,1, 1,1))
                    :add(ReLU(true))))
            :add(SpatialBatchNormalization(20*18+32))
            :add(SpatialConvolution(20*18+32, 20, 1,1,1,1):noBias()))
        :add(nn.Identity()))
    :add(nn.CAddTable())
    :add(SpatialBatchNormalization(20))
    :add(ReLU(true))

    :add(nn.ConcatTable() -- 19
        :add(nn.Sequential()
            :add(nn.Concat(2)
                :add(IntegralSmartNorm(20, 18, h, w))
                :add(nn.Sequential()
                    :add(SpatialConvolution(20, 32, 3,3, 1,1, 1,1))
                    :add(ReLU(true))))
            :add(SpatialBatchNormalization(20*18+32))
            :add(SpatialConvolution(20*18+32, 20, 1,1,1,1):noBias()))
        :add(nn.Identity()))
    :add(nn.CAddTable())
    :add(SpatialBatchNormalization(20))
    :add(ReLU(true))

    :add(SpatialConvolution(20, nClasses, 1,1,1,1))

model:add(nn.View(nClasses, w*h):setNumInputDims(3))
model:add(nn.Transpose({2, 1}):setNumInputDims(2))

local GSconfig = {
    {
        l = 1,
        r = 3*80,
        haarConv = model:get(4),
        bn       = model:get(3),
        int      = model:get(2):get(1),
        intInput = model:get(1),
        getHaarConvGradOutput = function() return model:get(5).gradInput end
    },
    {
        l = 1,
        r = 20*18,
        haarConv = model:get(7):get(1):get(3),
        bn       = model:get(7):get(1):get(2),
        int      = model:get(7):get(1):get(1):get(1),
        intInput = model:get(6),
        getHaarConvGradOutput = function() return model:get(8).gradInput[1] end
    },
    {
        l = 1,
        r = 20*18,
        haarConv = model:get(11):get(1):get(3),
        bn       = model:get(11):get(1):get(2),
        int      = model:get(11):get(1):get(1):get(1),
        intInput = model:get(10),
        getHaarConvGradOutput = function() return model:get(12).gradInput[1] end
    },
    {
        l = 1,
        r = 20*18,
        haarConv = model:get(15):get(1):get(3),
        bn       = model:get(15):get(1):get(2),
        int      = model:get(15):get(1):get(1):get(1),
        intInput = model:get(14),
        getHaarConvGradOutput = function() return model:get(16).gradInput[1] end
    },
    {
        l = 1,
        r = 20*18,
        haarConv = model:get(19):get(1):get(3),
        bn       = model:get(19):get(1):get(2),
        int      = model:get(19):get(1):get(1):get(1),
        intInput = model:get(18),
        getHaarConvGradOutput = function() return model:get(20).gradInput[1] end
    },
}

return model, GSconfig