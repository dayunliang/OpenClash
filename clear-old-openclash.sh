#!/bin/sh
# clear-old-openclash.sh
# 功能：删除 OpenClash 残留的 fwmark 0x162 路由 和 DNS(53) 重定向

# 1. 删除 OpenClash 默认的 fwmark 0x162 ICMP 路由
ip rule del fwmark 0x162 ipproto icmp lookup main 2>/dev/null

# 2. 删除 OpenClash 默认的 fwmark 0x162 其他路由
ip rule del fwmark 0x162 lookup 354          2>/dev/null

# 3. 删除 nat PREROUTING 表中 UDP 53 的 REDIRECT
iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null

# 4. 删除 nat PREROUTING 表中 TCP 53 的 REDIRECT
iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null

echo "已清理 OpenClash 0x162 路由和 DNS(53) 重定向残留。"
