#!/usr/bin/env lua5.3
-------------------------------------------------------------------------------
local argparse = require'argparse'
local rapidjson = require'rapidjson'
local colors = require'ansicolors'
-------------------------------------------------------------------------------

local parser = argparse("todo")

parser:command_target("command")

local _edit = parser:command("edit"):summary("Edit a todo.")
_edit:option("--line -l", "Edit this line. Defaults to the first line",
               1, tonumber, 1)

local _show = parser:command("show"):summary("Dumps the todo pile.")
_show:option("--tag -t", "Show only this tag."):args(1)

local _push = parser:command("push"):summary("Pushes into the todo pile.")
_push:option("--message -m", "The message."):args(1)
_push:option("--tag -t", "The message tag."):args(1)
_push:option("--priority -p", "The message priority. Defaults to 50.",
              50, tonumber, 1)

local _pop = parser:command("pop"):summary("Pops from the todo pile.")
_pop:mutex(
   _pop:option("--range -r", "Range to pop."):args(1),
   _pop:option("--line -l",
                 "The line number to pop. Defaults to the first line.",
                 1, tonumber, 1)
)

-------------------------------------------------------------------------------

local editor = "vim"
local home = os.getenv("HOME")
local todo_file = home.."/.todo.json"

local f = io.open(todo_file)
if not f then
   -- create empty file
   os.execute("echo '[]' > "..todo_file)
end

local ft = assert(rapidjson.load(todo_file))

-------------------------------------------------------------------------------

function ft_insert(o)
   ft[#ft + 1] = o
   table.sort(ft,
      function (a, b)
         return a.priority > b.priority
      end)
end

function colorize(priority)
   if priority < 10 then
      return "%{whitebg}"
   elseif priority >= 10 and priority < 50 then
      return "%{cyanbg}"
   elseif priority >= 50 and priority < 75 then
      return "%{yellowbg}"
   elseif priority >= 75 and priority < 90 then
      return "%{redbg}%{bright}"
   elseif priority >= 90 and priority < 100 then
      return "%{blackbg}%{bright}"
   end
end

local args = parser:parse()
if args.priority then
   -- clamp to [1, 99]
   args.priority = args.priority > 99 and 99 or args.priority
   args.priority = args.priority < 1 and 1 or args.priority
end

function cmd_show()
   for n, v in ipairs(ft) do
      if args.tag then
         if string.upper(args.tag) ~= v.tag then
            goto continue
         end
      end
      local prio =
         colors(colorize(v.priority) .. string.format("%02d", v.priority))
      print(string.format("%d - %s - [%s] %s", n, prio, v.tag, v.message))
      ::continue::
   end
end

function validate(o)
   o.tag = string.upper(tostring(o.tag))
   o.priority = tonumber(o.priority)
   o.message = tostring(o.message)
   if not o.priority then
      error("Priority should be a number.")
   end
end

function cmd_edit()
   local f = io.open("/tmp/.edit_todo", "w")
   args.line = args.line > #ft and #ft or args.line
   local o = table.remove(ft, args.line)
   local s = rapidjson.encode(o, {pretty = true})
   f:write(s)
   f:close()
   os.execute(editor .. " /tmp/.edit_todo")
   local o = rapidjson.load("/tmp/.edit_todo")
   if not o then
      error("Edited todo not in JSON Object format.")
   end
   validate(o)
   ft_insert(o)
   os.execute('rm /tmp/.edit_todo')
   -- show all tags
   args.tag = nil
   cmd_show()
   rapidjson.dump(ft, todo_file)
end

function cmd_push()
   if not args.message then
      error("No message.")
   end
   local o = {
      priority = args.priority,
      tag = args.tag and string.upper(args.tag) or "",
      message = args.message
   }
   ft_insert(rapidjson.object(o))
   -- show all tags
   args.tag = nil
   cmd_show()
   rapidjson.dump(ft, todo_file)
end

function cmd_pop()
   if args.range then
      local a, b = string.match(args.range, "(%d+)..(%d+)")
      if not a or not b then
         error("Range is invalid")
      end
      a, b = tonumber(a), tonumber(b)
      if a > b then
         a, b = b, a
      end
      for i = a, b do
         table.remove(ft, a)
      end
   else
      table.remove(ft, args.line)
   end
   -- show all tags
   args.tag = nil
   cmd_show()
   rapidjson.dump(ft, todo_file)
end

local cmds = {
   ["edit"] = cmd_edit,
   ["show"] = cmd_show,
   ["push"] = cmd_push,
   ["pop"] = cmd_pop,
}

assert(cmds[args.command])()
