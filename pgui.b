implement Pgui;

include "sys.m";
include "draw.m";
include "string.m";
include "freetype.m";
include "bufio.m";
include "imagefile.m";
include "lock.m";
include "pgui.m";

sys			: Sys;
draw			: Draw;
str			: String;
ft2			: Freetype;
bufio			: Bufio;
lock			: Lock;

Iobuf			: import bufio;
Matrix,
	Vector,
	Face,
	Glyph		: import ft2;
Context,
	Display,
	Font,
	Image,
	Point,
	Pointer,
	Rect,
	Screen,
	Wmcontext	: import draw;

Semaphore		: import lock;


init() : (int, string)
{
	sys	= load Sys Sys->PATH;
	ft2	= load Freetype Freetype->PATH;
	if (ft2 == nil)
	{
		return (-1, sys->sprint("Could not load Freetype: %r"));
	}

	draw = load Draw Draw->PATH;
	if (draw == nil)
	{
		return (-1, sys->sprint("Could not load Draw: %r"));
	}

	str = load String String->PATH;
	if (str == nil)
	{
		return (-1, sys->sprint("Could not load String: %r"));
	}

	bufio = load Bufio Bufio->PATH;
	if (bufio == nil)
	{
		return (-1, sys->sprint("Could not load Bufio: %r"));
	}

	lock = load Lock Lock->PATH;
	if (lock == nil)
	{
		return (-1, sys->sprint("Could not load Lock: %r"));
	}


	return (0, nil);
}


PScrollableText.new(screen: ref Draw->Screen, rect: Rect,
		fontname: string, nlines, wincolor, bgcolor: int) : (ref PScrollableText, string)
{
	p := ref PScrollableText (nil, nil, 1, 0, 0, ZP, ZP, nil, 0, nil, nil, nil, 1.0, nil);
	p.semaphore = Semaphore.new();

	#	First, try to load font as a Freetype 2 font.
	face := ft2->newface(fontname, 0);
	if (face != nil)
	{
		#	Glyph metrics are in 26.6 fixed point format (1 = 1/64th of a pixel)
		face.setcharsize(10<<6, 72, 72);
		p.font = ref PFont.Freetype2(PFreetype2.new(face, PG_DEFLT_GLYPHCACHESZ));
	}
	else
	{
		ifont := Font.open(screen.display, fontname);
		if (ifont == nil)
		{
			ifont = Font.open(screen.display, "*default*");
		}
		if (ifont == nil)
		{
			return (nil, sys->sprint("Could not open *default* font: %r"));
		}

		p.font = ref PFont.Inferno(ifont);
	}

	p.layerwin	= screen.newwindow(rect, Draw->Refbackup, wincolor);
	if (p.layerwin == nil)
	{
		return (nil, sys->sprint("Could not allocate a screen.newwindow(): %r"));
	}

	#	Whole image is actually based on the nlines parameter
	spacing 	:= int (real p.font.height() * p.linespacing);
	winwidth	:= rect.dx();
	winheight	:= spacing * nlines;
	winrect		:= Rect (rect.min, rect.min.add((winwidth, winheight)));

	p.layerimg	= screen.display.newimage(winrect, screen.image.chans, 0, bgcolor);
	if (p.layerimg == nil)
	{
		return (nil, sys->sprint("Could not allocate a screen.display.newimage(): %r"));
	}

	p.curorigin	= p.layerimg.r.min;

	pick f := p.font
	{
		Inferno		=>	p.cursorloc = p.curorigin;
				
		Freetype2	=>	p.cursorloc = p.curorigin.add((0, f.height()));
	}

	p.lines		= array [nlines] of ref PLine;
	p.nlines	= 0;


	return (p, nil);
}


PScrollableText.append(p: self ref PScrollableText, msg: string)
{
	p.lock();
	msglines	:= splitlines(p, msg);
	spacing		:= int (real p.font.height() * p.linespacing);

	while (msglines != nil)
	{
		curline := hd msglines;

		if (p.nlines == len p.lines)
		{
			p.lines[0:] = p.lines[1:];
			p.nlines--;
		}
		p.lines[p.nlines++] = curline;

		put(p, curline);

		if (!p.scrollable)
		{
			msglines = tl msglines;
			continue;
		}

		if (curline.linebrk)
		{
			p.cursorloc.x = p.layerwin.r.min.x;
			p.cursorloc = p.cursorloc.add((0, spacing));

			if (p.autoscroll &&
				(p.cursorloc.y > min(p.layerwin.r.max.y, p.layerimg.r.max.y)))
			{
				if (p.smoothscroll)
				{
					p.smoothscrollup(spacing);
				}
				else
				{
					p.scrollup(spacing);
				}
			}
		}

		msglines = tl msglines;
	}
	p.layerwin.draw(p.layerwin.r, p.layerimg, nil, p.curorigin);
	p.unlock();

	return;
}

put(p: ref PScrollableText, curline: ref PLine)
{
	sublines := curline.sublines;
	while (sublines != nil)
	{
		pick l := hd sublines
		{
		Text =>
			text := clean(l.text);
			if (len text == 0)
			{
				sublines = tl sublines;
				continue;
			}

			pick f := l.font
			{
				Inferno =>
				{
					p.layerimg.text(p.cursorloc, p.txtimg, ZP, f.font, text);
					p.cursorloc = p.cursorloc.add((f.width(text), 0));
				}

				Freetype2 =>
				{
					f.pfont.text(p.layerimg, p.cursorloc, p.txtimg, text);
					p.cursorloc = p.cursorloc.add((f.width(text), 0));
				}
			}

		Image =>
			p.layerimg.draw(p.layerimg.r, p.layerimg, nil, p.cursorloc);
			p.cursorloc = p.cursorloc.add((l.img.r.dx(), 0));
		}
		sublines = tl sublines;
	}
	return;
}


splitlines(p: ref PScrollableText, msg: string) : list of ref PLine
{
	if (msg == nil)
	{
		return nil;
	}

	lines		: list of ref PLine;
	curhoffset	:= p.cursorloc.x - p.layerwin.r.min.x;

	#	Slack space (width of an "M") for last char
	layer_width	:= p.layerwin.r.dx() - p.font.width("M");

	#	We stop one short of last char in string
	last := 0;
	for (i := 0; i < (len msg - 1); i++)
	{
		if (msg[i] == '\n' ||
			p.font.width(msg[last:i+1]) + curhoffset > layer_width)
		{
			tmp := ref PLine(1,
				ref PGeneric.Text(msg[last:i+1], p.font, PG_LeftJustify)::nil);
			lines = tmp :: lines;
			last = i+1;
			curhoffset = 0;
		}
	}

	lines = ref PLine(msg[len msg - 1] == '\n',
		ref PGeneric.Text(msg[last:], p.font, PG_LeftJustify)::nil) :: lines;

	return reorder(lines);
}

PScrollableText.scrollup(p : self ref PScrollableText, npixels : int)
{
	if (p.curorigin.y + npixels > p.cursorloc.y)
	{
		return;
	}

	p.curorigin 	= p.curorigin.add((0, npixels));
	spacing 	:= int (real p.font.height() * p.linespacing);

	#
	#	We keep the common case (scrollup) fast. When bottom
	#	of layerimg is reached, we wipe it clear and move to
	#	top. For a scrolldn, we'll have to redraw layerimg
	#	from contents of p.lines[].
	#
	if (p.curorigin.y + ((p.cursorloc.y + spacing) - p.layerwin.r.min.y)  > p.layerimg.r.max.y)
	{
		#	Wipe and reset
		p.layerimg.draw(p.layerimg.r, p.layerwin.display.white, nil, ZP);
		p.curorigin = p.layerimg.r.min;
		p.cursorloc = p.curorigin;

		winlines	:= min(p.layerwin.r.dy()/spacing,
						p.layerimg.r.dy()/spacing);
		start		:= max(p.nlines - winlines, 0);


		#	Fill the win with the most recent output
		if (p.nlines > winlines) for (i := 0; i < winlines; i++)
		{
			put(p, p.lines[p.nlines - 1 - winlines + i]);
			p.cursorloc.x = p.layerwin.r.min.x;
			p.cursorloc = p.cursorloc.add((0, spacing));
		}
	}
	p.layerwin.draw(p.layerwin.r, p.layerimg, nil, p.curorigin);

	return;
}

PScrollableText.scrolldn(p: self ref PScrollableText, npixels: int)
{
#sys->print("p.curorigin = (%d, %d)\n", p.curorigin.x, p.curorigin.y);
#sys->print("p.layerimg.r.min = (%d, %d)\n\n", p.layerimg.r.min.x, p.layerimg.r.min.y);

	if (p.curorigin.y - npixels >= p.layerimg.r.min.y)
	{
		p.curorigin.y -= npixels;
		p.layerwin.draw(p.layerwin.r, p.layerimg, nil, p.curorigin);
	}

	return;
}

PScrollableText.smoothscrollup(p: self ref PScrollableText, npixels: int)
{
	for (i := 0; i < npixels; i++)
		p.scrollup(1);
}

PScrollableText.smoothscrolldn(p: self ref PScrollableText, npixels: int)
{
	for (i := 0; i < npixels; i++)
		p.scrolldn(1);
}

PScrollableText.delete(p: self ref PScrollableText,
	whichline, startpt, endpt: int)
{
}

PScrollableText.highlight(p: self ref PScrollableText,
	whichline, startpt, endpt: int, highlightcolor: ref Image)
{
}

PScrollableText.reset(p: self ref PScrollableText)
{
	p.cursorloc	= p.layerwin.r.min;
	p.curorigin	= p.layerwin.r.min;
	p.nlines	= 0;

	#	Wipe the layerimg but dont update the layerwin
	p.layerimg.draw(p.layerimg.r, p.layerimg.display.white, nil, ZP);
}

PScrollableText.resetclear(p: self ref PScrollableText)
{
	p.cursorloc	= p.layerwin.r.min;
	p.curorigin	= p.layerwin.r.min;
	p.nlines	= 0;

	#	Wipe the layerimg AND write to layerwin
	p.layerimg.draw(p.layerimg.r, p.layerimg.display.white, nil, ZP);
	p.layerwin.draw(p.layerwin.r, p.layerimg, nil, p.layerimg.r.min);
}

PScrollableText.insert(p: self ref PScrollableText, whichline, insertpt: int)
{
}


PScrollableText.scrolllt(p: self ref PScrollableText, npixels: int)
{
}

PScrollableText.scrollrt(p: self ref PScrollableText, npixels: int)
{
}

PScrollableText.smoothscrolllt(p: self ref PScrollableText, npixels: int)
{
	for (i := 0; i < npixels; i++)
		p.scrolllt(1);
}

PScrollableText.smoothscrollrt(p: self ref PScrollableText, npixels: int)
{
	for (i := 0; i < npixels; i++)
		p.scrollrt(1);
}

PScrollableText.settxtimg(p: self ref PScrollableText, txtimg: ref Image)
{
	p.txtimg = txtimg;
}

PScrollableText.setbgimg(p: self ref PScrollableText, bgimg: ref Image)
{
	p.bgimg = bgimg;
}

PScrollableText.setlayerimg(p: self ref PScrollableText, layerimg: ref Image)
{
	p.layerimg = layerimg;
}

PScrollableText.setfont(p: self ref PScrollableText, fontname: string)
{
}

PScrollableText.setlinespacing(p: self ref PScrollableText, spacing: real)
{
	p.linespacing = spacing;
}

PScrollableText.getlayerimg(p: self ref PScrollableText) : ref Image
{
	return nil;
}

PScrollableText.top(p: self ref PScrollableText)
{
}

PScrollableText.bottom(p: self ref PScrollableText)
{
}

PScrollableText.hide(p: self ref PScrollableText)
{
}

PScrollableText.delwin(p: self ref PScrollableText)
{
}

PScrollableText.setalpha(p: self ref PScrollableText, alpha : int)
{
}

PScrollableText.winactive(p: self ref PScrollableText)
{
	#	Get the borderrect
}

PScrollableText.lock(p: self ref PScrollableText)
{
	p.semaphore.obtain();
}

PScrollableText.unlock(p: self ref PScrollableText)
{
	p.semaphore.release();
}

PLine.width(pline: self ref PLine) : int
{
	width := 0;

	sublines := pline.sublines;
	while (sublines != nil)
	{
		pick s := hd sublines
		{
		Text	=>
			width += s.font.width(s.text);

		Image	=>
			width += s.img.r.dx();
		}

		sublines = tl sublines;
	}

	return width;
}

PLine.height(pline: self ref PLine) : int
{
	height := 0;

	sublines := pline.sublines;
	while (sublines != nil)
	{
		pick s := hd sublines
		{
		Text	=>
			height = max(height, s.font.height());

		Image	=>
			height = max(height, s.img.r.dy());
		}

		sublines = tl sublines;
	}

	return height;
}

PFont.width(font: self ref PFont, s: string) : int
{
	pick f := font
	{
		Freetype2 =>
		{
			width := 0;

			#	Given the FT2 interface, everything has
			#	to be done glyph-at-a-time. Bummer.
			for (i := 0; i < len s; i++)
			{
				g := f.pfont.getglyph(s[i]);

				#	This should really be the
				#	'horiz. advance' glyph metric
				if (g != nil)
				{
					width += g.width;
				}
			}
			return width;
		}

		Inferno =>
		{
			return f.font.width(s);
		}
	}
}

PFont.height(font: self ref PFont) : int
{
	pick f := font
	{
		Freetype2 =>
		{
			return f.pfont.face.height;
		}

		Inferno =>
		{
			return f.font.height;
		}
	}
}

PScrollableList.new(screen: ref Screen, rect: Rect) : ref PScrollableList
{
	return nil;
}

PScrollBar.new(screen: ref Draw->Screen, rect: Draw->Rect,
		depth, maxdepth, fgcolor, bgcolor: int) : (ref PScrollBar, string)
{
	p := PScrollBar (depth, maxdepth, nil, nil);
	p.layerwin = screen.newwindow(rect, Draw->Refbackup, bgcolor);
	if (p.layerwin == nil)
	{
		return (nil, sys->sprint(
			"Could not allocate mem for PScrollBar.layerwin: %r"));
	}

	p.layerimg = screen.display.newimage(rect, screen.image.chans, 0,bgcolor);
	if (p.layerimg == nil)
	{
		return (nil, sys->sprint(
			"Could not allocate mem for PScrollBar.layerimg: %r"));
	}

	color	:= screen.display.color(fgcolor);
	lcolor	:= screen.display.color(int 16rDDDDDDFF);

	p0	:= Point ((rect.min.x+rect.max.x)/2, rect.min.y+5);
	p1	:= p0.add((0, rect.dy()-2*5));
	barrect	:= (rect.min.add((0, 10)), rect.min.add((rect.dx()+1, 50)));

	p.layerimg.line(p0, p1, Draw->Enddisc, Draw->Enddisc, 0, lcolor, p0);
	p.layerimg.fillpoly(getrectborder(barrect), ~0, color, rect.min);;

	p.layerwin.draw(p.layerwin.r, p.layerimg, nil, p.layerimg.r.min);


	return (ref p, nil);
}

PButton.new(screen: ref Screen, rect: Rect) : ref PButton
{
	return nil;
}

PFileDialog.new(screen: ref Screen, rect: Rect) : ref PFileDialog
{
	return nil;
}

PTextEntry.new(prompt: string, s: ref Screen, r: Rect, fontname: string, 
	nhistory, wincolor, bgcolor: int) : (ref PTextEntry, string)
{
	p 		:= ref PTextEntry (nil, prompt, nil, nil, 0, 0, (0, ZP, 0), (0, 0));
	p.history 	= array [nhistory] of string;
	err 		:= "";
	(p.s, err)	= PScrollableText.new(s, r, fontname, 1, wincolor, bgcolor);
	p.s.scrollable = 0;
	p.s.autoscroll = 0;

	#	Should eventually also spawn a thread here to blink cursor
	#	if cursor is configured to blink.

	return (p, err);
}

PTextEntry.update(p: self ref PTextEntry, key: int, mouse: Pointer) : string
{
	retstr : string;

	if (p == nil)
	{
		return nil;
	}

	case key
	{
	PG_NEWLINE	=>
		if (p.entrybuf != nil)
		{		
			retstr = p.entrybuf;
			p.history[p.nhistory++] = p.entrybuf;
			if (p.nhistory >= len p.history)
			{
				p.history[0:] = p.history[1:];
				p.nhistory--;
			}
			p.curidx = p.nhistory;
			p.entrybuf = nil;
		}

	PG_BACKSPACE	=>
		if (len p.entrybuf > 0)
		{
			p.entrybuf = p.entrybuf[:len p.entrybuf - 1];
		}

# TODO: need to figure out a good architecture for delivering
# mouse events. leftarr and rtarr should be used in Mgui for
# history, and uparr and dnarr for scrolling the  msgswin

	PG_RTARROW	=> ;

	PG_LTARROW	=> ;

	PG_UPARROW	=>
			p.curidx--;
			p.curidx = max(p.curidx, 0);
			p.entrybuf = p.history[p.curidx];

	PG_DNARROW	=>
			p.curidx++;
			p.curidx = min(p.curidx, p.nhistory);
			p.entrybuf = p.history[p.curidx];

	PG_TAB		=>
			n := len p.entrybuf;

			for (i := 0; i < p.nhistory; i++)
			{
				if (len p.history[i] > n &&
					p.entrybuf == p.history[i][:n])
				{
					p.entrybuf = p.history[i];
					break;
				}
			}

	*		=>
		p.entrybuf[len p.entrybuf] = key;
	}
	p.s.reset();
	p.s.append((p.prompt+p.entrybuf));


	return retstr;
}

PFreetype2.text(pft2: self ref PFreetype2, img: ref Image, cursorloc: Point, txtimg: ref Image, s: string)
{	
	origin	:= Point(cursorloc.x<<6, cursorloc.y<<6);
	bbox	:= Rect((0,0), (0,0));

	#	The rendered glyph bitmap from ft2 is a 256-grey image
	glyphsimg	:= img.display.newimage(img.r, Draw->GREY8, 0, Draw->Transparent);
	xbufimg		:= img.display.newimage(img.r, img.chans, 0, Draw->Transparent);
	if (glyphsimg == nil || xbufimg == nil)
	{
		raise "fail: Couldn't alloc glyphsimg/bufimg for rendering via FT2 in Pgui";
	}

	xbufimg.drawop(img.r, img, nil, img.r.min, Draw->S);
	for (i := 0; i < len s; i++)
	{
		g := pft2.getglyph(s[i]);
		if (g == nil)
		{
			sys->print("ft2_text: No glyph for char [%c][==%d]\n", s[i], s[i]);
			continue;
		}

		drawpt := Point(g.left+(origin.x>>6), (origin.y>>6)-g.top);
		r := Rect((0,0), (g.width, g.height));
		r = r.addpt(drawpt);
		bbox = bbox.combine(r);
		glyphsimg.writepixels(r, g.bitmap);
		xbufimg.draw(r, txtimg, glyphsimg, r.min);
		origin.x += g.advance.x;
		origin.y -= g.advance.y;
	}
	img.drawop(img.r, xbufimg, nil, img.r.min, Draw->S);

	return;
}

PFreetype2.getglyph(pft2: self ref PFreetype2, c: int) : ref Freetype->Glyph
{
#	pft2.accesses++;

#	if (!(pft2.accesses % 100))
#	{
#		sys->print("%d accesses, %d hits\n", pft2.accesses, pft2.hits);	
#	}

	idx := c % len pft2.glyphcache;
	(ch, glyph, valid) := pft2.glyphcache[idx];

	if (valid && ch == c)
	{
#		pft2.hits++;
		return glyph;
	}

	glyph = pft2.face.loadglyph(c);		
if (glyph == nil)
{
	sys->print("PFreetype2.getglyph: No glyph for char [%c][==%d]\n", c, c);
}

	pft2.glyphcache[idx] = (c, glyph, 1);

	return glyph;
}

PFreetype2.setxfrm(pft2: self ref PFreetype2, m: ref Freetype->Matrix, v: ref Freetype->Vector): string
{
	return pft2.face.settransform(m, v);
}

PFreetype2.setsize(pft2: self ref PFreetype2, pts, hdpi, vdpi: int): string
{
	return pft2.face.setcharsize(pts, hdpi, vdpi);
}

PFreetype2.new(face: ref Freetype->Face, cachesize: int) : ref PFreetype2
{
	glyphcache := array [cachesize] of (int, ref Freetype->Glyph, int);
	spawn pft2cacheinit(face, glyphcache);

	return ref PFreetype2(face, glyphcache, 0, 0);
}

pft2cacheinit(face: ref Freetype->Face, glyphcache: array of (int, ref Freetype->Glyph, int))
{
	for (i := 0; i < len glyphcache; i++)
	{
		glyphcache[i] = (i, face.loadglyph(i), 1);

(nil, glyph, nil) := glyphcache[i];
if (glyph == nil)
{
	sys->print("pft2cacheinit: No glyph for char [%c][==%d]\n", i, i);
}

	}
}

drawimgfromfile(filename : string, where : Draw->Rect, dstimg : ref Draw->Image) : string
{
	readgif		:= load RImagefile RImagefile->READGIFPATH;
	imageremap	:= load Imageremap Imageremap->PATH;

	fd := bufio->open(filename, Sys->OREAD);
	if (fd == nil)
	{
		return sys->sprint("Could not load banner image : %r");
	}

# TODO: for now, we only handle gifs. /appl/wm/view.b really should make its
#	interface public so we can reused things like its filetype() routine
#	or maybe rather just improve on what it does and eventually migrate
#	wm/view to use Pgui

	readgif->init(bufio);
	(rawimage, readgiferr) := readgif->read(fd);
	if (rawimage == nil)
	{
		return sys->sprint("Could not load banner image : %s", readgiferr);
	}
	(mappedimg, remaperr) := imageremap->remap(rawimage, dstimg.display, 0);
	if (mappedimg == nil)
	{
		return sys->sprint("Could not load banner image : %s", remaperr);
	}

	dstimg.draw(where, mappedimg, nil, mappedimg.r.min);

	return nil;
}

getimgfromfile(filename : string, display : ref Display) : (ref Image, string)
{
	readgif		:= load RImagefile RImagefile->READGIFPATH;
	imageremap	:= load Imageremap Imageremap->PATH;

	fd := bufio->open(filename, Sys->OREAD);
	if (fd == nil)
	{
		return (nil, sys->sprint("Could not load banner image : %r"));
	}

# TODO: for now, we only handle gifs. /appl/wm/view.b really should make its
#	interface public so we can reused things like its filetype() routine
#	or maybe rather just improve on what it does and eventually migrate
#	wm/view to use Pgui

	readgif->init(bufio);
	(rawimage, readgiferr) := readgif->read(fd);
	if (rawimage == nil)
	{
		return (nil, sys->sprint("Could not load banner image : %s", readgiferr));
	}
	(mappedimg, remaperr) := imageremap->remap(rawimage, display, 0);
	if (mappedimg == nil)
	{
		return (nil, sys->sprint("Could not load banner image : %s", remaperr));
	}

	return (mappedimg, nil);
}

getrectborder(r : Rect) : array of Point
{
#	TODO: this is a waste: should just use Image.border to do borders

	return array [] of {	r.min, r.min.add((r.dx()-1, 0)),
				r.max.sub((1,1)), r.min.add((0, r.dy()-1)), r.min};
}

joinlist [T] (front, rear : list of T) : list of T
{
	front = reorder(front);
	while (front != nil)
	{
		rear = hd front :: rear;
		front = tl front;
	}

	return rear;
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

flatten(s : string) : string
{
	(l, r) := str->splitl(s, "\t");
	while (r != nil)
	{
		n := (len l)%PG_TABLEN;
		tabs := array [n] of {* => byte ' '};

		s = l+string tabs+r[1:];
		(l, r) = str->splitl(s, "\t");
	}

	return s;
}


cleanbs(s : string) : string
{
	(l, r) := str->splitl(s, "\b");
	while (r != nil)
	{
		if (len l > 0)
		{
			s = l[:len l - 1]+r[1:];
		}
		else
		{
			s = l+r[1:];
		}
		(l, r) = str->splitl(s, "\b");
	}

	return s;
}

cleanlf(s : string) : string
{
	for (i := 0; i < len s - 1; i++)
	{
		if (s[i] == '\n')
		{
			s = s[:i] + s[i+1:];
		}
	}

	if (s[i] == '\n')
	{
		s = s[:i];
	}

	return s;
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

clean(s : string) : string
{
#	s = cleanbs(s);
	s = cleanlf(s);
	s = flatten(s);

	return s;
}
