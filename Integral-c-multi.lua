require 'nn'

ffi = require 'ffi'

local _, parent = torch.class('Integral', 'nn.Module')

ffi.cdef [[

void forward(
    void *intData, int h, int w, void *outData,
    int xMinCurr, int xMaxCurr, int yMinCurr, int yMaxCurr, float areaCoeff);

void backward(
    void *intData, void *gradOutData, int h, int w, void *deltas,
    int xMinCurr, int xMaxCurr, int yMinCurr, int yMaxCurr);

]]

local C = ffi.load('C/lib/libintegral-c.so')

do
    cv = require 'cv'
    require 'cv.imgproc'
    require 'cv.highgui'

    function Integral:__init(nWindows, h, w)
        parent.__init(self)
        self.nWindows, self.h, self.w = nWindows, h, w
        self.output = torch.Tensor(self.nWindows, h, w)
        self.integralDouble = torch.DoubleTensor()
        self.integral = torch.FloatTensor()
        self:reset()
        self:zeroGradParameters()
    end

    -- renew normalization coeffs
    function Integral:recalculateArea()
        for i = 1,self.nWindows do
            self.areaCoeff[i] = 
                1 / ((self.xMax[i]-self.xMin[i]+1)*(self.yMax[i]-self.yMin[i]+1))
        end
    end

    function Integral:reset()
        -- the only parameters of the module. Randomly initialize them
        self.xMin = torch.round((torch.rand(self.nWindows) - 0.5) * (2 * self.h * 0.3))
        self.yMin = torch.round((torch.rand(self.nWindows) - 0.5) * (2 * self.w * 0.3))
        self.xMax = torch.Tensor(self.nWindows)
        self.yMax = torch.Tensor(self.nWindows)
        
        for i = 1,self.nWindows do
            self.xMax[i] = torch.round(torch.uniform(self.xMin[i] + self.h * 0.05, self.xMin[i] + self.h * 0.25))
            self.yMax[i] = torch.round(torch.uniform(self.yMin[i] + self.w * 0.05, self.yMin[i] + self.w * 0.25))
        end
        
        -- area to normalize over
        self.areaCoeff = torch.Tensor(self.nWindows)
        self:recalculateArea()
        
        -- loss gradients wrt module's parameters
        self.gradXMin = torch.zeros(self.xMin:size())
        self.gradYMin = torch.zeros(self.xMin:size())
        self.gradXMax = torch.zeros(self.xMin:size())
        self.gradYMax = torch.zeros(self.xMin:size())
    end

    function Integral:parameters()
        local params = {self.xMin, self.xMax, self.yMin, self.yMax}
        local gradParams = {self.gradXMin, self.gradXMax, self.gradYMin, self.gradYMax}
        return params, gradParams
    end

    local function round_towards_zero(x)
        if x >= 0 then return math.floor(x) 
        else return math.floor(x) end
    end

    function Integral:updateOutput(input)
        if input:nDimension() == 2 then
            input = nn.Unsqueeze(1):forward(input)
        end
        
        assert(input:size(2) == self.h and input:size(3) == self.w)

        self.output:resize(input:size(1)*self.nWindows, input:size(2), input:size(3))
        
        self.integralDouble:resize(input:size(1), input:size(2)+1, input:size(3)+1)
        self.integral:resize(self.integralDouble:size())

        for inPlaneIdx = 1,input:size(1) do
            cv.integral{input[inPlaneIdx], self.integralDouble[inPlaneIdx]}
            self.integral[inPlaneIdx]:copy(self.integralDouble[inPlaneIdx]) -- cast
        
            for nWindow = 1,self.nWindows do
                
                -- round towards zero (?)
                local xMinCurr = round_towards_zero(self.xMin[nWindow])
                local xMaxCurr = round_towards_zero(self.xMax[nWindow])+1
                local yMinCurr = round_towards_zero(self.yMin[nWindow])
                local yMaxCurr = round_towards_zero(self.yMax[nWindow])+1
                
                -- round down (?)
        --         local xMinCurr = torch.round(self.xMin[nWindow] - 0.499)
        --         local xMaxCurr = torch.round(self.xMax[nWindow] - 0.499)+1
        --         local yMinCurr = torch.round(self.yMin[nWindow] - 0.499)
        --         local yMaxCurr = torch.round(self.yMax[nWindow] - 0.499)+1
                
                local outPlaneIdx = self.nWindows*(inPlaneIdx-1) + nWindow
                local outPlane = self.output[outPlaneIdx]
                
                local outData = torch.data(outPlane)
                local intData = torch.data(self.integral[inPlaneIdx])
                
                -- must add 1 to xMax/yMax/xMin/yMin due to OpenCV's
                -- `integral()` behavior. Namely, I(x,0) and I(0,y) are
                -- always 0 (so it's a C-style array sum).
                
                C.forward(
                    intData, self.h, self.w, outData, 
                    xMinCurr, xMaxCurr, yMinCurr, yMaxCurr,
                    self.areaCoeff[nWindow])
            end
        end
        
        return self.output
    end

    function Integral:updateGradInput(input, gradOutput)
        if self.gradInput then
            -- never call :backward() on backpropHelper!
            self.backpropHelper = self.backpropHelper or Integral(1, self.h, self.w)
        
            self.gradInput:resize(input:size()):zero()
            
            for inPlaneIdx = 1,input:size(1) do
                for nWindow = 1,self.nWindows do
                    self.backpropHelper.xMin[1] = -self.xMax[nWindow]
                    self.backpropHelper.xMax[1] = -self.xMin[nWindow]
                    self.backpropHelper.yMin[1] = -self.yMax[nWindow]
                    self.backpropHelper.yMax[1] = -self.yMin[nWindow]
                    self.backpropHelper:recalculateArea()
                    
                    local outPlaneIdx = self.nWindows*(inPlaneIdx-1) + nWindow

                    self.gradInput[inPlaneIdx]:add(
                        self.backpropHelper:forward(gradOutput[outPlaneIdx]):squeeze())
                end
            end
            
            return self.gradInput
        end
    end

    function Integral:accGradParameters(input, gradOutput, scale)
        scale = scale or 1
        
        for inPlaneIdx = 1,input:size(1) do
            for nWindow = 1,self.nWindows do
                local outPlaneIdx = self.nWindows*(inPlaneIdx-1) + nWindow
                local outputDot = torch.dot(self.output[outPlaneIdx], gradOutput[outPlaneIdx])
                
                -- round towards zero (?)
                -- and +1 because OpenCV's integral adds extra row and col
                local xMinCurr = round_towards_zero(self.xMin[nWindow])
                local xMaxCurr = round_towards_zero(self.xMax[nWindow])
                local yMinCurr = round_towards_zero(self.yMin[nWindow])
                local yMaxCurr = round_towards_zero(self.yMax[nWindow])

                local gradOutData = torch.data(gradOutput[outPlaneIdx])
                local intData = torch.data(self.integral[inPlaneIdx])
                
                -- deltas of dOut(x,y) (sum over one window)
                local deltas = ffi.new('float[4]')
                
                C.backward(
                    intData, gradOutData, self.h, self.w, deltas,
                    xMinCurr, xMaxCurr, yMinCurr, yMaxCurr)

                local xMinDelta, xMaxDelta = deltas[0], deltas[1]
                local yMinDelta, yMaxDelta = deltas[2], deltas[3]
                
                self.gradXMax[nWindow] = self.gradXMax[nWindow] + scale * (
                    xMaxDelta * self.areaCoeff[nWindow] -
                    outputDot / (self.xMax[nWindow] - self.xMin[nWindow] + 1))
                self.gradXMin[nWindow] = self.gradXMin[nWindow] + scale * (
                    xMinDelta * self.areaCoeff[nWindow] +
                    outputDot / (self.xMax[nWindow] - self.xMin[nWindow] + 1))
                self.gradYMax[nWindow] = self.gradYMax[nWindow] + scale * (
                    yMaxDelta * self.areaCoeff[nWindow] -
                    outputDot / (self.yMax[nWindow] - self.yMin[nWindow] + 1))
                self.gradYMin[nWindow] = self.gradYMin[nWindow] + scale * (
                    yMinDelta * self.areaCoeff[nWindow] +
                    outputDot / (self.yMax[nWindow] - self.yMin[nWindow] + 1))
            end
        end
    end

    function Integral:zeroGradParameters()
        self.gradXMin:zero()
        self.gradYMin:zero()
        self.gradXMax:zero()
        self.gradYMax:zero()
    end

    function Integral:updateParameters(lr)
        self.xMin:add(lr, self.gradXMin)
        self.yMin:add(lr, self.gradYMin)
        self.xMax:add(lr, self.gradXMax)
        self.yMax:add(lr, self.gradYMax)
        
        self:recalculateArea()
    end
end