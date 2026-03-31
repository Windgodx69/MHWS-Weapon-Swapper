local version = "0.0.18"

-- Cached values
local sdk = sdk
local imgui = imgui
local os = os

-- Other required files
local config = require("WeaponSwapper.Config")
local bindings = require("WeaponSwapper.Bindings")
local utils = require("WeaponSwapper.Utils")

-- Cached values
local action_id_type = sdk.find_type_definition("ace.ACTION_ID")
local facilitymenu_types = utils.generate_enum("app.FacilityMenu.TYPE")
local hunter_type_def = sdk.find_type_definition("app.HunterCharacter")

-- Variables
local swap_weapon = false
local last_swap_time = 0

-- COOLDOWN SETTINGS
local SWAP_COOLDOWN = 0.5 -- Prevention for accidental double-taps

local ALLOW_IN_COMBAT = false

--------------------------------------- Utilities ------------------------------------

local function has_facility_menu_open()
    local gui_manager = sdk.get_managed_singleton("app.GUIManager")
    if not gui_manager then return false end
    for _, value in ipairs(facilitymenu_types) do
        if value > 0 and gui_manager:isActiveMenu(value) then return true end
    end
    return false
end

local function request_swap_weapon()
    local master = utils.getMasterCharacter()
    if not master then return end 
    
    -- 1. THE SHEATH CHECK
    -- If this returns true, the weapon is out. We ONLY want to swap when false.
    if master:checkWeaponOn() then return end

    -- 2. Standard Safety Checks
    if not ALLOW_IN_COMBAT and utils.is_in_battle() then return end 
    if has_facility_menu_open() then return end 
    if master:get_IsInAllTent() then return end 
    if os.clock() - last_swap_time < SWAP_COOLDOWN then return end 

    swap_weapon = true
end

--------------------------------------- Config & UI ------------------------------------
ALLOW_IN_COMBAT = config.get("Allow in combat") or ALLOW_IN_COMBAT

local binding_config = config.get("swapkey")
if binding_config then
    bindings.add(binding_config.device, binding_config.keybinds, request_swap_weapon)
end

re.on_draw_ui(function()
    if imgui.collapsing_header("Weapon Swapper") then
        imgui.push_style_var(12, 5.0)
        local listen = bindings.listener:create("weaponswapper")

        listen:on_complete(function()
            if binding_config ~= nil then
                bindings.remove(binding_config.device, binding_config.keybinds)
            end
            binding_config = { keybinds = listen:get_inputs(), device = listen:get_device() }
            bindings.add(binding_config.device, binding_config.keybinds, request_swap_weapon)
            config.set("swapkey", binding_config)
        end)

        local keybind_string = ""
        if listen:is_listening() then
            keybind_string = "Listening... "
        elseif binding_config == nil or binding_config.keybinds == nil then
            keybind_string = "Not Set"
        else
            local inputs = bindings.get_names(binding_config.device, binding_config.keybinds)
            for i, input in ipairs(inputs) do
                keybind_string = keybind_string .. input.name
                if i < #inputs then keybind_string = keybind_string .. " + " end
            end
        end

        imgui.push_id("WeaponSwapper")
        imgui.indent(4)
        imgui.begin_disabled()
        imgui.input_text("", keybind_string)
        imgui.end_disabled()
        imgui.same_line()
        if imgui.button("Change Keybind") then listen:start() end
        
        if imgui.tree_node("Settings") then
            if imgui.checkbox("Allow in combat", ALLOW_IN_COMBAT) then
                ALLOW_IN_COMBAT = not ALLOW_IN_COMBAT
                config.set("Allow in combat", ALLOW_IN_COMBAT)
            end
            imgui.tree_pop()
        end
        imgui.unindent(4)
        imgui.pop_id()
        imgui.pop_style_var()
    end
end)

re.on_frame(function()
    bindings.update()
end)

------------------------------------ The Main Hook ------------------------------------

sdk.hook(hunter_type_def:get_method("update"), function(args)
    local obj = sdk.to_managed_object(args[2])
    
    if not obj or obj:get_address() == 0 then return end
    if not obj:get_type_definition():is_a(hunter_type_def) then return end
    
    -- Protected call for IsMaster
    local status, is_master = pcall(function() return obj:get_IsMaster() end)
    if not status or not is_master then return end
    
    local hunter = obj

    -- Swapping logic (Stripped down & simplified)
    if swap_weapon then
        local handling = hunter:get_WeaponHandling()
        if handling then
            hunter:changeWeaponFromReserve(false)
            last_swap_time = os.clock()
        end
        swap_weapon = false
    end
end, function(retval) return retval end)
