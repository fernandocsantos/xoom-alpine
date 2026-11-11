#!/bin/sh
# Motorola Xoom (stingray), kernel mainline. Lido pelo Sxmo a partir do
# compatible do device tree ("motorola,stingray").
export SXMO_NO_MODEM=1
export SXMO_MONITOR="LVDS-1"
export SXMO_POWER_BUTTON="0:0:cpcap-pwrbutton"
export SXMO_VOLUME_BUTTON="1:1:gpio-keys"
export SXMO_SWAY_SCALE="1"
