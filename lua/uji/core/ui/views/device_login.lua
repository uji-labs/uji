local class = require("uji.core.class")
local ito = require("ito")
local Modal = require("uji.core.ui.views.modal")
local Notice = require("uji.core.ui.transcript.notice")

local DeviceLogin = class(Modal)

DeviceLogin.takeover = true

function DeviceLogin:init(flow)
    Modal.init(self)
    self.url = flow.url
    self.code = flow.code
end

function DeviceLogin:accept() end

function DeviceLogin:view()
    local styles = ito.theme().styles
    return ito.VStack({
        ito.Text("Sign in with device code"):style(styles.confirm_title):wrap(),
        Notice({ text = "Open " .. self.url }),
        ito.Text("Enter this code:"):wrap(),
        ito.Text(self.code):style(styles.confirm_title):wrap(),
        ito.Text("Waiting for sign-in. Esc cancels."):style(styles.dim):wrap(),
    }):padding({ horizontal = 2, vertical = 1 })
end

return DeviceLogin
