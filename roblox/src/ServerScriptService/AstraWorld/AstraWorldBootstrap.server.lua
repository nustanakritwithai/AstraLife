local WorldService = require(script.Parent.WorldService)

local runtime = WorldService.Start({
    seed = 20904,
    fixedStep = 0.25,
    width = 64,
    depth = 64,
    cellSize = 16,
    maxCatchUpSteps = 8,
})

print(string.format(
    "[AstraLife][W0] Living World foundation started seed=%d grid=%dx%d cell=%d",
    runtime.config.seed,
    runtime.config.width,
    runtime.config.depth,
    runtime.config.cellSize
))
