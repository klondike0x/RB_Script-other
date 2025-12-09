--[[
    Auto Chest Collector
    - Press [ to toggle on/off
    - Prioritizes Zone5 chests
    - Also collects nearby size2/3 chests from tier1-4 (within 150 studs)
    - Teleports to highest chest next
    - Refreshes chest list every 10s
    - Clicks E only after teleporting, retries if chest not picked up
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

local TOGGLE_KEY = Enum.KeyCode.LeftBracket
local CHEST_REFRESH_INTERVAL = 10
local NO_CHEST_RETRY_INTERVAL = 5
local NEARBY_RADIUS = 150

local LootZones = Workspace:WaitForChild("LootZones")
local zone5Folder = LootZones:WaitForChild("Zone5")

local enabled = false
local allChests = {}
local unvisitedChests = {}
local pickedChests = {}
local currentChest = nil
local timeSinceLastRefresh = 0
local timeSinceNoChestRetry = 0
local noChestsFound = false

local ValidNearbyChestNames = {
    ["tier1_size2"] = true, ["tier1_size3"] = true,
    ["tier2_size2"] = true, ["tier2_size3"] = true,
    ["tier3_size2"] = true, ["tier3_size3"] = true,
    ["tier4_size2"] = true, ["tier4_size3"] = true,
}

local function isChestValid(model)
    if not model or not model.Parent then return false end
    if not model.PrimaryPart then return false end
    for _, prompt in ipairs(model:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            return true
        end
    end
    return false
end

local function assignPrimaryPartIfMissing(model)
    if not model.PrimaryPart then
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("BasePart") then
                model.PrimaryPart = child
                break
            end
        end
    end
end

local function loadAllZone5Chests()
    allChests = {}
    for _, obj in ipairs(zone5Folder:GetDescendants()) do
        if obj:IsA("Model") then
            assignPrimaryPartIfMissing(obj)
            if obj.PrimaryPart and isChestValid(obj) and not pickedChests[obj] then
                table.insert(allChests, obj)
            end
        end
    end
end

local function refillChests()
    unvisitedChests = {}
    for _, chest in ipairs(allChests) do
        if not pickedChests[chest] then
            table.insert(unvisitedChests, chest)
        end
    end
end

local function cleanChestLists()
    for i = #allChests, 1, -1 do
        if not isChestValid(allChests[i]) or pickedChests[allChests[i]] then
            table.remove(allChests, i)
        end
    end
    for i = #unvisitedChests, 1, 1 do -- Iterate forwards to handle removal better
        if not isChestValid(unvisitedChests[i]) or pickedChests[unvisitedChests[i]] then
            table.remove(unvisitedChests, i)
        end
    end
end

local function getHighestChest()
    local highestChest = nil
    local highestY = -math.huge
    for _, chest in ipairs(unvisitedChests) do
        if chest.PrimaryPart and chest.PrimaryPart.Position.Y > highestY then
            highestY = chest.PrimaryPart.Position.Y
            highestChest = chest
        end
    end
    if highestChest then
        for i, c in ipairs(unvisitedChests) do
            if c == highestChest then
                table.remove(unvisitedChests, i)
                break
            end
        end
    end
    return highestChest
end

local function getNearbyPriorityChest()
    for _, model in ipairs(Workspace:GetDescendants()) do
        if model:IsA("Model") and ValidNearbyChestNames[model.Name] and not pickedChests[model] then
            assignPrimaryPartIfMissing(model)
            if model.PrimaryPart then
                local dist = (HumanoidRootPart.Position - model.PrimaryPart.Position).Magnitude
                if dist <= NEARBY_RADIUS and isChestValid(model) then
                    return model
                end
            end
        end
    end
    return nil
end

local function isChestPickedUp()
    if not currentChest or not currentChest.Parent then return true end
    for _, prompt in ipairs(currentChest:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            return false
        end
    end
    return true
end

local function markChestPicked(chest)
    if chest then
        pickedChests[chest] = true
    end
end

-- Function to press and release 'E'
local function pressE()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)  -- Press 'E'
    task.wait(0.05) -- Small delay to ensure the press is registered
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) -- Release 'E'
end

-- Forward declaration for teleportToNextChest
local teleportToNextChest

local function interactWithChest()
    if not enabled or not currentChest then return end
    task.spawn(function()
        -- Add a small initial delay after teleporting to allow the game to settle
        task.wait(0.2)

        local attempts = 0
        local maxAttempts = 10 -- Limit interaction attempts to prevent infinite loops

        while enabled and currentChest and not isChestPickedUp() and attempts < maxAttempts do
            print("[Collector] Attempting to interact with:", currentChest.Name, "(Attempt " .. (attempts + 1) .. ")")
            pressE()
            task.wait(0.5) -- Wait a bit before checking if it was picked up or trying again
            attempts += 1
        end

        if currentChest and isChestPickedUp() then
            print("[Collector] Successfully picked up:", currentChest.Name)
            markChestPicked(currentChest)
            -- Add a very small delay before moving to the next chest to prevent rapid-fire teleports
            task.wait(0.1)
            teleportToNextChest()
        else
            print("[Collector] Failed to pick up chest or it became invalid:", currentChest.Name)
            -- If it failed after max attempts, mark it as picked to move on
            markChestPicked(currentChest)
            teleportToNextChest()
        end
    end)
end

function teleportToNextChest()
    cleanChestLists()

    local priorityChest = getNearbyPriorityChest()
    if priorityChest then
        currentChest = priorityChest
        if HumanoidRootPart and currentChest.PrimaryPart then
            HumanoidRootPart.CFrame = currentChest.PrimaryPart.CFrame + Vector3.new(0, 5, 0)
            print("[Collector] Teleporting to nearby chest:", currentChest:GetFullName())
            interactWithChest()
        else
            -- If primary part is somehow missing, mark it picked and move on
            markChestPicked(currentChest)
            teleportToNextChest()
        end
        return
    end

    if #unvisitedChests == 0 then
        loadAllZone5Chests()
        refillChests()
        cleanChestLists()
        if #unvisitedChests == 0 then
            print("[Collector] No more Zone5 chests found.")
            currentChest = nil
            noChestsFound = true
            return
        else
            noChestsFound = false
        end
    end

    currentChest = getHighestChest()
    if currentChest and HumanoidRootPart and currentChest.PrimaryPart then
        HumanoidRootPart.CFrame = currentChest.PrimaryPart.CFrame + Vector3.new(0, 5, 0)
        print("[Collector] Teleporting to Zone5 chest:", currentChest:GetFullName())
        interactWithChest()
    else
        print("[Collector] Could not find a valid Zone5 chest to teleport to.")
        currentChest = nil
        noChestsFound = true -- Set this to true to trigger retry logic
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == TOGGLE_KEY then
        enabled = not enabled
        if enabled then
            pickedChests = {} -- Reset picked chests on enable
            loadAllZone5Chests()
            refillChests()
            noChestsFound = false
            print("[Collector] ENABLED")
            teleportToNextChest()
            timeSinceLastRefresh = 0
            timeSinceNoChestRetry = 0
        else
            print("[Collector] DISABLED")
            currentChest = nil -- Clear current chest when disabled
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.1)
        if enabled then
            timeSinceLastRefresh += 0.1
            if timeSinceLastRefresh >= CHEST_REFRESH_INTERVAL then
                timeSinceLastRefresh = 0
                print("[Collector] Refreshing chest list...")
                loadAllZone5Chests()
                refillChests()
                
                -- Only teleport if there's no current chest or it's been picked up/invalidated
                if not currentChest or not isChestValid(currentChest) or pickedChests[currentChest] then
                    teleportToNextChest()
                end
            end

            if noChestsFound then
                timeSinceNoChestRetry += 0.1
                if timeSinceNoChestRetry >= NO_CHEST_RETRY_INTERVAL then
                    timeSinceNoChestRetry = 0
                    print("[Collector] Retrying to find chests...")
                    loadAllZone5Chests()
                    refillChests()
                    noChestsFound = (#unvisitedChests == 0)
                    if not noChestsFound then
                        teleportToNextChest()
                    end
                end
            end
        end
    end
end)