implement Mgui;

include "sys.m";
include "draw.m";
include "math.m";
include "freetype.m";
include "pgui.m";
include "string.m";
include "keyring.m";
include "security.m";
include "styxpersist.m";
include "tk.m";
include "wmsrv.m";
include "wmclient.m";
include "imagefile.m";
include "bufio.m";
include "readdir.m";
include "lock.m";
include "timers.m";
include "cache.m";
include "mgui.m";
include "timedio.m";
include "dialog.m";
include "selectfile.m";
include "tkclient.m";
include "winplace.m";


winplace		: Winplace;
dialog			: Dialog;
selectfile		: Selectfile;
tk			: Tk;
tkclient		: Tkclient;
str			: String;
lock			: Lock;
sys			: Sys;
wmclient		: Wmclient;
wmsrv			: Wmsrv;
bufio			: Bufio;
pgui			: Pgui;
timedio			: TimedIO;
draw			: Draw;
cache			: Cache;
random			: Random;
PFont,
	ZP,
	PTextEntry,
	PScrollableText,
	PScrollableList,
	PScrollBar,
	PButton,
	PFileDialog,
	PG_LTARROW,
	PG_RTARROW	: import pgui;
Context,
	Display,
	Font,
	Image,
	Point,
	Pointer,
	Rect,
	Screen,
	Wmcontext	: import draw;
timedopen,
	timedread,
	timedwrite,
	timedmount,
	timedunmount,
	timedreaddir,
	timedauclient,
	timeddial	: import timedio;
StrCache		: import cache;
Window, 
	Client		: import wmsrv;
Iobuf 			: import bufio;
Semaphore		: import lock;

M			: MguiState;

DEBUG			: con 0;

#	Stuff from /appl/wm/wm.b.
#	Needs major cleanup:
ptrfocus: ref Client;
kbdfocus: ref Client;
controller: ref Client;
allowcontrol := 1;
fakekbd: chan of string;
fakekbdin: chan of string;
buttons := 0;
lastrect: Rect;
Ptrstarted, Kbdstarted, Controlstarted, Controller, Fixedorigin: con 1<<iota;
Minx, Miny, Maxx, Maxy: con 1<<iota;
Sminx, Sminy, Smaxx, Smaxy: con iota;
Bdwidth: con 3;


init(ctxt: ref Context, args: list of string)
{
	buf	:= array [Sys->ATOMICIO] of byte;


	sys	= load Sys Sys->PATH;
	str	= load String String->PATH;
	bufio	= load Bufio Bufio->PATH;
	lock	= load Lock Lock->PATH;
	timedio	= load TimedIO TimedIO->PATH;
	cache	= load Cache Cache->PATH;
	random	= load Random Random->PATH;

	if (str == nil || bufio == nil || lock == nil || timedio == nil || cache == nil || random == nil)
	{
		fatal(sys->sprint(
			"Could not load String/Bufio/Readdir/Lock/TimedIO/Cache/Random modules: %r."));
	}

	if ((err := timedio->init()) != nil)
	{
		fatal(sys->sprint("Could not initialize TimedIO module: %s.", err));
	}

	#
	#	Fork pgrp+ns ASAP. Will also fork name space again
	#	to be separate from export later in services()
	#
	M.savedargs = args;
	M.pgrp = sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	M.stderr = sys->fildes(2);
	M.gui = 1;
	M.engineid = random->randomint(Random->ReallyRandom);

	tmpfd := sys->open("#e/emuroot", Sys->OREAD);
	if (tmpfd == nil)
	{
		fatal(sys->sprint("Could not open #e/emuroot: %r"));
	}

	n := sys->read(tmpfd, buf, len buf);
	if (n < 0)
	{
		fatal(sys->sprint("Could not read #e/emuroot: %r"));
	}
	status(sys->sprint("Root directory is \"%s\"", string buf[:n]));

	tmpfd = sys->open("#e/emuhost", Sys->OREAD);
	if (tmpfd == nil)
	{
		fatal(sys->sprint("Could not open #e/emuhost: %r"));
	}

	n = sys->read(tmpfd, buf, len buf);
	if (n < 0)
	{
		fatal(sys->sprint("Could not read #e/emuhost: %r"));
	}
	status(sys->sprint("Host architecture is \"%s\"", string buf[:n]));

	tmpfd = sys->open("#e/emuargs", Sys->OREAD);
	if (tmpfd == nil)
	{
		fatal(sys->sprint("Could not open #e/emuargs: %r"));
	}

	n = sys->read(tmpfd, buf, len buf);
	if (n < 0)
	{
		fatal(sys->sprint("Could not read #e/emuargs: %r"));
	}
	status(sys->sprint("Run with host args \"%s\"", string buf[:n]));
sys->print("1");
	#	Get rid of program name
	(nil, emuargs) := str->splitstrl(string buf[:n], " ");

	(l1, r1) := str->splitstrl(emuargs, "-I");
	(l2, r2) := str->splitstrl(emuargs, "-d");
	if (r1 != nil || r2 != nil)
	{
		M.daemonized = 1;
		M.gui = 0;
		status("Running in daemonized console mode");
	}

	if ((len args == 2) && (hd tl args == "-nogui"))
	{
		status("Running in console mode...");
		M.gui = 0;
	}
	else if (len args >= 2)
	{
		usage();
		cleanexit();
	}

	(there, nil) := sys->stat("/net/cs");
	if (there == -1)
	{
		cs := load Command "/dis/ndb/cs.dis";
		if (cs == nil)
		{
			fatal("Could not load /dis/ndb/cs.dis");
		}
		cs->init(nil, "cs"::nil);
	}

	(there, nil) = sys->stat("/net/dns");
	if (there == -1)
	{
		dns := load Command "/dis/ndb/dns.dis";
		if (dns == nil)
		{
			fatal("Could not load /dis/ndb/dns.dis");
		}
		dns->init(nil, "dns"::nil);
	}


	M.sem_cachedhosts	= Semaphore.new();
	M.sem_cachednodes	= Semaphore.new();
	M.sem_curhost		= Semaphore.new();
	M.sem_curnode		= Semaphore.new();
	
	M.mntcache = StrCache.new();
	if (M.mntcache == nil)
	{
		fatal("Could not initialize a StrCache.");
	}


	hostname := sysname();
	status(sys->sprint("Local host name is \"%s\"", hostname));
	status("Attaching local simulation engine...");

	if (sys->bind("#*sunflower!"+hostname+sys->sprint(".%uX", M.engineid), MG_MNTDIR, sys->MBEFORE) < 0)
	{
		fatal("Could not attach local simulation engine:"+
			sys->sprint("%r"));
	}

	status("Unioning local filesystem into / ...");
	ok := sys->bind("#U*", "/", Sys->MAFTER);
	if (ok < 0)
	{
		error(sys->sprint("Could not bind host filesystem ('#U*'): %r"));
	}

	ls := load Command "/dis/ls.dis";
	ls->init(nil, "ls"::"-ls"::MG_MNTDIR::nil);

	sync := chan of int;
	spawn enginectl(MG_MNTDIR+"sunflower."+hostname+sys->sprint(".%uX", M.engineid), sync);
	<- sync;

	#	Walk the device to pick up the node and lists
	M.setcachedhosts(getdevhostlist());

	#	Don't call setcachednodes though, because it needs gui init to be done (easier that way)
#	M.setcachednodes(getdevnodelist());

	tmp := M.getcachedhosts();
	if (tmp == nil)
	{
		fatal("No usable local engine (getdevnodelist() returned nil).");
	}

	M.localhost = hd tmp;
	status(sys->sprint("Local simulation engine @ %s", M.localhost.mntpt));
	M.curhost = M.localhost;

	#
	#	Need to spawn this off so we can detach export
	#	from name space, but only after enginectl is made
	#
	spawn services();

	if (M.gui)
	{	
		spawn guiinit(ctxt, sync);
		<-sync;
	}
}

allocmsgwin() : ref PScrollableText
{
	mr := get_msgswinrect();
	pmr := Rect (mr.min.add((MG_INPUTRECT_HOFFSET, 0)), mr.max);
	pmr = pmr.inset(MG_TEXTBOX_INSET);
	(msgwin, e) := PScrollableText.new(M.screen,
			pmr, MG_MSGS_FONT, MG_DFLT_TXTBUFLEN, Draw->White, Draw->White);
	##		pmr, "/appl/sfgui/fonts/ttf/LUCON.TTF", MG_DFLT_TXTBUFLEN,
	##		Draw->White, Draw->White);

	fatal(e);

	msgwin.setlinespacing(MG_DEFAULT_LINESPACING);
	msgwin.autoscroll = 1;
	msgwin.settxtimg(M.display.color(Draw->Black));

	return msgwin;
}

guiinit(ctxt : ref Draw->Context, guiinitsync : chan of int)
{
	draw		= load Draw Draw->PATH;
	wmsrv		= load Wmsrv Wmsrv->PATH;
	pgui		= load Pgui Pgui->PATH;
	tk		= load Tk Tk->PATH;
	tkclient	= load Tkclient Tkclient->PATH;
	selectfile	= load Selectfile Selectfile->PATH;
	dialog		= load Dialog Dialog->PATH;
	wmclient	= load Wmclient Wmclient->PATH;
	winplace	= load Winplace Winplace->PATH;


	#	So that fatal() etc. dont try to use an un-init graphics subsystem:
	M.gui = 0;

	if (draw == nil || wmsrv == nil || pgui == nil || tk == nil ||
		tkclient == nil || wmclient == nil || winplace == nil ||
		selectfile == nil || dialog == nil)
	{
		fatal(sys->sprint("Could not load %s modules : %r\n",
			"Draw/Wmsrv/Pgui/Tk/Tkclient/Slectfile/Dialog/Wmclient/Winplace"));
	}

	tkclient->init();
	selectfile->init();
	dialog->init();
	wmclient->init();
	winplace->init();

	(there, dir) := sys->stat("/dev/draw");
	if ((there == -1) || (dir.qid.qtype != Sys->QTDIR) || (dir.dtype != 'i'))
	{
		ok := sys->bind("#i", "/dev", Sys->MBEFORE);
		if (ok < 0)
		{
			fatal(sys->sprint("Could not bind draw module: %r"));
		}
	}

	if (ctxt == nil)
	{
		ctxt = wmclient->makedrawcontext();
	}
	if (ctxt == nil)
	{
		fatal(sys->sprint("Could not make or inherit a graphics context: %r"));
	}

	M.display = ctxt.display;
	M.ctxt = ctxt;

	(ok, err) := pgui->init();
	if (ok < 0)
	{
		fatal(sys->sprint("Initialization of PGui failed: %s", err));
	} 

	buts := Wmclient->Appl;
	if (ctxt.wm == nil)
	{
		buts = Wmclient->Plain;
	}

	M.win = wmclient->window(ctxt, "Sgui : Sunflower Simulator Control Interface", buts);
	wmclient->M.win.reshape(((0, 0), (900, 700)));
	wmclient->M.win.onscreen(nil);
	if (M.win.image == nil)
	{
		fatal("Mgui: cannot get image to draw on.");
	}

	wmclient->M.win.startinput("kbd" :: "ptr" :: nil);
	(clientwm, join, req) := wmsrv->init();
	clientctxt := ref Draw->Context(ctxt.display, ctxt.screen, clientwm);

	spawn toolbar(clientctxt);

	bg := M.display.color(MG_DEFAULT_BGCOLOR);
	M.screen = Screen.allocate(M.win.image, bg, 0);
	M.win.image.draw(M.win.image.r, M.screen.fill, nil, M.screen.fill.r.min);







	#
	#	Most of this drawing should go into Pgui
	#
	e := "";


	#	Global msgs window reference is pmsg. It is updated when we set the current node
	mr := get_msgswinrect();
	msgsbgwin := M.screen.newwindow(mr, Draw->Refbackup, Draw->White);
	M.display.image.draw(mr, msgsbgwin, nil, mr.min);
	mrborder := pgui->getrectborder(mr);
	M.display.image.poly(mrborder, Draw->Enddisc, Draw->Enddisc,
			MG_WINBORDER_PIXELS, M.display.color(MG_DEFAULT_BORDERCOLOR), mr.min);
	pmsgwin = allocmsgwin();
	#pmsgwin = M.getcurnode().msgwin;


	#
	#	Scrollbar for msgs window
	#
	smr := get_msgswinscrollrect();
	(pscrollmsgwin, e) = PScrollBar.new(M.screen, smr, 0, MG_DFLT_TXTBUFLEN,
				MG_COLOR_LIGHTORANGE, Draw->White);
	fatal(e);


	#	Input box
	ir := get_inputwinrect();
	irbgwin := M.screen.newwindow(ir, Draw->Refbackup, Draw->White);
	M.display.image.draw(ir, irbgwin, nil, ir.min);
	irborder := pgui->getrectborder(ir);
	M.display.image.poly(irborder, Draw->Enddisc, Draw->Enddisc,
			MG_WINBORDER_PIXELS, M.display.color(MG_DEFAULT_BORDERCOLOR), ir.min);
	(pinputwin, e) = PTextEntry.new(MG_PROMPT, M.screen,
			ir.inset(MG_INPUTBOX_INSET),
			MG_INPUT_FONT, MG_INPUT_HISTORYLEN, Draw->White, Draw->White);
	fatal(e);
	pinputwin.s.settxtimg(M.display.color(Draw->Black));
	pinputwin.s.append(MG_PROMPT);
	


	#	Remote hosts
	rr := get_remotewinrect();
	rrbgwin := M.screen.newwindow(rr, Draw->Refbackup, Draw->White);
	M.display.image.draw(rr, rrbgwin, nil, rr.min);
	rrborder := pgui->getrectborder(rr);
	M.display.image.poly(rrborder, Draw->Enddisc, Draw->Enddisc,
			MG_WINBORDER_PIXELS, M.display.color(MG_DEFAULT_BORDERCOLOR), rr.min);
	prr := Rect (rr.min.add((MG_INPUTRECT_HOFFSET, 0)), rr.max);
	prr = prr.inset(MG_TEXTBOX_INSET);
	(prmtwin, e) = PScrollableText.new(M.screen,
			prr, MG_REMOTEHOSTS_FONT, MG_DFLT_REMOTEBUFLEN,
			Draw->White, Draw->White);
	fatal(e);
	prmtwin.setlinespacing(MG_DEFAULT_LINESPACING);
	prmtwin.autoscroll = 1;
	prmtwin.settxtimg(M.display.color(MG_COLOR_DARKORANGE));



	#	Node info
	nr := get_nodeinforect();
	nrbgwin := M.screen.newwindow(nr, Draw->Refbackup, Draw->White);
	M.display.image.draw(nr, nrbgwin, nil, nr.min);
	nrborder := pgui->getrectborder(nr);
	M.display.image.poly(nrborder, Draw->Enddisc, Draw->Enddisc,
			MG_WINBORDER_PIXELS, M.display.color(MG_DEFAULT_BORDERCOLOR), nr.min);
	pnr := nr.inset(3);
	(pnodeinfowin, e) = PScrollableText.new(M.screen,
			pnr, MG_NODEINFO_FONT, MG_DFLT_REMOTEBUFLEN, Draw->White, Draw->White);

	fatal(e);
	pnodeinfowin.setlinespacing(1.0);
	pnodeinfowin.autoscroll = 0;
	pnodeinfowin.settxtimg(M.display.color(Draw->Black));



	#	Errors
	er := get_errwinrect();
	erbgwin := M.screen.newwindow(er, Draw->Refbackup, Draw->White);
	M.display.image.draw(er, erbgwin, nil, er.min);
	erborder := pgui->getrectborder(er);
	M.display.image.poly(erborder, Draw->Enddisc, Draw->Enddisc,
			MG_WINBORDER_PIXELS, M.display.color(MG_DEFAULT_BORDERCOLOR), er.min);
	per := Rect (er.min.add((3*MG_INPUTRECT_HOFFSET/4, 0)), er.max);
	per = per.inset(MG_TEXTBOX_INSET);
	(perrwin, e) = PScrollableText.new(M.screen,
			per, MG_ALERT_FONT, MG_DFLT_ERRBUFLEN, Draw->White, Draw->White);
	fatal(e);
	perrwin.setlinespacing(MG_DEFAULT_LINESPACING);
	perrwin.autoscroll = 1;
	perrwin.settxtimg(M.display.color(Draw->Red));



	#	Warnings
	sr := get_sanitywinrect();
	srbgwin := M.screen.newwindow(sr, Draw->Refbackup, Draw->White);
	M.display.image.draw(sr, srbgwin, nil, sr.min);
	srborder := pgui->getrectborder(sr);
	M.display.image.poly(srborder, Draw->Enddisc, Draw->Enddisc,
			MG_WINBORDER_PIXELS, M.display.color(MG_DEFAULT_BORDERCOLOR), sr.min);
	psr := Rect (sr.min.add((3*MG_INPUTRECT_HOFFSET/4, 0)), sr.max);
	psr = psr.inset(MG_TEXTBOX_INSET);
	(psanitywin, e) = PScrollableText.new(M.screen,
			psr, MG_ALERT_FONT, MG_DFLT_ERRBUFLEN, Draw->White, Draw->White);
	fatal(e);
	psanitywin.setlinespacing(MG_DEFAULT_LINESPACING);
	psanitywin.autoscroll = 1;
	psanitywin.settxtimg(M.display.color(Draw->Black));


	
	#	Author and PGP key stuff
	ar := get_authorwinrect();
	(pauthorswin, e) = PScrollableText.new(M.screen, ar,
			MG_AUTHORS_FONT, MG_DFLT_AUTHNLINES,
			MG_DEFAULT_BGCOLOR, MG_DEFAULT_BGCOLOR);
	fatal(e);
	pauthorswin.setlinespacing(1.0);
	pauthorswin.autoscroll = 0;
	pauthorswin.settxtimg(M.display.color(MG_DEFAULT_AUTHORSCOLOR));
	pauthorswin.setbgimg(M.display.color(Draw->Transparent));
	pauthorswin.append(
		"Sunflower simulator GUI.  Authored, 2004-2008, by phillip stanley-marbell\n");
	pauthorswin.append(
		"Public key fingerprint 62A1 E95D 304D 9876 D5B1  1FB2 BF7E B65F BD89 20AB\n");
	pauthorswin.append(
		"This software is provided with ABSOLUTELY NO WARRANTY. Read LICENSE.txt\n");



	#	Icons and other graphics
	#br := get_bannerwinrect();
	#bannerwin := M.screen.newwindow(br, Draw->Refbackup, MG_DEFAULT_BGCOLOR);
	#pgui->drawimgfromfile(MG_BANNERIMG, br, bannerwin);

	pgui->drawimgfromfile(MG_REMOTEIMG,
		get_remotewinrect().inset(MG_TEXTBOX_INSET), M.display.image);
	pgui->drawimgfromfile(MG_KEYBOARDIMG,
		get_inputwinrect().inset(MG_INPUTBOX_INSET).subpt((MG_INPUTRECT_HOFFSET, 0)),
		M.display.image);
	pgui->drawimgfromfile(MG_WARNIMG,
		get_sanitywinrect().inset(MG_TEXTBOX_INSET), M.display.image);
	pgui->drawimgfromfile(MG_ERRORIMG,
		get_errwinrect().inset(MG_TEXTBOX_INSET), M.display.image);

	#	For now, leave out the attempt to get a transparent banner...
	#M.display.image.draw(br, bannerwin, nil, br.min);






	
	M.gui 		= 1;
	M.kbdchan	= chan of int;
	M.msgschan 	= chan of string;
	M.tpgymousechan	= chan of Pointer;
	M.updatetopology= chan of int;

	M.tpgyfont	= Font.open(M.screen.display, MG_TPGY_FONT);
	if (M.tpgyfont == nil)
	{
		M.tpgyfont = Font.open(M.screen.display, "*default*");
	}
	if (M.tpgyfont == nil)
	{
		fatal(sys->sprint("Could not open *default* font: %r"));
	}


	sync := chan of int;
	spawn kbd(M.kbdchan, sync);
	<- sync;
	spawn remotedisplay();
	spawn nodeinfodisplay();
	spawn topologydisplay();

	spawn fastrefreshproc();
	spawn tpgymouse(M.tpgymousechan);
	spawn stdioproc();
	spawn splash();

	guiinitsync <-= 0;
	M.guiinit = 1;

	for (;;)
	alt
	{
	c := <-M.win.ctl or c = <-M.win.ctxt.ctl =>
		M.splashactive = 0;
		if (c == "exit")
		{
			cleanexit();
		}

		wmclient->M.win.wmctl(c);
		if(M.win.image != M.screen.image)
		{
			reshaped(M.win);
		}

	c := <-M.win.ctxt.kbd =>
		M.splashactive = 0;
		M.kbdchan <-= c;

		#
		#	TODO: a copy of this pointer event should be sent to Pwm, a
		#	window manager that is built on Pgui and monitors which window
		#	is active and updates thats window's border.
		#
	p := <-M.win.ctxt.ptr =>
		#
		#	Pointer events are first passed to titlebar
		#	then if not consumed, handled by us
		#
		if(wmclient->M.win.pointer(*p))
		{
			break;
		}

		if (p.buttons)
		{
			M.splashactive = 0;
			M.tpgymousechan <-= *p;
		}
#####
		if(p.buttons && (ptrfocus == nil || buttons == 0))
		{
			c := wmsrv->find(p.xy);
			if(c != nil){
				ptrfocus = c;
				c.ctl <-= "raise";
				setkbdfocus(c);
			}
		}
		if(ptrfocus != nil && (ptrfocus.flags & Ptrstarted) != 0)
		{
			buttons = p.buttons;
			ptrfocus.ptr <-= p;
			break;
		}
		buttons = 0;
####
	(c, rc) := <-join =>
		rc <-= nil;
		# new client; inform it of the available screen rectangle.
		# XXX do we need to do this now we've got wmrect?
		c.ctl <-= "rect " + r2s(M.screen.image.r);
		if(allowcontrol){
			controller = c;
			c.flags |= Controller;
			allowcontrol = 0;
		}else
			controlevent("newclient " + string c.id);
	(c, data, rc) := <-req =>
		# if client leaving
		if(rc == nil){
			c.remove();
			if(c == ptrfocus)
				ptrfocus = nil;
			if(c == kbdfocus)
				kbdfocus = nil;
			if(c == controller)
				controller = nil;
			controlevent("delclient " + string c.id);
			for(z := wmsrv->top(); z != nil; z = z.znext)
				if(z.flags & Kbdstarted)
					break;
			setkbdfocus(z);
			c.stop <-= 1;
			break;
		}
		reqerr := handlerequest(M.win, M.win.ctxt, c, string data);
		n := len data;
		if(reqerr != nil)
			n = -1;
		alt{
		rc <-= (n, reqerr) =>;
		* =>;
		}
####
	}
}

#	From wm/wm.b
controlevent(e: string)
{
	if (controller != nil && (controller.flags & Controlstarted))
	{
		controller.ctl <-= e;
	}
}

#	From wm/wm.b
sweep(ptr: chan of ref Pointer, r: Rect, offset: Point, borders: array of ref Image,
	move, show: int, min: Point): Rect
{
	while ((p := <-ptr).buttons != 0)
	{
		xy := p.xy.sub(offset);
		if(move&Minx)
			r.min.x = xy.x;
		if(move&Miny)
			r.min.y = xy.y;
		if(move&Maxx)
			r.max.x = xy.x;
		if(move&Maxy)
			r.max.y = xy.y;
		showborders(borders, r, show);
	}

	r = r.canon();

	if (r.min.y < M.screen.image.r.min.y)
	{
		r.min.y = M.screen.image.r.min.y;
		r = r.canon();
	}
	if(r.dx() < min.x)
	{
		if(move & Maxx)
			r.max.x = r.min.x + min.x;
		else
			r.min.x = r.max.x - min.x;
	}
	if(r.dy() < min.y)
	{
		if(move & Maxy)
		{
			r.max.y = r.min.y + min.y;
		}
		else
		{
			r.min.y = r.max.y - min.y;
			if(r.min.y < M.screen.image.r.min.y)
			{
				r.min.y = M.screen.image.r.min.y;
				r.max.y = r.min.y + min.y;
			}
		}
	}
	return r;
}

#	From wm/wm.b
dragwin(ptr: chan of ref Pointer, c: ref Client, w: ref Window, off: Point): string
{
	if(buttons == 0)
		return "too late";
	p: ref Pointer;
	do{
		p = <-ptr;
		w.img.origin(w.img.r.min, p.xy.sub(off));
	} while (p.buttons != 0);
	c.ptr <-= p;
	buttons = 0;
	r: Rect;
	r.min = p.xy.sub(off);
	r.max = r.min.add(w.r.size());
	if(r.eq(w.r))
		return "not moved";
	reshape(c, w.tag, r);
	return nil;
}

#	From wm/wm.b
bufferproc(in, out: chan of string)
{
	h, t: list of string;
	dummyout := chan of string;
	for(;;){
		outc := dummyout;
		s: string;
		if(h != nil || t != nil){
			outc = out;
			if(h == nil)
				for(; t != nil; t = tl t)
					h = hd t :: h;
			s = hd h;
		}
		alt{
		x := <-in =>
			t = x :: t;
		outc <-= s =>
			h = tl h;
		}
	}
}

#	From wm/wm.b
showborders(b: array of ref Image, r: Rect, show: int)
{
	r = r.canon();
	b[Sminx] = showborder(b[Sminx], show&Minx,
		(r.min, (r.min.x+Bdwidth, r.max.y)));
	b[Sminy] = showborder(b[Sminy], show&Miny,
		((r.min.x+Bdwidth, r.min.y), (r.max.x-Bdwidth, r.min.y+Bdwidth)));
	b[Smaxx] = showborder(b[Smaxx], show&Maxx,
		((r.max.x-Bdwidth, r.min.y), (r.max.x, r.max.y)));
	b[Smaxy] = showborder(b[Smaxy], show&Maxy,
		((r.min.x+Bdwidth, r.max.y-Bdwidth), (r.max.x-Bdwidth, r.max.y)));
}

#	From wm/wm.b
showborder(b: ref Image, show: int, r: Rect): ref Image
{
	if(!show)
		return nil;
	if(b != nil && b.r.size().eq(r.size()))
		b.origin(r.min, r.min);
	else
		b = M.screen.newwindow(r, Draw->Refbackup, Draw->Red);
	return b;
}

#	From wm/wm.b
fitrect(w, r: Rect): Rect
{
	if(w.dx() > r.dx())
		w.max.x = w.min.x + r.dx();
	if(w.dy() > r.dy())
		w.max.y = w.min.y + r.dy();
	size := w.size();
	if (w.max.x > r.max.x)
		(w.min.x, w.max.x) = (r.min.x - size.x, r.max.x - size.x);
	if (w.max.y > r.max.y)
		(w.min.y, w.max.y) = (r.min.y - size.y, r.max.y - size.y);
	if (w.min.x < r.min.x)
		(w.min.x, w.max.x) = (r.min.x, r.min.x + size.x);
	if (w.min.y < r.min.y)
		(w.min.y, w.max.y) = (r.min.y, r.min.y + size.y);
	return w;
}

#	From wm/wm.b:	find an suitable area for a window
newrect(w, r: Rect): Rect
{
	rl: list of Rect;
	for(z := wmsrv->top(); z != nil; z = z.znext)
		for(wl := z.wins; wl != nil; wl = tl wl)
			rl = (hd wl).r :: rl;
	lastrect = winplace->place(rl, r, lastrect, w.size());
	return lastrect;
}

#	From wm/wm.b
sizewin(ptrc: chan of ref Pointer, c: ref Client, w: ref Window, minsize: Point): string
{
	borders := array[4] of ref Image;
	showborders(borders, w.r, Minx|Maxx|Miny|Maxy);
	M.screen.image.flush(Draw->Flushnow);
	while((ptr := <-ptrc).buttons == 0)
		;
	xy := ptr.xy;
	move, show: int;
	offset := Point(0, 0);
	r := w.r;
	show = Minx|Miny|Maxx|Maxy;
	if(xy.in(w.r) == 0){
		r = (xy, xy);
		move = Maxx|Maxy;
	}else {
		if(xy.x < (r.min.x+r.max.x)/2){
			move=Minx;
			offset.x = xy.x - r.min.x;
		}else{
			move=Maxx;
			offset.x = xy.x - r.max.x;
		}
		if(xy.y < (r.min.y+r.max.y)/2){
			move |= Miny;
			offset.y = xy.y - r.min.y;
		}else{
			move |= Maxy;
			offset.y = xy.y - r.max.y;
		}
	}
	return reshape(c, w.tag, sweep(ptrc, r, offset, borders, move, show, minsize));
}


#	From wm/wm.b
handlerequest(win: ref Wmclient->Window, wmctxt: ref Wmcontext, c: ref Client, req: string): string
{
#sys->print("%d: %s\n", c.id, req);
	args := str->unquoted(req);
	if(args == nil)
		return "no request";
	n := len args;
	if(req[0] == '!' && n < 3)
		return "bad arg count";
	case hd args {
	"key" =>
		# XXX should we think about restricting this capability to certain clients only?
		if(n != 2)
			return "bad arg count";
		if(fakekbdin == nil){
			fakekbdin = chan of string;
			spawn bufferproc(fakekbdin, fakekbd);
		}
		fakekbdin <-= hd tl args;
	"ptr" =>
		# ptr x y
		if(n != 3)
			return "bad arg count";
		if(ptrfocus != c)
			return "cannot move pointer";
		e := wmclient->win.wmctl(req);
		if(e == nil){
			c.ptr <-= nil;		# flush queue
			c.ptr <-= ref Pointer(buttons, (int hd tl args, int hd tl tl args), sys->millisec());
		}
	"start" =>
		if(n != 2)
			return "bad arg count";
		case hd tl args {
		"mouse" or
		"ptr" =>
			c.flags |= Ptrstarted;
		"kbd" =>
			c.flags |= Kbdstarted;
			# XXX this means that any new window grabs the focus from the current
			# application, but usually you want this to happen... how can we distinguish
			# the two cases?
			setkbdfocus(c);
		"control" =>
			if((c.flags & Controller) == 0)
				return "control not available";
			c.flags |= Controlstarted;
		* =>
			return "unknown input source";
		}
	"!reshape" =>
		# reshape tag reqid rect [how]
		# XXX allow "how" to specify that the origin of the window is never
		# changed - a new window will be created instead.
		if(n < 7)
			return "bad arg count";
		args = tl args;
		tag := hd args; args = tl args;
		args = tl args;		# skip reqid
		r: Rect;
		r.min.x = int hd args; args = tl args;
		r.min.y = int hd args; args = tl args;
		r.max.x = int hd args; args = tl args;
		r.max.y = int hd args; args = tl args;
		if(args != nil){
			case hd args{
			"onscreen" =>
				r = fitrect(r, M.screen.image.r);
			"place" =>
				r = fitrect(r, M.screen.image.r);
				r = newrect(r, M.screen.image.r);
			"exact" =>
				;
			"max" =>
				r = M.screen.image.r;			# XXX don't obscure toolbar?
			* =>
				return "unkown placement method";
			}
		}
		return reshape(c, tag, r);
	"delete" =>
		# delete tag
		if(tl args == nil)
			return "tag required";
		c.setimage(hd tl args, nil);
		if(c.wins == nil && c == kbdfocus)
			setkbdfocus(nil);
	"raise" =>
		c.top();
	"lower" =>
		c.bottom();
	"!move" or
	"!size" =>
		# !move tag reqid startx starty
		# !size tag reqid mindx mindy
		ismove := hd args == "!move";
		if(n < 3)
			return "bad arg count";
		args = tl args;
		tag := hd args; args = tl args;
		args = tl args;			# skip reqid
		w := c.window(tag);
		if(w == nil)
			return "no such tag";
		if(ismove){
			if(n != 5)
				return "bad arg count";
			return dragwin(wmctxt.ptr, c, w, Point(int hd args, int hd tl args).sub(w.r.min));
		}else{
			if(n != 5)
				return "bad arg count";
			sizewin(wmctxt.ptr, c, w, Point(int hd args, int hd tl args));
		}
	"fixedorigin" =>
		c.flags |= Fixedorigin;
	"rect" =>
		;
	"kbdfocus" =>
		if(n != 2)
			return "bad arg count";
		if(int hd tl args)
			setkbdfocus(c);
		else if(c == kbdfocus)
			setkbdfocus(nil);
	# controller specific messages:
	"request" =>		# can be used to test for control.
		if((c.flags & Controller) == 0)
			return "you are not in control";
	"ctl" =>
		# ctl id msg
		if((c.flags & Controlstarted) == 0)
			return "invalid request";
		if(n < 3)
			return "bad arg count";
		id := int hd tl args;
		for(z := wmsrv->top(); z != nil; z = z.znext)
			if(z.id == id)
				break;
		if(z == nil)
			return "no such client";
		z.ctl <-= str->quoted(tl tl args);
	"endcontrol" =>
		if(c != controller)
			return "invalid request";
		controller = nil;
		allowcontrol = 1;
		c.flags &= ~(Controlstarted | Controller);
	* =>
		if(c == controller || controller == nil || (controller.flags & Controlstarted) == 0)
			return "unknown control request";
		controller.ctl <-= "request " + string c.id + " " + req;
	}
	return nil;

}

#	From wm/wm.b
setkbdfocus(new: ref Client)
{
	old := kbdfocus;
	if(old == new || (new != nil && (new.flags & Kbdstarted) == 0))
		return;
	if(old != nil){
		old.ctl <-= "haskbdfocus 0";
	}
	
	if(new != nil){
		new.ctl <-= "raise";
		new.ctl <-= "haskbdfocus 1";
		kbdfocus = new;
	} else
		kbdfocus = nil;
}

#	From wm/wm.b
reshape(c: ref Client, tag: string, r: Rect): string
{
	w := c.window(tag);
	# if window hasn't changed size, then just change its origin and use the same image.
	if((c.flags & Fixedorigin) == 0 && w != nil && w.r.size().eq(r.size())){
		c.setorigin(tag, r.min);
	} else {
		img := M.screen.newwindow(r, Draw->Refbackup, Draw->Nofill);
		if(img == nil)
			return sys->sprint("window creation failed: %r");
		if(c.setimage(tag, img) == -1)
			return "can't do two at once";
	}
	c.top();
	return nil;
}

MG_COLOR_MENU_BG : con 16rEFEFEF;
MG_COLOR_MENU_FG : con 16r222222;
MG_COLOR_MENU_ACTIVEBG : con 16r0066CC;
MG_COLOR_MENU_ACTIVEFG : con 16rFFFFFF;

#
#	50% transparent colors. Premultiply in the alpha.
#	Could also do it with Draw->setalpha()
#
MG_COLOR_MENU_TRANS_BG : con 16r7777777F;
MG_COLOR_MENU_TRANS_FG : con 16r1010107F;
MG_COLOR_MENU_TRANS_ACTIVEBG : con 16r0032657F;
MG_COLOR_MENU_TRANS_ACTIVEFG : con 16r7F7F7F7F;


menubase: con " -bg #EFEFEF -fg #222222 -activeforeground #FFFFFF" +
		" -activebackground #0066CC -font /fonts/ttf2subf/luxisr/luxisr.14.font";
menubarcolors: con menubase;
menuitemcolors: con " -bd 1 -relief flat" + menubase;

transmenucolors: con " -bd 0 -relief flat -bg #7777777F*#7F -fg #1010107F*#7F  -activeforeground #FFFFFF" +
		" -activebackground #0066CC";

buttoncolors: con " -bd 0 -padx 2 -highlightthickness 0 -bg orange -fg #222222" +
		" -activeforeground #FFFFFF -activebackground #0066CC" +
		" -font /fonts/ttf2subf/luxisr/luxisr.14.font";

toolbar_cfg := array[] of {
	"frame .m -relief raised -bd 1 -bg #EFEFEF -fg #222222",

	"menubutton .m.mgui -text {Sunflower      }	-menu .m.mgui.menu" + menubarcolors,
	"menubutton .m.config -text {Config      }	-menu .m.config.menu" + menubarcolors,
	"menubutton .m.simulate -text {Simulate      }	-menu .m.simulate.menu" + menubarcolors,
	"menubutton .m.connect -text {Connect      }	-menu .m.connect.menu" + menubarcolors,
	"menubutton .m.tools -text {Tools      }	-menu .m.tools.menu" + menubarcolors,
	"menubutton .m.help -text {Help }		-menu .m.help.menu" + menubarcolors,

	"button .m.eqrate -state disabled -text eqr -command {send cmd eqrate}" + buttoncolors,
	"button .m.eqrateproc -state disabled -text eqrp -command {send cmd eqrateproc}" + buttoncolors,
	"button .m.eqtimeproc -state disabled -text eqtp -command {send cmd eqtimeproc}" + buttoncolors,
	"button .m.onstar -state disabled -text {on*} -command {send cmd onstar}" + buttoncolors,
	"button .m.offstar -state disabled -text {off*} -command {send cmd offstar}" + buttoncolors,
	"button .m.splicestar -state disabled -text {splice*} -command {send cmd splicestar}" + buttoncolors,

	"button .m.onlyactive -text {active} -command {send cmd onlyactive}" + buttoncolors,
	"pack .m.mgui .m.config .m.simulate .m.connect .m.tools .m.help -side left -fill x",
	"pack .m.eqrate .m.eqrateproc .m.eqtimeproc .m.onstar .m.offstar .m.splicestar .m.onlyactive -side right -fill x -ipadx 3 -ipady 2",


	"menu .m.mgui.menu" + menuitemcolors,
	".m.mgui.menu add command -height 18 -label {   About   } -command {send cmd about}",
	".m.mgui.menu add command -height 18 -label {   Preferences   } -command {send cmd preferences} -state disabled",
	".m.mgui.menu add command -height 18 -label {   Software Update   } -command {send cmd softwareupdate} -state disabled",
	".m.mgui.menu add separator",
	".m.mgui.menu add command -height 18 -label {   Exit   } -command {send cmd quit}",
	".m.mgui.menu add separator",

	"menu .m.config.menu" + menuitemcolors,
	".m.config.menu add command -height 18 -label {   Load Configuration...   } -command {send cmd open} -state disabled",
	".m.config.menu add command -height 18 -label {   Save Configuration   } -command {send cmd savec} -state disabled",
	".m.config.menu add command -height 18 -label {   Save Configuration As...   } -command {send cmd savecas} -state disabled",
	".m.config.menu add separator",
	".m.config.menu add command -height 18 -label {   Save Transcript   } -command {send cmd savet} -state disabled",
	".m.config.menu add command -height 18 -label {   Save Transcript As...   } -command {send cmd savetas} -state disabled",
	".m.config.menu add separator",

	"menu .m.simulate.menu" + menuitemcolors,
	".m.simulate.menu add command -height 18 -label {   Make node runnable   } -command {send cmd run}",
	".m.simulate.menu add command -height 18 -label {   Stop node   } -command {send cmd stop}",
	".m.simulate.menu add separator",
	".m.simulate.menu add command -height 18 -label {   Simulator On   } -command {send cmd on}",
	".m.simulate.menu add command -height 18 -label {   Simulator Off   } -command {send cmd off}",
	".m.simulate.menu add command -height 18 -label {   Simulator Reset   } -command {send cmd reset}",
	".m.simulate.menu add separator",

	"menu .m.connect.menu" + menuitemcolors,
	".m.connect.menu add command -height 18 -label {   To Hosts...   } -command {send cmd connect} -state disabled",
	".m.connect.menu add command -height 18 -label {   To Hosts from File...   } -command {send cmd connectf} -state disabled",
	".m.connect.menu add separator",

	"menu .m.tools.menu" + menuitemcolors,
	".m.tools.menu add command -height 18 -label {   Analysis...   } -command {send cmd analysis} -state disabled",
	".m.tools.menu add command -height 18 -label {   Logging...   } -command {send cmd logging} -state disabled",
	".m.tools.menu add command -height 18 -label {   Plugins...   } -command {send cmd plugins} -state disabled",
	".m.tools.menu add separator",
	".m.tools.menu add command -height 18 -label {   Report Bug/Crash...   } -command {send cmd bugreport} -state disabled",
	".m.tools.menu add separator",

	"menu .m.help.menu" + menuitemcolors,
	".m.help.menu add command -height 18 -label {   Index...   } -command {send cmd help}",
	".m.help.menu add separator",

	"focus .m.mgui",
	"pack .m -fill x",
	"pack propagate . 0",
};

toolbar(ctxt: ref Draw->Context)
{
	(toolbar, toolbarwmctl) := tkclient->toplevel(ctxt, nil, nil, Tkclient->Plain);
	tkchan := chan of string;
	tk->namechan(toolbar, tkchan, "cmd");

	r := toolbar.screenr;

	for (i := 0; i < len toolbar_cfg; i++)
	{
		tk->cmd(toolbar, toolbar_cfg[i]);
	}

	tk->cmd(toolbar, ". configure -width " + string r.dx());
	tk->cmd(toolbar, "update");

	tkclient->onscreen(toolbar, "exact");
	tkclient->startinput(toolbar, "ptr" :: "kbd" :: nil);
	tk->cmd(toolbar, "update");

	for(;;) 
	{
		alt 
		{
		key := <-toolbar.ctxt.kbd	=>
			tk->keyboard(toolbar, key);

		m := <-toolbar.ctxt.ptr	=>
			tk->pointer(toolbar, *m);

		s := <-toolbar.ctxt.ctl or
		s = <-toolbar.wreq or
		s = <-toolbarwmctl		=>
			tkclient->wmctl(toolbar, s);

		s := <-tkchan		=>
			enginectlcmd(s);
		}

		tk->cmd(toolbar, "update");
		e := tk->cmd(toolbar, "variable lasterror");
		if(e != "")
		{
			if (DEBUG) sys->print("warning: %s\n", e);
		}
	}
}

tpgymouse(pchan : chan of Pointer)
{
	for(;;)
	{
		p := <-pchan;

		#	The work to be done might involve a moribund remote fs
		spawn tpgymousework(p);
	}
}

tpgymousework(p: Pointer)
{
	#
	#	The list of cached nodes is gotten from device and their
	#	tpgyrects updated, by topologydisplay() thread.
	#
	nodes := M.getcachednodes();

	while (nodes != nil)
	{
		node	:= hd nodes;

		if (node.tpgyrect.contains(p.xy))
		{
			cmd_sethost(string node.nodehost.hostid);
			spawn devsunflowercmd(M.getcurhost(), "setnode "+ string node.ID);
			break;
		}

		nodes = tl nodes;
	}

	#	Update topology display
	M.updatetopology <-= 0;
}

splash()
{
	(splashimg, splasherr) := pgui->getimgfromfile(MG_SPLASHIMG, M.display);
	fatal(splasherr);
	splashheight := splashimg.r.dy();
	pmsgwin.layerwin.draw(pmsgwin.layerwin.r, M.display.white, nil, ZP);

	M.refresh = 0;
	M.splashactive = 1;

	##	Scroll the splash
	for (i := 0; i <= splashheight && M.splashactive; i++)
	{
		pmsgwin.layerwin.draw(pmsgwin.layerwin.r, splashimg, nil, (0, i));
		if (sys->sleep(100) < 0)
		{
			error(sys->sprint("sleep failed: %r"));
		}
	}

	spawn devsunflowercmd(M.localhost, "version");
	M.refresh = 1;

	return;
}

services()
{
	#	Need to fork name space otherwise can have a
	#	circular mount loop.
	sys->pctl(Sys->FORKNS, nil);

	#	Should use Styxlisten to multiplex port ?
	listen := load Command "/dis/listen.dis";
	listen->init(nil,
	#	"listen"::"-v"::"-k"::"/usr/sunflower/keyring/default"::
		"listen"::"-v"::"-A"::
		"tcp!*!9999"::"export"::MG_MNTDIR::nil);

	status("Ready to accept connections from remote hosts.");

	return;
}

kbd(kbd, sync : chan of int)
{
#
#	TODO: keyboard events should be forwarded to a Pwm win manager
#		which micro-manages the contents of this window that is
#		in turn managed by, e,g, Inferno's Wm
#
	sync <-= 0;

	for (;;)
	{
		key := <- kbd;

#
#	TODO: must figure out the best way to do the highlighting etc
#		(even in the absence of Pwm).
#	We send empty pointer info; mouse thread likewise empty key info
#
		case key
		{
		PG_LTARROW	=>
			pmsgwin.scrollup(int (real pmsgwin.font.height() * pmsgwin.linespacing));

		PG_RTARROW	=>
			pmsgwin.scrolldn(int (real pmsgwin.font.height() * pmsgwin.linespacing));

		*		=>	kbdbuf := pinputwin.update(key, (0, ZP, 0));
			if (key == '\n')
			{
				spawn enginectlcmd(kbdbuf);
			}
		}
	}

	return;
}

enginectlcmd(cmd: string)
{
	if (sys->fprint(M.localhost.enginectlfd, "%s\n", cmd) < 0)
	{
		error(sys->sprint(
			"Error delivering command to enginectl: %r"));
	}

	return;
}

updatetpgy()
{
	buf := array [Sys->ATOMICIO] of byte;
	
	math := load Math Math->PATH;
	if (math == nil)
	{
		fatal(sys->sprint("Could not load Math module in updatetpgy(): %r"));
	}

	tpgyboxrect	:= get_topologyrect();
	tpgywin		:= M.screen.newwindow(tpgyboxrect, Draw->Refbackup, Draw->White);
	trborder	:= pgui->getrectborder(tpgywin.r);
	M.display.image.poly(trborder, Draw->Enddisc, Draw->Enddisc,
				MG_WINBORDER_PIXELS, M.display.color(MG_DEFAULT_BORDERCOLOR),
				tpgywin.r.min);
	tpgywinbuf	:= M.display.newimage(tpgyboxrect.inset(1), tpgywin.chans, 0,
				Draw->Paleyellow);
	mindim		:= min(tpgywin.r.dx(), tpgywin.r.dy());
	paleyellow	:= M.display.color(Draw->Paleyellow);
	mediumgrey	:= M.display.color(MG_COLOR_MEDIUMGREY);
	darkgrey	:= M.display.color(MG_COLOR_DARKGREY);
	orange		:= M.display.color(MG_COLOR_LIGHTORANGE);

	for(;;) alt
	{
	<-M.updatetopology =>
		#	Read from device (but we write to cached list)
		tmpnodes	:= getdevnodelist();
		tmpnumnodes	:= len tmpnodes;

		tpgywinbuf.draw(tpgywinbuf.r, paleyellow, nil, tpgywinbuf.r.min);
		if (tmpnumnodes == 0)
		{
			tpgywin.draw(tpgywin.r, tpgywinbuf, nil, tpgywin.r.min);

			return;
		}

		boxperside	:= int math->ceil(math->sqrt(real tmpnumnodes));
		boxside		:= (mindim - (MG_TPGYPAD + boxperside*MG_TPGYPAD)) / boxperside;
		nodeboxrect	:= Rect ((0, 0), (boxside, boxside));
		nodebox		:= M.display.newimage(nodeboxrect, tpgywin.chans, 0, Draw->White);
		where 		:= Point(MG_TPGYPAD, MG_TPGYPAD);

		tmp2nodes : list of ref Nodeinfo;
		for (i := 0; i < tmpnumnodes; i++)
		{
			bordercolor	: ref Draw->Image;
			tmpnode		:= hd tmpnodes;
			
			if (tmpnode.active)
			{
				nodebox.draw(nodebox.r, darkgrey, nil, nodebox.r.min);
				bordercolor = darkgrey;
			}
			else
			{
				nodebox.draw(nodebox.r, mediumgrey, nil, nodebox.r.min);
				bordercolor = mediumgrey;
			}
			

			nodemsg := sys->sprint("%d@%d", tmpnode.ID, tmpnode.nodehost.hostid);
			txtpoint := tpgywinbuf.r.min.add(Point(0, nodeboxrect.dy() + 1));
			txtpoint = txtpoint.add(where);

			tpgywinbuf.text(txtpoint, M.display.black, ZP, M.tpgyfont, nodemsg);
			tpgywinbuf.draw(tpgywinbuf.r.addpt(where),
					nodebox, nil, nodeboxrect.min);

			w := tpgywinbuf.r.addpt(where).min;
			a := Rect(w, w.add((boxside, boxside)));
			b := pgui->getrectborder(a);

			if (tmpnode.nodehost.hostid == M.curhost.hostid && tmpnode.iscurnode)
			{
				bordercolor = orange;
				M.setcurnode(tmpnode);
			}

			tpgywinbuf.poly(b, Draw->Endsquare, Draw->Endsquare,
					1, bordercolor, nodeboxrect.min);

			#	Construct the rect of the current node
			tmpnode.tpgyrect.min = tpgywinbuf.r.addpt(where).min;
			tmpnode.tpgyrect.max = tmpnode.tpgyrect.min.add((boxside, boxside));

			where = where.add(Point(MG_TPGYPAD + nodeboxrect.dx(), 0));
			if ((i+1)%boxperside == 0)
			{
				where = Point(MG_TPGYPAD,
					MG_TPGYPAD + (boxside+MG_TPGYPAD)*((i+1)/boxperside));
			}

			tmp2nodes = tmpnode :: tmp2nodes;
			tmpnodes = tl tmpnodes;
		}

		#
		#	M.setcachednodes is careful to retain information that we store in the
		#	list over time, in particular, the Nodeinfo.msgwin, and it will allocate
		#	a new msgwin if a new node is found. M.setcachednodes will update the
		#	curnode with a ref to a Nodeinfo with an alloc'd msgwin
		#
		M.setcachednodes(reorder(tmp2nodes));
		tpgywin.draw(tpgywin.r, tpgywinbuf, nil, tpgywin.r.min);
	}
}

topologydisplay()
{
	spawn updatetpgy();

	for (;;)
	{
		M.updatetopology <-= 0;

		if (sys->sleep(MG_SLOWPROC_SLEEP) < 0)
		{
			error(sys->sprint("sleep failed: %r"));
		}
	}
}

getdevhostlist() : list of ref Host
{
	hosts	: list of ref Host;


	(dirs, n) := timedreaddir(MG_MNTDIR, Readdir->NONE, MG_SMALL_TIMEOUT);
	if (n < 0)
	{
		error(sys->sprint(
			"getdevhostlist: Error reading mountpoint : %r"));
		return nil;
	}

	nhosts := 0;
	for (i := 0; i < n; i++) if ((dirs[i].qid.qtype & Sys->QTDIR) &&
		(dirs[i].name[:min(len dirs[i].name, len "sunflower.")] == "sunflower."))
	{
		(nil, hostname) := str->splitstrr(dirs[i].name, "sunflower.");
		if (hostname == nil)
		{
			continue;
		}

		tmphost := ref Host (nhosts++, hostname, dirs[i].name, MG_MNTDIR+dirs[i].name+"/",
				nil, nil, nil, nil, 0.0, 0, 0.0);

		path := tmphost.mntpt+"enginectl";
		tmphost.enginectlfd = sys->open(path, Sys->OWRITE);
		if (tmphost.enginectlfd == nil)
		{
			error(sys->sprint("Could not open %s: %r", path));
			M.deletehost(tmphost);

			continue;
		}

		hosts = tmphost :: hosts;
	}

	return hosts;
}

getdevnodelist() : list of ref Nodeinfo
{
	buf		:= array [Sys->ATOMICIO] of byte;
	tmpnodes	: list of ref Nodeinfo;


	#	Read host.mntpt/ctl to get number of nodes simulated on each
	for (tmphosts := getdevhostlist(); tmphosts != nil; tmphosts = tl tmphosts)
	{
		curnodeid := (hd tmphosts).getcurnodeid();
		if (curnodeid < 0)
		{
			error(sys->sprint("Could not determine host's current node."));
			M.deletehost(hd tmphosts);
			continue;
		}

		#	For each host, read its dir and parse subdir/ctl
		hostdirpath := (hd tmphosts).mntpt;
		(nodedirs, nnodedirs) := timedreaddir(hostdirpath, Readdir->NONE, MG_SMALL_TIMEOUT);
		if (nnodedirs < 0)
		{
			error(sys->sprint("tpgydisplay: Error reading %s: %r", hostdirpath));
			M.deletehost(hd tmphosts);
			continue;
		}

		#	For all subdirs, read ctl
		n := 0;
		for (i := 0; i < nnodedirs; i++) if (nodedirs[i].qid.qtype & Sys->QTDIR)
		{
			ndirname := nodedirs[i].name;
			(nil, tmpl) := sys->tokenize(ndirname, ".");
			if (len tmpl != 2)
			{
				continue;
			}

			nodeinfo := Nodeinfo.new();
			nodeinfo.ID = int hd tmpl;
			nodeinfo.active = int hd tl tmpl;

			if (!nodeinfo.active && M.onlyactive)
			{
				continue;
			}

			if (nodeinfo.ID == curnodeid)
			{
				nodeinfo.iscurnode = 1;
			}

			nodeinfo.nodehost = hd tmphosts;
			tmpnodes = nodeinfo :: tmpnodes;
		}
	}

	return tmpnodes;
}

nodeinfodisplay()
{
	info	: string;
	n	:= 0;


	buf := array [Sys->ATOMICIO] of byte;
	while (1)
	{
		curhost := M.getcurhost();
		curnode := M.getcurnode();

		if (curhost == nil || curnode == nil)
		{
			if (sys->sleep(MG_SLOWPROC_SLEEP))
			{
				error(sys->sprint("sleep failed: %r"));
			}
			continue;
		}


		fd := curnode.nodectlfd;
		if (fd == nil)
		{
			path := curhost.mntpt + string curnode.ID + "/ctl";
			curnode.nodectlfd = sys->open(path, Sys->ORDWR);
			continue;
		}

		for(; fd != nil ;)
		{
			n = timedread(fd, buf, len buf, MG_SMALL_TIMEOUT);
			if (n <= 0)
				break;
			info = info + string buf[:n];
		}

		if (n < 0)
		{
			error("nodeinfodisplay: Could not read from "+curhost.mntpt+
				sys->sprint("%d", curnode.ID)+"/ctl"+" : "+
				sys->sprint("%r"));

			M.deletehost(curhost);

			continue;
		}

		if (info != nil)
		{
			pnodeinfowin.reset();
			pnodeinfowin.append(info);
		}

		info = nil;
		if (sys->sleep(MG_SLOWPROC_SLEEP) < 0)
		{
			error(sys->sprint("sleep failed: %r"));
		}
	}
}

remotedisplay()
{
	remotehosts : string;


	buf := array [Sys->ATOMICIO] of byte;
	while (1)
	{
		(dirs, n) := timedreaddir(MG_MNTDIR, Readdir->NONE, MG_SMALL_TIMEOUT);
		if (n < 0)
		{
			error(sys->sprint("remotedisplay: Error reading mountpoint : %r"));
			continue;
		}

		for (i := 0; i < n; i++)
		{
			iscur	:= "   ";

			tmphost := devname2host(dirs[i].name);
			if (tmphost == nil)
			{
				continue;
			}

			if (tmphost.hostid == M.curhost.hostid)
			{
				iscur[0] = MG_RTRIANGLE_UNICODE;
			}
			else
			{
				iscur += " ";
			}

			remotehosts = remotehosts + iscur + tmphost.hostname+
					" (Host #"+string tmphost.hostid+")\n";
		}

		prmtwin.reset();
		prmtwin.append(remotehosts);
		remotehosts = nil;

		if (sys->sleep(MG_SLOWPROC_SLEEP) < 0)
		{
			error(sys->sprint("sleep failed: %r"));
		}
	}
}


enginectl(path: string, sync : chan of int)
{
	index 	:= 0;
	data	: array of byte;


	(ok, nil) := sys->stat(path);
	if (ok < 0)
	{
		fatal(sys->sprint("[%s] does not exist.", path));
	}


	if (sys->bind("#s", path, sys->MBEFORE) < 0)
	{
		 fatal(sys->sprint("Bind failed: %r"));
	}

	chanref := sys->file2chan(path, "enginectl");
	if (chanref == nil)
	{
		fatal(sys->sprint("Could not create %s/enginectl: %r\n", path));
	}

	sync <-= 0;

	while(1)
	alt
	{
		(off, nbytes, fid, rc) := <-chanref.read =>
		{
			if (rc == nil) break;
			
			if (index == 0)
			{
				data = array of byte 
					("hostname: "+sysname()+"\n");
			}
			
			if (index < len data)
			{
				end := min(index+nbytes, len data);
				rc <-= (data[index:end], "");
				index = end;
			}
			else
			{
				#	Finished serving contents of data[]
				rc <-= (nil, "");
				index = 0;
			}
		}

		(offset, writedata, fid, wc) := <-chanref.write =>
		{
			if (wc == nil)
			{
				break;
			}

			wc <-= (len writedata, "");
			(ncmds, cmdlist) := sys->tokenize(string writedata, " \t\n");
			if (cmdlist == nil)
			{
				break;
			}



			case (hd cmdlist)
			{
			"onlyactive"	=> M.onlyactive ^= 1;

			"about"		=>
				spawn splash();

			"connect"	=>
				spawn cmd_connect(cmdlist);

			"disconnect"	=>
				spawn cmd_disconnect(cmdlist);

			"sethost"	=>
				if (len cmdlist != 2)
				{
					error("Invalid sethost command");
					break;
				}

				spawn cmd_sethost(hd tl cmdlist);
			
#BUG: the atctl won't quite work since the remove node currently does not cross-mount us
			"splice"	=>
				if ((tl cmdlist != nil) && (hd tl cmdlist)[0] == '@')
				{
					#
					#	Need to spawn atctl as it could potentially try
					#	to write into the same file as we're serving
					#
					spawn atctl("splice", tl cmdlist);
				}
				else
				{
					spawn cmd_splice(cmdlist);
				}
			
			"splicestar"	=>
				if ((tl cmdlist != nil) && (hd tl cmdlist)[0] == '@')
				{
					spawn atctl("splice *", tl cmdlist);
				}
				else
				{
					spawn cmd_splice("splice"::"*"::nil);
				}

			"eqrate"	=>
				if ((tl cmdlist != nil) && (hd tl cmdlist)[0] == '@')
				{
					spawn atctl("eqrate", tl cmdlist);
				}
				else
				{
					spawn eqrate();
				}

			"eqrateproc"	=>
				if ((tl cmdlist != nil) && (hd tl cmdlist)[0] == '@')
				{
					spawn atctl("eqrateproc", tl cmdlist);
				}
				else
				{
					interval := 60;
					if (len cmdlist != 2)
					{
						status("Invalid interval for eqrateproc;");
						status("Using default of 60 secs...");
					}
					else
					{
						interval = int hd tl cmdlist;
						status("Eqrateproc with interval "+string interval+" secs.");
					}

					spawn eqrateproc(interval);
				}
			"eqtime"	=>
				if ((tl cmdlist != nil) && (hd tl cmdlist)[0] == '@')
				{
					spawn atctl("eqtime", tl cmdlist);
				}
				else
				{
					maxskew_ms := 10;

					if (len cmdlist != 2)
					{
						status("Invalid interval/maxskew for eqtime;");
						status("Using default maxskew of 10ms...");
					}
					else
					{
						maxskew_ms = int hd tl cmdlist;
						status(sys->sprint(
							"Eqtime with maxskew=%d ms\n", maxskew_ms));
					}

					spawn eqtime(maxskew_ms);
				}
			"eqtimeproc"	=>
				if ((tl cmdlist != nil) && (hd tl cmdlist)[0] == '@')
				{
					spawn atctl("eqtimeproc", tl cmdlist);
				}
				else
				{
					maxskew_ms := 10;
					interval := 30;

					if (len cmdlist != 3)
					{
						status("Invalid interval/maxskew for eqtime;");
						status("Using default interval of 30 secs, maxskew of 10ms...");
					}
					else
					{
						interval = int hd tl cmdlist;
						maxskew_ms = int hd tl tl cmdlist;
						status(sys->sprint(
							"Eqtime with interval=%d s, maxskew=%d ms\n",
								interval, maxskew_ms));
					}

					spawn eqtimeproc(interval, maxskew_ms);
				}

			"restart"	=>
					spawn cmd_restart(M.savedargs);


			"pload"	=>
				#	Takes a standard sunflower config file, and 
				#	sends chunks of it to different all remote hosts
				#	(currently, using heuristics + round-robin)
				#	if theres a single host, behavior is identical
				#	to normal sunflower load command. Future params
				#	might be scheduling algorithms/policies, using
				#	the yet-to-be-implemented /dev/perf
				spawn pload(tl cmdlist);


			"quit" or "q" =>
				spawn devsunflowercmd(M.localhost, "quit");
				cleanexit();

			"help" or "man" =>
				devsunflowercmd(M.localhost, string writedata);

				if ((len cmdlist) == 1)
				{
					echo(MG_HELP);
				}

			"echo"	=>
				echo(string writedata[min(5, len writedata):]);
			
			#"save"	=>
			#	fname := selectfile->filename(M.ctxt, M.display.image, "", nil, ".");
			#
			#"connectf" =>
			#	fname := selectfile->filename(M.ctxt, M.display.image,
			#			"", "*.mgh"::nil, ".");
			#	if (fname != nil)
			#	{
			#		spawn connectf(fname);
			#	}

			*	=>
				if ((hd cmdlist)[0] == '!')
				{
					spawn runcmd((hd cmdlist)[1:]:: tl cmdlist);
				}
				else if ((hd cmdlist)[0] == '@')
				{
					spawn atctl(nil, cmdlist);
				}
				else
				{
					spawn devsunflowercmd(M.getcurhost(), string writedata);
				}
			}
		}
	}

	return;
}

atctl(cmd: string, arglist: list of string)
{
	(nil, hostname) := str->splitstrr(hd arglist, "@");
	if (hostname == nil)
	{
		hostname = "0";
	}

	host := name2host(hostname);
	if (host == nil)
	{
		host = M.localhost;
	}

	sys->fprint(host.enginectlfd, "%s\n", list2str(cmd::(tl arglist)));
}

list2str(l: list of string): string
{
	s: string;

	tmp := l;
	while (tmp != nil)
	{
		#	Can have nil strings in the list. Don't add them.
		w := hd tmp;
		if (w != nil)
		{
			s += w + " ";
		}

		tmp = tl tmp;
	}

	#	Elide trailing white space
	s = s[:len s - 1];

	return s;
}

cmd_splice(cmdlist : list of string)
{
	if (len cmdlist == 2 && hd tl cmdlist == "*")
	{
		hosts := M.getcachedhosts();
		for (tmp1 := hosts; tmp1 != nil; tmp1 = tl tmp1)
		{
			for (tmp2 := hosts; tmp2 != nil; tmp2 = tl tmp2)
			{
				if ((hd tmp1).hostid != (hd tmp2).hostid)
				{
					spawn splice(
					string (hd tmp1).hostid ::
					string (hd tmp2).hostid :: nil);
				}
			}
		}
	}
	else
	{
		spawn splice(tl cmdlist);
	}
}

cmd_sethost(hostname: string)
{
	if ((tmp := name2host(hostname)) != nil)
	{
		M.setcurhost(tmp);
	}
	else
	{
		error("No such host as "+hostname+".");
	}
}

cmd_connect(cmdlist : list of string)
{
	#	connect remote_host [certificate] [alg]
	if (len cmdlist < 2 || len cmdlist > 4)
	{
		error("Badly formed \"connect\" command");
		return;
	}
			
	if (attachremote(tl cmdlist, "") < 0)
	{
		return;
	}
}

cmd_disconnect(cmdlist: list of string)
{
	cmdlist = tl cmdlist;
	while (cmdlist != nil)
	{
		host := name2host(hd cmdlist);
		if (host == nil)
		{
			error(sys->sprint("Cannot delete host %s: no such host", hd cmdlist));
			cmdlist = tl cmdlist;

			continue;
		}

		M.deletehost(host);
		cmdlist = tl cmdlist;
	}
}

cmd_restart(savedargs : list of string)
{
	sys->pctl(Sys->NEWPGRP, nil);
	runcmd("kill"::"-g"::string M.pgrp::nil);
	spawn runcmd(savedargs);

	return;
}

splice(args : list of string)
{
	bytesread, n	: int = 0;
	buf		:= array [Sys->ATOMICIO] of byte;
	dsthosts	: list of ref Host;


	if (args == nil)
	{
		error("Invalid source hostname supplied to splice.");
		return;
	}

	srchost := name2host(hd args);
	if (srchost == nil)
	{
		error("Invalid source hostname supplied to splice.");
		return;
	}

	srchost.netoutfd = sys->open(srchost.mntpt+"netout", sys->OREAD);
	if (srchost.netoutfd == nil)
	{
		error("Could not open source node's netout.");
		return;
	}

	args = tl args;

	while (args != nil)
	{
		host := name2host(hd args);
		if (host == nil)
		{
			error("Splice with invalid destination.");
			return;
		}

		if (host.hostid == srchost.hostid)
		{
			error("Splice with same src/dst not permitted.");
			return;
		}

		host.netinfd = sys->open(host.mntpt+"netin", sys->OWRITE);
		if (host.netinfd == nil)
		{
			error(sys->sprint("Could not open %s: %r.",
				host.mntpt+"netin"));
		}

		dsthosts = host :: dsthosts;

		args = tl args;
	}
	if (dsthosts == nil)
	{
		error("No valid destination hostname(s) supplied to splice");
		return;
	}

	tmpdsts := dsthosts;
	while (tmpdsts != nil)
	{
		sys->fprint(M.stderr, "Splice setup from [%s] to [%s]\n",
			srchost.hostname, (hd tmpdsts).hostname);
		tmpdsts = tl tmpdsts;
	}

	#	We simply stream from netin to netout. All
	#	other details are taken care of by respective
	#	devsunflowers. We can't use sys->stream though.
	for (;;)
	{
		n = timedread(srchost.netoutfd, buf, len buf, MG_SMALL_TIMEOUT);
		if (n < 0)
		{
			error("Could not read from "+srchost.mntpt+"netout"+" : "+
				sys->sprint("%r"));
			error("Cancelling splice");

			return;
		}

		if (n == 0)
		{
			continue;
		}

		#	Unused. Future: update a progress bar, bytes shuttled per sec
		#bytesread += n;

		for (tmpdst := dsthosts;
				(tmpdst != nil) && (n > 0);
				tmpdst = tl tmpdst)
		{
#			#	First, check to see if we can decode (i.e., is a valid buf)	
#			tmpdecode := netoutdecode(buf[:n]);
#			if (tmpdecode == nil)
#			{
#				error(sys->sprint("Could not decode netout from [%s]",
#					srchost.hostname));
#				error("Cancelling splice");
#
#				return;
#			}
#
#			if (tmpdecode.from_remote)
#			{
#				#
#				#	Should never happen since remote_enquue() in simulator
#				#	core does not put the incoming remote from in netsegcircbuf
#				#
#				error(sys->sprint("Frames with from_remote flag set on netout"));
#				continue;
#			}

			if (sys->write((hd tmpdst).netinfd, buf, n) < 0)
			{
				error(sys->sprint("Could not write to %s's netin : %r",
					(hd tmpdst).hostname));
				error("Cancelling splice");
				M.deletehost(hd tmpdst);

				return;
			}
sys->fprint(M.stderr, "[%s] (splice)-> [%s]\n", srchost.hostname, (hd tmpdst).hostname);
		}
	}
}

netoutdecode(buf : array of byte) : ref Segbuf
{	
	i, off : int = 0;


	segbuf := ref Segbuf (0.0, array [Sys->ATOMICIO] of byte, 0, 0, 0, 0, 0, 0, 0, 0);
	segbuf.timestamp = real string buf[off+len "Timestamp: ":];
	off += len "Timestamp: X.XXXXXXE-XX\n";

	#	Skip "Data: "
	off += len "Data: ";

	for (i = 0;
		(off < len segbuf.data) && (off < len buf) && (int buf[off] != '.');
		i++)
	{
		(val, nil) := str->toint(string buf[off:], 16);
		segbuf.data[i] = byte val;
		off += len "XX ";

		#	Newlines
		if (!((i+1) % 24))
		{
			off++;
		}
	}
	segbuf.payloadlen = i;
	off += len ".\n";

	if (off + len "Bits left: 0x" >= len buf) return nil;
	(segbuf.bits_left, nil) = str->toint(string buf[off + len "Bits left: 0x":], 16);
	off += len "Bits left: 0xXXXXXXXX\n";

	if (off + len "Src node: 0x" >= len buf) return nil;
	(segbuf.src_nodeid, nil) = str->toint(string buf[off + len "Src node: 0x":], 16);
	off += len "Src node: 0xXXXXXXXX\n";

	if (off + len "Dst node: 0x" >= len buf) return nil;
	(segbuf.dst_nodeid, nil) = str->toint(string buf[off + len "Dst node: 0x":], 16);
	off += len "Dst node: 0xXXXXXXXX\n";

	if (off + len "Bcast flag: 0x" >= len buf) return nil;
	(segbuf.bcast, nil) = str->toint(string buf[off + len "Bcast flag: 0x":], 16);
	off += len "Bcast flag: 0xXXXXXXXX\n";

	if (off + len "Src ifc: 0x" >= len buf) return nil;
	(segbuf.src_ifc, nil) = str->toint(string buf[off + len "Src ifc: 0x":], 16);
	off += len "Src ifc: 0xXXXXXXXX\n";

	if (off + len "Parent netseg ID: 0x" >= len buf) return nil;
	(segbuf.parent_netsegid, nil) = str->toint(string buf[off + len "Parent netseg ID: 0x":], 16);
	off += len "Parent netseg ID: 0xXXXXXXXX\n";

	if (off + len "from_remote flag: 0x" >= len buf) return nil;
	(segbuf.from_remote, nil) = str->toint(string buf[off + len "from_remote flag: 0x":], 16);
	off += len "from_remote flag: 0xXXXXXXXX\n";

	return segbuf;
}

dumpsegbuf(segbuf : ref Segbuf)
{
	if (segbuf == nil)
	{
		sys->fprint(M.stderr, "Invalid Segbuf passed into dumpsegbuf\n");
		return;
	}

	sys->fprint(M.stderr, "\n\n");
	sys->fprint(M.stderr, "Timestamp: %E\n", segbuf.timestamp);
	sys->fprint(M.stderr, "Data: ");
	
	for (i := 0; i < segbuf.payloadlen; i++)
	{
		sys->fprint(M.stderr, "%02X ", int segbuf.data[i]);

		#	Newlines
		if (!((i+1) % 24))
		{
			sys->fprint(M.stderr, "\n");
		}
	}
	sys->fprint(M.stderr, ".\n");

	sys->fprint(M.stderr, "Bits left: 0x%08X\n", segbuf.bits_left);
	sys->fprint(M.stderr, "Src node: 0x%08X\n", segbuf.src_nodeid);
	sys->fprint(M.stderr, "Dst node: 0x%08X\n", segbuf.dst_nodeid);
	sys->fprint(M.stderr, "Bcast flag: 0x%08X\n", segbuf.bcast);
	sys->fprint(M.stderr, "Src ifc: 0x%08X\n", segbuf.src_ifc);

	return;
}

pload(args : list of string)
{
	#	This is a heuristic which works only because of the way
	#	we have been writing the config files. As yet undecided
	#	whether to introduce new syntax for saying what should
	#	be replicated across engines (e.g. "global{...}") and
	#	what should be per-node (e.g., "per-node{...}"). Break this
	#	function out into a separate module ?
	nil = args;
}


devsunflowercmd(host: ref Host, cmd: string)
{
#sys->print("curdevname = %s\ncurmntpt = %s, cmd = [%s]\n", M.curhost.devname, M.curhost.mntpt, cmd);

	curnodeid := host.getcurnodeid();
	if (curnodeid < 0)
	{
		error("Could not determine host's current node.");
		M.deletehost(host);

		return;
	}

	ctlpath := host.mntpt+string curnodeid+"/ctl";

	fd := timedopen(ctlpath, sys->OWRITE, MG_SMALL_TIMEOUT);
	if (fd == nil)
	{
		error(sys->sprint("Could not open %s: %r", ctlpath));
		M.deletehost(host);

		return;
	}

	cmdarray := array of byte cmd;
	if (timedwrite(fd, cmdarray, len cmdarray, MG_SMALL_TIMEOUT) < 0)
	{
		error(sys->sprint("Could not write to %s: %r", ctlpath));
		M.deletehost(host);

		return;
	}

	if (M.gui)
	{
		refreshoutput();
	}

	return;
}

fastrefreshproc()
{
	while (1)
	{
		if (M.refresh)
		{
			refreshoutput();
			if (sys->sleep(MG_FASTPROC_SLEEP) < 0)
			{
				error(sys->sprint("sleep failed: %r"));
			}
		}
		else if (sys->sleep(MG_SLOWPROC_SLEEP) < 0)
		{
			error(sys->sprint("sleep failed: %r"));
		}
	}
}

stdioproc()
{
	if (sys->bind("#|", "/chan", Sys->MBEFORE) < 0)
	{
		error(sys->sprint("Could not bind pipe device: %r"));
		return;
	}

	stdin_pipe := array [2] of ref Sys->FD;
	stdout_pipe := array [2] of ref Sys->FD;
	stderr_pipe := array [2] of ref Sys->FD;

	a := sys->pipe(stdin_pipe);
	b := sys->pipe(stdout_pipe);
	c := sys->pipe(stderr_pipe);

	if (a < 0 || b < 0 || c < 0)
	{
		error(sys->sprint("Could not create pipe. Last error was: %r"));
		return;
	}

	a = sys->dup(stdin_pipe[0].fd, 0);
	b = sys->dup(stdout_pipe[0].fd, 1);
	c = sys->dup(stderr_pipe[0].fd, 2);

	if (a < 0 || b < 0 || c < 0)
	{
		error(sys->sprint("Could not dup descriptors. Last error was: %r"));
		return;
	}

#	spawn inpipe_proc(stdin_pipe);
	spawn outpipe_proc(stdout_pipe, MG_STDOUTMARKER);
	spawn outpipe_proc(stderr_pipe, MG_STDERRMARKER);

	return;
}

outpipe_proc(pipe: array of ref Sys->FD, outputname: string)
{
	e := "echo "+outputname;
	buf := array [Sys->ATOMICIO + len e] of byte;
	buf [0:] = array of byte e;

	while (1)
	{
		#	This read blocks until data is available:
		n := sys->read(pipe[1], buf[len e:], Sys->ATOMICIO);
		if (n < 0)
		{
			error(sys->sprint("Outpipe: read of pipe failed: %r\n"));
			return;
		}

		#	This write should not block indefinitely:
		if (timedwrite(M.localhost.enginectlfd, buf, n+len e, MG_SMALL_TIMEOUT) < 0)
		{
			error(sys->sprint("Outpipe: write to enginectl failed: %r\n"));
			return;
		}
	}
}

echo(s: string)
{
	if (pmsgwin != nil)
	{
		pmsgwin.append(s);
	}
	else
	{
		sys->print("%s", s);
	}

	return;
}

eqtimeproc(maxinterval, maxskew_ms: int)
{
	interval := 10;

	#	For intervals larger than 10ms, we gradually build up
	#	to them.  Don't generalize to a 'step', since intervals
	#	smaller than 10ms will lead to too much probing and slow
	#	down simulation engines.
	while (1)
	{
		eqtime(maxskew_ms);
		if (sys->sleep(interval*1000) < 0)
		{
			error(sys->sprint("sleep failed: %r"));
		}

		if (interval < maxinterval)
		{
			interval += 10;
		}
	}
}

eqtime(maxskew_ms: int)
{
	buf		:= array [Sys->ATOMICIO] of byte;
	hosts		:= M.getcachedhosts();
	min_Tcpu	:= Math->Infinity;


#BUG!: should read this off the Devsunflower

	global_cycletime := 1.0/4E6;


	#	Find min Tcpu:
	for (tmp := hosts; tmp != nil; tmp = tl tmp)
	{
		host		:= hd tmp;
		Tcpu_sum	:= 0.0;
		nTcpu_sum	:= 0.0;
		rate_sum	:= 0.0;
		nrate_sum	:= 0.0;
		actual_rate	:= 0.0;


		#
		#	The Tcpu across nodes shouldn't vary by more
		#	than a simulated machine clock cycletime.
		#
		for (nodelist := host.getparsednodes();
			nodelist != nil; nodelist = tl nodelist)
		{
			node := hd nodelist;
			if (node.Tcpu > 0.0)
			{
				Tcpu_sum += node.Tcpu;
				nTcpu_sum++;
			}

			if (node.tripsimrate > 0)
			{
				actual_rate = 1.0 /
					(1.0/(real node.tripsimrate) -
					((real node.throttle) * 1E-9));

				if (actual_rate > 0.0)
				{
					rate_sum += actual_rate;
					nrate_sum++;
				}
			}
		}

		if (nrate_sum == 0.0)
		{
			continue;
		}

		actual_rate = rate_sum / nrate_sum;
		sys->print("Host [%s], avgrate = [%E]\n", host.hostname, actual_rate);
		host.cachedsimrate = actual_rate;

		if (Tcpu_sum == 0.0)
		{
			continue;
		}

		Tcpu := Tcpu_sum / nTcpu_sum;
		sys->print("Host [%s], avg. Tcpu = [%E]\n", host.hostname, Tcpu);
		host.cachedTcpu = Tcpu;
		if (min_Tcpu > Tcpu)
		{
			min_Tcpu = Tcpu;
		}
	}

	if (min_Tcpu == Math->Infinity)
	{
		status("Could not find any running nodes.");
		return;
	}

	sys->print("Min Tcpu is %E\n", min_Tcpu);

	#
	#	If skew is > maxskew, based on simulation rate, calculate
	#	a duration of Real Time for which to pause simulation
	#
	for (tmp = hosts; tmp != nil; tmp = tl tmp)
	{
		host	:= hd tmp;
		skew	:= host.cachedTcpu - min_Tcpu;

		sys->print("Host [%s]: skew = %fms.\n",
			host.hostname, skew*1000.0);

		if ((skew*1000.0 < real maxskew_ms) || (host.cachedsimrate == 0.0))
		{
			continue;
		}

#BUG: global_cycletime should eventually be read from Devsunflower
		pause := skew / (host.cachedsimrate * global_cycletime);
		sys->print("Host [%s]: pause = %bdns.\n",
			host.hostname, big (pause*1E9));

		ctlpath := host.mntpt+"ctl";
		ctlfd := sys->open(ctlpath, Sys->OWRITE);
		if (ctlfd == nil)
		{
			error(sys->sprint("Could not open %s: %r", ctlpath));

			continue;
		}

		cmd := array of byte sys->sprint("nanopause %bd", big (pause*1E9));
		if (sys->write(ctlfd, cmd, len cmd) < 0)
		{
			error(sys->sprint("Could not write %s to %s: %r",
				string cmd, ctlpath));

			continue;
		}
	}
	sys->print("\n\n");

	return;
}

eqrateproc(interval: int)
{
	while (1)
	{
		eqrate();
		if (sys->sleep(interval*1000) < 0)
		{
			error(sys->sprint("sleep failed: %r"));
		}
	}
}

eqrate()
{
	buf		:= array [Sys->ATOMICIO] of byte;
	hosts		:= M.getcachedhosts();
	min_rate	:= Math->Infinity;


	#	Find min rate:
	for (tmp := hosts; tmp != nil; tmp = tl tmp)
	{
		host		:= hd tmp;
		rate_sum	:= 0.0;
		nrate_sum	:= 0.0;
		actual_rate	:= 0.0;

		for (nodelist := host.getparsednodes();
			nodelist != nil; nodelist = tl nodelist)
		{
			node := hd nodelist;

			if (node.tripsimrate == 0)
			{
				continue;
			}

			actual_rate = 1.0 /
				(1.0/(real node.tripsimrate) -
				((real node.throttle) * 1E-9));


			if (actual_rate > 0.0)
			{
				rate_sum += actual_rate;
				nrate_sum++;
			}

			#	Only really needed once, identical over all nodes
			host.cachedthrottle = node.throttle;
		}

		if (nrate_sum == 0.0)
		{
			continue;
		}

		actual_rate = rate_sum / nrate_sum;
		sys->print("Host [%s], avgrate = [%E]\n", host.hostname, actual_rate);
		host.cachedsimrate = actual_rate;

		if (min_rate > actual_rate)
		{
			min_rate = actual_rate;
		}
	}

	sys->print("Min rate is %E\n", min_rate);

	if (min_rate == Math->Infinity)
	{
		status("Could not find any running nodes");
		return;
	}

	#	Equalize:
	for (tmp = hosts; tmp != nil; tmp = tl tmp)
	{
		host	:= hd tmp;

		if (host.cachedsimrate == 0.0)
		{
			continue;
		}

		new_throttle_nsecs := int ((1.0/min_rate - 1.0/host.cachedsimrate)*1E9);
		new_throttle_nsecs = max(new_throttle_nsecs, 0);

		sys->print("Host [%s]: throttle factor = %f, throttle nanosecs = %d\n",
			host.hostname, host.cachedsimrate/min_rate, new_throttle_nsecs);

		ctlpath := host.mntpt+"ctl";
		ctlfd := sys->open(ctlpath, Sys->OWRITE);
		if (ctlfd == nil)
		{
			error(sys->sprint("Could not open %s: %r", ctlpath));

			continue;
		}

		cmd := array of byte ("throttle "+string new_throttle_nsecs);
		if (sys->write(ctlfd, cmd, len cmd) < 0)
		{
			error(sys->sprint("Could not write %s to %s: %r",
				string cmd, ctlpath));

			continue;
		}

		cmd = array of byte "resetallctrs";
		if (sys->write(ctlfd, cmd, len cmd) < 0)
		{
			error(sys->sprint("Could not write %s to %s: %r",
				string cmd, ctlpath));

			continue;
		}
	}
	sys->print("\n\n");

	return;
}

refreshoutput()
{
	result	: string;
	n	:= -1;
	buf	:= array[Sys->ATOMICIO] of byte;


	curhost := M.getcurhost();
	curnodeid := curhost.getcurnodeid();

	#	First read out node-specific info
	basepath	:= curhost.mntpt+string curnodeid+"/";
	ctlpath		:= basepath+"info";

	fd := timedopen(ctlpath, sys->OREAD, MG_SMALL_TIMEOUT);
	for(;fd  != nil;)
	{
		n = timedread(fd, buf, len buf, MG_SMALL_TIMEOUT);
		if(n <= 0)
			break;
		result = result + string buf[:n];
	}
	if (fd == nil || n < 0)
	{
		error(sys->sprint("Could not read from %s: %r", ctlpath));
		M.deletehost(curhost);

		return;
	}

	#	Next, read out node stdout
	stdoutpath	:= basepath+"stdout";
	fd = timedopen(stdoutpath, sys->OREAD, MG_SMALL_TIMEOUT);
	for(;fd  != nil;)
	{
		n = timedread(fd, buf, len buf, MG_SMALL_TIMEOUT);
		if(n <= 0)
			break;
		result = result + string buf[:n];
	}
	if (fd == nil || n < 0)
	{
		error(sys->sprint("Could not read from %s: %r", stdoutpath));
		M.deletehost(curhost);

		return;
	}

	#	Next, read out node stderr
	stderrpath	:= basepath+"stdout";
	fd = timedopen(stdoutpath, sys->OREAD, MG_SMALL_TIMEOUT);
	for(;fd  != nil;)
	{
		n = timedread(fd, buf, len buf, MG_SMALL_TIMEOUT);
		if(n <= 0)
			break;
		result = result + string buf[:n];
	}
	if (fd == nil || n < 0)
	{
		error(sys->sprint("Could not read from %s: %r", stderrpath));
		M.deletehost(curhost);

		return;
	}


	#	Next, read out system-wide output
	infopath	:= curhost.mntpt+"info";
	fd = timedopen(infopath, sys->OREAD, MG_SMALL_TIMEOUT);
	for(;fd != nil;)
	{
		n = timedread(fd, buf, len buf, MG_SMALL_TIMEOUT);
		if(n <= 0)
			break;
		result = result + string buf[:n];
	}
	if (fd == nil || n < 0)
	{
		error(sys->sprint("Could not read from %s: %r", infopath));
		M.deletehost(curhost);

		return;
	}
	
	if (len result > 0)
	{
		pmsgwin.append(result);
	}
	
	return;
}

#	From /appl/wm/wm.b
r2s(r: Rect): string
{
	return string r.min.x + " " + string r.min.y + " " +
			string r.max.x + " " + string r.max.y;
}


#	From /appl/wm/wm.b
reshaped(win: ref Wmclient->Window)
{
	Fix: con 1000;

	oldr := M.screen.image.r;
	newr := win.image.r;
	mx := Fix;
	if(oldr.dx() > 0)
		mx = newr.dx() * Fix / oldr.dx();
	my := Fix;
	if(oldr.dy() > 0)
		my = newr.dy() * Fix / oldr.dy();
	M.screen = makescreen(win.image);
	for(z := wmsrv->top(); z != nil; z = z.znext){
		for(wl := z.wins; wl != nil; wl = tl wl){
			w := hd wl;
			w.img = nil;
			nr := w.r.subpt(oldr.min);
			nr.min.x = nr.min.x * mx / Fix;
			nr.min.y = nr.min.y * my / Fix;
			nr.max.x = nr.max.x * mx / Fix;
			nr.max.y = nr.max.y * my / Fix;
			nr = nr.addpt(newr.min);
			w.img = M.screen.newwindow(nr, Draw->Refbackup, Draw->Nofill);
			# XXX check for creation failure
			w.r = nr;
			z.ctl <-= sys->sprint("!reshape %q -1 %s", w.tag, r2s(nr));
			z.ctl <-= "rect " + r2s(newr);
		}
	}
}

makescreen(img: ref Image): ref Screen
{
	return nil;
}

plainscreen(img: ref Image) : ref Screen
{
	splash := img.display.color(MG_DEFAULT_BGCOLOR);
	screen := Screen.allocate(img, splash, 0);
	img.draw(img.r, screen.fill, nil, screen.fill.r.min);
		
	return screen;
}

connectf(hostsfile : string)
{
	iobuf := bufio->open(hostsfile, Bufio->OREAD);
	if (iobuf == nil)
	{
		error(sys->sprint("Could not open %s: %r", hostsfile));
		return;
	}

	while ((line := iobuf.gets('\n')) != nil)
	{
		(nil, hostargs) := sys->tokenize(line, " \t\n");
		if ((hd hostargs)[0] != '#')
		{
			if (attachremote(hostargs, "") < 0)
			{
				continue;
			}
		}
	}

	return;
}

dialler(dialc: chan of chan of ref Sys->FD, dest: string)
{
	while((reply := <-dialc) != nil)
	{
		(ok, c) := sys->dial(dest, nil);
		if(ok == -1)
		{
			reply <-= nil;
			continue;
		}
		reply <-= c.dfd;
	}
}

attachremote(args: list of string, path: string) : int
{
	status("Connecting...");

	styxpersist := load Styxpersist Styxpersist->PATH;
	if(styxpersist == nil)
	{
		error(sys->sprint("Could not load %s: %r", Styxpersist->PATH));
		return -1;
	}
	sys->pipe(p := array[2] of ref Sys->FD);
	(c, err) := styxpersist->init(p[0], 0, nil);
	if(c == nil)
	{
		error("Styxpersist: "+err);
		return -1;
	}


	addr := hd args;
	spawn dialler(c, netmkaddr(addr, "tcp", "9999"));


	#status("Mount...");
	n := timedmount(p[1], nil, MG_CONNDIR, sys->MREPL, "", MG_MEDIUM_TIMEOUT);
	if (n < 0)
	{
		error("Mount failed: "+sys->sprint("%r"));
		return -1;
	}

#BUG/TODO: needs cleanup:	
	#	Avoid duplicates. The random ID in the engine name helps guard against
	#	possibility of multiple hosts with same local hostname, connection to
	#	localhost, etc.

	(dir, ndev) := timedreaddir(MG_CONNDIR, Readdir->NONE, MG_SMALL_TIMEOUT);
	if (ndev < 0)
	{
		error(sys->sprint("dirread failed: %r"));

		status("Unmounting...");
		if (sys->unmount(MG_CONNDIR, MG_MNTDIR) < 0)
		{
			error(sys->sprint("Could not unmount host: %r"));
		}

		return -1;
	}

	#	Search for an engine filesystem
	remotedevname := "";
	for (i := 0; i < ndev; i++)
	{
		#	Should be more thorough: opendir, look for enginectl
		(nil, remotedevname) = str->splitstrr(dir[i].name, "sunflower.");
		if (remotedevname != nil)
		{
			break;
		}
		status(
			sys->sprint("Skipping directory \"%s\", dtype = [%c]",
			dir[i].name, dir[i].dtype));
	}

	#	Note that the "remotedevname" here is not the full devname, so search for it
	#	in name2host.  BUG/TODO: there is some overlap in our current use of devnames
	#	versus names, and it should be cleaned up
	if (name2host(remotedevname) != nil)
	{
		status("Host with unique engine ID "+remotedevname+" already attached!");
sys->print("extant host matching [%s] is [%s]\n", remotedevname, name2host(remotedevname).hostname);

		status("Unmounting...");
		if (sys->unmount(nil, MG_CONNDIR) < 0)
		{
			error(sys->sprint("Could not unmount host: %r"));
		}

		return -1;
	}

	#status("Bind...");
	n = sys->bind(MG_CONNDIR+path, MG_MNTDIR, sys->MAFTER);
	if (n < 0)
	{
		error("Bind failed: "+sys->sprint("%r"));
		return -1;
	}
	status("Host "+addr+" attached.");

	(dir, ndev) = timedreaddir(MG_CONNDIR, Readdir->NONE, MG_SMALL_TIMEOUT);
	if (ndev < 0)
	{
		error(sys->sprint("dirread failed: %r"));

		status("Unmounting...");
		if (sys->unmount(MG_CONNDIR, MG_MNTDIR) < 0)
		{
			error(sys->sprint("Could not unmount host: %r"));
		}

		return -1;
	}

	#	Search for an engine filesystem
	remotedevname = "";
	for (i = 0; i < ndev; i++)
	{
		#	Should be more thorough: opendir, look for enginectl
		(nil, remotedevname) = str->splitstrr(dir[i].name, "sunflower.");
		if (remotedevname != nil)
		{
			break;
		}
		status(
			sys->sprint("Skipping directory \"%s\", dtype = [%c]",
			dir[i].name, dir[i].dtype));
	}
	if (remotedevname == "")
	{
		error("Remote host has no engine filesystem");
		
		status("Unmounting...");
		if (sys->unmount(MG_CONNDIR, MG_MNTDIR) < 0)
		{
			error(sys->sprint("Could not unmount host: %r"));
		}

		return -1;
	}

	#	TODO/BUG another example of why we should use the whole devname including "sunflower." as remotedevname
	M.mntcache.insert(remotedevname, MG_CONNDIR+"sunflower."+remotedevname);
	M.setcachedhosts(getdevhostlist());

	return 0;
}

sysname(): string
{
	fd := timedopen("/dev/sysname", sys->OREAD, MG_SMALL_TIMEOUT);
	if (fd == nil)
	{
		error(sys->sprint("Could not open /dev/sysname: %r"));
		return "localhost";
	}

	buf := array[Sys->ATOMICIO] of byte;
	n := timedread(fd, buf, len buf, MG_SMALL_TIMEOUT);
	if (n < 0)
	{
		error(sys->sprint("Could not read /dev/sysname: %r"));
		return "localhost";
	}

	return string buf[:n];	
}

netmkaddr(addr, net, svc: string): string
{
	if (net == nil)
	{
		net = "net";
	}

	(n, l) := sys->tokenize(addr, "!");
	if (n <= 1)
	{
		if(svc== nil)
		{
			return sys->sprint("%s!%s", net, addr);
		}
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}

	if(svc == nil || n > 2)
	{
		return addr;
	}

	return sys->sprint("%s!%s", addr, svc);
}

status(msg : string)
{
	if (M.gui && M.display != nil)
	{
		sanitybox(msg, M.alertfont,
			Draw->Black, Draw->White);
	}
	else
		sys->fprint(M.stderr, "Mgui: %s\n", msg);
}

error(e: string)
{
sys->print("%s\n", e);

	#	Should be written to a log file, MNTDIR/log
	if (M.gui && M.display != nil)
	{
		errorbox("error: "+e, M.alertfont,
			Draw->Yellow, Draw->Black);
	}
	else
		sys->fprint(M.stderr, "Mgui Error: %s\n", e);

	return;
}

fatal(s: string)
{
	#	Silently return if there is no error
	if (s == nil)
	{
		return;
	}

	#	Should be written to a log file, MNTDIR/log
	if (M.gui && draw != nil)
	{
		errorbox("fatal: "+s+"   Exiting...", M.alertfont,
			Draw->Red, Draw->White);
	}
	
	sys->fprint(M.stderr,
			"Mgui Fatal: %s\nExiting...\n", s);

	cleanexit();
	while (1) ;
}

errorbox(msg : string, font : ref Font, bgcolor, txtcolor: int)
{
	perrwin.append(msg+"\n");
	return;
}

sanitybox(msg : string, font : ref Font, bgcolor, txtcolor: int)
{
	psanitywin.append(msg+"\n");
	return;
}

reorder [T] (orig : list of T) : list of T
{
	rev : list of T;

	while (orig != nil)
	{
		rev = (hd orig) :: rev;
		orig = tl orig;
	}

	return rev;
}

hostid2host(id : int) : ref Host
{
	tmp := M.getcachedhosts();
	while (len tmp >= 1)
	{
		if ((hd tmp).hostid == id)
		{
			return hd tmp;
		}

		tmp = tl tmp;
	}

	return nil;
}

name2host(name : string) : ref Host
{
	if (name == nil)
	{
		return nil;
	}

	tmp := M.getcachedhosts();
	while (tmp != nil)
	{
		if ((hd tmp).hostname == name)
		{
			return hd tmp;
		}

		tmp = tl tmp;
	}

	#	Not a number, so don't try hostid2host
	if (name[0] > '9')
	{
		return nil;
	}

	return hostid2host(int name);
}


devname2host(devname : string) : ref Host
{
	tmp := M.getcachedhosts();
	while (tmp != nil)
	{
		if ((hd tmp).devname == devname)
		{
			return hd tmp;
		}

		tmp = tl tmp;
	}

	return nil;
}

MguiState.deletehost(host: ref Host)
{
	if (host.hostid == M.localhost.hostid)
	{
		error(sys->sprint(
			"You're not allowed to delete localhost (ID %d). Sorry!",
			host.hostid));

		return;
	}

	status(sys->sprint("Disconnecting host \"%s\"...", host.hostname));

	mntlist := M.mntcache.delete(host.hostname);
	while (mntlist != nil)
	{
		mntpath := hd mntlist;
sys->print("mntpath = [%s]\n", mntpath);
		#	Remove from union in MG_MNTDIR
		if (timedunmount(mntpath, MG_MNTDIR, MG_SMALL_TIMEOUT) < 0)
		{
			error(sys->sprint("Could not remove from host from union: %r"));

			return;
		}

		#	Actually terminate the Styx session
		if (timedunmount(mntpath, MG_CONNDIR, MG_SMALL_TIMEOUT) < 0)
		{
			error(sys->sprint("Could not unmount host: %r"));

			return;
		}

		mntlist = tl mntlist;
	}

	M.setcachedhosts(getdevhostlist());
	if (M.getcurhost().hostid == host.hostid)
	{
		M.setcurhost(M.localhost);
	}
}

MguiState.getcachedhosts() : list of ref Host
{
	M.sem_cachedhosts.obtain();
	hosts := M.cachedhosts;
	M.sem_cachedhosts.release();

	return hosts;
}

MguiState.setcachedhosts(hostlist : list of ref Host)
{
	M.sem_cachedhosts.obtain();
	M.cachedhosts = hostlist;
	M.sem_cachedhosts.release();
}

MguiState.getcachednodes() : list of ref Nodeinfo
{
	M.sem_cachednodes.obtain();
	x := M.cachednodes;
	M.sem_cachednodes.release();

	return x;
}

inl(node: ref Nodeinfo, nodelist: list of ref Nodeinfo) : ref Nodeinfo
{
	#	We check both host and ctlfd for a match. We really only
	#	need to check the ctlfd (host would not be enough though)
	tmp := nodelist;
	while (tmp != nil)
	{
		n := hd tmp;

		if (n.nodehost.hostname == node.nodehost.hostname && n.ID == node.ID)
		{
			return n;
		}
		tmp = tl tmp;
	}

	return nil;
}

MguiState.setcachednodes(nodelist: list of ref Nodeinfo)
{
	#
	#	Be careful to retain information that we store in the
	#	list over time, in particular, the Nodeinfo.msgwin,
	#	and allocate a new msgwin if a new node is found.
	#

	M.sem_cachednodes.obtain();

	#	First, keep only items already in cache which are on incoming list
	tmp := M.cachednodes;
	M.cachednodes = nil;
	while (tmp != nil)
	{
		node := hd tmp;
		if ((x := inl(node, nodelist)) != nil)
		{
			#	Save the msgwin, replace all other info
			tmpwin := node.msgwin;
			node = x;
			node.msgwin = tmpwin;
			M.cachednodes = node :: M.cachednodes;
		}
		tmp = tl tmp;
	}

	#	Then, add any new items from incoming list
	tmp = nodelist;
	while (tmp != nil)
	{
		node := hd tmp;
		if (inl(node, M.cachednodes) == nil)
		{
			#	If M.win is set, then enough of gui is init
			if (M.gui && M.guiinit)
			{
				node.msgwin = allocmsgwin();

				#	BUG: we do this now, while we are still fleshing out the multi-scroltextwins thing
				#	Lower the newly allocated window to bottom of stack by default
				node.msgwin.bottom();
			}

			M.cachednodes = node :: M.cachednodes;
		}
		tmp = tl tmp;
	}

	tmp = M.cachednodes;
	while (tmp != nil)
	{
		node := hd tmp;

		if (node.nodehost.hostid == M.curhost.hostid && node.iscurnode)
		{
			#	Update the window to which we should draw, if necessary
			pmsgwin = node.msgwin;
			pmsgwin.top();
		}
		tmp = tl tmp;
	}

	M.sem_cachednodes.release();
}

MguiState.getcurhost() : ref Host
{
	M.sem_curhost.obtain();
	x := M.curhost;
	M.sem_curhost.release();

	return x;
}

MguiState.setcurhost(host : ref Host)
{
	M.sem_curhost.obtain();
	M.curhost = host;
	M.sem_curhost.release();
}

MguiState.getcurnode() : ref Nodeinfo
{
	M.sem_curnode.obtain();
	x := M.curnode;
	M.sem_curnode.release();

	return x;
}

MguiState.setcurnode(node : ref Nodeinfo)
{
	M.sem_curnode.obtain();
	M.curnode = node;
	M.sem_curnode.release();
}

Host.getcurnodeid(me: self ref Host) : int
{
	buf	:= array [Sys->ATOMICIO] of byte;

	ctlpath := me.mntpt+"ctl";
	tmpfd	:= timedopen(ctlpath, Sys->OREAD, MG_SMALL_TIMEOUT);
	if (tmpfd == nil)
	{
		error(sys->sprint("Could not open %s: %r", ctlpath));
		return -1;
	}

	n := timedread(tmpfd, buf, len buf, MG_SMALL_TIMEOUT);
	if (n < 0)
	{
		error(sys->sprint("Could not read %s: %r", ctlpath));
		return -1;
	}

	(ntoks, tmplist) := sys->tokenize(string buf[:n], " \n\t,");
	if (ntoks != 6)
	{
		error(sys->sprint("Badly formatted ctl file: [%s]", string buf[:n]));
		return -1;
	}

	curid := hd tl tl tl tl tl tmplist;

	return int curid;
}


Host.getparsednodes(me: self ref Host) : list of ref Nodeinfo
{
	nodelist	: list of ref Nodeinfo;
	buf		:= array [Sys->ATOMICIO] of byte;


	(nodedirs, nnodedirs) := timedreaddir(me.mntpt, Readdir->NONE, MG_SMALL_TIMEOUT);
	if (nnodedirs < 0)
	{
		error(sys->sprint("Host.getparsednodes: Error reading %s: %r", me.mntpt));
		return nil;
	}

#sys->print("host dir has [%d] entries\n", nnodedirs);

	#	For all subdirs, read ctl
	for (i := 0; i < nnodedirs; i++) if (nodedirs[i].qid.qtype & Sys->QTDIR)
	{
		#	Skip the ".0/1" directory
		(l, r) := str->splitstrl(nodedirs[i].name, ".");
		if (r != nil)
		{
			continue;
		}

		nodeinfo := parsenodeinfo(me.mntpt+nodedirs[i].name+"/ctl");
		if (nodeinfo == nil)
		{
			continue;
		}

		nodelist = nodeinfo :: nodelist;
	}

	return nodelist;
}

Nodeinfo.new() : ref Nodeinfo
{
	return ref Nodeinfo (
		nil,		#	CPUtype		: string;
		0,		#	ID		: int;
		0,		#	active		: int;
		0,		#	PC		: int;
		0.0,		#	cycletime	: real;
		big 0,		#	ntrans		: big;
		0.0,		#	Ecpu		: real;
		0.0,		#	Tcpu		: real;
		big 0,		#	ninstrs		: big;
		0.0,		#	Vdd		: real;
		0,		#	nicnifcs	: int;
		0,		#	nicqintrs	: int;
		0.0,		#	Pfail		: real;
		big 0,		#	Maxfdur		: big;
		big 0,		#	nfaults		: big;
		0,		#	simrate		: int;
		0,		#	tripsimrate	: int;
		0,		#	throttle	: int;
		0.0,		#	ratio		: real;
		(0.0, 0.0, 0.0),#	location	: (real, real, real);
		0.0,		#	sensor0		: real;
		Rect(ZP, ZP),	#	tpgyrect	: Draw->Rect;
		nil,		#	nodehost	: cyclic ref Host;
		nil,		#	nodectlfd	: ref Sys->FD;
		0,		#	iscurnode	: int;	
		nil);		#	msgwin		: ref PScrollableText;

}

parsenodeinfo(ctlpath: string) : ref Nodeinfo
{
	buf		:= array [Sys->ATOMICIO] of byte;
	nodeinfo	: Nodeinfo;
	info		:= "";
	bytesread	:= 0;


	fd := sys->open(ctlpath, Sys->OREAD);
	for(;fd != nil;)
	{
		bytesread = timedread(fd, buf, len buf, MG_SMALL_TIMEOUT);
		if (bytesread <= 0)
			break;
		info = info + string buf[:bytesread];
	}

	if (fd == nil || bytesread < 0)
	{
		error(sys->sprint("Could not open/read %s: %r", ctlpath));
		return nil;
	}

	(n, tlist) := sys->tokenize(info, " \t\n");
	if (n != 62)
	{
		error(sys->sprint("tokenizing [%s] returned [%d] != 62 items",
			ctlpath, n));
		return nil;
	}

#TODO: for now we just parse for simrate and throttle, active

	(nil, tmpr) := str->splitstrr(info, "ID =");
	(nil, tlist) = sys->tokenize(tmpr, " \t\n");
	nodeinfo.ID = int hd tlist;

	(nil, tmpr) = str->splitstrr(info, "tripRate =");
	(nil, tlist) = sys->tokenize(tmpr, " \t\n");
	nodeinfo.tripsimrate = int hd tlist;

	(nil, tmpr) = str->splitstrr(info, "Throttle =");
	(nil, tlist) = sys->tokenize(tmpr, " \t\n");
	nodeinfo.throttle = int hd tlist;

	(nil, tmpr) = str->splitstrr(info, "Active =");
	(nil, tlist) = sys->tokenize(tmpr, " \t\n");
	nodeinfo.active = int hd tlist;

	(nil, tmpr) = str->splitstrr(info, "Tcpu =");
	(nil, tlist) = sys->tokenize(tmpr, " \t\n");
	nodeinfo.Tcpu = real hd tlist;

#sys->print("ID = %d, tripsimrate = %d,  throttle = %d, active = %d, Tcpu = %E\n",
#	nodeinfo.ID, nodeinfo.tripsimrate, nodeinfo.throttle, nodeinfo.active, nodeinfo.Tcpu);

	return ref nodeinfo;
}

get_msgswinrect() : Rect
{
	mguiwinrect := M.win.image.r;

	winwidth := int (real (mguiwinrect.dx() - 3*MG_HBORDER_PIXELS)*MG_MSGSWIN_HFRACT);
	winwidth = max(winwidth, MG_MINWIDTH);

	winheight := int (real mguiwinrect.dy()*MG_MSGSWIN_VFRACT);
	winheight = max(winheight, MG_MINHEIGHT);

	min := mguiwinrect.min.add((MG_HBORDER_PIXELS, 2*MG_HBORDER_PIXELS));
	max := min.add((winwidth, winheight));


	return (min, max);
}

get_msgswinscrollrect() : Rect
{
	mr := get_msgswinrect();

	winwidth := MG_VBORDER_PIXELS;
	winheight := mr.dy();

	min := mr.min.add((3*MG_HBORDER_PIXELS, 0));
	max := min.add((winwidth, winheight));
	rect := Rect(min, max);

	return rect.inset(1);
}

get_inputwinrect() : Rect
{
	mguiwinrect := M.win.image.r;
	mr := get_msgswinrect();

	min := mr.min.add((MG_INPUTRECT_HOFFSET, mr.dy()+MG_VBORDER_PIXELS));
	max := mr.max.add((0, MG_VBORDER_PIXELS+MG_INPUTBOX_HEIGHT));


	return (min, max);
}

get_remotewinrect() : Rect
{
	mguiwinrect := M.win.image.r;
	ir := get_inputwinrect();
	wy := mguiwinrect.dy() - MG_BBORDER_PIXELS;
	my := get_msgswinrect().dy();
	iy := ir.dy();

	winheight := wy - (2*MG_VBORDER_PIXELS + my + iy);
	winheight = max(winheight, MG_MINHEIGHT);

	min := ir.min.add((-MG_INPUTRECT_HOFFSET, ir.dy()+MG_VBORDER_PIXELS));
	max := ir.max.add((0, MG_VBORDER_PIXELS+winheight));


	return (min, max);
}

get_topologyrect() : Rect
{
	mguiwinrect := M.win.image.r;
	mr := get_msgswinrect();

	winwidth := int (real (mguiwinrect.dx() - 3*MG_HBORDER_PIXELS)*MG_TPGYWIN_HFRACT);
	winwidth = max(winwidth, MG_MINWIDTH);

	winheight := int (real mguiwinrect.dy()*MG_TPGYWIN_VFRACT);
	winheight = max(winheight, MG_MINHEIGHT);

	min := mguiwinrect.min.add((2*MG_HBORDER_PIXELS+mr.dx(), 2*MG_HBORDER_PIXELS));
	max := min.add((winwidth, winheight));


	return (min, max);
}


get_nodeinforect() : Rect
{
	mguiwinrect := M.win.image.r;
	tr := get_topologyrect();
	mr := get_msgswinrect();

	winwidth := tr.dx();
	winwidth = max(winwidth, MG_MINWIDTH);

	winheight := mr.dy() - MG_VBORDER_PIXELS - tr.dy();
	winheight = max(winheight, MG_MINHEIGHT);

	min := tr.min.add((0, tr.dy() + MG_VBORDER_PIXELS));
	max := min.add((winwidth, winheight));


	return (min, max);
}

get_sanitywinrect() : Rect
{
	mguiwinrect := M.win.image.r;
	tr := get_topologyrect();
	nr := get_nodeinforect();
	my := mguiwinrect.dy() - MG_BBORDER_PIXELS;

	winwidth := tr.dx();
	winwidth = max(winwidth, MG_MINWIDTH);

	winheight := (my - (tr.dy() + nr.dy() + 
				3*MG_VBORDER_PIXELS))/2;
	winheight = max(winheight, MG_MINHEIGHT);

	min := nr.min.add((0, nr.dy() + MG_VBORDER_PIXELS));
	max := min.add((winwidth, winheight));


	return (min, max);
}

get_errwinrect() : Rect
{
	mguiwinrect := M.win.image.r;
	sr := get_sanitywinrect();

	winwidth := sr.dx();
	winwidth = max(winwidth, MG_MINWIDTH);

	winheight := sr.dy();
	winheight = max(winheight, MG_MINHEIGHT);

	min := sr.min.add((0, sr.dy() + MG_VBORDER_PIXELS));
	max := min.add((winwidth, winheight));


	return (min, max);
}

get_bannerwinrect() : Rect
{
	er := get_errwinrect();

	winwidth := er.dx();
	winheight := MG_BBORDER_PIXELS;

	min := er.min.add((0, er.dy() + MG_VBORDER_PIXELS));
	max := min.add((winwidth, winheight));

	return (min, max);
}


get_authorwinrect() : Rect
{
	rr := get_remotewinrect();

	winwidth := rr.dx();
	winheight := MG_BBORDER_PIXELS;

	min := rr.min.add((0, rr.dy() + MG_VBORDER_PIXELS));
	max := min.add((winwidth, winheight));

	return (min, max);
}

runcmd(args : list of string)
{
	execfile := hd args;
	x := len ".dis";
	y := len execfile;


	if ((y <= x) || execfile[y-x:] != ".dis")
	{
		execfile = hd args + ".dis";
	}

	mod := load Command execfile;
	if (mod == nil)
	{
		mod = load Command "/dis/" + execfile;
	}
	if (mod == nil)
	{
		sys->print("Could not run %s: %r\n", execfile);
		return;
	}
	mod->init(nil, args);
}

cleanexit()
{
	sys->pctl(Sys->NEWPGRP, nil);
	spawn runcmd("kill"::"-g"::string M.pgrp::nil);
}

min(a, b : int) : int
{
	if (a < b)
		return a;

	return b;
}

max(a, b : int) : int
{
	if (a > b)
		return a;

	return b;
}

usage()
{
	sys->fprint(M.stderr, "Usage:\n\tmgui [-nogui]\n");
}
