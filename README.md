# Alpine Linux para o Motorola Xoom (Linux mainline)

*English below.*

Rootfs Alpine Linux (armv7, 3.24) para a partição userdata (mmcblk0p10) de um Motorola
Xoom com o [kernel mainline](https://github.com/fernandocsantos/linux/tree/xoom-stingray),
e a configuração que roda no tablet: Sxmo (sway) como sessão principal e Phosh como
alternativa, as duas compondo pela GPU com o
[Mesa do grate](https://github.com/fernandocsantos/mesa/tree/xoom-tegra20).

> **Aviso:** `montar-rootfs.sh` montou o rootfs inicial (14/10/2026), mas boa parte do
> sistema de hoje (Phosh, PipeWire, GPS, GPU) foi instalada e configurada depois, no próprio
> tablet. A configuração em `config/` é a de hoje; **reconstruir tudo do zero pelo script
> nunca foi testado.** Use como referência.

## montar-rootfs.sh

Roda como usuário comum no PC (x86_64), sem root e sem qemu:

1. baixa o minirootfs armv7 e confere SHA256 e a assinatura GPG da Alpine;
2. usa o `apk.static` (x86_64), verificado pela cadeia chave → índice → pacote
   (`verifica-apk.py`);
3. instala os pacotes com `--no-scripts` dentro de um fakeroot (os scripts ARM rodam no
   primeiro boot: `config/etc/local.d/primeiro-boot.start`);
4. copia módulos do kernel, firmware e `config/`, gera a chave ssh do root (no PC, fora do
   repositório) e cria o usuário `xoom` com login automático no tty1;
5. gera `rootfs-xoom.ext4`, que cresce até o tamanho da partição no primeiro boot.

Organização esperada: uma pasta de trabalho com este repositório em `alpine/`, o
`initramfs/` do [xoom-mainline](https://github.com/fernandocsantos/xoom-mainline) (com o
firmware e a NVRAM do **seu** tablet em `initramfs/extras/`) e os módulos instalados em
`out-stingray/modstage`.

## config/

| Caminho | O que é |
|---|---|
| `etc/init.d/rede-usb`, `etc/udhcpd.conf` | rede pelo cabo USB (o tablet em 172.16.42.1, o PC recebe 172.16.42.2) |
| `etc/init.d/bt-addr` | grava no BCM4329 o endereço Bluetooth lido da partição PDS do próprio aparelho |
| `etc/init.d/xoom-gps`, `etc/geoclue/`, `etc/conf.d/gpsd` | GPS (ver [xoom-gps](https://github.com/fernandocsantos/xoom-gps)) |
| `etc/udev/rules.d/70-rfkill-netdev.rules` | Bluetooth no Phosh sem logind |
| `etc/NetworkManager/`, `etc/wpa_supplicant/` | Wi-Fi (modelo sem rede nem senha) |
| `usr/share/alsa/ucm2/Tegra/cpcap/`, `var/lib/alsa/asound.state` | UCM do Xoom (alto-falante, fone, microfones) para a PipeWire |
| `opt/grate/bin/sway` | chama a sway com as libs do grate pelo loader da musl (a sway tem `cap_sys_nice`, e a musl ignora `LD_LIBRARY_PATH` nesse caso) |
| `home/xoom/.profile`, `usr/local/bin/trocar-sessao`, `phosh-sessao` | escolha da sessão (Sxmo ou Phosh), volta ao Sxmo se a outra cair |
| `usr/local/bin/sxmo_deviceprofile_motorola,stingray.sh` | perfil do aparelho no Sxmo |
| `usr/local/sbin/i2c0-travar`, `i2c0-destravar` | testes da recuperação do I2C 0 por GPIO |
| `usr/local/sbin/reboot-bootloader` | reinicia direto no fastboot |
| `pacotes.txt` | os pacotes (nome e versão) baixados em 10/2026 |

Licenças: MIT (`LICENSE`); `config/etc/conf.d/gpsd` mantém o cabeçalho GPL-2.0 do Gentoo.

---

# Alpine Linux for the Motorola Xoom (mainline Linux)

An Alpine Linux (armv7, 3.24) root filesystem for the userdata partition of a Motorola Xoom
running mainline Linux, and the configuration in use on the tablet: Sxmo (sway) as the main
session and Phosh as an alternative, both composited on the GPU with the grate Mesa driver.

`montar-rootfs.sh` builds the image as a normal user on an x86_64 PC (no root, no qemu): it
verifies the minirootfs (SHA256 + GPG) and `apk.static`, installs packages with
`--no-scripts` under fakeroot (ARM scripts run on first boot) and writes an ext4 image.
**Warning:** a lot of today's system was set up on the tablet later; rebuilding everything
from scratch with the script has never been tested. `config/` is the current configuration
(USB networking, Bluetooth address from the PDS partition, GPS service, UCM for PipeWire,
session switching). MIT licensed.
