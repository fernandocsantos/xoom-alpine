#!/bin/sh
# configversion: f1282bb39c782471bb788ccf8df0bb76
# Menu de apps do Sxmo: lista padrão + apps instalados à mão em /usr/local
# (o Sxmo usa o primeiro sxmo_hook_apps.sh do PATH; ~/.config/sxmo/hooks vem antes)

. sxmo_hook_icons.sh

/usr/share/sxmo/default_hooks/sxmo_hook_apps.sh

[ -x /usr/local/bin/trocar-sessao ] && [ -x /usr/bin/phosh-session ] && printf "%s ^ 0 ^ %s\n" "$icon_phn Trocar para o Phosh" "/usr/local/bin/trocar-sessao phosh"
