#!/bin/sh

LAN_NET=192.168.122.0/24
ROUTE_TABLE=100
GW=192.168.12.254
WAN_IF=eth1

logger -t backroute "准备配置回程路由..."

# 延时等待 eth1 准备好（可选）
tries=0
while ! ip link show "$WAN_IF" | grep -q "state UP"; do
  sleep 1
  tries=$((tries+1))
  [ $tries -ge 5 ] && logger -t backroute "等待 $WAN_IF 超时，强行继续..." && break
done

# 清理
iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null
iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null
ip rule del from ${LAN_NET} lookup ${ROUTE_TABLE} 2>/dev/null
ip route flush table ${ROUTE_TABLE} 2>/dev/null

# 注册表（安全性增强，可选）
grep -qE "^${ROUTE_TABLE}[[:space:]]" /etc/iproute2/rt_tables || echo "${ROUTE_TABLE} backroute" >> /etc/iproute2/rt_tables

# 添加策略与路由
ip rule add from ${LAN_NET} lookup ${ROUTE_TABLE}
ip route add default via ${GW} dev ${WAN_IF} table ${ROUTE_TABLE} && \
  logger -t backroute "✅ 添加默认路由成功：table ${ROUTE_TABLE} via ${GW} dev ${WAN_IF}" || \
  logger -t backroute "❌ 添加默认路由失败！"

logger -t backroute "回程路由部署完成"
