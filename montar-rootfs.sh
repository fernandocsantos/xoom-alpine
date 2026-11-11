#!/bin/sh
# Monta um rootfs Alpine armv7 para o Motorola Xoom e gera uma imagem ext4
# para a partição userdata (mmcblk0p10). Roda como usuário comum: o fakeroot
# guarda os donos (root) dos arquivos, e o apk.static instala os pacotes sem
# executar binários ARM. Os scripts de pós-instalação que dependem de ARM
# rodam no primeiro boot (/etc/local.d/primeiro-boot.start).
set -eu

X=$(cd "$(dirname "$0")/.." && pwd)
A=$X/alpine
VER=${VER:-3.24.2}
BR=v${VER%.*}
MIRROR=https://dl-cdn.alpinelinux.org/alpine
WORK=$A/work
RF=$WORK/rootfs
FS=$WORK/fakeroot.state
IMG=$A/rootfs-xoom.ext4
IMG_SIZE=${IMG_SIZE:-1G}
# Chave de assinatura da Alpine (Natanael Copa)
NCOPA_FPR=0482D84022F52DF1C4E7CD43293ACD0907D9495A
PACOTES="alpine-base openrc busybox-openrc busybox-extras
	dropbear dropbear-openrc wpa_supplicant wpa_supplicant-openrc iw
	wireless-regdb e2fsprogs e2fsprogs-extra kmod
	i2c-tools evtest htop
	eudev eudev-openrc udev-init-scripts udev-init-scripts-openrc
	dbus-openrc seatd seatd-openrc util-linux-misc
	sxmo-utils sxmo-utils-sway sxmo-utils-udev sway wvkbd foot lisgd superd
	font-dejavu netsurf
	networkmanager networkmanager-wifi networkmanager-cli networkmanager-openrc
	alsa-utils alsa-utils-openrc
	bluez bluez-btmgmt pipewire-spa-bluez
	python3 gpsd gpsd-openrc gpsd-clients geoclue"

fr() { fakeroot -s "$FS" -i "$FS" "$@"; }

mkdir -p "$WORK/dl"
cd "$WORK/dl"

# 1. minirootfs armv7, verificado por SHA256 e GPG
MRF=alpine-minirootfs-$VER-armv7.tar.gz
[ -f "$MRF" ] || curl -sfO "$MIRROR/$BR/releases/armv7/$MRF"
curl -sfO "$MIRROR/$BR/releases/armv7/$MRF.sha256"
curl -sfO "$MIRROR/$BR/releases/armv7/$MRF.asc"
sha256sum -c "$MRF.sha256"
[ -f ncopa.asc ] || curl -sf https://alpinelinux.org/keys/ncopa.asc -o ncopa.asc
gpg --show-keys --with-colons ncopa.asc | grep -q "^fpr:::::::::$NCOPA_FPR:" \
	|| { echo "impressão digital da chave da Alpine não confere" >&2; exit 1; }
rm -f k.gpg && gpg -q --no-default-keyring --keyring "$PWD/k.gpg" --import ncopa.asc
gpgv --keyring "$PWD/k.gpg" "$MRF.asc" "$MRF"

rm -rf "$RF" "$FS"; mkdir -p "$RF"; touch "$FS"
fr tar -xzpf "$MRF" -C "$RF"

# 2. apk.static (x86_64), verificado pela cadeia chave -> índice -> pacote
curl -sf "$MIRROR/$BR/main/x86_64/APKINDEX.tar.gz" -o APKINDEX-x86_64.tar.gz
APKV=$(zcat APKINDEX-x86_64.tar.gz 2>/dev/null | tr -d '\0' |
	awk '/^P:apk-tools-static$/{f=1} f&&/^V:/{print substr($0,3); exit}')
curl -sf "$MIRROR/$BR/main/x86_64/apk-tools-static-$APKV.apk" -o apk-tools-static.apk
python3 -I "$A/verifica-apk.py" "$RF/usr/share/apk/keys/x86_64" \
	APKINDEX-x86_64.tar.gz apk-tools-static.apk apk-tools-static
rm -rf apkst && mkdir apkst && tar -xzf apk-tools-static.apk -C apkst 2>/dev/null
APK=$PWD/apkst/sbin/apk.static

# 3. Pacotes (o apk verifica a assinatura de cada um); cache fica no rootfs
mkdir -p "$RF/var/cache/apk"
ln -sf /var/cache/apk "$RF/etc/apk/cache"
# shellcheck disable=SC2086
fr "$APK" --root "$RF" --arch armv7 --keys-dir "$RF/etc/apk/keys" --no-scripts \
	--cache-dir "$RF/var/cache/apk" add $PACOTES

# O apk 3 sob fakeroot às vezes registra um arquivo comum como link simbólico
# (visto com regulatory.db). Recria esses arquivos para corrigir o registro.
find "$RF" -type f > "$WORK/reais.txt"
fr sh -c 'while read -r f; do if [ -L "$f" ]; then echo "$f"; fi; done < "$1"' sh "$WORK/reais.txt" > "$WORK/divergentes.txt"
if [ -s "$WORK/divergentes.txt" ]; then
	echo "corrigindo tipo no fakeroot: $(wc -l < "$WORK/divergentes.txt") arquivo(s)"
	# modo real lido fora do fakeroot (dentro dele o arquivo "é" um link)
	while read -r f; do echo "$(stat -c %a "$f") $f"; done < "$WORK/divergentes.txt" > "$WORK/divergentes-modo.txt"
	fr sh -c 'while read -r m f; do
		cat "$f" > "$f.tmp"; rm -f "$f"; mv "$f.tmp" "$f"
		chown 0:0 "$f"; chmod "$m" "$f"
	done < "$1"' sh "$WORK/divergentes-modo.txt"
	fr sh -c 'while read -r f; do if [ -L "$f" ]; then echo "ainda divergente: $f"; fi; done < "$1"' sh "$WORK/divergentes.txt"
fi

# O apk sob fakeroot não aplica setuid/setgid: reaplica os modos que os
# próprios pacotes declaram (ex.: bin/bbsuid 4111)
python3 -I - "$RF/var/cache/apk" > "$WORK/setuid.txt" <<'PY'
import glob, sys, tarfile
for apk in glob.glob(sys.argv[1] + "/*.apk"):
    with tarfile.open(apk) as t:
        for m in t.getmembers():
            if m.isfile() and m.mode & 0o6000:
                print(f"{m.mode & 0o7777:o} /{m.name}")
PY
fr sh -c 'while read -r m p; do chmod "$m" "$1$p"; done < "$2"' sh "$RF" "$WORK/setuid.txt"
sed 's/^/setuid\/setgid reaplicado: /' "$WORK/setuid.txt"

# 4 e 5. Módulos, firmware e configuração. Tudo dentro do fakeroot, para os
# arquivos entrarem na imagem com dono root (e não com o UID de quem roda).
STAGE=$X/out-stingray/modstage/lib/modules
KV=$(ls "$STAGE" | head -n 1)
mkdir -p "$X/ssh"
[ -f "$X/ssh/xoom_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -C xoom -f "$X/ssh/xoom_ed25519"

fr sh -eu -c '
	RF=$1 STAGE=$2 KV=$3 X=$4 A=$5
	mkdir -p "$RF/lib/modules" "$RF/lib/firmware/brcm" "$RF/root/.ssh"
	cp -r --preserve=mode,timestamps,links "$STAGE/$KV" "$RF/lib/modules/"
	rm -f "$RF/lib/modules/$KV/build" "$RF/lib/modules/$KV/source"
	cp "$X/initramfs/extras/lib/firmware/brcm/"* "$RF/lib/firmware/brcm/"
	# tar segue links de diretório do Alpine (ex.: /etc/init.d) em vez de
	# tentar substituí-los; --no-same-owner deixa os arquivos com dono root
	tar -C "$A/config" -cf - . | tar -C "$RF" -xf - --keep-directory-symlink --no-same-owner
	chmod 755 "$RF/etc/init.d/rede-usb" "$RF/etc/init.d/xoom-gps" "$RF/etc/local.d/primeiro-boot.start"
	echo xoom > "$RF/etc/hostname"
	printf "127.0.0.1\txoom localhost\n::1\t\txoom localhost\n" > "$RF/etc/hosts"
	cp "$X/ssh/xoom_ed25519.pub" "$RF/root/.ssh/authorized_keys"
	chmod 700 "$RF/root/.ssh"; chmod 600 "$RF/root/.ssh/authorized_keys"
	chown -R 0:0 "$RF/lib/modules" "$RF/lib/firmware" "$RF/root"
	# pós-instalação do alpine-baselayout
	chown 0:"$(awk -F: "\$1==\"shadow\"{print \$3}" "$RF/etc/group")" "$RF/etc/shadow"
' sh "$RF" "$STAGE" "$KV" "$X" "$A"

# Serviços do OpenRC (equivalente a rc-update add)
rl() {
	fr sh -c 'mkdir -p "$1/etc/runlevels/$3" && ln -sf "/etc/init.d/$2" "$1/etc/runlevels/$3/$2"' \
		sh "$RF" "$1" "$2"
}
# udev (e não mdev): o libinput do sway precisa do banco de dispositivos
for s in devfs dmesg udev udev-trigger udev-settle; do rl $s sysinit; done
for s in modules sysctl hostname bootmisc syslog localmount; do rl $s boot; done
for s in mount-ro killprocs savecache; do rl $s shutdown; done
for s in rede-usb dropbear local dbus seatd udev-postmount networkmanager alsa bt-addr bluetooth xoom-gps gpsd; do rl $s default; done
# xoom-gps precisa ainda de /opt/android (blobs + bionic do TWRP) e /opt/hybris
# (libhybris musl), que não vêm daqui: ver RESUMO-SESSAO.md, "GPS BCM4750".

# Usuário da interface gráfica (Sxmo): login automático no tty1, sem senha
# (a administração é por ssh como root). adduser é binário ARM, então as
# entradas vão direto nos arquivos.
fr sh -eu -c '
	RF=$1
	grep -q "^xoom:" "$RF/etc/passwd" || {
		echo "xoom:x:1000:1000:Xoom:/home/xoom:/bin/sh" >> "$RF/etc/passwd"
		echo "xoom:x:1000:" >> "$RF/etc/group"
		echo "xoom:!:20000:0:99999:7:::" >> "$RF/etc/shadow"
	}
	# Os grupos (seat, messagebus...) são criados por scripts de pacote,
	# que só rodam no primeiro boot; a filiação do xoom é feita lá.
	chown -R 1000:1000 "$RF/home/xoom"
	chmod 755 "$RF/etc/local.d/rundir-xoom.start" "$RF/usr/local/bin/sxmo_deviceprofile_motorola,stingray.sh"
' sh "$RF"

# 6. Imagem ext4 (cresce até o tamanho da partição no primeiro boot)
rm -f "$IMG"
# O mke2fs -d precisa ler cada arquivo de verdade: libera leitura no arquivo
# real (fora do fakeroot). O fakeroot continua informando o modo original
# (ex.: bbsuid 4111), e é esse que vai para a imagem.
find "$RF" -type f ! -perm -u=r > "$WORK/ilegiveis.txt"
fr sh -c 'while read -r f; do echo "$(stat -c %a "$f") $f"; done < "$1"' sh "$WORK/ilegiveis.txt" > "$WORK/ilegiveis-modo.txt"
[ -s "$WORK/ilegiveis.txt" ] && xargs -d '\n' chmod u+r < "$WORK/ilegiveis.txt"
# reaplica o modo original (ex.: setuid do bbsuid) no registro do fakeroot
fr sh -c 'while read -r m f; do chmod "$m" "$f"; done < "$1"' sh "$WORK/ilegiveis-modo.txt"
fr mkfs.ext4 -q -L xoom-root -d "$RF" "$IMG" "$IMG_SIZE"
echo "imagem: $IMG ($(du -h "$IMG" | cut -f1) ocupados de $IMG_SIZE), kernel $KV"
