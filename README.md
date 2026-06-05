# Guia: ONT/ONU GPON num stick SFP+ LuLeey LL-XS2510 (RTL960x) numa UniFi UDM

Manual de **auto-ajuda da comunidade** pra usar um **stick SFP+ XPON LuLeey LL-XS2510** (chip Realtek RTL960x) no lugar da caixa de ONT/ONU do provedor — plugado direto no SFP+ de uma **UniFi Dream Machine** (UDM / UDM Pro / Pro Max / SE), com a UDM discando o PPPoE.

> Baseado numa migração real (provedor GPON brasileiro, ONT ZTE F6600P → stick LuLeey, UDM Pro Max). **Todos os dados específicos viraram placeholders** (`<SEU_...>`) — adapte aos seus.

> ⚠️ **Aviso de uso responsável:** este guia é pra usar a **SUA própria conexão no SEU próprio equipamento** ("bring your own ONT"). Clonar identidade de ONT de terceiros ou burlar provedor é ilegal. Mexer em GPON é por sua conta e risco — erro pode te deixar offline. Sem garantias.

---

## 📌 TL;DR
- ✅ **Funciona:** o stick clona a identidade GPON da sua ONT → registra **O5** no OLT → a UDM faz o PPPoE → IP. Troca a caixa da ONT por um SFP no slot.
- 🔑 **Use o firmware HGU** — o SFU tem um **bug de VLAN** (não desmarca a descida).
- 🔁 **Dual-bank:** troca de firmware **sem reflashar** (`nv setenv sw_tryactive`/`sw_commit`).
- 🚀 **Velocidade:** se o download trava em ~**770-850 Mbps** num link de 1 Giga, o culpado quase sempre é o **DPI / "Traffic Identification"** da UniFi (não o PPPoE!). **Desligue o DPI + regras de QoS que casam apps → a UDM crava ~940 Mbps.** Detalhe no [aprendizado #4](#4-o-teto-de-770-mbps-geralmente-é-o-dpi-da-unifi).
- 🌐 **IPv6:** o provedor entrega, mas a UDM **não instala a rota default IPv6 no PPPoE** — precisa de um curativo (ou **IPoE**, que é nativo).

## 🗺️ Arquitetura
```
Internet (seu provedor GPON)
        │
   OLT do provedor              VLAN de transporte: <SUA_VLAN> (confirme via OMCI)
        │  fibra GPON (SC/APC)
        │
  Stick LuLeey LL-XS2510  (clona a SUA ONT)
   SN · MAC · PLOAM · MACKEY da sua ONT · Firmware HGU · Estado O5
   Bridge transparente: VLAN (OLT)  <->  untagged (UDM)
        │  SFP+ da UDM (ex: eth9), 1 Gbps
        │
  UniFi UDM  —  faz o PPPoE (ppp0) → IP público
        │
   sua LAN
```

---

## 📑 Índice
- [Pra quem é](#pra-quem-é)
- [O que você precisa](#o-que-você-precisa)
- [Pré-requisitos na UDM](#pré-requisitos-na-udm)
- [Conceitos rápidos](#conceitos-rápidos)
- [Os 4 aprendizados-ouro](#os-4-aprendizados-ouro)
- [Passo a passo](#passo-a-passo)
- [Acesso e gerência do stick](#acesso-e-gerência-do-stick)
- [Instalação dos scripts (permanente)](#instalação-dos-scripts-permanente)
- [Velocidade: o teto de PPPoE da UDM](#velocidade-o-teto-de-pppoe-da-udm)
- [IPv6 em PPPoE na UDM](#ipv6-em-pppoe-na-udm)
- [Troubleshooting e recuperação](#troubleshooting-e-recuperação)
- [FAQ](#faq)
- [Scripts](#scripts)
- [Referências](#referências)

---

## Pra quem é
- Tem fibra **GPON** e quer trocar a caixa da ONT por um **SFP no slot da UDM**.
- Tem (ou vai comprar) um stick **LuLeey LL-XS2510** ou similar **RTL960x** (RTL9601/9603).
- Topa mexer em **telnet/SSH** (não tem como fugir disso).

## O que você precisa
| Item | Detalhe |
|---|---|
| Stick | **LuLeey LL-XS2510** (XPON/GPON, Realtek RTL960x) |
| Roteador | **UDM com SFP+** (Pro / Pro Max / SE) — ou outro que faça PPPoE |
| Dados da sua ONT | **GPON SN**, **MAC**, **PLOAM password**, **usuário/senha PPPoE**, e a **VLAN** de serviço |
| Acesso | À web da ONT atual (pra ler os dados) ou a etiqueta + suporte do provedor |

## Pré-requisitos na UDM
Antes de começar, prepare a UDM:
1. **Habilite o SSH:** UniFi OS → **Console Settings → SSH** → ligue e defina a senha **root**. (É essa a senha de `ssh root@<IP-DA-UDM>` — **não** é a do "Device SSH Authentication" do app Network.)
2. **Instale o on-boot-script** (pros scripts persistirem no boot): [unifios-utilities / on-boot-script](https://github.com/unifi-utilities/unifios-utilities/tree/main/on-boot-script). Sem ele, `/data/on_boot.d/` não roda no boot (e a persistência some num update do UniFi OS).
3. **Descubra suas interfaces** — os scripts usam `eth9` (SFP+ no Pro Max) e `br0` (LAN); no seu modelo pode mudar:
   ```sh
   ip -br link     # ache a interface do SFP+ (onde o stick está plugado)
   ip -br addr     # veja qual é a bridge da LAN (geralmente br0)
   ```
   Ajuste `eth9`/`br0` nos scripts pro que encontrar.

## Conceitos rápidos
- **ONU states O0–O5:** O1 = procurando sinal, **O5 = registrado e operando**. O alvo é sempre **O5**.
- **PLOAM password:** senha com que o OLT autentica a ONU. Tem que bater com a do provedor.
- **MACKEY:** chave derivada do MAC, **obrigatória** nos RTL960x pra registrar (sem ela: O0, "Mackey Status: fail"). Fórmula: `MD5("hsgq1.9a" + MAC_MAIÚSCULO_SEM_SEPARADOR)`. Use [`scripts/mackey-calc.sh`](scripts/mackey-calc.sh).
- **VLAN de transporte:** o provedor entrega o serviço numa VLAN. ⚠️ **A VLAN que o suporte informa às vezes está errada** — a real você lê na ONT via OMCI (`omcicli mib get 84` / `171`) ou no `lastgood.xml`.
- **HGU vs SFU:** os firmwares LuLeey vêm em duas "personalidades". **Use o HGU.** O SFU tem um bug de VLAN (abaixo).

## Os 4 aprendizados-ouro

### 1. Use o firmware **HGU** (não o SFU)
- **HGU** (ex.: `V1.1.4-xxxxxx`): faz a tradução de VLAN **bidirecional** (untagged ↔ VLAN) pela **conexão WAN**. ✅
- **SFU** (ex.: `V1.0.2-xxxxxx`): marca a VLAN na **subida** mas **NÃO desmarca na descida** → a sessão PPPoE volta do BRAS *tagged* e o roteador (untagged) **ignora** → "LCP timeout". Dá pra provar com `tcpdump -i <wan> -e` (você vê a resposta voltar com `vlan XXXX`).
- ⚠️ No SFU a VLAN fica em **"VLAN Settings → PVID"** (caminho **errado**/bugado). No HGU vai no campo **`vid` da conexão WAN** (caminho certo).

### 2. Dois bancos de firmware — troque **SEM reflashar**
O RTL960x guarda **dois firmwares** em bancos separados (`k0/r0` e `k1/r1`); a partição `config` é **compartilhada**. Troca **segura** (watchdog volta sozinho se o banco for ruim):
```sh
nv getenv sw_active        # banco ativo (0 ou 1)
nv setenv sw_tryactive 1   # TENTA o outro banco (watchdog protege; sem fibra é seguro)
reboot
nv setenv sw_commit 1      # confirma/trava DEPOIS de validar que é o que você quer
```
Muitas vezes o HGU **já está no outro banco** — você nem precisa de arquivo de firmware. Ver `cat /proc/mtd`. Doc oficial: [How To Switch The Software Version](https://www.luleey.com/how-to-switch-the-software-versionll-xs2510/).

### 3. SN e MACKEY são **protegidos**
Sobrevivem a "reset all parameters", restore de config e flash de firmware (ficam em flash vars separadas). O backup `config.xml` **NÃO** os contém — não conte com ele pra restaurar SN/MACKEY.

### 4. O teto de ~770 Mbps geralmente é o **DPI** da UniFi
Se o download trava em ~770-850 Mbps num link de 1 Giga, o suspeito nº1 **não é o PPPoE** — é o **DPI / "Traffic Identification"** (e regras de **QoS que casam aplicativos**, que também acionam o DPI por baixo). O DPI inspeciona **cada pacote** → infla o custo de CPU por pacote → a **softirq do core de recepção satura**.

Confirma ao vivo: `mpstat -P ALL 1` durante um speedtest mostra um core a ~74% de `%soft`. Com o DPI **ligado** o idle agregado fica ~22%; **desligado**, salta pra ~45% e a velocidade pula de ~850 → **~940**.

**Como resolver:**
1. `Settings → Traffic Identification` (ou "Deep Packet Inspection" / "Application Visibility") → **OFF**.
2. **Remova/desabilite regras de QoS que priorizam aplicativos** (ex.: "Critical Apps Prioritization") — elas reativam o DPI por baixo, mesmo com o item 1 desligado.
3. Valide via SSH: `iptables-save | grep -c dpi` deve dar **0** e `lsmod | grep xt_dpi` deve ter **0 refs**.
4. Re-teste. Custo: você perde só os **gráficos de "quais apps usam a banda"**. Reversível.

> ⚠️ **Pistas falsas comuns:** (a) `grep -c OFFLOAD /proc/net/nf_conntrack` dá **0** mesmo com tudo OK — nesse chip (Annapurna AL324) a tag de offload **não aparece**, então não prova nada. (b) O speedtest **interno da UDM** (1× softirq) não reflete um **device encaminhado** (2× softirq: entra na WAN + sai na LAN) — um cliente real fica um pouco abaixo do teste interno; use boa NIC e evite switches antigos no caminho.

## Passo a passo

1. **Colete os dados da sua ONT atual** (web da ONT): GPON SN, MAC, PLOAM, usuário/senha PPPoE, e a VLAN de serviço.
2. **Garanta o firmware HGU** no stick (troque de banco se vier no SFU — seção acima).
3. **Acesse o stick.** Plugue o stick no SFP+ da UDM. Via SSH (`ssh root@<IP-DA-UDM>`), rode [`scripts/udm-stick-route.sh`](scripts/udm-stick-route.sh) (ajuste a interface se não for `eth9`) e abra `http://<IP-DA-UDM>:8888` (login `admin`/`admin`). Se não abrir, confirme que o stick responde: `ping 192.168.1.1` da UDM — alguns sticks vêm noutro IP.
4. **GPON Settings:** preencha **SN**, **PLOAM**, **Vendor ID** (ex.: `ZTEG`), **Product Class** (ex.: `F6600P`), as **versões de SW/HW** e o **MACKEY** (calcule: `scripts/mackey-calc.sh <SEU_MAC>`).
5. **Conexão WAN (modo bridge):**
   - `ChannelMode = Bridge` (0)
   - **`BridgeType = 0`** (transparente — costuma ser campo **OCULTO**; setar via telnet/`config.xml`)
   - `NAPT = 0`
   - **`vid = <SUA_VLAN>`** (a VLAN **real** do provedor)
   - mapeada na LAN/porta certa, `applicationtype = 2` (INTERNET)
   - Jeito mais robusto: editar `/etc/config/lastgood.xml` via telnet (`sed`) — veja [`configs/config-exemplo-hgu.xml`](configs/config-exemplo-hgu.xml). **Exemplo** (faça backup antes, reinicie depois):
     ```sh
     cp /etc/config/lastgood.xml /etc/config/lastgood.xml.bak
     sed -i 's/Name="BridgeType" Value="2"/Name="BridgeType" Value="0"/' /etc/config/lastgood.xml
     sed -i 's/Name="vid" Value="[0-9]*"/Name="vid" Value="<SUA_VLAN>"/'   /etc/config/lastgood.xml
     reboot
     ```
6. **Na UDM:** configure a WAN como **PPPoE untagged** (sem VLAN — quem faz a VLAN é o stick), usuário/senha do provedor, na porta do SFP+.
7. **Plugue a fibra no stick.** Acompanhe `diag gpon get onu-state` (telnet do stick) até **O5**. A UDM disca o PPPoE sozinha → IP público. 🎉
8. **Acesso permanente:** deixe a web do stick (`:8888`) **sempre no ar** — comandos prontos em [Instalação dos scripts](#instalação-dos-scripts-permanente).
9. **Deu certo?** Na UDM: `ip -4 -br addr | grep ppp` mostra **IP público** e `ping -c2 8.8.8.8` responde. Rode um speedtest. Se ficar offline, veja o **rollback** no [Troubleshooting](#troubleshooting-e-recuperação).

## Acesso e gerência do stick
O stick fica numa rede isolada (geralmente **`192.168.1.1`**). Pra alcançar a web dele pela LAN, a UDM faz um **DNAT** `:8888 → 192.168.1.1:80`.
- **Rota one-shot:** [`scripts/udm-stick-route.sh`](scripts/udm-stick-route.sh).
- **Permanente** (sobrevive a reprovisionamento, que limpa o iptables): ver [Instalação dos scripts](#instalação-dos-scripts-permanente).
- **Web:** `http://<IP-DA-UDM>:8888` (login `admin`/`admin`).
- **Telnet:** `busybox telnet 192.168.1.1` (precisa **TTY interativo**; pipes simples fecham). Logins comuns (root): `admin/admin`, `user/user`, e o **backdoor conhecido dos LuLeey** `administrator/Stel$864` (documentado nos fóruns).
- 🔒 **Endureça:** troque o `admin/admin` do stick (web → Admin → Password) e, idealmente, restrinja o `:8888` a um IP de gerência (no DNAT, troque `-i br0` por `-s <SEU_IP>/32`).
- ⚠️ O DNAT é só pra **clientes da LAN** — um `curl` da própria UDM dá HTTP 000 (falso negativo).

## Instalação dos scripts (permanente)
Pra o acesso ao stick (`:8888`) sobreviver a reboots **e** reprovisionamentos. Requer os [Pré-requisitos na UDM](#pré-requisitos-na-udm) (SSH + on-boot-script).

```sh
# 1) (na UDM) garanta a pasta on_boot.d
mkdir -p /data/on_boot.d

# 2) (do seu PC) copie os 2 scripts pra UDM:
scp scripts/xpon-stick-keepalive.sh      root@<IP-DA-UDM>:/data/
scp scripts/on_boot.d-10-xpon-stick.sh   root@<IP-DA-UDM>:/data/on_boot.d/10-xpon-stick.sh

# 3) (na UDM, via ssh) permissões + ativar:
chmod +x /data/xpon-stick-keepalive.sh /data/on_boot.d/10-xpon-stick.sh
sh /data/on_boot.d/10-xpon-stick.sh                 # cria + ativa o service systemd
systemctl is-active xpon-stick-keepalive.service    # -> active
```
> 💡 O `on_boot.d-10-xpon-stick.sh` **já cria a unit systemd inline** e a ativa. Por isso você **não precisa** instalar o `xpon-stick-keepalive.service` à parte — ele está no repo só como referência do conteúdo da unit (uma fonte da verdade só).
> Note o **rename** no passo 2: o arquivo vai pra `/data/on_boot.d/` como `10-xpon-stick.sh` (o prefixo `on_boot.d-` é só o nome no repo).

## Velocidade: o teto de ~770 e como destravar
Veja o [aprendizado #4](#4-o-teto-de-770-mbps-geralmente-é-o-dpi-da-unifi): na grande maioria dos casos o teto de ~770-850 é o **DPI** da UniFi, não o PPPoE. **Em ordem:**
1. 🥇 **Desligar o DPI** ("Traffic Identification") **+ remover regras de QoS que casam apps** → costuma cravar **~940** na própria UDM, sem mexer em mais nada. *(Comece por aqui — é grátis e reversível.)*
2. 🥈 Se ainda faltar banda nos **devices** (não no teste interno), lembre do **2× softirq** do tráfego encaminhado: use boa NIC e evite switches antigos no caminho.
3. 🥉 **IPoE/DHCP** do provedor — hoje vale mais pelo **IPv6 nativo** + IP público direto do que pela banda (a banda o DPI-off já resolve).

## IPv6 em PPPoE na UDM
Se seu provedor entrega **IPv6 por PPPoE**, prepare-se pra esse buraco: a UniFi pega o prefixo (DHCPv6-PD) e configura as LANs (RA), **mas NÃO instala a rota default IPv6 na WAN PPPoE** → o IPv6 não navega e a aba Internet não mostra nada.

**Causa exata:** num roteador (`net.ipv6.conf.all.forwarding=1`), o kernel só aceita a rota default vinda da RA com **`accept_ra=2`** — e a UniFi deixa **`accept_ra=1`** na `ppp0`. (Em **IPoE** é nativo; o buraco é só no PPPoE.)

**Confirme que o provedor entrega IPv6** (sonda na WAN):
```sh
rdisc6 -1 ppp0       # deve voltar uma RA com prefixo + router lifetime
odhcp6c -P 56 ppp0   # deve fazer Solicit -> Advertise -> Request -> Reply (a PD)
```

**Fix (curativo):** keepalive que põe `accept_ra=2` + instala a rota via o peer (BRAS) da `ppp0`:
```sh
GW=$(ip -6 addr show dev ppp0 | grep -oE "fe80::[0-9a-f:]+" | head -2 | tail -1)
sysctl -w net.ipv6.conf.ppp0.accept_ra=2
ip -6 route replace default via "$GW" dev ppp0 metric 100
```
Permanente: [`scripts/ipv6-route-keepalive.sh`](scripts/ipv6-route-keepalive.sh) + `.service` + [`scripts/on_boot.d-20-ipv6-route.sh`](scripts/on_boot.d-20-ipv6-route.sh) (mesmo padrão de instalação dos outros keepalives). Teste: [test-ipv6.com](https://test-ipv6.com) → 10/10.

⚠️ **Multi-WAN:** uma 2ª WAN com IPv6 (SLAAC) compete — desabilite o IPv6 dela. E lembre: **é curativo** — o fix limpo é **IPoE** (aí o IPv6 é nativo na UniFi e você remove o keepalive).

## Troubleshooting e recuperação
| Sintoma | Causa provável / fix |
|---|---|
| Não chega em O5 / "Mackey Status: fail" | MACKEY errado — recalcule com o MAC certo (maiúsculas) |
| O5 mas sem internet | Confira `vid` (VLAN) e **`BridgeType=0`**. Capture `tcpdump -i <wan> -e`: se a volta vem *tagged*, é o bug do SFU → **migre pro HGU** |
| VLAN errada | Leia a real na ONT: `omcicli mib get 84` / `171`. Não confie só no suporte |
| Stick travado | SFP+ **não tem PoE**; **reinicie a UDM** pra cortar a energia do cage e resetar o stick. Ou puxe o SFP |
| Firmware travou no boot | O **watchdog** do dual-bank volta sozinho pro outro banco |
| `:8888` não abre | Confira a rota (`ip -br addr` mostra `192.168.1.2` na interface do SFP+) e o `ping 192.168.1.1`. Lembre: `curl` da própria UDM sempre dá HTTP 000 |
| Como sei que funcionou? | `ip -4 -br addr \| grep ppp` mostra IP público + `ping -c2 8.8.8.8` ok → rode um speedtest |
| 🔙 **Rollback** (fiquei offline) | Religue a fibra na **ONT original** e aponte a WAN da UDM de volta pra porta dela (mesmo user/senha PPPoE). Volta na hora — depois retoma os testes com calma |
| Quero zerar | **Fiber-reset:** desplugar/replugar a fibra 5–6x em 30s reseta a config (menos loid/ploam). ⚠️ Apaga o resto — só em emergência |

## FAQ
- **Funciona em UDM normal / UXG / outro roteador?** Onde tiver como plugar o SFP e fazer PPPoE, sim. E o teto de ~770 por DPI (aprendizado #4) vale pra qualquer gateway UniFi.
- **Preciso baixar o firmware HGU?** Quase sempre **não** — ele costuma já estar no outro banco (dual-bank).
- **Serve pra outro stick RTL960x?** O método é o mesmo (RTL9601/9603): a fórmula do MACKEY e os comandos `nv`/`omcicli` valem. As versões de firmware mudam.
- **Vou ter o giga cheio?** Sim, na própria UDM com PPPoE — **desde que você desligue o DPI/"Traffic Identification"** (ver aprendizado #4). Com DPI ligado trava em ~770-850; desligado crava ~940. Nos **devices** da LAN, conte com um pouco menos (custo 2× do tráfego encaminhado).
- **E o IPv6?** O provedor entrega, mas a UDM **não instala a rota default IPv6 no PPPoE** — precisa do keepalive (ver [IPv6 em PPPoE na UDM](#ipv6-em-pppoe-na-udm)). Com **IPoE** é nativo.
- **Posso clonar qualquer ONT?** O guia cobre clonar a **sua** (ZTE F6600P no caso). Outros modelos: ajuste Vendor ID/Product Class/versões pros da sua ONT.

## Scripts
| Script | O que faz |
|---|---|
| [`scripts/mackey-calc.sh`](scripts/mackey-calc.sh) | Calcula o **MACKEY** a partir do MAC (`MD5("hsgq1.9a"+MAC)`) |
| [`scripts/udm-stick-route.sh`](scripts/udm-stick-route.sh) | Rota **one-shot** pra acessar a web do stick (`:8888`) |
| [`scripts/xpon-stick-keepalive.sh`](scripts/xpon-stick-keepalive.sh) | Mantém o `:8888` **sempre no ar** (re-aplica a rota a cada 30s) |
| [`scripts/xpon-stick-keepalive.service`](scripts/xpon-stick-keepalive.service) | Unit systemd (referência — o `on_boot.d` já cria ela inline) |
| [`scripts/on_boot.d-10-xpon-stick.sh`](scripts/on_boot.d-10-xpon-stick.sh) | Vai em `/data/on_boot.d/10-xpon-stick.sh` — cria/ativa o keepalive no boot |
| [`scripts/ipv6-route-keepalive.sh`](scripts/ipv6-route-keepalive.sh) | **(IPv6/PPPoE)** instala a rota default IPv6 que a UniFi não instala — ver [IPv6 em PPPoE](#ipv6-em-pppoe-na-udm) |
| [`scripts/ipv6-route-keepalive.service`](scripts/ipv6-route-keepalive.service) | Unit systemd do keepalive de IPv6 (`Restart=always`) |
| [`scripts/on_boot.d-20-ipv6-route.sh`](scripts/on_boot.d-20-ipv6-route.sh) | Vai em `/data/on_boot.d/20-ipv6-route.sh` — re-cria o keepalive de IPv6 no boot |

> Os scripts usam `eth9` (SFP+ no UDM Pro Max) e `br0` (LAN) — descubra os seus com `ip -br link` / `ip -br addr` e **ajuste** se diferente. Instalação na seção [Instalação dos scripts](#instalação-dos-scripts-permanente).

## Referências
- [LuLeey LL-XS2510 (produto)](https://www.luleey.com/product/2-5g-xpon-stick-sfp-onu/) · [How To Switch The Software Version](https://www.luleey.com/how-to-switch-the-software-versionll-xs2510/)
- [Anime4000/RTL960x — engenharia reversa do chip](https://github.com/Anime4000/RTL960x) · [Issues do LL-XS2510](https://github.com/Anime4000/RTL960x/issues)
- [unifios-utilities — on-boot-script (persistência na UDM)](https://github.com/unifi-utilities/unifios-utilities/tree/main/on-boot-script)
- [pon.wiki — custom firmware em PON sticks](https://pon.wiki)
- Fóruns Ubiquiti/PON (busque "LuLeey RTL960x backdoor", "GPON SFP UDM")

## Créditos
Manual da comunidade, baseado numa migração real documentada por **Pastorello Lab**, com assistência do Claude. **Contribuições e correções são bem-vindas** — abra uma issue ou PR. 🛜

---
*Sem afiliação com LuLeey, Ubiquiti ou provedores. Marcas pertencem aos seus donos.*
