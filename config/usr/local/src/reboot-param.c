/*
 * reboot-param: reinicia passando um argumento ao kernel (LINUX_REBOOT_CMD_RESTART2),
 * por exemplo "bootloader" (fastboot) ou "recovery". O reboot do busybox não passa
 * argumento. Uso normal: pelo /usr/local/sbin/reboot-bootloader, que deixa o
 * argumento em /run/reboot-param e chama o reboot do busybox; o inittab roda
 * "reboot-param --from-inittab" depois do "openrc shutdown" (discos já em ro).
 *
 * gcc -O2 -o /usr/local/sbin/reboot-param reboot-param.c
 */
#include <linux/reboot.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#define PARAM_FILE "/run/reboot-param"

int main(int argc, char **argv)
{
	char arg[64] = "";

	if (argc == 2 && !strcmp(argv[1], "--from-inittab")) {
		FILE *f = fopen(PARAM_FILE, "r");

		if (!f)
			return 0;	/* reboot ou poweroff normal: nada a fazer */
		if (!fgets(arg, sizeof(arg), f))
			arg[0] = '\0';
		fclose(f);
		arg[strcspn(arg, "\r\n")] = '\0';
		unlink(PARAM_FILE);
		if (!arg[0])
			return 0;
	} else if (argc == 2) {
		snprintf(arg, sizeof(arg), "%s", argv[1]);
	} else {
		fprintf(stderr, "uso: %s <bootloader|recovery|...> | --from-inittab\n", argv[0]);
		return 2;
	}

	sync();
	syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		LINUX_REBOOT_CMD_RESTART2, arg);
	perror("reboot");
	return 1;
}
