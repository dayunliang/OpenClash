#!/bin/sh
# back-route-complete.sh
# ——————————————————————————————————————————
# 一键清理旧残留 + 部署：DNS绕过、精准回程、HTTPS对称
# 适用于 Fake-IP (tun) 模式
# ——————————————————————————————————————————

# —— 参数 —— 
LAN_NET=192.168.122.0/24
IN_IF=eth0
OUT_IF=eth1
GW=192.168.12.254
TABLE=100
DNS_MARK=0x53
TCP_MARK=0x70

# —— 1. 清理旧规则 —— 
# 删除不带接口的通配回程
ip rule del from ${LAN_NET} lookup ${TABLE}            2>/dev/null
# 删除 OpenClash 默认的 fwmark 0x162 规则
ip rule del fwmark 0x162 ipproto icmp lookup main      2>/dev/null
ip rule del fwmark 0x162         lookup 354            2>/dev/null
# 删除残留的 DNS nat 重定向
iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null
iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null

# —— 完全清空回程表和自定义 mangle —— 
ip rule del fwmark ${DNS_MARK} lookup main            2>/dev/null
ip rule del fwmark ${TCP_MARK} lookup ${TABLE}        2>/dev/null
ip route flush table ${TABLE}                         2>/dev/null
iptables -t mangle -F PREROUTING                       2>/dev/null

# —— 2. DNS 绕过 (53 → 主表, pref50) —— 
iptables -t mangle -I PREROUTING 1 \
  -i ${IN_IF} -s ${LAN_NET} -p udp --dport 53 -j MARK --set-mark ${DNS_MARK}
iptables -t mangle -I PREROUTING 2 \
  -i ${IN_IF} -s ${LAN_NET} -p tcp --dport 53 -j MARK --set-mark ${DNS_MARK}
ip rule add fwmark ${DNS_MARK} lookup main pref 50

# —— 3. 精准回程 (iif eth0 & LAN_NET → table100, pref100) —— 
ip rule add iif ${IN_IF} from ${LAN_NET} lookup ${TABLE} pref 100
ip route add default via ${GW} dev ${OUT_IF} table ${TABLE}

# —— 4. HTTPS 对称回程 (TCP/443 → 标记0x70 → table100, pref150) —— 
iptables -t mangle -I PREROUTING 3 \
  -i ${IN_IF} -s ${LAN_NET} -p tcp --dport 443 -j MARK --set-mark ${TCP_MARK}
ip rule add fwmark ${TCP_MARK} lookup ${TABLE} pref 150

# —— 5. 验证 —— 
echo "=== mangle PREROUTING (top 5) ==="
iptables -t mangle -L PREROUTING -n --line-numbers | head -n5
echo
echo "=== ip rule ==="
ip rule show | grep -E "fwmark ${DNS_MARK}|fwmark ${TCP_MARK}|iif ${IN_IF}"
echo
echo "=== table ${TABLE} routes ==="
ip route show table ${TABLE}
