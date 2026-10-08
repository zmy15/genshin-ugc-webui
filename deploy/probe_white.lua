--[[ 探针：白色障碍诊断（真机用）

     目的：在真机上抓到"白块"发生的那一刻，打印出足够定位的信息：
       · 该控件的 imageId / imageColor 到底是什么
       · 它是否在 rendered.live 里（即渲染器是否认识它）
       · 它是新建的还是从池里复用的
       · 同一帧其它障碍槽的状态（对照"一个白一个正常"）

     用法：把本文件放到部署目录，在 demo 的 tick 里调用
             require('probe_white').scan(uiRef, spNodes, nodes)
           或直接在 onReady 里挂上（见文件末尾的用法说明）。

     ⚠️ 只在诊断期用，不要留在正式版本里（每帧遍历有开销）。 ]]
local P = {}

local warned = {}
local frame = 0

--[[ 扫描所有精灵矩形，找出"可见但没有正确贴图/染色"的控件。

     uiRef     webui 的 ui 对象（要有 .rendered.live）
     spNodes   前缀 -> 矩形节点表
     nodes     id -> 节点  ]]--
function P.scan(uiRef, spNodes, nodes)
  frame = frame + 1
  if frame % 10 ~= 0 then return end     -- 每 10 帧扫一次，降开销

  local live = uiRef and uiRef.rendered and uiRef.rendered.live
  local bad = {}

  for prefix, list in pairs(spNodes) do
    if type(list) == "table" then
      for i = 1, #list do
        local node = list[i]
        if node and node._displayOverride ~= "none" then
          local e = live and live[node]
          local ctrl = e and e.control
          local info = {
            prefix = prefix, idx = i,
            inLive = (e ~= nil),
            imageId = nil, color = "nil",
          }
          if ctrl then
            local ok, v = pcall(function() return ctrl.imageId end)
            info.imageId = ok and v or "ERR"
            local ok2, c = pcall(function() return ctrl.imageColor end)
            if ok2 and type(c) == "table" then
              info.color = string.format("#%02x%02x%02x",
                c.r or 0, c.g or 0, c.b or 0)
            end
            -- 白 = 没贴图（nil）或染色接近全白
            if info.imageId == nil or info.imageId ~= 100001 then
              bad[#bad + 1] = info
            elseif type(c) == "table" and (c.r or 0) > 240
               and (c.g or 0) > 240 and (c.b or 0) > 240 then
              bad[#bad + 1] = info
            end
          else
            info.imageId = "NO_CTRL"
            bad[#bad + 1] = info
          end
        end
      end
    end
  end

  if #bad > 0 then
    -- 按前缀归并（同一障碍的多个矩形合并成一条，避免刷屏）
    local byPrefix = {}
    for _, b in ipairs(bad) do
      local k = b.prefix
      if not byPrefix[k] then
        byPrefix[k] = { n = 0, inLive = 0, imageId = b.imageId,
                        color = b.color, idx = b.idx }
      end
      byPrefix[k].n = byPrefix[k].n + 1
      if b.inLive then byPrefix[k].inLive = byPrefix[k].inLive + 1 end
    end
    for k, v in pairs(byPrefix) do
      local key = k .. ":" .. tostring(v.imageId)
      if not warned[key] then
        warned[key] = true
        print(string.format(
          "[白块] prefix=%s 矩形=%d 在live=%d 首矩形=%d imageId=%s color=%s",
          k, v.n, v.inLive, v.idx, tostring(v.imageId), tostring(v.color)))
      end
    end
  end
end

--[[ 用法（贴在 demo_dino.lua 的 tick 末尾、或 onReady 里包一层）：

     local probeWhite = require('probe_white')
     -- 在 tick 的【最后】：
     probeWhite.scan(uiRef, spNodes, nodes)

     ★ 关键判读：
       imageId = nil    -> 控件【从未 SetImage】= 真机上就是白块
                            => 贴图通路漏了（reassert 没覆盖到）
       imageId = 100001
       color   = #ffffff -> 贴了图但【没染色】= 也是白块
                            => 染色通路漏了
       在live  = 0       -> 渲染器不认识这个节点
                            => 节点/控件绑定错位

     ⚠️ 注意：真机上读 imageId 是【只读字段】，可以读；
        imageColor 读回来可能是宿主对象，这里用 pcall 兜住。 ]]--

return P