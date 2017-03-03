implement Lens;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Font, Rect, Point, Image, Screen, Pointer: import draw;
	display: ref Display;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;

# related to Tk
win: ref Tk->Toplevel;

# related to us
disp, screen, color, cheq: ref Image;

brdr: Rect;
ptrchan: chan of Pointer;

zoom: int; 	# zoom level, ∈ [1,16]
grid: int;		# show grid


Lens: module
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

	display = ctxt.display;	# assume always works
	disp = display.image;
	
	brdr = Rect((0,0), (400, 400));
	
	sys->pctl(Sys->NEWPGRP, nil);
	ctlchan: chan of string;
	(win, ctlchan) = tkclient->toplevel(ctxt, nil, "Lens", Tkclient->Hide);

	cmd(win, "panel .c ");
	cmd(win, "pack .c");
	cmd(win, "focus .c");

	cmd(win, ".c configure -width " + string (brdr.dx()) + " -height " + string (brdr.dy()));

	tkclient->startinput(win, "kbd"::"ptr"::nil);
	tkclient->onscreen(win, nil);

	screen = display.newimage(brdr, display.image.chans, 0, Draw->White);
	if(screen == nil)
		sys->fprint(sys->fildes(2), "no image memory (screen): %r\n");
	tk->putimage(win, ".c", screen, nil);
	cmd(win, "pack propagate . 0");

	color = display.newimage(Rect((0, 0), (1, 1)), display.image.chans, 1, Draw->Red);
	if(color == nil)
		sys->fprint(sys->fildes(2), "no image memory (color): %r\n");
	
	# chequered image for drawing the grid
	cheq = display.newimage(Rect((0, 0), (2, 2)), Draw->GREY1, 1, Draw->Black);
	if(cheq == nil)
		sys->fprint(sys->fildes(2), "no image memory (cheq): %r\n");
	cheq.draw(Rect((0, 0), (1, 1)), display.white, nil, cheq.r.min);
	cheq.draw(Rect((1, 1), (2, 2)), display.white, nil, cheq.r.min);

	ptrchan = chan of Pointer;
	zoom = 4;

	spawn winctl(ctlchan);
	spawn lens();
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
	ptr: Pointer; 	# remember where the mouse is
	for(;;) alt {
		ls := <-win.ctxt.ptr => 
			ptrchan <-= ptr = *ls;
			tk->pointer(win, *ls);
		ls := <-win.ctxt.kbd => 
			processkbd(ls);
			# update screen
			ptrchan <-= ptr;
		ls := <-win.ctxt.ctl or
		ls = <-win.wreq or
		ls = <-ctlchan =>
			tkclient->wmctl(win, ls);
	}
}

processkbd(kbd: int)
{
	case kbd {
		'1' or '2' or '3' or '4' or '5' or '6' or '7' or '8' or '9' => zoom = kbd-16r30;
		'0' => zoom = 10;
		'+' => 
			if(++zoom > 16)
				zoom = 16;
		'-' => if(--zoom < 1)
				zoom = 1;
		'g' => grid = !grid;
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

drawgrid()
{
	z := zoom;
	if (z < 5)
		z *= 10;
	
	gridimg := display.newimage(Rect((0, 0), (z, z)), 
			# this concoction is the expanded version of
			# CHAN2(CGrey, 8, CAlpha, 8) from Plan9's lens.c
			# it takes care of the transparent dots on the grid
			Draw->Chans((((Draw->CGrey)<<4)|8)<<8|(((Draw->CAlpha)<<4)|8)),
			1, Draw->Transparent);
	if(gridimg != nil) {
		gridimg.draw(Rect((0, 0), (z, 1)), cheq, nil, gridimg.r.min);
		gridimg.draw(Rect((0, 1), (1, z)), cheq, nil, gridimg.r.min);

		# draw one more to avoid artifacts
		screen.draw(Rect(screen.r.min, screen.r.max.add(Point(z,z))), 
				gridimg, nil, screen.r.min);
	}
}

lens()
{
	p, off: Point;
	r: Rect;
	ptr: Pointer;
	x, y, i, j: int;

	for(;;) {
		ptr = <- ptrchan;

		off = brdr.size().div(2*zoom);

		p = ptr.xy;
		if(p.x < disp.r.min.x + off.x)
			p.x = disp.r.min.x + off.x;
		if(p.x > disp.r.max.x - off.x)
			p.x = disp.r.max.x - off.x;
		if(p.y < disp.r.min.y + off.y)
			p.y = disp.r.min.y + off.y;
		if(p.y > disp.r.max.y - off.y)
			p.y = disp.r.max.y - off.y;

		# zoom == 1 is a special case, optimize
		if(zoom == 1) {
			screen.draw(screen.r, disp, nil, p.sub(off));
		} else {
			# we draw extra rectangles so no artifacts are left
			# on resize
			i = 0;
			for (x = p.x-(off.x+1); x <= p.x+off.x; x++) {
				j = 0;
				for (y = p.y-(off.y+1); y <= p.y+off.y; y ++) {
					r = Rect((i, j), (i+zoom, j+zoom));

					color.draw(color.r, disp, nil, Point(x, y));
					screen.draw(r, color, nil, color.r.min);
					j+=zoom;
				}
				i+=zoom;
			}
		}
		if(grid)
			drawgrid();
		flush();
	}
}