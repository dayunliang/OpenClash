#!/bin/sh
# back-route-generic-fixed.sh
# 通用回程路由脚本（修正版）。
# 1) 删除所有“from 192.168.122.0/24”策略路由（无论原来指向哪个表）
# 2) 清空回程表 100 并重建默认路由

# —— 参数区 —— 
SRC_NET=192.168.122.0/24    # 主路由 WAN6 子网
GW=192.168.12.254           # iKuai 主路由 LAN 地址
WAN_IF=eth1                 # 旁路由 WAN 接口
TABLE=100                   # 回程路由表编号

# —— 1. 删除所有旧的“from SRC_NET”策略路由 —— 
echo "删除所有旧的 from ${SRC_NET} 策略路由:"
ip rule show \
  | awk -v net="$SRC_NET" '$0 ~ "from "net {print $1}' \
  | sed 's/://g' \
  | while read pref; do
      echo "  删除 pref $pref"
      ip rule del pref "$pref"
    done

# —— 2. 清空回程表 TABLE 中的所有路由 —— 
echo "清空路由表 $TABLE"
ip route flush table "${TABLE}"

# —— 3. 添加新的策略路由 —— 
echo "添加策略路由: from ${SRC_NET} lookup ${TABLE}"
ip rule add from "${SRC_NET}" lookup "${TABLE}"

# —— 4. 在表 TABLE 中设置默认路由 —— 
echo "在表 $TABLE 中添加默认路由 via ${GW} dev ${WAN_IF}"
ip route add default via "${GW}" dev "${WAN_IF}" table "${TABLE}"

# —— 5. 验证 —— 
echo
echo "=== 当前策略路由 (ip rule) ==="
ip rule show
echo
echo "=== 路由表 $TABLE 内容 (ip route show table $TABLE) ==="
ip route show table "${TABLE}"
