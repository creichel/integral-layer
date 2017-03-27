torch.setdefaulttensortype('torch.FloatTensor')

require 'image'
local lena = image.lena():mean(1):squeeze()[{{1,4}, {1,4}}]

Integral = nil
debug.getregistry()['Integral'] = nil 
package.loaded['Integral-c'] = nil
package.loaded['Integral-c-multi'] = nil
package.loaded['Integral-jit'] = nil
package.loaded['Integral-jit-multi'] = nil
package.loaded['Integral-cuda-multi'] = nil
require 'Integral-jit-multi'

-- compute true forward and backward results for some data
local intGold = Integral(3, 4, 4)
local params, gradParamsGold = intGold:getParameters()

local forwardGold = intGold:forward(lena)
local gradInputGold = intGold:backward(lena, forwardGold)

-- remove the old slow class
Integral = nil
debug.getregistry()['Integral'] = nil 
package.loaded['Integral-c'] = nil
package.loaded['Integral-c-multi'] = nil
package.loaded['Integral-jit'] = nil
package.loaded['Integral-jit-multi'] = nil
package.loaded['Integral-cuda-multi'] = nil

-- require the new fast class
require 'Integral-cuda-multi'

local intTest = Integral(3, 4, 4):cuda()
local paramsTest, gradParamsTest = intTest:getParameters()

paramsTest:copy(params)
intTest:recalculateArea()

-- compare results
lena = lena:cuda()

local forwardTest = intTest:forward(lena)

local forwardErr = (forwardGold - forwardTest:float()):abs():sum() / 
                   forwardTest:nElement() / torch.abs(forwardGold):mean()
print('Output mean relative error:', forwardErr * 100 .. ' %')

local gradInputTest = intTest:backward(lena, forwardGold:cuda())
local gradInputErr = (gradInputGold - gradInputTest:float()):abs():sum() / 
                     gradInputTest:nElement() / torch.abs(gradInputGold):mean()
print('gradInput mean relative error:', gradInputErr * 100 .. ' %')
local gradParamsErr = (gradParamsGold - gradParamsTest):abs():sum() / 
                      gradParamsTest:nElement() / torch.abs(gradParamsGold):mean()
print('gradParams mean relative error:', gradParamsErr * 100 .. ' %')

assert(forwardErr    < 1e-6)
assert(gradInputErr  < 1e-6)
assert(gradParamsErr < 7e-4)