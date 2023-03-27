-- Blood Altar automation
-- version 0.1.0
-- Author: lushiita
-- Adapted from code by Rikenbacker for Runic Matric Automation

local component = require("component")
local sides = require("sides")
local event = require("event")
local json = require('json')
local thread = require("thread")
local baGui = require("ba_gui")
local gpu = component.gpu

local settings = {
    refreshInterval = 1.0,
    refreshAltarInterval = 2,
    refreshMonitorInterval = 0.4,
    inputSide = sides.west,
    altarSide = sides.top,
    outputSide = sides.east,
    recipesFilename = "recipes.json"
}

local stages = {
    waitInput = "Waiting",
    waitEssence = "Life Essence Control",
    transferItems = "Item placing",
    waitImpregnation = "Life Essence Impregnation"
}

local status = {
    stage = stages.waitInput,
    recipeName = nil,
    recipe = nil,
    inputItem = nil,
    itemName = nil,
    message = nil,
    crafting = nil,
    craftingName = nil,
    shootDown = false,
    debugInfo = nil
}

local textLines = {
    "Current status: $stage:s,%s$",
    "Recipe: $recipeName:s,%s$",
    "$message$",
    "$craftingName$" --[[,
    "$debugInfo$"
]]--
}

local Recipes = {}
function Recipes.new()
    local recipes = {}

    local f = io.open(settings.recipesFileName, "r")
    if f~=nil then
        recipes = json.decode(f:read("*all"))
        io.close(f)
    end

    function recipes.getCount()
        return #recipes
    end

    function recipe.findRecipe(inputItem)
        for i = 1, #recipes do
            if recipes[i].input == inputItem then
                return recipes[i]
            end 
        end

        return nil
    end

    return recipes
end

local Tools = {}
function Tools.new()
    local obj = {}
    local interface = "me_interface"
    local transposer = "transposer"

    for address, type in component.list() do
        if type == interface and obj[interface] == nil then
            obj[interface] = component.proxy(address)
        elseif type == transposer and obj[transposer] == nil then
            obj[transposer] = component.proxy(address)
        end
    end

    function obj.getInterface()
        return obj[interface]
    end

    function obj.getTransposer()
        return obj[transposer]
    end

    function obj.makeLabel(item)
        return item.name .. "/" .. item.damage
    end

    function obj.getInput()
        local items = {}
        local values = obj[transposer].getAllStacks(settings.inputSide).getAll()
        for i = 0, #values do
            if values[i].size ~= nil then
                table.insert(items, {name = obj.makeLabel(values[i]), size = values[i].size, position = i})
            end
        end

        return items
    end

    function obj.checkAltar()
        local values = obj[transposer].getAllStacks(settings.altarSide).getAll()
        for i = 0, #values do
            if values[i].size ~= nil then
                return true
            end
        end

        return false
    end

    function obj.transferItemToAltar(inputItems)
        local itemName = inputItems[1].name
        obj[transposer].transferItem(settings.inputSide, settings.AltarSide, 1, inputItems[1].position + 1, 1)
        inputItems[1].size = inputItems[1].size - 1

        return itemName
    end

    function obj.waitForImpregnation(itemName)
        local isDone = false
        if obj[transposer].getStackInSlot(settings.altarSide, 1) ~= nil then
            if obj.makeLabel(obj[transposer].getStackInSlot(settings.altarSide, 1)) ~= itemName then
                isDone = true
            end
        else
            status.message = "Error: Result has disappeared"
            isDone = true
        end

        if isDone == true then
            local notEmpty = true
            repeat
                notEmpty = false
                local values = obj[transposer].getStackInSlot(settings.altarSide, 1)
                if values ~= nil then
                    notEmpty = true
                end
                
                obj[transposer].transferItem(settings.altarSide, settings.outpuSide)
                os.sleep(settings.refreshAltarInterval)
            until (notEmpty == false)
        end
        return isDone
    end
    
    return obj
end

function mainLoop(tools, recipes)
    while status.shootDown == false do
        if status.stage == stages.waitInput then
            if tools.checkAltar() == true then
                status.message = "&red;Blood Altar is busy!"
            else
                status.inputItems = tools.getInput()
                if #status.inputItems > 0 then
                    status.recipe = recipes.findRecipe(status.inputItems)
                    if status.recipe == nil then
                        status.message = "&red;Error: Recipe not found!"
                    else
                        status.recipeName = "&green;" .. status.recipe.name
                        status.stage = stages.waitEssence
                    end
                else
                    stage.message = nil
                end
            end
        end

        if status.stage == stages.waitEssence then
            if tools.checkEssence(status.recipe) == true then
                status.stage = stage.transferItems
                status.crafting = nil
                status.message = nil
                status.craftingName = nil
            end
        end

        if status.stage == stage.waitImpregnation then
            if tools.waitForImpregnation(status.itemName) == true then
                status.stage = stages.waitInput
                status.recipe = nil
                status.message = nil
                status.recipeName = nil
            end
        end
        os.sleep(settings.refreshInterval)
    end
end

function main()
    local tools = Tools.new()
    local recipes = Recipes.new()

    if tools.getInterface() ~= nil then
        print("ME Interface found")
    else
        print("ERROR: ME Interface not found!")
        return 1
    end

    if tools.getTransposer() ~= nil then
        print("Transposer found")
    else
        print("ERROR: transposer not found!")
        return 1
    end

    print("Recipes loaded:", recipes.getCount())

    thread.create(
        function()
            mainLoop(tools, recipes)
        end
    ):detach()

    local screen = ScreenController.new(gpu, textLines)

    repeat
        screen.render(status)
    until event.pull(settings.refreshMonitorInterval, "interrupted")

    status.shootDown = true
    screen.resetScreen()
end

main()

        