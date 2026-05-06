local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error(string.format("%s: expected %q, got %q", message, tostring(expected), tostring(actual)), 2)
    end
end

local function shell_quote(value)
    value = tostring(value or "")
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function make_temp_dir()
    local base = os.getenv("TMPDIR") or "/tmp"
    local dir = base:gsub("/$", "")
        .. "/infisical-env-test-"
        .. tostring(os.time())
        .. "-"
        .. tostring(math.random(1000000))
    assert(os.execute("mkdir -p " .. shell_quote(dir)))
    return dir
end

local commands = {}
local decoded_data = nil

package.preload["cmd"] = function()
    return {
        exec = function(command)
            table.insert(commands, command)
            return "__json__"
        end,
    }
end

package.preload["json"] = function()
    return {
        decode = function(output)
            assert_equal("__json__", output, "json.decode received command output")
            return decoded_data
        end,
    }
end

PLUGIN = {}
dofile("hooks/mise_env.lua")

local function write_config(dir)
    local path = dir .. "/.infisical.json"
    local file = assert(io.open(path, "w"))
    file:write("{}\n")
    file:close()
    return path
end

local function env_map(result)
    local map = {}
    for _, item in ipairs(result.env) do
        map[item.key] = item.value
    end
    return map
end

local function run_hook(data, options)
    commands = {}
    decoded_data = data

    local dir = make_temp_dir()
    local config_file = write_config(dir)
    options = options or {}
    options.config_file = config_file
    options.infisical_bin = "/fake/infisical"

    return PLUGIN:MiseEnv({ options = options }), commands[1], config_file
end

local function test_array_export()
    local result, command, config_file = run_hook({
        { key = "API_KEY", value = "secret-value", type = "shared" },
        { key = "PORT", value = 3000, type = "shared" },
        { key = "INCOMPLETE_SECRET" },
    }, {
        env = "dev",
        path = "/",
    })
    local env = env_map(result)

    assert_equal(true, result.cacheable, "array export is cacheable")
    assert_equal(true, result.redact, "array export is redacted")
    assert_equal(config_file, result.watch_files[1], "array export watches config")
    assert_equal("secret-value", env.API_KEY, "array export maps secret key")
    assert_equal("3000", env.PORT, "array export stringifies non-string values")
    assert_equal(nil, env.INCOMPLETE_SECRET, "array export skips entries without a value")
    assert(command:find("--format=json", 1, true), "command requests JSON")
    assert(command:find("--env='dev'", 1, true), "command includes env option")
    assert(command:find("--path='/'", 1, true), "command includes path option")
end

local function test_object_export()
    local result = run_hook({
        secrets = {
            API_KEY = "secret-value",
            PORT = 3000,
            NESTED = { ignored = true },
        },
    })
    local env = env_map(result)

    assert_equal("secret-value", env.API_KEY, "object export maps secret key")
    assert_equal("3000", env.PORT, "object export stringifies non-string values")
    assert_equal(nil, env.NESTED, "object export skips nested tables")
end

local function test_missing_config()
    commands = {}
    decoded_data = {}

    local result = PLUGIN:MiseEnv({
        options = {
            config_file = "/tmp/infisical-env-test-missing/.infisical.json",
            infisical_bin = "/fake/infisical",
        },
    })

    assert_equal(0, #result.env, "missing config returns no env vars")
    assert_equal(0, #result.watch_files, "missing config has no watch files")
    assert_equal(0, #commands, "missing config does not call infisical")
end

math.randomseed(os.time())

test_array_export()
test_object_export()
test_missing_config()

print("mise_env_test.lua: ok")
