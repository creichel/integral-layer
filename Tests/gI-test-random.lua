require 'torch'
torch.setdefaulttensortype('torch.FloatTensor')

require 'IntegralSmartNorm'

local seed = os.time()
-- seed = 1504623733
print('Random seed is ' .. seed)
torch.manualSeed(seed)
math.randomseed(seed)

local h,w = math.random(2, 400), math.random(2, 400)
print('h, w = ' .. h .. ', ' .. w)

int = IntegralSmartNorm(2, 2, h, w)

local testType = 'corner' -- 'corner' | 'border' | 'inner'

local targetX, targetY
if testType == 'inner' then
    targetX = math.random(2, h-1)
    targetY = math.random(2, w-1)
elseif testType == 'corner' then
    targetX = ({1,h})[math.random(1,2)]
    targetY = ({1,w})[math.random(1,2)]
elseif testType == 'border' then
    if math.random(1,2) == 1 then
        -- vertical border
        targetX = math.random(2, h-1)
        targetY = ({1,w})[math.random(1,2)]
    else
        -- horizontal border
        targetX = ({1,h})[math.random(1,2)]
        targetY = math.random(2, w-1)
    end
end
local targetPlane = math.random(1, int.nInputPlane)

print('targetX, targetY, targetPlane = ' .. targetX .. ', ' .. targetY .. ', ' .. targetPlane)

int.exact = true
int.smart = true
int.replicate = true
int.normalize = true
crit = nn.MSECriterion()

img = torch.rand(int.nInputPlane, h, w)
target = torch.rand(int.nInputPlane*int.nWindows, h, w):add(-0.5):mul(0.1)

local function rand(a,b)
	return torch.rand(1)[1] * (b-a) + a
end

for planeIdx = 1,int.nInputPlane do
    for winIdx = 1,int.nWindows do
        local xMin, yMin = rand(-h+1, h-2), rand(-w+1, w-2)
        local xMax, yMax = rand(xMin+1, h-1), rand(yMin+1, w-1)

        int.xMin[planeIdx][winIdx] = xMin
        int.xMax[planeIdx][winIdx] = xMax
        int.yMin[planeIdx][winIdx] = yMin
        int.yMax[planeIdx][winIdx] = yMax

        print('int.xMin[' .. planeIdx .. '][' .. winIdx .. '] = ' .. xMin)
        print('int.xMax[' .. planeIdx .. '][' .. winIdx .. '] = ' .. xMax)
        print('int.yMin[' .. planeIdx .. '][' .. winIdx .. '] = ' .. yMin)
        print('int.yMax[' .. planeIdx .. '][' .. winIdx .. '] = ' .. yMax)
        print('')
    end
end

int:forward(img)

target:add(int.output)

loss = crit:forward(int.output, target)
gradOutput = crit:updateGradInput(int.output, target)

int:zeroGradParameters()
int:backward(img, gradOutput)

params = {}
loss = {}
deriv = {}
derivM = {}

local k = 1
local step = 1--0.1
local innerStep = 1--0.004

for param = -5,5,step do
    img[{targetPlane, targetX, targetY}] = param
    pred = int:forward(img)

    params[k] = param
    loss[k] = crit:forward(pred, target)

    int:zeroGradParameters()
    int:backward(img, crit:updateGradInput(pred, target))
    derivM[k] = int.gradInput[{targetPlane, targetX, targetY}]
    
    img[{targetPlane, targetX, targetY}] = param + innerStep
    valFront = crit:forward(int:forward(img), target)
    img[{targetPlane, targetX, targetY}] = param - innerStep
    valBack = crit:forward(int:forward(img), target)
    
    deriv[k] = (valFront - valBack) / (2 * innerStep)

    -- img[{targetPlane, targetX, targetY}] = param + innerStep
    -- valFront = crit:forward(int:forward(img), target)
    -- deriv[k] = (valFront - loss[k]) / innerStep
    
    k = k + 1
end

-- loss[#loss] = nil
-- params[#params] = nil
-- derivM[#derivM] = nil

require 'gnuplot'

gnuplot.plot(
    {'Loss', torch.Tensor(params), torch.Tensor(loss), '-'},
    {'Diff', torch.Tensor(params), torch.Tensor(deriv), '-'},
    {'Manual', torch.Tensor(params), torch.Tensor(derivM), '-'}
)

gnuplot.grid(true)