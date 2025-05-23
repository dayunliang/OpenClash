#!/bin/sh
# back-route-complete.sh
# —————————————————————————————
# 功能：
#  • 来自 WAN6 子网 (192.168.122.0/24) 的 DNS (UDP/TCP 53)  → 主表 lookup main  
#  • 电视/手机的 HTTPS (TCP/443)                           → 打标走回程表100 → 对称回程  
#  • Fake-IP 模式下的 QUIC (UDP/443) 自动被 tun0 隧道拦截 → 对称回程  
#  • 其它任何流量                                         → 主表（默认行为）  
# —————————————————————————————

# —— 可调整参数 —— 
LAN_NET=192.168.122.0/24  # 从此网段进来的流量
IN_IF=eth0                # 软路由接 iKuai WAN6 的接口
OUT_IF=eth1               # 软路由回 iKuai LAN 的接口
GW=192.168.12.254         # iKuai LAN 网关
TABLE=100                 # 回程路由表编号
DNS_MARK=0x53             # DNS 标记
TCP_MARK=0x70             # TCP/443 标记

# —— 1. 清理旧配置 —— 
ip rule del fwmark ${DNS_MARK} lookup main            2>/dev/null
ip rule del iif ${IN_IF} from ${LAN_NET} lookup ${TABLE} 2>/dev/null
ip rule del fwmark ${TCP_MARK} lookup ${TABLE}       2>/dev/null
ip route flush table ${TABLE}                        2>/dev/null
iptables -t mangle -F PREROUTING                      2>/dev/null

# —— 2. DNS 绕过（端口53 → 主表）—— pref 50 —— 
iptables -t mangle -I PREROUTING 1 \
  -i ${IN_IF} -s ${LAN_NET} -p udp --dport 53 \
  -j MARK --set-mark ${DNS_MARK}
iptables -t mangle -I PREROUTING 2 \
  -i ${IN_IF} -s ${LAN_NET} -p tcp --dport 53 \
  -j MARK --set-mark ${DNS_MARK}
ip rule add fwmark ${DNS_MARK} lookup main pref 50

# —— 3. 回程策略：iif eth0 && from LAN_NET → 表100 —— pref 100 —— 
ip rule add iif ${IN_IF} from ${LAN_NET} lookup ${TABLE} pref 100
ip route add default via ${GW} dev ${OUT_IF} table ${TABLE}

# —— 4. 电视/手机 HTTPS (TCP/443) 对称回程 —— 
iptables -t mangle -I PREROUTING 3 \
  -i ${IN_IF} -s ${LAN_NET} -p tcp --dport 443 \
  -j MARK --set-mark ${TCP_MARK}
ip rule add fwmark ${TCP_MARK} lookup ${TABLE}

# —— 5. 验证 —— 
echo "=== iptables mangle PREROUTING ==="
iptables -t mangle -L PREROUTING -n --line-numbers | head -n6
echo
echo "=== ip rule ==="
ip rule show | grep -E "fwmark ${DNS_MARK}|fwmark ${TCP_MARK}|from ${LAN_NET}"
echo
echo "=== table ${TABLE} routes ==="
ip route show table ${TABLE}
