local activeCrafting = {}

BccUtils.RPC:Register('bcc-crafting:AttemptCraft', function(params, cb, source)
    local item = params.item
    if not item then
        devPrint("[ERROR] Missing item data in crafting attempt.")
        return cb(false)
    end

    local Character = VORPcore.getUser(source).getUsedCharacter
    if not Character then
        devPrint("[ERROR] Failed to retrieve character data for source: " .. tostring(source))
        return cb(false)
    end
    local playerId = Character.charIdentifier
    local playerJob = Character.job

    local inputAmount = item.itemAmount or 1 -- Input amount from the player, default to 1 if not provided
    local itemConfigAmount = getConfigItemAmount(item.itemName) * inputAmount

    -- Check job requirements
    if item.requiredJobs and #item.requiredJobs > 0 then
        devPrint("Checking job requirements for: " .. item.itemLabel)
        local hasValidJob = false
        for _, allowedJob in pairs(item.requiredJobs) do
            devPrint("Allowed job: " .. allowedJob)

            if playerJob == allowedJob then
                hasValidJob = true
                devPrint("Player meets the job requirements for: " .. allowedJob)
                break
            end
        end

        if not hasValidJob then
            devPrint("Player does not meet the job requirements for: " .. item.itemLabel)
            VORPcore.NotifyObjective(source, _U('InvalidJobForCrafting') .. item.itemLabel, 4000)
            cb(false)
            return
        end
    else
        devPrint("No job requirements for: " .. item.itemLabel)
    end

    -- Check if player has required items
    local hasItems = true
    for _, reqItem in pairs(item.requiredItems) do
        devPrint(_U('CheckingRequiredItem') .. reqItem.itemName)
        local requiredItemCount = reqItem.itemCount
        local count = exports.vorp_inventory:getItemCount(source, nil, reqItem.itemName)
        devPrint(_U('PlayerHas') .. count .. _U('Of') .. reqItem.itemName .. _U('Requires') .. requiredItemCount .. ")")

        if count < requiredItemCount then
            hasItems = false
            devPrint(_U('MissingItem') .. reqItem.itemName)
            break
        end
    end

    if not hasItems then
        VORPcore.NotifyRightTip(source, _U('MissingMaterials') .. item.itemLabel .. ".", 4000)
        cb(false)
        return
    end

    -- Check player's crafting level
    GetPlayerCraftingData(playerId, function(xp, level)
        if level < item.requiredLevel then
            VORPcore.NotifyRightTip(source, _U('RequiredLevel') .. item.requiredLevel .. ".", 4000)
            cb(false)
            return
        end

        local totalDuration = item.duration * inputAmount
        local isWeapon = string.find(item.itemName, "^WEAPON_")
        if isWeapon then
            -- Retrieve the player's weapon inventory and limit the weapon count
            exports.vorp_inventory:getUserInventoryWeapons(source, function(weapons)
                local currentWeaponCount = #weapons
                local maxWeaponsAllowed = 5 -- Adjust this based on your server's maximum allowed weapon count
            end)
        else
            -- Regular item limit check for non-weapon items
            local itemDBData = exports.vorp_inventory:getItemDB(item.itemName)
            local itemLimit = itemDBData and itemDBData.limit
            devPrint("[DEBUG] Non-weapon item: " ..
                tostring(item.itemName) ..
                " - Item limit: " .. tostring(itemLimit) .. ", Requested amount: " .. tostring(itemConfigAmount))
            if itemLimit and itemConfigAmount > itemLimit then
                VORPcore.NotifyRightTip(source, _U('CannotCraftOverLimit') .. item.itemLabel, 4000)
                cb(false)
                return
            end
        end
        -- Remove required items from inventory
        for _, reqItem in pairs(item.requiredItems) do
            if reqItem.removeItem then
                local requiredItemCount = reqItem.itemCount * inputAmount
                devPrint("[DEBUG] Attempting to remove item: " ..
                tostring(reqItem.itemName) .. " | Required Count: " .. tostring(requiredItemCount))

                -- Attempt to remove the item
                local subItem = exports.vorp_inventory:subItem(source, reqItem.itemName, requiredItemCount,
                    reqItem.metadata or {})
                if not subItem then
                    devPrint("[ERROR] Failed to remove item: " ..
                    tostring(reqItem.itemName) .. " | Required: " .. tostring(requiredItemCount))
                    VORPcore.NotifyRightTip(source, _U('RemoveItemFailed', reqItem.itemLabel), 4000)
                    cb(false)
                    return
                else
                    devPrint("[DEBUG] Successfully removed item: " ..
                    tostring(reqItem.itemName) .. " | Amount Removed: " .. tostring(requiredItemCount))
                end
            else
                devPrint("[DEBUG] Item flagged as non-removable, processing durability for: " ..
                tostring(reqItem.itemName))

                -- Fetch the item
                local item = exports.vorp_inventory:getItem(source, reqItem.itemName)
                if not item then
                    devPrint("[ERROR] Item not found in inventory: " .. tostring(reqItem.itemName))
                    VORPcore.NotifyRightTip(source, "Item not found: " .. reqItem.itemLabel, 4000)
                    cb(false)
                    return
                end

                local maxDurability = 100
                local useDurability = 1

                -- Check if item metadata exists
                if not next(item.metadata) then
                    devPrint("[DEBUG] No durability metadata found for item: " ..
                    tostring(reqItem.itemName) .. ". Initializing durability.")

                    -- Initialize durability
                    local newData = {
                        description = "Durability " .. (maxDurability - useDurability) .. '%',
                        durability = maxDurability - useDurability,
                        id = item.id
                    }
                    exports.vorp_inventory:setItemMetadata(source, item.id, newData, 1)
                    devPrint("[DEBUG] Durability initialized for item: " ..
                    tostring(reqItem.itemName) .. " | New Durability: " .. tostring(maxDurability - useDurability))
                else
                    -- Handle durability reduction
                    local currentDurability = item.metadata.durability
                    devPrint("[DEBUG] Current durability for item: " ..
                    tostring(reqItem.itemName) .. " | Durability: " .. tostring(currentDurability))

                    if currentDurability <= useDurability then
                        -- Remove item if durability is depleted
                        exports.vorp_inventory:subItemID(source, item.id)
                        Core.NotifyRightTip(source, "Your crafting tool has broken", 4000)
                        devPrint("[DEBUG] Item broken and removed: " .. tostring(reqItem.itemName))
                    else
                        -- Update durability metadata
                        local newDurability = currentDurability - useDurability
                        local newData = {
                            description = "Durability " .. newDurability .. '%',
                            durability = newDurability,
                            id = item.id
                        }
                        exports.vorp_inventory:setItemMetadata(source, item.id, newData, 1)
                        devPrint("[DEBUG] Updated durability for item: " ..
                        tostring(reqItem.itemName) .. " | New Durability: " .. tostring(newDurability))
                    end
                end
            end
        end


        -- Prepare data for database insertion
        local craftingData = {
            ['charidentifier'] = playerId,
            ['itemName'] = item.itemName,
            ['itemLabel'] = item.itemLabel,
            ['itemAmount'] = itemConfigAmount, -- Use the calculated amount
            ['requiredItems'] = json.encode(item.requiredItems),
            ['status'] = 'in_progress',
            ['duration'] = totalDuration,
            ['rewardXP'] = item.rewardXP,
            ['timestamp'] = os.time()
        }

        -- Insert crafting attempt into database
        MySQL.insert(
            'INSERT INTO bcc_crafting_log (charidentifier, itemName, itemLabel, itemAmount, requiredItems, status, duration, rewardXP, timestamp) VALUES (@charidentifier, @itemName, @itemLabel, @itemAmount, @requiredItems, @status, @duration, @rewardXP, @timestamp)',
            craftingData, function(insertId)
                if insertId then
                    item.craftingId = insertId
                    activeCrafting[source] = {
                        item = item,
                        startTime = os.time(),
                        duration = totalDuration
                    }
                    BccUtils.RPC:Call("bcc-crafting:StartCrafting", { item = item }, nil, source)
                    Discord:sendMessage("Player ID: " ..
                        tostring(source) ..
                        " started crafting " ..
                        tostring(item.itemLabel) ..
                        ". Amount: " ..
                        tostring(itemConfigAmount) .. ". Total Duration: " .. tostring(totalDuration) .. "s")
                    cb(true)
                else
                    VORPcore.NotifyRightTip(source, _U('CraftingAttemptFailed'), 4000)
                    cb(false)
                end
            end)
    end)
end)

-- Server-side function to retrieve ongoing crafting items and remaining times
RegisterNetEvent('bcc-crafting:getOngoingCrafting')
AddEventHandler('bcc-crafting:getOngoingCrafting', function()
    local _source = source
    local Character = VORPcore.getUser(_source).getUsedCharacter
    local charIdentifier = Character.charIdentifier -- Unique character identifier
    MySQL.query("SELECT * FROM bcc_crafting_log WHERE charidentifier = @charidentifier AND status = 'in_progress'",
        { ['@charidentifier'] = charIdentifier }, function(result)
            local ongoingCraftingList = {}
            if result and #result > 0 then
                for _, craftingLog in ipairs(result) do
                    local startTime = craftingLog.timestamp
                    local currentTime = os.time()
                    local elapsedTime = currentTime - startTime
                    local remainingTime = craftingLog.duration - elapsedTime
                    if remainingTime <= 0 then
                        MySQL.update.await(
                            "UPDATE bcc_crafting_log SET status = 'completed', completed_at = NOW() WHERE id = @id",
                            { ['@id'] = craftingLog.id })
                        remainingTime = 0
                    end
                    table.insert(ongoingCraftingList, { craftingLog = craftingLog, remainingTime = remainingTime })
                end
            end
            TriggerClientEvent('bcc-crafting:sendOngoingCraftingList', _source, ongoingCraftingList)
        end)
end)

BccUtils.RPC:Register("bcc-crafting:GetCompletedCrafting", function(_, cb, source)
    -- Retrieve character information
    local Character = VORPcore.getUser(source).getUsedCharacter
    if not Character then
        devPrint("[ERROR] Failed to retrieve character for source: " .. tostring(source))
        cb(false)
        return
    end

    local charIdentifier = Character.charIdentifier

    -- Query the database for completed crafting items
    MySQL.query("SELECT * FROM bcc_crafting_log WHERE charidentifier = @charidentifier AND status = 'completed'",
        { ['@charidentifier'] = charIdentifier }, function(completedResult)
            if completedResult and #completedResult > 0 then
                devPrint("[DEBUG] Completed crafting data found for character: " .. tostring(charIdentifier))
                cb(completedResult)
            else
                devPrint("[DEBUG] No completed crafting data found for character: " .. tostring(charIdentifier))
                cb(false)
            end
        end
    )
end)

-- Register the callback for collecting crafted items
BccUtils.RPC:Register('bcc-crafting:collectCraftedItem', function(params, cb, source)
    if not params or not params.craftingLog then
        devPrint("[ERROR] Missing parameters or crafting log.")
        cb(false)
        return
    end

    local craftingLog = params.craftingLog
    -- Get Character Information
    local Character = VORPcore.getUser(source).getUsedCharacter
    local playerId = Character.charIdentifier
    local firstname = Character.firstname
    local lastname = Character.lastname

    -- Basic item details
    local itemName = craftingLog.itemName
    local itemLabel = craftingLog.itemLabel
    local rewardXP = craftingLog.rewardXP
    local amountToAdd = craftingLog.itemAmount

    -- Determine if the crafted item is a weapon
    local isWeapon = string.sub(itemName:lower(), 1, string.len("weapon_")) == "weapon_"
    devPrint("[DEBUG] Item name:" .. itemName .. " Is weapon:" .. tostring(isWeapon))

    if isWeapon then
        -- Retrieve the player's weapon inventory and limit the weapon count
        exports.vorp_inventory:getUserInventoryWeapons(source, function(weapons)
            local currentWeaponCount = #weapons

            if currentWeaponCount >= Config.maxWeaponsAllowed then
                VORPcore.NotifyRightTip(source, _U('CannotCarryMoreWeapons'), 4000)
                cb(false)
                return
            end

            -- Add weapon to inventory
            local weaponAdded = exports.vorp_inventory:createWeapon(source, itemName, {})
            if weaponAdded then
                MySQL.execute('DELETE FROM bcc_crafting_log WHERE id = @id', { ['@id'] = craftingLog.id })
                VORPcore.NotifyRightTip(source, _U('CollectedWeapon') .. itemLabel, 4000)

                -- Award XP for crafting a weapon
                local totalXP = rewardXP
                AddPlayerCraftingXP(playerId, totalXP, function(newLevel)
                    if newLevel then
                        TriggerClientEvent('bcc-crafting:levelUp', source, newLevel)
                    end
                end)

                -- Send a message to Discord
                local discordMessage = string.format(
                    "**Crafting Completion**\n\n" ..
                    "**Player:** %s %s (ID: %s)\n" ..
                    "**Crafted Weapon:** %s\n" ..
                    "**XP Gained:** %d XP\n" ..
                    "**Weapon Collected Successfully**",
                    firstname, lastname, playerId, itemLabel, totalXP
                )
                Discord:sendMessage(discordMessage)
                cb(true)
            else
                VORPcore.NotifyRightTip(source, _U('FailedToAddWeapon'), 4000)
                cb(false)
            end
        end)
        return
    else
        -- Handle regular items
        local itemData = exports.vorp_inventory:getItemDB(itemName)
        devPrint("[ERROR] Item name: " .. itemName)
        if not itemData then
            devPrint("[ERROR] Item data not found: " .. itemName)
            VORPcore.NotifyRightTip(source, "Item data not found for item: " .. itemLabel, 4000)
            cb(false)
            return
        end

        -- Calculate available space using the new function
        local availableSpace = getAvailableSpace(source, itemName)
        local addableAmount = math.min(amountToAdd, availableSpace)
        local remainingAmount = amountToAdd - addableAmount

        -- Check if the player can carry the full addableAmount
        local canCarry = exports.vorp_inventory:canCarryItem(source, itemName, addableAmount)
        if canCarry and addableAmount > 0 then
            -- Player can carry the full amount, proceed to add it
            local addItemResult = exports.vorp_inventory:addItem(source, itemName, addableAmount, {})
            if addItemResult then
                -- Update or delete crafting log based on remaining amount
                if remainingAmount > 0 then
                    MySQL.execute('UPDATE bcc_crafting_log SET itemAmount = @remainingAmount WHERE id = @id', {
                        ['@remainingAmount'] = remainingAmount,
                        ['@id'] = craftingLog.id
                    })
                    devPrint("[DEBUG] Updated crafting log with remaining amount: " .. remainingAmount)
                    VORPcore.NotifyRightTip(source, _U('CollectedPartially') .. addableAmount .. "x " .. itemLabel .. ".",
                        4000)
                else
                    MySQL.execute('DELETE FROM bcc_crafting_log WHERE id = @id', { ['@id'] = craftingLog.id })
                    devPrint("[DEBUG] Crafting log entry deleted for item: " .. itemName)
                    VORPcore.NotifyRightTip(source,
                        _U('CollectedCraftedItem') .. addableAmount .. "x " .. itemLabel .. ".", 4000)
                end

                -- Award XP for crafting items
                local totalXP = rewardXP * addableAmount
                AddPlayerCraftingXP(playerId, totalXP, function(newLevel)
                    if newLevel then
                        devPrint("[DEBUG] Player leveled up to: " .. newLevel)
                        TriggerClientEvent('bcc-crafting:levelUp', source, newLevel)
                    end
                end)

                -- Send a message to Discord
                local discordMessage = string.format(
                    "**Crafting Completion**\n\n" ..
                    "**Player:** %s %s (ID: %s)\n" ..
                    "**Crafted Item:** %s x%d\n" ..
                    "**XP Gained:** %d XP\n" ..
                    "**Item Collected Successfully**",
                    firstname, lastname, playerId, itemLabel, addableAmount, totalXP
                )
                Discord:sendMessage(discordMessage)
                cb(true)
            else
                devPrint("[ERROR] Failed to add crafted item to inventory: " .. itemName)
                VORPcore.NotifyRightTip(source, _U('FailedToAddItem'), 4000)
                cb(false)
            end
        else
            -- Player cannot carry the full amount, find a partial amount that fits
            local partialAmount = addableAmount
            local foundCarryableAmount = false

            -- Loop to decrease amount until we find one that can be carried
            while partialAmount > 0 and not foundCarryableAmount do
                local canCarryPartial = exports.vorp_inventory:canCarryItem(source, itemName, partialAmount)
                if canCarryPartial then
                    foundCarryableAmount = true
                else
                    partialAmount = partialAmount - 1
                end
            end

            if partialAmount > 0 then
                -- Proceed to add the partial amount
                local addItemResult = exports.vorp_inventory:addItem(source, itemName, partialAmount, {})
                if addItemResult then
                    -- Update crafting log with remaining amount if some items were left
                    local remainingAmount = amountToAdd - partialAmount
                    if remainingAmount > 0 then
                        MySQL.execute('UPDATE bcc_crafting_log SET itemAmount = @remainingAmount WHERE id = @id', {
                            ['@remainingAmount'] = remainingAmount,
                            ['@id'] = craftingLog.id
                        })
                        devPrint("[DEBUG] Updated crafting log with remaining amount: " .. remainingAmount)
                        VORPcore.NotifyRightTip(source,
                            _U('CollectedPartially') .. partialAmount .. "x " .. itemLabel .. ".", 4000)
                    else
                        MySQL.execute('DELETE FROM bcc_crafting_log WHERE id = @id', { ['@id'] = craftingLog.id })
                        devPrint("[DEBUG] Crafting log entry deleted for item: " .. itemName)
                        VORPcore.NotifyRightTip(source,
                            _U('CollectedCraftedItem') .. partialAmount .. "x " .. itemLabel .. ".", 4000)
                    end

                    -- Award XP for crafting items
                    local totalXP = rewardXP * partialAmount
                    AddPlayerCraftingXP(playerId, totalXP, function(newLevel)
                        if newLevel then
                            devPrint("[DEBUG] Player leveled up to: " .. newLevel)
                            TriggerClientEvent('bcc-crafting:levelUp', source, newLevel)
                        end
                    end)

                    -- Send a message to Discord
                    local discordMessage = string.format(
                        "**Crafting Completion**\n\n" ..
                        "**Player:** %s %s (ID: %s)\n" ..
                        "**Crafted Item:** %s x%d\n" ..
                        "**XP Gained:** %d XP\n" ..
                        "**Item Collected Successfully**",
                        firstname, lastname, playerId, itemLabel, partialAmount, totalXP
                    )
                    Discord:sendMessage(discordMessage)
                    cb(true)
                else
                    devPrint("[ERROR] Failed to add crafted item to inventory: " .. itemName)
                    VORPcore.NotifyRightTip(source, _U('FailedToAddItem'), 4000)
                    cb(false)
                end
            else
                -- No space available even for a partial amount
                VORPcore.NotifyRightTip(source, _U('NotEnoughSpace') .. amountToAdd .. "x " .. itemLabel .. ".", 4000)
                cb(false)
            end
        end
    end
end)

-- Function to get available space for an item in player's inventory
function getAvailableSpace(source, itemName)
    -- Fetch item data from the inventory database
    local itemData = exports.vorp_inventory:getItemDB(itemName)
    if not itemData then
        devPrint("[ERROR] Item data not found for item: " .. itemName)
        return 0 -- No space available if item data doesn't exist
    end

    -- Calculate available space based on item limit and current count
    local itemLimit = itemData.limit
    local currentCount = exports.vorp_inventory:getItemCount(source, nil, itemName)
    local spaceAvailable = math.max(itemLimit - currentCount, 0)

    return spaceAvailable
end

BccUtils.RPC:Register("bcc-crafting:GetCraftingData", function(params, cb, recSource)
    print("[DEBUG] Received RPC request for crafting data")
    local user = VORPcore.getUser(recSource)
    if not user then
        print("[DEBUG] No user found for source: " .. tostring(recSource))
        return cb(false)
    end

    local char = user.getUsedCharacter
    if not char then
        print("[DEBUG] No character data found for user.")
        return cb(false)
    end

    local playerId = char.charIdentifier
    print("[DEBUG] Character ID: " .. tostring(playerId))

    -- Query the database directly
    MySQL.query('SELECT currentXP, currentLevel FROM bcc_craft_progress WHERE charidentifier = @charidentifier', {
        ['@charidentifier'] = playerId
    }, function(result)
        if not result or #result == 0 then
            print("[DEBUG] No crafting data found. Initializing default data.")

            -- Insert default data if none exists
            MySQL.execute(
                'INSERT INTO bcc_craft_progress (charidentifier, currentXP, currentLevel) VALUES (@charidentifier, 0, 1)',
                { ['@charidentifier'] = playerId }
            )

            -- Default response for a new player
            local craftingData = {
                level = 1,
                xpToNextLevel = Config.LevelThresholds[1].xpPerLevel,
                categories = params.categories or {}
            }
            return cb(craftingData)
        end

        -- Extract current XP and level
        local currentXP = result[1].currentXP
        local level = result[1].currentLevel
        print("[DEBUG] Retrieved XP: " .. tostring(currentXP) .. ", Level: " .. tostring(level))

        -- Calculate XP required for the next level
        local xpForNextLevel = 0
        for _, threshold in ipairs(Config.LevelThresholds) do
            if level >= threshold.minLevel and level <= threshold.maxLevel then
                xpForNextLevel = threshold.xpPerLevel
                break
            end
        end

        if xpForNextLevel == 0 then
            print("[DEBUG] XP threshold not found for level: " .. tostring(level))
            return cb(false)
        end

        -- Calculate the remaining XP to the next level
        local xpToNextLevel = xpForNextLevel - (currentXP % xpForNextLevel)
        print("[DEBUG] XP to next level: " .. tostring(xpToNextLevel))

        -- Prepare the response
        local craftingData = {
            level = level,
            xpToNextLevel = math.max(0, xpToNextLevel), -- Ensure no negative values
            categories = params.categories or {}        -- Include any categories passed in params
        }

        -- Send the result back
        return cb(craftingData)
    end)
end)

function AddPlayerCraftingXP(playerId, amount, callback)
    devPrint("Adding XP for player:" .. playerId .. " Amount:" .. amount)

    GetPlayerCraftingData(playerId, function(xp, lastLevel)
        devPrint("Current XP: " .. xp .. " Last Level: " .. lastLevel)

        -- Calculate new level and remaining XP
        xp = xp + amount
        local newLevel, remainingXP = CalculateIncrementalLevel(xp, lastLevel)

        devPrint("New XP after addition: " .. xp)
        devPrint("Calculated New Level: " .. newLevel)
        devPrint("Remaining XP after leveling: " .. remainingXP)

        -- Update the database
        local param = {
            ['charidentifier'] = playerId,
            ['currentXP'] = remainingXP,
            ['currentLevel'] = newLevel,
            ['lastLevel'] = newLevel
        }

        MySQL.execute(
            'UPDATE bcc_craft_progress SET currentXP = @currentXP, currentLevel = @currentLevel, lastLevel = @lastLevel WHERE charidentifier = @charidentifier',
            param, function(rowsAffected)
                devPrint("Database Update Result: " .. json.encode(rowsAffected) .. " rows affected")
            end
        )

        -- Notify callback if level increased
        if newLevel > lastLevel then
            devPrint("Level increased! New Level: " .. newLevel)
            callback(newLevel)
        else
            devPrint("No level increase.")
            callback(nil)
        end
    end)
end

-- Function to get player crafting data (XP and level)
function GetPlayerCraftingData(playerId, callback)
    local param = { ['charidentifier'] = playerId }
    MySQL.query('SELECT currentXP, currentLevel FROM bcc_craft_progress WHERE charidentifier = @charidentifier', param,
        function(result)
            if #result > 0 then
                local xp = result[1].currentXP
                local level = result[1].currentLevel
                callback(xp, level)
            else
                MySQL.execute(
                    'INSERT INTO bcc_craft_progress (charidentifier, currentXP, currentLevel) VALUES (@charidentifier, 0, 1)',
                    param)
                callback(0, 1)
            end
        end)
end

-- Calculate the player's level and remaining XP based on dynamic LevelThresholds
function CalculateLevelFromXP(xp)
    local level = 1
    local remainingXP = xp

    for _, threshold in ipairs(Config.LevelThresholds) do
        local xpForRange = (threshold.maxLevel - threshold.minLevel + 1) * threshold.xpPerLevel

        if remainingXP >= xpForRange then
            -- Move to the next range
            remainingXP = remainingXP - xpForRange
            level = threshold.maxLevel + 1
        else
            -- Calculate level within the current range
            level = threshold.minLevel + math.floor(remainingXP / threshold.xpPerLevel)
            remainingXP = remainingXP % threshold.xpPerLevel -- Update remaining XP after level calculation
            break                                            -- Exit once level and remaining XP are determined for current threshold
        end
    end

    return level, remainingXP
end

function CalculateIncrementalLevel(xp, lastLevel)
    local level = lastLevel
    local remainingXP = xp

    for _, threshold in ipairs(Config.LevelThresholds) do
        if level >= threshold.minLevel and level <= threshold.maxLevel then
            -- Determine XP required for the current level
            local xpPerLevel = threshold.xpPerLevel

            while remainingXP >= xpPerLevel do
                -- Level up
                remainingXP = remainingXP - xpPerLevel
                level = level + 1

                -- Stop leveling if we reach the max level of the threshold
                if level > threshold.maxLevel then
                    break
                end
            end

            -- If XP is less than the XP per level, stop further checks
            if remainingXP < xpPerLevel then
                break
            end
        end
    end

    return level, remainingXP
end

for _, location in ipairs(CraftingLocations) do
    --devPrint("Registering craftbooks for location: " .. json.encode(location.coords))

    for _, category in ipairs(location.categories) do
        local craftBookItem = category.craftBookItem

        -- Check if the craftBookItem is valid
        if craftBookItem and craftBookItem ~= "" then
            exports.vorp_inventory:registerUsableItem(craftBookItem, function(data)
                local src = data.source -- The player's server ID
                exports.vorp_inventory:closeInventory(src)

                -- Use RPC to call the client to open the category menu
                BccUtils.RPC:Call("bcc-crafting:OpenCategoryMenu", { categoryName = category.name }, nil, src)
            end)
        else
            --devPrint("Skipping registration for empty craftBookItem in category: " .. category.name)
        end
    end
end

BccUtils.RPC:Register("bcc-crafting:getItemLimit", function(params, cb, source)
    local itemName = params.itemName
    devPrint("Received request to fetch item limit for item:", tostring(itemName or "No Item Name Provided"))

    -- Validate the itemName
    if not itemName or itemName == "" then
        devPrint("[ERROR] No itemName provided for getItemLimit RPC.")
        cb("N/A") -- Respond with "N/A" if itemName is invalid
        return
    end

    -- Fetch item data from vorp_inventory
    devPrint("[DEBUG] Fetching item limit from database for item:", itemName)
    local itemDBData = exports.vorp_inventory:getItemDB(itemName)

    -- Handle the response
    if itemDBData and itemDBData.limit then
        devPrint("[DEBUG] Item data found for:", itemName, "with limit:", tostring(itemDBData.limit))
        cb(itemDBData.limit) -- Send back the item limit
    else
        devPrint("[ERROR] No data found for item:", itemName)
        cb("N/A") -- Respond with "N/A" if no data is found
    end
end)

-- Function to update crafting status
function updateCraftingStatus(craftingId, status)
    local params = {
        ['id'] = craftingId,
        ['status'] = status,
        ['completed_at'] = status == 'completed' and os.date('%Y-%m-%d %H:%M:%S') or nil
    }

    MySQL.update.await('UPDATE bcc_crafting_log SET status = @status, completed_at = @completed_at WHERE id = @id',
        params)
end

-- Function to get itemAmount from CraftingLocations based on itemName
function getConfigItemAmount(itemName)
    for _, location in ipairs(CraftingLocations) do
        for _, category in ipairs(location.categories) do
            for _, item in ipairs(category.items) do
                if item.itemName == itemName then
                    return item.itemAmount
                end
            end
        end
    end
    devPrint("[ERROR] Item not found in CraftingLocations: " .. itemName)
    return nil -- Return nil if item is not found
end

--devPrint(_U('VersionCheck') .. GetCurrentResourceName())
BccUtils.Versioner.checkFile(GetCurrentResourceName(), 'https://github.com/BryceCanyonCounty/bcc-craft')
