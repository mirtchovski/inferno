implement Zoom;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Font, Rect, Point, Image, Screen: import draw;
	display: ref Display;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "rand.m";
	rand: Rand;
include "daytime.m";
	daytime: Daytime;
include "math.m";
	math: Math;

win: ref Tk->Toplevel;
disp, screen, color, src: ref Image;

brdr: Rect;
lenses: int;


Zoom: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();

	tk = load Tk Tk->PATH;
	daytime = load Daytime Daytime->PATH;
	rand = load Rand Rand->PATH;
	rand->init(daytime->now());

	math = load Math Math->PATH;

	display = ctxt.display;	# assume always works
	disp = display.image;
	
	brdr = Rect((0,0), (600, 600));
	
	src = display.newimage(disp.r, display.image.chans, 0, Draw->Red);
	if(src == nil)
		sys->fprint(sys->fildes(2), "no image memory (src): %r\n");
	src.draw(src.r, disp, nil, disp.r.min);


	sys->pctl(Sys->NEWPGRP, nil);
	ctlchan: chan of string;
	(win, ctlchan) = tkclient->toplevel(ctxt, nil, "Zoom", Tkclient->Hide);

	cmd(win, "panel .c -bd 2 -relief ridge");
	cmd(win, "pack .c");
	cmd(win, "focus .c");

	cmd(win, ".c configure -width " + string (brdr.dx()) + " -height " + string (brdr.dy()));

	tkclient->startinput(win, "kbd"::"ptr"::nil);
	tkclient->onscreen(win, nil);

	zoominit();

	spawn winctl(ctlchan);
	spawn zoom();
}

cmd(win: ref Tk->Toplevel, s: string): string
{
	r := tk->cmd(win, s);
	if(len r > 0 && r[0] == '!'){
		sys->print("error executing '%s': %s\n", s, r[1:]);
	}
	return r;
}

winctl(ctlchan: chan of string)
{
	for(;;) alt {
		ls := <-win.ctxt.ptr =>
			tk->pointer(win, *ls);
		ls := <-win.ctxt.ctl or
		ls = <-win.wreq or
		ls = <-ctlchan =>
			tkclient->wmctl(win, ls);
	}
}

flush()
{
	tmp: string;

	tmp = sys->sprint("%d %d %d %d", 
				brdr.min.x,
				brdr.min.y,
				brdr.max.x,
				brdr.max.y);

	cmd(win, ".c dirty "+ tmp);
	cmd(win, "update");
}


X_PERIOD: con 45000.0;
Y_PERIOD: con 36000.0;
PI: con 3.141592;
tlx, tly, s: int;
sizex, sizey: int;
pixwidth, pixheight, pixspacex, pixspacey, lensoffsetx, lensoffsety: int;
delay: int;

zoominit()
{
	nblocksx, nblocksy: int;

	lenses = rand->rand(2);

	sizex = disp.r.dx();
	sizey = disp.r.dy();

	delay = 10;
	pixheight = pixwidth = 10;
	pixspacex = 2;
	pixspacey = 2;
	lensoffsetx = 5;
	lensoffsety = lensoffsetx;

	nblocksx = int math->ceil(real (sizex / (pixwidth + pixspacex)));
	nblocksy = int math->ceil(real (sizey / (pixheight + pixspacey)));
	if (lenses) {
		if((nblocksx - 1) * lensoffsetx + pixwidth > 
		    (nblocksy - 1) * lensoffsety + pixheight)
			s = 2* ((nblocksx - 1) * lensoffsetx + pixwidth);
		else 
			s = 2*((nblocksy - 1) * lensoffsety + pixheight);
	} else {
		if(nblocksx > nblocksy) 
			s = nblocksx* 2;
		else 
			s = nblocksy*2;
	}
	screen = display.newimage(brdr, display.image.chans, 0, Draw->Red);
	if(screen == nil)
		sys->fprint(sys->fildes(2), "no image memory (screen): %r\n");
	color = display.newimage(Rect((0, 0), (1, 1)), display.image.chans, 1, Draw->Red);
	if(color == nil)
		sys->fprint(sys->fildes(2), "no image memory (color): %r\n");
	tk->putimage(win, ".c", screen, nil);

	screen.draw(screen.r, display.black, nil, disp.r.min);
}


zoom()
{

	x, y, i, j: int;

	p2: Point;
	r: Rect;
	now: real;

	for(;;) {
		now = real sys->millisec();
	
		# find new x,y
		tlx = int ((((1.0 + math->sin(now / X_PERIOD * 2.0 * PI)))/2.0) * (real sizex - real s/2.0));
		tly = int ((((1.0 + math->sin(now / Y_PERIOD * 2.0 * PI)))/2.0) * (real sizey - real s/2.0));

		if (lenses) {
			for (x = i = 0; x < sizex; x += (pixwidth + pixspacex)) {
				for (y = j = 0; y < sizey; y += (pixheight + pixspacey)) {
					r = Rect((x, y), (x+pixwidth, y+pixheight));
					p2 = Point(tlx + i * lensoffsetx, tly + j * lensoffsety);
					screen.draw(r, src, nil, p2);	
					j++;
				}
				i++;
			}
		} else {
			for (x = i = 0; x < sizex; x += (pixwidth + pixspacex)) {
				for (y = j = 0; y < sizey; y += (pixheight + pixspacey)) {
					r = Rect((i * (pixwidth + pixspacex),
					    	j * (pixheight + pixspacey)), 
						(i * (pixwidth + pixspacex)+pixwidth, 
						j * (pixheight + pixspacey)+pixheight));
					color.draw(color.r, src, nil, Point(tlx+i, tly+j));
					screen.draw(r, color, nil, color.r.min);
					j++;
				}
				i++;
			}
		}
		flush();
		sys->sleep(10);
	}

}