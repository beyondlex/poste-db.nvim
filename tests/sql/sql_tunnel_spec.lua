local tunnel = require("poste-db.tunnel")

describe("tunnel", function()
  describe("normalize_cfg", function()
    it("accepts a plain ssh destination string", function()
      assert.same({ dest = "jump@bastion", port = 22 }, tunnel._test.normalize_cfg("jump@bastion"))
    end)

    it("accepts a table with to/port/key", function()
      assert.same(
        { dest = "jump@bastion", port = 2222, key = "~/.ssh/id_ed25519" },
        tunnel._test.normalize_cfg({ to = "jump@bastion", port = 2222, key = "~/.ssh/id_ed25519" }))
    end)

    it("accepts `host` as an alias for `to` and defaults the port", function()
      assert.same({ dest = "bastion", port = 22 }, tunnel._test.normalize_cfg({ host = "bastion" }))
    end)

    it("rejects invalid shapes", function()
      assert.is_nil(tunnel._test.normalize_cfg(""))
      assert.is_nil(tunnel._test.normalize_cfg(42))
      assert.is_nil(tunnel._test.normalize_cfg({ port = 22 }))
    end)
  end)

  describe("free_port", function()
    it("returns a bindable high port", function()
      local port = tunnel._test.free_port()
      assert.is_number(port)
      assert.is_true(port > 1024 and port <= 65535)
    end)
  end)

  describe("forward_arg", function()
    it("builds the -L forwarding spec", function()
      assert.equals("127.0.0.1:15432:db.internal:5432",
        tunnel._test.forward_arg(15432, "db.internal", 5432))
    end)
  end)

  describe("build_ssh_cmd", function()
    it("forwards with exit-on-failure and no remote shell", function()
      local cfg = { dest = "jump@bastion", port = 2222, key = "~/.ssh/k" }
      local cmd = tunnel._test.build_ssh_cmd(cfg, "127.0.0.1:15432:h:5432")
      assert.are.same({
        "ssh", "-N", "-T",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-p", "2222",
        "-i", "~/.ssh/k",
        "-L", "127.0.0.1:15432:h:5432",
        "jump@bastion",
      }, cmd)
    end)
  end)

  describe("status_list", function()
    it("is empty when no tunnel is active", function()
      assert.same({}, tunnel.status_list())
    end)
  end)

  describe("stop", function()
    it("is a no-op for unknown names", function()
      assert.is_false(tunnel.stop("nope"))
    end)
  end)
end)
