-- helper methods
-- see if the file exists
local function file_exists(file)
    -- https://stackoverflow.com/questions/11201262/how-to-read-data-from-a-file-in-lua
    local f = io.open(file, "rb")
    if f then f:close() end
    return f ~= nil
end
  
-- get all lines from a file, returns an empty 
-- list/table if the file does not exist
local function lines_from(file)
    -- https://stackoverflow.com/questions/11201262/how-to-read-data-from-a-file-in-lua
    if not file_exists(file) then return {} end
    lines = {}
    for line in io.lines(file) do 
        lines[#lines + 1] = line
    end
    return lines
end

-- check if a string starts with a certain sub-string
local function starts_with(str, start)
    -- http://lua-users.org/wiki/StringRecipes
    return str:sub(1, #start) == start
end

-- create an error alert and exit the dialog
local function create_error(str, dialog)
    app.alert(str)
    dialog:close()
end

-- grab pixel info from the image for the given character
local function get_pixel_data(image, char)
    local idx = string.find(props.alphabet, char) - 1

    -- identify the "letter cell" in the font atlas that we need to scan
    local row = math.floor(idx / props.cols)
    local col = idx % props.cols

    local px_x = col * props.width
    local px_y = row * props.height

    -- now, scan every pixel into a handy table that we can read from later
    local pixels = {}
    for i = 0, (props.height - 1) do -- rows
        pixels[i] = {}
        for j = 0, (props.width - 1) do -- columns
            local newx = px_x + j
            local newy = px_y + i
            pixels[i][j] = image:getPixel(newx, newy)
        end
    end

    return pixels
end

-- write pixel info to an image
local function write_pixel_data(image, x, y, pixels)
    for i = 0, (props.height-1) do
        for j = 0, (props.width-1) do
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
        text=props.sprite
    }

    dialog:modify {
        id="rows_label",
        visible=true,
        text=props.rows
    }

    dialog:modify {
        id="cols_label",
        visible=true,
        text=props.cols
    }

    dialog:modify {
        id="width_label",
        visible=true,
        text=props.width
    }

    dialog:modify {
        id="height_label",
        visible=true,
        text=props.height
    }

    dialog:modify {
        id="no_data_label",
        visible=false
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
    filetypes={ "txt" } 
}

-- read properties in and display to user
dlg:button {
    id = "read",
    text = "Read Properties File",
    focus = false,
    onclick = function()
        local props_filename = dlg.data.props

        -- attempt to load the properties
        if (not file_exists(props_filename)) then
            create_error("Oh no! Error loading the properties file.", dlg)
            return
        end

        local props_lines = lines_from(props_filename)
        for idx, line in pairs(props_lines) do
            if starts_with(line, "alphabet") then
                props.alphabet = string.match(line, "=(.*)")
            elseif starts_with(line, "sprite") then
                props.sprite = string.match(line, "=(.*)")
            elseif starts_with(line, "rows") then
                props.rows = tonumber(string.match(line, "=(.*)"))
            elseif starts_with(line, "cols") then
                props.cols = tonumber(string.match(line, "=(.*)"))
            elseif starts_with(line, "width") then
                props.width = tonumber(string.match(line, "=(.*)"))
            elseif starts_with(line, "height") then
                props.height = tonumber(string.match(line, "=(.*)"))
            else
                create_error("Unknown property: "..line, dlg)
                return
            end
        end

        -- validate all properties exist
        if (props.alphabet == "") or (props.sprite == "") or (props.rows < 1) or (props.cols < 1) or 
           (props.width < 1) or (props.height < 1) then
            create_error("Missing essential property.", dlg)
            return
        end

        -- get the full-file path for the sprite file
        -- the line gets the path separator for the current os. \ for Windows and / for everything else
        local path_sep = ""
        local os_check = os.getenv("HOME")
		if (os_check ~= nil) then
            -- Unix-based Systems
            path_sep = "/"
        else
            -- Windows
            path_sep = "\\"
        end

        -- sprite filepath can be absolute
        local full_path = props.sprite
        -- if the filename is relative, try to find it in the same directory as the properties file
        if (not string.find(props.sprite, path_sep)) then
            full_path = string.match(props_filename, ".*"..path_sep)
            props.sprite = full_path..props.sprite
        end

        -- check for existence
        if (not file_exists(props.sprite)) then
            create_error("Oh no! I could not find the sprite file on the file system.", dlg)
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
    onclick = function()
        local text = dlg.data.text

        -- validate the text field is not blank
        if (text == "") then
            create_error("Oh no! The text field was left blank.", dlg)
            return
        end

        -- validate the text does not use any characters not defined in the alphabet
        for char in text:gmatch"." do
            if (not string.find(props.alphabet, char)) then
                create_error("Oh no! Text has characters not defined by the alphabet.", dlg)
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
        local font_sprite = app.open(props.sprite)
        -- flatten the sprite so it only has 1 layer
        font_sprite:flatten()
        local font_image = font_sprite.layers[1]:cel(1).image

        -- paint every character in the text string to the destination image
        for i = 1, #text do
            -- get the pixels to paint onto the new image
            local char = text:sub(i, i)
            local pixels = get_pixel_data(font_image, char)

            local x = 5 + ((i-1) * props.width)
            local y = 5

            -- paint them on the new image
            write_pixel_data(img_image, x, y, pixels)
        end

        -- wrap up the dialog
        font_sprite:close() -- THIS DOES NOT SAVE THE SPRITE (which is what we want)
        dlg:close()
    end
}


-- always give the user a way to exit
local function cancelWizard(dlg)
    dlg:close()
end

-- display the dialog to the user
dlg:show{ wait=false, bounds=Rectangle{dlg.bounds.x, dlg.bounds.y, 300, dlg.bounds.height} }