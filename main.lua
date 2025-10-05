-- Portions of this code are derived from the original "filebrowser.koplugin"
-- for KOReader, licensed under the GNU AGPLv3.
-- Modifications and extensions © 2025 [Neeraj Patel].
local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage") -- luacheck:ignore
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

local path = DataStorage:getFullDataDir()
local config_path = path .. "/plugins/filebrowserplus.koplugin/config.json"
local db_path = path .. "/plugins/filebrowserplus.koplugin/filebrowser.db"

local plugin_path = path .. "/plugins/filebrowserplus.koplugin/filebrowser"
local silence_cmd = ""
-- uncomment below to prevent cmd output from cluttering up crash.log
silence_cmd = " > /dev/null 2>&1"
local pid_path = "/tmp/filebrowserplus_koreader.pid"
local bin_path = plugin_path .. "/filebrowser"

local filebrowser_args = string.format("-d %s -c %s ", db_path, config_path)
local filebrowser_cmd = bin_path .. " " .. filebrowser_args
local log_path = plugin_path .. "/filebrowserplus.log"

if not util.pathExists(bin_path) then
    logger.info("[FilebrowserPlus] binary missing, plugin not loading")
    return {
        disabled = true
    }
elseif os.execute("test -x '" .. bin_path .. "'") ~= 0 then
    logger.info("[FilebrowserPlus] binary not executable, attempting to fix permissions")
    os.execute("chmod +x " .. bin_path)
end

local FilebrowserPlus = WidgetContainer:extend{
    name = "FilebrowserPlus",
    is_doc_only = false
}

function FilebrowserPlus:init()
    self.filebrowserplus_first_setup = false
    self.filebrowserplus_port = G_reader_settings:readSetting("FilebrowserPlus_port") or "80"
    self.allow_no_password = G_reader_settings:isTrue("FilebrowserPlus_allow_no_password")
    self.autostart = G_reader_settings:isTrue("FilebrowserPlus_autostart")
    self.filebrowserplus_dataPath = G_reader_settings:readSetting("FilebrowserPlus_dataPath") or "/"

    if self.autostart then
        logger.info("[FilebrowserPlus] Autostart enabled, starting server on port " .. self.filebrowserplus_port)
        self:start()
    end

    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function FilebrowserPlus:config()
    os.remove(config_path)
    os.remove(db_path)

    local init_cmd = filebrowser_cmd .. " config init" .. silence_cmd
    logger.dbg("init:", init_cmd)
    local status = os.execute(init_cmd)

    local add_user_cmd = filebrowser_cmd .. "users add admin admin12345678 --perm.admin" .. silence_cmd
    logger.dbg("create_user:", add_user_cmd)
    status = os.execute(add_user_cmd)
    logger.dbg("status:", status)

    if status == 0 then
        logger.info("[FilebrowserPlus] User 'admin' has been created.")
    else
        logger.info("[FilebrowserPlus] Failed to reset admin password and auth, status Filebrowser, status:", status)
        local info = InfoMessage:new{
            icon = "notice-warning",
            text = _("Failed to reset Filebrowser config.")
        }
        UIManager:show(info)
    end
end

function FilebrowserPlus:resetPassword()
    local username = "admin"
    local newPass = "admin12345678"
    local reset_passwd_cmd = string.format("%s -d %s -c %s users update %s --password=%s", bin_path, db_path,
        config_path, username, newPass) .. silence_cmd
    logger.dbg("reset_pass:", reset_passwd_cmd)
    local status = os.execute(reset_passwd_cmd)
    logger.dbg("status:", status)

    if status == 0 then
        local info = InfoMessage:new{
            timeout = 15,
            text = string.format(
                "Password for user %s is now set to %s\nYou can change it via the filbrowser web portal!", username,
                newPass)
        }
        UIManager:show(info)
    else
        local info = InfoMessage:new{
            icon = "notice-warning",
            text = _("Failed to reset default password.")
        }
        UIManager:show(info)
    end
end

function FilebrowserPlus:start()
    if self:isRunning() then
        logger.dbg("[FilerowserX] Not starting FilebrowserPlus, already running.")
        return
    end

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
        os.execute(string.format("%s %s %s", "iptables -A INPUT -p tcp --dport", self.filebrowserplus_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s", "iptables -A OUTPUT -p tcp --sport", self.filebrowserplus_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    if not util.fileExists(db_path) then
        self.filebrowserplus_first_setup = true
        self:config()
    else
        self.filebrowserplus_first_setup = false
    end

    if not util.pathExists(self.filebrowserplus_dataPath) then
        logger.info("[FilebrowserPlus] Data path does not exist, creating:", self.filebrowserplus_dataPath)
        os.execute(string.format("mkdir -p %q", self.filebrowserplus_dataPath))
        if util.pathExists(self.filebrowserplus_dataPath) then
            logger.info("[FilebrowserPlus] Created missing data path successfully.")
        else
            logger.info("[FilebrowserPlus] Failed to create data path:", self.filebrowserplus_dataPath)
            UIManager:show(InfoMessage:new{
                icon = "notice-warning",
                text = _("Failed to create data directory. Check path or permissions.")
            })
            return
        end
    end

    if self.allow_no_password then
        local disable_auth_cmd = string.format("%s -d %s -c %s config set --auth.method=noauth", bin_path, db_path,
            config_path) .. silence_cmd
        logger.dbg("set_noauth:", disable_auth_cmd)
        os.execute(disable_auth_cmd)
    else
        local enable_auth_cmd = string.format("%s -d %s -c %s config set --auth.method=json", bin_path, db_path,
            config_path) .. silence_cmd
        logger.dbg("set_auth:", enable_auth_cmd)
        os.execute(enable_auth_cmd)
    end

    local cmd = string.format("nohup %q -a 0.0.0.0 -r %q -p %s -l %q %s & echo $! > %q", bin_path,
        self.filebrowserplus_dataPath, self.filebrowserplus_port, log_path, filebrowser_args, pid_path)

    logger.info("[FilebrowserPlus] Launching Filebrowser:", cmd)
    local status = os.execute(cmd)

    if status == 0 then
        -- Try to get IP address only
        local ip_info = ""
        if Device.retrieveNetworkInfo then
            local net_info = Device:retrieveNetworkInfo()
            if type(net_info) == "table" and net_info.ip then
                ip_info = net_info.ip
            elseif type(net_info) == "string" then
                -- In case the function returns a string (some devices do)
                ip_info = net_info:match("(%d+%.%d+%.%d+%.%d+)") or _("Unknown IP")
            else
                ip_info = _("Unknown IP")
            end
        else
            ip_info = _("Could not retrieve IP address.")
        end

        -- Add default credentials if it's the first setup
        local extra_info = ""
        if self.filebrowserplus_first_setup then
            extra_info = _("\n\nDefault username: admin\nDefault password: admin12345678")
        end

        local info = InfoMessage:new{
            timeout = 15,
            text = T(_("FilebrowserPlus server started.\n\nPort: %1\nIP Address: %2%3"), self.filebrowserplus_port,
                ip_info, extra_info)
        }
        UIManager:show(info)
    else
        local info = InfoMessage:new{
            icon = "notice-warning",
            text = _("Failed to start FilebrowserPlus server.")
        }
        UIManager:show(info)
    end

end

function FilebrowserPlus:isRunning()
    if not util.pathExists(pid_path) then
        local check = os.execute(string.format("pgrep -f '%s' >/dev/null 2>&1", bin_path))
        return check == 0
    end

    local f = io.open(pid_path, "r")
    if not f then
        return false
    end
    local pid = f:read("*n")
    f:close()

    if not pid then
        os.remove(pid_path)
        return false
    end

    -- Check if process with this PID exists
    local check_cmd = string.format("kill -0 %d 2>/dev/null", pid)
    local status = os.execute(check_cmd)
    if status == 0 then
        return true
    else
        -- Cleanup stale PID file
        os.remove(pid_path)
        return false
    end
end

function FilebrowserPlus:stop()
    local cmd = string.format("if [ -f '%s' ]; then kill $(cat '%s') 2>/dev/null; rm -f '%s'; fi", pid_path, pid_path,
        pid_path)
    logger.info("[FilebrowserPlus] Stopping Filebrowser:", cmd)
    local status = os.execute(cmd)

    if status == 0 then
        logger.info("[FilebrowserPlus] Filebrowser stopped.")
        UIManager:show(InfoMessage:new{
            text = _("FilebrowserPlus server stopped."),
            timeout = 2
        })
    else
        logger.info("[FilebrowserPlus] Failed to stop Filebrowser, status:", status)
        UIManager:show(InfoMessage:new{
            icon = "notice-warning",
            text = _("Failed to stop Filebrowser.")
        })
    end

    if Device:isKindle() then
        os.execute(string.format("%s %s %s", "iptables -D INPUT -p tcp --dport", self.filebrowserplus_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s", "iptables -D OUTPUT -p tcp --sport", self.filebrowserplus_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end
end

function FilebrowserPlus:onToggleFilebrowserPlusServer()
    if self:isRunning() then
        self:stop()
    else
        self:start()
    end
end

function FilebrowserPlus:show_port_dialog(touchmenu_instance)
    self.port_dialog = InputDialog:new{
        title = _("Choose FilebrowserPlus port"),
        input = self.filebrowserplus_port,
        input_type = "number",
        input_hint = self.filebrowserplus_port,
        buttons = {{{
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self.port_dialog)
            end
        }, {
            text = _("Save"),
            is_enter_default = true,
            callback = function()
                local value = tonumber(self.port_dialog:getInputText())
                if value and value >= 0 then
                    self.filebrowserplus_port = value
                    G_reader_settings:saveSetting("FilebrowserPlus_port", self.filebrowserplus_port)
                    UIManager:close(self.port_dialog)
                    touchmenu_instance:updateItems()
                end
            end
        }}}
    }
    UIManager:show(self.port_dialog)
    self.port_dialog:onShowKeyboard()
end

function FilebrowserPlus:show_dataPath_dialog(touchmenu_instance)
    self.dataPath_dialog = InputDialog:new{
        title = _("Enter FilebrowserPlus Data Path"),
        input = self.filebrowserplus_dataPath,
        input_type = "text",
        input_hint = "/mnt/us/koreader/books",
        buttons = {{{
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self.dataPath_dialog)
            end
        }, {
            text = _("Save"),
            is_enter_default = true,
            callback = function()
                local value = self.dataPath_dialog:getInputText()
                if value then
                    self.filebrowserplus_dataPath = value
                    G_reader_settings:saveSetting("FilebrowserPlus_dataPath", value)
                    UIManager:close(self.dataPath_dialog)
                    touchmenu_instance:updateItems()
                end
            end
        }}}
    }
    UIManager:show(self.dataPath_dialog)
    self.dataPath_dialog:onShowKeyboard()
end

function FilebrowserPlus:addToMainMenu(menu_items)
    menu_items.filebrowserplus = {
        text = _("FilebrowserPlus"),
        sorting_hint = "network",
        keep_menu_open = true,
        sub_item_table = {{
            text = _("FilebrowserPlus server"),
            checked_func = function()
                return self:isRunning()
            end,
            check_callback_updates_menu = true,
            callback = function(touchmenu_instance)
                self:onToggleFilebrowserPlusServer()
                -- sleeping might not be needed, but it gives the feeling
                -- something has been done and feedback is accurate
                ffiutil.sleep(1)
                touchmenu_instance:updateItems()
            end
        }, {
            text_func = function()
                return T(_("FilebrowserPlus port (%1)"), self.filebrowserplus_port)
            end,
            keep_menu_open = true,
            enabled_func = function()
                return not self:isRunning()
            end,
            callback = function(touchmenu_instance)
                self:show_port_dialog(touchmenu_instance)
            end
        }, {
            text_func = function()
                return T(_("FilebrowserPlus Data Path (%1)"), self.filebrowserplus_dataPath)
            end,
            keep_menu_open = true,
            enabled_func = function()
                return not self:isRunning()
            end,
            callback = function(touchmenu_instance)
                self:show_dataPath_dialog(touchmenu_instance)
            end
        }, {
            text = _("Reset Admin User Password"),
            keep_menu_open = true,
            enabled_func = function()
                return not self:isRunning()
            end,
            callback = function(touchmenu_instance)
                self:resetPassword()
            end
        }, {
            text = _("Login without password (DANGEROUS)"),
            checked_func = function()
                return self.allow_no_password
            end,
            enabled_func = function()
                return not self:isRunning()
            end,
            callback = function()
                self.allow_no_password = not self.allow_no_password
                G_reader_settings:flipNilOrFalse("FilebrowserPlus_allow_no_password")
            end
        }, {
            text = _("Start FilebrowserPlus server with KOReader"),
            checked_func = function()
                return self.autostart
            end,
            enabled_func = function()
                return not self:isRunning()
            end,
            callback = function()
                self.autostart = not self.autostart
                G_reader_settings:flipNilOrFalse("FilebrowserPlus_autostart")
            end
        }}
    }
end

function FilebrowserPlus:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_filebrowserplus_server", {
        category = "none",
        event = "ToggleFilebrowserPlusServer",
        title = _("Toggle FilebrowserPlus server"),
        general = true
    })
end

return FilebrowserPlus
