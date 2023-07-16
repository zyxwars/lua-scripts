--[[

    gimp.lua - export and edit with GIMP

    Copyright (C) 2016 Bill Ferguson <wpferguson@gmail.com>.

    Portions are lifted from hugin.lua and thus are

    Copyright (c) 2014  Wolfgang Goetz
    Copyright (c) 2015  Christian Kanzian
    Copyright (c) 2015  Tobias Jakobs


    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
    gimp - export an image and open with GIMP for editing

    This script provides another storage (export target) for darktable.  Selected
    images are exported in the specified format to temporary storage.  GIMP is launched
    and opens the files.  After editing, the exported images are overwritten to save the
    changes.  When GIMP exits, the exported files are moved into the current collection
    and imported into the database.  The imported files then show up grouped with the
    originally selected images.

    ADDITIONAL SOFTWARE NEEDED FOR THIS SCRIPT
    * GIMP - http://www.gimp.org

    USAGE
    * require this script from your main lua file
    * select an image or images for editing with GIMP
    * in the export dialog select "Edit with GIMP" and select the format and bit depth for the
      exported image.  Check the  "run_detached" button to run GIMP in detached mode.  Images
      will not be returned to darktable in this mode, but additional images can be sent to 
      GIMP without stopping it.
    * Press "export"
    * Edit the image with GIMP then save the changes with File->Overwrite....
    * Exit GIMP
    * The edited image will be imported and grouped with the original image

    CAVEATS
    * Developed and tested on Ubuntu 14.04 LTS with darktable 2.0.3 and GIMP 2.9.3 (development version with
      > 8 bit color)
    * There is no provision for dealing with the xcf files generated by GIMP, since darktable doesn't deal with
      them.  You may want to save the xcf file if you intend on doing further edits to the image or need to save
      the layers used.  Where you save them is up to you.

    BUGS, COMMENTS, SUGGESTIONS
    * Send to Bill Ferguson, wpferguson@gmail.com

    CHANGES
    * 20160823 - os.rename doesn't work across filesystems.  Added fileCopy and fileMove functions to move the file
                 from the temporary location to the collection location irregardless of what filesystem it is on.  If an
                 issue is encountered, a message is printed back to the UI so the user isn't left wondering what happened.
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"
local gettext = dt.gettext
local gimp_widget = nil

du.check_min_api_version("7.0.0", "gimp") 

-- return data structure for script_manager

local script_data = {}

script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again
script_data.show = nil -- only required for libs since the destroy_method only hides them

-- Tell gettext where to find the .mo file translating messages for a particular domain
gettext.bindtextdomain("gimp",dt.configuration.config_dir.."/lua/locale/")

local function _(msgid)
    return gettext.dgettext("gimp", msgid)
end

local function group_if_not_member(img, new_img)
  local image_table = img:get_group_members()
  local is_member = false
  for _,image in ipairs(image_table) do
    dt.print_log(image.filename .. " is a member")
    if image.filename == new_img.filename then
      is_member = true
      dt.print_log("Already in group")
    end
  end
  if not is_member then
    dt.print_log("group leader is "..img.group_leader.filename)
    new_img:group_with(img.group_leader)
    dt.print_log("Added to group")
  end
end

local function show_status(storage, image, format, filename,
  number, total, high_quality, extra_data)
    dt.print(string.format(_("Export Image %i/%i"), number, total))
end

local function gimp_edit(storage, image_table, extra_data) --finalize

  local run_detached = dt.preferences.read("gimp", "run_detached", "bool")

  local gimp_executable = df.check_if_bin_exists("gimp")

  if not gimp_executable then
    dt.print_error(_("GIMP not found"))
    return
  end

  if dt.configuration.running_os == "macos" then
    if run_detached then
      gimp_executable = "open -a " .. gimp_executable
    else
      gimp_executable = "open -W -a " .. gimp_executable
    end
  end

  -- list of exported images
  local img_list

   -- reset and create image list
  img_list = ""

  for _,exp_img in pairs(image_table) do
    exp_img = df.sanitize_filename(exp_img)
    img_list = img_list ..exp_img.. " "
  end

  dt.print(_("Launching GIMP..."))

  local gimpStartCommand
  gimpStartCommand = gimp_executable .. " " .. img_list

  if run_detached then
    if dt.configuration.running_os == "windows" then
      gimpStartCommand = "start /b \"\" " .. gimpStartCommand
    else
      gimpStartCommand = gimpStartCommand .. " &"
    end
  end

  dt.print_log(gimpStartCommand)

  dtsys.external_command(gimpStartCommand)

  if not run_detached then

    -- for each of the image, exported image pairs
    --   move the exported image into the directory with the original
    --   then import the image into the database which will group it with the original
    --   and then copy over any tags other than darktable tags

    for image,exported_image in pairs(image_table) do

      local myimage_name = image.path .. "/" .. df.get_filename(exported_image)

      while df.check_if_file_exists(myimage_name) do
        myimage_name = df.filename_increment(myimage_name)
        -- limit to 99 more exports of the original export
        if string.match(df.get_basename(myimage_name), "_(d-)$") == "99" then
          break
        end
      end

      dt.print_log("moving " .. exported_image .. " to " .. myimage_name)
      local result = df.file_move(exported_image, myimage_name)

      if result then
        dt.print_log("importing file")
        local myimage = dt.database.import(myimage_name)

        group_if_not_member(image, myimage)

        for _,tag in pairs(dt.tags.get_tags(image)) do
          if not (string.sub(tag.name,1,9) == "darktable") then
            dt.print_log("attaching tag")
            dt.tags.attach(tag,myimage)
          end
        end
      end
    end
  end
end

local function destroy()
  dt.destroy_storage("module_gimp")
end

-- Register

gimp_widget = dt.new_widget("check_button"){
  label = _("run detached"),
  tooltip = _("don't import resulting image back into darktable"),
  value = dt.preferences.read("gimp", "run_detached", "bool"),
  clicked_callback = function(this)
    dt.preferences.write("gimp", "run_detached", "bool", this.value)
  end
}

dt.register_storage("module_gimp", _("Edit with GIMP"), show_status, gimp_edit, nil, nil, gimp_widget)

--
script_data.destroy = destroy

return script_data
