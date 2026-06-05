#!/bin/sh
# ============================================================================
# udm-stick-route.sh  —  rota ONE-SHOT pra acessar a web do stick LuLeey pela LAN
# (use o keepalive/service pra deixar permanente; este e so pra teste rapido)
#
# Roda na UDM (root). Depois abra http://<IP-DA-SUA-UDM>:8888 de um PC na LAN.
# Ajuste eth9 (SFP+ no UDM Pro Max) e br0 (LAN) pra sua interface/modelo se diferente.
# ============================================================================
ip addr add 192.168.1.2/24 dev eth9 2>/dev/null
iptables -t nat -A PREROUTING  -i br0 -p tcp --dport 8888 -j DNAT --to-destination 192.168.1.1:80
iptables -t nat -A POSTROUTING -d 192.168.1.1/32 -o eth9 -p tcp --dport 80 -j MASQUERADE

echo "Rota aplicada. Web do stick: http://<IP-DA-SUA-UDM>:8888  (login admin/admin)"
echo "Telnet do stick: busybox telnet 192.168.1.1  (admin/admin, precisa TTY interativo)"
