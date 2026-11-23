-- Screen arrangement that needs no profile, for laptops that dock anywhere
-- (hyprland.autoArrange in ./options.nix). Replaces kanshi there: kanshi only
-- acts on a set of screens it has a profile for, and every other set fell
-- back to the Nix rules, which put every screen at 0,0 on top of each other
-- (Erik, 2026-11-22: "should never be in a configuration so they overlap").
--
-- Whatever is plugged in, after each plug, unplug, lid change and reload:
--   * enabled screens never overlap. If any two do, the external screens are
--     laid out left to right in their current order, top-aligned, and the
--     built-in screen goes centred below them. A layout without overlaps
--     (one dragged in the shell's displays window) is left alone.
--   * the built-in screen is off while the lid is closed and another screen
--     works, and on otherwise.
--   * Erik's workspaces never stay on a screen that is off or on the agents'
--     headless output (AGENT-1); "agent" and "agent-park" stay where they are.
--
-- Rules are keyed by the full description (make, model, serial), so they
-- follow a monitor when the MST dock renames its connector; two screens with
-- the same description (one Dell on two cables) fall back to the connector.

local arrange = { lid = nil }
auto_arrange = arrange -- `hyprctl eval 'auto_arrange.run()'` re-arranges now

local AGENT_WORKSPACES = { agent = true, ["agent-park"] = true }

local function lid_closed()
  if arrange.lid ~= nil then
    return arrange.lid
  end
  for _, name in ipairs({ "LID0", "LID", "LID1" }) do
    local f = io.open("/proc/acpi/button/lid/" .. name .. "/state")
    if f then
      local state = f:read("*a")
      f:close()
      return state:find("closed") ~= nil
    end
  end
  return false
end

-- A physical screen. Headless outputs (AGENT-1) and Hyprland's FALLBACK have
-- no description.
local function physical(m)
  return m.description ~= "" and m.name ~= "FALLBACK"
end

local function logical_size(m)
  local w, h = m.width / m.scale, m.height / m.scale
  if m.transform % 2 == 1 then
    w, h = h, w
  end
  return math.floor(w + 0.5), math.floor(h + 0.5)
end

local function overlap(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- hl.monitor starts from the existing rule of the same name, so a screen
-- turned off by this file needs `disabled = false` to come back.
local function rule(m, selector, x, y)
  local spec = {
    output = selector,
    disabled = false,
    position = x .. "x" .. y,
    scale = m.scale,
    transform = m.transform,
    mode = m.width > 0 and string.format("%dx%d@%.3f", m.width, m.height, m.refresh_rate) or "preferred",
  }
  hl.monitor(spec)
end

local function move_workspaces(from, target)
  for _, ws in ipairs(hl.get_workspaces()) do
    if
      ws.monitor
      and from[ws.monitor.name]
      and not AGENT_WORKSPACES[ws.name]
      and not ws.name:find("^special")
    then
      hl.dispatch(hl.dsp.workspace.move({ workspace = ws.addressable_name, monitor = target }))
    end
  end
end

function arrange.run()
  local monitors = hl.get_monitors({ all = true })

  local count = {}
  for _, m in ipairs(monitors) do
    if physical(m) then
      count[m.description] = (count[m.description] or 0) + 1
    end
  end
  local function selector(m)
    return count[m.description] > 1 and m.name or ("desc:" .. m.description)
  end

  -- One monitor on two cables (same serial; the office Dell over HDMI and
  -- USB-C) shows one input at a time: the second output mirrors the first, so
  -- whichever input it shows has the desktop and nothing hides beside it.
  local primary_of = {}
  for _, m in ipairs(monitors) do
    if physical(m) and m.enabled and m.serial ~= "" and count[m.description] > 1 then
      local p = primary_of[m.description]
      if p == nil or m.name < p.name then
        primary_of[m.description] = m
      end
    end
  end

  local internal, boxes, strays = nil, {}, {}
  for _, m in ipairs(monitors) do
    local primary = physical(m) and primary_of[m.description]
    if primary and primary ~= m then
      strays[m.name] = true
      if not m.is_mirror then
        hl.monitor({
          output = m.name,
          mode = m.width > 0 and string.format("%dx%d@%.3f", m.width, m.height, m.refresh_rate) or "preferred",
          position = "auto",
          scale = m.scale,
          mirror = primary.name,
        })
      end
    elseif not physical(m) then
      strays[m.name] = true
    elseif m.name:find("^eDP") then
      internal = m
    elseif m.enabled and m.width > 0 then
      local w, h = logical_size(m)
      boxes[#boxes + 1] = { m = m, x = m.x, y = m.y, w = w, h = h }
    elseif not m.enabled then
      strays[m.name] = true
    end
  end

  local internal_on = internal ~= nil and not (lid_closed() and #boxes > 0)
  local inner
  if internal_on then
    local w, h = logical_size(internal)
    inner = { m = internal, x = internal.x, y = internal.y, w = w, h = h }
  elseif internal then
    strays[internal.name] = true
  end

  local all = {}
  for _, b in ipairs(boxes) do
    all[#all + 1] = b
  end
  if inner then
    all[#all + 1] = inner
  end
  local overlapping = false
  for i = 1, #all do
    for j = i + 1, #all do
      if overlap(all[i], all[j]) then
        overlapping = true
      end
    end
  end

  if overlapping then
    table.sort(boxes, function(a, b)
      if a.x ~= b.x then
        return a.x < b.x
      end
      return a.m.name < b.m.name
    end)
    local x, height = 0, 0
    for _, b in ipairs(boxes) do
      b.x, b.y = x, 0
      x = x + b.w
      height = math.max(height, b.h)
    end
    if inner then
      inner.x, inner.y = math.floor((x - inner.w) / 2), height
      if #boxes == 0 then
        inner.x, inner.y = 0, 0
      elseif inner.x < 0 then
        for _, b in ipairs(boxes) do
          b.x = b.x - inner.x
        end
        inner.x = 0
      end
    end
  end

  -- Where Erik's workspaces go: the leftmost external screen, else the
  -- built-in one.
  local main = inner
  for _, b in ipairs(boxes) do
    if main == nil or main == inner or b.x < main.x then
      main = b
    end
  end

  -- Screens coming on first, so the workspaces always have somewhere to go.
  if inner and (not internal.enabled or inner.x ~= internal.x or inner.y ~= internal.y) then
    rule(internal, selector(internal), inner.x, inner.y)
  end
  for _, b in ipairs(boxes) do
    -- A former mirror whose twin is gone gets its own rule again.
    if b.x ~= b.m.x or b.y ~= b.m.y or b.m.is_mirror then
      rule(b.m, selector(b.m), b.x, b.y)
    end
  end

  if main then
    move_workspaces(strays, main.m.name)
  end
  if internal and not internal_on and internal.enabled then
    hl.monitor({ output = selector(internal), disabled = true })
  end
end

-- A screen that is connected but has no mode (0x0) after Hyprland's three
-- retries is blocked by a stream the last dock left running on a display pipe:
-- aquamarine fails to switch it off on unplug, and nothing inside Hyprland can
-- (quickshell docs/surveys/monitor-runtime.md). Switching to another console
-- and back makes the kernel do a full modeset that drops it. Seen at the home
-- KVM and, on 2026-11-23, with the office Dell blocked by the KVM's stream.
-- At most once a minute, so a screen that is really broken cannot make it loop.
local last_reset = -60
local function stuck()
  for _, m in ipairs(hl.get_monitors({ all = true })) do
    if physical(m) and m.enabled and m.width == 0 then
      return true
    end
  end
  return false
end
local function reset_if_stuck()
  local now = os.time()
  if stuck() and now - last_reset >= 60 then
    last_reset = now
    hl.exec_cmd(
      "v=$(/run/wrappers/bin/sudo -n fgconsole) && /run/wrappers/bin/sudo -n chvt $((v % 6 + 1))"
        .. " && sleep 1 && /run/wrappers/bin/sudo -n chvt $v"
    )
  end
end

-- Plugging in an MST dock adds its screens one by one; wait until it settles.
-- Never more than 10 runs in 30 s: a rule Hyprland keeps reporting as changed
-- must not turn into a loop.
local generation, runs = 0, {}
local function guarded_run()
  local now, recent = os.time(), {}
  for _, t in ipairs(runs) do
    if now - t < 30 then
      recent[#recent + 1] = t
    end
  end
  runs = recent
  if #runs < 10 then
    runs[#runs + 1] = now
    arrange.run()
  end
end
function arrange.schedule(ms)
  generation = generation + 1
  local mine = generation
  hl.timer(function()
    if mine == generation then
      guarded_run()
    end
  end, { timeout = ms or 700, type = "oneshot" })
  hl.timer(function()
    if mine == generation then
      reset_if_stuck()
    end
  end, { timeout = 6000, type = "oneshot" })
end

hl.on("monitor.added", function()
  arrange.schedule()
end)
hl.on("monitor.removed", function()
  arrange.schedule()
end)
-- A screen that gets its mode late (after a retry or the console switch) adds
-- no monitor, only changes the layout. run() issues rules only when something
-- is off, so the layout change its own rules cause ends there.
hl.on("monitor.layout_changed", function()
  arrange.schedule()
end)

hl.bind("switch:on:Lid Switch", function()
  arrange.lid = true
  arrange.schedule(100)
end, { locked = true, description = "Lid closed: built-in screen off when another screen works" })
hl.bind("switch:off:Lid Switch", function()
  arrange.lid = false
  arrange.schedule(100)
end, { locked = true, description = "Lid opened: built-in screen back on" })

-- At login and after every reload (a rebuild reloads the config).
arrange.schedule(500)
