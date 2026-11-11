#!/bin/sh
# gps-rodar.sh [segundos] [job|-]: liga o BCM4750 pelo motor da Broadcom (bionic do TWRP)
# Precisa de: /system (blobs + bionic-ics), /data/location, DTB com a UARTE (ttyTHS2).
T=${1:-900}; JOB=${2:-Periodic}
# "-" = sem job: quem pede posição é um cliente (HAL pela libhybris)
JOBARG="-job $JOB"; [ "$JOB" = "-" ] && JOBARG=
ln -sf /dev/ttyTHS2 /dev/ttyHS4
for g in 56 57; do
	[ -d /sys/class/gpio/gpio$g ] || echo $g > /sys/class/gpio/export
	echo low > /sys/class/gpio/gpio$g/direction
done
mkdir -p /dev/socket /data/location/com.broadcom.gps/logs
cd /data/location || exit 1
killall -q location brcm_guci_drv; sleep 1
timeout $((T + 20)) python3 /root/android-socket-exec.py gpshal_socket,location_shim,gps_tcmd -- \
	/system/bin/location > /tmp/location.out 2>&1 &
sleep 3
LD_PRELOAD=/system/lib/libgpsshim.so timeout $T \
	/system/bin/brcm_guci_drv -config /system/etc/gpsconfig-xoom.xml $JOBARG > /tmp/guci.out 2>&1
echo "fim rc=$?" >> /tmp/guci.out
