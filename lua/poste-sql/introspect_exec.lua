local cli = require("poste.cli")
local util = require("poste.util")
local job = require("poste-sql.introspect_job")
local const = require("poste-sql.constants")

local M = {}

function M.run_json_items_job(args, opts)
  opts = opts or {}
  local stderr_lines = {}
  cli.run_async(args, {
    on_stdout = function(data)
      data = util.ensure_job_data(data)
      if #data == 0 then return end

      local output = table.concat(data, "\n")
      vim.schedule(function()
        local parsed = job.decode_json_table(output, opts.failure_message or "Failed to parse response")
        if not parsed then return end

        local items = parsed.items
        if not items or #items == 0 then
          if opts.empty_message then
            vim.notify(opts.empty_message, vim.log.levels.WARN, { title = opts.title or const.PLUGIN_TITLE })
          end
          return
        end

        if opts.on_items then
          opts.on_items(items, parsed)
        end
      end)
    end,
    on_stderr = function(data)
      job.append_stderr(stderr_lines, data, opts.stderr_prefix)
    end,
    on_exit = function(code)
      if code ~= 0 then
        vim.schedule(function()
          job.notify_exit_error(opts.exit_kind or "Introspection", code, stderr_lines, opts.title or const.PLUGIN_TITLE)
        end)
      end
    end,
  })
end

return M
