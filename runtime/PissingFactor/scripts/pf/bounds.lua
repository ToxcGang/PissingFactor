local Bounds = {}

-- Conservative segment/AABB entry. Unknown water surfaces must not fall through
-- to a submerged-floor stain. Bounds are exclusion regions, not water planes.
function Bounds.entry(a,b,center,extent)
    local first,last=0,1
    for _,axis in ipairs({"X","Y","Z"}) do
        local delta=b[axis]-a[axis]
        local low,high=center[axis]-extent[axis],center[axis]+extent[axis]
        if math.abs(delta)<0.000001 then
            if a[axis]<low or a[axis]>high then return nil end
        else
            local near,far=(low-a[axis])/delta,(high-a[axis])/delta
            if near>far then near,far=far,near end
            first,last=math.max(first,near),math.min(last,far)
            if first>last then return nil end
        end
    end
    return first
end
return Bounds
