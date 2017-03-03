implement Sokoban;

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
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "readdir.m";
	readdir: Readdir;
include "keyboard.m";
	Up, Down, Right, Left: import Keyboard;

# SokoMain:	con string "/lib/sokoban";
SokoMain:	con string ".";

# the two basic levels, overrideable

# the image sprites, constants
GlendaR: 		con SokoMain + "/images/right.bit";
GlendaL:		con SokoMain + "/images/left.bit";
IWall:		con SokoMain + "/images/wall.bit";
IEmpty:		con SokoMain + "/images/empty.bit";
ICargo:		con SokoMain + "/images/cargo.bit";
IGoalCargo:	con SokoMain + "/images/goalcargo.bit";
IGoal:		con SokoMain + "/images/goal.bit";
IWin:			con SokoMain + "/images/win.bit";

Boardx, Boardy: int;

# levels
Empty,
Background,
Wall,
Goal: con iota;

# the following can be combined with other elements.
# (Mark signifies the end of a move in the undo list and isn't
# found on the board itself).
Mark,
Cargo,
Glenda: con 16r10<<iota;	# can be combined with other elements

Norect: con Rect((16r7fffffff, 16r7fffffff), (-16r7fffffff, -16r7fffffff));

Level:	adt {
	n:		int;
	glenda:	Point;
	size:		Point;
	done:	int;
	board:	array of array of int;
	moves:	int;
	undos:	list of (Point, int);
	redos:	list of (Point, int);
	dirty:	Rect;

	new:		fn(board: array of array of int, size: Point): ref Level;
	move:	fn(l: self ref Level, vec: Point): int;
	copy:	fn(l: self ref Level): ref Level;
	set: 		fn(l: self ref Level, p: Point, v: int);
	get:		fn(l: self ref Level, p: Point): int;
	undo:	fn(l: self ref Level);
	redo:	fn(l: self ref Level);
	finished:	fn(l: self ref Level): int;
};

levelname: string;
levels:	array of ref Level;
currlevel: ref Level;

img, goal, cargo, goalcargo, wall, empty, gleft, gright, glenda, bg, text, winimg: ref Image;

ptrchan: chan of Pointer;
clickch, cmdch: chan of string;
win: ref Tk->Toplevel;

Sokoban: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

sokocmd := array[] of {
	"frame .f",
	"button .f.left -bitmap small_color_left.bit -bd 0 -command {send cmd left}",
	"button .f.right -bitmap small_color_right.bit -bd 0 -command {send cmd right}",
	"button .f.restart -bitmap sadsmiley.bit -bd 0 -command {send cmd restart}",
	"choicebutton .f.levelset -command {send cmd newlevelset}",
	"choicebutton .f.level -command {send cmd newlevel}",
	"label .f.l -text {level: }",
	"label .f.m -text {moves: 0}",
	"pack .f.left .f.right .f.levelset -side left",
	"pack .f.l -side left",
	"pack .f.level -side left",
	"pack .f.restart -side right",
	"pack .f.m -side right",
	"pack .f -fill x",
	"panel .p",
	"bind .p <ButtonRelease-1> {send click %x %y}",
	"bind .p <ButtonRelease-3> {send cmd undo}",
	"pack .p",
	"focus .p",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	bufio = load Bufio Bufio->PATH;
	readdir = load Readdir Readdir->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();
	if (ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "sokoban: no window context\n");
		raise "fail:bad context";
	}

	display = ctxt.display;	# assume always works
	
	sys->pctl(Sys->NEWPGRP, nil);
	ctlchan: chan of string;
	(win, ctlchan) = tkclient->toplevel(ctxt, nil, "Sokoban", Tkclient->Hide);

	cmdch = chan of string;
	tk->namechan(win, cmdch, "cmd");
	clickch = chan of string;
	tk->namechan(win, clickch, "click");
	for (i := 0; i < len sokocmd; i++)
		cmd(win, sokocmd[i]);

	levs := levelsets();
	if(levs == nil){
		sys->print("sokoban: no levels found\n");
		exit;
	}
	s := "";
	for(; levs != nil; levs = tl levs)
		s += hd levs + " ";
	cmd(win, ".f.levelset configure -values {"+s+"}");
	levelname = cmd(win, ".f.levelset getvalue");
	loadlevels(SokoMain+"/levels/"+levelname+ ".slc");

	s = "";
	for(i = 1; i <= len levels; i++)
		s += string i + " ";
	cmd(win, ".f.level configure -values {"+s+"}");

	tkclient->startinput(win, "kbd"::"ptr"::nil);
	tkclient->onscreen(win, nil);

	loadimages();

	currlevel = levels[0].copy();

	drawlevel(currlevel);

	spawn winctl(ctlchan);
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
	for(;;){
		redraw := 0;
		alt{
		ls := <-win.ctxt.ptr => 
			tk->pointer(win, *ls);
		ls := <-win.ctxt.kbd => 
			processkbd(ls);
			redraw = 1;
		ls := <-win.ctxt.ctl or
		ls = <-win.wreq or
		ls = <-ctlchan =>
			tkclient->wmctl(win, ls);
		c := <-cmdch =>
			case c {
			"left" =>
				processkbd('p');
			"right" =>
				processkbd('n');
			"restart" =>
				processkbd('R');
			"undo" =>
				processkbd('u');
			"newlevelset" =>
				s := cmd(win, ".f.levelset getvalue");
				if(s != levelname){
					loadlevels(SokoMain+"/levels/"+s+".slc");
					currlevel = levels[0].copy();
					redraw = 1;
					levelname = s;
					s = "";
					for(i := 1; i <= len levels; i++)
						s += string i + " ";
					cmd(win, ".f.level configure -values {"+s+"}");
				}
			"newlevel" =>
				s := cmd(win, ".f.level getvalue");
				currlevel = levels[int s - 1].copy();
			}
			redraw = 1;
		c := <-clickch =>
			(nil, toks) := sys->tokenize(c, " ");
			p := Point(int hd toks, int hd tl toks);
			p.x /= Boardx;
			p.y /= Boardy;
			if(p.x != currlevel.glenda.x && p.y != currlevel.glenda.y)
				break;
			vec := p.sub(currlevel.glenda);
			(vec.x, vec.y) = (sgn(vec.x), sgn(vec.y));
			while(!currlevel.glenda.eq(p) && currlevel.move(vec))
				;
			if(vec.x != 0){
				if(vec.x > 0)
					glenda = gright;
				else
					glenda = gleft;
			}
			redraw = 1;
		}
		if(redraw){
			if(currlevel.finished()) 
				currlevel.done = 1;
			drawlevel(currlevel);
			if(currlevel.done){
				sys->sleep(300);
				processkbd('n');
				drawlevel(currlevel);
			}
		}
	}
}

processkbd(kbd: int)
{
	case kbd {
	'q' or
	'Q' =>
		exit;
	'r' =>
		currlevel.redo();
	'u' =>
		currlevel.undo();
	'R' =>
		currlevel = levels[currlevel.n].copy();
	'p' or
	'P' =>
		if(currlevel.n > 0)
			currlevel = levels[currlevel.n - 1].copy();
	'n' or
	'N' =>
		if(currlevel.n < len levels - 1)
			currlevel = levels[++currlevel.n].copy();
	Up =>
		currlevel.move((0, -1));
	Down =>
		currlevel.move((0, 1));
	Left =>
		currlevel.move((-1, 0));
		glenda = gleft;
	Right =>
		currlevel.move((1, 0));
		glenda = gright;
	}
}

levelsets(): list of string
{
	(a, nil) := readdir->init(SokoMain+"/levels", Readdir->NAME|Readdir->COMPACT|Readdir->DESCENDING);
	levs: list of string;
	for(i := 0; i < len a; i++){
		s := a[i].name;
		if(len s > 4 && s[len s-4:] == ".slc")
			levs = s[0:len s - 4] :: levs;
	}
	return levs;
}

drawlevel(l: ref Level)
{
	cmd(win, ".f.m configure -text 'moves: " + string l.moves);
	cmd(win, ".f.l configure -text 'level: ");
	cmd(win, ".f.level  set " + string l.n);
	sizex := l.size.x * Boardx;
	sizey := l.size.y * Boardy;
	if(img == nil || img.r.dx() != sizex || img.r.dy() != sizey) {
		img = display.newimage(Rect((0, 0), (sizex, sizey)), display.image.chans, 0, Draw->Darkyellow);
		if(img == nil)
			sys->fprint(sys->fildes(2), "no image memory (img): %r\n");
		tk->putimage(win, ".p", img, nil);

		cmd(win, ".p configure -width " + string sizex + " -height " + string sizey);
	}
	dirty := l.dirty;
	for(y := dirty.min.y; y < dirty.max.y; y++) 
		for(x := dirty.min.x; x < dirty.max.x; x++) 
			drawboard(l.board[x][y], (x, y), l.done);
	
	cmd(win, ".p dirty "+r2s((l.dirty.min.mul(Boardx), l.dirty.max.mul(Boardy))));
	cmd(win, "update");
	l.dirty = Norect;
}

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

drawboard(b: int, p: Point, done: int)
{
	p = (Boardx*p.x, Boardy*p.y);
	r := Rect(p, p.add((Boardx, Boardy)));

	case b {
	Background =>
		img.draw(r, bg, nil, img.r.min);
	Empty =>
		img.draw(r, empty, nil, img.r.min);
	Wall =>
		img.draw(r, wall, nil, img.r.min);
	Cargo|Empty =>
		img.draw(r, cargo, nil, img.r.min);
	Goal =>
		img.draw(r, goal, nil, img.r.min);
	Glenda|Empty or
	Glenda|Goal =>
		if(done){
			img.draw(r, empty, nil, img.r.min);
			img.draw(r, text, winimg, img.r.min);
		}else
			img.draw(r, glenda, nil, img.r.min);
	Cargo|Goal =>
		img.draw(r, goalcargo, nil, img.r.min);
	}
}

loadlevels(file: string)
{
	x := 0;
	y := 0;
	
	buf := bufio->open(file, Bufio->OREAD);
	if(buf == nil) {
		sys->fprint(sys->fildes(2), "cannot load %s: %r", file);
		exit;
	}

	max := Point(0, 0);
	board := array[20] of {* => array[20] of {* => 0}};
	pglenda := Point(0, 0);
	levs: list of ref Level;

	lcurr := 0;
	while((c := buf.getc()) >= 0) {
		case c {
		';' =>
			while((c = buf.getc()) != '\n' && c != Bufio->EOF)
				;
		'\n' =>
			max.y = ++y;

			x = 0;
			if(buf.getc() == '\n') {
				levs = Level.new(board, max) :: levs;
				(hd levs).glenda = pglenda;
				(hd levs).n = lcurr++;
				board = array[20] of {* => array[20] of {* => 0}};
				max = (0, 0);
				y = 0;
			} else
				buf.ungetc();
		'#' =>
			board[x][y] = Wall;
			x++;

		' ' =>
			board[x][y] = Empty;
			x++;

		'$' =>
			board[x][y] = Cargo|Empty;
			x++;

		'*' =>
			board[x][y] = Cargo|Goal;
			x++;

		'.' =>
			board[x][y] = Goal;
			x++;

		'@' =>
			board[x][y] = Glenda|Empty;
			pglenda = Point(x, y);
			x++;

		'+' =>
			board[x][y] = Glenda|Goal;
			pglenda = Point(x, y);
			x++;

		* =>
			sys->fprint(sys->fildes(2), "impossible character for level %d: %c\n", lcurr+1, c);
			exit;
		}
		if(x > max.x)
			max.x = x;
	}
	levels = array[len levs] of ref Level;
	for(i := len levels - 1; i >= 0; i--)
		(levels[i], levs) = (hd levs, tl levs);
}

loadimages()
{
	goal = ereadimg(IGoal);
	cargo = ereadimg(ICargo);
	goalcargo = ereadimg(IGoalCargo);
	wall = ereadimg(IWall);
	empty = ereadimg(IEmpty);
	gleft = ereadimg(GlendaL);
	gright = ereadimg(GlendaR);
	glenda = gright;
	winimg = ereadimg(IWin);
	Boardx = empty.r.dx();
	Boardy = empty.r.dy();
	bg = display.color(Draw->Darkyellow);
	text = display.color(Draw->Bluegreen);
}

blanklevel: Level;
Level.new(board: array of array of int, size: Point): ref Level
{
	l := ref blanklevel;
	l.board = array[size.x] of {* => array[size.y] of int};
	l.size = size;
	for(i := 0; i < size.x; i++)
		l.board[i][0:] = board[i][0:size.y];
	l.dirty = ((0, 0), size);
	return l;
}

Level.copy(l: self ref Level): ref Level
{
	c := ref *l;
	c.board = array[l.size.x] of {* => array[l.size.y] of int};

	for(i := 0; i < l.size.x; i++)
		c.board[i][0:] = l.board[i];

	l.dirty = ((0, 0), l.size);
	return c;
}

# glenda moves in the direction of unit-vector vec.
Level.move(l: self ref Level, vec: Point): int
{
	if(l.done)
		return 0;
	g := l.glenda;
	moved := 0;

	p1 := g.add(vec);
	p2 := g.add(vec.mul(2));

	case b1 := l.get(p1) {
	Empty or
	Goal =>
		moved = 1;
		l.set(p1, b1|Glenda|Mark);
	Empty|Cargo or
	Goal|Cargo =>
		b2 := l.get(p2);
		if(b2 == Empty || b2 == Goal){
			l.set(p1, b1 & ~Cargo | Glenda | Mark);
			l.set(p2, b2 | Cargo);
			moved = 1;
		}
	}
	if(moved){
		l.set(g, l.get(g) & ~Glenda);
		l.glenda = p1;
		l.moves++;
	}
	return moved;
}

Level.set(l: self ref Level, p: Point, v: int)
{
	l.undos = (p, l.board[p.x][p.y] | (v & Mark)) :: l.undos;
	l.redos = nil;
	l.board[p.x][p.y] = v & ~Mark;
	l.dirty = l.dirty.combine(((p.x, p.y), (p.x+1, p.y+1)));
}

applychange(a, b: list of (Point, int), l: ref Level): (int, list of (Point, int), list of (Point, int))
{
	if(a == nil)
		return (0, a, b);
	firstmark := Mark;
	for(;;){
		(p, v) := hd a;
		b = (p, l.board[p.x][p.y] | firstmark) :: b;
		l.board[p.x][p.y] = v & ~Mark;
		l.dirty = l.dirty.combine(((p.x, p.y), (p.x+1, p.y+1)));
		if(v & Glenda)
			l.glenda = p;
		firstmark = 0;
		a = tl a;
		if(v & Mark)
			break;
	}
	return (1, a, b);
}

Level.undo(l: self ref Level)
{
	moved: int;
	(moved, l.undos, l.redos) = applychange(l.undos, l.redos, l);
	if(moved)
		l.moves--;
}

Level.redo(l: self ref Level)
{
	moved: int;
	(moved, l.redos, l.undos) = applychange(l.redos, l.undos, l);
	if(moved)
		l.moves++;
}

Level.get(l: self ref Level, p: Point): int
{
	return l.board[p.x][p.y];
}

Level.finished(c: self ref Level): int
{
	for(x := 0; x < len c.board; x++)
		for(y := 0; y < len c.board[0]; y++)
			if((c.board[x][y] & ~Glenda) == Goal)
				return 0;

	return 1;
}

ereadimg(path: string): ref Image
{
	i := display.open(path);
	if(i == nil) {
		sys->fprint(sys->fildes(2), "cannot load image: %s: %r", path);
		exit;
	}
	return i;
}

sgn(x: int): int
{
	if(x == 0)
		return 0;
	if(x > 0)
		return 1;
	return -1;
}
