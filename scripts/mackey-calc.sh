#!/bin/sh
# ============================================================================
# mackey-calc.sh  —  calcula o MACKEY GPON dos sticks LuLeey / Realtek RTL960x
#
# O MACKEY e obrigatorio pro stick registrar no OLT (sem ele: estado O0,
# "Mackey Status: fail"). Formula (da engenharia reversa do RTL960x):
#
#     MACKEY = MD5("hsgq1.9a" + MAC_EM_MAIUSCULAS_SEM_SEPARADORES)
#
# Uso:  ./mackey-calc.sh AA:BB:CC:DD:EE:FF
#       ./mackey-calc.sh AABBCCDDEEFF
# ============================================================================
MAC="$1"
if [ -z "$MAC" ]; then
  echo "Uso: $0 <MAC>   (ex: AA:BB:CC:DD:EE:FF)"
  exit 1
fi
MAC_UPPER=$(echo "$MAC" | tr -d ':-' | tr 'a-z' 'A-Z')

if command -v md5sum >/dev/null 2>&1; then
  KEY=$(printf '%s' "hsgq1.9a${MAC_UPPER}" | md5sum | awk '{print $1}')
else
  KEY=$(printf '%s' "hsgq1.9a${MAC_UPPER}" | openssl md5 | awk '{print $NF}')
fi

echo "MAC    : ${MAC_UPPER}"
echo "MACKEY : ${KEY}"
