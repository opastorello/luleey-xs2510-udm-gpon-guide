#!/bin/sh
# ============================================================================
# 20-ipv6-route.sh  -  vai em /data/on_boot.d/ na UDM
# Re-cria o keepalive da rota IPv6 (curativo p/ WAN PPPoE) apos boot/update
# do UniFi OS (que limpa o /etc). O script .sh em /data persiste; aqui so
# recriamos a unit systemd e ativamos.
# ⚠️ REMOVER quando migrar pra IPoE.
# ============================================================================
if [ ! -f /etc/systemd/system/ipv6-route-keepalive.service ]; then
  cat > /etc/systemd/system/ipv6-route-keepalive.service <<'UNIT'
[Unit]
Description=IPv6 default route keepalive (PPPoE WAN)
After=network-online.target
[Service]
Type=simple
ExecStart=/data/ipv6-route-keepalive.sh
Restart=always
RestartSec=15
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload 2>/dev/null
fi
systemctl enable --now ipv6-route-keepalive.service 2>/dev/null
