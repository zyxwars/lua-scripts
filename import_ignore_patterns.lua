local dt = require "darktable"
local log = require "lib/dtutils.log"

SCRIPT_NAME = "import_ignore_patterns"
PREFERENCE_NAME = "ignore_patterns"
LABEL = "Import ignore patterns"
TOOLTIP = "Pipe (|) separated lua patterns to ignore when importing"

dt.print_log(string.format("Loaded %s", SCRIPT_NAME))

dt.preferences.register(SCRIPT_NAME, PREFERENCE_NAME, "string",
  LABEL, TOOLTIP, "darktable_exported")

dt.register_event(SCRIPT_NAME, "pre-import", function(event,images)
    local patterns_string = dt.preferences.read(SCRIPT_NAME, PREFERENCE_NAME, "string") 
    -- Create array from iterator
    local patterns = {}
    for pattern in string.gmatch(patterns_string, '([^|]+)') do
        table.insert(patterns,pattern)
    end

    local ignored = 0

    for i, img in ipairs(images) do
        for _, pattern in ipairs(patterns) do
            if img:match(pattern) then
                dt.print_log(string.format("Ignoring %s, matched %s", img, pattern))
                images[i] = nil
                ignored = ignored + 1
                break 
            end
        end
    end

    log.msg(log.screen, string.format("Ignored %d images containing ignore patterns", ignored))
end)
