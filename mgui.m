Mgui: module
{
	MG_DEVCHAR		: con 'j';
	MG_CONTROLLER_SHAREDPATH: con "shared/";

	MG_PROMPT		: con "->>  ";
	MG_FLATTABS		: con "        ";
	MG_INPUT_FONT		: con "/fonts/lucidasans/boldlatin1.7.font";
	MG_REMOTEHOSTS_FONT	: con "/fonts/charon/bold.small.font";
	MG_ALERT_FONT		: con "/fonts/lucidasans/typelatin1.6.font";
	MG_MSGS_FONT		: con "/fonts/lucidasans/typelatin1.6.font";
	MG_TPGY_FONT		: con "/fonts/lucidasans/typelatin1.6.font";
	MG_BANNER_FONT		: con "/fonts/lucidasans/typelatin1.6.font";
	MG_NODEINFO_FONT	: con "/fonts/lucidasans/typelatin1.6.font";
	MG_BIG_ALERT_FONT	: con "/fonts/lucidasans/typelatin1.7.font";
	MG_BIG_MSGS_FONT	: con "/fonts/lucidasans/typelatin1.7.font";
	MG_BIG_TPGY_FONT	: con "/fonts/lucidasans/typelatin1.7.font";
	MG_BIG_BANNER_FONT	: con "/fonts/lucidasans/typelatin1.7.font";
	MG_BIG_NODEINFO_FONT	: con "/fonts/lucidasans/typelatin1.7.font";
	MG_AUTHORS_FONT		: con "/fonts/lucidasans/typelatin1.6.font";	##"/appl/myrmigki/ttf/luxisr.ttf";
	MG_BANNERIMG		: con "/dis/sfgui/images/banner.png";
	MG_ANTSIMG		: con "/dis/sfgui/images/ants.gif";
	MG_REMOTEIMG		: con "/dis/sfgui/images/poppi-cpu.gif";
	MG_KEYBOARDIMG		: con "/dis/sfgui/images/poppi-keyboard.gif";
	MG_NODESTDOUTIMG	: con "/dis/sfgui/images/poppi-nodestdout.gif";
	MG_NODESTDERRIMG	: con "/dis/sfgui/images/poppi-nodestderr.gif";
	MG_NODEINFOIMG		: con "/dis/sfgui/images/poppi-nodeinfo.gif";
	MG_SIMINFOIMG		: con "/dis/sfgui/images/poppi-siminfo.gif";
	MG_SANITYIMG		: con "/dis/sfgui/images/poppi-straightjacket.gif";
	MG_WARNIMG		: con "/dis/sfgui/images/poppi-warning.gif";
	MG_ERRORIMG		: con "/dis/sfgui/images/poppi-bomb.gif";
	MG_SPLASHIMG		: con "/dis/sfgui/images/splash.gif";
	MG_MNTDIR		: con "/mnt/sunflower/";
	MG_CONNDIR		: con "/n/remote";
	MG_STDOUTMARKER		: con "\u0087\u00B9  ";	# Bell, 1
	MG_STDERRMARKER		: con "\u0087\u00B2  ";	# Bell, 2
	MG_WIDEST_GLYPH		: con "M";
	MG_TPGYPAD		: con 20;

	#	New Amazon-Look-Inside-Alike color theme
	MG_COLOR_A_MEDIUMGREY	: con int 16rA19C98FF;
	MG_COLOR_A_DARKGREY	: con int 16r857D79FF;

	#	Colors and Schemes
	MG_COLOR_LIGHTGREY	: con int 16rEEEEEEFF;
	MG_COLOR_MEDIUMGREY	: con int 16rDDDDDDFF;
	MG_COLOR_LIGHTORANGE	: con int 16rFF9900FF;
	MG_COLOR_DARKORANGE	: con int 16rFF6600FF;
	MG_COLOR_DARKGREY	: con int 16r5D5D5DFF;
	MG_DEFAULT_BGCOLOR	: con int MG_COLOR_LIGHTGREY;
	MG_DEFAULT_BORDERCOLOR	: con int 16rADADADFF;
	MG_DEFAULT_AUTHORSCOLOR	: con int 16r8D8D8DFF;

	#	Unicode values of some useful glyphs
	MG_RTRIANGLE_UNICODE	: con int 16r25B6;

	#	Gui (window-size-independent) Layout Parameters
	MG_MINWIDTH		: con 60;
	MG_MINHEIGHT		: con 30;
	MG_HBORDER_PIXELS	: con 10;
	MG_VBORDER_PIXELS	: con 5;
	MG_BBORDER_PIXELS	: con 70;
	MG_WINBORDER_PIXELS	: con 0;
	MG_TPGYWIN_HFRACT	: con 0.35;
	MG_TPGYWIN_VFRACT	: con 0.5;
	MG_MSGSWIN_HFRACT	: con 0.65;
	MG_MSGSWIN_VFRACT	: con 0.7;
	MG_INPUTRECT_HOFFSET	: con 35;
	MG_TEXTBOX_INSET	: con 5;
	MG_INPUTBOX_INSET	: con 2;
	MG_INPUTBOX_HEIGHT	: con 17;
	MG_INPUT_HISTORYLEN	: con 64;
	MG_DEFAULT_LINESPACING	: con 1.0;

	#	Default history buffer length. Makes no sense to be
	#	larger than the circular buffers in Myrmigki
	MG_DFLT_TXTBUFLEN	: con 1024;
	MG_DFLT_ERRBUFLEN	: con 128;
	MG_DFLT_REMOTEBUFLEN	: con 128;
	MG_DFLT_AUTHNLINES	: con 4;

	#	Delays for fast/slow refresh threads
	MG_FASTPROC_SLEEP	: con 100;
	MG_SLOWPROC_SLEEP	: con 300;

	#	Timeouts in microseconds
	MG_SMALL_TIMEOUT	: con 30000000;
	MG_MEDIUM_TIMEOUT	: con 60000000;
	MG_LARGE_TIMEOUT	: con 90000000;


	MguiState : adt
	{
		savedargs	: list of string;


		localhost	: ref Host;
		curhost		: ref Host;
		curnode		: ref Nodeinfo;


		cachednodes	: list of ref Nodeinfo;
		cachedhosts	: list of ref Host;


		#	Various communication paths
		kbdchan		: chan of int;
		msgschan	: chan of string;
		rmtchan		: chan of string;
		refreshchan	: chan of string;
		tpgymousechan	: chan of Pointer;

		#	References to state allocated on a display
		alertfont	: ref Font;
		inputfont	: ref Font;
		msgsfont	: ref Font;
		remotehostsfont	: ref Font;
		tpgyfont	: ref Font;
		display		: ref Display;
		screen		: ref Screen;
		win		: ref Wmclient->Window;

		#	Misc.
		controlled	: int;
		stderr		: ref Sys->FD;
		splashactive	: int;
		gui 		: int;
		daemonized	: int;
		pgrp		: int;
		onlyactive	: int;

		
		#	Fine grained locks
		sem_cachedhosts	: ref Lock->Semaphore;
		sem_cachednodes	: ref Lock->Semaphore;
		sem_curhost	: ref Lock->Semaphore;
		sem_curnode	: ref Lock->Semaphore;


		#	Cache of hostname <-> mount file descr names
		mntcache	: ref Cache->StrCache;


		#	Threads access the shared state through these methods
		getcurhost	: fn() : ref Host;
		setcurhost	: fn(host : ref Host);
		getcurnode	: fn() : ref Nodeinfo;
		setcurnode	: fn(node : ref Nodeinfo);

		getcachedhosts	: fn() : list of ref Host;
		setcachedhosts	: fn(hosts : list of ref Host);

		getcachednodes	: fn() : list of ref Nodeinfo;
		setcachednodes	: fn(nodes : list of ref Nodeinfo);

		deletehost	: fn(host : ref Host);
	};

	Layout : adt
	{
		msgswin		: ref Image;
		tpgywin		: ref Image;
		inputbox	: ref Image;
		remotewin	: ref Image;
		graphwin	: ref Image;
	};
	
	Nodeinfo : adt
	{
		#	Info obtained from dev
		CPUtype		: string;
		ID		: int;
		active		: int;
		PC		: int;
		cycletime	: real;
		ntrans		: big;
		Ecpu		: real;
		Tcpu		: real;
		ninstrs		: big;
		Vdd		: real;
		nicnifcs	: int;
		nicqintrs	: int;
		Pfail		: real;
		Maxfdur		: big;
		nfaults		: big;
		simrate		: int;
		tripsimrate	: int;
		throttle	: int;
		ratio		: real;
		location	: (real, real, real);
		sensor0		: real;

		#	Mgui info
		tpgyrect	: Draw->Rect;
		nodehost	: ref Host;
		nodectlfd	: ref Sys->FD;
		iscurnode	: int;

		new		: fn() : ref Nodeinfo;
	};

	Host : adt
	{
		hostid		: int;
		hostname	: string;
		devname		: string;
		mntpt		: string;
		msgscreens	: list of ref PScrollableText;
		enginectlfd	: ref Sys->FD;
		netinfd		: ref Sys->FD;
		netoutfd	: ref Sys->FD;

		#	Used/set by equalizers
		cachedsimrate	: real;
		cachedthrottle	: int;
		cachedTcpu	: real;

		gethostnodes	: fn(me: self ref Host) : list of ref Nodeinfo;
		getcurnodeid	: fn(me: self ref Host) : int;
	};
	
	Segbuf : adt
	{
		timestamp	: real;
		data		: array of byte;
		payloadlen	: int;
		bits_left	: int;
		src_nodeid	: int;
		dst_nodeid	: int;
		bcast		: int;
		src_ifc		: int;
		parent_netsegid	: int;
		from_remote	: int;
	};

	init			: fn(ctxt: ref Draw->Context, args: list of string);

	ptpgywin		: ref PScrollableText;
	pbannerwin		: ref PScrollableText;
	perrwin			: ref PScrollableText;
	psanitywin		: ref PScrollableText;
	pmsgwin			: ref PScrollableText;
	pinputwin		: ref PTextEntry;
	prmtwin			: ref PScrollableText;
	pauthorswin		: ref PScrollableText;
	pnodeinfowin		: ref PScrollableText;
	pscrollmsgwin		: ref PScrollBar;
};


Command : module
{
	init			: fn(ctxt: ref Draw->Context, args: list of string);
};

