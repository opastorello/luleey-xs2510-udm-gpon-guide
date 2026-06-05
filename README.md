# Guia: ONT/ONU GPON num stick SFP+ LuLeey LL-XS2510 (RTL960x) numa UniFi UDM

Manual de **auto-ajuda da comunidade** pra usar um **stick SFP+ XPON LuLeey LL-XS2510** (chip Realtek RTL960x) no lugar da caixa de ONT/ONU do provedor — plugado direto no SFP+ de uma **UniFi Dream Machine** (UDM / UDM Pro / Pro Max / SE), com a UDM discando o PPPoE.

> Baseado numa migração real (provedor GPON brasileiro, ONT ZTE F6600P → stick LuLeey, UDM Pro Max). **Todos os dados específicos viraram placeholders** (`<SEU_...>`) — adapte aos seus.

> ⚠️ **Aviso de uso responsável:** este guia é pra usar a **SUA própria conexão no SEU próprio equipamento** ("bring your own ONT"). Clonar identidade de ONT de terceiros ou burlar provedor é ilegal. Mexer em GPON é por sua conta e risco — erro pode te deixar offline. Sem garantias.

---

## 📑 Índice
- [Pra quem é](#pra-quem-é)
- [O que você precisa](#o-que-você-precisa)
- [Conceitos rápidos](#conceitos-rápidos)
- [Os 4 aprendizados-ouro](#os-4-aprendizados-ouro)
- [Passo a passo](#passo-a-passo)
- [Acesso e gerência do stick](#acesso-e-gerência-do-stick)
- [Velocidade: o teto de PPPoE da UDM](#velocidade-o-teto-de-pppoe-da-udm)
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

### 4. A UDM trava o PPPoE em **~770 Mbps** (num link de 1 Giga)
A UDM (testado em Pro Max) **não faz offload de hardware no PPPoE** → o tráfego cai na via de **software** → teto de ~770. Confirma com:
```sh
ethtool -k <wan> | grep hw-tc-offload   # -> off [fixed]
grep -c OFFLOAD /proc/net/nf_conntrack  # -> 0
```
**Não é o stick** (a ONT em bridge dá o mesmo teto). Pra **giga cheio**: peça **IPoE/DHCP** ao provedor (a UDM roteia em HW), ou deixe um roteador externo fazer o PPPoE.

## Passo a passo

1. **Colete os dados da sua ONT atual** (web da ONT): GPON SN, MAC, PLOAM, usuário/senha PPPoE, e a VLAN de serviço.
2. **Garanta o firmware HGU** no stick (troque de banco se vier no SFU — seção acima).
3. **Acesse o stick.** Plugue na UDM; rode [`scripts/udm-stick-route.sh`](scripts/udm-stick-route.sh) na UDM (root via SSH) e abra `http://<IP-DA-SUA-UDM>:8888` (login `admin`/`admin`).
4. **GPON Settings:** preencha **SN**, **PLOAM**, **Vendor ID** (ex.: `ZTEG`), **Product Class** (ex.: `F6600P`), as **versões de SW/HW** e o **MACKEY** (calcule: `scripts/mackey-calc.sh <SEU_MAC>`).
5. **Conexão WAN (modo bridge):**
   - `ChannelMode = Bridge` (0)
   - **`BridgeType = 0`** (transparente — costuma ser campo **OCULTO**; setar via telnet/`config.xml`)
   - `NAPT = 0`
   - **`vid = <SUA_VLAN>`** (a VLAN **real** do provedor)
   - mapeada na LAN/porta certa, `applicationtype = 2` (INTERNET)
   - Jeito mais robusto: editar `/etc/config/lastgood.xml` via telnet (`sed`) — veja [`configs/config-exemplo-hgu.xml`](configs/config-exemplo-hgu.xml).
6. **Na UDM:** configure a WAN como **PPPoE untagged** (sem VLAN — quem faz a VLAN é o stick), usuário/senha do provedor, na porta do SFP+.
7. **Plugue a fibra no stick.** Acompanhe `diag gpon get onu-state` (telnet do stick) até **O5**. A UDM disca o PPPoE sozinha → IP público. 🎉
8. **Acesso permanente:** instale o keepalive ([`scripts/`](scripts/)) pra a web do stick (`:8888`) ficar **sempre no ar**.

## Acesso e gerência do stick
O stick fica numa rede isolada (geralmente **`192.168.1.1`**). Pra alcançar a web dele pela LAN, a UDM faz um **DNAT** `:8888 → 192.168.1.1:80`.
- **Rota one-shot:** [`scripts/udm-stick-route.sh`](scripts/udm-stick-route.sh).
- **Permanente** (sobrevive a reprovisionamento, que limpa o iptables): [`scripts/xpon-stick-keepalive.sh`](scripts/xpon-stick-keepalive.sh) + [`scripts/xpon-stick-keepalive.service`](scripts/xpon-stick-keepalive.service) + [`scripts/on_boot.d-10-xpon-stick.sh`](scripts/on_boot.d-10-xpon-stick.sh).
- **Web:** `http://<IP-DA-UDM>:8888` (login `admin`/`admin`).
- **Telnet:** `busybox telnet 192.168.1.1` (precisa **TTY interativo**; pipes simples fecham). Logins comuns (root): `admin/admin`, `user/user`, e o **backdoor conhecido dos LuLeey** `administrator/Stel$864` (documentado nos fóruns).
- ⚠️ O DNAT é só pra **clientes da LAN** — um `curl` da própria UDM dá HTTP 000 (falso negativo).

## Velocidade: o teto de PPPoE da UDM
Já está no [aprendizado #4](#4-a-udm-trava-o-pppoe-em-770-mbps-num-link-de-1-giga): a UDM não faz offload de PPPoE → ~770 Mbps. **Soluções, em ordem:**
1. 🥇 **IPoE/DHCP** do provedor (sem PPPoE) → a UDM roteia em hardware → giga cheio.
2. 🥈 Um **roteador externo** fazendo o PPPoE (a UDM atrás por DHCP).
3. 🥉 Aceitar ~770 com a UDM no PPPoE.

## Troubleshooting e recuperação
| Sintoma | Causa provável / fix |
|---|---|
| Não chega em O5 / "Mackey Status: fail" | MACKEY errado — recalcule com o MAC certo (maiúsculas) |
| O5 mas sem internet | Confira `vid` (VLAN) e **`BridgeType=0`**. Capture `tcpdump -i <wan> -e`: se a volta vem *tagged*, é o bug do SFU → **migre pro HGU** |
| VLAN errada | Leia a real na ONT: `omcicli mib get 84` / `171`. Não confie só no suporte |
| Stick travado | SFP+ **não tem PoE**; **reinicie a UDM** pra cortar a energia do cage e resetar o stick. Ou puxe o SFP |
| Firmware travou no boot | O **watchdog** do dual-bank volta sozinho pro outro banco |
| Quero zerar | **Fiber-reset:** desplugar/replugar a fibra 5–6x em 30s reseta a config (menos loid/ploam). ⚠️ Apaga o resto — só em emergência |

## FAQ
- **Funciona em UDM normal / UXG / outro roteador?** Onde tiver como plugar o SFP e fazer PPPoE, sim. O teto de ~770 vale onde a **UDM** termina o PPPoE.
- **Preciso baixar o firmware HGU?** Quase sempre **não** — ele costuma já estar no outro banco (dual-bank).
- **Serve pra outro stick RTL960x?** O método é o mesmo (RTL9601/9603): a fórmula do MACKEY e os comandos `nv`/`omcicli` valem. As versões de firmware mudam.
- **Vou ter o giga cheio?** Com a UDM no PPPoE, não (~770). Com **IPoE** do provedor, sim.
- **Posso clonar qualquer ONT?** O guia cobre clonar a **sua** (ZTE F6600P no caso). Outros modelos: ajuste Vendor ID/Product Class/versões pros da sua ONT.

## Scripts
| Script | O que faz |
|---|---|
| [`scripts/mackey-calc.sh`](scripts/mackey-calc.sh) | Calcula o **MACKEY** a partir do MAC (`MD5("hsgq1.9a"+MAC)`) |
| [`scripts/udm-stick-route.sh`](scripts/udm-stick-route.sh) | Rota **one-shot** pra acessar a web do stick (`:8888`) |
| [`scripts/xpon-stick-keepalive.sh`](scripts/xpon-stick-keepalive.sh) | Mantém o `:8888` **sempre no ar** (re-aplica a rota a cada 30s) |
| [`scripts/xpon-stick-keepalive.service`](scripts/xpon-stick-keepalive.service) | Unit systemd do keepalive (`Restart=always`) |
| [`scripts/on_boot.d-10-xpon-stick.sh`](scripts/on_boot.d-10-xpon-stick.sh) | Vai em `/data/on_boot.d/` — re-cria o keepalive no boot (sobrevive a updates do UniFi OS) |

> Os scripts usam `eth9` (SFP+ no UDM Pro Max) e `br0` (LAN) — **ajuste pra sua interface/modelo** se diferente.

## Referências
- [LuLeey LL-XS2510 (produto)](https://www.luleey.com/product/2-5g-xpon-stick-sfp-onu/) · [How To Switch The Software Version](https://www.luleey.com/how-to-switch-the-software-versionll-xs2510/)
- [Anime4000/RTL960x — engenharia reversa do chip](https://github.com/Anime4000/RTL960x) · [Issues do LL-XS2510](https://github.com/Anime4000/RTL960x/issues)
- [pon.wiki — custom firmware em PON sticks](https://pon.wiki)
- Fóruns Ubiquiti/PON (busque "LuLeey RTL960x backdoor", "GPON SFP UDM")

## Créditos
Manual da comunidade, baseado numa migração real documentada por **Pastorello Lab**, com assistência do Claude. **Contribuições e correções são bem-vindas** — abra uma issue ou PR. 🛜

---
*Sem afiliação com LuLeey, Ubiquiti ou provedores. Marcas pertencem aos seus donos.*
