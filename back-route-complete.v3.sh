#!/bin/sh
# back-route-complete.v3.sh
# 修改时间：2025-05-24 23:00
#
# 功能：
#  1. 清理 OpenClash 默认的 fwmark 回程策略（0x162）
#  2. 清理 NAT 表中针对 DNS(53) 的 REDIRECT
#  3. 清理 tun0 上的旧 DNS/QUIC REDIRECT
#  4. 删除旧的旁路由回程策略（192.168.122.0/24 + VPN 段）
#  5. 把 tun0 上的 DNS/QUIC 也交给 Clash
#  6. 配置新的旁路由回程（192.168.122.0/24 + 10.10.10.0/24 → table100）
#
### 参数区 ###
LAN1=192.168.122.0/24     # 家庭 LAN
LAN2=10.10.10.0/24        # VPN 子网
TABLE=100                 # 回程路由表
GW=192.168.12.254         # iKuai LAN 网关
WAN_IF=eth1               # 到 iKuai LAN 的接口
CLASH_MARK=0x162          # OpenClash 默认标记
CLASH_DNS_PORT=53
CLASH_REDIR_PORT=7892

### 1. 清理 OpenClash 默认回程标记 ###
ip rule del fwmark ${CLASH_MARK} ipproto icmp lookup main 2>/dev/null
ip rule del fwmark ${CLASH_MARK}         lookup 354         2>/dev/null

### 2. 清理 DNS(53) 重定向 (所有接口) ###
iptables -t nat -D PREROUTING -p udp  --dport 53 -j REDIRECT --to-ports ${CLASH_DNS_PORT} 2>/dev/null
iptables -t nat -D PREROUTING -p tcp  --dport 53 -j REDIRECT --to-ports ${CLASH_DNS_PORT} 2>/dev/null

### 3. 清理 tun0 上的旧 DNS/QUIC REDIRECT ###
iptables -t nat -D PREROUTING -i tun0 -p udp  --dport 53  -j REDIRECT --to-ports ${CLASH_DNS_PORT} 2>/dev/null
iptables -t nat -D PREROUTING -i tun0 -p tcp  --dport 53  -j REDIRECT --to-ports ${CLASH_DNS_PORT} 2>/dev/null
iptables -t nat -D PREROUTING -i tun0 -p udp --dport 443 -j REDIRECT --to-ports ${CLASH_REDIR_PORT} 2>/dev/null

### 4. 删除旧的回程策略 ###
ip rule del from ${LAN1} lookup ${TABLE} 2>/dev/null
ip rule del from ${LAN2} lookup ${TABLE} 2>/dev/null
ip route flush table ${TABLE}              2>/dev/null

### 5. 把 tun0 上的 DNS/QUIC 也交给 Clash ###
iptables -t nat -I PREROUTING 1 -i tun0 -p udp  --dport 53  -j REDIRECT --to-ports ${CLASH_DNS_PORT}
iptables -t nat -I PREROUTING 2 -i tun0 -p tcp  --dport 53  -j REDIRECT --to-ports ${CLASH_DNS_PORT}
iptables -t nat -I PREROUTING 3 -i tun0 -p udp --dport 443 -j REDIRECT --to-ports ${CLASH_REDIR_PORT}

### 6. 添加新的回程路由 ###
ip rule add from ${LAN1} lookup ${TABLE}
ip rule add from ${LAN2} lookup ${TABLE}
ip route add default via ${GW} dev ${WAN_IF} table ${TABLE}

### 完成提示 ###
echo "✅ 已部署：DNS/QUIC 对 tun0 生效，回程策略支持 LAN & VPN 两网段"
