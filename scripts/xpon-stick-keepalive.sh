#!/bin/sh
# ============================================================================
# xpon-stick-keepalive.sh  —  roda na UDM (em /data/)
# Mantem a gerencia do stick LuLeey (192.168.1.1) acessivel via
# http://<IP-DA-SUA-UDM>:8888 APENAS para clientes da LAN.
#
# Re-aplica a rota a cada 30s pra sobreviver a REPROVISIONAMENTOS da UDM,
# que limpam o iptables (por isso a rota "caia" sem este keepalive).
#
# Instalado como service systemd (xpon-stick-keepalive.service, Restart=always).
# Ajuste eth9 (SFP+) e br0 (LAN) pra sua interface/modelo se diferente.
#
# >>> SEGURANCA: ajuste LAN_IP/LAN_NET pra SUA rede. O DNAT TEM que ter "-d"
#     (filtro de destino). A versao "-i br0 --dport 8888 -j DNAT" SEM "-d"
#     sequestra QUALQUER conexao da LAN para a porta 8888 (a QUALQUER IP do
#     mundo) e a joga pro web admin do stick (admin/admin). Aqui o DNAT so casa
#     origem LAN -> destino o IP da propria UDM. Alem disso, a regra so e
#     instalada se o stick estiver REALMENTE presente (ping em 192.168.1.1);
#     se o stick sumir, a regra e removida sozinha.
# ============================================================================

LAN_IP="192.168.1.254"     # <<< TROQUE pelo IP da SUA UDM na LAN
LAN_NET="192.168.0.0/16"   # <<< TROQUE pela SUA sub-rede LAN (origem permitida)
STICK_IP="192.168.1.1"     # web admin do stick (porta 80)

add_rules() {
  iptables -t nat -C PREROUTING -i br0 -s "$LAN_NET" -d "$LAN_IP" -p tcp --dport 8888 -j DNAT --to-destination "$STICK_IP":80 2>/dev/null \
    || iptables -t nat -A PREROUTING -i br0 -s "$LAN_NET" -d "$LAN_IP" -p tcp --dport 8888 -j DNAT --to-destination "$STICK_IP":80
  iptables -t nat -C POSTROUTING -d "$STICK_IP"/32 -o eth9 -p tcp --dport 80 -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -d "$STICK_IP"/32 -o eth9 -p tcp --dport 80 -j MASQUERADE
}

del_rules() {
  # remove a regra travada (nova) e tambem a versao antiga/insegura (sem -d/-s), se existirem
  while iptables -t nat -D PREROUTING -i br0 -s "$LAN_NET" -d "$LAN_IP" -p tcp --dport 8888 -j DNAT --to-destination "$STICK_IP":80 2>/dev/null; do :; done
  while iptables -t nat -D PREROUTING -i br0 -p tcp --dport 8888 -j DNAT --to-destination "$STICK_IP":80 2>/dev/null; do :; done
}

while true; do
  # 1) IP de gerencia na interface do SFP+ (eth9), na subnet do stick (inofensivo)
  ip addr show eth9 2>/dev/null | grep -q "192.168.1.2/24" \
    || ip addr add 192.168.1.2/24 dev eth9 2>/dev/null

  # 2) So instala o DNAT se o stick estiver presente; senao, garante que nenhuma
  #    regra :8888 fique pendurada (evita o hairpin com o stick ausente).
  if ping -c1 -W1 "$STICK_IP" >/dev/null 2>&1; then
    add_rules
  else
    del_rules
  fi

  sleep 30
done
