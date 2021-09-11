function init(plugin)
    print("Aseprite is initializing Font Custom")
  
    plugin:newCommand {
        id="Custom Font",
        title="Use Custom Font",
        group="edit_fx",
        onclick=function()
            local executable = app.fs.joinPath(app.fs.userConfigPath, "extensions", "font-custom", "font-custom.lua")
            dofile(executable)
        end
    }
end
  
function exit(plugin)
    print("Aseprite is closing Font Custom")
end