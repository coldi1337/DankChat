-- Load after the general DMS window rules to allow DankChat to tile.
hl.window_rule({
    name = "dankchat-tiling",
    match = { class = "^com\\.danklinux\\.dms$", title = "^DankChat$" },
    float = false,
})
