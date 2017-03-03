# rotzoomer, original in XScreensaver
# original © 2001 Claudio Matsuoka
#
# rewritten in Limbo by Andrey Mirtchovski


implement Rotzoom;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Font, Rect, Point, Image: import draw;
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

Zoom: adt {
	w, h: 	int;
	inc1, inc2:	int;
	dx, dy: 	int;
	a1, a2:	int;
	ox, oy:	int;
	xx, yy:	int;
	x, y:		int;
	ww, hh:	int;
	n, count:	int;
};

width, height:	int;
zoom_box := array[2] of ref Zoom;
num_zoom := 2;
move := 0;
sweep := 0;
delay := 0;
anim := 1;

win: ref Tk->Toplevel;
disp, screen, color, src: ref Image;

brdr: Rect;
lenses: int;


Rotzoom: module
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
	
	brdr = Rect((0,0), (disp.r.dx(), disp.r.dy()));
	
	src = display.newimage(brdr, display.image.chans, 0, Draw->Red);
	if(src == nil)
		sys->fprint(sys->fildes(2), "no image memory (src): %r\n");
	#squeeze(disp, src);
	src.draw(src.r, disp, nil, disp.r.min);


	sys->pctl(Sys->NEWPGRP, nil);
	ctlchan: chan of string;
	(win, ctlchan) = tkclient->toplevel(ctxt, nil, "Rotzoom", Tkclient->Hide);

	cmd(win, "panel .c -bd 2 -relief ridge");
	cmd(win, "pack .c");
	cmd(win, "focus .c");

	cmd(win, ".c configure -width " + string (brdr.dx()) + " -height " + string (brdr.dy()));

	tkclient->startinput(win, "kbd"::"ptr"::nil);
	tkclient->onscreen(win, nil);

	zinit();

	spawn winctl(ctlchan);
	spawn zmain();
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


zinit()
{

	screen = display.newimage(brdr, display.image.chans, 0, Draw->Nofill);
	if(screen == nil)
		sys->fprint(sys->fildes(2), "no image memory (screen): %r\n");
	color = display.newimage(Rect((0, 0), (1, 1)), display.image.chans, 1, Draw->Red);
	if(color == nil)
		sys->fprint(sys->fildes(2), "no image memory (color): %r\n");
	tk->putimage(win, ".c", screen, nil);

	screen.draw(screen.r, src, nil, src.r.min);

	sweep = rand->rand(2);

	if (sweep || !anim)
		num_zoom = 1;

	if (!anim)
		sweep = 0;

	width = brdr.dx();
	height = brdr.dy();

	if (width & 1)
		width--;
	if (height & 1)
		height--;

	for(i := 0; i < num_zoom; i++) {
		zoom_box[i] = reset_zoom();

	}

	flush();
}


zmain()
{
	i: int;

	for(;;) {
		for(i = 0; i < num_zoom; i++) {
			if(move || sweep)
				update_position(zoom_box[i]);
			if(zoom_box[i].n > 0) {
				if(anim || zoom_box[i].count == 0)
					rotzoom(zoom_box[i]);
				zoom_box[i].n--;
			} else 
				zoom_box[i] = reset_zoom();
		}
		flush();
		sys->sleep(10);
	}
}

rotzoom(za: ref Zoom)
{
	r: Rect;

	x, y, c, s, zoom, z: int;
	x2 := za.x + za.w - 1;
	y2 := za.y + za.h - 1;
	ox := 0;
	oy := 0;
	ys, yc: int;

	z = int (8100.0 * math->sin(math->Pi * (real za.a2) / 8192.0));
	zoom = 8192 + z;

	c = int (real zoom * math->cos(math->Pi * (real za.a1) / 8192.0));
	s = int (real zoom * math->sin(math->Pi * (real za.a1) / 8192.0));
	ys = za.y * s;
	yc = za.y * c;
	for (y = za.y; y <= y2; y+=2) {
		oxbig :=  za.x*c + ys;
		oybig := -za.x*s + yc;

		ys += s;
		yc += c;
		for (x = za.x; x <= x2; x+=2) {
			ox = oxbig >> 13;
			if (ox < 0)
				do 
				{
					ox += width;
				} while (ox < 0);
			else
				while (ox >= width)
				ox -= width;
			oxbig += c;

			oy = oybig >> 13;
			if (oy < 0)
				do {
					oy += height;
				} while (oy < 0);
			else
				while (oy >= height)
					oy -= height;
			oybig -= s;
			r = Rect((x, y), (x+2, y+2));
			screen.draw(r, src, nil, Point(ox, oy));
		}
	}
	za.a1 += za.inc1;	
	za.a1 &= 16r3fff;

	za.a2 += za.inc2;	
	za.a2 &= 16r3fff;

	za.ox = ox;		
	za.oy = oy;

	za.count++;
	
}

reset_zoom(): ref Zoom
{
	za: Zoom;
	if (sweep) {
		speed := rand->rand(100) + 100;

		case rand->rand(4) {
		0 =>
			za.w = width;
			za.h = 10;
			za.x = za.y = za.dx = 0;
			za.dy = speed;
			za.n = height - 10;
		1 =>
			za.w = 10;
			za.h = height;
			za.x = width - 10;
			za.y = 0;
			za.dx = -speed;
			za.dy = 0;
			za.n = width - 10;

		2 =>
			za.w = width;
			za.h = 10;
			za.x = 0;
			za.y = height - 10;
			za.dx = 0;
			za.dy = -speed;
			za.n = height - 10;
			break;
		3 =>
			za.w = 10;
			za.h = height;
			za.x = 0;
			za.y = 0;
			za.dx = speed;
			za.dy = 0;
			za.n = width - 10;
			break;
		}
		za.n = (za.n * 256) / speed;
		za.ww = width - za.w;
		za.hh = height - za.h;

		za.a1 = za.a2 = 0;
		za.inc1 = (2*(rand->rand(2)) - 1) * (1 + rand->rand(7));
		za.inc2 = (2*(rand->rand(2)) - 1) * (1 + rand->rand(7));
	} else {
		za.w = 50 + rand->rand(300);
		za.h = 50 + rand->rand(300);

		if (za.w > width / 3)
			za.w = width / 3;
		if (za.h > height / 3)
			za.h = height / 3;

		za.ww = width - za.w;
		za.hh = height - za.h;

		za.x = rand->rand(za.ww);
		za.y = rand->rand(za.hh);

		za.dx = (2*(rand->rand(2)) - 1) * (100 + rand->rand(300));
		za.dy = (2*(rand->rand(2)) - 1) * (100 + rand->rand(300));

		if (anim) {
			za.n = 50 + rand->rand(1000);
			za.a1 = za.a2 = 0;
		}
		else {
			za.n = 5 + rand->rand(10);
			za.a1 = rand->rand(360);
			za.a2 = rand->rand(360);
		}
		za.inc1 = (2*(rand->rand(2)) - 1) * (rand->rand(30));
		za.inc2 = (2*(rand->rand(2)) - 1) * (rand->rand(30));
	}
	za.xx = za.x * 256;
	za.yy = za.y * 256;

	za.count = 0;
	
	return ref za;
}

update_position(za: ref Zoom)
{
	za.xx += za.dx;
	za.yy += za.dy;

	za.x = za.xx >> 8;
	za.y = za.yy >> 8;

	if (za.x < 0) {
		za.x = 0;
		za.dx = 100 + rand->rand(100);
	}

	if (za.y < 0) {
		za.y = 0;
		za.dy = 100 + rand->rand(100);
	}

	if (za.x > za.ww) {
		za.x = za.ww;
		za.dx = -(100 + rand->rand(100));
	}

	if (za.y > za.hh) {
		za.y = za.hh;
		za.dy = -(100 + rand->rand(100));
	}
	
}

squeeze(f: ref Image, t: ref Image)
{
	x, y, xx, yy: int;
	dx, dy: real;
	r: Rect;

	dx = (real f.r.dx())/(real t.r.dx());
	dy = (real f.r.dy())/(real t.r.dy());

	for(y=0; y<t.r.dy(); y++){
		for(x=0; x<t.r.dx(); x++){
			yy = (int  dy*y);
			xx = (int dx*x);

			r = Rect((x, y), (x+1, y+1));	
			t.draw(r, f, nil, Point(xx, yy));
		}
	}
}
