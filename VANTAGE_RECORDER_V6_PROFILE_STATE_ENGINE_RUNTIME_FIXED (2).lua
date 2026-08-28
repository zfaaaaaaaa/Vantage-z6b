-- ============================================

-- RECORDER + SAVE + LOAD (تخزين دائم)

-- ============================================

local Players = game:GetService("Players")

local RunService = game:GetService("RunService")

local UserInputService = game:GetService("UserInputService")

local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

-- ============================================

-- CONFIG

-- ============================================

local MenuOpen = true

local SAVE_FOLDER = "Recordings/"
local LOCATION_FOLDER = "VantageLocations/"
local LOCATION_FILE = LOCATION_FOLDER .. "locations.json"
local DEFAULT_WALK_SPEED = 16
local PROFILE_FOLDER = "VantageProfiles/"
local PROFILE_FILE = PROFILE_FOLDER .. "profiles.json"
local ACTIVE_PROFILE_FILE = PROFILE_FOLDER .. "active_profile.json"

-- ============================================

-- CREATE FOLDER

-- ============================================

pcall(function()

    makefolder(SAVE_FOLDER)

end)

pcall(function()
    if isfolder then
        if not isfolder(LOCATION_FOLDER) then
            makefolder(LOCATION_FOLDER)
        end
    else
        makefolder(LOCATION_FOLDER)
    end
end)

pcall(function()
    if isfolder then
        if not isfolder(PROFILE_FOLDER) then
            makefolder(PROFILE_FOLDER)
        end
    else
        makefolder(PROFILE_FOLDER)
    end
end)


-- ============================================

-- VARIABLES

-- ============================================

local recording = false

local playing = false

local loopPlaying = false

local recordedData = {}

local startPosition = nil

local recordingsList = {}

local currentLoopName = ""

local lastPos = nil

local lastTime = nil
local spectatingPlayer = nil
local spectateConnection = nil
local espEnabled = false
local espObjects = {}
local espUpdateConnection = nil
local espCharacterConnections = {}
local espDeathConnections = {}
local espRemovingConnections = {}
local espHealthConnections = {}
local espAncestryConnections = {}
local espReconcileElapsed = 0
local ESP_RECONCILE_INTERVAL = 0.20
local espColor = Color3.fromRGB(90, 185, 255)
local espColorPromptOpen = false

-- BOT/NPC ESP state intentionally stored in one global table.
-- This avoids adding top-level locals to this already-large Luau chunk.
VantageBotRadar = VantageBotRadar or {
    Objects = {},
    Elapsed = 0,
}


local savedLocations = {}
local loopTeleporting = false
local currentLoopLocation = nil
local walkSpeedValue = DEFAULT_WALK_SPEED
local antiFallEnabled = false
local autoReturnEnabled = false
local antiFallConnection = nil
local lastSafeLocationName = nil
local locationNamePromptOpen = false
local pendingSavedCFrame = nil
local savedProfiles = {}
local activeProfileName = nil
local hudConnection = nil
local hudElapsed = 0
local hudFrames = 0
local currentFPS = 0
local currentPing = "—"
local playerSearchQuery = ""
local VantageProfileBridge = {}


-- ============================================
-- LOCATIONS / MOVEMENT / FLY
-- ============================================

local function GetRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function SanitizeLocationName(name)
    name = tostring(name or "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub("[\\/:*?\"<>|]", "_")
    if name == "" then return nil end
    return name:sub(1, 40)
end

local function CFrameToData(cf)
    local x, y, z,
        r00, r01, r02,
        r10, r11, r12,
        r20, r21, r22 = cf:GetComponents()

    return {
        X = x, Y = y, Z = z,
        R00 = r00, R01 = r01, R02 = r02,
        R10 = r10, R11 = r11, R12 = r12,
        R20 = r20, R21 = r21, R22 = r22,
        Date = os.date("%Y-%m-%d %H:%M:%S")
    }
end

local function DataToCFrame(data)
    if type(data) ~= "table" then return nil end

    local x = tonumber(data.X or data.x)
    local y = tonumber(data.Y or data.y)
    local z = tonumber(data.Z or data.z)
    if not (x and y and z) then return nil end

    local r00, r01, r02 = tonumber(data.R00), tonumber(data.R01), tonumber(data.R02)
    local r10, r11, r12 = tonumber(data.R10), tonumber(data.R11), tonumber(data.R12)
    local r20, r21, r22 = tonumber(data.R20), tonumber(data.R21), tonumber(data.R22)

    if r00 and r01 and r02 and r10 and r11 and r12 and r20 and r21 and r22 then
        return CFrame.new(
            x, y, z,
            r00, r01, r02,
            r10, r11, r12,
            r20, r21, r22
        )
    end

    return CFrame.new(x, y, z)
end

local function SaveLocationsFile()
    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode(savedLocations)
    end)

    if not okEncode or not encoded then
        warn("VANTAGE: Could not encode locations.")
        return false
    end

    local okWrite, err = pcall(function()
        if isfolder and not isfolder(LOCATION_FOLDER) then
            makefolder(LOCATION_FOLDER)
        end
        writefile(LOCATION_FILE, encoded)
    end)

    if not okWrite then
        warn("VANTAGE: Could not save locations file: " .. tostring(err))
        return false
    end

    return true
end

local function LoadLocationsFile()
    savedLocations = {}

    local okRead, raw = pcall(function()
        if isfile and not isfile(LOCATION_FILE) then
            return nil
        end
        return readfile(LOCATION_FILE)
    end)

    if not okRead or not raw or raw == "" then
        return
    end

    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if okDecode and type(decoded) == "table" then
        savedLocations = decoded
    else
        warn("VANTAGE: Saved locations file is invalid.")
    end
end

local function SaveCurrentLocation(name, exactCFrame)
    name = SanitizeLocationName(name)
    if not name then
        warn("VANTAGE: Invalid location name.")
        return false
    end

    local cf = exactCFrame
    if not cf then
        local root = GetRoot()
        if not root then
            warn("VANTAGE: HumanoidRootPart not found.")
            return false
        end
        cf = root.CFrame
    end

    savedLocations[name] = CFrameToData(cf)

    if not SaveLocationsFile() then
        savedLocations[name] = nil
        return false
    end

    lastSafeLocationName = name
    print("VANTAGE: Location saved -> " .. name)
    return true
end

local function TeleportToLocation(name)
    local data = savedLocations[name]
    local root = GetRoot()

    if not data or not root then
        return false
    end

    local cf = DataToCFrame(data)
    if not cf then
        return false
    end

    root.CFrame = cf
    lastSafeLocationName = name
    return true
end

local function StopLoopTeleport()
    loopTeleporting = false
    currentLoopLocation = nil
end

local function StartLoopTeleport(name)
    if not savedLocations[name] then return end

    if loopTeleporting and currentLoopLocation == name then
        StopLoopTeleport()
        return
    end

    loopTeleporting = true
    currentLoopLocation = name

    task.spawn(function()
        while loopTeleporting and currentLoopLocation == name do
            TeleportToLocation(name)
            task.wait(0.25)
        end
    end)
end

local function DeleteLocation(name)
    if not savedLocations[name] then return end

    savedLocations[name] = nil

    if currentLoopLocation == name then
        StopLoopTeleport()
    end

    if lastSafeLocationName == name then
        lastSafeLocationName = nil
    end

    SaveLocationsFile()
end

local function ApplyWalkSpeed()
    local humanoid = GetHumanoid()
    if humanoid then
        humanoid.WalkSpeed = walkSpeedValue
    end
end

local function SetWalkSpeed(value)
    walkSpeedValue = math.clamp(tonumber(value) or DEFAULT_WALK_SPEED, 8, 100)
    ApplyWalkSpeed()
end

local function StopAntiFall()
    if antiFallConnection then
        antiFallConnection:Disconnect()
        antiFallConnection = nil
    end
end

local function StartAntiFall()
    StopAntiFall()

    local elapsed = 0
    antiFallConnection = RunService.Heartbeat:Connect(function(dt)
        if not antiFallEnabled then
            StopAntiFall()
            return
        end

        elapsed += dt
        if elapsed < 0.20 then
            return
        end
        elapsed = 0

        if lastSafeLocationName then
            local root = GetRoot()
            if root and root.Position.Y < -25 then
                TeleportToLocation(lastSafeLocationName)
            end
        end
    end)
end

-- FLY
local flying = false
local flySpeed = 55
local flyVelocity = nil
local flyGyro = nil
local flyConnection = nil

local function StopFly()
    flying = false

    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end

    if flyVelocity then
        flyVelocity:Destroy()
        flyVelocity = nil
    end

    if flyGyro then
        flyGyro:Destroy()
        flyGyro = nil
    end

    local humanoid = GetHumanoid()
    if humanoid then
        humanoid.AutoRotate = true
    end
end

local function StartFly()
    if flying then
        StopFly()
        return
    end

    local root = GetRoot()
    local humanoid = GetHumanoid()
    if not root or not humanoid then
        warn("VANTAGE: Fly could not start.")
        return
    end

    flying = true
    humanoid.AutoRotate = false

    flyVelocity = Instance.new("BodyVelocity")
    flyVelocity.Name = "VantageFlyVelocity"
    flyVelocity.MaxForce = Vector3.new(250000, 250000, 250000)
    flyVelocity.P = 15000
    flyVelocity.Velocity = Vector3.zero
    flyVelocity.Parent = root

    flyGyro = Instance.new("BodyGyro")
    flyGyro.Name = "VantageFlyGyro"
    flyGyro.MaxTorque = Vector3.new(250000, 250000, 250000)
    flyGyro.P = 12000
    flyGyro.CFrame = root.CFrame
    flyGyro.Parent = root

    flyConnection = RunService.RenderStepped:Connect(function()
        if not flying then return end

        local currentRoot = GetRoot()
        local camera = workspace.CurrentCamera

        if not currentRoot or not camera or not flyVelocity or not flyGyro then
            StopFly()
            return
        end

        local direction = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direction += camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direction -= camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direction -= camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direction += camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            direction += Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            direction -= Vector3.new(0, 1, 0)
        end

        if direction.Magnitude > 0 then
            direction = direction.Unit
        end

        flyVelocity.Velocity = direction * flySpeed
        flyGyro.CFrame = CFrame.lookAt(
            currentRoot.Position,
            currentRoot.Position + camera.CFrame.LookVector
        )
    end)
end


-- ============================================
-- PROFILES
-- ============================================

local function SaveProfilesFile()
    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode(savedProfiles)
    end)
    if not okEncode or not encoded then return false end

    local okWrite = pcall(function()
        if isfolder and not isfolder(PROFILE_FOLDER) then
            makefolder(PROFILE_FOLDER)
        end
        writefile(PROFILE_FILE, encoded)
    end)

    return okWrite
end

local function LoadProfilesFile()
    savedProfiles = {}

    local okRead, raw = pcall(function()
        if isfile and not isfile(PROFILE_FILE) then
            return nil
        end
        return readfile(PROFILE_FILE)
    end)

    if not okRead or not raw or raw == "" then return end

    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if okDecode and type(decoded) == "table" then
        savedProfiles = decoded
    end
end


local function SaveActiveProfileName(name)
    local okEncode, encoded = pcall(function()
        return HttpService:JSONEncode({ Name = name or "" })
    end)
    if not okEncode or not encoded then return false end

    return pcall(function()
        writefile(ACTIVE_PROFILE_FILE, encoded)
    end)
end

local function LoadActiveProfileName()
    local okRead, raw = pcall(function()
        if isfile and not isfile(ACTIVE_PROFILE_FILE) then return nil end
        return readfile(ACTIVE_PROFILE_FILE)
    end)
    if not okRead or not raw or raw == "" then return nil end

    local okDecode, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if okDecode and type(decoded) == "table" and type(decoded.Name) == "string" and decoded.Name ~= "" then
        return decoded.Name
    end

    return nil
end

local function SanitizeProfileName(name)
    name = tostring(name or "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    name = name:gsub("[\\/:*?\"<>|]", "_")
    if name == "" then return nil end
    return name:sub(1, 32)
end

local function CaptureCurrentProfile()
    local profile = {
        -- Movement
        WalkSpeed = walkSpeedValue,
        FlySpeed = flySpeed,
        Flying = flying == true,
        AntiFall = antiFallEnabled == true,
        AutoReturn = autoReturnEnabled == true,

        -- ESP / Radar
        ESPEnabled = espEnabled == true,
        ESPColor = {
            R = math.floor(espColor.R * 255 + 0.5),
            G = math.floor(espColor.G * 255 + 0.5),
            B = math.floor(espColor.B * 255 + 0.5),
        },

        -- Useful UI state
        PlayerSearchQuery = playerSearchQuery or "",
    }

    -- AIM lives in the isolated addon; read its exact live state.
    if VantageProfileBridge.GetAimState then
        local okAim, aimState = pcall(VantageProfileBridge.GetAimState)
        if okAim and type(aimState) == "table" then
            profile.AimEnabled = aimState.Enabled == true
            profile.AimFOVRadius = tonumber(aimState.FOV) or 150
            profile.AimSmoothness = tonumber(aimState.Smoothness) or 1
            profile.AimTargetPart = aimState.TargetPart or "Head"
        end
    end

    return profile
end

local function SaveProfile(name)
    name = SanitizeProfileName(name)
    if not name then return false end

    savedProfiles[name] = CaptureCurrentProfile()
    if SaveProfilesFile() then
        activeProfileName = name
        SaveActiveProfileName(name)
        return true
    end

    savedProfiles[name] = nil
    return false
end

local ApplyProfile

local function DeleteProfile(name)
    if not savedProfiles[name] then return false end
    savedProfiles[name] = nil
    if activeProfileName == name then
        activeProfileName = nil
        SaveActiveProfileName(nil)
    end
    return SaveProfilesFile()
end

-- ============================================

-- SAVE TO FILE

-- ============================================

local function SaveRecordingToFile(name, data)

    local fileName = SAVE_FOLDER .. name .. ".json"

    local json = HttpService:JSONEncode(data)

    local success = pcall(function()

        writefile(fileName, json)

    end)

    return success

end

-- ============================================

-- LOAD FROM FILE

-- ============================================

local function LoadRecordingFromFile(name)

    local fileName = SAVE_FOLDER .. name .. ".json"

    local success, data = pcall(function()

        return readfile(fileName)

    end)

    if not success or not data then

        return nil

    end

    local decoded = HttpService:JSONDecode(data)

    return decoded

end

-- ============================================

-- LOAD ALL RECORDINGS

-- ============================================

local function LoadAllRecordings()

    recordingsList = {}

    local success, files = pcall(function()

        return listfiles(SAVE_FOLDER)

    end)

    if not success or not files then

        print("No saved recordings found.")

        return

    end

    local loadedCounter = 0
    for _, file in pairs(files) do
        loadedCounter += 1
        if loadedCounter % 25 == 0 then
            task.wait()
        end

        local name = file:match("([^/]+)%.json$")

        if name then

            local data = LoadRecordingFromFile(name)

            if data then

                recordingsList[name] = data

            end

        end

    end

    print("✅ تم تحميل " .. #recordingsList .. " ريكورد")

end

-- ============================================

-- DELETE FROM FILE

-- ============================================

local function DeleteRecordingFile(name)

    local fileName = SAVE_FOLDER .. name .. ".json"

    local success = pcall(function()

        delfile(fileName)

    end)

    return success

end

-- ============================================

-- RECORDING FUNCTIONS

-- ============================================

local function StartRecording()

    local char = LocalPlayer.Character

    if not char then 

        print("ERROR: Character not found!")

        return 

    end

    local root = char:FindFirstChild("HumanoidRootPart")

    if not root then 

        print("ERROR: HumanoidRootPart not found!")

        return 

    end

    startPosition = root.Position

    recordedData = {}

    lastPos = nil

    lastTime = nil

    recording = true

    print("Recording started.")

    RecordBtn.Text = "● RECORDING..."

    RecordBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 30)

    RecordBtn.BorderColor3 = Color3.fromRGB(80, 255, 80)

end

local function StopRecording()

    recording = false

    if #recordedData == 0 then

        print("ERROR: No movement was recorded.")

        RecordBtn.Text = "● START RECORDING"

        RecordBtn.BackgroundColor3 = Color3.fromRGB(7, 14, 25)

        RecordBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

        return

    end

    local name = "ريكورد_" .. os.time()

    local data = {

        Name = name,

        StartPosition = {

            X = startPosition.X,

            Y = startPosition.Y,

            Z = startPosition.Z

        },

        Movements = recordedData,

        Date = os.date("%Y-%m-%d %H:%M:%S"),

        Count = #recordedData

    }

    -- Save to file

    local saved = SaveRecordingToFile(name, data)

    if saved then

        recordingsList[name] = data

        print("✅ تم الحفظ: " .. name .. " (" .. #recordedData .. " حركات)")

    else

        print("ERROR: Failed to save recording.")

    end

    RecordBtn.Text = "● START RECORDING"

    RecordBtn.BackgroundColor3 = Color3.fromRGB(7, 14, 25)

    RecordBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

    UpdateList()

end

-- ============================================

-- PLAY FUNCTIONS

-- ============================================

local function PlayRecording(name)

    local data = recordingsList[name]

    if not data then

        print("❌ ما فيه ريكورد بإسم: " .. tostring(name))

        return

    end

    if loopPlaying then

        print("⚠️ أوقف الLOOP أولاً")

        return

    end

    if playing then

        playing = false

        task.wait(0.1)

    end

    if type(data.Movements) ~= "table" then

        print("❌ الريكورد القديم ما فيه Movements صالحة")

        return

    end

    if #data.Movements == 0 then

        print("ERROR: Recording is empty.")

        return

    end

    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

    local root = char:WaitForChild("HumanoidRootPart", 10)

    if not root then

        print("ERROR: HumanoidRootPart not found.")

        return

    end

    -- دعم صيغ StartPosition القديمة والجديدة

    if data.StartPosition then

        local startPos = data.StartPosition

        local x = tonumber(startPos.X or startPos.x or startPos[1])

        local y = tonumber(startPos.Y or startPos.y or startPos[2])

        local z = tonumber(startPos.Z or startPos.z or startPos[3])

        if x and y and z then

            root.CFrame = CFrame.new(x, y + 3, z)

            task.wait(0.15)

        end

    end

    playing = true

    print("▶️ PLAY: " .. tostring(name) .. " | الحركات: " .. tostring(#data.Movements))

    task.spawn(function()

        for index, move in ipairs(data.Movements) do

            if not playing then

                break

            end

            local charNow = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

            local rootNow = charNow:WaitForChild("HumanoidRootPart", 10)

            if not rootNow then

                print("ERROR: HumanoidRootPart disappeared.")

                break

            end

            local pos = move.Position or move.position or move.Pos or move.pos

            if pos then

                local x = tonumber(pos.X or pos.x or pos[1])

                local y = tonumber(pos.Y or pos.y or pos[2])

                local z = tonumber(pos.Z or pos.z or pos[3])

                if x and y and z then

                    rootNow.CFrame = CFrame.new(x, y + 3, z)

                else

                    print("⚠️ حركة رقم " .. tostring(index) .. " إحداثياتها غير صالحة")

                end

            else

                print("⚠️ حركة رقم " .. tostring(index) .. " ما فيها Position")

            end

            local waitTime = tonumber(move.Time or move.time or move.Delay or move.delay) or 0.03

            waitTime = math.clamp(waitTime, 0.01, 0.25)

            task.wait(waitTime)

        end

        playing = false

        print("✅ انتهى PLAY الريكورد")

    end)

end

-- ============================================

-- STOP PLAYBACK (normal + loop)

-- ============================================

local function StopAllPlayback()

    local wasPlaying = playing or loopPlaying

    playing = false

    loopPlaying = false

    currentLoopName = ""

    if LoopBtn then

        LoopBtn.Text = "↻ LOOP PLAYBACK"

        LoopBtn.BackgroundColor3 = Color3.fromRGB(7, 14, 25)

        LoopBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

    end

    if wasPlaying then

        print("⏹️ تم إيقاف PLAY الريكورد")

    else

        print("ℹ️ ما فيه ريكورد شغال حالياً")

    end

end

-- ============================================

-- LOOP PLAY

-- ============================================

local function StartLoopPlay(name)

    local data = recordingsList[name]

    if not data then

        print("❌ ما فيه ريكورد بإسم: " .. name)

        return

    end

    if loopPlaying then

        loopPlaying = false

        LoopBtn.Text = "↻ LOOP PLAYBACK"

        LoopBtn.BackgroundColor3 = Color3.fromRGB(7, 14, 25)

        LoopBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

        print("⏹️ تم إيقاف الPLAY المتكرر")

        return

    end

    currentLoopName = name

    loopPlaying = true

    LoopBtn.Text = "■ STOP LOOP"

    LoopBtn.BackgroundColor3 = Color3.fromRGB(55, 22, 29)

    LoopBtn.BorderColor3 = Color3.fromRGB(220, 76, 88)

    print("🔄 بدأ الLOOP اللانهائي: " .. name)

    task.spawn(function()

        while loopPlaying do

            local dataNow = recordingsList[currentLoopName]

            if not dataNow then

                print("ERROR: Recording not found.")

                loopPlaying = false

                break

            end

            -- انتظر الشخصية بدل ما نوقف الLOOP

            local char = LocalPlayer.Character

            while loopPlaying and not char do

                task.wait(0.1)

                char = LocalPlayer.Character

            end

            if not loopPlaying then

                break

            end

            -- انتظر HumanoidRootPart بدل ما نوقف الLOOP

            local root = char:FindFirstChild("HumanoidRootPart")

            while loopPlaying and not root do

                task.wait(0.1)

                char = LocalPlayer.Character

                if char then

                    root = char:FindFirstChild("HumanoidRootPart")

                end

            end

            if not loopPlaying then

                break

            end

            -- يرجع لنقطة بداية الريكورد في كل دورة

            local startPos = dataNow.StartPosition

            root.CFrame = CFrame.new(

                Vector3.new(startPos.X, startPos.Y, startPos.Z) + Vector3.new(0, 3, 0)

            )

            task.wait(0.05)

            for _, move in ipairs(dataNow.Movements) do

                if not loopPlaying then

                    break

                end

                local charNow = LocalPlayer.Character

                while loopPlaying and not charNow do

                    task.wait(0.1)

                    charNow = LocalPlayer.Character

                end

                if not loopPlaying then

                    break

                end

                local rootNow = charNow:FindFirstChild("HumanoidRootPart")

                while loopPlaying and not rootNow do

                    task.wait(0.1)

                    charNow = LocalPlayer.Character

                    if charNow then

                        rootNow = charNow:FindFirstChild("HumanoidRootPart")

                    end

                end

                if not loopPlaying then

                    break

                end

                local pos = move.Position

                rootNow.CFrame = CFrame.new(

                    Vector3.new(pos.X, pos.Y, pos.Z) + Vector3.new(0, 3, 0)

                )

                task.wait(math.max(tonumber(move.Time) or 0.03, 0.01))

            end

            -- طالما loopPlaying = true يبدأ دورة جديدة مباشرة

            if loopPlaying then

                task.wait(0.05)

            end

        end

        loopPlaying = false

        LoopBtn.Text = "↻ LOOP PLAYBACK"

        LoopBtn.BackgroundColor3 = Color3.fromRGB(7, 14, 25)

        LoopBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

        print("⏹️ انتهى الLOOP")

    end)

end

-- ============================================

-- DELETE

-- ============================================

local function DeleteRecording(name)

    if not recordingsList[name] then

        print("❌ ما فيه ريكورد بإسم: " .. name)

        return

    end

    if loopPlaying and currentLoopName == name then

        loopPlaying = false

        LoopBtn.Text = "↻ LOOP PLAYBACK"

        LoopBtn.BackgroundColor3 = Color3.fromRGB(7, 14, 25)

        LoopBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

    end

    -- Delete from file

    DeleteRecordingFile(name)

    recordingsList[name] = nil

    print("🗑️ تم حذف: " .. name)

    UpdateList()

end


-- ============================================
-- PLAYER UTILITIES
-- ============================================

local function GetPlayerRoot(player)
    local char = player and player.Character
    return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function GetPlayerHumanoid(player)
    local char = player and player.Character
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function TeleportToPlayer(player)
    local myRoot = GetRoot()
    local targetRoot = GetPlayerRoot(player)
    if not myRoot or not targetRoot then
        warn("VANTAGE: Player position unavailable.")
        return
    end
    myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
end

local function StopSpectate()
    spectatingPlayer = nil

    if spectateConnection then
        spectateConnection:Disconnect()
        spectateConnection = nil
    end

    local camera = workspace.CurrentCamera
    local myHumanoid = GetHumanoid()

    if camera then
        camera.CameraType = Enum.CameraType.Custom
        if myHumanoid then
            camera.CameraSubject = myHumanoid
        end
    end
end

local function StartSpectate(player)
    if not player or player == LocalPlayer then
        StopSpectate()
        return
    end

    StopSpectate()
    spectatingPlayer = player

    local camera = workspace.CurrentCamera
    if not camera then return end

    local function attach()
        if spectatingPlayer ~= player then return end
        local targetHumanoid = GetPlayerHumanoid(player)
        if targetHumanoid and targetHumanoid.Parent then
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = targetHumanoid
        end
    end

    attach()

    spectateConnection = player.CharacterAdded:Connect(function()
        task.wait(0.35)
        attach()
    end)
end


-- ============================================
-- VANTAGE WALL SKELETON ESP
-- ============================================

local STUD_TO_METER = 0.28

local function NewESPLine()
    local line = Instance.new("Frame")
    line.Name = "SkeletonLine"
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.BackgroundColor3 = espColor
    line.BorderSizePixel = 0
    line.ZIndex = 80
    line.Visible = false
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local espGui = playerGui and playerGui:FindFirstChild("VantageRecorderUI")

    if not espGui then
        line:Destroy()
        return nil
    end

    line.Parent = espGui

    local stroke = Instance.new("UIStroke")
    stroke.Color = espColor:Lerp(Color3.new(1, 1, 1), 0.55)
    stroke.Thickness = 0.8
    stroke.Transparency = 0.08
    stroke.Parent = line

    return line
end

local function SetLine(line, a, b, visible)
    if not line or not line.Parent then return end

    if not visible then
        line.Visible = false
        return
    end

    local dx = b.X - a.X
    local dy = b.Y - a.Y
    local length = math.sqrt(dx * dx + dy * dy)

    if length < 1 then
        line.Visible = false
        return
    end

    line.Size = UDim2.new(0, length, 0, 2.4)
    line.Position = UDim2.new(0, (a.X + b.X) * 0.5, 0, (a.Y + b.Y) * 0.5)
    line.Rotation = math.deg(math.atan2(dy, dx))
    line.Visible = true
end

local function GetPartPoint(character, partName)
    if not character then return nil end

    local part = character:FindFirstChild(partName)
    if not part then
        part = character:FindFirstChild(partName, true)
    end

    return (part and part:IsA("BasePart")) and part.Position or nil
end

local function GetSkeletonSegments(character)
    if not character then return {} end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return {} end

    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        return {
            {"Head", "UpperTorso"},
            {"UpperTorso", "LowerTorso"},

            {"UpperTorso", "LeftUpperArm"},
            {"LeftUpperArm", "LeftLowerArm"},
            {"LeftLowerArm", "LeftHand"},

            {"UpperTorso", "RightUpperArm"},
            {"RightUpperArm", "RightLowerArm"},
            {"RightLowerArm", "RightHand"},

            {"LowerTorso", "LeftUpperLeg"},
            {"LeftUpperLeg", "LeftLowerLeg"},
            {"LeftLowerLeg", "LeftFoot"},

            {"LowerTorso", "RightUpperLeg"},
            {"RightUpperLeg", "RightLowerLeg"},
            {"RightLowerLeg", "RightFoot"},
        }
    else
        return {
            {"Head", "Torso"},
            {"Torso", "Left Arm"},
            {"Torso", "Right Arm"},
            {"Torso", "Left Leg"},
            {"Torso", "Right Leg"},
        }
    end
end

local function RemoveESP(player)
    local data = espObjects[player]
    if not data then return end

    if data.Lines then
        for _, line in ipairs(data.Lines) do
            pcall(function() line:Destroy() end)
        end
    end

    if data.NameTag then
        pcall(function() data.NameTag:Destroy() end)
    end

    local deathConnection = espDeathConnections[player]
    if deathConnection then
        deathConnection:Disconnect()
        espDeathConnections[player] = nil
    end

    local healthConnection = espHealthConnections[player]
    if healthConnection then
        healthConnection:Disconnect()
        espHealthConnections[player] = nil
    end

    local ancestryConnection = espAncestryConnections[player]
    if ancestryConnection then
        ancestryConnection:Disconnect()
        espAncestryConnections[player] = nil
    end

    espObjects[player] = nil
end

local function CreateESP(player)
    if not espEnabled or not player or player == LocalPlayer then
        return
    end

    local character = player.Character
    if not character or not character.Parent then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("HumanoidRootPart", true)

    if not humanoid or humanoid.Health <= 0 or not root then
        return
    end

    local segments = GetSkeletonSegments(character)
    if #segments == 0 then
        return
    end

    -- Only remove the old ESP after the replacement character is valid.
    RemoveESP(player)

    local lines = {}

    for _ = 1, #segments do
        local line = NewESPLine()
        if line then
            table.insert(lines, line)
        end
    end

    if #lines ~= #segments then
        for _, line in ipairs(lines) do
            pcall(function() line:Destroy() end)
        end
        return
    end

    local nameTag = Instance.new("TextLabel")
    nameTag.Name = "VantageESP_Name"
    nameTag.AnchorPoint = Vector2.new(0.5, 1)
    nameTag.Size = UDim2.new(0, 300, 0, 42)
    nameTag.BackgroundTransparency = 1
    nameTag.Text = ""
    nameTag.TextColor3 = espColor:Lerp(Color3.new(1, 1, 1), 0.72)
    nameTag.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameTag.TextStrokeTransparency = 0
    nameTag.TextSize = 15
    nameTag.Font = Enum.Font.GothamBold
    nameTag.TextXAlignment = Enum.TextXAlignment.Center
    nameTag.TextYAlignment = Enum.TextYAlignment.Center
    nameTag.ZIndex = 81
    nameTag.Visible = false

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local espGui = playerGui and playerGui:FindFirstChild("VantageRecorderUI")

    if not espGui then
        nameTag:Destroy()
        for _, line in ipairs(lines) do
            pcall(function() line:Destroy() end)
        end
        return
    end

    nameTag.Parent = espGui

    espObjects[player] = {
        Character = character,
        Lines = lines,
        Segments = segments,
        NameTag = nameTag,
    }

    if espDeathConnections[player] then
        espDeathConnections[player]:Disconnect()
        espDeathConnections[player] = nil
    end

    if espHealthConnections[player] then
        espHealthConnections[player]:Disconnect()
        espHealthConnections[player] = nil
    end

    if espAncestryConnections[player] then
        espAncestryConnections[player]:Disconnect()
        espAncestryConnections[player] = nil
    end

    espDeathConnections[player] = humanoid.Died:Connect(function()
        RemoveESP(player)
    end)

    espHealthConnections[player] = humanoid.HealthChanged:Connect(function(health)
        if health <= 0 then
            RemoveESP(player)
        end
    end)

    espAncestryConnections[player] = character.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            RemoveESP(player)
        end
    end)
end

local function RefreshESP()
    local existing = {}
    for player in pairs(espObjects) do
        table.insert(existing, player)
    end

    for _, player in ipairs(existing) do
        RemoveESP(player)
    end

    if not espEnabled then return end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            CreateESP(player)
        end
    end
end

local function StopESPUpdater()
    if espUpdateConnection then
        espUpdateConnection:Disconnect()
        espUpdateConnection = nil
    end
end


function VantageBotRadar.IsPlayerCharacter(model)
    if not model or not model:IsA("Model") then
        return false
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then
            return true
        end
    end

    return false
end

function VantageBotRadar.Remove(model)
    local data = VantageBotRadar.Objects[model]
    if not data then return end

    for _, line in ipairs(data.Lines or {}) do
        pcall(function()
            if line then
                line:Destroy()
            end
        end)
    end

    if data.NameTag then
        pcall(function()
            data.NameTag:Destroy()
        end)
    end

    VantageBotRadar.Objects[model] = nil
end

function VantageBotRadar.GetSegments(model)
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    if not humanoid then return {} end

    -- Reuse the exact same R6/R15 skeleton builder as players.
    local segments = GetSkeletonSegments(model)
    if #segments > 0 then
        return segments
    end

    -- Simple/custom bot fallback.
    local head = model:FindFirstChild("Head") or model:FindFirstChild("Head", true)
    local root = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("HumanoidRootPart", true)
    local torso = model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("UpperTorso", true)
        or model:FindFirstChild("Torso", true)

    if head and torso then
        return {{"Head", torso.Name}}
    end

    if head and root and head ~= root then
        return {{"Head", root.Name}}
    end

    return {}
end

function VantageBotRadar.Create(model)
    if not espEnabled
        or not model
        or not model:IsA("Model")
        or not model.Parent
        or VantageBotRadar.IsPlayerCharacter(model) then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("HumanoidRootPart", true)

    if not humanoid or humanoid.Health <= 0 or not root then
        return false
    end

    local segments = VantageBotRadar.GetSegments(model)
    if #segments == 0 then
        return false
    end

    VantageBotRadar.Remove(model)

    local lines = {}
    for _ = 1, #segments do
        local line = NewESPLine()
        if line then
            table.insert(lines, line)
        end
    end

    if #lines ~= #segments then
        for _, line in ipairs(lines) do
            pcall(function()
                if line then line:Destroy() end
            end)
        end
        return false
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local espGui = playerGui and playerGui:FindFirstChild("VantageRecorderUI")
    if not espGui then
        for _, line in ipairs(lines) do
            pcall(function()
                if line then line:Destroy() end
            end)
        end
        return false
    end

    local tag = Instance.new("TextLabel")
    tag.Name = "VantageBotESP_Name"
    tag.AnchorPoint = Vector2.new(0.5, 1)
    tag.Size = UDim2.new(0, 300, 0, 42)
    tag.BackgroundTransparency = 1
    tag.Text = ""
    tag.TextColor3 = espColor:Lerp(Color3.new(1, 1, 1), 0.72)
    tag.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    tag.TextStrokeTransparency = 0
    tag.TextSize = 15
    tag.Font = Enum.Font.GothamBold
    tag.TextXAlignment = Enum.TextXAlignment.Center
    tag.TextYAlignment = Enum.TextYAlignment.Center
    tag.ZIndex = 81
    tag.Visible = false
    tag.Parent = espGui

    VantageBotRadar.Objects[model] = {
        Humanoid = humanoid,
        Root = root,
        Lines = lines,
        Segments = segments,
        NameTag = tag,
    }

    return true
end

function VantageBotRadar.Reconcile()
    if not espEnabled then return end

    local seen = {}

    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("Humanoid") then
            local model = descendant.Parent

            if model
                and model:IsA("Model")
                and descendant.Health > 0
                and not VantageBotRadar.IsPlayerCharacter(model) then

                local root = model:FindFirstChild("HumanoidRootPart")
                    or model:FindFirstChild("HumanoidRootPart", true)

                if root then
                    seen[model] = true

                    local data = VantageBotRadar.Objects[model]
                    if not data
                        or data.Humanoid ~= descendant
                        or data.Root ~= root
                        or not data.NameTag
                        or not data.NameTag.Parent then
                        VantageBotRadar.Create(model)
                    end
                end
            end
        end
    end

    local stale = {}
    for model, data in pairs(VantageBotRadar.Objects) do
        if not seen[model]
            or not model
            or not model.Parent
            or not data.Humanoid
            or data.Humanoid.Health <= 0 then
            table.insert(stale, model)
        end
    end

    for _, model in ipairs(stale) do
        VantageBotRadar.Remove(model)
    end
end

function VantageBotRadar.Update(camera, myRoot)
    local stale = {}

    for model, data in pairs(VantageBotRadar.Objects) do
        local humanoid = data.Humanoid
        local root = data.Root

        if not model
            or not model.Parent
            or not humanoid
            or humanoid.Health <= 0
            or not root
            or not root.Parent then
            table.insert(stale, model)
        else
            for index, segment in ipairs(data.Segments or {}) do
                local aWorld = GetPartPoint(model, segment[1])
                local bWorld = GetPartPoint(model, segment[2])
                local line = data.Lines[index]

                if aWorld and bWorld and line then
                    local aScreen = camera:WorldToScreenPoint(aWorld)
                    local bScreen = camera:WorldToScreenPoint(bWorld)

                    SetLine(
                        line,
                        Vector2.new(aScreen.X, aScreen.Y),
                        Vector2.new(bScreen.X, bScreen.Y),
                        aScreen.Z > 0 and bScreen.Z > 0
                    )
                elseif line then
                    line.Visible = false
                end
            end

            local labelPart = model:FindFirstChild("Head")
                or model:FindFirstChild("Head", true)
                or model:FindFirstChild("UpperTorso")
                or model:FindFirstChild("Torso")
                or root

            if labelPart and data.NameTag then
                local offset = (labelPart.Name == "Head") and 0.8 or 2.5
                local screen = camera:WorldToScreenPoint(
                    labelPart.Position + Vector3.new(0, offset, 0)
                )

                if screen.Z > 0 then
                    local meters = 0
                    if myRoot then
                        meters = (myRoot.Position - root.Position).Magnitude * STUD_TO_METER
                    end

                    local botName = humanoid.DisplayName
                    if not botName or botName == "" then
                        botName = model.Name
                    end
                    if not botName or botName == "" then
                        botName = "BOT"
                    end

                    data.NameTag.Position = UDim2.new(0, screen.X, 0, screen.Y - 8)
                    data.NameTag.Text = string.format(
                        "[BOT] %s  •  %.1f m",
                        botName,
                        meters
                    )
                    data.NameTag.Visible = true
                else
                    data.NameTag.Visible = false
                end
            end
        end
    end

    for _, model in ipairs(stale) do
        VantageBotRadar.Remove(model)
    end
end

function VantageBotRadar.Clear()
    local models = {}
    for model in pairs(VantageBotRadar.Objects) do
        table.insert(models, model)
    end

    for _, model in ipairs(models) do
        VantageBotRadar.Remove(model)
    end

    VantageBotRadar.Elapsed = 0
end

local function StartESPUpdater()
    StopESPUpdater()

    espReconcileElapsed = 0

    espUpdateConnection = RunService.RenderStepped:Connect(function(dt)
        if not espEnabled then
            StopESPUpdater()
            return
        end

        local camera = workspace.CurrentCamera
        local myRoot = GetRoot()
        if not camera then return end

        -- BOT/NPC ESP runs inside this SAME updater.
        VantageBotRadar.Elapsed += dt
        if VantageBotRadar.Elapsed >= 0.25 then
            VantageBotRadar.Elapsed = 0
            VantageBotRadar.Reconcile()
        end
        VantageBotRadar.Update(camera, myRoot)

        -- Reconcile missing ESP entries inside the same updater.
        -- This fixes players whose character/rig was only partially loaded
        -- when CharacterAdded first fired, without adding another permanent loop.
        espReconcileElapsed += dt
        if espReconcileElapsed >= ESP_RECONCILE_INTERVAL then
            espReconcileElapsed = 0

            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local character = player.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    local root = character and (
                        character:FindFirstChild("HumanoidRootPart")
                        or character:FindFirstChild("HumanoidRootPart", true)
                    )
                    local data = espObjects[player]

                    if character
                        and character.Parent
                        and humanoid
                        and root
                        and humanoid.Health > 0
                        and humanoid:GetState() ~= Enum.HumanoidStateType.Dead then

                        local needsESP = not data
                            or data.Character ~= character
                            or not data.NameTag
                            or not data.NameTag.Parent

                        if not needsESP and data.Lines then
                            for _, line in ipairs(data.Lines) do
                                if not line or not line.Parent then
                                    needsESP = true
                                    break
                                end
                            end
                        end

                        if needsESP then
                            CreateESP(player)
                        end
                    elseif data then
                        RemoveESP(player)
                    end
                end
            end
        end

        local rebuild = {}
        local remove = {}

        for player, data in pairs(espObjects) do
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and (
                character:FindFirstChild("HumanoidRootPart")
                or character:FindFirstChild("HumanoidRootPart", true)
            )
            local head = character and (
                character:FindFirstChild("Head")
                or character:FindFirstChild("Head", true)
            )

            if not character
                or data.Character ~= character
                or not humanoid
                or not root
                or not character.Parent
                or humanoid.Health <= 0
                or humanoid:GetState() == Enum.HumanoidStateType.Dead then
                table.insert(remove, player)
            else
                local currentSegments = data.Segments or {}

                if #currentSegments ~= #data.Lines or #currentSegments == 0 then
                    table.insert(rebuild, player)
                else
                    for i, segment in ipairs(currentSegments) do
                        local aWorld = GetPartPoint(character, segment[1])
                        local bWorld = GetPartPoint(character, segment[2])

                        if aWorld and bWorld then
                            local aScreen, aVisible = camera:WorldToScreenPoint(aWorld)
                            local bScreen, bVisible = camera:WorldToScreenPoint(bWorld)

                            local inFront = aScreen.Z > 0 and bScreen.Z > 0

                            SetLine(
                                data.Lines[i],
                                Vector2.new(aScreen.X, aScreen.Y),
                                Vector2.new(bScreen.X, bScreen.Y),
                                inFront
                            )
                        else
                            data.Lines[i].Visible = false
                        end
                    end

                    local labelPart = head
                        or character:FindFirstChild("UpperTorso")
                        or character:FindFirstChild("Torso")
                        or root

                    if labelPart and data.NameTag then
                        local yOffset = (labelPart == head) and 0.8 or 2.5
                        local headScreen = camera:WorldToScreenPoint(
                            labelPart.Position + Vector3.new(0, yOffset, 0)
                        )

                        if headScreen.Z > 0 then
                            local meters = 0
                            if myRoot then
                                meters = (myRoot.Position - root.Position).Magnitude * STUD_TO_METER
                            end

                            data.NameTag.Position = UDim2.new(0, headScreen.X, 0, headScreen.Y - 8)
                            data.NameTag.Text = string.format(
                                "%s  •  %.1f m",
                                player.DisplayName,
                                meters
                            )
                            data.NameTag.Visible = true
                        else
                            data.NameTag.Visible = false
                        end
                    end
                end
            end
        end

        for _, player in ipairs(remove) do
            RemoveESP(player)
        end

        for _, player in ipairs(rebuild) do
            if espEnabled then
                CreateESP(player)
            end
        end
    end)
end


local function ApplyESPColor(color)
    if typeof(color) ~= "Color3" then return end

    espColor = color

    for _, data in pairs(espObjects) do
        if data.Lines then
            for _, line in ipairs(data.Lines) do
                if line and line.Parent then
                    line.BackgroundColor3 = espColor

                    local stroke = line:FindFirstChildOfClass("UIStroke")
                    if stroke then
                        stroke.Color = espColor:Lerp(Color3.new(1, 1, 1), 0.55)
                    end
                end
            end
        end

        if data.NameTag and data.NameTag.Parent then
            data.NameTag.TextColor3 = espColor:Lerp(Color3.new(1, 1, 1), 0.72)
        end
    end

    for _, data in pairs(VantageBotRadar.Objects) do
        for _, line in ipairs(data.Lines or {}) do
            if line and line.Parent then
                line.BackgroundColor3 = espColor
                local stroke = line:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = espColor:Lerp(Color3.new(1, 1, 1), 0.55)
                end
            end
        end

        if data.NameTag and data.NameTag.Parent then
            data.NameTag.TextColor3 = espColor:Lerp(Color3.new(1, 1, 1), 0.72)
        end
    end

end

local function SetESPEnabled(enabled)
    espEnabled = enabled and true or false

    if espEnabled then
        RefreshESP()
        StartESPUpdater()
    else
        StopESPUpdater()
        espReconcileElapsed = 0
        RefreshESP()
        VantageBotRadar.Clear()
    end
end


-- PROFILE APPLY
-- Defined here so all movement + ESP locals are already in lexical scope.
ApplyProfile = function(name)
    local profile = savedProfiles[name]
    if type(profile) ~= "table" then
        return false
    end

    -- MOVEMENT
    SetWalkSpeed(tonumber(profile.WalkSpeed) or DEFAULT_WALK_SPEED)
    flySpeed = math.clamp(tonumber(profile.FlySpeed) or flySpeed, 10, 200)

    antiFallEnabled = profile.AntiFall == true
    autoReturnEnabled = profile.AutoReturn == true

    if antiFallEnabled then
        StartAntiFall()
    else
        StopAntiFall()
    end

    -- ESP / RADAR
    if type(profile.ESPColor) == "table" then
        local r = math.clamp(tonumber(profile.ESPColor.R) or 90, 0, 255)
        local g = math.clamp(tonumber(profile.ESPColor.G) or 185, 0, 255)
        local b = math.clamp(tonumber(profile.ESPColor.B) or 255, 0, 255)
        ApplyESPColor(Color3.fromRGB(r, g, b))
    end

    SetESPEnabled(profile.ESPEnabled == true)

    -- FLY toggle
    local shouldFly = profile.Flying == true
    if shouldFly and not flying then
        StartFly()
    elseif not shouldFly and flying then
        StopFly()
    end

    -- PLAYER FINDER
    if type(profile.PlayerSearchQuery) == "string" then
        playerSearchQuery = profile.PlayerSearchQuery
        if VantageProfileBridge.SetPlayerSearchQuery then
            pcall(VantageProfileBridge.SetPlayerSearchQuery, playerSearchQuery)
        end
    end

    -- AIM is isolated and loads later, so use its bridge.
    if VantageProfileBridge.ApplyAimState then
        local okAim, errAim = pcall(function()
            VantageProfileBridge.ApplyAimState({
                Enabled = profile.AimEnabled == true,
                FOV = tonumber(profile.AimFOVRadius),
                Smoothness = tonumber(profile.AimSmoothness),
                TargetPart = profile.AimTargetPart,
            })
        end)

        if not okAim then
            warn("VANTAGE PROFILE AIM APPLY ERROR: " .. tostring(errAim))
        end
    end

    activeProfileName = name
    SaveActiveProfileName(name)

    -- Notify GUI/state bridges after everything has been applied.
    if VantageProfileBridge.RefreshUI then
        pcall(VantageProfileBridge.RefreshUI)
    end

    return true
end

local function AttachESPCharacterWatcher(player)
    if not player or player == LocalPlayer or espCharacterConnections[player] then
        return
    end

    espCharacterConnections[player] = player.CharacterAdded:Connect(function(character)
        if espEnabled then
            task.defer(function()
                -- Immediate attempt first.
                if player.Character == character and espEnabled then
                    CreateESP(player)
                end

                -- Short bounded retry burst for streamed/late rig parts.
                -- Stops as soon as ESP is successfully created.
                for _ = 1, 12 do
                    if not espEnabled or player.Character ~= character then
                        break
                    end

                    task.wait(0.10)

                    local data = espObjects[player]
                    if character.Parent and (not data or data.Character ~= character) then
                        CreateESP(player)
                    elseif data and data.Character == character then
                        break
                    end
                end
            end)
        end
    end)

    espRemovingConnections[player] = player.CharacterRemoving:Connect(function()
        RemoveESP(player)
    end)
end

local function DetachESPCharacterWatcher(player)
    local connection = espCharacterConnections[player]
    if connection then
        connection:Disconnect()
        espCharacterConnections[player] = nil
    end

    local removingConnection = espRemovingConnections[player]
    if removingConnection then
        removingConnection:Disconnect()
        espRemovingConnections[player] = nil
    end

    local deathConnection = espDeathConnections[player]
    if deathConnection then
        deathConnection:Disconnect()
        espDeathConnections[player] = nil
    end

    local healthConnection = espHealthConnections[player]
    if healthConnection then
        healthConnection:Disconnect()
        espHealthConnections[player] = nil
    end

    local ancestryConnection = espAncestryConnections[player]
    if ancestryConnection then
        ancestryConnection:Disconnect()
        espAncestryConnections[player] = nil
    end
end

-- CREATE GUI - VANTAGE MINIMAL NAVY
-- ============================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VantageRecorderUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local TweenService = game:GetService("TweenService")

local T = {
    Black = Color3.fromRGB(5, 5, 9),
    Navy = Color3.fromRGB(10, 9, 17),
    Navy2 = Color3.fromRGB(15, 12, 26),
    Surface = Color3.fromRGB(18, 14, 31),
    Surface2 = Color3.fromRGB(24, 18, 42),
    Border = Color3.fromRGB(63, 45, 96),
    Blue = Color3.fromRGB(145, 82, 255),
    BlueSoft = Color3.fromRGB(181, 126, 255),
    Purple = Color3.fromRGB(145, 82, 255),
    PurpleSoft = Color3.fromRGB(190, 142, 255),
    Text = Color3.fromRGB(244, 241, 250),
    Muted = Color3.fromRGB(151, 145, 169),
    Green = Color3.fromRGB(81, 218, 154),
    Red = Color3.fromRGB(237, 88, 112),
}

local function Corner(obj, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = obj
end

local function Stroke(obj, color, trans)
    local s = Instance.new("UIStroke")
    s.Color = color or T.Border
    s.Thickness = 1
    s.Transparency = trans or 0
    s.Parent = obj
    return s
end

local function Text(parent, value, size, pos, font, textSize, color, align)
    local x = Instance.new("TextLabel")
    x.BackgroundTransparency = 1
    x.Size = size
    x.Position = pos
    x.Text = value
    x.Font = font or Enum.Font.Gotham
    x.TextSize = textSize or 14
    x.TextColor3 = color or T.Text
    x.TextXAlignment = align or Enum.TextXAlignment.Left
    x.TextYAlignment = Enum.TextYAlignment.Center
    x.Parent = parent
    return x
end

local function Hover(btn, normal, hover)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.14), {BackgroundColor3 = hover}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.14), {BackgroundColor3 = normal}):Play()
    end)
end

-- Main shell
local MainMenu = Instance.new("Frame")
MainMenu.Name = "MainMenu"
MainMenu.AnchorPoint = Vector2.new(0.5, 0.5)
MainMenu.Size = UDim2.new(0, 650, 0, 630)
MainMenu.Position = UDim2.new(0.5, 0, 0.5, 0)
MainMenu.BackgroundColor3 = T.Black
MainMenu.BorderSizePixel = 0
MainMenu.Visible = true
MainMenu.Parent = ScreenGui
Corner(MainMenu, 14)
Stroke(MainMenu, Color3.fromRGB(79, 48, 121), 0.05)

local ShellGradient = Instance.new("UIGradient")
ShellGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(4, 4, 8)),
    ColorSequenceKeypoint.new(0.58, Color3.fromRGB(10, 7, 17)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 10, 29))
})
ShellGradient.Rotation = 12
ShellGradient.Parent = MainMenu

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 70)
Header.BackgroundColor3 = Color3.fromRGB(9, 7, 15)
Header.BorderSizePixel = 0
Header.Parent = MainMenu
Corner(Header, 14)

local LogoBox = Instance.new("Frame")
LogoBox.Size = UDim2.new(0, 40, 0, 40)
LogoBox.Position = UDim2.new(0, 18, 0, 15)
LogoBox.BackgroundColor3 = T.Navy2
LogoBox.BorderSizePixel = 0
LogoBox.Parent = Header
Corner(LogoBox, 10)
Stroke(LogoBox, T.Border, 0)

local Logo = Text(LogoBox, "V", UDim2.new(1,0,1,0), UDim2.new(), Enum.Font.GothamBlack, 20, T.BlueSoft, Enum.TextXAlignment.Center)

local Brand = Text(Header, "VANTAGE", UDim2.new(0, 210, 0, 24), UDim2.new(0, 70, 0, 13), Enum.Font.GothamBold, 17, T.Text)
local Sub = Text(Header, "ULTIMATE GAME ENHANCER", UDim2.new(0, 210, 0, 18), UDim2.new(0, 70, 0, 36), Enum.Font.GothamMedium, 9, T.Muted)


local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 32, 0, 32)
MinBtn.Position = UDim2.new(1, -82, 0, 19)
MinBtn.BackgroundColor3 = T.Navy
MinBtn.BorderSizePixel = 0
MinBtn.Text = "–"
MinBtn.TextColor3 = T.Muted
MinBtn.TextSize = 17
MinBtn.Font = Enum.Font.GothamBold
MinBtn.Parent = Header
Corner(MinBtn, 8)
Stroke(MinBtn, T.Border, 0.2)
Hover(MinBtn, T.Navy, T.Surface)

local HeaderClose = Instance.new("TextButton")
HeaderClose.Size = UDim2.new(0, 32, 0, 32)
HeaderClose.Position = UDim2.new(1, -44, 0, 19)
HeaderClose.BackgroundColor3 = T.Navy
HeaderClose.BorderSizePixel = 0
HeaderClose.Text = "×"
HeaderClose.TextColor3 = T.Muted
HeaderClose.TextSize = 19
HeaderClose.Font = Enum.Font.Gotham
HeaderClose.Parent = Header
Corner(HeaderClose, 8)
Stroke(HeaderClose, T.Border, 0.2)
Hover(HeaderClose, T.Navy, Color3.fromRGB(37, 18, 25))

-- Content
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -32, 1, -120)
Content.Position = UDim2.new(0, 16, 0, 84)
Content.BackgroundTransparency = 1
Content.Parent = MainMenu

local SectionTitle = Text(Content, "QUICK ACTIONS", UDim2.new(1, 0, 0, 20), UDim2.new(0, 2, 0, 0), Enum.Font.GothamBold, 10, T.Muted)

local function ActionButton(name, x, y, w, h, icon, title, desc, accent)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, w, 0, h)
    btn.Position = UDim2.new(0, x, 0, y)
    btn.BackgroundColor3 = T.Navy
    btn.BorderSizePixel = 0
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = Content
    Corner(btn, 12)
    Stroke(btn, T.Border, 0.18)
    Hover(btn, T.Navy, T.Surface)

    local iconBox = Instance.new("Frame")
    iconBox.Size = UDim2.new(0, 42, 0, 42)
    iconBox.Position = UDim2.new(0, 14, 0.5, -21)
    iconBox.BackgroundColor3 = Color3.fromRGB(8, 18, 31)
    iconBox.BorderSizePixel = 0
    iconBox.Parent = btn
    Corner(iconBox, 10)
    Stroke(iconBox, accent, 0.25)

    Text(iconBox, icon, UDim2.new(1,0,1,0), UDim2.new(), Enum.Font.GothamBold, 18, accent, Enum.TextXAlignment.Center)
    Text(btn, title, UDim2.new(1, -80, 0, 22), UDim2.new(0, 68, 0, 15), Enum.Font.GothamBold, 13, T.Text)
    Text(btn, desc, UDim2.new(1, -80, 0, 18), UDim2.new(0, 68, 0, 38), Enum.Font.Gotham, 9, T.Muted)

    local arrow = Text(btn, "›", UDim2.new(0, 20, 0, 30), UDim2.new(1, -32, 0.5, -15), Enum.Font.GothamBold, 20, Color3.fromRGB(83, 105, 130), Enum.TextXAlignment.Center)
    return btn
end

RecordBtn = ActionButton("RecordButton", 0, 28, 296, 76, "●", "START RECORDING", "Capture and save movement", T.BlueSoft)
LoopBtn = ActionButton("LoopButton", 306, 28, 296, 76, "↻", "LOOP PLAYBACK", "Repeat selected recording", T.Blue)
StopBtn = ActionButton("StopButton", 0, 114, 296, 76, "■", "STOP PLAYBACK", "Stop active playback", T.Red)
ListBtn = ActionButton("LibraryButton", 306, 114, 296, 76, "≡", "RECORDINGS", "Open recording library", Color3.fromRGB(91, 137, 184))

LocationsBtn = ActionButton("LocationsButton", 0, 200, 296, 64, "⌖", "LOCATIONS", "F10 save • teleport • loop", Color3.fromRGB(78, 132, 185))
MovementBtn = ActionButton("MovementButton", 306, 200, 296, 64, "»", "MOVEMENT", "Speed • anti-fall • auto return", Color3.fromRGB(128, 83, 214))

PlayersBtn = ActionButton("PlayersButton", 0, 274, 194, 64, "◎", "PLAYER LIST", "Players and spectate", Color3.fromRGB(117, 76, 198))
ESPMainBtn = ActionButton("ESPButton", 204, 274, 194, 64, "◇", "ESP: OFF", "Wall skeleton ESP", Color3.fromRGB(166, 105, 255))
ESPColorBtn = ActionButton("ESPColorButton", 408, 274, 194, 64, "◈", "ESP COLOR", "Choose custom RGB", espColor)

ProfilesBtn = ActionButton("ProfilesButton", 0, 348, 602, 54, "▣", "PROFILES", "Save and restore your VANTAGE setup", Color3.fromRGB(137, 91, 218))

-- Wide exit row
CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "ExitButton"
CloseBtn.Size = UDim2.new(0, 602, 0, 46)
CloseBtn.Position = UDim2.new(0, 0, 0, 412)
CloseBtn.BackgroundColor3 = Color3.fromRGB(9, 17, 29)
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = ""
CloseBtn.AutoButtonColor = false
CloseBtn.Parent = Content
Corner(CloseBtn, 12)
Stroke(CloseBtn, Color3.fromRGB(41, 60, 83), 0.18)
Hover(CloseBtn, Color3.fromRGB(9, 17, 29), Color3.fromRGB(14, 25, 41))

local ExitIcon = Text(CloseBtn, "×", UDim2.new(0, 40, 1, 0), UDim2.new(0, 14, 0, 0), Enum.Font.GothamBold, 19, Color3.fromRGB(144, 159, 178), Enum.TextXAlignment.Center)
Text(CloseBtn, "EXIT RECORDER", UDim2.new(0, 180, 0, 22), UDim2.new(0, 62, 0, 9), Enum.Font.GothamBold, 12, T.Text)
Text(CloseBtn, "Close interface and stop all processes", UDim2.new(0, 300, 0, 18), UDim2.new(0, 62, 0, 30), Enum.Font.Gotham, 9, T.Muted)
Text(CloseBtn, "›", UDim2.new(0, 30, 1, 0), UDim2.new(1, -42, 0, 0), Enum.Font.GothamBold, 20, T.Muted, Enum.TextXAlignment.Center)

-- Bottom status bar
local Footer = Instance.new("Frame")
Footer.Size = UDim2.new(1, -32, 0, 30)
Footer.Position = UDim2.new(0, 16, 1, -38)
Footer.BackgroundColor3 = Color3.fromRGB(6, 12, 21)
Footer.BorderSizePixel = 0
Footer.Parent = MainMenu
Corner(Footer, 9)
Stroke(Footer, T.Border, 0.38)

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 7, 0, 7)
StatusDot.Position = UDim2.new(0, 12, 0.5, -3)
StatusDot.BackgroundColor3 = T.Green
StatusDot.BorderSizePixel = 0
StatusDot.Parent = Footer
Corner(StatusDot, 7)

Text(Footer, "READY", UDim2.new(0, 90, 1, 0), UDim2.new(0, 27, 0, 0), Enum.Font.GothamBold, 9, T.Green)
Text(Footer, "VANTAGE RECORDER", UDim2.new(0, 180, 1, 0), UDim2.new(0.5, -90, 0, 0), Enum.Font.GothamMedium, 9, T.Muted, Enum.TextXAlignment.Center)
Text(Footer, "v3.0", UDim2.new(0, 70, 1, 0), UDim2.new(1, -82, 0, 0), Enum.Font.GothamBold, 9, Color3.fromRGB(95, 117, 143), Enum.TextXAlignment.Right)

local ServerCountLabel = Text(
    Footer, "PLAYERS: 0",
    UDim2.new(0, 120, 1, 0), UDim2.new(1, -220, 0, 0),
    Enum.Font.GothamBold, 9, T.BlueSoft, Enum.TextXAlignment.Right
)

local PerformanceHUD = Instance.new("Frame")
PerformanceHUD.Name = "PerformanceHUD"
PerformanceHUD.Size = UDim2.new(0, 188, 0, 34)
PerformanceHUD.Position = UDim2.new(1, -204, 0, 8)
PerformanceHUD.BackgroundColor3 = Color3.fromRGB(5, 12, 21)
PerformanceHUD.BorderSizePixel = 0
PerformanceHUD.ZIndex = 90
PerformanceHUD.Parent = ScreenGui
Corner(PerformanceHUD, 9)
Stroke(PerformanceHUD, T.Border, 0.3)

local FPSLabel = Text(
    PerformanceHUD, "FPS: —",
    UDim2.new(0.5, -8, 1, 0), UDim2.new(0, 8, 0, 0),
    Enum.Font.GothamBold, 10, T.Green
)
FPSLabel.ZIndex = 91

local PingLabel = Text(
    PerformanceHUD, "PING: —",
    UDim2.new(0.5, -8, 1, 0), UDim2.new(0.5, 0, 0, 0),
    Enum.Font.GothamBold, 10, T.BlueSoft
)
PingLabel.ZIndex = 91

local function UpdateServerCounter()
    if ServerCountLabel and ServerCountLabel.Parent then
        ServerCountLabel.Text = "PLAYERS: " .. tostring(#Players:GetPlayers())
    end
end

local function GetPingText()
    local ok, value = pcall(function()
        local network = Stats:FindFirstChild("Network")
        local serverStats = network and network:FindFirstChild("ServerStatsItem")
        local pingItem = serverStats and serverStats:FindFirstChild("Data Ping")
        return pingItem and pingItem:GetValueString() or nil
    end)

    if ok and value and value ~= "" then return value end
    return "—"
end

local function StopPerformanceHUD()
    if hudConnection then
        hudConnection:Disconnect()
        hudConnection = nil
    end
end

local function StartPerformanceHUD()
    StopPerformanceHUD()
    hudElapsed = 0
    hudFrames = 0

    hudConnection = RunService.RenderStepped:Connect(function(dt)
        hudElapsed += dt
        hudFrames += 1

        if hudElapsed >= 0.5 then
            currentFPS = math.floor(hudFrames / hudElapsed + 0.5)
            currentPing = GetPingText()

            if FPSLabel and FPSLabel.Parent then
                FPSLabel.Text = "FPS: " .. tostring(currentFPS)
            end
            if PingLabel and PingLabel.Parent then
                PingLabel.Text = "PING: " .. tostring(currentPing)
            end

            hudElapsed = 0
            hudFrames = 0
        end
    end)
end

UpdateServerCounter()
StartPerformanceHUD()



-- ESP COLOR PICKER
local ESPColorFrame = Instance.new("Frame")
ESPColorFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ESPColorFrame.Size = UDim2.new(0, 430, 0, 300)
ESPColorFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
ESPColorFrame.BackgroundColor3 = T.Black
ESPColorFrame.BorderSizePixel = 0
ESPColorFrame.Visible = false
ESPColorFrame.ZIndex = 120
ESPColorFrame.Parent = ScreenGui
Corner(ESPColorFrame, 14)
Stroke(ESPColorFrame, T.Border, 0.02)

local ESPColorTitle = Text(
    ESPColorFrame, "ESP COLOR",
    UDim2.new(1, -70, 0, 28), UDim2.new(0, 18, 0, 14),
    Enum.Font.GothamBold, 16, T.Text
)
ESPColorTitle.ZIndex = 121

local ESPColorSub = Text(
    ESPColorFrame, "Choose a color",
    UDim2.new(1, -36, 0, 18), UDim2.new(0, 18, 0, 42),
    Enum.Font.Gotham, 9, T.Muted
)
ESPColorSub.ZIndex = 121

local ESPColorClose = Instance.new("TextButton")
ESPColorClose.Size = UDim2.new(0, 32, 0, 32)
ESPColorClose.Position = UDim2.new(1, -46, 0, 16)
ESPColorClose.BackgroundColor3 = T.Navy
ESPColorClose.BorderSizePixel = 0
ESPColorClose.Text = "×"
ESPColorClose.TextColor3 = T.Muted
ESPColorClose.TextSize = 18
ESPColorClose.Font = Enum.Font.GothamBold
ESPColorClose.ZIndex = 123
ESPColorClose.Parent = ESPColorFrame
Corner(ESPColorClose, 8)

local ESPPalette = Instance.new("Frame")
ESPPalette.Size = UDim2.new(1, -36, 0, 184)
ESPPalette.Position = UDim2.new(0, 18, 0, 70)
ESPPalette.BackgroundTransparency = 1
ESPPalette.ZIndex = 121
ESPPalette.Parent = ESPColorFrame

local ESPPaletteGrid = Instance.new("UIGridLayout")
ESPPaletteGrid.CellSize = UDim2.new(0, 58, 0, 48)
ESPPaletteGrid.CellPadding = UDim2.new(0, 7, 0, 8)
ESPPaletteGrid.FillDirectionMaxCells = 6
ESPPaletteGrid.SortOrder = Enum.SortOrder.LayoutOrder
ESPPaletteGrid.Parent = ESPPalette

local paletteColors = {
    {Name = "BLUE",    Color = Color3.fromRGB(70, 170, 255)},
    {Name = "CYAN",    Color = Color3.fromRGB(45, 235, 255)},
    {Name = "GREEN",   Color = Color3.fromRGB(65, 225, 125)},
    {Name = "LIME",    Color = Color3.fromRGB(175, 255, 65)},
    {Name = "YELLOW",  Color = Color3.fromRGB(255, 220, 65)},
    {Name = "ORANGE",  Color = Color3.fromRGB(255, 145, 55)},

    {Name = "RED",     Color = Color3.fromRGB(255, 70, 85)},
    {Name = "PINK",    Color = Color3.fromRGB(255, 95, 185)},
    {Name = "PURPLE",  Color = Color3.fromRGB(165, 90, 255)},
    {Name = "WHITE",   Color = Color3.fromRGB(245, 248, 255)},
    {Name = "SILVER",  Color = Color3.fromRGB(165, 180, 200)},
    {Name = "AQUA",    Color = Color3.fromRGB(70, 255, 200)},

    {Name = "SKY",     Color = Color3.fromRGB(120, 205, 255)},
    {Name = "MINT",    Color = Color3.fromRGB(135, 255, 190)},
    {Name = "GOLD",    Color = Color3.fromRGB(255, 190, 45)},
    {Name = "CORAL",   Color = Color3.fromRGB(255, 105, 90)},
    {Name = "VIOLET",  Color = Color3.fromRGB(205, 100, 255)},
    {Name = "ICE",     Color = Color3.fromRGB(195, 235, 255)},
}

local selectedESPColorButton = nil

local function UpdateESPColorButtonAccent()
    for _, obj in ipairs(ESPColorBtn:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Text == "◈" then
            obj.TextColor3 = espColor
        end
    end
end

for index, entry in ipairs(paletteColors) do
    local swatch = Instance.new("TextButton")
    swatch.Name = "Color_" .. entry.Name
    swatch.LayoutOrder = index
    swatch.BackgroundColor3 = entry.Color
    swatch.BorderSizePixel = 0
    swatch.Text = ""
    swatch.AutoButtonColor = false
    swatch.ZIndex = 122
    swatch.Parent = ESPPalette
    Corner(swatch, 9)

    local swatchStroke = Instance.new("UIStroke")
    swatchStroke.Color = Color3.fromRGB(235, 243, 252)
    swatchStroke.Thickness = 1
    swatchStroke.Transparency = 0.72
    swatchStroke.Parent = swatch

    local check = Instance.new("TextLabel")
    check.Name = "Selected"
    check.Size = UDim2.new(1, 0, 1, 0)
    check.BackgroundTransparency = 1
    check.Text = "✓"
    check.TextColor3 = Color3.fromRGB(255, 255, 255)
    check.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    check.TextStrokeTransparency = 0.15
    check.TextSize = 22
    check.Font = Enum.Font.GothamBold
    check.Visible = false
    check.ZIndex = 123
    check.Parent = swatch

    swatch.MouseButton1Click:Connect(function()
        if selectedESPColorButton then
            local oldCheck = selectedESPColorButton:FindFirstChild("Selected")
            if oldCheck then oldCheck.Visible = false end
        end

        selectedESPColorButton = swatch
        check.Visible = true

        ApplyESPColor(entry.Color)
        UpdateESPColorButtonAccent()

        task.delay(0.15, function()
            if ESPColorFrame and ESPColorFrame.Parent then
                ESPColorFrame.Visible = false
                espColorPromptOpen = false
            end
        end)
    end)
end

local ESPColorHint = Text(
    ESPColorFrame,
    "Click any color to apply it instantly",
    UDim2.new(1, -36, 0, 24),
    UDim2.new(0, 18, 1, -38),
    Enum.Font.GothamMedium,
    9,
    T.Muted,
    Enum.TextXAlignment.Center
)
ESPColorHint.ZIndex = 121

local function OpenESPColorPicker()
    espColorPromptOpen = true
    ESPColorFrame.Visible = true
end

local function CloseESPColorPicker()
    espColorPromptOpen = false
    ESPColorFrame.Visible = false
end

ESPColorClose.MouseButton1Click:Connect(CloseESPColorPicker)


-- PROFILES PANEL
local ProfilesFrame = Instance.new("Frame")
ProfilesFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ProfilesFrame.Size = UDim2.new(0, 500, 0, 430)
ProfilesFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
ProfilesFrame.BackgroundColor3 = T.Black
ProfilesFrame.BorderSizePixel = 0
ProfilesFrame.Visible = false
ProfilesFrame.ZIndex = 110
ProfilesFrame.Parent = ScreenGui
Corner(ProfilesFrame, 14)
Stroke(ProfilesFrame, T.Border, 0.03)

local ProfilesTitle = Text(
    ProfilesFrame, "PROFILES",
    UDim2.new(0, 250, 0, 28), UDim2.new(0, 18, 0, 14),
    Enum.Font.GothamBold, 16, T.Text
)
ProfilesTitle.ZIndex = 111

local ProfilesSub = Text(
    ProfilesFrame, "Save ESP, movement and utility settings",
    UDim2.new(0, 350, 0, 18), UDim2.new(0, 18, 0, 42),
    Enum.Font.Gotham, 9, T.Muted
)
ProfilesSub.ZIndex = 111

local ProfilesClose = Instance.new("TextButton")
ProfilesClose.Size = UDim2.new(0, 32, 0, 32)
ProfilesClose.Position = UDim2.new(1, -46, 0, 16)
ProfilesClose.BackgroundColor3 = T.Navy
ProfilesClose.BorderSizePixel = 0
ProfilesClose.Text = "×"
ProfilesClose.TextColor3 = T.Muted
ProfilesClose.TextSize = 18
ProfilesClose.Font = Enum.Font.GothamBold
ProfilesClose.ZIndex = 112
ProfilesClose.Parent = ProfilesFrame
Corner(ProfilesClose, 8)

local ProfileNameBox = Instance.new("TextBox")
ProfileNameBox.Size = UDim2.new(0, 300, 0, 36)
ProfileNameBox.Position = UDim2.new(0, 18, 0, 72)
ProfileNameBox.BackgroundColor3 = T.Navy
ProfileNameBox.BorderSizePixel = 0
ProfileNameBox.PlaceholderText = "Profile name..."
ProfileNameBox.PlaceholderColor3 = T.Muted
ProfileNameBox.Text = ""
ProfileNameBox.TextColor3 = T.Text
ProfileNameBox.TextSize = 11
ProfileNameBox.Font = Enum.Font.GothamMedium
ProfileNameBox.ClearTextOnFocus = false
ProfileNameBox.ZIndex = 111
ProfileNameBox.Parent = ProfilesFrame
Corner(ProfileNameBox, 8)
Stroke(ProfileNameBox, T.Border, 0.18)

local SaveProfileBtn = Instance.new("TextButton")
SaveProfileBtn.Size = UDim2.new(0, 146, 0, 36)
SaveProfileBtn.Position = UDim2.new(1, -164, 0, 72)
SaveProfileBtn.BackgroundColor3 = Color3.fromRGB(18, 59, 96)
SaveProfileBtn.BorderSizePixel = 0
SaveProfileBtn.Text = "SAVE PROFILE"
SaveProfileBtn.TextColor3 = T.Text
SaveProfileBtn.TextSize = 9
SaveProfileBtn.Font = Enum.Font.GothamBold
SaveProfileBtn.ZIndex = 111
SaveProfileBtn.Parent = ProfilesFrame
Corner(SaveProfileBtn, 8)

local ProfilesScroll = Instance.new("ScrollingFrame")
ProfilesScroll.Size = UDim2.new(1, -36, 1, -132)
ProfilesScroll.Position = UDim2.new(0, 18, 0, 120)
ProfilesScroll.BackgroundTransparency = 1
ProfilesScroll.BorderSizePixel = 0
ProfilesScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
ProfilesScroll.ScrollBarThickness = 3
ProfilesScroll.ScrollBarImageColor3 = Color3.fromRGB(57, 86, 116)
ProfilesScroll.ZIndex = 111
ProfilesScroll.Parent = ProfilesFrame

local function UpdateProfilesList()
    for _, child in ipairs(ProfilesScroll:GetChildren()) do
        child:Destroy()
    end

    local names = {}
    for name in pairs(savedProfiles) do table.insert(names, name) end
    table.sort(names)

    if #names == 0 then
        local empty = Text(
            ProfilesScroll, "NO SAVED PROFILES",
            UDim2.new(1, 0, 0, 50), UDim2.new(0, 0, 0, 10),
            Enum.Font.GothamBold, 11, T.Muted, Enum.TextXAlignment.Center
        )
        empty.ZIndex = 112
        ProfilesScroll.CanvasSize = UDim2.new(0, 0, 0, 70)
        return
    end

    local y = 4

    for _, name in ipairs(names) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 54)
        row.Position = UDim2.new(0, 3, 0, y)
        row.BackgroundColor3 = T.Navy
        row.BorderSizePixel = 0
        row.ZIndex = 112
        row.Parent = ProfilesScroll
        Corner(row, 9)
        Stroke(row, T.Border, 0.24)

        local nameLabel = Text(
            row,
            name .. (activeProfileName == name and "  • ACTIVE" or ""),
            UDim2.new(1, -220, 0, 22), UDim2.new(0, 12, 0, 7),
            Enum.Font.GothamBold, 11,
            activeProfileName == name and T.Green or T.Text
        )
        nameLabel.ZIndex = 113

        local data = savedProfiles[name]
        local detailLabel = Text(
            row,
            string.format(
                "ESP %s  •  Speed %s  •  Fly %s",
                data.ESPEnabled == true and "ON" or "OFF",
                tostring(data.WalkSpeed or 16),
                tostring(data.FlySpeed or 55)
            ),
            UDim2.new(1, -220, 0, 18), UDim2.new(0, 12, 0, 29),
            Enum.Font.Gotham, 8, T.Muted
        )
        detailLabel.ZIndex = 113

        local loadBtn = Instance.new("TextButton")
        loadBtn.Size = UDim2.new(0, 82, 0, 32)
        loadBtn.Position = UDim2.new(1, -186, 0.5, -16)
        loadBtn.BackgroundColor3 = Color3.fromRGB(18, 57, 91)
        loadBtn.BorderSizePixel = 0
        loadBtn.Text = "LOAD"
        loadBtn.TextColor3 = T.Text
        loadBtn.TextSize = 9
        loadBtn.Font = Enum.Font.GothamBold
        loadBtn.ZIndex = 113
        loadBtn.Parent = row
        Corner(loadBtn, 8)

        local deleteBtn = Instance.new("TextButton")
        deleteBtn.Size = UDim2.new(0, 82, 0, 32)
        deleteBtn.Position = UDim2.new(1, -94, 0.5, -16)
        deleteBtn.BackgroundColor3 = Color3.fromRGB(54, 22, 29)
        deleteBtn.BorderSizePixel = 0
        deleteBtn.Text = "DELETE"
        deleteBtn.TextColor3 = Color3.fromRGB(229, 139, 145)
        deleteBtn.TextSize = 9
        deleteBtn.Font = Enum.Font.GothamBold
        deleteBtn.ZIndex = 113
        deleteBtn.Parent = row
        Corner(deleteBtn, 8)

        loadBtn.MouseButton1Click:Connect(function()
            if ApplyProfile(name) then UpdateProfilesList() end
        end)

        deleteBtn.MouseButton1Click:Connect(function()
            DeleteProfile(name)
            UpdateProfilesList()
        end)

        y += 60
    end

    ProfilesScroll.CanvasSize = UDim2.new(0, 0, 0, y + 8)
end

SaveProfileBtn.MouseButton1Click:Connect(function()
    local name = SanitizeProfileName(ProfileNameBox.Text)

    if not name then
        SaveProfileBtn.Text = "ENTER NAME"
        task.delay(0.7, function()
            if SaveProfileBtn and SaveProfileBtn.Parent then
                SaveProfileBtn.Text = "SAVE PROFILE"
            end
        end)
        return
    end

    if SaveProfile(name) then
        ProfileNameBox.Text = ""
        SaveProfileBtn.Text = "SAVED"
        UpdateProfilesList()

        task.delay(0.5, function()
            if SaveProfileBtn and SaveProfileBtn.Parent then
                SaveProfileBtn.Text = "SAVE PROFILE"
            end
        end)
    end
end)

ProfilesClose.MouseButton1Click:Connect(function()
    ProfilesFrame.Visible = false
    MenuOpen = true
    MainMenu.Visible = true
end)

-- Dragging
do
    local dragging = false
    local dragStart
    local startPos
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainMenu.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            MainMenu.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

MinBtn.MouseButton1Click:Connect(function()
    MenuOpen = false
    MainMenu.Visible = false
end)

HeaderClose.MouseButton1Click:Connect(function()
    MenuOpen = false
    MainMenu.Visible = false
end)


-- ============================================
-- LOCATION NAME PROMPT
-- ============================================

local NamePrompt = Instance.new("Frame")
NamePrompt.AnchorPoint = Vector2.new(0.5, 0.5)
NamePrompt.Size = UDim2.new(0, 380, 0, 180)
NamePrompt.Position = UDim2.new(0.5, 0, 0.5, 0)
NamePrompt.BackgroundColor3 = T.Black
NamePrompt.BorderSizePixel = 0
NamePrompt.Visible = false
NamePrompt.ZIndex = 100
NamePrompt.Parent = ScreenGui
Corner(NamePrompt, 14)
Stroke(NamePrompt, T.Border, 0.02)

Text(NamePrompt, "SAVE LOCATION", UDim2.new(1, -30, 0, 28), UDim2.new(0, 18, 0, 14), Enum.Font.GothamBold, 16, T.Text)
Text(NamePrompt, "Enter a name for this position", UDim2.new(1, -30, 0, 18), UDim2.new(0, 18, 0, 41), Enum.Font.Gotham, 9, T.Muted)

local NameBox = Instance.new("TextBox")
NameBox.Size = UDim2.new(1, -36, 0, 42)
NameBox.Position = UDim2.new(0, 18, 0, 72)
NameBox.BackgroundColor3 = T.Navy
NameBox.BorderSizePixel = 0
NameBox.PlaceholderText = "Example: Stage 12"
NameBox.PlaceholderColor3 = Color3.fromRGB(90, 108, 129)
NameBox.Text = ""
NameBox.TextColor3 = T.Text
NameBox.TextSize = 13
NameBox.Font = Enum.Font.GothamMedium
NameBox.ClearTextOnFocus = false
NameBox.Parent = NamePrompt
Corner(NameBox, 9)
Stroke(NameBox, T.Border, 0.15)

local PromptCancel = Instance.new("TextButton")
PromptCancel.Size = UDim2.new(0, 104, 0, 34)
PromptCancel.Position = UDim2.new(1, -226, 1, -48)
PromptCancel.BackgroundColor3 = T.Navy
PromptCancel.BorderSizePixel = 0
PromptCancel.Text = "CANCEL"
PromptCancel.TextColor3 = T.Muted
PromptCancel.TextSize = 10
PromptCancel.Font = Enum.Font.GothamBold
PromptCancel.Parent = NamePrompt
Corner(PromptCancel, 8)

local PromptSave = Instance.new("TextButton")
PromptSave.Size = UDim2.new(0, 104, 0, 34)
PromptSave.Position = UDim2.new(1, -116, 1, -48)
PromptSave.BackgroundColor3 = Color3.fromRGB(19, 62, 101)
PromptSave.BorderSizePixel = 0
PromptSave.Text = "SAVE"
PromptSave.TextColor3 = T.Text
PromptSave.TextSize = 10
PromptSave.Font = Enum.Font.GothamBold
PromptSave.Parent = NamePrompt
Corner(PromptSave, 8)

for _, obj in ipairs(NamePrompt:GetDescendants()) do
    if obj:IsA("GuiObject") then
        obj.ZIndex = 101
    end
end

local function OpenLocationNamePrompt()
    local root = GetRoot()
    if not root then
        warn("VANTAGE: Cannot save location - HumanoidRootPart not found.")
        return
    end

    pendingSavedCFrame = root.CFrame

    if locationNamePromptOpen then
        NamePrompt.Visible = true
        NameBox:CaptureFocus()
        return
    end

    locationNamePromptOpen = true
    NameBox.Text = ""
    NamePrompt.Visible = true
    NameBox:CaptureFocus()
end

local function CloseLocationNamePrompt()
    locationNamePromptOpen = false
    pendingSavedCFrame = nil
    NamePrompt.Visible = false
    NameBox:ReleaseFocus()
end

PromptCancel.MouseButton1Click:Connect(CloseLocationNamePrompt)

local function SubmitLocationName()
    local name = SanitizeLocationName(NameBox.Text)

    if not name then
        NameBox.PlaceholderText = "Enter a valid name"
        return
    end

    local saved = SaveCurrentLocation(name, pendingSavedCFrame)

    if saved then
        PromptSave.Text = "SAVED"
        PromptSave.TextColor3 = T.Green

        if UpdateLocationsList then
            UpdateLocationsList()
        end

        task.wait(0.15)
        CloseLocationNamePrompt()

        task.delay(0.3, function()
            if PromptSave and PromptSave.Parent then
                PromptSave.Text = "SAVE"
                PromptSave.TextColor3 = T.Text
            end
        end)
    else
        PromptSave.Text = "FAILED"
        PromptSave.TextColor3 = T.Red

        task.delay(0.8, function()
            if PromptSave and PromptSave.Parent then
                PromptSave.Text = "SAVE"
                PromptSave.TextColor3 = T.Text
            end
        end)
    end
end

PromptSave.MouseButton1Click:Connect(SubmitLocationName)
NameBox.FocusLost:Connect(function(enterPressed)
    if enterPressed and locationNamePromptOpen then
        SubmitLocationName()
    end
end)

-- ============================================
-- LOCATIONS PANEL
-- ============================================

local LocationsFrame = Instance.new("Frame")
LocationsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
LocationsFrame.Size = UDim2.new(0, 620, 0, 410)
LocationsFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
LocationsFrame.BackgroundColor3 = T.Black
LocationsFrame.BorderSizePixel = 0
LocationsFrame.Visible = false
LocationsFrame.ZIndex = 30
LocationsFrame.Parent = ScreenGui
Corner(LocationsFrame, 14)
Stroke(LocationsFrame, T.Border, 0.05)

Text(LocationsFrame, "SAVED LOCATIONS", UDim2.new(0, 280, 0, 25), UDim2.new(0, 18, 0, 12), Enum.Font.GothamBold, 16, T.Text)
Text(LocationsFrame, "F10 saves your exact position", UDim2.new(0, 300, 0, 18), UDim2.new(0, 18, 0, 36), Enum.Font.Gotham, 9, T.Muted)

local LocationsClose = Instance.new("TextButton")
LocationsClose.Size = UDim2.new(0, 32, 0, 32)
LocationsClose.Position = UDim2.new(1, -46, 0, 16)
LocationsClose.BackgroundColor3 = T.Navy
LocationsClose.BorderSizePixel = 0
LocationsClose.Text = "×"
LocationsClose.TextColor3 = T.Muted
LocationsClose.TextSize = 18
LocationsClose.Font = Enum.Font.GothamBold
LocationsClose.Parent = LocationsFrame
Corner(LocationsClose, 8)

local LocationsScroll = Instance.new("ScrollingFrame")
LocationsScroll.Size = UDim2.new(1, -24, 1, -80)
LocationsScroll.Position = UDim2.new(0, 12, 0, 66)
LocationsScroll.BackgroundTransparency = 1
LocationsScroll.BorderSizePixel = 0
LocationsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
LocationsScroll.ScrollBarThickness = 3
LocationsScroll.ScrollBarImageColor3 = Color3.fromRGB(57, 86, 116)
LocationsScroll.Parent = LocationsFrame

function UpdateLocationsList()
    for _, child in ipairs(LocationsScroll:GetChildren()) do
        child:Destroy()
    end

    local names = {}
    for name in pairs(savedLocations) do table.insert(names, name) end
    table.sort(names)

    if #names == 0 then
        Text(LocationsScroll, "NO SAVED LOCATIONS", UDim2.new(1, 0, 0, 50), UDim2.new(0,0,0,10), Enum.Font.GothamBold, 11, T.Muted, Enum.TextXAlignment.Center)
        LocationsScroll.CanvasSize = UDim2.new(0,0,0,70)
        return
    end

    local y = 4
    for _, name in ipairs(names) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 54)
        row.Position = UDim2.new(0, 3, 0, y)
        row.BackgroundColor3 = T.Navy
        row.BorderSizePixel = 0
        row.Parent = LocationsScroll
        Corner(row, 10)
        Stroke(row, T.Border, 0.25)

        Text(row, name, UDim2.new(0, 250, 0, 20), UDim2.new(0, 14, 0, 8), Enum.Font.GothamBold, 11, T.Text)
        local d = savedLocations[name]
        Text(row, string.format("%.1f, %.1f, %.1f", tonumber(d.X) or 0, tonumber(d.Y) or 0, tonumber(d.Z) or 0),
            UDim2.new(0, 250, 0, 16), UDim2.new(0, 14, 0, 29), Enum.Font.Gotham, 8, T.Muted)

        local tp = Instance.new("TextButton")
        tp.Size = UDim2.new(0, 74, 0, 32)
        tp.Position = UDim2.new(1, -250, 0.5, -16)
        tp.BackgroundColor3 = Color3.fromRGB(18, 57, 91)
        tp.BorderSizePixel = 0
        tp.Text = "TELEPORT"
        tp.TextColor3 = T.Text
        tp.TextSize = 9
        tp.Font = Enum.Font.GothamBold
        tp.Parent = row
        Corner(tp, 8)

        local loop = Instance.new("TextButton")
        loop.Size = UDim2.new(0, 74, 0, 32)
        loop.Position = UDim2.new(1, -168, 0.5, -16)
        loop.BackgroundColor3 = Color3.fromRGB(13, 36, 59)
        loop.BorderSizePixel = 0
        loop.Text = (loopTeleporting and currentLoopLocation == name) and "STOP LOOP" or "LOOP TP"
        loop.TextColor3 = T.BlueSoft
        loop.TextSize = 9
        loop.Font = Enum.Font.GothamBold
        loop.Parent = row
        Corner(loop, 8)

        local del = Instance.new("TextButton")
        del.Size = UDim2.new(0, 74, 0, 32)
        del.Position = UDim2.new(1, -86, 0.5, -16)
        del.BackgroundColor3 = Color3.fromRGB(54, 22, 29)
        del.BorderSizePixel = 0
        del.Text = "DELETE"
        del.TextColor3 = Color3.fromRGB(229, 139, 145)
        del.TextSize = 9
        del.Font = Enum.Font.GothamBold
        del.Parent = row
        Corner(del, 8)

        tp.MouseButton1Click:Connect(function() TeleportToLocation(name) end)
        loop.MouseButton1Click:Connect(function()
            StartLoopTeleport(name)
            UpdateLocationsList()
        end)
        del.MouseButton1Click:Connect(function()
            DeleteLocation(name)
            UpdateLocationsList()
        end)

        y += 60
    end
    LocationsScroll.CanvasSize = UDim2.new(0,0,0,y + 8)
end

LocationsClose.MouseButton1Click:Connect(function()
    LocationsFrame.Visible = false
    MenuOpen = true
    MainMenu.Visible = true
end)

-- ============================================
-- MOVEMENT PANEL
-- ============================================

local MovementFrame = Instance.new("Frame")
MovementFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MovementFrame.Size = UDim2.new(0, 430, 0, 390)
MovementFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MovementFrame.BackgroundColor3 = T.Black
MovementFrame.BorderSizePixel = 0
MovementFrame.Visible = false
MovementFrame.ZIndex = 30
MovementFrame.Parent = ScreenGui
Corner(MovementFrame, 14)
Stroke(MovementFrame, T.Border, 0.05)

Text(MovementFrame, "MOVEMENT", UDim2.new(0, 240, 0, 25), UDim2.new(0, 18, 0, 12), Enum.Font.GothamBold, 16, T.Text)
Text(MovementFrame, "Speed and obby helpers", UDim2.new(0, 280, 0, 18), UDim2.new(0, 18, 0, 36), Enum.Font.Gotham, 9, T.Muted)

local MovementClose = Instance.new("TextButton")
MovementClose.Size = UDim2.new(0, 32, 0, 32)
MovementClose.Position = UDim2.new(1, -46, 0, 16)
MovementClose.BackgroundColor3 = T.Navy
MovementClose.BorderSizePixel = 0
MovementClose.Text = "×"
MovementClose.TextColor3 = T.Muted
MovementClose.TextSize = 18
MovementClose.Font = Enum.Font.GothamBold
MovementClose.Parent = MovementFrame
Corner(MovementClose, 8)

Text(MovementFrame, "WALK SPEED", UDim2.new(0, 130, 0, 20), UDim2.new(0, 18, 0, 78), Enum.Font.GothamBold, 10, T.Muted)
local SpeedValue = Text(MovementFrame, tostring(walkSpeedValue), UDim2.new(0, 70, 0, 32), UDim2.new(1, -88, 0, 72), Enum.Font.GothamBold, 16, T.BlueSoft, Enum.TextXAlignment.Right)

local function SpeedButton(textValue, x, value)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 82, 0, 36)
    b.Position = UDim2.new(0, x, 0, 108)
    b.BackgroundColor3 = T.Navy
    b.BorderSizePixel = 0
    b.Text = textValue
    b.TextColor3 = T.Text
    b.TextSize = 11
    b.Font = Enum.Font.GothamBold
    b.Parent = MovementFrame
    Corner(b, 8)
    b.MouseButton1Click:Connect(function()
        SetWalkSpeed(value)
        SpeedValue.Text = tostring(walkSpeedValue)
    end)
end

SpeedButton("16", 18, 16)
SpeedButton("24", 106, 24)
SpeedButton("32", 194, 32)
SpeedButton("50", 282, 50)

local MinusSpeed = Instance.new("TextButton")
MinusSpeed.Size = UDim2.new(0, 82, 0, 36)
MinusSpeed.Position = UDim2.new(0, 18, 0, 152)
MinusSpeed.BackgroundColor3 = T.Navy
MinusSpeed.BorderSizePixel = 0
MinusSpeed.Text = "- 4"
MinusSpeed.TextColor3 = T.Muted
MinusSpeed.TextSize = 11
MinusSpeed.Font = Enum.Font.GothamBold
MinusSpeed.Parent = MovementFrame
Corner(MinusSpeed, 8)

local PlusSpeed = Instance.new("TextButton")
PlusSpeed.Size = UDim2.new(0, 82, 0, 36)
PlusSpeed.Position = UDim2.new(0, 106, 0, 152)
PlusSpeed.BackgroundColor3 = T.Navy
PlusSpeed.BorderSizePixel = 0
PlusSpeed.Text = "+ 4"
PlusSpeed.TextColor3 = T.BlueSoft
PlusSpeed.TextSize = 11
PlusSpeed.Font = Enum.Font.GothamBold
PlusSpeed.Parent = MovementFrame
Corner(PlusSpeed, 8)

MinusSpeed.MouseButton1Click:Connect(function()
    SetWalkSpeed(walkSpeedValue - 4)
    SpeedValue.Text = tostring(walkSpeedValue)
end)

PlusSpeed.MouseButton1Click:Connect(function()
    SetWalkSpeed(walkSpeedValue + 4)
    SpeedValue.Text = tostring(walkSpeedValue)
end)

local AntiFallBtn = Instance.new("TextButton")
AntiFallBtn.Size = UDim2.new(0, 170, 0, 42)
AntiFallBtn.Position = UDim2.new(0, 18, 0, 208)
AntiFallBtn.BackgroundColor3 = T.Navy
AntiFallBtn.BorderSizePixel = 0
AntiFallBtn.Text = "ANTI-FALL: OFF"
AntiFallBtn.TextColor3 = T.Muted
AntiFallBtn.TextSize = 10
AntiFallBtn.Font = Enum.Font.GothamBold
AntiFallBtn.Parent = MovementFrame
Corner(AntiFallBtn, 9)

local AutoReturnBtn = Instance.new("TextButton")
AutoReturnBtn.Size = UDim2.new(0, 170, 0, 42)
AutoReturnBtn.Position = UDim2.new(0, 200, 0, 208)
AutoReturnBtn.BackgroundColor3 = T.Navy
AutoReturnBtn.BorderSizePixel = 0
AutoReturnBtn.Text = "AUTO RETURN: OFF"
AutoReturnBtn.TextColor3 = T.Muted
AutoReturnBtn.TextSize = 10
AutoReturnBtn.Font = Enum.Font.GothamBold
AutoReturnBtn.Parent = MovementFrame
Corner(AutoReturnBtn, 9)

AntiFallBtn.MouseButton1Click:Connect(function()
    antiFallEnabled = not antiFallEnabled

    if antiFallEnabled then
        StartAntiFall()
    else
        StopAntiFall()
    end

    AntiFallBtn.Text = antiFallEnabled and "ANTI-FALL: ON" or "ANTI-FALL: OFF"
    AntiFallBtn.TextColor3 = antiFallEnabled and T.Green or T.Muted
end)

AutoReturnBtn.MouseButton1Click:Connect(function()
    autoReturnEnabled = not autoReturnEnabled
    AutoReturnBtn.Text = autoReturnEnabled and "AUTO RETURN: ON" or "AUTO RETURN: OFF"
    AutoReturnBtn.TextColor3 = autoReturnEnabled and T.Green or T.Muted
end)

Text(MovementFrame, "FLY", UDim2.new(0, 100, 0, 20), UDim2.new(0, 18, 0, 270), Enum.Font.GothamBold, 10, T.Muted)

local FlyBtn = Instance.new("TextButton")
FlyBtn.Size = UDim2.new(0, 170, 0, 42)
FlyBtn.Position = UDim2.new(0, 18, 0, 298)
FlyBtn.BackgroundColor3 = T.Navy
FlyBtn.BorderSizePixel = 0
FlyBtn.Text = "FLY: OFF"
FlyBtn.TextColor3 = T.Muted
FlyBtn.TextSize = 10
FlyBtn.Font = Enum.Font.GothamBold
FlyBtn.Parent = MovementFrame
Corner(FlyBtn, 9)
Stroke(FlyBtn, T.Border, 0.2)

local FlyMinus = Instance.new("TextButton")
FlyMinus.Size = UDim2.new(0, 42, 0, 42)
FlyMinus.Position = UDim2.new(0, 200, 0, 298)
FlyMinus.BackgroundColor3 = T.Navy
FlyMinus.BorderSizePixel = 0
FlyMinus.Text = "-"
FlyMinus.TextColor3 = T.Muted
FlyMinus.TextSize = 16
FlyMinus.Font = Enum.Font.GothamBold
FlyMinus.Parent = MovementFrame
Corner(FlyMinus, 9)

local FlySpeedText = Text(
    MovementFrame,
    tostring(flySpeed),
    UDim2.new(0, 70, 0, 42),
    UDim2.new(0, 248, 0, 298),
    Enum.Font.GothamBold,
    13,
    T.BlueSoft,
    Enum.TextXAlignment.Center
)

local FlyPlus = Instance.new("TextButton")
FlyPlus.Size = UDim2.new(0, 42, 0, 42)
FlyPlus.Position = UDim2.new(0, 326, 0, 298)
FlyPlus.BackgroundColor3 = T.Navy
FlyPlus.BorderSizePixel = 0
FlyPlus.Text = "+"
FlyPlus.TextColor3 = T.BlueSoft
FlyPlus.TextSize = 16
FlyPlus.Font = Enum.Font.GothamBold
FlyPlus.Parent = MovementFrame
Corner(FlyPlus, 9)

FlyBtn.MouseButton1Click:Connect(function()
    StartFly()
    FlyBtn.Text = flying and "FLY: ON" or "FLY: OFF"
    FlyBtn.TextColor3 = flying and T.Green or T.Muted
end)

FlyMinus.MouseButton1Click:Connect(function()
    flySpeed = math.clamp(flySpeed - 10, 20, 200)
    FlySpeedText.Text = tostring(flySpeed)
end)

FlyPlus.MouseButton1Click:Connect(function()
    flySpeed = math.clamp(flySpeed + 10, 20, 200)
    FlySpeedText.Text = tostring(flySpeed)
end)

Text(
    MovementFrame,
    "WASD = move   SPACE = up   LEFT CTRL = down",
    UDim2.new(1, -36, 0, 18),
    UDim2.new(0, 18, 0, 350),
    Enum.Font.Gotham,
    9,
    T.Muted
)

MovementClose.MouseButton1Click:Connect(function()
    MovementFrame.Visible = false
    MenuOpen = true
    MainMenu.Visible = true
end)


-- ============================================
-- PLAYER LIST
-- ============================================

local PlayersFrame = Instance.new("Frame")
PlayersFrame.Name = "PlayerList"
PlayersFrame.AnchorPoint = Vector2.new(0.5, 0.5)
PlayersFrame.Size = UDim2.new(0, 650, 0, 440)
PlayersFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
PlayersFrame.BackgroundColor3 = T.Black
PlayersFrame.BorderSizePixel = 0
PlayersFrame.Visible = false
PlayersFrame.ZIndex = 30
PlayersFrame.Parent = ScreenGui
Corner(PlayersFrame, 14)
Stroke(PlayersFrame, T.Border, 0.05)

Text(PlayersFrame, "PLAYER LIST", UDim2.new(0, 250, 0, 25), UDim2.new(0, 18, 0, 12), Enum.Font.GothamBold, 16, T.Text)
local PlayerCountText = Text(PlayersFrame, "", UDim2.new(0, 260, 0, 18), UDim2.new(0, 18, 0, 36), Enum.Font.Gotham, 9, T.Muted)

local PlayersClose = Instance.new("TextButton")
PlayersClose.Size = UDim2.new(0, 32, 0, 32)
PlayersClose.Position = UDim2.new(1, -46, 0, 16)
PlayersClose.BackgroundColor3 = T.Navy
PlayersClose.BorderSizePixel = 0
PlayersClose.Text = "×"
PlayersClose.TextColor3 = T.Muted
PlayersClose.TextSize = 18
PlayersClose.Font = Enum.Font.GothamBold
PlayersClose.Parent = PlayersFrame
Corner(PlayersClose, 8)

local StopSpectateBtn = Instance.new("TextButton")
StopSpectateBtn.Size = UDim2.new(0, 140, 0, 30)
StopSpectateBtn.Position = UDim2.new(1, -198, 0, 17)
StopSpectateBtn.BackgroundColor3 = Color3.fromRGB(10, 27, 45)
StopSpectateBtn.BorderSizePixel = 0
StopSpectateBtn.Text = "STOP SPECTATE"
StopSpectateBtn.TextColor3 = T.BlueSoft
StopSpectateBtn.TextSize = 9
StopSpectateBtn.Font = Enum.Font.GothamBold
StopSpectateBtn.Parent = PlayersFrame
Corner(StopSpectateBtn, 8)




local PlayerSearchBox = Instance.new("TextBox")
PlayerSearchBox.Size = UDim2.new(0, 230, 0, 32)
PlayerSearchBox.Position = UDim2.new(0, 18, 0, 62)
PlayerSearchBox.BackgroundColor3 = T.Navy
PlayerSearchBox.BorderSizePixel = 0
PlayerSearchBox.PlaceholderText = "Find player..."
PlayerSearchBox.PlaceholderColor3 = T.Muted
PlayerSearchBox.Text = ""
PlayerSearchBox.TextColor3 = T.Text
PlayerSearchBox.TextSize = 11
PlayerSearchBox.Font = Enum.Font.GothamMedium
PlayerSearchBox.ClearTextOnFocus = false
PlayerSearchBox.Parent = PlayersFrame
Corner(PlayerSearchBox, 8)
Stroke(PlayerSearchBox, T.Border, 0.18)

VantageProfileBridge.SetPlayerSearchQuery = function(value)
    playerSearchQuery = tostring(value or "")
    if PlayerSearchBox and PlayerSearchBox.Parent then
        PlayerSearchBox.Text = playerSearchQuery
    end
end

local ClearPlayerSearch = Instance.new("TextButton")
ClearPlayerSearch.Size = UDim2.new(0, 72, 0, 32)
ClearPlayerSearch.Position = UDim2.new(0, 256, 0, 62)
ClearPlayerSearch.BackgroundColor3 = T.Navy
ClearPlayerSearch.BorderSizePixel = 0
ClearPlayerSearch.Text = "CLEAR"
ClearPlayerSearch.TextColor3 = T.Muted
ClearPlayerSearch.TextSize = 9
ClearPlayerSearch.Font = Enum.Font.GothamBold
ClearPlayerSearch.Parent = PlayersFrame
Corner(ClearPlayerSearch, 8)

local PlayersScroll = Instance.new("ScrollingFrame")
PlayersScroll.Size = UDim2.new(1, -24, 1, -116)
PlayersScroll.Position = UDim2.new(0, 12, 0, 104)
PlayersScroll.BackgroundTransparency = 1
PlayersScroll.BorderSizePixel = 0
PlayersScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayersScroll.ScrollBarThickness = 3
PlayersScroll.ScrollBarImageColor3 = Color3.fromRGB(57, 86, 116)
PlayersScroll.Parent = PlayersFrame

local function UpdatePlayerList()
    for _, child in ipairs(PlayersScroll:GetChildren()) do
        child:Destroy()
    end

    local allPlayers = Players:GetPlayers()
    table.sort(allPlayers, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)

    local query = string.lower(playerSearchQuery or "")
    local list = {}

    for _, player in ipairs(allPlayers) do
        local displayName = string.lower(player.DisplayName or "")
        local username = string.lower(player.Name or "")

        if query == ""
            or string.find(displayName, query, 1, true)
            or string.find(username, query, 1, true) then
            table.insert(list, player)
        end
    end

    if query == "" then
        PlayerCountText.Text = tostring(#allPlayers) .. " players in this server"
    else
        PlayerCountText.Text = tostring(#list) .. " found • " .. tostring(#allPlayers) .. " total"
    end

    local y = 4
    for _, player in ipairs(list) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 58)
        row.Position = UDim2.new(0, 3, 0, y)
        row.BackgroundColor3 = T.Navy
        row.BorderSizePixel = 0
        row.Parent = PlayersScroll
        Corner(row, 10)
        Stroke(row, T.Border, 0.25)

        local shownName = player.DisplayName
        if player.DisplayName ~= player.Name then
            shownName = player.DisplayName .. "  @" .. player.Name
        end

        Text(row, shownName, UDim2.new(0, 310, 0, 22), UDim2.new(0, 14, 0, 8), Enum.Font.GothamBold, 11, player == LocalPlayer and T.Green or T.Text)

        local stateText = player == LocalPlayer and "YOU" or "PLAYER"
        if spectatingPlayer == player then stateText = "SPECTATING" end
        Text(row, stateText, UDim2.new(0, 180, 0, 17), UDim2.new(0, 14, 0, 32), Enum.Font.Gotham, 8, spectatingPlayer == player and T.BlueSoft or T.Muted)

        local tp = Instance.new("TextButton")
        tp.Size = UDim2.new(0, 92, 0, 34)
        tp.Position = UDim2.new(1, -206, 0.5, -17)
        tp.BackgroundColor3 = Color3.fromRGB(17, 53, 84)
        tp.BorderSizePixel = 0
        tp.Text = player == LocalPlayer and "YOU" or "TELEPORT"
        tp.TextColor3 = player == LocalPlayer and T.Muted or T.Text
        tp.TextSize = 9
        tp.Font = Enum.Font.GothamBold
        tp.Parent = row
        Corner(tp, 8)

        local sp = Instance.new("TextButton")
        sp.Size = UDim2.new(0, 92, 0, 34)
        sp.Position = UDim2.new(1, -106, 0.5, -17)
        sp.BackgroundColor3 = Color3.fromRGB(11, 34, 56)
        sp.BorderSizePixel = 0
        sp.Text = player == LocalPlayer and "RESET CAM" or (spectatingPlayer == player and "WATCHING" or "SPECTATE")
        sp.TextColor3 = T.BlueSoft
        sp.TextSize = 9
        sp.Font = Enum.Font.GothamBold
        sp.Parent = row
        Corner(sp, 8)

        tp.MouseButton1Click:Connect(function()
            if player ~= LocalPlayer then
                TeleportToPlayer(player)
            end
        end)

        sp.MouseButton1Click:Connect(function()
            if player == LocalPlayer or spectatingPlayer == player then
                StopSpectate()
            else
                StartSpectate(player)
            end
            UpdatePlayerList()
        end)

        y += 64
    end

    PlayersScroll.CanvasSize = UDim2.new(0, 0, 0, y + 8)
end


PlayerSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    playerSearchQuery = PlayerSearchBox.Text or ""
    UpdatePlayerList()
end)

ClearPlayerSearch.MouseButton1Click:Connect(function()
    PlayerSearchBox.Text = ""
    playerSearchQuery = ""
    UpdatePlayerList()
end)

PlayersClose.MouseButton1Click:Connect(function()
    PlayersFrame.Visible = false
    MenuOpen = true
    MainMenu.Visible = true
end)

StopSpectateBtn.MouseButton1Click:Connect(function()
    StopSpectate()
    UpdatePlayerList()
end)

Players.PlayerAdded:Connect(function(player)
    UpdateServerCounter()
    AttachESPCharacterWatcher(player)

    if espEnabled and player.Character then
        task.defer(function()
            CreateESP(player)
        end)
    end

    if PlayersFrame.Visible then
        UpdatePlayerList()
    end
end)

Players.PlayerRemoving:Connect(function(player)
    task.defer(UpdateServerCounter)
    if spectatingPlayer == player then
        StopSpectate()
    end

    RemoveESP(player)
    DetachESPCharacterWatcher(player)

    if PlayersFrame.Visible then
        task.defer(UpdatePlayerList)
    end
end)

-- ============================================
-- RECORDING LIBRARY - CLEAN TABLE VIEW
-- ============================================

local ListFrame = Instance.new("Frame")
ListFrame.Name = "RecordingLibrary"
ListFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ListFrame.Size = UDim2.new(0, 620, 0, 390)
ListFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
ListFrame.BackgroundColor3 = T.Black
ListFrame.BorderSizePixel = 0
ListFrame.Visible = false
ListFrame.Parent = ScreenGui
Corner(ListFrame, 14)
Stroke(ListFrame, T.Border, 0.05)

local ListHeader = Instance.new("Frame")
ListHeader.Size = UDim2.new(1, 0, 0, 66)
ListHeader.BackgroundColor3 = Color3.fromRGB(6, 12, 21)
ListHeader.BorderSizePixel = 0
ListHeader.Parent = ListFrame
Corner(ListHeader, 14)

Text(ListHeader, "RECORDINGS", UDim2.new(0, 260, 0, 24), UDim2.new(0, 18, 0, 11), Enum.Font.GothamBold, 16, T.Text)
Text(ListHeader, "Your saved movement library", UDim2.new(0, 300, 0, 18), UDim2.new(0, 18, 0, 34), Enum.Font.Gotham, 9, T.Muted)

local ListClose = Instance.new("TextButton")
ListClose.Size = UDim2.new(0, 32, 0, 32)
ListClose.Position = UDim2.new(1, -46, 0, 17)
ListClose.BackgroundColor3 = T.Navy
ListClose.BorderSizePixel = 0
ListClose.Text = "×"
ListClose.TextColor3 = T.Muted
ListClose.TextSize = 18
ListClose.Font = Enum.Font.GothamBold
ListClose.Parent = ListHeader
Corner(ListClose, 8)
Stroke(ListClose, T.Border, 0.2)
Hover(ListClose, T.Navy, Color3.fromRGB(37, 18, 25))

ListClose.MouseButton1Click:Connect(function()
    ListFrame.Visible = false
end)

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, -24, 1, -82)
ScrollFrame.Position = UDim2.new(0, 12, 0, 72)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.ScrollBarThickness = 3
ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(57, 86, 116)
ScrollFrame.Parent = ListFrame

-- ============================================

-- UPDATE LIST

-- ============================================

function UpdateList()

    for _, child in pairs(ScrollFrame:GetChildren()) do

        if child:IsA("Frame") then

            child:Destroy()

        end

    end

    local yOffset = 5

    local names = {}

    for name, _ in pairs(recordingsList) do

        table.insert(names, name)

    end

    table.sort(names)

    if #names == 0 then

        local empty = Instance.new("TextLabel")

        empty.Size = UDim2.new(1, 0, 0, 40)

        empty.Position = UDim2.new(0, 0, 0, 10)

        empty.BackgroundTransparency = 1

        empty.Text = "NO RECORDINGS FOUND"

        empty.TextColor3 = Color3.fromRGB(200, 200, 200)

        empty.TextSize = 14

        empty.Font = Enum.Font.GothamBold

        empty.Parent = ScrollFrame

        return

    end

    for _, name in ipairs(names) do

        local data = recordingsList[name]

        local moveCount = data and #data.Movements or 0

        local btn = Instance.new("Frame")

        btn.Size = UDim2.new(1, -10, 0, 42)

        btn.Position = UDim2.new(0, 5, 0, yOffset)

        btn.BackgroundColor3 = Color3.fromRGB(9, 17, 29)

        btn.BackgroundTransparency = 0.1

        btn.BorderSizePixel = 1

        btn.BorderColor3 = Color3.fromRGB(30, 52, 78)

        btn.Parent = ScrollFrame

        local btnCorner = Instance.new("UICorner")

        btnCorner.CornerRadius = UDim.new(0, 6)

        btnCorner.Parent = btn

        local nameLabel = Instance.new("TextLabel")

        nameLabel.Size = UDim2.new(0.45, 0, 1, 0)

        nameLabel.Position = UDim2.new(0, 8, 0, 0)

        nameLabel.BackgroundTransparency = 1

        nameLabel.Text = name .. " (" .. moveCount .. ")"

        nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)

        nameLabel.TextSize = 11

        nameLabel.TextXAlignment = Enum.TextXAlignment.Left

        nameLabel.Font = Enum.Font.GothamBold

        nameLabel.Parent = btn

        local playBtn = Instance.new("TextButton")

        playBtn.Size = UDim2.new(0, 40, 0, 28)

        playBtn.Position = UDim2.new(0.50, 2, 0, 7)

        playBtn.BackgroundColor3 = Color3.fromRGB(22, 74, 57)

        playBtn.BackgroundTransparency = 0.1

        playBtn.BorderSizePixel = 1

        playBtn.BorderColor3 = Color3.fromRGB(69, 198, 142)

        playBtn.Text = "PLAY"

        playBtn.TextColor3 = Color3.fromRGB(200, 255, 200)

        playBtn.TextSize = 9

        playBtn.Font = Enum.Font.GothamBold

        playBtn.Parent = btn

        local playCorner = Instance.new("UICorner")

        playCorner.CornerRadius = UDim.new(0, 4)

        playCorner.Parent = playBtn

        local loopBtn = Instance.new("TextButton")

        loopBtn.Size = UDim2.new(0, 35, 0, 28)

        loopBtn.Position = UDim2.new(0.68, 2, 0, 7)

        loopBtn.BackgroundColor3 = Color3.fromRGB(18, 42, 68)

        loopBtn.BackgroundTransparency = 0.1

        loopBtn.BorderSizePixel = 1

        loopBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

        loopBtn.Text = "LOOP"

        loopBtn.TextColor3 = Color3.fromRGB(170, 210, 250)

        loopBtn.TextSize = 9

        loopBtn.Font = Enum.Font.GothamBold

        loopBtn.Parent = btn

        local loopCorner = Instance.new("UICorner")

        loopCorner.CornerRadius = UDim.new(0, 4)

        loopCorner.Parent = loopBtn

        local delBtn = Instance.new("TextButton")

        delBtn.Size = UDim2.new(0, 30, 0, 28)

        delBtn.Position = UDim2.new(0.85, 2, 0, 7)

        delBtn.BackgroundColor3 = Color3.fromRGB(92, 30, 38)

        delBtn.BackgroundTransparency = 0.15

        delBtn.BorderSizePixel = 1

        delBtn.BorderColor3 = Color3.fromRGB(220, 76, 88)

        delBtn.Text = "✕"

        delBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

        delBtn.TextSize = 14

        delBtn.Font = Enum.Font.GothamBold

        delBtn.Parent = btn

        local delCorner = Instance.new("UICorner")

        delCorner.CornerRadius = UDim.new(0, 4)

        delCorner.Parent = delBtn

        playBtn.MouseButton1Click:Connect(function()

            ListFrame.Visible = false

            PlayRecording(name)

        end)

        loopBtn.MouseButton1Click:Connect(function()

            ListFrame.Visible = false

            StartLoopPlay(name)

        end)

        delBtn.MouseButton1Click:Connect(function()

            DeleteRecording(name)

        end)

        yOffset = yOffset + 48

    end

    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 10)

end

-- ============================================

-- RECORDING LOOP

-- ============================================

RunService.RenderStepped:Connect(function()

    if not recording then return end

    local char = LocalPlayer.Character

    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")

    if not root then return end

    local currentPos = root.Position

    local currentTime = tick()

    if lastPos and lastTime then

        local distance = (currentPos - lastPos).Magnitude

        if distance > 0.3 then

            table.insert(recordedData, {

                Position = {X = currentPos.X, Y = currentPos.Y, Z = currentPos.Z},

                Time = currentTime - lastTime

            })

            lastPos = currentPos

            lastTime = currentTime

        end

    else

        lastPos = currentPos

        lastTime = currentTime

    end

end)

-- ============================================

-- BUTTON EVENTS

-- ============================================

RecordBtn.MouseButton1Click:Connect(function()

    if recording then

        StopRecording()

    else

        StartRecording()

    end

end)

LoopBtn.MouseButton1Click:Connect(function()

    if loopPlaying then

        loopPlaying = false

        LoopBtn.Text = "↻ LOOP PLAYBACK"

        LoopBtn.BackgroundColor3 = Color3.fromRGB(7, 14, 25)

        LoopBtn.BorderColor3 = Color3.fromRGB(62, 142, 230)

        print("⏹️ تم إيقاف الLOOP")

    else

        UpdateList()

        ListFrame.Visible = true

        print("Select a recording from the library.")

    end

end)

StopBtn.MouseButton1Click:Connect(function()

    StopAllPlayback()

end)

ListBtn.MouseButton1Click:Connect(function()

    UpdateList()

    ListFrame.Visible = true

end)

LocationsBtn.MouseButton1Click:Connect(function()
    UpdateLocationsList()
    MenuOpen = false
    MainMenu.Visible = false
    LocationsFrame.Visible = true
end)

MovementBtn.MouseButton1Click:Connect(function()
    MenuOpen = false
    MainMenu.Visible = false
    MovementFrame.Visible = true
    SpeedValue.Text = tostring(walkSpeedValue)
end)

ProfilesBtn.MouseButton1Click:Connect(function()
    UpdateProfilesList()
    MenuOpen = false
    MainMenu.Visible = false
    ProfilesFrame.Visible = true
end)

PlayersBtn.MouseButton1Click:Connect(function()
    UpdatePlayerList()
    MenuOpen = false
    MainMenu.Visible = false
    PlayersFrame.Visible = true
end)

ESPMainBtn.MouseButton1Click:Connect(function()
    local targetState = not espEnabled

    local ok, err = pcall(function()
        SetESPEnabled(targetState)
    end)

    if not ok then
        espEnabled = false
        warn("VANTAGE ESP ERROR: " .. tostring(err))
    end

    local labels = ESPMainBtn:GetChildren()

    for _, obj in ipairs(labels) do
        if obj:IsA("TextLabel") and (obj.Text == "ESP: OFF" or obj.Text == "ESP: ON") then
            obj.Text = espEnabled and "ESP: ON" or "ESP: OFF"
            obj.TextColor3 = espEnabled and T.Green or T.Text
        end
    end
end)

ESPColorBtn.MouseButton1Click:Connect(function()
    OpenESPColorPicker()
end)

CloseBtn.MouseButton1Click:Connect(function()

    recording = false

    playing = false

    loopPlaying = false
    loopTeleporting = false
    StopAntiFall()
    StopFly()
    StopSpectate()

    MenuOpen = false

    print("VANTAGE Recorder closed completely.")

    SetESPEnabled(false)

    for player in pairs(espCharacterConnections) do
        DetachESPCharacterWatcher(player)
    end

    CloseESPColorPicker()
    StopPerformanceHUD()
    ScreenGui:Destroy()

end)

-- ============================================

-- KEYBOARD SHORTCUTS

-- ============================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.F10 and ScreenGui.Parent then
        OpenLocationNamePrompt()
        return
    end

    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.Insert and ScreenGui.Parent then
        MenuOpen = not MenuOpen
        MainMenu.Visible = MenuOpen
    end
end)


-- ============================================
-- MOVEMENT RUNTIME
-- ============================================

LocalPlayer.CharacterAdded:Connect(function(character)
    StopFly()

    local humanoid = character:WaitForChild("Humanoid", 10)
    local root = character:WaitForChild("HumanoidRootPart", 10)

    task.wait(0.25)
    ApplyWalkSpeed()

    if autoReturnEnabled and lastSafeLocationName and root then
        task.wait(0.45)
        TeleportToLocation(lastSafeLocationName)
    end
end)

-- Anti-fall now uses an on-demand connection instead of a permanent loop.

-- ============================================

-- STARTUP

-- ============================================

-- Load all saved recordings and locations

for _, player in ipairs(Players:GetPlayers()) do
    AttachESPCharacterWatcher(player)
end

LoadAllRecordings()
LoadLocationsFile()
LoadProfilesFile()
ApplyWalkSpeed()

print("========================================")

print("VANTAGE RECORDER - PERFORMANCE MODE")

print("========================================")

print("")

print("📌 CONTROLS:")

print("  Insert  = Show/Hide menu")
print("  F10     = Save current location")

print("  ● START RECORDING = Start/Stop recording")

print("  ↻ LOOP PLAYBACK = Open library / stop loop")

print("  📋 قائمة = Open recordings")

print("========================================")

print("💾 Recordings are saved automatically")

print("📂 Recordings persist after leaving the game")

print("========================================")

-- ============================================
-- VANTAGE AIM ADD-ON V2 (ISOLATED / STICKY LOCK)
-- Loaded only after the working base is fully running.
-- ============================================

local AimModuleLoaded, AimModuleError = pcall(function()
    local aimEnabled = false
    local aimHolding = false
    local aimFOVRadius = 150
    local aimSmoothness = 1.0
    local aimTargetPart = "Head"
    local lockedTarget = nil

    local aimInputBeganConnection = nil
    local aimInputEndedConnection = nil
    local AIM_BIND_NAME = "VantageAimLock"

    -- Preserve the working UI; only reposition existing cards after creation.
    MainMenu.Size = UDim2.new(0, 650, 0, 700)

    if ProfilesBtn and ProfilesBtn.Parent then
        ProfilesBtn.Position = UDim2.new(0, 0, 0, 412)
    end

    if CloseBtn and CloseBtn.Parent then
        CloseBtn.Position = UDim2.new(0, 0, 0, 476)
    end

    local AimBtn = ActionButton(
        "AimButton", 0, 348, 296, 54,
        "⊙", "AIM: OFF", "Hold RMB • sticky target lock",
        Color3.fromRGB(235, 95, 115)
    )

    local AimSettingsBtn = ActionButton(
        "AimSettingsButton", 306, 348, 296, 54,
        "◌", "AIM SETTINGS", "FOV • lock strength • target",
        Color3.fromRGB(157, 92, 244)
    )

    -- Dedicated overlay prevents GUI inset from shifting the FOV.
    local AimOverlay = Instance.new("ScreenGui")
    AimOverlay.Name = "VantageAimOverlay"
    AimOverlay.ResetOnSpawn = false
    AimOverlay.IgnoreGuiInset = true
    AimOverlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    AimOverlay.DisplayOrder = 50
    AimOverlay.Parent = LocalPlayer:WaitForChild("PlayerGui")

    local FOVCircle = Instance.new("Frame")
    FOVCircle.Name = "FOVCircle"
    FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    FOVCircle.Size = UDim2.new(0, aimFOVRadius * 2, 0, aimFOVRadius * 2)
    FOVCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    FOVCircle.BackgroundTransparency = 1
    FOVCircle.BorderSizePixel = 0
    FOVCircle.Visible = false
    FOVCircle.ZIndex = 10
    FOVCircle.Parent = AimOverlay

    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(1, 0)
    circleCorner.Parent = FOVCircle

    local circleStroke = Instance.new("UIStroke")
    circleStroke.Color = Color3.fromRGB(90, 185, 255)
    circleStroke.Thickness = 1.7
    circleStroke.Transparency = 0.05
    circleStroke.Parent = FOVCircle

    local centerDot = Instance.new("Frame")
    centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
    centerDot.Size = UDim2.new(0, 4, 0, 4)
    centerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
    centerDot.BackgroundColor3 = Color3.fromRGB(240, 248, 255)
    centerDot.BorderSizePixel = 0
    centerDot.ZIndex = 11
    centerDot.Parent = FOVCircle

    local centerCorner = Instance.new("UICorner")
    centerCorner.CornerRadius = UDim.new(1, 0)
    centerCorner.Parent = centerDot

    local function UpdateAimButton()
        for _, obj in ipairs(AimBtn:GetChildren()) do
            if obj:IsA("TextLabel") and (obj.Text == "AIM: OFF" or obj.Text == "AIM: ON") then
                obj.Text = aimEnabled and "AIM: ON" or "AIM: OFF"
                obj.TextColor3 = aimEnabled and T.Green or T.Text
            end
        end
    end

    local function GetTargetPart(target)
        if not target or target == LocalPlayer then return nil end

        local character = nil

        if target:IsA("Player") then
            character = target.Character
        elseif target:IsA("Model") then
            character = target
        else
            return nil
        end

        if not character or not character.Parent then return nil end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid
            or humanoid.Health <= 0
            or humanoid:GetState() == Enum.HumanoidStateType.Dead then
            return nil
        end

        return character:FindFirstChild(aimTargetPart)
            or character:FindFirstChild(aimTargetPart, true)
            or character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("HumanoidRootPart", true)
    end

    local function IsInsideFOV(target)
        local camera = workspace.CurrentCamera
        local part = GetTargetPart(target)
        if not camera or not part then return false, math.huge end

        local point, visible = camera:WorldToViewportPoint(part.Position)
        if not visible or point.Z <= 0 then return false, math.huge end

        local viewport = camera.ViewportSize
        local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
        local distance = (Vector2.new(point.X, point.Y) - center).Magnitude

        return distance <= aimFOVRadius, distance
    end

    local function FindClosestTarget()
        local bestTarget = nil
        local bestDistance = aimFOVRadius

        -- Real players
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local inside, distance = IsInsideFOV(player)

                if inside and distance < bestDistance then
                    bestDistance = distance
                    bestTarget = player
                end
            end
        end

        -- Bots / NPCs already detected by VantageBotRadar
        if VantageBotRadar and VantageBotRadar.Objects then
            for model, data in pairs(VantageBotRadar.Objects) do
                if model
                    and model.Parent
                    and data
                    and data.Humanoid
                    and data.Humanoid.Health > 0 then

                    local inside, distance = IsInsideFOV(model)

                    if inside and distance < bestDistance then
                        bestDistance = distance
                        bestTarget = model
                    end
                end
            end
        end

        return bestTarget
    end

    local function ClearTarget()
        lockedTarget = nil
        circleStroke.Color = Color3.fromRGB(90, 185, 255)
    end

    local function AcquireTarget()
        if espEnabled and VantageBotRadar and VantageBotRadar.Reconcile then
            pcall(VantageBotRadar.Reconcile)
        end

        lockedTarget = FindClosestTarget()

        if lockedTarget then
            circleStroke.Color = Color3.fromRGB(85, 235, 145)
        else
            circleStroke.Color = Color3.fromRGB(90, 185, 255)
        end
    end

    local function AimRenderStep()
        if not aimEnabled or not aimHolding then
            ClearTarget()
            return
        end

        local camera = workspace.CurrentCamera
        if not camera then return end

        -- Sticky: keep current target while alive and inside FOV.
        if lockedTarget then
            local valid, _ = IsInsideFOV(lockedTarget)
            if not valid then
                ClearTarget()
            end
        end

        -- Only acquire a new target when current lock is lost.
        if not lockedTarget then
            AcquireTarget()
        end

        local part = lockedTarget and GetTargetPart(lockedTarget)
        if not part then
            ClearTarget()
            return
        end

        local cameraPosition = camera.CFrame.Position
        local desired = CFrame.new(cameraPosition, part.Position)

        if aimSmoothness >= 0.99 then
            camera.CFrame = desired
        else
            camera.CFrame = camera.CFrame:Lerp(
                desired,
                math.clamp(aimSmoothness, 0.05, 0.98)
            )
        end
    end

    local function StartAim()
        pcall(function()
            RunService:UnbindFromRenderStep(AIM_BIND_NAME)
        end)

        -- Run after Roblox's normal camera update so the lock is not overwritten.
        RunService:BindToRenderStep(
            AIM_BIND_NAME,
            Enum.RenderPriority.Camera.Value + 1,
            AimRenderStep
        )
    end

    local function StopAim()
        pcall(function()
            RunService:UnbindFromRenderStep(AIM_BIND_NAME)
        end)
        aimHolding = false
        ClearTarget()
    end

    local function SetAimEnabled(state)
        aimEnabled = state == true
        FOVCircle.Visible = aimEnabled

        if aimEnabled then
            StartAim()
        else
            StopAim()
        end

        UpdateAimButton()
    end


    VantageProfileBridge.GetAimState = function()
        return {
            Enabled = aimEnabled == true,
            FOV = aimFOVRadius,
            Smoothness = aimSmoothness,
            TargetPart = aimTargetPart,
        }
    end

    VantageProfileBridge.ApplyAimState = function(state)
        if type(state) ~= "table" then return end

        if tonumber(state.FOV) then
            aimFOVRadius = math.clamp(tonumber(state.FOV), 60, 400)
            FOVCircle.Size = UDim2.new(0, aimFOVRadius * 2, 0, aimFOVRadius * 2)
        end

        if tonumber(state.Smoothness) then
            aimSmoothness = math.clamp(tonumber(state.Smoothness), 0.05, 1)
        end

        if state.TargetPart == "Head" or state.TargetPart == "HumanoidRootPart" then
            aimTargetPart = state.TargetPart
        end

        SetAimEnabled(state.Enabled == true)
        ClearTarget()
    end

    VantageProfileBridge.RefreshUI = function()
        UpdateAimButton()
        FOVCircle.Visible = aimEnabled
    end

        -- ========================================
    -- SETTINGS
    -- ========================================

    local AimSettingsFrame = Instance.new("Frame")
    AimSettingsFrame.Name = "AimSettings"
    AimSettingsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    AimSettingsFrame.Size = UDim2.new(0, 430, 0, 330)
    AimSettingsFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    AimSettingsFrame.BackgroundColor3 = T.Black
    AimSettingsFrame.BorderSizePixel = 0
    AimSettingsFrame.Visible = false
    AimSettingsFrame.ZIndex = 140
    AimSettingsFrame.Parent = ScreenGui
    Corner(AimSettingsFrame, 14)
    Stroke(AimSettingsFrame, T.Border, 0.03)

    Text(
        AimSettingsFrame, "AIM SETTINGS",
        UDim2.new(1, -70, 0, 28), UDim2.new(0, 18, 0, 14),
        Enum.Font.GothamBold, 16, T.Text
    ).ZIndex = 141

    Text(
        AimSettingsFrame, "Hold Right Mouse Button • green ring = locked",
        UDim2.new(1, -36, 0, 18), UDim2.new(0, 18, 0, 42),
        Enum.Font.Gotham, 9, T.Muted
    ).ZIndex = 141

    local AimClose = Instance.new("TextButton")
    AimClose.Size = UDim2.new(0, 32, 0, 32)
    AimClose.Position = UDim2.new(1, -46, 0, 16)
    AimClose.BackgroundColor3 = T.Navy
    AimClose.BorderSizePixel = 0
    AimClose.Text = "×"
    AimClose.TextColor3 = T.Muted
    AimClose.TextSize = 18
    AimClose.Font = Enum.Font.GothamBold
    AimClose.ZIndex = 142
    AimClose.Parent = AimSettingsFrame
    Corner(AimClose, 8)

    local function OptionButton(label, x, y, width)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, width, 0, 36)
        button.Position = UDim2.new(0, x, 0, y)
        button.BackgroundColor3 = T.Navy
        button.BorderSizePixel = 0
        button.Text = label
        button.TextColor3 = T.Text
        button.TextSize = 10
        button.Font = Enum.Font.GothamBold
        button.ZIndex = 141
        button.Parent = AimSettingsFrame
        Corner(button, 8)
        Stroke(button, T.Border, 0.20)
        return button
    end

    Text(
        AimSettingsFrame, "FOV SIZE",
        UDim2.new(0, 130, 0, 20), UDim2.new(0, 18, 0, 80),
        Enum.Font.GothamBold, 10, T.Muted
    ).ZIndex = 141

    local F100 = OptionButton("100", 18, 106, 88)
    local F150 = OptionButton("150", 112, 106, 88)
    local F200 = OptionButton("200", 206, 106, 88)
    local F250 = OptionButton("250", 300, 106, 88)

    local function SetFOV(value)
        aimFOVRadius = value
        FOVCircle.Size = UDim2.new(0, value * 2, 0, value * 2)
        ClearTarget()
    end

    F100.MouseButton1Click:Connect(function() SetFOV(100) end)
    F150.MouseButton1Click:Connect(function() SetFOV(150) end)
    F200.MouseButton1Click:Connect(function() SetFOV(200) end)
    F250.MouseButton1Click:Connect(function() SetFOV(250) end)

    Text(
        AimSettingsFrame, "LOCK STRENGTH",
        UDim2.new(0, 150, 0, 20), UDim2.new(0, 18, 0, 160),
        Enum.Font.GothamBold, 10, T.Muted
    ).ZIndex = 141

    local InstantButton = OptionButton("INSTANT", 18, 186, 118)
    local StrongButton = OptionButton("STRONG", 146, 186, 118)
    local SmoothButton = OptionButton("SMOOTH", 274, 186, 118)

    InstantButton.MouseButton1Click:Connect(function()
        aimSmoothness = 1.0
    end)

    StrongButton.MouseButton1Click:Connect(function()
        aimSmoothness = 0.55
    end)

    SmoothButton.MouseButton1Click:Connect(function()
        aimSmoothness = 0.20
    end)

    Text(
        AimSettingsFrame, "TARGET",
        UDim2.new(0, 100, 0, 20), UDim2.new(0, 18, 0, 240),
        Enum.Font.GothamBold, 10, T.Muted
    ).ZIndex = 141

    local HeadButton = OptionButton("HEAD", 18, 266, 185)
    local BodyButton = OptionButton("BODY", 213, 266, 185)

    HeadButton.MouseButton1Click:Connect(function()
        aimTargetPart = "Head"
        ClearTarget()
    end)

    BodyButton.MouseButton1Click:Connect(function()
        aimTargetPart = "HumanoidRootPart"
        ClearTarget()
    end)

    AimBtn.MouseButton1Click:Connect(function()
        local ok, err = pcall(function()
            SetAimEnabled(not aimEnabled)
        end)

        if not ok then
            warn("VANTAGE AIM ERROR: " .. tostring(err))
        end
    end)

    AimSettingsBtn.MouseButton1Click:Connect(function()
        MenuOpen = false
        MainMenu.Visible = false
        AimSettingsFrame.Visible = true
    end)

    AimClose.MouseButton1Click:Connect(function()
        AimSettingsFrame.Visible = false
        MainMenu.Visible = true
        MenuOpen = true
    end)

    -- Do not reject RMB merely because Roblox marked it as processed.
    aimInputBeganConnection = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 and aimEnabled then
            aimHolding = true
            AcquireTarget()
        end
    end)

    aimInputEndedConnection = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            aimHolding = false
            ClearTarget()
        end
    end)

    ScreenGui.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            StopAim()

            if aimInputBeganConnection then
                aimInputBeganConnection:Disconnect()
                aimInputBeganConnection = nil
            end

            if aimInputEndedConnection then
                aimInputEndedConnection:Disconnect()
                aimInputEndedConnection = nil
            end

            if AimOverlay then
                AimOverlay:Destroy()
            end
        end
    end)

    print("VANTAGE AIM V2: LOADED")
end)

if not AimModuleLoaded then
    warn("VANTAGE AIM V2 FAILED: " .. tostring(AimModuleError))
    warn("Main VANTAGE menu remains available.")
end

-- ============================================
-- VANTAGE DEVELOPER PAGE
-- Premium purple creator profile
-- ============================================
local VantageDeveloperLoaded, VantageDeveloperError = pcall(function()
    local DEVELOPER_NAME = "AB"
    local DEVELOPER_DISCORD = "z6b"
    local DEVELOPER_INVITE = "https://discord.gg/DdybHKbs5m"
    local DEVELOPER_IMAGE_URL = "https://raw.githubusercontent.com/zfaaaaaaaa/Vantage-z6b/refs/heads/main/vantage_developer_ab.png"
    local DEVELOPER_IMAGE_FOLDER = "VantageDeveloper"
    local DEVELOPER_IMAGE_FILE = DEVELOPER_IMAGE_FOLDER .. "/developer_ab.png"

    local function MakeGradient(parent, c1, c2, rotation)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, c1),
            ColorSequenceKeypoint.new(1, c2),
        })
        g.Rotation = rotation or 0
        g.Parent = parent
        return g
    end

    local function TryCopy(value)
        local copied = false

        if setclipboard then
            copied = pcall(function()
                setclipboard(value)
            end)
        elseif toclipboard then
            copied = pcall(function()
                toclipboard(value)
            end)
        end

        return copied
    end

    local function ResolveDeveloperImage()
        local customAsset = getcustomasset or getsynasset
        if not customAsset then
            return nil
        end

        local ok = pcall(function()
            if makefolder and isfolder and not isfolder(DEVELOPER_IMAGE_FOLDER) then
                makefolder(DEVELOPER_IMAGE_FOLDER)
            end

            local needsDownload = true
            if isfile then
                needsDownload = not isfile(DEVELOPER_IMAGE_FILE)
            end

            if needsDownload and writefile then
                local body = game:HttpGet(DEVELOPER_IMAGE_URL)
                if body and #body > 100 then
                    writefile(DEVELOPER_IMAGE_FILE, body)
                end
            end
        end)

        if not ok then
            return nil
        end

        local success, asset = pcall(function()
            return customAsset(DEVELOPER_IMAGE_FILE)
        end)

        if success then
            return asset
        end

        return nil
    end

    -- Final main-menu spacing after AIM + AUTO COMBAT have already initialized.
    MainMenu.Size = UDim2.new(0, 650, 0, 700)

    if ProfilesBtn and ProfilesBtn.Parent then
        ProfilesBtn.Position = UDim2.new(0, 0, 0, 412)
    end

    local DeveloperBtn = ActionButton(
        "DeveloperButton", 0, 476, 602, 54,
        "♛", "DEVELOPER", "Creator profile • Discord • VANTAGE",
        T.PurpleSoft
    )

    if CloseBtn and CloseBtn.Parent then
        CloseBtn.Position = UDim2.new(0, 0, 0, 540)
    end

    -- Developer page shell
    local DeveloperFrame = Instance.new("Frame")
    DeveloperFrame.Name = "DeveloperFrame"
    DeveloperFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    DeveloperFrame.Size = UDim2.new(0, 780, 0, 590)
    DeveloperFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    DeveloperFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 9)
    DeveloperFrame.BorderSizePixel = 0
    DeveloperFrame.Visible = false
    DeveloperFrame.Parent = ScreenGui
    Corner(DeveloperFrame, 18)
    Stroke(DeveloperFrame, Color3.fromRGB(93, 53, 143), 0.05)

    MakeGradient(
        DeveloperFrame,
        Color3.fromRGB(5, 5, 9),
        Color3.fromRGB(20, 10, 31),
        14
    )

    -- Subtle top accent
    local TopAccent = Instance.new("Frame")
    TopAccent.Size = UDim2.new(1, -44, 0, 2)
    TopAccent.Position = UDim2.new(0, 22, 0, 74)
    TopAccent.BackgroundColor3 = T.Purple
    TopAccent.BorderSizePixel = 0
    TopAccent.Parent = DeveloperFrame
    Corner(TopAccent, 2)
    MakeGradient(
        TopAccent,
        Color3.fromRGB(75, 42, 125),
        Color3.fromRGB(192, 113, 255),
        0
    )

    -- Header
    local DevLogoBox = Instance.new("Frame")
    DevLogoBox.Size = UDim2.new(0, 42, 0, 42)
    DevLogoBox.Position = UDim2.new(0, 24, 0, 18)
    DevLogoBox.BackgroundColor3 = Color3.fromRGB(22, 14, 37)
    DevLogoBox.BorderSizePixel = 0
    DevLogoBox.Parent = DeveloperFrame
    Corner(DevLogoBox, 21)
    Stroke(DevLogoBox, T.Purple, 0.1)

    Text(
        DevLogoBox, "♙",
        UDim2.new(1, 0, 1, 0), UDim2.new(),
        Enum.Font.GothamBold, 22, T.PurpleSoft,
        Enum.TextXAlignment.Center
    )

    Text(
        DeveloperFrame, "DEVELOPER",
        UDim2.new(0, 250, 0, 26), UDim2.new(0, 80, 0, 15),
        Enum.Font.GothamBlack, 21, T.PurpleSoft
    )

    Text(
        DeveloperFrame, "ABOUT THE CREATOR",
        UDim2.new(0, 250, 0, 18), UDim2.new(0, 80, 0, 41),
        Enum.Font.GothamMedium, 10, T.Muted
    )

    local DevClose = Instance.new("TextButton")
    DevClose.Size = UDim2.new(0, 36, 0, 36)
    DevClose.Position = UDim2.new(1, -56, 0, 20)
    DevClose.BackgroundColor3 = Color3.fromRGB(13, 10, 22)
    DevClose.BorderSizePixel = 0
    DevClose.Text = "×"
    DevClose.TextColor3 = T.Muted
    DevClose.TextSize = 20
    DevClose.Font = Enum.Font.Gotham
    DevClose.AutoButtonColor = false
    DevClose.Parent = DeveloperFrame
    Corner(DevClose, 9)
    Stroke(DevClose, T.Border, 0.2)
    Hover(DevClose, Color3.fromRGB(13, 10, 22), Color3.fromRGB(29, 17, 43))

    -- Left creator card
    local CreatorCard = Instance.new("Frame")
    CreatorCard.Size = UDim2.new(0, 300, 0, 415)
    CreatorCard.Position = UDim2.new(0, 24, 0, 94)
    CreatorCard.BackgroundColor3 = Color3.fromRGB(10, 8, 16)
    CreatorCard.BorderSizePixel = 0
    CreatorCard.Parent = DeveloperFrame
    Corner(CreatorCard, 16)
    Stroke(CreatorCard, Color3.fromRGB(78, 48, 118), 0.08)

    local PortraitRing = Instance.new("Frame")
    PortraitRing.Size = UDim2.new(0, 230, 0, 230)
    PortraitRing.Position = UDim2.new(0.5, -115, 0, 24)
    PortraitRing.BackgroundColor3 = Color3.fromRGB(23, 15, 36)
    PortraitRing.BorderSizePixel = 0
    PortraitRing.Parent = CreatorCard
    Corner(PortraitRing, 115)
    local portraitStroke = Stroke(PortraitRing, T.Purple, 0.03)
    portraitStroke.Thickness = 2

    local Portrait = Instance.new("ImageLabel")
    Portrait.Size = UDim2.new(1, -10, 1, -10)
    Portrait.Position = UDim2.new(0, 5, 0, 5)
    Portrait.BackgroundColor3 = Color3.fromRGB(16, 13, 23)
    Portrait.BorderSizePixel = 0
    Portrait.ScaleType = Enum.ScaleType.Crop
    Portrait.Image = ""
    Portrait.Parent = PortraitRing
    Corner(Portrait, 110)

    local PortraitFallback = Text(
        Portrait, "AB",
        UDim2.new(1, 0, 1, 0), UDim2.new(),
        Enum.Font.GothamBlack, 56, T.PurpleSoft,
        Enum.TextXAlignment.Center
    )

    task.spawn(function()
        local asset = ResolveDeveloperImage()
        if asset and Portrait.Parent then
            Portrait.Image = asset
            PortraitFallback.Visible = false
        end
    end)

    Text(
        CreatorCard, "AB",
        UDim2.new(1, -30, 0, 44), UDim2.new(0, 15, 0, 270),
        Enum.Font.GothamBlack, 38, T.Text,
        Enum.TextXAlignment.Center
    )

    Text(
        CreatorCard, "DEVELOPER & CREATOR",
        UDim2.new(1, -30, 0, 20), UDim2.new(0, 15, 0, 314),
        Enum.Font.GothamBold, 11, T.PurpleSoft,
        Enum.TextXAlignment.Center
    )

    local Signature = Text(
        CreatorCard, "A B",
        UDim2.new(1, -30, 0, 54), UDim2.new(0, 15, 0, 340),
        Enum.Font.GothamBlack, 31, T.Purple,
        Enum.TextXAlignment.Center
    )
    Signature.TextTransparency = 0.04

    -- Right profile
    local Right = Instance.new("Frame")
    Right.Size = UDim2.new(0, 416, 0, 415)
    Right.Position = UDim2.new(0, 340, 0, 94)
    Right.BackgroundTransparency = 1
    Right.Parent = DeveloperFrame

    Text(
        Right, "AB",
        UDim2.new(0, 240, 0, 48), UDim2.new(0, 0, 0, 4),
        Enum.Font.GothamBlack, 40, T.Text
    )

    local Verified = Instance.new("Frame")
    Verified.Size = UDim2.new(0, 28, 0, 28)
    Verified.Position = UDim2.new(0, 73, 0, 13)
    Verified.BackgroundColor3 = T.Purple
    Verified.BorderSizePixel = 0
    Verified.Rotation = 45
    Verified.Parent = Right
    Corner(Verified, 7)

    local Check = Text(
        Verified, "✓",
        UDim2.new(1, 0, 1, 0), UDim2.new(),
        Enum.Font.GothamBlack, 15, T.Text,
        Enum.TextXAlignment.Center
    )
    Check.Rotation = -45

    Text(
        Right, "DEVELOPER & CREATOR",
        UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 54),
        Enum.Font.GothamBold, 11, T.PurpleSoft
    )

    local QuoteCard = Instance.new("Frame")
    QuoteCard.Size = UDim2.new(1, 0, 0, 100)
    QuoteCard.Position = UDim2.new(0, 0, 0, 86)
    QuoteCard.BackgroundColor3 = Color3.fromRGB(10, 8, 16)
    QuoteCard.BorderSizePixel = 0
    QuoteCard.Parent = Right
    Corner(QuoteCard, 13)
    Stroke(QuoteCard, Color3.fromRGB(75, 48, 111), 0.28)

    Text(
        QuoteCard, "“",
        UDim2.new(0, 34, 0, 38), UDim2.new(0, 15, 0, 8),
        Enum.Font.GothamBlack, 31, T.PurpleSoft
    )

    local Quote = Text(
        QuoteCard,
        "Building VANTAGE for precision, control and performance.",
        UDim2.new(1, -70, 0, 52), UDim2.new(0, 50, 0, 24),
        Enum.Font.GothamMedium, 13, Color3.fromRGB(211, 206, 220)
    )
    Quote.TextWrapped = true

    local function InfoRow(y, icon, label, value, buttonText, copyValue)
        local Row = Instance.new("Frame")
        Row.Size = UDim2.new(1, 0, 0, 61)
        Row.Position = UDim2.new(0, 0, 0, y)
        Row.BackgroundColor3 = Color3.fromRGB(10, 8, 16)
        Row.BorderSizePixel = 0
        Row.Parent = Right
        Corner(Row, 12)
        Stroke(Row, Color3.fromRGB(70, 45, 103), 0.3)

        local IconBox = Instance.new("Frame")
        IconBox.Size = UDim2.new(0, 40, 0, 40)
        IconBox.Position = UDim2.new(0, 10, 0.5, -20)
        IconBox.BackgroundColor3 = Color3.fromRGB(29, 18, 47)
        IconBox.BorderSizePixel = 0
        IconBox.Parent = Row
        Corner(IconBox, 9)
        Stroke(IconBox, T.Purple, 0.25)

        Text(
            IconBox, icon,
            UDim2.new(1, 0, 1, 0), UDim2.new(),
            Enum.Font.GothamBold, 16, T.PurpleSoft,
            Enum.TextXAlignment.Center
        )

        Text(
            Row, label,
            UDim2.new(0, 210, 0, 15), UDim2.new(0, 62, 0, 9),
            Enum.Font.GothamMedium, 9, T.Muted
        )

        Text(
            Row, value,
            UDim2.new(0, 225, 0, 23), UDim2.new(0, 62, 0, 27),
            Enum.Font.GothamBold, 13, T.Text
        )

        local CopyBtn = Instance.new("TextButton")
        CopyBtn.Size = UDim2.new(0, 92, 0, 34)
        CopyBtn.Position = UDim2.new(1, -102, 0.5, -17)
        CopyBtn.BackgroundColor3 = Color3.fromRGB(27, 17, 43)
        CopyBtn.BorderSizePixel = 0
        CopyBtn.Text = buttonText
        CopyBtn.TextColor3 = T.PurpleSoft
        CopyBtn.TextSize = 11
        CopyBtn.Font = Enum.Font.GothamBold
        CopyBtn.AutoButtonColor = false
        CopyBtn.Parent = Row
        Corner(CopyBtn, 8)
        Stroke(CopyBtn, T.Purple, 0.28)
        Hover(CopyBtn, Color3.fromRGB(27, 17, 43), Color3.fromRGB(40, 24, 62))

        CopyBtn.MouseButton1Click:Connect(function()
            local original = CopyBtn.Text
            local copied = TryCopy(copyValue)
            CopyBtn.Text = copied and "COPIED" or "COPY"
            task.delay(1.0, function()
                if CopyBtn and CopyBtn.Parent then
                    CopyBtn.Text = original
                end
            end)
        end)
    end

    InfoRow(202, "◉", "DISCORD USERNAME", DEVELOPER_DISCORD, "COPY", DEVELOPER_DISCORD)
    InfoRow(273, "↗", "DISCORD SERVER", "VANTAGE COMMUNITY", "INVITE", DEVELOPER_INVITE)
    InfoRow(344, "∞", "SERVER INVITE", "discord.gg/DdybHKbs5m", "COPY", DEVELOPER_INVITE)

    -- Bottom about card
    local AboutCard = Instance.new("Frame")
    AboutCard.Size = UDim2.new(1, -48, 0, 52)
    AboutCard.Position = UDim2.new(0, 24, 1, -66)
    AboutCard.BackgroundColor3 = Color3.fromRGB(11, 8, 18)
    AboutCard.BorderSizePixel = 0
    AboutCard.Parent = DeveloperFrame
    Corner(AboutCard, 12)
    Stroke(AboutCard, Color3.fromRGB(72, 46, 108), 0.25)

    Text(
        AboutCard, "♛",
        UDim2.new(0, 40, 1, 0), UDim2.new(0, 12, 0, 0),
        Enum.Font.GothamBlack, 20, T.PurpleSoft,
        Enum.TextXAlignment.Center
    )

    Text(
        AboutCard, "ABOUT VANTAGE",
        UDim2.new(0, 160, 0, 19), UDim2.new(0, 59, 0, 8),
        Enum.Font.GothamBold, 11, T.PurpleSoft
    )

    Text(
        AboutCard, "Made for control • precision • performance",
        UDim2.new(0, 360, 0, 17), UDim2.new(0, 59, 0, 27),
        Enum.Font.Gotham, 10, T.Muted
    )

    local BackBtn = Instance.new("TextButton")
    BackBtn.Size = UDim2.new(0, 118, 0, 34)
    BackBtn.Position = UDim2.new(1, -132, 0.5, -17)
    BackBtn.BackgroundColor3 = Color3.fromRGB(28, 17, 44)
    BackBtn.BorderSizePixel = 0
    BackBtn.Text = "←  BACK"
    BackBtn.TextColor3 = T.PurpleSoft
    BackBtn.TextSize = 11
    BackBtn.Font = Enum.Font.GothamBold
    BackBtn.AutoButtonColor = false
    BackBtn.Parent = AboutCard
    Corner(BackBtn, 8)
    Stroke(BackBtn, T.Purple, 0.25)
    Hover(BackBtn, Color3.fromRGB(28, 17, 44), Color3.fromRGB(43, 25, 65))

    local function OpenDeveloperPage()
        MainMenu.Visible = false
        DeveloperFrame.Visible = true
    end

    local function CloseDeveloperPage()
        DeveloperFrame.Visible = false
        MainMenu.Visible = true
    end

    DeveloperBtn.MouseButton1Click:Connect(OpenDeveloperPage)
    BackBtn.MouseButton1Click:Connect(CloseDeveloperPage)
    DevClose.MouseButton1Click:Connect(CloseDeveloperPage)

    print("VANTAGE DEVELOPER PAGE: LOADED")
end)

if not VantageDeveloperLoaded then
    warn("VANTAGE DEVELOPER PAGE ERROR: " .. tostring(VantageDeveloperError))
end


task.defer(function()
    -- One deferred turn guarantees every GUI/module bridge above is ready.
    local ok, err = pcall(function()
        local lastProfile = LoadActiveProfileName()

        if lastProfile and savedProfiles[lastProfile] and ApplyProfile then
            local applied = ApplyProfile(lastProfile)
            if applied then
                print("VANTAGE PROFILE AUTO-LOADED: " .. tostring(lastProfile))
            end
        end
    end)

    if not ok then
        warn("VANTAGE PROFILE AUTO-LOAD ERROR: " .. tostring(err))
    end
end)
