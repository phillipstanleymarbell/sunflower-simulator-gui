#
#	PGui :	The popup-free gui toolkit (for Inferno). One
#		window, no pop-ups :)
#

Pgui : module
{
	PATH			: con "/dis/sfgui/pgui.dis";

	ZP			: con (0, 0);

	PG_DEFLT_GLYPHCACHESZ	: con 128;
	PG_TALLEST_GLYPH	: con "I";
	PG_TABLEN		: con 5;
	PG_NEWLINE		: con '\n';
	PG_BACKSPACE		: con '\b';
	PG_UPARROW		: con 57362;	# Scancode E0 12
	PG_DNARROW		: con 57363;	# Scancode E0 13
	PG_LTARROW		: con 57364;	# Scancode E0 14
	PG_RTARROW		: con 57365;	# Scancode E0 15
	PG_CTRLUPARROW		: con 18;
	PG_CTRLDNARROW		: con 19;
	PG_CTRLLTARROW		: con 20;
	PG_CTRLRTARROW		: con 21;
	PG_TAB			: con '\t';
	PG_LeftJustify,
	PG_RightJustify,
	PG_CenterJustify,
	PG_FullJustify		: con 1 << iota;


	#
	#	For now we call the adt methods direcctly, but would
	#	be nice to eventually have a wrapper FS for creating
	#	and manipulating the various objects.
	#
	#	Each object created by such a filesystem should have
	#	a per-filesystem uniqe ID (doesnt dev/draw already do this ?)
	#	and this ID string is returned to you when you create a
	#	new object. You can then use this to change properties on
	#	the object. E.g., a "color selection tool" like Inspector in
	#	keynote, to let you change font, bgcolor, and any of the
	#	per-object-specific properties of a particular object
	#	Thus things become "skinnable", since a skin is just
	#	a program that traverses the "gui tree", queries what objects
	#	exist at each level, and has predefined configs for
	#	setting the various attributes of each object type.
	#

	PFont : adt
	{
		pick
		{
			Inferno 	=> font : ref Draw->Font;

			Freetype2	=> pfont: ref PFreetype2;
		}
	
		height	: fn(font: self ref PFont) : int;
		width	: fn(font: self ref PFont, s: string) : int;
	};


	PFreetype2 : adt
	{
		face		: ref Freetype->Face;
		glyphcache	: array of (int, ref Freetype->Glyph, int);

		#	Debug statistics
		accesses	: int;
		hits		: int;

		text		: fn(pft2: self ref PFreetype2, img: ref Draw->Image,
					cursorloc: Draw->Point, txtimg: ref Draw->Image, s: string);
		getglyph	: fn(pft2: self ref PFreetype2, c : int) : ref Freetype->Glyph;
		setxfrm		: fn(pft2: self ref PFreetype2, m: ref Freetype->Matrix,
					v: ref Freetype->Vector): string;
		setsize		: fn(pft2: self ref PFreetype2, pts, hdpi, vdpi: int): string;
		new		: fn(face: ref Freetype->Face, cachesize: int) : ref PFreetype2;
	};


	PGeneric : adt
	{
		pick
		{
			Text	=> text	: string;
				   font	: ref PFont;
				   j11n : int;

			Image	=> img	: ref Draw->Image;
		}
	};
	

	PLine : adt
	{
		linebrk		: int;
		sublines	: list of ref PGeneric;

		width		: fn(nil: self ref PLine) : int;
		height		: fn(nil: self ref PLine) : int;
	};


	#
	#	Each of the following is treated as a Window (i.e., an Image managed by a
	#	particular screen, to make overlapping, z-ordering etc easier to manage.
	#
	PScrollableText : adt
	{
		#	Created via screen.newwindow() when the .new() method is called
		layerwin	: ref Draw->Image;

		#	An offscreen image, parts of which get drawn onto the above window
		layerimg	: ref Draw->Image;

		scrollable	: int;
		autoscroll	: int;
		smoothscroll	: int;
		cursorloc	: Draw->Point;
		curorigin	: Draw->Point;
		lines		: array of ref PLine;
		nlines		: int;
		bgimg		: ref Draw->Image;
		txtimg		: ref Draw->Image;
		font		: ref PFont;
		linespacing	: real;
		semaphore	: ref Lock->Semaphore;
	
		append		: fn(p : self ref PScrollableText, msg : string);
		delete		: fn(p : self ref PScrollableText,
					whichline, startpt, endpt : int);
		insert		: fn(p : self ref PScrollableText, whichline, insertpt : int);
		reset		: fn(p : self ref PScrollableText);
		resetclear	: fn(p : self ref PScrollableText);
		highlight	: fn(p : self ref PScrollableText,
					whichline, startpt, endpt : int, color : ref Draw->Image);
		scrollup	: fn(p : self ref PScrollableText, npixels : int);
		smoothscrollup	: fn(p : self ref PScrollableText, npixels : int);
		scrolldn	: fn(p : self ref PScrollableText, npixels : int);
		smoothscrolldn	: fn(p : self ref PScrollableText, npixels : int);
		scrolllt	: fn(p : self ref PScrollableText, npixels : int);
		smoothscrolllt	: fn(p : self ref PScrollableText, npixels : int);
		scrollrt	: fn(p : self ref PScrollableText, npixels : int);
		smoothscrollrt	: fn(p : self ref PScrollableText, npixels : int);
		settxtimg	: fn(p : self ref PScrollableText, txtimg : ref Draw->Image);
		setbgimg	: fn(p : self ref PScrollableText, bgimg : ref Draw->Image);
		setlayerimg	: fn(p : self ref PScrollableText, layerimg : ref Draw->Image);
		setfont		: fn(p : self ref PScrollableText, fontname : string);
		setlinespacing	: fn(p : self ref PScrollableText, spacing : real);
		winactive	: fn(p : self ref PScrollableText);
	

		#
		#	These are used, e.g. in Mgui to maintain a collection
		#	of ScrollableTexts, and this is used to trivially
		#	implement, e.g., a "tabbed display". setalpha() can
		#	be used for transparency, e.g. in Mgui to show all the layers
		#	of a stack of ScrollableTexts at the same time
		#
		top	: fn(scrlwin : self ref PScrollableText);
		bottom	: fn(scrlwin : self ref PScrollableText);
		hide	: fn(scrlwin : self ref PScrollableText);
		delwin	: fn(scrlwin : self ref PScrollableText);
		setalpha: fn(scrlwin : self ref PScrollableText, alpha : int);


		#
		#	This can be used to stack multiple layers, e.g.,
		#	first render text, then get the Image and then 
		#	draw images on top of that, etc., or to do
		#	recursive rendering of a ScrollableText
		#	within another, etc.,
		#
		getlayerimg	: fn(scrlwin : self ref PScrollableText) : ref Draw->Image;
		# getlayerwin	: fn(p : self ref PScrollableText) : ref Image;
	
	
		lock		: fn(p: self ref PScrollableText);
		unlock		: fn(p: self ref PScrollableText);
		new		: fn(s : ref Draw->Screen, r : Draw->Rect,
				fontname : string, nlines, wincolor, bgcolor : int) : 
					(ref PScrollableText, string);
	};
	
	PTextEntry : adt
	{
		s		: ref PScrollableText;
		prompt		: string;
		entrybuf	: string;
		history		: array of string;
		nhistory	: int;
		curidx		: int;
		lastmouse	: Draw->Pointer;
		selected	: (int, int);

		update		: fn(p: self ref PTextEntry, key: int, mouse: Draw->Pointer) : string;
		new		: fn(prompt: string, s : ref Draw->Screen, r : Draw->Rect, fontname : string,
				nlines, wincolor, bgcolor : int) : 
				(ref PTextEntry, string);
	};

	PScrollableList : adt
	{
		#	created via screen.newwindow() when the .new() method is called
		layerwin	: ref Draw->Image;

		#	Specialize ScrollableText to do per-line highlighting
		highlightimg	: ref Draw->Image;
		items		: PScrollableText;

		new		: fn(screen : ref Draw->Screen, rect : Draw->Rect) : ref PScrollableList;
	};
	
	PScrollBar : adt
	{
		#	How much stuff we're controlling, and maximum amount
		depth		: int;
		maxdepth	: int;
		layerwin	: ref Draw->Image;
		layerimg	: ref Draw->Image;

		new		: fn(screen: ref Draw->Screen, rect: Draw->Rect,
					depth, maxdepth, fgcolor, bgcolor: int) : (ref PScrollBar, string);
	};
	
	PButton : adt
	{
		#	created via screen.newwindow() when the .new() method is called
		layerwin	: ref Draw->Image;

		new		: fn(screen : ref Draw->Screen, rect : Draw->Rect) : ref PButton;
	};
	
	PFileDialog : adt
	{
		#	created via screen.newwindow() when the .new() method is called
		layerwin	: ref Draw->Image;

		#	A specialization of PScollable list, PScrollable text etc.
		new		: fn(screen : ref Draw->Screen, rect : Draw->Rect) : ref PFileDialog;
	};


	init			: fn() : (int, string);
##	get_rectborder : fn();
##	scale_linear : fn() : ref Draw->image;
##	scale_bilinear : fn();
##	average		: fn();
#
#	Functions for easier interfaceing with Readimg etc,
#		automatically determining the file type like
#		wm/view does, and retuning error if no decoder
#		was found
	drawimgfromfile	: fn(filename : string, where : Draw->Rect, dstimg : ref Draw->Image) : string;
	getimgfromfile	: fn(filename : string, display : ref Draw->Display) : (ref Draw->Image, string);
	getrectborder	: fn(r : Draw->Rect) : array of Draw->Point;
};
