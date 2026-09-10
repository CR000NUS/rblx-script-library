local LIBRARY_BUILD = "cronus-library-002"

-- Reload the library once when switching to this known-good build.
-- Subsequent executions reuse it, so library-level input connections do not stack.
if not getgenv().CronusLibrary or getgenv().CronusLibraryBuild ~= LIBRARY_BUILD then
    if getgenv().CronusWindowInstance then
        pcall(function()
            getgenv().CronusWindowInstance:Destroy()
        end)
    end

    getgenv().CronusWindow = nil
    getgenv().CronusWindowInstance = nil
    getgenv().CronusDebugConsole = nil
    getgenv().CronusLibrary = nil

    getgenv().CronusLibrary = loadstring(
        game:HttpGet("https://raw.githubusercontent.com/CR000NUS/rblx-script-library/refs/heads/main/library_v3", true)
    )()
    getgenv().CronusLibraryBuild = LIBRARY_BUILD
end

local library = getgenv().CronusLibrary
local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local LocalPlayer = PlayersService.LocalPlayer

local window
local WindowInstance
local GeneralTab
local PlayersTab
local DebugTab
local TerminateTab
local DebugConsole

-- Hook print only once. The hook always targets the newest console.
if not getgenv().CronusPrintHooked then
    getgenv().CronusPrintHooked = true

    local oldPrint = print
    print = function(...)
        oldPrint(...)

        local args = {...}
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(args[i])
        end

        local console = getgenv().CronusDebugConsole
        if console then
            console:Log(table.concat(parts, " "))
        end
    end
end

local function disconnectGlobal(name)
    local conn = getgenv()[name]
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
        getgenv()[name] = nil
    end
end

local function CleanupOldMenu()
    -- Disconnect connections created by the main script.
    disconnectGlobal("CronusCharacterAddedConn")
    disconnectGlobal("CronusPlayerAddedConn")
    disconnectGlobal("CronusPlayerRemovingConn")
    disconnectGlobal("CronusNoclipConn")
    disconnectGlobal("CronusFlyConn")
    disconnectGlobal("CronusDebugHistoryConn")

    -- Remove any fly force left behind by the previous run.
    local oldVelocity = getgenv().CronusFlyBodyVelocity
    if oldVelocity then
        pcall(function()
            oldVelocity:Destroy()
        end)
        getgenv().CronusFlyBodyVelocity = nil
    end

    getgenv().CronusDebugConsole = nil

    -- Destroy only the old window. Keep the already-loaded library itself.
    -- This avoids stacking whole library-level input connections on every reload.
    local oldWindow = getgenv().CronusWindowInstance
    if oldWindow then
        pcall(function()
            oldWindow:Destroy()
        end)
    end

    getgenv().CronusWindow = nil
    getgenv().CronusWindowInstance = nil

    getgenv().CronusDebugHistoryConn = UIS.InputBegan:Connect(function(input, gameProcessed)
        if not commandBox:IsFocused() then
            return
        end

        if input.KeyCode == Enum.KeyCode.Up then
            if #commandHistory == 0 then
                return
            end

            historyIndex = math.max(1, historyIndex - 1)
            commandBox.Text = commandHistory[historyIndex]
            commandBox.CursorPosition = #commandBox.Text + 1

        elseif input.KeyCode == Enum.KeyCode.Down then
            if #commandHistory == 0 then
                return
            end

            historyIndex = math.min(#commandHistory + 1, historyIndex + 1)

            if historyIndex > #commandHistory then
                commandBox.Text = ""
                commandBox.CursorPosition = 1
            else
                commandBox.Text = commandHistory[historyIndex]
                commandBox.CursorPosition = #commandBox.Text + 1
            end
        end
    end)
end

local function CreateDebugTab()
    DebugConsole = DebugTab:AddConsole({
        y = 300,
        source = "Logs",
        readonly = true,
        full = false,
    })

    getgenv().CronusDebugConsole = DebugConsole

    local Cronus = {
        plr = LocalPlayer,
        Players = PlayersService,
        UIS = UIS,
        RunService = RunService,
        library = library,
        window = window,
    }

    local Help = {
        title = "Cronus' Debug Console Help",

        lines = {
            "This is a so debug console...",
            "",
            "It means that you can check game objects and variables while being in the game. You basically control everything with the command:",
            "",
            "print(...)",
            "",
            "With this you can display (or 'print out') anything you want. Be careful since you can also break things with this",
            "",
            "Imagine it like a folder structure. Start of by typing print(Cronus) From there you can go deeper into the folder print(Cronus.plr) From there you can go deeper again and so on and so on...",
            "",
        }
    }

    local DebugEnv = setmetatable({
        Cronus = Cronus,
        help = Help,
    }, {
        __index = getgenv()
    })

    -- Make print() from debug commands write directly to the debug console
    DebugEnv.print = function(...)
        local args = {...}

        local function isExpandable(value)
            return typeof(value) == "Instance"
                or typeof(value) == "table"
        end

        local function logValue(value)
            if value == Help then
                DebugConsole:Log(Help.title)
                DebugConsole:Log("")

                for _, line in ipairs(Help.lines) do
                    DebugConsole:Log(line)
                end

                return
            end
            
            -- Roblox Instance
            if typeof(value) == "Instance" then
                DebugConsole:Log(
                    tostring(value:GetFullName())
                    .. " [" .. value.ClassName .. "]"
                )

                -- If the runtime supports property enumeration, show properties
                if typeof(getproperties) == "function" then
                    local success, properties = pcall(getproperties, value)

                    if success and properties then
                        local names = {}

                        for propertyName in pairs(properties) do
                            table.insert(names, tostring(propertyName))
                        end

                        table.sort(names)

                        for _, propertyName in ipairs(names) do
                            local successValue, propertyValue = pcall(function()
                                return value[propertyName]
                            end)

                            if successValue then
                                if isExpandable(propertyValue) then
                                    -- Object/table: can be explored further
                                    DebugConsole:Log(
                                        "  ." .. propertyName
                                    )
                                else
                                    -- Simple value
                                    DebugConsole:Log(
                                        "  ." .. propertyName
                                        .. " = "
                                        .. tostring(propertyValue)
                                    )
                                end
                            else
                                DebugConsole:Log(
                                    "  ." .. propertyName
                                )
                            end
                        end
                    end
                else
                    -- Standard Roblox/Luau cannot enumerate every Instance property.
                    -- Show children as a useful fallback.
                    local children = value:GetChildren()

                    if #children > 0 then
                        DebugConsole:Log("  Children:")

                        for _, child in ipairs(children) do
                            DebugConsole:Log(
                                "    ." .. child.Name
                                .. " [" .. child.ClassName .. "]"
                            )
                        end
                    end

                    DebugConsole:Log(
                        "  [Property enumeration unavailable in this runtime]"
                    )
                end

                -- Also show actual child Instances
                local children = value:GetChildren()

                if #children > 0 then
                    DebugConsole:Log("  Children:")

                    table.sort(children, function(a, b)
                        return a.Name:lower() < b.Name:lower()
                    end)

                    for _, child in ipairs(children) do
                        DebugConsole:Log(
                            "    ." .. child.Name
                            .. " [" .. child.ClassName .. "]"
                        )
                    end
                end

                return
            end

            -- Lua table
            if typeof(value) == "table" then
                DebugConsole:Log("{")

                for key, tableValue in pairs(value) do
                    if isExpandable(tableValue) then
                        DebugConsole:Log(
                            "  ." .. tostring(key)
                        )
                    else
                        DebugConsole:Log(
                            "  ." .. tostring(key)
                            .. " = "
                            .. tostring(tableValue)
                        )
                    end
                end

                DebugConsole:Log("}")
                return
            end

            -- Normal values
            DebugConsole:Log(tostring(value))
        end

        for i = 1, select("#", ...) do
            logValue(args[i])
        end
    end

    -- Optional: make warn() work there too
    DebugEnv.warn = function(...)
        local args = {...}
        local parts = {}

        for i = 1, select("#", ...) do
            parts[i] = tostring(args[i])
        end

        DebugConsole:Log("[WARN] " .. table.concat(parts, " "))
    end

    local commandHistory = {}
    local historyIndex = 1

    local commandBox = DebugTab:AddTextBox("Enter Lua command...", function(command)
        if not command or command == "" then
            return
        end

        if commandHistory[#commandHistory] ~= command then
            table.insert(commandHistory, command)

            if #commandHistory > 100 then
                table.remove(commandHistory, 1)
            end
        end

        historyIndex = #commandHistory + 1

        DebugConsole:Log("> " .. command)

        local func, compileError = loadstring(command)

        if not func then
            DebugConsole:Log("[ERROR] " .. tostring(compileError))
            return
        end

        setfenv(func, DebugEnv)

        local results = table.pack(pcall(func))

        if not results[1] then
            DebugConsole:Log("[ERROR] " .. tostring(results[2]))
            return
        end

        if results.n > 1 then
            local output = {}

            for i = 2, results.n do
                output[#output + 1] = tostring(results[i])
            end

            DebugConsole:Log("=> " .. table.concat(output, ", "))
        end
    end, {
        clear = true
    })

    local historyConnection

    historyConnection = UIS.InputBegan:Connect(function(input, gameProcessed)
        if not commandBox:IsFocused() then
            return
        end

        if input.KeyCode == Enum.KeyCode.Up then
            if #commandHistory == 0 then
                return
            end

            historyIndex = math.max(1, historyIndex - 1)

            commandBox.Text = commandHistory[historyIndex]
            commandBox.CursorPosition = #commandBox.Text + 1

        elseif input.KeyCode == Enum.KeyCode.Down then
            if #commandHistory == 0 then
                return
            end

            historyIndex = math.min(#commandHistory + 1, historyIndex + 1)

            if historyIndex > #commandHistory then
                commandBox.Text = ""
                commandBox.CursorPosition = 1
            else
                commandBox.Text = commandHistory[historyIndex]
                commandBox.CursorPosition = #commandBox.Text + 1
            end
        end
    end)
end

local function CreatePlayersTab()
    local playerFolders = {}

    local function addPlayerEntry(plr)
        local folder_data, folderFrame = PlayersTab:AddFolder(plr.Name)

        folder_data:AddButton("Teleporttttt To", function()
            local targetCharacter = plr.Character
            local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")

            local myCharacter = LocalPlayer.Character
            local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")

            if targetRoot and myRoot then
                myRoot.CFrame = targetRoot.CFrame
            else
                warn("Could not teleport to " .. plr.Name .. " - character not ready")
            end
        end)

        folder_data:AddButton("xxx", function()
            print(plr.Name .. " -> xxx clicked")
        end)

        folder_data:AddButton("yyy", function()
            print(plr.Name .. " -> yyy clicked")
        end)

        folder_data:AddButton("zzz", function()
            print(plr.Name .. " -> zzz clicked")
        end)

        playerFolders[plr] = folderFrame
    end

    local function removePlayerEntry(plr)
        local folderFrame = playerFolders[plr]
        if folderFrame then
            folderFrame:Destroy()
            playerFolders[plr] = nil
        end
    end

    for _, plr in ipairs(PlayersService:GetPlayers()) do
        addPlayerEntry(plr)
    end

    getgenv().CronusPlayerAddedConn = PlayersService.PlayerAdded:Connect(addPlayerEntry)
    getgenv().CronusPlayerRemovingConn = PlayersService.PlayerRemoving:Connect(removePlayerEntry)
end

local function CreateGeneralTab()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid")

    getgenv().CronusCharacterAddedConn = LocalPlayer.CharacterAdded:Connect(function(newChar)
        character = newChar
        humanoid = newChar:WaitForChild("Humanoid")
    end)

    GeneralTab:AddSlider("WalkSpeed", function(value)
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = value
        end
    end, { min = 10, max = 200 })

    GeneralTab:AddSlider("JumpPower", function(value)
        if humanoid and humanoid.Parent then
            humanoid.JumpPower = value
        end
    end, { min = 10, max = 300 })

    do
        local noclipEnabled = false

        getgenv().CronusNoclipConn = RunService.Stepped:Connect(function()
            if noclipEnabled and character and character.Parent then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)

        GeneralTab:AddSwitch("Noclip", function(toggled)
            noclipEnabled = toggled

            if not toggled and character and character.Parent then
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        part.CanCollide = true
                    end
                end
            end
        end)
    end

    do
        local flyEnabled = false
        local flySpeed = 50
        local bodyVelocity

        local function destroyBodyVelocity()
            if bodyVelocity then
                bodyVelocity:Destroy()
                bodyVelocity = nil
            end
            getgenv().CronusFlyBodyVelocity = nil
        end

        local function getMoveVector()
            local camera = workspace.CurrentCamera
            if not camera then
                return Vector3.new()
            end

            local moveVector = Vector3.new()

            if UIS:IsKeyDown(Enum.KeyCode.W) then moveVector += camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then moveVector -= camera.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then moveVector -= camera.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then moveVector += camera.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then moveVector += Vector3.new(0, 1, 0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector -= Vector3.new(0, 1, 0) end

            if moveVector.Magnitude > 0 then
                moveVector = moveVector.Unit
            end

            return moveVector
        end

        getgenv().CronusFlyConn = RunService.Heartbeat:Connect(function()
            if not flyEnabled or not character or not character.Parent then
                return
            end

            local hrp = character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end

            if not bodyVelocity or bodyVelocity.Parent ~= hrp then
                destroyBodyVelocity()

                bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bodyVelocity.Parent = hrp
                getgenv().CronusFlyBodyVelocity = bodyVelocity
            end

            bodyVelocity.Velocity = getMoveVector() * flySpeed
        end)

        GeneralTab:AddSwitch("Fly", function(toggled)
            flyEnabled = toggled
            if not toggled then
                destroyBodyVelocity()
            end
        end)

        GeneralTab:AddSlider("Fly Speed", function(value)
            flySpeed = value
        end, { min = 10, max = 200 })
    end

    -- Avatar Height Scale
    local defaultHeightScale

    local function getHeightScale()
        if not humanoid then
            return nil
        end

        humanoid.AutomaticScalingEnabled = true

        local heightScale = humanoid:FindFirstChild("BodyHeightScale")

        if heightScale and heightScale:IsA("NumberValue") then
            return heightScale
        end

        return nil
    end

    local heightScale = getHeightScale()

    if heightScale then
        defaultHeightScale = heightScale.Value

        GeneralTab:AddSlider("Avatar Height", function(value)
            local currentHeightScale = getHeightScale()

            if currentHeightScale then
                currentHeightScale.Value = value / 100

                print(
                    "Avatar height set to "
                    .. tostring(currentHeightScale.Value)
                )
            end
        end, {
            min = 50,
            max = 200
        })

        GeneralTab:AddButton("Reset Avatar Height", function()
            local currentHeightScale = getHeightScale()

            if currentHeightScale and defaultHeightScale then
                currentHeightScale.Value = defaultHeightScale

                print(
                    "Avatar height reset to "
                    .. tostring(defaultHeightScale)
                )
            end
        end)
    else
        GeneralTab:AddLabel("Avatar scaling unavailable")
    end

end

local function CreateMenuTabs()
    GeneralTab = window:AddTab("General")
    PlayersTab = window:AddTab("Players")
    DebugTab = window:AddTab("Debug")
    TerminateTab = window:AddTab("Terminate")

    -- Build Debug first so any later print/warn output has somewhere to go.
    CreateDebugTab()
    CreateGeneralTab()
    CreatePlayersTab()

    -- Leave General selected by default.
    GeneralTab:Show()
end

local function CreateMenu()
    CleanupOldMenu()

    window, WindowInstance = library:AddWindow("Cronus' - Universal - Menu", {
        main_color = Color3.fromRGB(0, 0, 0),
        min_size = Vector2.new(500, 400),
        can_resize = true,
    })

    getgenv().CronusWindow = window
    getgenv().CronusWindowInstance = WindowInstance

    CreateMenuTabs()
end

CreateMenu()