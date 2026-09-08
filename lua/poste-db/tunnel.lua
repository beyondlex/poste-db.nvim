--- SSH tunnel management for connections.toml `tunnel` fields.
---
--- A tunneled connection forwards its database host:port through an ssh
--- jump host; `connections.resolve_connection_url()` rewrites the target to
--- 127.0.0.1:<local port>, so the Rust binary needs no tunnel awareness.
--- Tunnels start on first use and stay up for the editing session (same
--- lifetime model as pooled SQL sessions); `:PosteDbTunnel` lists them and
--- stops one or all, and nvim exit tears everything down.
---
--- Config forms in connections.toml (applies to host/port connections, not
--- sqlite files or a raw `url`):
---
---   tunnel = "jump@bastion"
---   tunnel = { to = "jump@bastion", port = 2222, key = "~/.ssh/id_ed25519" }

local M = {}

local active = {}

---------------------------------------------------------------------------
-- Config normalization
---------------------------------------------------------------------------

--- Normalize a connections.toml `tunnel` value to { dest, port, key }.
--- @param v string|table
--- @return table|nil cfg, string|nil error_message
function M.normalize_cfg(v)
  if type(v) == "string" and v ~= "" then
    return { dest = v, port = 22 }
  end
  if type(v) == "table" then
    local dest = v.to or v.host
    if type(dest) ~= "string" or dest == "" then
      return nil, "tunnel table needs a `to` field (ssh destination)"
    end
    return { dest = dest, port = tonumber(v.port) or 22, key = v.key }
  end
  return nil, "tunnel must be an ssh destination string or { to = ..., port = ..., key = ... }"
end

---------------------------------------------------------------------------
-- Local port / ssh command
---------------------------------------------------------------------------

--- Grab a free loopback port from the OS (bind port 0, read it, release).
--- @return number|nil
function M.free_port()
  local sock = vim.uv.new_tcp()
  if not sock then return nil end
  local ok = sock:bind("127.0.0.1", 0)
  if not ok then
    sock:close()
    return nil
  end
  local addr = sock:getsockname()
  sock:close()
  return addr and addr.port or nil
end

--- The -L argument forwarding 127.0.0.1:local → db_host:db_port through ssh.
--- @return string
function M.forward_arg(local_port, db_host, db_port)
  return string.format("127.0.0.1:%d:%s:%d", local_port, db_host, db_port)
end

local function build_ssh_cmd(cfg, fwd)
  local cmd = {
    "ssh", "-N", "-T",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-p", tostring(cfg.port or 22),
  }
  if cfg.key then
    cmd[#cmd + 1] = "-i"
    cmd[#cmd + 1] = cfg.key
  end
  cmd[#cmd + 1] = "-L"
  cmd[#cmd + 1] = fwd
  cmd[#cmd + 1] = cfg.dest
  return cmd
end

local function can_connect(port)
  local sock = vim.uv.new_tcp()
  if not sock then return false end
  local done, ok = false, false
  sock:connect("127.0.0.1", port, function(err)
    ok = err == nil
    done = true
  end)
  vim.wait(500, function() return done end, 20)
  pcall(sock.close, sock)
  return ok
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

--- Start (or reuse) the tunnel for a named connection. Blocking on first
--- use only — waits up to a few seconds for the forwarded port to answer.
--- @param name string connection name (cache key)
--- @param tunnel_cfg string|table connections.toml `tunnel` value
--- @param db_host string database host from the connection section
--- @param db_port number|string database port from the connection section
--- @return number|nil local_port, string|nil error_message
function M.ensure(name, tunnel_cfg, db_host, db_port)
  db_host = db_host or "localhost"
  db_port = tonumber(db_port)
  local cfg, cerr = M.normalize_cfg(tunnel_cfg)
  if not cfg then return nil, cerr end
  if not db_port then return nil, "tunnel needs a numeric database port" end

  local existing = active[name]
  if existing
    and existing.dest == cfg.dest and existing.ssh_port == (cfg.port or 22)
    and existing.key == cfg.key and existing.db_host == db_host
    and existing.db_port == db_port
    and existing.proc and existing.proc:is_active() then
    return existing.port
  end
  if existing then M.stop(name) end

  if vim.fn.executable("ssh") == 0 then
    return nil, "ssh not found on PATH"
  end

  local port = M.free_port()
  if not port then return nil, "no free local port for tunnel" end

  local stderr = {}
  local proc = vim.system(build_ssh_cmd(cfg, M.forward_arg(port, db_host, db_port)), {
    text = true,
    stderr = function(_, chunk)
      if chunk then stderr[#stderr + 1] = chunk end
    end,
  })

  -- ExitOnForwardFailure makes ssh quit promptly when the forward is
  -- refused; readiness = the local port accepting connections while the
  -- process is still alive.
  local deadline = vim.uv.now() + 5000
  while vim.uv.now() < deadline do
    if not proc:is_active() then break end
    if can_connect(port) then
      active[name] = {
        proc = proc, port = port,
        dest = cfg.dest, ssh_port = cfg.port or 22, key = cfg.key,
        db_host = db_host, db_port = db_port,
      }
      return port
    end
    vim.wait(100)
  end

  pcall(proc.kill, proc)
  local text = table.concat(stderr, ""):gsub("%s+", " ")
  return nil, ("ssh tunnel failed (%s → %s:%d)%s"):format(
    cfg.dest, db_host, db_port, text ~= "" and (": " .. text:sub(1, 300)) or "")
end

--- Stop the tunnel of one connection. Returns true when one was running.
--- @param name string
--- @return boolean
function M.stop(name)
  local t = active[name]
  if not t then return false end
  active[name] = nil
  if t.proc then pcall(t.proc.kill, t.proc) end
  return true
end

--- Stop every tunnel. Returns the count.
--- @return number
function M.stop_all()
  local n = 0
  for name in pairs(active) do
    if M.stop(name) then n = n + 1 end
  end
  return n
end

--- Active tunnels for display: { name, port, target } per entry.
--- @return table[]
function M.status_list()
  local out = {}
  for name, t in pairs(active) do
    out[#out + 1] = {
      name = name,
      port = t.port,
      target = ("%s:%d via %s"):format(t.db_host, t.db_port, t.dest),
    }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- Register the teardown autocmd (called from setup()).
function M.setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("PosteDbTunnelTeardown", { clear = true }),
    callback = function() M.stop_all() end,
  })
end

M._test = {
  normalize_cfg = M.normalize_cfg,
  free_port = M.free_port,
  forward_arg = M.forward_arg,
  build_ssh_cmd = build_ssh_cmd,
  status_list = M.status_list,
}

return M
