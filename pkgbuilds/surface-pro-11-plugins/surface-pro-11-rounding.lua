-- Surface Pro 11: round windows to match the display's rounded corners, in
-- every theme. The Rounded corners plugin follows this radius.
--
-- Copied here once by surface-pro-11-plugins. Delete this file to go back to
-- the theme's own corners; it is not copied again. Settings in your own
-- ~/.config/hypr files load after this one and win.
hl.config({
  decoration = {
    rounding = 12,
    -- A circular arc, like the panel's corners. Some themes set a much higher
    -- power, which flattens the corner almost square.
    rounding_power = 2.0,
  },
})
