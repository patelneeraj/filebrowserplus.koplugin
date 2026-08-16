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
local TouchMenu = require("ui/widget/touchmenu")
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
    self.auto_stop_minutes = G_reader_settings:readSetting("FilebrowserPlus_auto_stop_minutes") or 30
    self.auto_stop_task = function()
        self:checkAutoStop()
    end
    self.auto_stop_scheduled = false
    if self.autostart then
        logger.info("[FilebrowserPlus] Autostart enabled, starting server on port " .. self.filebrowserplus_port)
        self:start()
    end

    -- Restore auto-stop timer if server is running (e.g. after KOReader restart)
    -- This resets the timer to the full duration
    if self:isRunning() and self.auto_stop_minutes > 0 and not self.auto_stop_scheduled then
        logger.info("[FilebrowserPlus] Server found running, restoring auto-stop timer.")
        self.stop_deadline = os.time() + (self.auto_stop_minutes * 60)
        self:checkAutoStop()
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

    if Device:isKindle() then
        os.execute(string.format("%s %s %s", "iptables -A INPUT -p tcp --dport", self.filebrowserplus_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s", "iptables -A OUTPUT -p tcp --sport", self.filebrowserplus_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    if self:isRunning() then
        logger.dbg("[FilebrowserPlus] Not starting FilebrowserPlus, already running.")
        return
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
                text = _("Failed to create data directory.\n" .. "Please check the path or permissions.\n\n" ..
                             "Note: On Kindle, only locations under /mnt/us are writable.\n" ..
                             "On Kobo, only locations under /mnt/onboard are writable.")
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
        -- Add default credentials if it's the first setup
        local extra_info = ""
        local timeout_duration = 3
        if self.filebrowserplus_first_setup then
            extra_info = _("\n\nDefault username: admin\nDefault password: admin12345678")
            timeout_duration = 15
        end

        local auto_stop_msg = ""
        if self.auto_stop_minutes and self.auto_stop_minutes > 0 then
            auto_stop_msg = "\n" .. T(_("Auto-stop in %1 min"), self.auto_stop_minutes)
        end

        local info = InfoMessage:new{
            timeout = timeout_duration,
            text = _("FilebrowserPlus server started.") .. auto_stop_msg .. extra_info
        }
        UIManager:show(info)
        
        -- Schedule auto-stop if configured
        if self.auto_stop_minutes and self.auto_stop_minutes > 0 then
            self.stop_deadline = os.time() + (self.auto_stop_minutes * 60)
            self:checkAutoStop()
            logger.info("[FilebrowserPlus] Auto-stop scheduled in " .. self.auto_stop_minutes .. " minutes (Deadline: " .. os.date("%c", self.stop_deadline) .. ").")
        end
    else
        local info = InfoMessage:new{
            icon = "notice-warning",
            timeout = 15,
            text = _("Failed to start FilebrowserPlus server")
        }
        UIManager:show(info)
    end

end

function FilebrowserPlus:checkAutoStop()
    if not self:isRunning() then
        self.auto_stop_scheduled = false
        return
    end

    if not self.stop_deadline then
        self.auto_stop_scheduled = false
        return
    end

    if os.time() >= self.stop_deadline then
        logger.info("[FilebrowserPlus] Auto-stop timer expired, stopping server.")
        self.auto_stop_scheduled = false
        self:stop(true)
        UIManager:show(InfoMessage:new{
            text = _("FilebrowserPlus server auto-stopped after timeout"),
            timeout = 3
        })
    else
        local remaining = self.stop_deadline - os.time()
        local next_check = math.min(60, math.max(1, remaining))
        self.auto_stop_scheduled = true
        UIManager:scheduleIn(next_check, self.auto_stop_task)
    end
end

function FilebrowserPlus:isRunning()
    if not util.pathExists(pid_path) then
        return false
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

function FilebrowserPlus:stop(is_auto)
    -- Cancel auto-stop timer if running
    if self.auto_stop_scheduled and self.auto_stop_task then
        UIManager:unschedule(self.auto_stop_task)
        self.auto_stop_scheduled = false
    end
    self.stop_deadline = nil    
    
    local cmd = string.format("if [ -f '%s' ]; then kill $(cat '%s') 2>/dev/null; rm -f '%s'; fi", pid_path, pid_path,
        pid_path)
    logger.info("[FilebrowserPlus] Stopping Filebrowser:", cmd)
    local status = os.execute(cmd)

    if status == 0 then
        logger.info("[FilebrowserPlus] Filebrowser stopped.")
        if not is_auto then
            UIManager:show(InfoMessage:new{
                text = _("FilebrowserPlus server stopped."),
                timeout = 3
            })
        end

        if Device:isKindle() then
            os.execute(string.format("%s %s %s", "iptables -D INPUT -p tcp --dport", self.filebrowserplus_port,
                "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
            os.execute(string.format("%s %s %s", "iptables -D OUTPUT -p tcp --sport", self.filebrowserplus_port,
                "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
        end
    else
        logger.info("[FilebrowserPlus] Failed to stop Filebrowser, status:", status)
        UIManager:show(InfoMessage:new{
            icon = "notice-warning",
            timeout = 15,
            text = _("Failed to stop Filebrowser")
        })
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

function FilebrowserPlus:getIPAddress()
    if Device.retrieveNetworkInfo then
        local net_info = Device:retrieveNetworkInfo()
        if type(net_info) == "table" and net_info.ip then
            return net_info.ip
        elseif type(net_info) == "string" then
            return net_info:match("(%d+%.%d+%.%d+%.%d+)") or nil
        end
    end
    return nil
end

function FilebrowserPlus:show_autostop_dialog(touchmenu_instance)
    self.autostop_dialog = InputDialog:new{
        title = _("Auto-stop timeout (min)"),
        description = _("Set to 0 to disable"),
        input = tostring(self.auto_stop_minutes),
        input_type = "number",
        buttons = {{{
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self.autostop_dialog)
            end
        }, {
            text = _("Save"),
            is_enter_default = true,
            callback = function()
                local value = tonumber(self.autostop_dialog:getInputText())
                if value and value >= 0 then
                    self.auto_stop_minutes = value
                    G_reader_settings:saveSetting("FilebrowserPlus_auto_stop_minutes", value)
                    UIManager:close(self.autostop_dialog)
                    touchmenu_instance:updateItems()
                end
            end
        }}}
    }
    UIManager:show(self.autostop_dialog)
    self.autostop_dialog:onShowKeyboard()
end

function FilebrowserPlus:addToMainMenu(menu_items)
    local sub_item_table = {{
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
    }, {
        text_func = function()
            if self.auto_stop_minutes and self.auto_stop_minutes > 0 then
                return T(_("Auto-stop timeout (%1 min)"), self.auto_stop_minutes)
            else
                return _("Auto-stop timeout (disabled)")
            end
        end,
        keep_menu_open = true,
        enabled_func = function()
            return not self:isRunning()
        end,
        callback = function(touchmenu_instance)
            self:show_autostop_dialog(touchmenu_instance)
        end
    }}

    menu_items.filebrowserplus = {
        text_func = function()
            if self:isRunning() then
                local ip = self:getIPAddress()
                if ip then
                    return T(_("FilebrowserPlus (%1:%2)"), ip, self.filebrowserplus_port)
                else
                    return T(_("FilebrowserPlus (:%1)"), self.filebrowserplus_port)
                end

            else
                return _("FilebrowserPlus (Long press for settings)")
            end
        end,
        sorting_hint = "network",
        keep_menu_open = true,
        checked_func = function()
            return self:isRunning()
        end,
        callback = function(touchmenu_instance)
            self:onToggleFilebrowserPlusServer()
            ffiutil.sleep(1)
            touchmenu_instance:updateItems()
        end,
        hold_keep_menu_open = true,
        hold_callback = function(touchmenu_instance)
            local dummy_item = {
                text = _("FilebrowserPlus settings"),
                sub_item_table = sub_item_table
            }
            if touchmenu_instance.onMenuSelect then
                touchmenu_instance:onMenuSelect(dummy_item)
            else
                local submenu = TouchMenu:new{
                    title = _("FilebrowserPlus settings"),
                    item_table = sub_item_table,
                    parent = touchmenu_instance,
                }
                UIManager:show(submenu)
            end
        end
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
