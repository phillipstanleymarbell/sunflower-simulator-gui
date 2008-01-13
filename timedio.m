TimedIO : module
{
	PATH		: con "/dis/sfgui/timedio.dis";

	timedopen	: fn(file: string, omode, timeout: int): ref Sys->FD;
	timedread	: fn(fd: ref Sys->FD, buf: array of byte, nbytes, timeout: int): int;
	timedwrite	: fn(fd: ref Sys->FD, buf: array of byte, nbytes, timeout: int): int;
	timedmount	: fn(fd: ref Sys->FD, afd: ref Sys->FD, old: string, flag: int, 
				aname: string, timeout: int): int;
	timedunmount	: fn(name, old: string, timeout: int): int;
	timedreaddir	: fn(path: string, sortkey, timeout: int): (array of ref Sys->Dir, int);
	timedauclient	: fn(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD,
				timeout: int): (ref Sys->FD, string);
	timeddial	: fn(addr, local: string, timeout: int): (int, Sys->Connection);

	init		: fn(): string;
	shutdown	: fn();
};
