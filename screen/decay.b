implement Decayscreen;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Rect, Point, Image: import draw;
	display: ref Display;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "rand.m";
	rand: Rand;
include "daytime.m";
	daytime: Daytime;

win: ref Tk->Toplevel;
disp, screen, color, src: ref Image;

brdr: Rect;

mode, iterations, toggle, frames: int;
Cycles: con 50000;


Decayscreen: module
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

	display = ctxt.display;	# assume always works
	disp = display.image;
	
	brdr = disp.r;
	
	src = display.newimage(disp.r, display.image.chans, 0, Draw->Nofill);
	if(src == nil)
		sys->fprint(sys->fildes(2), "no image memory (src): %r\n");
	src.draw(src.r, disp, nil, disp.r.min);

	screen = display.newimage(brdr, display.image.chans, 0, Draw->Nofill);
	if(screen == nil)
		sys->fprint(sys->fildes(2), "no image memory (screen): %r\n");
	screen.draw(screen.r, src, nil, src.r.min);

	sys->pctl(Sys->NEWPGRP, nil);
	ctlchan: chan of string;
	(win, ctlchan) = tkclient->toplevel(ctxt, nil, "Decayscreen", Tkclient->Hide);

	cmd(win, "panel .c -bd 2 -relief ridge");
	cmd(win, "pack .c");
	cmd(win, "focus .c");

	cmd(win, ".c configure -width " + string (brdr.dx()) + " -height " + string (brdr.dy()));
	tkclient->startinput(win, "kbd"::"ptr"::nil);
	tkclient->onscreen(win, nil);


	tk->putimage(win, ".c", screen, nil);

	mode = rand->rand(Fuzz+1);

	if(mode == Melt || mode == Stretch) {
		screen.line((0, 0), (brdr.dx(), 1), 
			Draw->Endsquare, Draw->Endsquare, 0, 
			display.black, screen.r.min);
		iterations =1;
	}

	spawn winctl(ctlchan);
	spawn decay();
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

decay() 
{
	for(;;) {
		decay1();
		flush();
		
		sys->sleep(10);

		if(frames-- < 0) {
			squeeze(src,screen); 
			frames = Cycles;
		}
	}
}


Shuffle: 		con 0;
Up: 			con 1;
Left: 			con 2;
Right: 		con 3;
Down: 		con 4;
Upleft: 		con 5;
Downleft: 		con 6;
Upright: 		con 7;
Downright: 	con 8;
In: 			con 9;
Out: 			con 10;
Melt: 		con 11;
Stretch: 		con 12;
Fuzz: 		con 13;

L: con 101;
R: con 102;
U: con 103;
D: con 104;

no_bias := array [] of { L,L,L,L, R,R,R,R, U,U,U,U, D,D,D,D };
up_bias := array [] of { L,L,L,L, R,R,R,R, U,U,U,U, U,U,D,D 	};
down_bias := array [] of { L,L,L,L, R,R,R,R, U,U,D,D, D,D,D,D 	};
left_bias := array [] of { L,L,L,L, L,L,R,R, U,U,U,U, D,D,D,D };
right_bias := array [] of { L,L,R,R, R,R,R,R, U,U,U,U, D,D,D,D };

upleft_bias := array [] of { L,L,L,L, L,R,R,R, U,U,U,U, U,D,D,D };
downleft_bias := array [] of { L,L,L,L, L,R,R,R, U,U,U,D, D,D,D,D };
upright_bias := array [] of { L,L,L,R, R,R,R,R, U,U,U,U, U,D,D,D };
downright_bias := array [] of { L,L,L,R, R,R,R,R, U,U,U,D, D,D,D,D};

decay1 ()
{
	left, top, width, height, toleft, totop: int;
	r: Rect; 
	p, p2: Point;
	bias: array of int;


	case mode{
	Shuffle or In or Out or Melt or Stretch or Fuzz=>	
		bias = no_bias; 
	Up =>	
		bias = up_bias; 
	Left =>	
		bias = left_bias; 
	Right =>	
		bias = right_bias; 
	Down =>	
		bias = down_bias; 
	Upleft =>	
		bias = upleft_bias; 
	Downleft =>	
		bias = downleft_bias; 
	Upright =>
		bias = upright_bias; 
	Downright =>	
		bias = downright_bias; 
	}

	if (mode == Melt || mode == Stretch) {
		left = rand->rand(brdr.dx()/2);
		top = rand->rand(brdr.dy());
		width = rand->rand( brdr.dx()/2 ) + brdr.dx()/2 - left;
		height = rand->rand(brdr.dy() - top);
		toleft = left;
		totop = top+1;

	} else if (mode == Fuzz) {  
		toggle = 0;

		left = rand->rand(brdr.dx() - 1);
		top  = rand->rand(brdr.dy() - 1);
		toggle = !toggle;
		if (toggle) {
			totop = top;
			height = 1;
			toleft = rand->rand(brdr.dx() - 1);
			if (toleft > left) {
				width = toleft-left;
				toleft = left;
				left++;
			} else {
				width = left-toleft;
				left = toleft;
				toleft++;
			}
		} else {
			toleft = left;
			width = 1;
			totop  = rand->rand(brdr.dy() - 1);
			if (totop > top) {
				height = totop-top;
				totop = top;
				top++;
			} else {
				height = top-totop;
				top = totop;
				totop++;
			}
		}
	} else {

		left = rand->rand(brdr.dx() - 1);
		top = rand->rand(brdr.dy());
		width = rand->rand(brdr.dx() - left);
		height = rand->rand(brdr.dy() - top);

		toleft = left;
		totop = top;
		if (mode == In || mode == Out) {
			x := left+(width/2);
			y := top+(height/2);
			cx: int = brdr.dx()/2;
			cy: int = brdr.dy()/2;
			if (mode == In) {
				if      (x > cx && y > cy)   bias = upleft_bias;
				else if (x < cx && y > cy)   bias = upright_bias;
				else if (x < cx && y < cy)   bias = downright_bias;
				else bias = downleft_bias;
			} else {
				if      (x > cx && y > cy)   bias = downright_bias;
				else if (x < cx && y > cy)   bias = downleft_bias;
				else if (x < cx && y < cy)   bias = upleft_bias;
				else bias = upright_bias;
			}
		}

		case (bias[rand->rand(len no_bias)]) {
			L =>
				toleft = left-1; 
			R =>
				toleft = left+1; 
			U =>
				totop = top-1; 
			D =>
				totop = top+1; 
		}
	}

	r = screen.r;
	if (mode == Stretch) {
		p = r.min.add(Point(0, brdr.dy()-top-1));
		p2 = r.min.add(Point(0, brdr.dy()-top-2));
		r = Rect(p, p.add(Point(brdr.dx(), top+1)));
	} else {
		p = r.min.add(Point(toleft, totop));
		p2 = r.min.add(Point(left, top));
		r = Rect(p, p.add(Point(width, height)));
	}

	screen.draw(r, screen, nil, p2);
}