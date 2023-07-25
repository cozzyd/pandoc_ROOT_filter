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
local default_formats = { latex =  "pdf", html = "jsroot"}
local exts = { pdf = "pdf", eps = "eps", png="png", jpg = "jpg", svg ="svg", jsroot="json"}; 

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
  local ext = exts[format] 
  local basename = "plot" .. plot_counter; 
  local fname = output_dest .. basename ..".".. ext 
  plot_counter = plot_counter + 1; 
  return fname, basename
end



local function emitPlot(c, dest, caption, format)
  local format = format or default_formats[FORMAT]; 

  -- make sure valid -- 
  if not valid_formats[FORMAT][format] == nil then 
    format = default_formats[FORMAT] ; 
  end 

  local fname, basename = get_img_output_name(format);  

  local fn = "->SaveAs(\""..fname.."\");"
  if format == "pdf" then 
   fn = "->Print(\""..fname.."\",\"EmbedFonts\");"
  end

  emit( "((TPad*)gROOT->FindObject(\""..c.."\"))"..fn, dest); 

  if FORMAT == "html" and format == "jsroot" then 
    table.insert(jsroot_canvases,basename); 
    return pandoc.RawBlock("html","<div><div id='"..basename.."', class='__ROOT_pandoc'></div><i><p class='caption' align='center' >"..caption.."</i></p></div>"); 
  elseif FORMAT == "html" then 
    return pandoc.RawBlock("html","<div><img src='"..fname.."' alt='"..caption.."'> <p class='caption' align='center'><i>"..caption.."</i></p></div>"); 
  else
    return pandoc.RawBlock("latex","\\begin{figure}\\includegraphics{"..fname.."}\\caption{"..caption.."}\\end{figure}"); 
  end


end

local function get_file(path)

  local f = io.open(path,"rb") 
  if not f then 
    print ("Could not open" .. path)
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
    if  elem.classes[1] ~= "ROOT"  then
      return elem
    end


    local is_pre = false; 
    local echo = false; 
    local plot = nil; 
    local quote = false; 


    local dest = main; 
    local ret = {}; 

    -- Check if we are quoting -- 
    if elem.attributes.quote=="true" then; 
      quote = true; 
      local text = "```{.ROOT" 
      for key,val in pairs(elem.attributes) do 
        text = text .. " " .. key .. "=\"" .. val .. "\""; 
      end
      text = text .. "}\n" ;
      text = text .. elem.text;
      text = text .. "\n```" ;
      table.insert(ret, pandoc.CodeBlock(text))
    end
    
    -- Check if we have pre equal to true 
    if elem.attributes.pre == "true" then 
      is_pre = true;
      dest = pre ; 
    end 


    -- redirect output if echoing
    if elem.attributes.echo == "true" then 
      local fname = get_text_output_name(); 
      emit("gSystem->RedirectOutput(\""..fname.."\",\"w\");\n", dest)
      local cb=  pandoc.CodeBlock("to be filled",pandoc.Attr(fname, {"ROOT"}, {replacewith=fname})); 
      table.insert(ret,cb); 
      must_fill_code_text = true; 
    end

    -- quote the block-- 

    -- emit to macro -- 
    if  elem.attributes.include then
      emit ("//from " .. elem.attributes.include,dest); 
      local stuff = get_file(elem.attributes.include); 
      if stuff == nil then 
        emit (" #warning(\""..elem.attributes.include.." not found!\")"); 
      else 
        emit (stuff, dest); 
      end
    end 

    if elem.text ~= nil then
      emit (elem.text, dest); 
    end
    


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
    local _,_,val = string.find(elem.text, "^!.ROOT%((.+)%)$")
    if val == nil then 
      return elem 
    end 
    
    must_fill_str_text = true; 
    local fname = get_text_output_name()
    emit("__write_to_file(\""..fname.."\","..val..");",main);
    return pandoc.Str( "!.ROOT("..fname..")"); 
end


local ReplaceCodeBlock = function(elem) 
  if  elem.classes[1] ~= "ROOT"  or elem.attributes.quote=="true" then
      return elem
  end
  return pandoc.CodeBlock(get_file(elem.attributes.replacewith)) 
end

  
local ReplaceStr = function(elem) 
    local _,_,val = string.find(elem.text, "^!.ROOT%((.+)%)$")
    if val == nil then 
      return elem 
    end 
    return pandoc.Str(get_file(val)); 
end

  


function Pandoc(elem) 

  --first pass -- 
  -- if we don't have traverse available, do code blocks first, then strings 
  local p = nil; 
  if PANDOC_VERSION[1] == 2 and PANDOC_VERSION[2] < 17 then 
    local filters = {{CodeBlock = GenCodeBlock}, {Str = GenStr}};
    p = pandoc.walk_block(pandoc.Div(elem.blocks), filters[1]).content; 
    p = pandoc.walk_block(pandoc.Div(p), filters[2]).content; 
  else 
    local filters = {traverse='topdown', CodeBlock = GenCodeBlock, Str = GenStr };
    p = pandoc.walk_block(pandoc.Div(elem.blocks), filters).content; 
  end
  -- construct the ROOT file -- 

  os.execute('mkdir -p ' ..output_dest); 
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

  local ret  = os.execute("root.exe -b -q " .. full_macro_path); 

  -- we have to run over a second time to do text replacements -- 
  if must_fill_code_text or must_fill_str_text then 
    local t= {}; 
    if must_fill_code_text  then
      t.CodeBlock = ReplaceCodeBlock;
    end
    if must_fill_str_text then
      t.Str = ReplaceStr;
    end 
    p = pandoc.walk_block(pandoc.Div(p), t).content;
  end

  -- if html and jsroot, need to add script stuff -- 
  
  if FORMAT == "html" and jsroot_canvases[1] ~=nil then 
    script_code = [[
    <script type='module'>
    import { httpRequest, draw, redraw, resize, cleanup } from 'https://root.cern/js/latest/modules/main.mjs';
    var plots = document.getElementsByClassName("__ROOT_pandoc"); 
    for (var i = 0; i < plots.length; i++) 
    {
      let filename = "]]..output_dest..[[" + plots[i].id + ".json"; 
      let obj = await httpRequest(filename, 'object');
      plots[i].setAttribute("style", "width:" + obj['fCw'] + "px"); 
      plots[i].setAttribute("style", "height:" + obj['fCh'] + "px"); 
      draw(plots[i].id, obj);
    }
    </script> 
    ]] 

    p:extend({pandoc.RawBlock("html",script_code)}); 


  end

  elem.meta.graphics=true; 
  return pandoc.Pandoc(p, elem.meta)
end 
 








