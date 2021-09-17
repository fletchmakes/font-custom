-- MIT License

-- Copyright (c) 2021 David Fletcher

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

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

-- return the index for a character (or nil if no index found)
-- unfortunately we have to brute-force this one since string.find doesn't work
-- as desired if we pass it a special pattern char like . % {} etc
local function find_char_idx(str, search_char)
    for i = 1, #str do
        local char = str:sub(i, i)
        if (search_char == char) then
            return i
        end
    end

    return nil
end

-- create an error alert and exit the dialog
local function create_error(str, dialog, exit)
    app.alert(str)
    if (exit == 1) then dialog:close() end
end

-- create a confirmation dialog and wait for the user to confirm
local function create_confirm(str)
    local confirm = Dialog("Confirm?")

    confirm:label {
        id="text",
        text=str
    }

    confirm:button {
        id="cancel",
        text="Cancel",
        onclick=function()
            confirm:close()
        end
    }

    confirm:button {
        id="confirm",
        text="Confirm",
        onclick=function()
            confirm:close()
        end
    }

    -- always give the user a way to exit
    local function cancelWizard(confirm)
        confirm:close()
    end

    -- show to grab centered coordinates
    confirm:show{ wait=true }

    return confirm.data.confirm
end

-- get the calculated pixel width of the text string
local function get_text_pixel_width(str)
    local last_char = ""
    local len = 0
    -- it might seem strange that we iterate until 1 past the string length
    -- however, we need to ensure that the accumulator includes with width of last_char
    -- this is a slightly hacky way to do so
    for i = 1, (#str+1) do
        -- get the pixels to paint onto the new image
        local char = ""
        if (i <= #str) then char = str:sub(i, i) end

        -- shift our 'cursor' over to get ready for the next letter
        if (last_char ~= "") then 
            -- if the character has a special width value, use that instead
            if (props.atlas.character_widths[last_char] ~= nil) then
                len = len + props.atlas.character_widths[last_char] + props.default_spacing
            else
                len = len + props.atlas.common_width + props.default_spacing
            end
            -- add the kerning value if the current character has a special pairing with the previous
            if (props.kerning[last_char] ~= nil) then
                if (string.find(props.kerning[last_char].paired_with, char)) then
                    len = len + props.kerning[last_char].spacing
                end
            end
        end

        -- remember the last character we scanned
        last_char = char
    end

    -- get the last_char's width and add that to the accumulator
    return len 
end

-- grab pixel info from the image for the given character
local function get_pixel_data(image, char)
    -- check if the character is a space
    if (char == " ") then return {} end

    local idx = find_char_idx(props.alphabet, char) - 1

    if (idx == nil) then create_error("Oh no! Could not find character in alphabet.", dlg, 1) end

    -- identify the "letter cell" in the font atlas that we need to scan
    local row = math.floor(idx / props.atlas.cols)
    local col = idx % props.atlas.cols

    local px_x = col * props.atlas.grid_width
    local px_y = row * props.atlas.grid_height

    -- now, scan every pixel into a handy table that we can read from later
    local pixels = {}
    for i = 0, (props.atlas.grid_height - 1) do -- rows
        pixels[i] = {}
        for j = 0, (props.atlas.grid_width - 1) do -- columns
            local newx = px_x + j
            local newy = px_y + i
            if (newx >= image.width) or (newy >= image.height) then
                break
            end
            pixels[i][j] = image:getPixel(newx, newy)
        end
    end

    return pixels
end

-- write pixel info to an image
local function write_pixel_data(image, x, y, pixels)
    for i = 0, #pixels do -- rows
        if (not pixels[i]) then break end
        for j = 0, #pixels[i] do -- columns
            if (not pixels[i][j]) then break end
            image:drawPixel(j + x, i + y, pixels[i][j])
        end
    end
end

-- data validation
local function validate_char_width_prop(prop)
    local err = nil
    for key, val in pairs(prop) do
        -- each key should be a single character long
        if (#key > 1) then
            err = "Key \""..key.."\" is too long. It must specify one character only."
            break
        end
        -- each value should be an integer
        if (type(val) ~= "number") then
            err = "Value "..val.." (key \""..key.."\") must be an integer (with no decimal places)."
            break
        else
            -- modf returns a tuple; integer, fractional (parts of the number)
            local i, f = math.modf(val)
            if (f ~= 0) then
                err = "Value "..val.." (key \""..key.."\") must be an integer (with no decimal places)."
                break
            end
        end
    end

    return err
end

local function validate_kerning_prop(prop)
    local err = nil
    for key, val in pairs(prop) do
        -- each key should be a single character long
        if (#key > 1) then
            err = "Key \""..key.."\" is too long. It must specify one character only."
            break
        end
        -- each value should be an object with keys "paired_with" and "spacing"
        if (type(val) ~= "table") then
            err = "Value with key \""..key.."\" is not an object {}."
            break
        else
            -- validate that "paired_with" and "spacing" exist and are properly formatted
            if (val.paired_with == nil) then
                err = "Object with key \""..key.."\" is missing the \"paired_with\" property."
                break
            elseif (type(val.paired_with) ~= "string") then
                err = "Object with key \""..key.."\"'s \"paired_with\" property is formatted incorrectly."
                break
            end

            if (val.spacing == nil) then
                err = "Object with key \""..key.."\" is missing the \"spacing\" property."
                break
            elseif (type(val.spacing) ~= "number") then
                err = "Object with key \""..key.."\"'s \"spacing\" property must be an integer (with no decimal places)."
                break
            else
                -- modf returns a tuple; integer, fractional (parts of the number)
                local i, f = math.modf(val.spacing)
                if (f ~= 0) then
                    err = "Object with key \""..key.."\"'s \"spacing\" property must be an integer (with no decimal places)."
                    break
                end
            end
        end
    end

    return err
end

-- now that we've read in properties, update the dialog to allow the user to continue
local function update_dialog_with_props(dialog, success)
    dialog:modify {
        id="properties_label",
        text="Properties read in successfully!"
    }

    dialog:modify {
        id="text",
        enabled=true
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
    id="read",
    text="Read Properties File",
    focus=false,
    onclick=function()
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

        local status, val = pcall(json.decode, json_str)
        if (not status) then create_error(val, dlg, 0) return
        else props = val end

        -- validate all essential properties exist
        if (not props.alphabet) or (props.alphabet == "") then
            create_error("Missing an essential property: alphabet", dlg, 0)
            return
        end

        if (not props.sprite_path) or (props.sprite_path == "") then
            create_error("Missing an essential property: sprite_path", dlg, 0)
            return
        end

        local checkExt = app.fs.fileExtension(props.sprite_path)
        if (checkExt ~= "png") and (checkExt ~= "aseprite") and (checkExt ~= "ase") then
            create_error("Sprite in .json must have one of the following extensions: .png, .ase, .aseprite")
            return
        end

        if (not props.atlas) then
            create_error("Missing an essential object: atlas", dlg, 0)
            return
        end

        if (not props.atlas.rows) or (props.atlas.rows < 0) then
            create_error("Missing an essential property: atlas.rows", dlg, 0)
            return
        end

        if (not props.atlas.cols) or (props.atlas.cols < 0) then
            create_error("Missing an essential property: atlas.cols", dlg, 0)
            return
        end

        if (not props.atlas.grid_width) or (props.atlas.grid_width < 0) then
            create_error("Missing an essential property: atlas.grid_width", dlg, 0)
            return
        end

        if (not props.atlas.grid_height) or (props.atlas.grid_height < 0) then
            create_error("Missing an essential property: atlas.grid_height", dlg, 0)
            return
        end

        -- default certain values so that we don't hit undefined errors
        if (props.atlas.common_width == nil) then
            props.atlas.common_width = props.atlas.grid_width
        end

        if (props.atlas.character_widths == nil) then
            props.atlas.character_widths = {}
        else
            local err = validate_char_width_prop(props.atlas.character_widths)
            if (err) then
                create_error(err, dlg, 0)
                return
            end
        end

        if (props.default_spacing == nil) then
            props.default_spacing = 1
        end

        if (props.kerning == nil) then
            props.kerning = {}
        else
            local err = validate_kerning_prop(props.kerning)
            if (err) then
                create_error(err, dlg, 0)
                return
            end
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

dlg:label {
    id="properties_label",
    label="Properties:",
    visible=true,
    text="No properties found. Read in file first."
}

-- separator
dlg:separator { id="text_separator" }

-- text to draw to screen
dlg:entry {
    id="text",
    label="Text:",
    text="",
    focus=false,
    enabled=false
}

-- OK button to execute logic
dlg:button { 
    id="ok",
    text="OK",
    focus=false,
    enabled=false,
    onclick=function()
        app.transaction( function()
            local text = dlg.data.text

            -- validate the text field is not blank
            if (text == "") then
                create_error("Oh no! The text field was left blank.", dlg, 0)
                return
            end
    
            -- validate the text does not use any characters not defined in the alphabet
            for char in text:gmatch"." do
                if (not find_char_idx(props.alphabet, char)) and (char ~= " ") then
                    create_error("Oh no! Text has characters not defined by the alphabet.", dlg, 0)
                    return
                end
            end

            -- do math to center the text within the destination image
            local text_width = get_text_pixel_width(text)
            local text_height = props.atlas.grid_height
            local img_sprite = app.activeSprite

            local continue = true
            if (text_width > img_sprite.width) or (text_height > img_sprite.height) then
                -- if the text wouldn't fit, ask if they would like to continue anyways
                continue = create_confirm("The text won't fit on the canvas, and will be clipped. Would you like to continue anyways?")
            end
    
            if (continue) then
                -- save the current sprite into a variable so we can manipulate it later
                local layer = img_sprite:newLayer()
                layer.name = "CUSTOM TEXT"
                local img_cel = img_sprite:newCel(layer, app.activeFrame)
                local img_image = img_cel.image
        
                -- open the sprite
                local font_sprite = app.open(props.sprite_path)
                -- flatten the sprite so it only has 1 layer
                font_sprite:flatten()
                -- however, flattening also "trims" the image to the smallest available size
                -- we need to resize the image again back to the full height / width of the canvas
                local font_image = font_sprite.layers[1]:cel(1).image

                local x = math.floor( (img_image.width - text_width) / 2 )
                local y = math.floor( (img_image.height - text_height) / 2 )
                local last_char = ""
                -- paint every character in the text string to the destination image
                for i = 1, #text do
                    -- get the pixels to paint onto the new image
                    local char = text:sub(i, i)
                    local pixels = get_pixel_data(font_image, char)
        
                    -- shift our 'cursor' over to get ready for the next letter
                    if (last_char ~= "") then 
                        -- if the character has a special width value, use that instead
                        if (props.atlas.character_widths[last_char] ~= nil) then
                            x = x + props.atlas.character_widths[last_char] + props.default_spacing
                        else
                            x = x + props.atlas.common_width + props.default_spacing
                        end
                        -- add the kerning value if the current character has a special pairing with the previous
                        if (props.kerning[last_char] ~= nil) then
                            if (string.find(props.kerning[last_char].paired_with, char)) then
                                x = x + props.kerning[last_char].spacing
                            end
                        end
                    end
                        
                    -- paint them on the new image
                    write_pixel_data(img_image, x, y, pixels)
                    
                    -- remember the last character we printed
                    last_char = char
                end

                font_sprite:close() -- THIS DOES NOT SAVE THE SPRITE (which is what we want)
            end

            -- wrap up the dialog
            app.activeSprite = img_sprite
            dlg:close()
        end ) -- end transaction
    end
}


-- always give the user a way to exit
local function cancelWizard(dlg)
    dlg:close()
end

-- show to grab centered coordinates
dlg:show{ wait=false }
