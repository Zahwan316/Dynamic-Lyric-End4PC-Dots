hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Batalkan toggle search/overview saat SUPER dipakai sebagai kombinasi.
-- Hyprland 0.57 mengirim event release shortcut global lewat release callback,
-- jadi old interrupt `SUPER, catchall` tidak lagi jalan. Kita daftarkan per key.
local function superComboInterrupt()
    hl.dispatch(hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
end

for code = 9, 255 do
    if code ~= 133 and code ~= 134 then -- skip SUPER_L / SUPER_R
        hl.bind("SUPER + code:" .. code, superComboInterrupt,
            { ignore_mods = true, transparent = true, non_consuming = true })
    end
end

for _, mouse in ipairs({ "mouse:272", "mouse:273", "mouse:274", "mouse:275", "mouse:276", "mouse_up", "mouse_down" }) do
    hl.bind("SUPER + " .. mouse, superComboInterrupt,
        { ignore_mods = true, transparent = true, non_consuming = true })
end
