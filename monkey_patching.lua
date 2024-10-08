--
-- fs51 - Compatibility layer for Minetest formspecs
--
-- Copyright © 2021 by luk3yx.
--

fs51.monkey_patching_enabled = true

local fixers = ...
local get_player_information, type = minetest.get_player_information, type
local function remove_hypertext(text)
    -- If the text doesn't contain backslashes use gsub for performance
    if not text:find('\\', 1, true) then
        return text:gsub('<[^>]+>', '')
    end

    -- Otherwise iterate over it
    local res = ''
    local escaping, ignoring
    for i = 1, #text do
        local char = text:sub(i, i)
        if ignoring then
            ignoring = char ~= '>'
        elseif escaping then
            res = res .. char
            escaping = false
        elseif char == '<' then
            ignoring = true
        elseif char == '\\' then
            escaping = true
        else
            res = res .. char
        end
    end
    return res
end

local FIELD_PREFIX = "_*fs51*"

-- Backport index_event by modifying the dropdown items so that they all start
-- with \x1b(fs51@idx_<N>). This is then parsed out here if the player has been
-- shown any formspec with a dropdown that has index_event. The extra check is
-- done to prevent trying to parse every single field for every single player.
local fields_transform_enabled = {}
minetest.after(0, minetest.register_on_player_receive_fields,
        function(player, _, fields)
    local name = player:get_player_name()
    if not fields_transform_enabled[name] then return end

    local to_update = {}
    for field, raw_value in pairs(fields) do
        if field:sub(1, #FIELD_PREFIX) == FIELD_PREFIX then
            -- The leading escape character may be stripped by the engine
            local new_value = raw_value:match("^\27*%(fs51@idx_([0-9]+)%)")
            if new_value then
                to_update[field] = new_value
            else
                -- Show a fallback open URL dialog
                local url, v = raw_value:match("^\27*%(fs51@url_([^%)]+)%)(.+)")
                if url then
                    to_update[field] = v
                    fields.quit = "true"

                    minetest.show_formspec(name, "fs51:url",
                        "formspec_version[4]" ..
                        "size[10.5,3.3]" ..
                        "label[0.3,0.5;Open URL]" ..
                        "field[0.3,1.2;9.9,0.8;u;Paste the below URL into " ..
                            "your web browser;" ..
                            minetest.formspec_escape(url) .. "]" ..
                        "button_exit[0.3,2.2;9.9,0.8;done;Done]")
                end
            end
        end
    end

    for field, value in pairs(to_update) do
        fields[field] = nil
        fields[field:sub(#FIELD_PREFIX + 1)] = value
    end
end)

minetest.register_on_leaveplayer(function(player)
    fields_transform_enabled[player:get_player_name()] = nil
end)

local function backport_for(name, formspec)
    local info = get_player_information(name)
    local formspec_version = info and info.formspec_version or 1
    local protocol_version = info and info.protocol_version or 0
    -- The protocol version is needed to detect MT 5.9.0
    if formspec_version >= 8 or protocol_version >= 44 then return formspec end

    local tree, err = formspec_ast.parse(formspec)
    if not tree then
        minetest.log('warning', '[fs51] Error parsing formspec (in ' ..
            'monkey_patching.lua): ' .. tostring(err))
        return formspec
    end

    -- Add some placeholders
    local modified
    for node in formspec_ast.walk(tree) do
        local node_type = node.type
        if (node_type == "button_url" or node_type == "button_url_exit") and
                formspec_version < 8 and protocol_version < 44 then
            -- Replace URL buttons with a fallback
            fields_transform_enabled[name] = true

            modified = true
            node.type = "button"
            node.name = FIELD_PREFIX .. node.name
            -- Deprecated in later MT versions, but that shouldn't matter as
            -- this only gets sent to old clients
            node.label = "\27(fs51@url_" .. node.url:gsub("%)", "%%29") ..
                ")" .. node.label
        elseif node_type == "dropdown" and formspec_version < 4 and
                node.index_event and node.items then
            -- Enable the field value transforming hack for this player
            fields_transform_enabled[name] = true

            modified = true
            node.name = "_*fs51*" .. node.name
            for i, item in ipairs(node.items) do
                node.items[i] = "\27(fs51@idx_" .. i .. ")" .. item
            end
            node.index_event = nil
        elseif formspec_version >= 3 then  -- luacheck: ignore 542
            -- Don't do anything else
        elseif formspec_version == 1 and node_type == 'background9' then
            -- No need to set modified here
            node.type = 'background'
            node.middle_x, node.middle_y = nil, nil
            node.middle_x2, node.middle_y2 = nil, nil
        elseif node_type == 'animated_image' then
            modified = true
            node.type = 'image'
            local frame_start = node.frame_start or 1
            node.texture_name = ('(%s)^[verticalframe:%d:%d'):format(
                node.texture_name, node.frame_count, frame_start - 1)
        elseif node_type == 'model' and node.textures[1] then
            modified = true
            node.type = 'image'
            node.texture_name = node.textures[1]
        elseif node_type == 'hypertext' then
            -- Convert hypertext elements to regular textareas
            modified = true
            node.type = 'textarea'
            node.name = ''
            node.label = ''
            node.default = remove_hypertext(node.text)
            node.text = nil
        elseif node_type == 'scroll_container' then
            modified = true
            node.type = 'container'
            -- Scroll containers are always going to be broken on older clients
            for i = #node, 1, -1 do
                local inner_node = node[i]
                if inner_node.x and inner_node.y and
                        (inner_node.x >= node.w or inner_node.y >= node.h) then
                    table.remove(node, i)
                end
            end
        elseif formspec_version == 1 and node_type == 'tabheader' then
            node.w, node.h = nil, nil
        elseif formspec_version == 2 and node_type == 'bgcolor' then
            modified = true
            fixers.bgcolor(node)
        end
    end

    if formspec_version == 1 then
        modified = true
        tree = fs51.backport(tree)
    end

    if modified then
        return assert(formspec_ast.unparse(tree))
    end
    return formspec
end

-- Patch minetest.show_formspec()
local show_formspec = minetest.show_formspec
function minetest.show_formspec(pname, formname, formspec)
    return show_formspec(pname, formname, backport_for(pname, formspec))
end

-- Patch player:set_inventory_formspec()
local old_set_inventory_formspec
local function new_set_inventory_formspec(self, formspec, ...)
    return old_set_inventory_formspec(self,
        backport_for(self:get_player_name(), formspec), ...)
end

minetest.register_on_joinplayer(function(player)
    if old_set_inventory_formspec == nil then
        assert(type(player) == 'userdata', 'Fake player object?')
        local cls = getmetatable(player)
        old_set_inventory_formspec = cls.set_inventory_formspec
        cls.set_inventory_formspec = new_set_inventory_formspec

        -- In case the inventory formspec has been set in the meantime
        player:set_inventory_formspec(player:get_inventory_formspec())
    end
end)

if minetest.settings:get_bool('fs51.disable_meta_override', true) then
    return
end

-- Patch minetest.get_meta()
-- Inspired by https://gitlab.com/sztest/nodecore/-/blob/master/mods/nc_api
local old_nodemeta_set_string
local function new_nodemeta_set_string(self, k, v)
    if k == 'formspec' and type(v) == 'string' then
        v = fs51.backport_string(v) or v
    end
    return old_nodemeta_set_string(self, k, v)
end

local get_meta = minetest.get_meta
function minetest.get_meta(...)
    local meta = get_meta(...)
    if old_nodemeta_set_string == nil and type(meta) == 'userdata' then
        minetest.get_meta = get_meta
        local cls = getmetatable(meta)
        old_nodemeta_set_string = cls.set_string
        cls.set_string = new_nodemeta_set_string
    end
    return meta
end
