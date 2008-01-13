implement TimedIO;

include "sys.m";
include "readdir.m";
include "keyring.m";
include "timers.m";
include "security.m";
include "timedio.m";

sys	: Sys;
timers	: Timers;
readdir	: Readdir;
au	: Auth;

Timer	: import timers;


init(): string
{
	sys = load Sys Sys->PATH;

	timers	= load Timers Timers->PATH;
	readdir	= load Readdir Readdir->PATH;
	au	= load Auth Auth->PATH;

	if (timers == nil || readdir == nil || au == nil)
	{
		return sys->sprint("TimedIO->init(): could not load Timers/Readdir/Auth module: %r");
	}

	if ((err := au->init()) != nil)
	{
		return sys->sprint("Could not init Auth module: %s", err);
	}
	timers->init(1);

	return nil;
}

shutdown()
{
	timers->shutdown();
}
	
timedopen(file: string, omode, timeout: int): ref Sys->FD
{
	rfd	: ref Sys->FD;
	fdchan	:= chan of ref Sys->FD;
	pidchan	:= chan of int;

	t := Timer.start(timeout/1000);
	spawn open_worker(file, omode, fdchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		rfd =<- fdchan	=>
			t.stop();

		<- t.timeout	=>
			sys->werrstr(sys->sprint(
				"TimedIO->timedopen() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return rfd;
}

open_worker(file: string, omode: int, fdchan: chan of ref Sys->FD, pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	fd := sys->open(file, omode);
	fdchan <-= fd;

	return;
}

timedread(fd: ref Sys->FD, buf: array of byte, nbytes, timeout: int): int
{
	nchan	:= chan of int;
	pidchan	:= chan of int;
	n	:= -1;

	t := Timer.start(timeout/1000);
	spawn read_worker(fd, buf, nbytes, nchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		n =<- nchan	=>
			t.stop();

		<- t.timeout	=>
			sys->werrstr(sys->sprint(
				"TimedIO->timedread() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return n;
}

read_worker(fd: ref Sys->FD, buf: array of byte, nbytes: int, nchan, pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	n := sys->read(fd, buf, nbytes);
	nchan <-= n;

	return;
}


timedwrite(fd: ref Sys->FD, buf: array of byte, nbytes, timeout: int): int
{
	nchan	:= chan of int;
	pidchan	:= chan of int;
	n	:= -1;

	t := Timer.start(timeout/1000);
	spawn write_worker(fd, buf, nbytes, nchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		n =<- nchan	=>
			t.stop();

		<- t.timeout	=>
			sys->werrstr(sys->sprint(
				"TimedIO->timedwrite() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return n;
}

write_worker(fd: ref Sys->FD, buf: array of byte, nbytes: int, nchan, pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	n := sys->write(fd, buf, nbytes);
	nchan <-= n;

	return;
}

timedmount(fd: ref Sys->FD, afd: ref Sys->FD, old: string, flag: int, 
				aname: string, timeout: int): int
{
	nchan	:= chan of int;
	pidchan	:= chan of int;
	n	:= -1;

	t := Timer.start(timeout/1000);
	spawn mount_worker(fd, afd, old, flag, aname, nchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		n =<- nchan	=>
			t.stop();

		<- t.timeout	=>
			sys->werrstr(sys->sprint(
				"TimedIO->timedmount() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return n;
}

mount_worker(fd: ref Sys->FD, afd: ref Sys->FD, old: string, flag: int, 
				aname: string, nchan, pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	n := sys->mount(fd, afd, old, flag, aname);
	nchan <-= n;

	return;
}

timedunmount(name, old: string, timeout: int): int
{
	nchan	:= chan of int;
	pidchan	:= chan of int;
	n	:= -1;

	t := Timer.start(timeout/1000);
	spawn unmount_worker(name, old, nchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		n =<- nchan	=>
			t.stop();

		<- t.timeout	=>
			sys->werrstr(sys->sprint(
				"TimedIO->timedunmount() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return n;
}

unmount_worker(name, old: string, nchan, pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	n := sys->unmount(name, old);
	nchan <-= n;

	return;
}

timedreaddir(path: string, sortkey, timeout: int): (array of ref Sys->Dir, int)
{
	rchan	:= chan of (array of ref Sys->Dir, int);
	dirs	: array of ref Sys->Dir;
	pidchan	:= chan of int;
	n	:= -1;

	t := Timer.start(timeout/1000);
	spawn readdir_worker(path, sortkey, rchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		(dirs, n) =<- rchan	=>
			t.stop();

		<- t.timeout		=>
			sys->werrstr(sys->sprint(
				"TimedIO->timedreaddir() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return (dirs, n);
}

readdir_worker(path: string, sortkey: int, rchan: chan of (array of ref Sys->Dir, int),
	pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	(dirs, n) := readdir->init(path, sortkey);
	rchan <-= (dirs, n);

	return;
}

timedauclient(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD,
				timeout: int): (ref Sys->FD, string)
{
	rchan	:= chan of (ref Sys->FD, string);
	rfd	: ref Sys->FD;
	pidchan	:= chan of int;
	info	:= "";

	t := Timer.start(timeout/1000);
	spawn auclient_worker(alg, ai, fd, rchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		(rfd, info) =<- rchan	=>
			t.stop();

		<- t.timeout		=>
			sys->werrstr(sys->sprint(
				"TimedIO->timedauclient() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return (rfd, info);
}

auclient_worker(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD,
	rchan: chan of (ref Sys->FD, string), pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	(rfd, info) := au->client(alg, ai, fd);
	rchan <-= (rfd, info);

	return;
}


timeddial(addr, local: string, timeout: int): (int, Sys->Connection)
{
	rchan	:= chan of (int, Sys->Connection);
	pidchan	:= chan of int;
	rc	: Sys->Connection;
	ok	:= -1;

	t := Timer.start(timeout/1000);
	spawn dial_worker(addr, local, rchan, pidchan);
	workerpid :=<- pidchan;

	alt
	{
		(ok, rc) =<- rchan	=>
			t.stop();

		<- t.timeout		=>
			sys->werrstr(sys->sprint(
				"TimedIO->timeddial() timed out after %d us.",
				timeout));
			killpid(workerpid);
	}
	
	return (ok, rc);
}

dial_worker(addr, local: string, rchan: chan of (int, Sys->Connection), pidchan: chan of int)
{
	pidchan <-= sys->pctl(0, nil);
	(ok, rc) := sys->dial(addr, local);
	rchan <-= (ok, rc);

	return;
}

killpid(pid: int)
{
	msg	:= array of byte "kill";
	fd	:= sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);

	if (fd != nil)
	{
		sys->write(fd, msg, len msg);
	}

	return ;
}
