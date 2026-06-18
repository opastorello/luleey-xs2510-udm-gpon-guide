#!/bin/sh
# ============================================================================
# udm-stick-route.sh  —  rota ONE-SHOT pra acessar a web do stick LuLeey pela LAN
# (use o keepalive/service pra deixar permanente; este e so pra teste rapido)
#
# Roda na UDM (root). Depois abra http://<IP-DA-SUA-UDM>:8888 de um PC na LAN.
# Ajuste eth9 (SFP+ no UDM Pro Max) e br0 (LAN) pra sua interface/modelo se diferente.
#
# >>> SEGURANCA: ajuste LAN_IP pro IP da SUA UDM na LAN. O DNAT TEM que ter "-d"
#     (filtro de destino). NUNCA use "-i br0 --dport 8888 -j DNAT" SEM "-d":
#     sem ele, QUALQUER conexao da LAN para a porta 8888 (a QUALQUER IP do mundo)
#     e sequestrada (hairpin) para o web admin do stick.
# ============================================================================
LAN_IP="192.168.1.254"     # <<< TROQUE pelo IP da SUA UDM na LAN (ex.: 192.168.1.1)
LAN_NET="192.168.0.0/16"   # <<< TROQUE pela SUA sub-rede LAN (origem permitida)
STICK_IP="192.168.1.1"     # web admin do stick (porta 80)

ip addr add 192.168.1.2/24 dev eth9 2>/dev/null
iptables -t nat -A PREROUTING  -i br0 -s "$LAN_NET" -d "$LAN_IP" -p tcp --dport 8888 -j DNAT --to-destination "$STICK_IP":80
iptables -t nat -A POSTROUTING -d "$STICK_IP"/32 -o eth9 -p tcp --dport 80 -j MASQUERADE

echo "Rota aplicada. Web do stick: http://$LAN_IP:8888  (login admin/admin)"
echo "Telnet do stick: busybox telnet $STICK_IP  (admin/admin, precisa TTY interativo)"
