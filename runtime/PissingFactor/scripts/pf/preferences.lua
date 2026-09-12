local Preferences={}
Preferences.defaults={Keyboard="P",Action="Gamepad_DPad_Left",
    Settings="F8",SoundVolume=0.65,StreamEffects=true,SurfaceStains=true,WaterEffects=true}

function Preferences.validate(source,validKey)
    local out,warnings={},{}
    source=type(source)=="table" and source or {}
    for k,v in pairs(Preferences.defaults) do out[k]=v end
    for _,name in ipairs({"Keyboard","Action","Settings"}) do
        local value=source[name]
        if value~=nil then
            if type(value)=="string" and #value<=64 and value:match("^[%w_]+$")
                and (not validKey or validKey(value)) then out[name]=value
            else warnings[#warnings+1]="Invalid binding: "..name end
        end
    end
    local seen={}
    for _,name in ipairs({"Keyboard","Action","Settings"}) do
        if seen[out[name]] then
            warnings[#warnings+1]="Duplicate bindings; restoring defaults"
            for _,key in ipairs({"Keyboard","Action","Settings"}) do out[key]=Preferences.defaults[key] end
            break
        end
        seen[out[name]]=true
    end
    local volume=source.SoundVolume
    if type(volume)=="number" and volume==volume and volume>=0 and volume<=1 then out.SoundVolume=volume end
    for _,name in ipairs({"StreamEffects","SurfaceStains","WaterEffects"}) do
        if type(source[name])=="boolean" then out[name]=source[name] end
    end
    return out,warnings
end

return Preferences
