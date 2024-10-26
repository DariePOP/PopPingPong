#!/usr/bin/instantfpc -B -FlSDL2 -FuSDL2
PROGRAM PopPingPong;
{
  //TODO
  °) test players (same line, inequal teams etc.)
  °) test geometries (different W & H)
  °) closed levels (breakout style)
  °) networking (LAN server/client, create & join game)
  °) webassembly
  //STRUCT
  Global Deps
    procedure Quit;
    procedure keyAdd(key: byte);
    procedure keyDel(key: byte);
    function sdlPressed: boolean;
  Eye Candy
    procedure Wallpaper;
    procedure FlipTextIni(len: integer);
    procedure FlipTextAdd(color: integer; text: string);
    procedure FlipTextAt(x, y: integer);
    procedure Fireworks(x1, y1, x2, y2: integer);
  Game Deps
    function NewIdent: word;
    function GetBallIX(id: word): integer;
    function GetPadIX(id: char): integer;
  Game Init
    procedure InitLevel(lvl: char);
    procedure ResetPlayers;
    procedure LoadPlayers;
    procedure SetPlayers(const playerz: array of integer);
  Game Dynamics
    procedure GameOver;
    procedure PrintPoints;
    procedure RefreshStatus;
    //pad actions
    procedure PutPad(px: integer);
    procedure DelPad(px: integer);
    procedure MovePad(px, dir: integer);
    procedure ResizePad(px, len: integer);
    procedure FirePad(px: integer);
    //game actions
    procedure ResetGame;
    procedure NewGame(lvl: char);
    procedure PauseGame;
    //keypresses
    procedure ResetBalls;
    procedure HandleKeypress(key: char);
    //game play
    procedure HandleHit(bx: integer; chr: char);
    function HandleFire(fx: integer; chr: char): boolean;
    procedure UpdateGamestate;
}
USES
{$IFDEF UNIX}
  cthreads,
{$ENDIF}
  strutils,
  sysutils,
  crt, SDL2,
  pop;
TYPE
  TBall = record
    id: word;
    x, y: integer;
    dx, dy: integer;
    last_chr: char;
    last_tch: char;
  end;
  TPad = record
    id: char;
    x, y, z: integer;
    ini: array of char;
    pad: array of char;
    hasGlue: boolean;
    hasBall: boolean;
    hasBallID: word;
    hasFire: boolean;
    needsRefresh: boolean;
    isOut: boolean; //isDead, has been shot
    //
    points: integer;
    team: integer;
    bgr: string;
    chr: string;
    clr: string;
    inactive: boolean;
  end;
  TFire = record
    x, y: integer;
    dx: integer;
    oriPadID: char;
    last_chr: char;
  end;
CONST
  PLAYERS = '()[]{}';
  DIR_LT = -1;
  DIR_RT = +1;
  DIR_UP = -1;
  DIR_DN = +1;
  TEAM_N = -1;
  TEAM_P = +1;
  ELONG = +1;
  SHORT = -1;
VAR
  W, H, BGR, CLR: integer;
  DeltaWidth, DeltaHeight: integer;
  vDiff, hDiff, nhDiff: integer;

  BALL, FIRE: char;
  BALL_BGR, BALL_CHR, BALL_CLR: string;
  FIRE_BGR, FIRE_CHR, FIRE_CLR: string;

  detected: array of TPad;
  padz: array of TPad;
  ballz: array of TBall;
  firez: array of TFire;

  game_confort, game_speed: integer;
  set1, set2, scored: integer;
  current_level: char;
  mute, game_over, ball_over: boolean;

  flip_text_len: integer;
  flip_text_clr: array of integer;
  flip_text_str: array of string;

  delta_speed, DeltaSpeed: integer;

  superball: boolean;
  last_ident: word;

  win: PSDL_Window;
  evt: TSDL_Event;
  sdl: boolean = true;
  sdl_pressed: boolean;
  keys: string = '';
  que: integer;

{
  Global Deps
}

procedure Quit;
begin
  window(1, 1, WindMaxX, WindMaxY);
  textbackground(black);
  textcolor(white);
  SetCursor(true);
  clrscr;
  if sdl then sdl_destroyWindow(win);
  halt;
end;
procedure keyAdd(key: byte);
var chr: char;
begin
  if key = 27 then Quit;
  sdl_pressed := true;
  chr := char(key);
  if pos(chr, keys) = 0 then keys := keys + chr;
end;
procedure keyDel(key: byte);
var chr: char;
begin
  chr := char(key);
  keys := stringReplace(keys, chr, '', [rfReplaceAll]);
end;
function sdlPressed: boolean;
begin
  sdl_pressed := false;
  sdlPressed := sdl_pressed;
  if not sdl then exit;
  if not ( sdl_pollEvent(@evt) = 0 ) then case evt.type_ of
    SDL_KEYDOWN: keyAdd(evt.key.keysym.sym);
    SDL_KEYUP: keyDel(evt.key.keysym.sym);
  end;
  sdlPressed := sdl_pressed;
end;

{
  Eye Candy
}

procedure Wallpaper;
var
  x, y, i: integer;
begin
  for i := 1 to 10 *1000 +random(5000) do begin
    x := random(WindMaxX) +1;
    y := random(WindMaxY) +1;

    if ( x = WindMaxX ) and ( y = WindMaxY )
      then continue;

    if ( x > DeltaWidth -5 -1 ) and ( x < DeltaWidth+W +5 )
    and ( y > DeltaHeight -3 ) and ( y < DeltaHeight+H +5 )
      then continue;

    gotoxy(x,y);
    textbackground(random(6)+1);
    write(' ');

    if i mod 1000 = 0
      then tone(random(5000)+500, random(150)+50);

    if sdlpressed or keypressed then break;
  end;
  textbackground(BGR);
end;

procedure FlipTextIni(len: integer);
begin
  flip_text_len := len;
  setlength(flip_text_clr, 0);
  setlength(flip_text_str, 0);
end;
procedure FlipTextAdd(color: integer; text: string);
begin
  setlength(flip_text_clr, length(flip_text_clr) +1);
  setlength(flip_text_str, length(flip_text_str) +1);
  while length(text) < flip_text_len do text := text + ' ';
  setlength(text, flip_text_len); //trunk
  flip_text_clr[high(flip_text_clr)] := color;
  flip_text_str[high(flip_text_str)] := text;
end;
procedure FlipTextAt(x, y: integer);
var
  i, j: integer;
  flip_text_aux: array of string;
  done: boolean;
begin
  //init
  setlength(flip_text_aux, 0);
  setlength(flip_text_aux, length(flip_text_str));
  for i := low(flip_text_aux) to high(flip_text_aux) do begin
    flip_text_aux[i] := '';
    for j := 1 to length(flip_text_str[i]) do begin
      flip_text_aux[i] := flip_text_aux[i] + ' ';
    end;
  end;
  //do
  repeat
    done := true;
    //increment
    for i := low(flip_text_aux) to high(flip_text_aux) do begin //each line
      for j := 1 to length(flip_text_aux[i]) do begin //each char
        if not ( flip_text_aux[i][j] = flip_text_str[i][j] ) then begin
          flip_text_aux[i][j] := chr( byte(flip_text_aux[i][j]) +1 );
          done := false;
        end;
      end;
    end;
    //display
    for i := low(flip_text_aux) to high(flip_text_aux) do begin //by line
      textcolor(flip_text_clr[i]);
      gotoxy(x,y+i);
      write(flip_text_aux[i]);
    end;
    //wait
    delay(15);
  until done or sdlpressed or keypressed;
end;

procedure Fireworks(x1, y1, x2, y2: integer);
var x, y: integer;
begin
  x := random(x2-x1 +1) +x1;
  y := random(y2-y1) +y1;
  textbackground(random(6)+1);
  gotoxy(x,y);
  write(' ');
  delay(1);
  textbackground(BGR);
end;

{
  Game Deps
}

function NewIdent: word;
begin
  inc(last_ident);
  if last_ident = 65530 then last_ident := 9; //lol
  NewIdent := last_ident;
end;

function GetBallIX(id: word): integer;
var bx: integer;
begin
  GetBallIX := -1;
  for bx := low(ballz) to high(ballz) do begin
    if ( ballz[bx].id = id ) then begin
      GetBallIX := bx;
      exit;
    end;
  end;
end;

function GetPadIX(id: char): integer;
var px: integer;
begin
  GetPadIX := -1;
  for px := low(padz) to high(padz) do begin
    if ( padz[px].id = id ) then begin
      GetPadIX := px;
      exit;
    end;
  end;
end;

{
  Game Init
}

procedure InitLevel(lvl: char);
// called only from NewGame
const
  chr = '|';
var
  x, y, found: integer;
  dx, ix, lx: integer;
  key: string;
  q: char;
begin
  current_level := lvl;
  LoadLevel(CfgInt('Width'), CfgInt('Height'), 'level'+current_level+'.pop');
  {
    detect
  }
  setlength(detected, 0);
  //scan for lower x
  //(horiz, from top to bottom)
  found := 0;
  for x := 1 to W do begin
    y := 0;
    while y < H do begin
      q := ThisLevel[y,x];
      if q = chr then begin
        dx := found;
        inc(found);
        setlength(detected, found);
        detected[dx].chr := PLAYERS[found];
        detected[dx].x := x;
        detected[dx].z := y +vDiff;
        if x > W div 2
          then detected[dx].team := TEAM_N
          else detected[dx].team := TEAM_P;
        ix := 0;
        lx := 1;
        while not ( q = ' ' ) do begin
          setlength(detected[dx].ini, lx);

          if q = chr
            then detected[dx].ini[ix] := detected[dx].chr[1]
            else detected[dx].ini[ix] := q;

          ix := lx;
          inc(lx);
          inc(y);
          q := ThisLevel[y,x];
        end;
      end;
      inc(y);
    end;
  end;
  {
    finish
  }
  //send level to screen
  PushLevel;
  //reset visuals
  for x := low(pop_chr) to high(pop_chr) do begin
    key := 'BGR' + IntToHex(x)[4];
    if not ( CfgGet(key) = -1 )
      then pop_bgr[x] := CfgInt(key);
    key := 'CHR' + IntToHex(x)[4];
    if not ( CfgGet(key) = -1 )
      then pop_chr[x] := CfgChr(key);
    key := 'CLR' + IntToHex(x)[4];
    if not ( CfgGet(key) = -1 )
      then pop_clr[x] := CfgInt(key);
  end;
end;

procedure ResetPlayers;
var px: integer;
begin
  setlength(padz, length(PLAYERS));
  //set defaults for all players
  for px := low(padz) to high(padz) do begin
    padz[px].id := PLAYERS[px+1];
    padz[px].chr := PLAYERS[px+1];
    padz[px].points := 0;
    padz[px].hasGlue := false;
    padz[px].hasFire := false;
    padz[px].hasBall := false;
    padz[px].needsRefresh := false;
    padz[px].isOut := false;
    padz[px].inactive := true;
  end;
end;

procedure LoadPlayers;
var dx, ix, px: integer;
begin
  //override
  for dx := low(detected) to high(detected) do begin
    padz[dx].id := detected[dx].chr[1];
    padz[dx].chr := detected[dx].chr;
    padz[dx].x := detected[dx].x;
    padz[dx].y := detected[dx].z;
    padz[dx].z := detected[dx].z;

    setlength(padz[dx].ini, length(detected[dx].ini));
    setlength(padz[dx].pad, length(detected[dx].ini));
    for ix := low(detected[dx].ini) to high(detected[dx].ini) do begin
      padz[dx].ini[ix] := detected[dx].ini[ix];
      padz[dx].pad[ix] := detected[dx].ini[ix];
    end;
    padz[dx].team := detected[dx].team;
    if padz[dx].team = TEAM_P then begin
      padz[dx].bgr := CfgStr('BGR_Team+');
      padz[dx].clr := CfgStr('CLR_Team+');
    end else begin
      padz[dx].bgr := CfgStr('BGR_Team-');
      padz[dx].clr := CfgStr('CLR_Team-');
    end;

    padz[dx].inactive := false;
  end;
  //cleanup
  px := length(padz);
  while px > 0 do begin
    dec(px);
    if padz[px].inactive
      then delete(padz, px, 1);
  end;
end;

procedure SetPlayers(const playerz: array of integer);
//SetPlayers([x1,y1,l1 , x2,y2,l2 , x3,y3,l3 , x4,y4,l4 , x5,y5,l5 , x6,y6,l6]);
var
  px, pos: integer;
  x, y, l: integer;
begin
  if not ( length(playerz) mod 3 = 0 ) then exit;
  for px := low(playerz) to length(playerz) div 3 -1 do begin
    pos := px * 3;
    x := playerz[pos+0];
    y := playerz[pos+1];
    l := playerz[pos+2];
    //set
    padz[px].x := x;
    padz[px].y := y;
    padz[px].z := y;
    if x > W div 2 then begin
      padz[px].team := TEAM_N;
      padz[px].bgr := CfgStr('BGR_Team-');
      padz[px].clr := CfgStr('CLR_Team-');
    end else begin
      padz[px].team := TEAM_P;
      padz[px].bgr := CfgStr('BGR_Team+');
      padz[px].clr := CfgStr('CLR_Team+');
    end;
    setlength(padz[px].pad, l);
    for l := 0 to l do begin
      padz[px].ini[l] := padz[px].chr[1];
      padz[px].pad[l] := padz[px].chr[1];
    end;
    padz[px].inactive := false;
  end;
  //cleanup
  px := length(padz);
  while px > 0 do begin
    dec(px);
    if padz[px].inactive
      then delete(padz, px, 1);
  end;
end;

{
  Game Dynamics
}

procedure GameOver;
// called only from RefreshStatus
var
  x, points1, points2: integer;
  s: string;
begin
  points1 := 0;
  points2 := 0;
  for x := low(padz) to high(padz) do begin
    if ( x mod 2 = 0 ) then begin
      inc(points1, padz[x].points);
    end else begin
      inc(points2, padz[x].points);
    end;
  end;

  s := '';
  if ( points1 > points2 ) or ( points1 = points2 ) and ( set1 = 0 ) then begin
    for x := 1 to length(CfgStr('Team+')) do s := s + ' ' + CfgStr('Team+')[x];
    s := trim(s);
    while length(s) < 39 do s := ' ' + s + ' ';
    x := CfgInt('BGR_Team+');
  end;
  if ( points1 < points2 ) or ( points1 = points2 ) and ( set2 = 0 ) then begin
    for x := 1 to length(CfgStr('Team-')) do s := s + CfgStr('Team-')[x];
    s := trim(s);
    while length(s) < 39 do s := ' ' + s + ' ';
    x := CfgInt('BGR_Team-');
  end;
  FlipTextIni(39);
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '           G A M E   O V E R           ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(x, s);
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                W I N S                ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '     C O N G R A T U L A T I O N S     ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '                                       ');
  FlipTextAt(1,2);

  x := 0;
  repeat
    Fireworks(W div 2 +1, 2, W,H);
    if x < -5 then begin
      x := random(300)+30;
      atone(random(10000)+50, x);
    end;
    dec(x);
  until sdlpressed or keypressed;
end;
procedure PrintPoints;
var
  s: string;
  x, points1, points2: integer;
begin
  points1 := 0;
  points2 := 0;
  for x := low(padz) to high(padz) do begin
    if ( x mod 2 = 0 ) then begin
      inc(points1, padz[x].points);
    end else begin
      inc(points2, padz[x].points);
    end;
  end;
  textbackground(BGR);
  s := '  ' + inttostr(points1) + ' ';
  gotoxy(W div 2 - (length(s)) -3, 1);
  textcolor(CfgInt('CLR'+BALL));
  write(s);
  s := ' ' + inttostr(points2) + '  ';
  gotoxy(W div 2 +1 +nhDiff +3, 1);
  textcolor(CfgInt('CLR'+BALL));
  write(s);
end;
procedure RefreshStatus;
var x: integer;
begin
  textbackground(BGR);
  for x := 1 to W -1 do begin
    gotoxy(x, H+1);
    write(' ');
  end;
  PrintPoints;
  if ( set1 = 0 ) or ( set2 = 0 ) then begin
    game_over := true;
    GameOver();
    exit;
  end;
  if ( set2 < W div 2 -1 ) then begin
    for x := 1 to set2 do begin
      gotoxy(x, H +1);
      textbackground(CfgInt('BGR_Team+'));
      write(' ');
    end;
  end;
  if ( set1 < W div 2 -1 ) then begin
    for x := 1 to set1 do begin
      gotoxy(x+ W div 2 +nhDiff, H +1);
      textbackground(CfgInt('BGR_Team-'));
      write(' ');
    end;
  end;
  textbackground(BGR);
end;

procedure PutPad(px: integer);
var i, x, y: integer;
begin
  if padz[px].isOut then exit;
  for i := low(padz[px].pad) to high(padz[px].pad) do begin
    x := padz[px].X;
    y := padz[px].Y +i;
    PutCharAt(x,y, padz[px].pad[i]);
  end;
end;
procedure DelPad(px: integer);
var i, x, y: integer;
begin
  for i := low(padz[px].pad) to high(padz[px].pad) do begin
    x := padz[px].X;
    y := padz[px].Y +i;
    PutCharAt(x,y, ' ');
  end;
end;
procedure MovePad(px, dir: integer);
var cur_y, nxt_y, low_y, bx: integer;
begin
  //calculate new
  cur_y := padz[px].Y;
  nxt_y := cur_y + dir;
  low_y := cur_y + length(padz[px].pad);
  //if pad may move
  if ( dir = DIR_UP ) and ( nxt_y = 1 ) then exit;
  if ( dir = DIR_UP ) and not ( GetCharAt(padz[px].X, nxt_y) = ' ' ) then exit;
  if ( dir = DIR_DN ) and ( low_y = H ) then exit;
  if ( dir = DIR_DN ) and not ( GetCharAt(padz[px].X, low_y) = ' ' ) then exit;
  //del old pad
  DelPad(px);
  //this padle moves, ball needs to forget-it
  for bx := low(ballz) to high(ballz)
    do if ( ballz[bx].last_chr = padz[px].id )
      then ballz[bx].last_chr := ' ';
  //move pad
  padz[px].Y := nxt_y;
  //has attach?
  if padz[px].hasBall then begin
    bx := GetBallIX(padz[px].hasBallID);
    //del old ball
    PutCharAt(ballz[bx].x, ballz[bx].y, ' ');
    //set new ball
    inc(ballz[bx].y, dir);
  end;
  //put new pad
  PutPad(px);
end;
procedure ResizePad(px, len: integer);
var size, i: integer;
begin
  DelPad(px);
  //check
  size := length(padz[px].pad);
  if ( len = ELONG ) and ( size + 2*len > H div 2 ) //too big
  or ( len = SHORT ) and ( size + 2*len < 1 ) //too small
    then exit;
  //resize
  inc(size, 2*len);
  setlength(padz[px].pad, 0);
  setlength(padz[px].pad, size);
  for i := low(padz[px].pad) to high(padz[px].pad)
    do padz[px].pad[i] := padz[px].id;
  //repos
  if len > 0 then begin
    //ELONG
    dec(padz[px].Y);
    if padz[px].Y < 2 then padz[px].Y := 2;
    while padz[px].Y + size > H do dec(padz[px].Y);
  end else begin
    //SHORT
    inc(padz[px].Y);
  end;
  //done
  PutPad(px);
end;
procedure FirePad(px: integer);
var mid, bx, fx, dx: integer;
begin
  //determine the middle of the px
  mid := padz[px].y + length(padz[px].pad) div 2;
  //glue?
  if padz[px].hasGlue and padz[px].hasBall then begin
    bx := GetBallIX(padz[px].hasBallID);
    // left or right ?
    ballz[bx].dx := DIR_LT;
    if ballz[bx].x < W div 2 then ballz[bx].dx := DIR_RT;
    // up or dn ? default (random)
    ballz[bx].dy := DIR_UP;
    if random(2) = 1 then ballz[bx].dy := DIR_DN;
    // up or dn ? calculate
    if ballz[bx].y < mid then ballz[bx].dy := DIR_UP;
    if ballz[bx].y > mid then ballz[bx].dy := DIR_DN;
    //done
    padz[px].hasBall := false;
  end else if padz[px].hasFire then begin
    dx := DIR_LT;
    if padz[px].x < W div 2 then dx := DIR_RT;
    fx := length(firez);
    setlength(firez, fx+1);
    firez[fx].oriPadID := padz[px].id;
    firez[fx].x := padz[px].x;
    firez[fx].y := mid;
    firez[fx].dx := dx;
    firez[fx].last_chr := ' ';
  end;
end;

procedure ResetGame;
var bx, px, fx, i: integer;
begin
  {
    These are volatile values,
      they change after each out.
    The default values for the level
      are set in NewGame.
  }
  delta_speed := 0;
  superball := false;
  ball_over := false;
  {
    // reset ballz
  }
  //delete ball(s)
  for bx := low(ballz) to high(ballz)
    do PutCharAt(ballz[bx].x, ballz[bx].y, ballz[bx].last_chr);
  //resize ball(s)
  setlength(ballz, 1);
  //reset ball
  bx := 0;
  ballz[bx].id := NewIdent;
  // ball coords, x & y
  ballz[bx].x := W div 2;
  ballz[bx].y := H div 2;
  //fix x (off the net)
  inc(ballz[bx].x, scored);
  //fix x for even width
  if nhDiff = scored then inc(ballz[bx].x);
  //fix y for odd height
  if ( vDiff=1 ) and ( random(2)=1 ) then dec(ballz[bx].y);
  // ball dir ( L / R ), dx & dy
  ballz[bx].dx := scored;
  // ball dir ( Hi / Lo )
  ballz[bx].dy := 1;
  if random(2) = 1 then ballz[bx].dy := -ballz[bx].dy;
  //last touch
  px := 1 - ((scored+1) div 2);
  ballz[bx].last_tch := padz[px].id;
  //last char
  ballz[bx].last_chr := GetCharAt(ballz[bx].x, ballz[bx].y);
  //reset config
  CfgSet('BGR'+BALL, BALL_BGR);
  CfgSet('CHR'+BALL, BALL_CHR);
  CfgSet('CLR'+BALL, BALL_CLR);
  {
    // reset padz
  }
  for px := low(padz) to high(padz) do begin
    DelPad(px);
    PrintScreen;
    //reset values
    padz[px].isOut := false;
    padz[px].hasGlue := false;
    padz[px].hasFire := false;
    padz[px].hasBall := false;
    padz[px].needsRefresh := false;
    //reset padle
    setlength(padz[px].pad, 0);
    setlength(padz[px].pad, length(padz[px].ini));
    for i := low(padz[px].pad) to high(padz[px].pad)
      do padz[px].pad[i] := padz[px].ini[i];
    //reset pos
    //padz[px].Y := H div 2 - length(padz[px].pad) div 2 +vDiff;
    padz[px].Y := padz[px].Z;
    //reset cfg
    CfgSet('BGR'+padz[px].id, padz[px].bgr);
    //done
    PutPad(px);
    PrintScreen;
  end;
  {
    // reset firez
  }
  for fx := low(firez) to high(firez)
    do PutCharAt(firez[fx].x, firez[fx].y, firez[fx].last_chr);
  setlength(firez, 0);
  {
    // done
  }
  RefreshStatus;
end;
procedure NewGame(lvl: char);
const bx = 0;
begin
  scored := TEAM_P; //Team+
  game_over := false;
  set1 := CfgInt('StartBalls');
  set2 := CfgInt('StartBalls');

  InitLevel(lvl);
  ResetPlayers;
  LoadPlayers;

  //needed for last touch
  setlength(ballz, bx+1);
  ballz[bx].id := NewIdent;
  ballz[bx].last_tch := padz[low(padz)].id;

  ResetGame;
end;

procedure PauseGame;
var
  i: integer;
  s: string;
begin
  textcolor(white);
  for i := 1 to W -32 do begin
    gotoxy(i, H +1);
    write(' @COPYLEFT: ALL WRONGS DESERVED.');
  end;
  textcolor(CLR);
  gotoxy(1, H +1);
  write('SDL');
  textcolor(white);
  write(':');
  if sdl then begin
    textcolor(green);
    write('ON');
  end else begin
    textcolor(red);
    write('OFF');
  end;

  FlipTextIni(39);
  FlipTextAdd(white,                '                                       ');
  s := '     ' + CfgStr('Team+');
  while length(s) < 39 do s := s + ' ';
  FlipTextAdd(CfgInt('BGR_Team+'),  s);
  FlipTextAdd(CfgInt('CLR'+BALL),   '            UP: E     FIRE: D          ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '          DOWN: C                      ');
  FlipTextAdd(white,                '                                       ');
  s := '     ' + CfgStr('Team-');
  while length(s) < 39 do s := s + ' ';
  FlipTextAdd(CfgInt('BGR_Team-'),  s);
  FlipTextAdd(CfgInt('CLR'+BALL),   '            UP: I     FIRE: J          ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '          DOWN: N                      ');
  FlipTextAdd(white,                '                                       ');
  FlipTextAdd(white,                '     ESC: QUIT                         ');
  FlipTextAdd(white,                '     TAB: UN/MUTE                      ');
  FlipTextAdd(white,                '     SPACE: PAUSE                      ');
  FlipTextAdd(white,                '     ENTER: RESET LEVEL                ');
  FlipTextAdd(white,                '     BACKSPACE: RESET BALLS            ');
  FlipTextAdd(white,                '                                       ');
  FlipTextAdd(white,                '     SPEED UP:     +                   ');
  FlipTextAdd(white,                '     SPEED DOWN:   -                   ');
  FlipTextAdd(white,                '     CHANGE LEVEL: 1 to 9              ');
  FlipTextAdd(white,                '                                       ');
  FlipTextAdd(white,                '                                       ');
  FlipTextAdd(CfgInt('CLR'+BALL),   '     PRESS ANY KEY TO CONTINUE         ');
  FlipTextAdd(white,                '                                       ');
  FlipTextAdd(white,                '                                       ');
  FlipTextAt(1,2);

  i := 0;
  repeat
    Fireworks(W div 2 +1, 2, W,H);
    inc(i);
    if ( i > 10*1000 + random(5)*1000 ) then begin
      i := 0;
      FlipTextAt(1, 2);
    end;
  until sdlPressed or keyPressed;
  if sdl then keyDel(32) else if readkey = #27 then Quit;

  ResetScreen;
  for i := 1 to W -1 do begin
    gotoxy(i, H +1);
    write(' ');
  end;

  RefreshStatus;
end;

procedure ResetBalls;
//called only from HandleKeypress
begin
  set1 := CfgInt('StartBalls');
  set2 := CfgInt('StartBalls');
  RefreshStatus;
end;
procedure HandleKeypress(key: char);
begin
  case key of
    '1': NewGame(key);
    '2': NewGame(key);
    '3': NewGame(key);
    '4': NewGame(key);
    '5': NewGame(key);
    '6': NewGame(key);
    '7': NewGame(key);
    '8': NewGame(key);
    '9': NewGame(key);
    '0': NewGame(key);
    'e': MovePad(GetPadIX(padz[low(padz)].id), DIR_UP);
    'c': MovePad(GetPadIX(padz[low(padz)].id), DIR_DN);
    'd': FirePad(GetPadIX(padz[low(padz)].id));
    'i': MovePad(GetPadIX(padz[high(padz)].id), DIR_UP);
    'n': MovePad(GetPadIX(padz[high(padz)].id), DIR_DN);
    'j': FirePad(GetPadIX(padz[high(padz)].id));
    ' ': PauseGame;
    '+': dec(game_speed, 5);
    '-': inc(game_speed, 5);
     #8: ResetBalls; //backspace
     #9: mute := not mute; //tab
    #13: NewGame(current_level); //enter
    #27: Quit; //esc
  end;
  //game confort
  delay(game_confort);
end;

procedure HandleHit(bx: integer; chr: char);
var px, int, nbx, p: integer;
begin
  ballz[bx].last_chr := chr;
  //pad hit
  for px := low(padz) to high(padz) do begin
    if padz[px].id = chr then begin
      ballz[bx].dx := -ballz[bx].dx;
      ballz[bx].last_tch := padz[px].id;
      inc(padz[px].points, 1000);
      if padz[px].hasGlue then begin
        //stop ball
        ballz[bx].dx := 0;
        ballz[bx].dy := 0;
        //del ball
        PutCharAt(ballz[bx].x, ballz[bx].y, ballz[bx].last_chr);
        ballz[bx].last_chr := ' ';
        //flag
        padz[px].hasBall := true;
        padz[px].hasBallID := ballz[bx].id;
        //reset ball position
        if ballz[bx].x > W div 2
          then dec(ballz[bx].x)
          else inc(ballz[bx].x);
      end;
      if not mute then atone(900, 50);
      exit;
    end;
  end;
  //retrieve pad index
  px := GetPadIX(ballz[bx].last_tch);
  //superball
  if superball then begin
    if ( ballz[bx].y = 1 ) or ( ballz[bx].y = H )
      then ballz[bx].dy := -ballz[bx].dy;
    if not mute then atone(1200, 50);
    inc(padz[px].points, 50);
    ballz[bx].last_chr := ' ';
    exit;
  end;
  //hit another non-object (ball, fire)
  if not isHexa(chr) then begin
    ballz[bx].last_chr := ' ';
    exit;
  end;
  //not pad hit
  int := hex2dec(chr);
  if boolean( int and 8 ) then begin
    //SPECIAL
    case int of
      //PERMANENT
       8: dec(delta_speed, DeltaSpeed); //FAST
       9: inc(delta_speed, DeltaSpeed); //SLOW
      10: ResizePad(GetPadIX(ballz[bx].last_tch), ELONG); //ELONG
      11: ResizePad(GetPadIX(ballz[bx].last_tch), SHORT); //SHORT
      //ERASEABLE
      12: begin //BREAK
          CfgSet('CHR'+BALL, CfgStr('CHR'+chr));
          superball := true;
        end;
      13: begin //BALLS
          //add ball
          nbx := length(ballz);
          setlength(ballz, nbx+1);
          ballz[nbx].id := NewIdent;
          ballz[nbx].last_chr := ' ';
          ballz[nbx].last_tch := ballz[bx].last_tch;
          ballz[nbx].x := ballz[bx].x;
          ballz[nbx].y := ballz[bx].y;
          ballz[nbx].dx := -ballz[bx].dx;
          ballz[nbx].dy := -ballz[bx].dy;
        end;
      14: begin //GLUE
        padz[px].hasGlue := true;
        padz[px].needsRefresh := true;
        //change! pad
        p := high(padz[px].pad) div 2;
        padz[px].pad[p] := chr;
      end;
      15: begin //FIRE
        padz[px].hasFire := true;
        padz[px].needsRefresh := true;
        //change? pad
        p := high(padz[px].pad) div 2;
        if padz[px].pad[p] = padz[px].id
          then padz[px].pad[p] := chr;
        //change! pad
        CfgSet('BGR'+padz[px].id, FIRE_CLR);
      end;
    end;
    //points
    inc(padz[px].points, 100);
  end else begin
    //NORMAL
    if boolean( int and 1 ) then ballz[bx].dy := -ballz[bx].dy;
    if boolean( int and 2 ) then ballz[bx].dx := -ballz[bx].dx;
    inc(padz[px].points, 1);
  end;
  //Erase?
  if boolean( int and 4 ) then begin
    ballz[bx].last_chr := ' ';
    inc(padz[px].points, 10);
  end;
  //Mute?
  if not mute then atone(int * 1000, 50);
end;
function HandleFire(fx: integer; chr: char): boolean;
var
  int, px, po: integer;
  po1, po2: string;
  ph: boolean;
begin
  HandleFire := false;
  firez[fx].last_chr := chr;
  if chr = ' ' then exit;
  //hit a brik ?
  if isHexa(chr) then begin
    int := hex2dec(chr);
    //is it transparent ?
    if ( int xor 1 > int ) then exit;
  end;
  //hit a pad ?
  ph := false;
  for px := low(padz) to high(padz) do begin
    if padz[px].id = chr then begin
      //yup, hit a pad.
      ph := true;
      padz[px].isOut := true;
      padz[px].needsRefresh := true;
      //points
      dec(padz[px].points, padz[px].points div 10);
      inc(padz[GetPadIX(firez[fx].oriPadID)].points, 1000);
      //mute?
      if not mute then atone(500, 100);
    end;
  end;
  //all pads out?
  if ph then begin
    po1 := ''; // 0 2 4 Team+
    po2 := ''; // 1 3 5 Team-
    for px := low(padz) to high(padz) do begin
      if padz[px].isOut then begin
        if px mod 2 = 0 then begin
          po1 := po1 + '|';
        end else begin
          po2 := po2 + '|';
        end;
      end;
    end;
    po := ( high(padz) +1 ) div 2;
    if ( length(po1) = po ) then scored := TEAM_P;
    if ( length(po2) = po ) then scored := TEAM_N;
    if ( length(po1) = po )
    or ( length(po2) = po )
    then begin
      if not mute then tone(600, 600);
      ball_over := true;
      exit;
    end;
  end;
  //hit a ball, hit a fire ?
  delete(firez, fx, 1);
  HandleFire := true;
end;
procedure UpdateGamestate;
var
  s: string;
  chr: char;
  i: integer;
  some_out: boolean;
  bx, px, fx: integer;
begin
  if game_over then begin
    //next level
    i := StrToInt(current_level) +1;
    s := IntToStr(i);
    NewGame(s[length(s)]);
    exit;
  end;

  //padle refresh?
  for px := low(padz) to high(padz) do begin
    if padz[px].needsRefresh then begin
      DelPad(px);
      PrintScreen;
      PutPad(px);
      PrintScreen;
      padz[px].needsRefresh := false;
    end;
  end;

  //bullets shot?
  fx := length(firez);
  while fx > 0 do begin
    dec(fx);
    PutCharAt(firez[fx].x, firez[fx].y, firez[fx].last_chr);
    inc(firez[fx].x, firez[fx].dx);
    if ( firez[fx].x < 1 ) or ( firez[fx].x > W ) then begin
      //out
      delete(firez, fx, 1);
      continue;
    end;
    chr := GetCharAt(firez[fx].x, firez[fx].y);
    if HandleFire(fx, chr) then continue;
    if ball_over then begin
      ResetGame;
      exit;
    end;
    PutCharAt(firez[fx].x, firez[fx].y, FIRE);
  end;

  some_out := false;
  bx := length(ballz);
  repeat
    dec(bx);
    //del ball
    PutCharAt(ballz[bx].x, ballz[bx].y, ballz[bx].last_chr);
    ballz[bx].last_chr := ' ';
    //new ball coords
    inc(ballz[bx].x, ballz[bx].dx);
    inc(ballz[bx].y, ballz[bx].dy);
    //OUT?
    if ( ballz[bx].x < 1 ) or ( ballz[bx].y < 1 )
    or ( ballz[bx].x > W ) or ( ballz[bx].y > H )
    then begin
      some_out := true;
      //last ball ?
      if length(ballz) = 1 then begin
        if ( ballz[bx].x <= 1 ) then begin
          //out left
          dec(set1);
          scored := TEAM_N; //Team-
          for px := low(padz) to high(padz) do if ( px mod 2 = 0 ) then
              dec(padz[px].points, ( padz[px].points div 10 ));
        end else begin
          //out right
          dec(set2);
          scored := TEAM_P; //Team+
          for px := low(padz) to high(padz) do if not ( px mod 2 = 0 ) then
              dec(padz[px].points, ( padz[px].points div 10 ));
        end;
        if not mute then tone(300, 600);
        ResetGame;
        exit;
      end;
      //remove
      delete(ballz, bx, 1);
      continue;
    end;
    //new ball coords ok
    chr := GetCharAt(ballz[bx].x, ballz[bx].y);
    //colision check
    if not ( chr = ' ' )
      then HandleHit(GetBallIX(ballz[bx].id), chr);
    //put ball
    PutCharAt(ballz[bx].x, ballz[bx].y, BALL);
  until bx = 0;
  //1 beep to rule them all
  if some_out then begin
    if not mute then atone(300, 100);
    some_out := false;
  end;
  //finish
  PrintPoints;
  //game speed
  delay(game_speed + delta_speed);
end;

BEGIN
  //load config(s)
  CfgLoad('ini.pop', true);
  W := CfgInt('Width');
  H := CfgInt('Height');
  if ( WindMaxX < W ) or ( WindMaxY < H ) then begin
    writeln('Console too small, please resize. Press ENTER to continue.');
    readln;
    quit;
  end;
  CfgLoad('cfg.pop', false);

  //init
  clrscr;
  randomize;
  SetCursor(false);
  mute := false;
  vDiff := H mod 2;
  hDiff := W mod 2;
  nhDiff := 1 - hDiff;
  last_ident := 9; //allow for pads
  if sdl_init(SDL_INIT_VIDEO) < 0 then sdl := false;
  if sdl then begin
    win := sdl_createWindow('pppEventsConcealedWindow', 1,1 , 1,1 ,
                            SDL_WINDOW_BORDERLESS or SDL_WINDOW_SKIP_TASKBAR);
    if win = nil then sdl := false;
  end;
  //cache
  BGR := CfgInt('BGR');
  CLR := CfgInt('CLR');
  game_confort := CfgInt('GameConfort');
  game_speed := CfgInt('GameSpeed');
  DeltaSpeed := CfgInt('DeltaSpeed');
  BALL := CfgChr('BALL');
  BALL_BGR := CfgStr('BGR');
  BALL_CHR := CfgStr('BALL');
  BALL_CLR := CfgStr('CLR');
  FIRE := CfgChr('CHRF');
  FIRE_BGR := CfgStr('BGR');
  FIRE_CHR := CfgStr('CHRF');
  FIRE_CLR := CfgStr('CLR');
  //post-init
  CfgSet('BGR_', '0'); //lag
  CfgSet('BGR'+BALL, BALL_BGR);
  CfgSet('CHR'+BALL, BALL_CHR);
  CfgSet('CLR'+BALL, BALL_CLR);
  CfgSet('FIRE', FIRE_CHR);
  CfgSet('BGR'+FIRE, FIRE_BGR);
  CfgSet('CHR'+FIRE, FIRE_CHR);
  CfgSet('CLR'+FIRE, FIRE_CLR);

  //center window
  DeltaWidth := ( WindMaxX -W ) div 2;
  DeltaHeight := ( WindMaxY -H ) div 2;
  //background
  Wallpaper;
  //window
  window(DeltaWidth, DeltaHeight,
         DeltaWidth +W -1, DeltaHeight +H);
  { window has one more line }

  //load default level
  NewGame(CfgChr('StartLevel'));
  PauseGame;

  repeat
    PrintScreen;

    if sdl then begin
      sdl_raiseWindow(win); //win
      sdl_setWindowInputFocus(win); //nix
      while not ( sdl_pollEvent(@evt) = 0 ) do case evt.type_ of
        SDL_KEYDOWN: keyAdd(evt.key.keysym.sym);
        SDL_KEYUP: keyDel(evt.key.keysym.sym);
      end;
      for que := 1 to length(keys) do HandleKeypress(keys[que]);
    end else while keypressed do HandleKeypress(readkey);

    UpdateGamestate;
  until false;

END.
