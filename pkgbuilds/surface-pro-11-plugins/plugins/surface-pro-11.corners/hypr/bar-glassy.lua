-- Installed by the Corners plugin while the bar is glassy, and removed when it
-- is not. The bar fills share the bar's layer, and xray blurs only the
-- wallpaper behind it, so windows and the bar itself don't bleed into the
-- fills' blur and they match the bar.
hl.layer_rule({
  match = { namespace = "^omarchy-bar$" },
  xray = true,
})
