{$MODE OBJFPC}{$H+}

UNIT POP;

// Licensed under the EUPL

INTERFACE

TYPE
  pop_matrix = array of string; //HxW

VAR
  pop_bgr: array [0..15] of integer;
  pop_chr: array [0..15] of char;
  pop_clr: array [0..15] of integer;

procedure
   Tone(frequency_hz, duration_ms: integer);
procedure
  aTone(frequency_hz, duration_ms: integer);
procedure
  SetCursor(visible: boolean);
procedure
  SDL_aToneGenerator(userdata: pointer; stream: PUInt8; len: longint); cdecl;

//cfg may be re-written to use inicol unit, TCollection & TCollectionItem(s)
procedure
  CfgShow;
function
  CfgGet(key: string): integer;
procedure
  CfgSet(key, val: string);
procedure
  CfgLoad(FileName: string; flush: boolean);
procedure
  CfgSave(FileName: string);
function
  CfgBol(key: string): boolean;
function
  CfgChr(key: string): char;
function
  CfgInt(key: string): integer;
function
  CfgStr(key: string): string;

procedure
  LoadLevel(Width, Height: integer; FileName: string);
function
  ThisLevel: pop_matrix;
procedure
  PushLevel;
procedure
  PrintScreen;
procedure
  ResetScreen;
function
  GetCharAt(x, y: integer): char;
procedure
  PutCharAt(x, y: integer; c: char);
function
  isHexa(chr: char): boolean;

IMPLEMENTATION

USES
{$IFDEF UNIX}
  cthreads,
  unix,
{$ENDIF}
  classes,
  process,
  strutils,
  sysutils,
  crt, SDL2;

TYPE
  TSDL_AsyncTone = class(TThread)
    private
      hz, ms: integer;
      aPhaseIncrement, aCurrentPhase: double; //need to be thread specific
      procedure TSDL_aToneGenerator(userdata: pointer; stream: PUInt8; len: longint); cdecl;
      procedure TSDL_aTone(frequency_hz, duration_ms: integer);
    protected
      procedure Execute; override;
    public
      constructor Create(frequency_hz, duration_ms: integer);
  end;
  procedure TSDL_AsyncTone.TSDL_aToneGenerator(userdata: pointer; stream: PUInt8; len: longint); cdecl;
  var
    buffer: PInt16;
    i: integer;
  begin
    buffer := PInt16(stream);
    for i := 0 to (len div 2) - 1 do begin
      buffer^ := trunc(32767 * sin(aCurrentPhase));
      inc(buffer);
      aCurrentPhase := aCurrentPhase + aPhaseIncrement;
      if aCurrentPhase > 2 * pi then
        aCurrentPhase := aCurrentPhase - 2 * pi;
    end;
  end;
  procedure TSDL_AsyncTone.TSDL_aTone(frequency_hz, duration_ms: integer);
  var
    audioSpec: TSDL_AudioSpec;
    deviceID: TSDL_AudioDeviceID;
  begin
    with audioSpec do begin
      freq := 44100;
      format := AUDIO_S16SYS;
      channels := 1;
      samples := 4096;
      callback := @SDL_aToneGenerator;
      userdata := self;
    end;
    deviceID := SDL_OpenAudioDevice(nil, 0, @audioSpec, nil, 0);
    if deviceID = 0 then exit;
    aPhaseIncrement := (2 * pi * frequency_hz) / audioSpec.freq;
    aCurrentPhase := 0;
    SDL_PauseAudioDevice(deviceID, 0);
    SDL_Delay(duration_ms);
    SDL_CloseAudioDevice(deviceID);
  end;
  procedure TSDL_AsyncTone.Execute;
  begin
    TSDL_aTone(hz, ms);
  end;
  constructor TSDL_AsyncTone.Create(frequency_hz, duration_ms: integer);
  begin
    inherited create(true);
    FreeOnTerminate := true;
    hz := frequency_hz;
    ms := duration_ms;
    start;
  end;

VAR
  pop_keys: array of string;
  pop_vals: array of string;
  pop_mat: pop_matrix; //level
  pop_mat_h, pop_mat_w: integer;
  old_screen, new_screen, lag_screen: ansistring;

  pop_sdl: boolean = true;
  pop_audio: boolean = false;
  pop_phaseIncrement, pop_currentPhase: double;

procedure SDL_aToneGenerator(userdata: pointer; stream: PUInt8; len: longint); cdecl;
var iTone: TSDL_AsyncTone;
begin
  if userdata = nil then exit;
  iTone := TSDL_AsyncTone(userdata);
  iTone.TSDL_aToneGenerator(nil, stream, len);
end;

procedure SDL_ToneGenerator(userdata: pointer; stream: PUInt8; len: longint); cdecl;
var
  buffer: PInt16;
  i: integer;
begin
  buffer := PInt16(stream);
  for i := 0 to (len div 2) - 1 do begin
    buffer^ := trunc(32767 * sin(pop_currentPhase));
    inc(buffer);
    pop_currentPhase := pop_currentPhase + pop_phaseIncrement;
    if pop_currentPhase > 2 * pi then
      pop_currentPhase := pop_currentPhase - 2 * pi;
  end;
end;
procedure SDL_Tone(frequency_hz, duration_ms: integer);
var
  audioSpec: TSDL_AudioSpec;
  deviceID: TSDL_AudioDeviceID;
begin
  // Set the desired audio specifications
  with audioSpec do begin
    freq := 44100; // Audio sampling (CD quality)
    format := AUDIO_S16SYS; // 16-bit signed audio format
    channels := 1; // Mono audio
    samples := 4096; // Audio buffer size
    callback := @SDL_ToneGenerator;
    userdata := nil;
  end;
  // Open the audio device
  deviceID := SDL_OpenAudioDevice(nil, 0, @audioSpec, nil, 0);
  if deviceID = 0 then begin
    pop_sdl := false;
    exit;
  end;
  // Calculate the phase increment for a given Hz tone
  pop_phaseIncrement := (2 * pi * frequency_hz) / audioSpec.freq;
  pop_currentPhase := 0;
  // Start playing audio
  SDL_PauseAudioDevice(deviceID, 0);
  // Duration (milliseconds)
  SDL_Delay(duration_ms);
  // Clean up
  SDL_CloseAudioDevice(deviceID);
end;

procedure Tone(frequency_hz, duration_ms: integer);
// uses sysutils
var cmd, duration_s: string;
begin
  if frequency_hz < 200 then frequency_hz := 200;
  if frequency_hz > 13000 then frequency_hz := 13000;
  if duration_ms < 30 then duration_ms := 30;
  if duration_ms > 3000 then duration_ms := 3000;
  if pop_sdl and not pop_audio then begin
    if SDL_Init(SDL_INIT_AUDIO) < 0
      then pop_sdl := false
      else pop_audio := true;
  end;
  if pop_sdl and pop_audio then begin
    SDL_Tone(frequency_hz, duration_ms);
    exit;
  end;
  {$IFDEF WINDOWS}
  cmd := 'try{[console]::beep(%d,%d)}catch{}';
  cmd := Format(cmd, [frequency_hz, duration_ms]);
  ExecuteProcess('powershell', ['-command', cmd]);
  {$ELSE}
  duration_s := FloatToStrF(duration_ms/1000, ffFixed, 3, 3); // ms to s
  cmd := '(2>/dev/null 1>&2 speaker-test -t sine -f %d)& pid=$!; sleep %ss; 2>/dev/null 1>&2 kill -9 $pid';
  cmd := Format(cmd, [frequency_hz, duration_s]);
  ExecuteProcess('/bin/sh', ['-c', cmd]);
  {$ENDIF}
end;

procedure aTone(frequency_hz, duration_ms: integer); //async
// uses sysutils, process
var
  cmd, duration_s: string;
  prc: TProcess;
begin
  if frequency_hz < 200 then frequency_hz := 200;
  if frequency_hz > 13000 then frequency_hz := 13000;
  if duration_ms < 30 then duration_ms := 30;
  if duration_ms > 3000 then duration_ms := 3000;
  if pop_sdl and not pop_audio then begin
    if SDL_Init(SDL_INIT_AUDIO) < 0
      then pop_sdl := false
      else pop_audio := true;
  end;
  if pop_sdl and pop_audio then begin
    TSDL_AsyncTone.Create(frequency_hz, duration_ms);
    exit;
  end;
  prc := TProcess.Create(nil);
  {$IFDEF WINDOWS}
  cmd := 'try{[console]::beep(%d,%d)}catch{}';
  cmd := Format(cmd, [frequency_hz, duration_ms]);
  prc.executable := 'powershell';
  prc.parameters.add('-command');
  {$ELSE}
  duration_s := FloatToStrF(duration_ms/1000, ffFixed, 3, 3); // ms to s
  cmd := '(2>/dev/null 1>&2 speaker-test -t sine -f %d)& pid=$!; sleep %ss; 2>/dev/null 1>&2 kill -9 $pid';
  cmd := Format(cmd, [frequency_hz, duration_s]);
  prc.executable := '/bin/sh';
  prc.parameters.add('-c');
  {$ENDIF}
  prc.parameters.add(cmd);
  prc.execute;
  prc.free;
end;

procedure SetCursor(visible: boolean);
begin
  if visible then begin
    {$IFDEF WINDOWS}
    cursoron;
    {$ELSE}
    //write(#27'[?25h');
    fpsystem('tput cnorm');
    {$ENDIF}
  end else begin
    {$IFDEF WINDOWS}
    cursoroff;
    {$ELSE}
    //write(#27'[?25l');
    fpsystem('tput civis');
    {$ENDIF}
  end;
end;

procedure CfgShow;
var i: integer;
begin
  for i := low(pop_keys) to high(pop_keys)
    do writeln(pop_keys[i], ' ', pop_vals[i]);
  for i := 0 to 15
    do writeln(i,
      ';pop_bgr:',pop_bgr[i],
      ';pop_chr:',pop_chr[i],
      ';pop_clr:',pop_clr[i]);
end;

function CfgGet(key: string): integer;
var i: integer;
begin
  CfgGet := -1;
  for i := low(pop_keys) to high(pop_keys) do begin
    if pop_keys[i] = key then begin
      CfgGet := i;
      exit;
    end;
  end;
end;

procedure CfgSet(key, val: string);
var i: integer;
begin
  i := CfgGet(key);
  //key does not exists
  if ( i = -1 ) then begin
    i := length(pop_keys) +1;
    setlength(pop_keys, i);
    setlength(pop_vals, i);
    i := i -1;
  end;
  //set
  pop_keys[i] := key;
  pop_vals[i] := val;
end;

procedure CfgLoad(FileName: string; flush: boolean);
var
  f: text;
  i: integer;
  s: ansistring;
begin
  //init
  i := 0;
  if flush then begin
    setlength(pop_keys, 0);
    setlength(pop_vals, 0);
  end;
  //set file
  assign(f, fileName);
  //open file
  reset(f);
  //read lines
  while not eof(f) do begin
    i := i + 1;
    readln(f, s);
    //skip?
    s := s.trim();
    if s.isempty then continue;
    if s.startswith('#') then continue;
    s := s.replace(chr(9), ' ');
    if not s.contains(' ') then continue;
    //clean
    while s.contains('  ') do s := s.replace('  ', ' ');
    //new
    CfgSet(s.split(' ')[0], s.split(' ')[1]);
  end;
  //close file
  close(f);
end;

procedure CfgSave(FileName: string);
var
  f: text;
  i: integer;
begin
  //set file
  assign(f, fileName);
  //create file
  rewrite(f);
  //write lines
  for i := low(pop_keys) to high(pop_keys)
    do writeln(f, pop_keys[i], chr(9), pop_vals[i]);
  //close file
  close(f);
end;

function CfgBol(key: string): boolean;
var
  i: integer;
  s: ansistring;
begin
  CfgBol := false; //default
  i := CfgGet(key);
  if ( i = -1 )
    then exit;
  s := pop_vals[i];
  CfgBol := s.toboolean();
end;

function CfgChr(key: string): char;
var
  i: integer;
  s: string;
begin
  CfgChr := ' '; //default
  i := CfgGet(key);
  if ( i = -1 )
    then exit;
  s := pop_vals[i];
  CfgChr := s[1];
end;

function CfgInt(key: string): integer;
var
  i: integer;
  s: ansistring;
begin
  CfgInt := 0; //default
  i := CfgGet(key);
  if ( i = -1 )
    then exit;
  s := pop_vals[i];
  CfgInt := s.tointeger();
end;

function CfgStr(key: string): string;
var i: integer;
begin
  CfgStr := ''; //default
  i := CfgGet(key);
  if ( i = -1 )
    then exit;
  CfgStr := pop_vals[i];
end;

procedure LoadLevel(Width, Height: integer; FileName: string);
var
  f: text;
  i, j: integer;
  s: string;
begin
  pop_mat_w := Width;
  pop_mat_h := Height;
  //reset matrix
  setlength(pop_mat, pop_mat_h);
  //reset level
  for i := 0 to pop_mat_h -1 do begin
    pop_mat[i] := '';
    for j := 1 to pop_mat_w do
      pop_mat[i] := pop_mat[i] + ' ';
  end;
  //set file
  assign(f, fileName);
  //open file
  reset(f);
  //read lines
  i := 0;
  while not eof(f) do begin
    readln(f, s);
    while length(s) < width
      do s := s + ' ';
    pop_mat[i] := s;
    i := i + 1;
  end;
  //close file
  close(f);
  //jetlag
  setlength(lag_screen, width * height);
  for i := 1 to width * height do lag_screen[i] := '|';
end;

function ThisLevel: pop_matrix;
begin
  ThisLevel := pop_mat;
end;

procedure PushLevel;
var
  i, j: integer;
  c: char;
begin
  //reset chars & colors
  for i := 0 to high(pop_chr) do begin
    pop_bgr[i] := CfgInt('BGR');
    pop_chr[i] := ' ';
    pop_clr[i] := CfgInt('CLR');
  end;
  //init screens
  old_screen := '';
  new_screen := '';
  for i := 0 to pop_mat_h -1 do begin
    for j := 1 to pop_mat_w do begin
      old_screen := old_screen + '|';
      c := pop_mat[i][j];
      if isHexa(c)
        then new_screen := new_screen + c
        else new_screen := new_screen + ' ';
    end;
  end;
  lag_screen := old_screen;
end;

function LagCharAt(x, y: integer): char;
begin
  // from 1 to 0 based index
  y := y - 1;
  LagCharAt := lag_screen[y*pop_mat_w +x];
end;
procedure PrintScreen;
var
  i, j, k, bgr, clr: integer;
  old_c, new_c, chr_x: char;
begin
  bgr := CfgInt('BGR');
  clr := CfgInt('CLR');
  for i := 1 to pop_mat_h do begin
    for j := 1 to pop_mat_w do begin
      //matrix to vector index
      k := (i-1)*pop_mat_w +j;
      //detect changes
      old_c := old_screen[k];
      new_c := new_screen[k];
      if new_c = old_c then continue;
      //repos
      gotoxy(j,i);
      //change
      old_screen[k] := new_c;
      if new_c = ' ' then begin
        textbackground(bgr);
        write(' ');
        continue;
      end else begin
        if ( new_c = CfgChr('BALL') )
        or ( new_c = CfgChr('FIRE') )
        then begin
          chr_x := LagCharAt(j,i);
          textbackground(CfgInt('BGR'+chr_x));
        end else begin
          textbackground(CfgInt('BGR'+new_c));
        end;
        textcolor(CfgInt('CLR'+new_c));
        write(CfgChr('CHR'+new_c));
      end;
    end;
  end;
  lag_screen := old_screen;
  textbackground(bgr);
  textcolor(clr);
end;

procedure ResetScreen;
var i: integer;
begin
  for i := 1 to length(old_screen)
    do old_screen[i] := '|';
end;

function GetCharAt(x, y: integer): char;
begin
  // from 1 to 0 based index
  y := y - 1;
  GetCharAt := new_screen[y*pop_mat_w +x];
end;

procedure PutCharAt(x, y: integer; c: char);
begin
  // from 1 to 0 based index
  y := y - 1;
  new_screen[y*pop_mat_w +x] := c;
end;

function isHexa(chr: char): boolean;
const hex = '1234567890ABCDEF';
begin
  isHexa := boolean( pos(chr, hex) );
end;

END.
