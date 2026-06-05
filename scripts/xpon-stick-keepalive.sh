#!/bin/sh
# ============================================================================
# xpon-stick-keepalive.sh  —  roda na UDM (em /data/)
# Mantem a gerencia do stick LuLeey (192.168.1.1) SEMPRE acessivel via
# http://<IP-DA-SUA-UDM>:8888 a partir de clientes da LAN.
#
# Re-aplica a rota a cada 30s pra sobreviver a REPROVISIONAMENTOS da UDM,
# que limpam o iptables (por isso a rota "caia" sem este keepalive).
#
# Instalado como service systemd (xpon-stick-keepalive.service, Restart=always).
# Ajuste eth9 (SFP+) e br0 (LAN) pra sua interface/modelo se diferente.
# ============================================================================
while true; do
  # 1) IP de gerencia na interface do SFP+ (eth9), na subnet do stick
  ip addr show eth9 2>/dev/null | grep -q "192.168.1.2/24" \
    || ip addr add 192.168.1.2/24 dev eth9 2>/dev/null

  # 2) DNAT: <IP-DA-UDM>:8888 (LAN) -> 192.168.1.1:80 (web do stick)
  iptables -t nat -C PREROUTING -i br0 -p tcp --dport 8888 -j DNAT --to-destination 192.168.1.1:80 2>/dev/null \
    || iptables -t nat -A PREROUTING -i br0 -p tcp --dport 8888 -j DNAT --to-destination 192.168.1.1:80

  # 3) MASQUERADE pra resposta voltar
  iptables -t nat -C POSTROUTING -d 192.168.1.1/32 -o eth9 -p tcp --dport 80 -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -d 192.168.1.1/32 -o eth9 -p tcp --dport 80 -j MASQUERADE

  sleep 30
done
