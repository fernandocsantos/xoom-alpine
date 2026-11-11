# Inicia a sessão gráfica no tty1; o seatd dá acesso à tela e ao touch.
# Sessão: Sxmo (sway) por padrão. Com ~/.config/sessao-phosh presente, sobe o
# Phosh (/usr/local/bin/phosh-sessao: phoc + phosh pelo gnome-session); com
# ~/.config/phosh-gles2 o phoc desenha pela GPU (grate). Se o Phosh morrer em menos
# de 60 s, grava ~/.cache/phosh-falhou e cai no Sxmo na hora (e nos logins
# seguintes, até apagar esse arquivo). Alternar: trocar-sessao phosh|sxmo.
# Renderizador do Sxmo: pixman (software) por padrão. Com ~/.config/sxmo-gles2 presente,
# usa GLES2 pelo Mesa do grate (/opt/grate; lib-sway = grate sem a libdrm antiga,
# que não tem os símbolos que o wlroots 0.20 usa). Para reiniciar a sessão:
# kill do PID da sway (pkill -x sway não acha: o processo é o loader do musl). Se o sway com GLES2 morrer em
# menos de 20 s, grava ~/.cache/sxmo-gles2-falhou e o próximo login usa pixman.
if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ]; then
	export LIBSEAT_BACKEND=seatd
	pfalhou="$HOME/.cache/phosh-falhou"
	gfalhou="$HOME/.cache/phosh-gles2-falhou"
	if [ -e "$HOME/.config/sessao-phosh" ] && [ ! -e "$pfalhou" ]; then
		# GLES2 no phoc (grate) com ~/.config/phosh-gles2; se cair em < 60 s, grava
		# ~/.cache/phosh-gles2-falhou e tenta já com pixman; se esse cair também,
		# grava ~/.cache/phosh-falhou e sobe o Sxmo.
		if [ -e "$HOME/.config/phosh-gles2" ] && [ ! -e "$gfalhou" ]; then
			/usr/local/bin/phosh-sessao gles2 > "$HOME/.phosh.log" 2>&1 && exit
			mkdir -p "$HOME/.cache"
			cp "$HOME/.phosh.log" "$gfalhou"
		fi
		/usr/local/bin/phosh-sessao pixman > "$HOME/.phosh.log" 2>&1 && exit
		mkdir -p "$HOME/.cache"
		cp "$HOME/.phosh.log" "$pfalhou"
	fi
	falhou="$HOME/.cache/sxmo-gles2-falhou"
	if [ -e "$HOME/.config/sxmo-gles2" ] && [ ! -e "$falhou" ]; then
		# /opt/grate/bin/sway chama o loader do musl com --library-path: a
		# /usr/bin/sway tem cap_sys_nice e por isso o musl ignora LD_LIBRARY_PATH.
		export PATH="/opt/grate/bin:$PATH"
		# Só a sway usa o Mesa do grate (o wrapper passa --library-path e o
		# Mesa do grate acha /opt/grate/lib/dri sozinho): nada de LD_LIBRARY_PATH
		# para não vazar para os apps.
		export WLR_RENDERER=gles2
		inicio=$(date +%s)
		sxmo_swayinit.sh > "$HOME/.sxmo-sway.log" 2>&1
		if [ $(( $(date +%s) - inicio )) -lt 20 ]; then
			mkdir -p "$HOME/.cache"
			cp "$HOME/.sxmo-sway.log" "$falhou"
		fi
		exit
	fi
	export WLR_RENDERER=pixman
	exec sxmo_swayinit.sh > "$HOME/.sxmo-sway.log" 2>&1
fi
