SUNFLOWERROOT	= /Users/pip/Hg/sunflowersim-svn-changes
INFERNOSRCROOT	= /Users/pip/inferno-os-read-only

<$INFERNOSRCROOT/mkconfig

DIRS=\
#	\

TARG=\
	pgui.dis\
	mgui.dis\
	timedio.dis\
	cache.dis\

MODULES=\
	mgui.m\
	pgui.m\
	timedio.m\
	cache.m\

SYSMODULES=\
	bufio.m\
	dialog.m\
	draw.m\
	freetype.m\
	imagefile.m\
	keyring.m\
	lock.m\
	math.m\
	readdir.m\
	security.m\
	selectfile.m\
	string.m\
	sys.m\
	timers.m\
	tk.m\
	tkclient.m\
	winplace.m\
	wmclient.m\
	wmsrv.m\

DISBIN=$ROOT/dis/sfgui

<$ROOT/mkfiles/mkdis
LIMBOFLAGS = $LIMBOFLAGS 
<$ROOT/mkfiles/mksubdirs

mksfdirs:
	mkdir -p $DISBIN; cp -r images $DISBIN/
	mkdir -p $ROOT/usr/sunflower/keyring
	mkdir -p $ROOT/mnt/sunflower
	cp -r fonts/ttf2subf $ROOT/fonts/
	cp conf/keyring-default  $ROOT/usr/sunflower/keyring/default
	cp -r $SUNFLOWERROOT/sim $ROOT/libsunflower
	cp -r $SUNFLOWERROOT/sim/devsunflower.c $ROOT/emu/port
	chmod 444 $ROOT/emu/port/devsunflower.c
	chmod 444 $ROOT/libsunflower/*.[c,h,y]

nuke-std:V:     clean-std
        rm -rf $DISBIN; rm -rf $ROOT/usr/sunflower;
	rm -rf $ROOT/libsunflower
	rm -f $ROOT/emu/port/devsunflower.c

