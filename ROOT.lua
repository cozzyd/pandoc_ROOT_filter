--- GPLv3 License (GPLv3) 
--- Copyright (c) 2023  Cosmin Deaconu <cozzyd@kicp.uchicago.edu> 
--
--

local main  = {} ;  
local pre   = {}; 
local helpers = {
    "template <typename T> void __write_to_file( const char * f, const T & what) ",
    "{", 
    "  std::ofstream of(f); of << what << std::endl; ", 
    "}"

}; 

local plot_counter = 1;
local text_counter = 1; 
local output_dest = "./__pandoc_ROOT_filter/";
local macro_name = "ROOT_filter" ; 
local must_fill_code_text = false; 
local must_fill_str_text = false; 
local jsroot_canvases = {}; 

local valid_formats = { latex = { "pdf", "eps", "png", "jpg" }, html = {"png","jpg","svg","jsroot"}} ; 
local default_formats = { latex = { "pdf"}, html = {"jsroot"}}
local exts = { pdf = "pdf", eps = "eps", png="png", jpg = "jpg", svg ="svg", jsroot="root"}; 

local function emit(what, dest) 
  table.insert(dest, "\n//---------//\n");
  table.insert(dest,what);
  table.insert(dest, "\n//---------//\n"); 
end

local function get_text_output_name() 
  local fname = output_dest .. "output" .. text_counter .. ".txt" 
  text_counter = text_counter + 1; 
  return fname 
end


local function get_img_output_name(format) 
  ext = exts[format] 
  local basename = output_dest .. "plot" .. text_counter; 
  local fname = basename ..".".. ext 
  plot_counter = plot_counter + 1; 
  return fname 
end



local function emitPlot(c, dest, caption, format)
  local format = format or default_format[FORMAT]; 

  -- make sure valid -- 
  if not has_value(valid_formats[FORMAT], format) then 
    format = default_format[FORMAT] ; 
  end 

  local fname, basename = get_img_output_name(format);  

  emit( "("..c..")->SaveAs(\""..fname.."\");", dest); 

  if FORMAT == "html" and format == "jsroot" then 
    jsroot_canvases.insert(basename); 
    return pandoc.Div(caption, { identifier = "__c_"..basename}); 
  else 
    return pandoc.Image{caption, fname} 
  end


end

local function get_file(path)

  local f = open(path,"rb") 
  if not f then 
    return nil 
  end
  local stuff = f:read("*all") 
  f:close() 
  return stuff
end 




-- first we filter with this table, which generates the macro
-- then we'll have to go back if there are any texts to fill to fill them. 
local GenCodeBlock = function(elem) 
    -- handle only codeblocks with ROOT
    if not has_value(  elem.classes, "ROOT")  then
      return elem
    end


    local is_pre = false; 
    local echo = false; 
    local plot = nil; 

    local dest = main; 
    local ret = {}; 
    
    -- Check if we have pre equal to true 
    if elem.attributes.pre == "true" then 
      is_pre = true;
      dest = pre ; 
    end 


    -- redirect output if echoing
    if elem.attributes.echo == "true" then 
      local fname = get_text_output_name()
      emit("gSystem->RedirectOutput(\""..fname.."\");\n", dest)
      table.insert(ret, pandoc.CodeBlock{ text = "to be filled" , classes = { "ROOT" } , attributes = { replacewith = fname }}); 
      must_fill_code_text = true; 
    end

    -- emit to macro -- 
    emit (elem.text, dest); 
    


    -- unredirect output if not echoing
    if elem.attributes.echo == "true" then 
      emit("gSystem->RedirectOutput(0);\n", dest)
    end

    -- if we are making a plot we have to return something 
    if elem.attributes.plot ~= nil and elem.attributes.plot ~=""  then 
      table.insert(ret,emitPlot(elem.attributes.plot, dest, elem.attributes.caption or elem.attributes.plot, elem.attributes.format)); 
    end 

    return ret

end 

--this finds replacement strings, triggers output to file and sets us up for replacement
local GenStr = function (elem) 
    local _,_val = string.find(elem, "^!.ROOT%(.+%)$")
    if val == nil then 
      return elem 
    end 
    
    must_fill_str_text = true; 
    local fname = get_text_output_name()
    emit("__write_to_file(\""..fname.."\","..val..");",dest)
    return pandoc.Str( "!.ROOT("..fname..")") 
end


local ReplaceCodeBlock = function(elem) 
  if not has_value(  elem.classes, "ROOT")  then
      return elem
  end
  return pandoc.CodeBlock(get_file(elem.text)) 
end

  
local ReplaceStr = function(elem) 
    local _,_val = string.find(elem, "^!.ROOT%(.+%)$")
    if val == nil then 
      return elem 
    end 
    return pandoc.Str(get_file(val)); 
end

  


local function Pandoc(elem) 

  print "hello"; 
  --first pass -- 
  local p = pandoc.walk_block(pandoc.Div(el.blocks), { CodeBlock = GenCodeBlock, Str = GenStr }); 

  -- construct the ROOT file -- 

  pandoc.system.make_directory(output_dest); 
  local full_macro_path = output_dest .. '/' .. macro_name .. ".C";
  local of = io.open( full_macro_path, "w") 

  -- first write out the helpers
  for _,value in ipairs(helpers) do 
    of:write(value .. "\n") 
  end 

  -- then the pre
  for _,value in ipairs(pre) do 
    of:write(value) 
  end 
 
  of:write("void " .. macro_name .. "() {\n"); 

  for _,value in ipairs(main) do 
    of:write(value) 
  end 

  of:write("}"); 
  of:close(); 

  local ret  = pandoc.pipe("root.exe -b -q " .. full_macro_path); 

  -- we have to run over a second time to do text replacements -- 
  if must_fill_code_text or must_fill_str_text then 
    local t= {}; 
    if must_fill_code_text  then
      t.insert{ CodeBlock = ReplaceCodeBlock }
    end
    if must_fill_str_text then
      t.insert{ Str = ReplaceStr }
    end 
    p = pandoc.walk_block(pandoc.Div(p.blocks), t);
  end

  -- if html and jsroot, need to add script stuff -- 
  
end 
 








