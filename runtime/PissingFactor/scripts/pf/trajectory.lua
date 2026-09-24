local M = {}
M.speed, M.gravity = 550, 980

local function distance(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Y - b.Y)^2 + (a.Z - b.Z)^2)
end

-- Trace the arc, not just the camera ray. The caller excludes the emitting
-- character. The first obstruction wins, including water before a solid floor.
function M.trace(origin, direction, range, traceSegment)
    local points, previous, travelled = { origin }, origin, 0
    local speed, gravity, step = M.speed, M.gravity, 0.04
    for i = 1, 64 do
        local t = i * step
        local point = { X = origin.X + direction.X * speed * t,
            Y = origin.Y + direction.Y * speed * t,
            Z = origin.Z + direction.Z * speed * t - 0.5 * gravity * t * t }
        local length = distance(point, previous)
        if travelled + length > range then
            local fraction = (range - travelled) / length
            point = { X = previous.X + (point.X - previous.X) * fraction,
                Y = previous.Y + (point.Y - previous.Y) * fraction,
                Z = previous.Z + (point.Z - previous.Z) * fraction }
            length = range - travelled
            t = (i - 1 + fraction) * step
        end
        local hit = traceSegment(previous, point)
        if hit then
            points[#points + 1] = hit.position
            local fraction = length > 0 and math.min(1, distance(previous, hit.position) / length) or 0
            return { points = points, hit = hit, endpoint = hit.position,
                duration = (i - 1) * step + (t - (i - 1) * step) * fraction }
        end
        points[#points + 1] = point
        travelled = travelled + length
        if travelled >= range - 0.001 then
            return { points = points, endpoint = point, duration = t }
        end
        previous = point
    end
    return { points = points, endpoint = points[#points], duration = 64 * step }
end

-- Cubic Hermite tangents reproduce the ballistic parabola. The supplied end
-- point clips the last traced segment exactly at its first obstruction.
function M.tangents(direction, duration)
    local start = {X=direction.X*M.speed*duration,Y=direction.Y*M.speed*duration,
        Z=direction.Z*M.speed*duration}
    return start, {X=start.X,Y=start.Y,Z=start.Z-M.gravity*duration*duration}
end

return M
