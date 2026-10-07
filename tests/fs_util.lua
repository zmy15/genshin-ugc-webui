--[[ 跨平台的少量文件系统辅助（仅供测试使用）。

  为什么需要：
    CI 跑在 ubuntu，本地开发是 Windows。
    直接用 `dir /b`、`mkdir "..." 2>nul`、`rmdir /s /q` 这类命令，
    在另一边会【静默失败】—— 已经因此让 CI 红过一轮：
      · Linux 上 `2>nul` 不是重定向，而是创建了一个名为 nul 的文件
      · `dir /b` 在 Linux 不存在，io.popen 返回空列表
      · `mkdir "a\b"` 在 Linux 会建出名字里带反斜杠的怪目录

  这里按 package.config 判断平台，两边分别用正确的命令。
  本文件不以 test_ 开头，所以不会被 CI 当成测试套件执行。
]]--

local F = {}

-- package.config 第一行是目录分隔符："\\" (Windows) 或 "/" (Unix)
F.IS_WINDOWS = (package.config:sub(1, 1) == "\\")

--[[ 空设备。

     ★ `>nul` 是 Windows 写法；在 Linux 上它不是重定向，
       而是会创建（或写入）一个名为 nul 的文件 —— 静默地做错事。
       统一用这个常量拼重定向。
]]--
F.NULL = F.IS_WINDOWS and "nul" or "/dev/null"

-- 拼一个"丢弃所有输出"的重定向片段
F.SILENT = " >" .. F.NULL .. " 2>&1"

local function q(s)
  return '"' .. tostring(s) .. '"'
end

--[[ 创建目录（已存在也算成功）。

     ★ Lua 标准库没有 mkdir，只能用 shell。
       两边写法不同，这里分开处理。
]]--
function F.mkdir(path)
  if F.IS_WINDOWS then
    os.execute("mkdir " .. q((path:gsub("/", "\\"))) .. " 2>nul")
  else
    os.execute("mkdir -p " .. q(path) .. " 2>/dev/null")
  end
end

--[[ 递归删除目录。 ]]--
function F.rmdir(path)
  if F.IS_WINDOWS then
    os.execute("rmdir /s /q " .. q((path:gsub("/", "\\"))) .. " 2>nul")
  else
    os.execute("rm -rf " .. q(path) .. " 2>/dev/null")
  end
end

--[[ 文件是否存在且可读。 ]]--
function F.exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

--[[ 读整个文件（二进制），失败返回 nil。 ]]--
function F.read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

--[[ 写整个文件（二进制），成功返回字节数，失败返回 nil。 ]]--
function F.write(path, data)
  local f = io.open(path, "wb")
  if not f then return nil end
  f:write(data)
  f:close()
  return #data
end

--[[ 列出目录下的文件名（不含子目录遍历）。

     Windows: dir /b      Unix: ls -1
     两边都输出"一行一个名字"，所以后面统一处理。
]]--
function F.listdir(dir)
  local cmd
  if F.IS_WINDOWS then
    cmd = "dir /b " .. q((dir:gsub("/", "\\"))) .. " 2>nul"
  else
    cmd = "ls -1 " .. q(dir) .. " 2>/dev/null"
  end

  local out = {}
  local p = io.popen(cmd)
  if p then
    for raw in p:lines() do
      -- 不给循环变量赋值（Lua 5.5 起循环变量是 const）
      local n = (raw:gsub("%s+$", ""))
      if n ~= "" then out[#out + 1] = n end
    end
    p:close()
  end
  return out
end

return F
