-- import libraries
local json_lib_path = app.fs.joinPath(app.fs.userConfigPath, "extensions", "font-custom", "json.lua")
json = dofile(json_lib_path)

-- helper methods
-- get everything from a file, returns an empty string if the file does not exist
local function file_to_str(filename)
    if not app.fs.isFile(filename) then return "" end
    local file = io.open(filename)
    local str = file:read("*a")
    file:close()
    return str
end

-- create an error alert and exit the dialog
local function create_error(str, dialog, exit)
    app.alert(str)
    if (exit == 1) then dialog:close() end
end

-- grab pixel info from the image for the given character
local function get_pixel_data(image, char)
    -- check if the character is a space
    if (char == " ") then return {} end

    local idx = string.find(props.alphabet, char) - 1

    -- identify the "letter cell" in the font atlas that we need to scan
    local row = math.floor(idx / props.atlas.cols)
    local col = idx % props.atlas.cols

    local px_x = col * props.atlas.default_width
    local px_y = row * props.atlas.default_height

    -- now, scan every pixel into a handy table that we can read from later
    local pixels = {}
    for i = 0, (props.atlas.default_height - 1) do -- rows
        pixels[i] = {}
        for j = 0, (props.atlas.default_width - 1) do -- columns
            local newx = px_x + j
            local newy = px_y + i
            pixels[i][j] = image:getPixel(newx, newy)
        end
    end

    return pixels
end

-- write pixel info to an image
local function write_pixel_data(image, x, y, pixels)
    for i = 0, #pixels do
        if not pixels[i] then break end
        for j = 0, #pixels[i] do
            image:drawPixel(j + x, i + y, pixels[i][j])
        end
    end
end

local function update_dialog_with_props(dialog)
    dialog:modify {
        id="alphabet_label",
        visible=true,
        text=props.alphabet
    }

    dialog:modify {
        id="sprite_label",
        visible=true,
        text=props.sprite_path
    }

    dialog:modify {
        id="rows_label",
        visible=true,
        text=props.atlas.rows
    }

    dialog:modify {
        id="cols_label",
        visible=true,
        text=props.atlas.cols
    }

    dialog:modify {
        id="width_label",
        visible=true,
        text=props.atlas.default_width
    }

    dialog:modify {
        id="height_label",
        visible=true,
        text=props.atlas.default_height
    }

    dialog:modify {
        id="no_data_label",
        visible=false
    }

    dialog:modify {
        id="ok",
        enabled=true
    }
end

-- properties object to be used later
props = {
    alphabet={},
    sprite="",
    rows=0,
    cols=0,
    width=0,
    height=0
}

-- declare the dialog object
dlg = Dialog("Use Custom Pixel Font")

-- populate dialog object
-- properties file
dlg:file {
    id="props",
    label="Open Properties File",
    title="Properties File",
    open=true,
    filetypes={ "json" } 
}

-- read properties in and display to user
dlg:button {
    id = "read",
    text = "Read Properties File",
    focus = false,
    onclick = function()
        local props_filename = dlg.data.props

        -- attempt to load the properties
        if (not app.fs.isFile(props_filename)) then
            create_error("Oh no! Error loading the properties file.", dlg, 0)
            return
        end

        -- read and parse the file
        local json_str = file_to_str(props_filename)
        if (json_str == "") then 
            create_error("Oh no! Error reading the properties file.", dlg, 0)
            return
        end

        props = json.decode(json_str)

        -- validate all properties exist
        if (props.alphabet == "") then
            create_error("Missing an essential property: alphabet", dlg, 0)
            return
        end

        if (props.sprite_path == "") then
            create_error("Missing an essential property: sprite", dlg, 0)
            return
        end

        if (props.atlas.rows < 0) then
            create_error("Missing an essential property: rows", dlg, 0)
            return
        end

        if (props.atlas.cols < 0) then
            create_error("Missing an essential property: cols", dlg, 0)
            return
        end

        if (props.atlas.default_width < 0) then
            create_error("Missing an essential property: width", dlg, 0)
            return
        end

        if (props.atlas.default_height < 0) then
            create_error("Missing an essential property: height", dlg, 0)
            return
        end

        -- if the filename is relative, try to find it in the same directory as the properties file
        if (not string.find(props.sprite_path, app.fs.pathSeparator)) then
            local full_path = app.fs.joinPath(app.fs.filePath(props_filename), props.sprite_path)
            props.sprite_path = full_path
        end

        -- check for existence
        if (not app.fs.isFile(props.sprite_path)) then
            create_error("No sprite file found at location: "..props.sprite_path, dlg, 0)
            return
        end

        -- update dialog with prop values
        update_dialog_with_props(dlg)
    end
}

-- separator
dlg:separator { id="props_separator" }

-- properties displayed back to user after reading props file
dlg:label {
    id="alphabet_label",
    label="Alphabet:",
    visible=false,
    text=""
}

dlg:label {
    id="sprite_label",
    label="Sprite filepath:",
    visible=false,
    text=""
}

dlg:label {
    id="rows_label",
    label="# of rows:",
    visible=false,
    text=""
}

dlg:label {
    id="cols_label",
    label="# of columns:",
    visible=false,
    text=""
}

dlg:label {
    id="width_label",
    label="Width of each letter:",
    visible=false,
    text=""
}

dlg:label {
    id="height_label",
    label="Height of each letter:",
    visible=false,
    text=""
}

dlg:label {
    id="no_data_label",
    label="No data present:",
    visible=true,
    text="Read in properties file first."
}

-- separator
dlg:separator { id="text_separator" }

-- text to draw to screen
dlg:entry {
    id="text",
    label="Text:",
    text="",
    focus=false
}

-- OK button to execute logic
dlg:button { 
    id = "ok",
    text = "OK",
    focus = false,
    enabled = false,
    onclick = function()
        app.transaction( function()
            local text = dlg.data.text

            -- validate the text field is not blank
            if (text == "") then
                create_error("Oh no! The text field was left blank.", dlg, 0)
                return
            end
    
            -- validate the text does not use any characters not defined in the alphabet
            for char in text:gmatch"." do
                if (not string.find(props.alphabet, char)) and (char ~= " ") then
                    create_error("Oh no! Text has characters not defined by the alphabet.", dlg, 0)
                    return
                end
            end
    
            -- save the current sprite into a variable so we can manipulate it later
            local img_sprite = app.activeSprite
            local layer = img_sprite:newLayer()
            layer.name = "CUSTOM TEXT"
            local img_cel = img_sprite:newCel(layer, app.activeFrame)
            local img_image = img_cel.image
    
            -- open the sprite
            local font_sprite = app.open(props.sprite_path)
            -- flatten the sprite so it only has 1 layer
            font_sprite:flatten()
            local font_image = font_sprite.layers[1]:cel(1).image
    
            -- paint every character in the text string to the destination image
            for i = 1, #text do
                -- get the pixels to paint onto the new image
                local char = text:sub(i, i)
                local pixels = get_pixel_data(font_image, char)
    
                local x = 0 + ((i-1) * props.atlas.default_width)
                local y = 0
    
                -- paint them on the new image
                write_pixel_data(img_image, x, y, pixels)
            end
    
            -- wrap up the dialog
            font_sprite:close() -- THIS DOES NOT SAVE THE SPRITE (which is what we want)
            dlg:close()
        end)
    end
}


-- always give the user a way to exit
local function cancelWizard(dlg)
    dlg:close()
end

-- show to grab centered coordinates
dlg:show{ wait=false }

-- quickly swap out the coords so we can force a larger width
local x = (dlg.bounds.x - math.floor(450 / 4))
local y = dlg.bounds.y
local width = 400
local height = dlg.bounds.height

dlg.bounds = Rectangle{x, y, width, height}
