BabblerOwnerMixin = CreateMixin(BabblerOwnerMixin)
BabblerOwnerMixin.type = "BabblerOwner"


local kMaxTrackedBabblers = 18
BabblerOwnerMixin.networkVars = 
{
    babblerCount = "integer (0 to " .. kMaxTrackedBabblers .. ")",
    webbedBabblerCount = "integer (0 to " .. kMaxTrackedBabblers .. ")",
    bombBabblerCount = "integer (0 to " .. kMaxTrackedBabblers .. ")"
}

kBabblerHatchTime = 2.5
function BabblerOwnerMixin:__initmixin()
    
    PROFILE("BabblerOwnerMixin:__initmixin")
    
    self.babblerCount = 0
    self.webbedBabblerCount = 0
    self.bombBabblerCount = 0
    self.babblerBaitId = Entity.invalidId

    if Server then
        self:AddTimedCallback(self.HatchBabbler, kBabblerHatchTime)
    end
end

function BabblerOwnerMixin:GetBabblerCount()
    return self.babblerCount
end

-- Upper bound of the webbedBabblerCount network var declared above.
local kMaxTrackedWebbedBabblers = 6

function BabblerOwnerMixin:WebBabblerAdded()
    self.webbedBabblerCount = math.min(kMaxTrackedWebbedBabblers, self.webbedBabblerCount + 1)
end
function BabblerOwnerMixin:WebBabblerRemoved()
    self.webbedBabblerCount = math.max(0, self.webbedBabblerCount - 1)
end

function BabblerOwnerMixin:GetNumWebbedBabblers()
    return self.webbedBabblerCount or 0
end

function BabblerOwnerMixin:GetBombBabblerCount()
    return self.bombBabblerCount
end

function BabblerOwnerMixin:GetMaxBabblers()
    return 6
end

function BabblerOwnerMixin:OnWeaponAdded(weapon)
    if weapon:GetMapName() == BabblerAbility.kMapName then
        self.babblerBaitId = weapon:GetId()
    end
end

-- Returns if the owner can hatch/spawn a babbler
function BabblerOwnerMixin:GetCanHatchBabbler()
    -- owner needs to be below the babbler limit
    local aboveBabblerLimit = self:GetBabblerCount() >= self:GetMaxBabblers()
    if aboveBabblerLimit then
        return false
    end

    -- owner needs to be able to attach the babblers
    if not self:GetCanAttachBabbler() then
        return false
    end

    -- owner needs to be on a playing team
    if self.GetIsOnPlayingTeam and not self:GetIsOnPlayingTeam() then
        return false
    end

    -- owner needs to be alive
    if HasMixin(self, "Live") and not self:GetIsAlive() then
        return false
    end
    
    -- owner needs to be not under attack
    if self.GetIsUnderFire and self:GetIsUnderFire() then
        return false
    end

    -- if all requirements are met owner can hatch another babbler
    return true
end

if Server then

    function BabblerOwnerMixin:BabblerCreated()
        self.babblerCount = math.min(kMaxTrackedBabblers, self.babblerCount + 1)
        --Log("%s - Babblers created, new count: %s", self, self.babblerCount)
    end

    function BabblerOwnerMixin:BabblerDestroyed()
        self.babblerCount = math.max(0, self.babblerCount - 1)
        --Log("%s - Babblers destroyed, new count %s", self, self.babblerCount)
    end

    function BabblerOwnerMixin:BombBabblerCreated()
        self.bombBabblerCount = math.min(kMaxTrackedBabblers, self.bombBabblerCount + 1)
    end

    function BabblerOwnerMixin:BombBabblerDestroyed()
        self.bombBabblerCount = math.max(0, self.bombBabblerCount - 1)
    end
    
    local function CountRealBabblers(owner)

        local count = 0
        local webbedCount = 0
        local ownerId = owner:GetId()
        for _, babbler in ipairs(GetEntitiesForTeam("Babbler", owner:GetTeamNumber())) do
            if babbler:GetOwnerId() == ownerId and not babbler.babblerBombSpawned then
                count = count + 1
                if babbler:GetIsOnWeb() then
                    webbedCount = webbedCount + 1
                end
            end
        end

        return count, webbedCount

    end

    -- The audit is a full team-wide entity scan, so it is throttled instead of
    -- running on every hatch tick (it used to run several times a second).
    local kCounterAuditInterval = 10
    local function AuditBabblerCount(self)

        local now = Shared.GetTime()
        if self.timeNextBabblerAudit and now < self.timeNextBabblerAudit then
            return
        end
        self.timeNextBabblerAudit = now + kCounterAuditInterval

        local actual, webbed = CountRealBabblers(self)
        if actual ~= self.babblerCount then
            Print("Error: BabblerOwner drift: counter %d, actual %d (fixing)", self.babblerCount, actual)
            self.babblerCount = math.min(kMaxTrackedBabblers, actual)
        end

        if webbed ~= self.webbedBabblerCount then
            self.webbedBabblerCount = math.min(kMaxTrackedBabblers, webbed)
        end

    end

    function BabblerOwnerMixin:HatchBabbler()

        -- truth check before acting on the counter
        AuditBabblerCount(self)

        if self:GetCanHatchBabbler() then

            -- GetCanAttachBabbler said there is room, but the attach point list is
            -- the authority: bail rather than CreateEntity at a nil origin.
            local origin = self:GetFreeBabblerAttachPointOrigin()
            if not origin then
                return true
            end

            local babbler = CreateEntity(Babbler.kMapName, origin, self:GetTeamNumber())
            if not babbler then
                return true
            end

            babbler:SetOwner(self)
            babbler:SetSilenced(self.silenced == true)

            local client = self.GetClient and self:GetClient()
            if client and client.variantData then
                babbler:SetVariant(client.variantData.babblerVariant)
            end

            babbler:SetMoveType(kBabblerMoveType.Cling, self, self:GetOrigin(), true)

        end

        return true
    end

    function BabblerOwnerMixin:HatchMaxBabblers()
        for _ = 1, self:GetMaxBabblers() do
            if not self:GetCanHatchBabbler() then
                break
            end
            self:HatchBabbler()
        end
    end

    function BabblerOwnerMixin:DestroyAllOwnedBabblers()
        local ownerId = self:GetId()
        for _, babbler in ipairs(GetEntitiesForTeam("Babbler", self:GetTeamNumber())) do
            if babbler:GetOwnerId() == ownerId and babbler:GetIsAlive() then
                babbler:Kill()
            end
        end
    end

    function BabblerOwnerMixin:OnKill()
        self:DestroyAllOwnedBabblers()
    end
end
