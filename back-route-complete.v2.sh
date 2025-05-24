#!/bin/sh
# back-route-complete.v2.sh
# 修改时间：2025-05-24
# 功能：
#  • 一键清理 OpenClash 残留（fwmark 0x162、DNS 重定向等）
#  • 自动获取 eth1 默认网关
#  • 部署 DNS 绕过（UDP/TCP 53 → 主表 lookup main）
#  • 部署精准回程（来自 eth0 且源自 192.168.122.0/24 → table100）
#  • 部署 QUIC 拦截（UDP/443 → 重定向至 Clash REDIR 端口 7892）
#  • 部署 HTTPS 对称回程（TCP/443 → table100）
#  • 兼容 Fake-IP 模式下的 QUIC 隧道截取
#  • 最终保证：电视 YouTube 流畅 + WAN6 DNS 通畅

# —— 参数 —— 
LAN_NET=192.168.122.0/24    # 要回程的子网
IN_IF=eth0                  # 软路由接 iKuai WAN6 的接口
OUT_IF=eth1                 # 软路由回 iKuai LAN 的接口
TABLE=100                   # 回程表编号
DNS_MARK=0x53               # DNS 标记
TCP_MARK=0x70               # HTTPS 标记
CLASH_REDIR_PORT=7892       # Clash 假IP 重定向端口

# —— 0. 动态获取 OUT_IF 的默认网关 —— 
GW=$(ip route | awk '/^default/ && / dev '"${OUT_IF}"'/ {print $3}')
if [ -z "$GW" ]; then
  echo "Error: 无法获取 ${OUT_IF} 的默认网关"
  exit 1
fi
echo "使用网关：${GW}"

# —— 1. 清理旧规则 —— 
ip rule del from ${LAN_NET} lookup ${TABLE}                  2>/dev/null
ip rule del fwmark 0x162 ipproto icmp lookup main           2>/dev/null
ip rule del fwmark 0x162         lookup 354                 2>/dev/null

iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null
iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null

ip rule del fwmark ${DNS_MARK} lookup main                   2>/dev/null
ip rule del fwmark ${TCP_MARK} lookup ${TABLE}               2>/dev/null
ip route flush table ${TABLE}                                2>/dev/null
iptables -t mangle -F PREROUTING                              2>/dev/null

# —— 2. DNS 绕过 (UDP/TCP 53 → 主表, pref50) —— 
iptables -t mangle -I PREROUTING 1 \
  -i ${IN_IF} -s ${LAN_NET} -p udp  --dport 53 -j MARK --set-mark ${DNS_MARK}
iptables -t mangle -I PREROUTING 2 \
  -i ${IN_IF} -s ${LAN_NET} -p tcp  --dport 53 -j MARK --set-mark ${DNS_MARK}
ip rule add fwmark ${DNS_MARK} lookup main pref 50

# —— 3. 精准回程 (iif eth0 & LAN_NET → table100, pref100) —— 
ip rule add iif ${IN_IF} from ${LAN_NET} lookup ${TABLE} pref 100
ip route add default via ${GW} dev ${OUT_IF} table ${TABLE}

# —— 4a. QUIC 拦截 (UDP/443 → 重定向至 Clash REDIR 端口) —— 
iptables -t nat -I PREROUTING 1 \
  -i ${IN_IF} -s ${LAN_NET} -p udp --dport 443 \
  -j REDIRECT --to-port ${CLASH_REDIR_PORT}

# —— 4b. HTTPS 对称回程 (TCP/443 → 打标 0x70 → table100, pref150) —— 
iptables -t mangle -I PREROUTING 2 \
  -i ${IN_IF} -s ${LAN_NET} -p tcp --dport 443 -j MARK --set-mark ${TCP_MARK}
ip rule add fwmark ${TCP_MARK} lookup ${TABLE} pref 150

# —— 5. 验证输出 —— 
echo
echo "=== mangle PREROUTING (top 5) ==="
iptables -t mangle -L PREROUTING -n --line-numbers | head -n5
echo
echo "=== nat PREROUTING (top 5) ==="
iptables -t nat -L PREROUTING -n --line-numbers | head -n5
echo
echo "=== ip rule ==="
ip rule show | grep -E "fwmark ${DNS_MARK}|fwmark ${TCP_MARK}|iif ${IN_IF}"
echo
echo "=== table ${TABLE} routes ==="
ip route show table ${TABLE}
