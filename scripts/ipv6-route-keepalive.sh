#!/bin/sh
# ============================================================================
# ipv6-route-keepalive.sh  -  roda na UDM (/data/)
#
# CURATIVO: a UniFi NAO instala a rota default IPv6 em WAN PPPoE. Ela deixa
# accept_ra=1 na ppp0, e num roteador (forwarding=1) o kernel so aceita a rota
# default vinda da RA com accept_ra=2. Resultado: a LAN pega o prefixo via
# DHCPv6-PD (o provedor entrega IPv6 normal), mas a UDM nao tem rota de saida
# IPv6 -> nao navega, e a UI da Internet nao mostra IPv6.
#
# Este loop poe accept_ra=2 e instala a rota default via o link-local do BRAS
# (= o "peer" da ppp0), com metric 100 (preferida sobre uma WAN de backup).
#
# ⚠️ E UM CURATIVO. O fix limpo e IPoE/DHCP (ai o IPv6 fica nativo na UniFi).
#    REMOVER este keepalive quando migrar pra IPoE.
# Ajuste "ppp0" se sua interface PPPoE tiver outro nome.
# ============================================================================
while true; do
  # gateway = 2o link-local listado na ppp0 (o peer/BRAS do provedor)
  GW=$(ip -6 addr show dev ppp0 2>/dev/null | grep -oE "fe80::[0-9a-f:]+" | head -2 | tail -1)
  if [ -n "$GW" ]; then
    sysctl -w net.ipv6.conf.ppp0.accept_ra=2 >/dev/null 2>&1
    ip -6 route replace default via "$GW" dev ppp0 metric 100 2>/dev/null
  fi
  sleep 20
done
