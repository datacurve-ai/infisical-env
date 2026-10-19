local cmd = require("cmd")
local json = require("json")

local CONFIG_FILE = ".infisical.json"

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sh_quote(value)
    value = tostring(value or "")
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local function dirname(path)
    if path == "/" then
        return "/"
    end

    path = path:gsub("/+$", "")
    local parent = path:match("^(.*)/[^/]+$")
    if parent == "" then
        return "/"
    end
    return parent
end

local function path_join(left, right)
    if left:sub(-1) == "/" then
        return left .. right
    end
    return left .. "/" .. right
end

local function current_dir()
    local pwd = os.getenv("PWD")
    if pwd and pwd ~= "" then
        return pwd
    end
    return trim(cmd.exec("pwd"))
end

local function find_config_file(config_file)
    if config_file and config_file ~= "" then
        if config_file:sub(1, 1) == "/" then
            return config_file
        end
        return path_join(current_dir(), config_file)
    end

    local dir = current_dir()
    while dir do
        local candidate = path_join(dir, CONFIG_FILE)
        if file_exists(candidate) then
            return candidate
        end
        if dir == "/" then
            break
        end
        dir = dirname(dir)
    end

    return nil
end

local function option(ctx, ...)
    local options = ctx.options or {}
    for _, key in ipairs({ ... }) do
        if options[key] ~= nil then
            return options[key]
        end
    end
    return nil
end

local function append_option(parts, flag, value)
    if value == nil or value == "" then
        return
    end
    table.insert(parts, flag .. "=" .. sh_quote(value))
end

local function append_bool_option(parts, flag, value)
    if value == nil then
        return
    end
    table.insert(parts, flag .. "=" .. tostring(value))
end

local function append_csv_option(parts, flag, value)
    if value == nil or value == "" then
        return
    end

    if type(value) == "table" then
        local values = {}
        for _, item in ipairs(value) do
            table.insert(values, tostring(item))
        end
        value = table.concat(values, ",")
    end

    append_option(parts, flag, value)
end

local function build_command(ctx, project_root)
    local infisical_bin = option(ctx, "infisical_bin", "bin") or "infisical"
    local parts = {
        "cd " .. sh_quote(project_root),
        "&&",
        "INFISICAL_DISABLE_UPDATE_CHECK=true",
        sh_quote(infisical_bin),
        "export",
        "--format=json",
        "--silent",
    }

    append_option(parts, "--env", option(ctx, "env", "environment"))
    append_option(parts, "--path", option(ctx, "path", "secret_path"))
    append_option(parts, "--projectId", option(ctx, "projectId", "project_id", "workspaceId", "workspace_id"))
    append_option(parts, "--domain", option(ctx, "domain", "api_url"))
    append_csv_option(parts, "--tags", option(ctx, "tags"))
    append_bool_option(parts, "--expand", option(ctx, "expand"))
    append_bool_option(parts, "--include-imports", option(ctx, "include_imports", "include-imports"))
    append_bool_option(parts, "--secret-overriding", option(ctx, "secret_overriding", "secret-overriding"))

    return table.concat(parts, " ")
end

local function to_env_vars(data)
    local env_vars = {}

    if data[1] ~= nil then
        for _, secret in ipairs(data) do
            if type(secret) == "table" and secret.key ~= nil and secret.value ~= nil then
                table.insert(env_vars, {
                    key = tostring(secret.key),
                    value = tostring(secret.value),
                })
            end
        end
        return env_vars
    end

    local source = data.secrets or data
    for key, value in pairs(source) do
        if type(value) ~= "table" then
            table.insert(env_vars, {
                key = tostring(key),
                value = tostring(value),
            })
        end
    end

    return env_vars
end

function PLUGIN:MiseEnv(ctx)
    local config_file = find_config_file(option(ctx, "config_file", "config"))
    if not config_file or not file_exists(config_file) then
        return {
            cacheable = true,
            watch_files = {},
            env = {},
            redact = true,
        }
    end

    local project_root = dirname(config_file)
    local command = build_command(ctx, project_root)
    local ok, output = pcall(function()
        return cmd.exec(command)
    end)

    if not ok then
        print("[infisical] warning: `" .. command .. "` failed: " .. tostring(output))
        return {
            cacheable = true,
            watch_files = { config_file },
            env = {},
            redact = true,
        }
    end

    local decode_ok, data = pcall(json.decode, output)
    if not decode_ok or type(data) ~= "table" then
        print("[infisical] warning: failed to parse JSON from `" .. command .. "`")
        return {
            cacheable = true,
            watch_files = { config_file },
            env = {},
            redact = true,
        }
    end

    return {
        cacheable = option(ctx, "cache") ~= false,
        watch_files = { config_file },
        env = to_env_vars(data),
        redact = true,
    }
end
