#!/usr/bin/env python3
"""
android-socket-exec.py NOME[,NOME...] -- PROGRAMA [ARGS...]

Faz o papel do init do Android para um serviço com linhas "socket NOME stream":
cria cada socket UNIX em /dev/socket/NOME (stream, modo 0660), deixa o fd herdável
e o passa ao programa na variável ANDROID_SOCKET_NOME (é o que
android_get_control_socket() do libcutils lê).
"""
import os
import socket
import sys

if len(sys.argv) < 4 or sys.argv[2] != "--":
    sys.exit(__doc__)

os.makedirs("/dev/socket", exist_ok=True)
manter = []
for nome in sys.argv[1].split(","):
    caminho = "/dev/socket/" + nome
    try:
        os.unlink(caminho)
    except FileNotFoundError:
        pass
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(caminho)
    os.chmod(caminho, 0o660)
    fd = s.detach()
    os.set_inheritable(fd, True)
    os.environ["ANDROID_SOCKET_" + nome] = str(fd)
    manter.append(fd)

os.execv(sys.argv[3], sys.argv[3:])
