//------------------------------------------------------------------------------
//
//  DoomXS - A basic Windows source port of Doom
//  based on original Linux Doom as published by "id Software"
//  Copyright (C) 1993-1996 by id Software, Inc.
//  Copyright (C) 2021 by Jim Valavanis
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, inc., 59 Temple Place - Suite 330, Boston, MA
//  02111-1307, USA.
//
//------------------------------------------------------------------------------
//  Site: https://sourceforge.net/projects/doomxs/
//------------------------------------------------------------------------------

unit i_music;

interface


//  MUSIC I/O

procedure I_InitMusic;
procedure I_ShutdownMusic;

// Volume.
procedure I_SetMusicVolume(volume: integer);

// PAUSE game handling.
procedure I_PauseSong(handle: integer);
procedure I_ResumeSong(handle: integer);

// Registers a song handle to song data.
function I_RegisterSong(Data: pointer; size: integer): integer;

// Called by anything that wishes to start music.
//  plays a song, and when the song is done,
//  starts playing it again in an endless loop.
// Horrible thing to do, considering.
procedure I_PlaySong(handle: integer; looping: boolean);

// See above (register), then think backwards
procedure I_UnRegisterSong(handle: integer);

procedure I_ProcessMusic;

implementation

uses
  Windows,
  Messages,
  d_delphi,
  mmsystem,
  doomdef,
  doomstat,
  m_argv,
  m_misc,
  i_system,
  i_sound,
  i_midi,
  s_sound,
  w_wad,
  z_memory;

type
  music_t = (m_none, m_mus, m_midi);

const
  MAX_MIDI_EVENTS = 512;
  MUSMAGIC = $1A53554D; //"MUS"<EOF>

var
  hMidiStream: HMIDISTRM = 0;
  MidiDevice: LongWord;
  midicaps: MIDIOUTCAPS;
  m_type: music_t = m_none;

type
  MidiEvent_t = packed record
    time: LongWord;                  { Ticks since last event }
    ID: LongWord;                    { Reserved, must be zero }
    case integer of
      1: (Data: packed array[0..2] of byte;
        _type: byte);
      2: (mevent: LongWord);
  end;
  PMidiEvent_t = ^MidiEvent_t;
  MidiEvent_tArray = array[0..$FFFF] of MidiEvent_t;
  PMidiEvent_tArray = ^MidiEvent_tArray;

  Pmidiheader_t = ^midiheader_t;

  midiheader_t = record
    lpData: pointer;             { pointer to locked data block }
    dwBufferLength: LongWord;    { length of data in data block }
    dwBytesRecorded: LongWord;   { used for input only }
    dwUser: LongWord;            { for client's use }
    dwFlags: LongWord;           { assorted flags (see defines) }
    lpNext: Pmidiheader_t;       { reserved for driver }
    reserved: LongWord;          { reserved for driver }
    dwOffset: LongWord;          { Callback offset into buffer }
    dwReserved: array[0..7] of LongWord; { Reserved for MMSYSTEM }
  end;

  musheader_t = packed record
    ID: LongWord;       // identifier "MUS" 0x1A
    scoreLen: word;
    scoreStart: word;
    channels: word;     // count of primary channels
    sec_channels: word; // count of secondary channels
    instrCnt: word;
    dummy: word;
  end;
  Pmusheader_t = ^musheader_t;

const
  NUMMIDIHEADERS = 2;

type
  songinfo_t = record
    numevents: integer;
    nextevent: integer;
    midievents: PMidiEvent_tArray;
    header: array[0..NUMMIDIHEADERS - 1] of midiheader_t;
  end;
  Psonginfo_t = ^songinfo_t;

const
  MidiControlers: packed array[0..9] of byte =
    (0, 0, 1, 7, 10, 11, 91, 93, 64, 67);

var
  started: boolean = False;
  CurrentSong: Psonginfo_t = nil;
  loopsong: boolean = False;

function XLateMUSControl(control: byte): byte;
begin
  case control of
    10: Result := 120;
    11: Result := 123;
    12: Result := 126;
    13: Result := 127;
    14: Result := 121;
    else
    begin
      I_Error('XLateMUSControl(): Unknown control %d', [control]);
      Result := 0;
    end;
  end;
end;

const
  NUMTEMPOEVENTS = 2;

function GetSongLength(Data: PByteArray): integer;
var
  done: boolean;
  events: integer;
  header: Pmusheader_t;
  time: boolean;
  i: integer;
begin
  header := Pmusheader_t(Data);
  i := header.scoreStart;
  events := 0;
  done := header.ID <> MUSMAGIC;
  time := False;
  while not done do
  begin
    if boolval(Data[i] and $80) then
      time := True;
    Inc(i);
    case _SHR(Data[i - 1], 4) and 7 of
      1:
      begin
        if boolval(Data[i] and $80) then
          Inc(i);
        Inc(i);
      end;
      0,
      2,
      3: Inc(i);
      4: Inc(i, 2);
      else
        done := True;
    end;
    Inc(events);
    if time then
    begin
      while boolval(Data[i] and $80) do
        Inc(i);
      Inc(i);
      time := False;
    end;
  end;
  Result := events + NUMTEMPOEVENTS;
end;

function I_MusToMidi(MusData: PByteArray; MidiEvents: PMidiEvent_tArray): boolean;
var
  header: Pmusheader_t;
  score: PByteArray;
  spos: integer;
  event: PMidiEvent_tArray;
  channel: byte;
  etype: integer;
  delta: integer;
  finished: boolean;
  channelvol: array[0..15] of byte;
  count: integer;
  i: integer;
begin
  header := Pmusheader_t(MusData);
  Result := header.ID = MUSMAGIC;
  if not Result then
  begin
    printf('I_MusToMidi(): Not a MUS file' + #13#10);
    exit;
  end;

  count := GetSongLength(MusData);
  score := PByteArray(@MusData[header.scoreStart]);
  event := MidiEvents;

  i := 0;
  while i < NUMTEMPOEVENTS do
  begin
    event[i].time := 0;
    event[i].ID := 0;
    event[i]._type := MEVT_TEMPO;
    event[i].Data[0] := $00;
    event[i].Data[1] := $80; //not sure how to work this out, should be 140bpm
    event[i].Data[2] := $02; //but it's guessed so it sounds about right
    Inc(i);
  end;

  delta := 0;
  spos := 0;
  ZeroMemory(channelvol, SizeOf(channelvol));

  finished := False;
  while True do
  begin
    event[i].time := delta;
    delta := 0;
    event[i].ID := 0;
    etype := _SHR(score[spos], 4) and 7;
    event[i]._type := MEVT_SHORTMSG;
    channel := score[spos] and 15;
    if channel = 9 then
      channel := 15
    else if channel = 15 then
      channel := 9;
    if score[spos] and $80 <> 0 then
      delta := -1;
    Inc(spos);
    case etype of
      0:
      begin
        event[i].Data[0] := channel or $80;
        event[i].Data[1] := score[spos];
        Inc(spos);
        event[i].Data[2] := channelvol[channel];
      end;
      1:
      begin
        event[i].Data[0] := channel or $90;
        event[i].Data[1] := score[spos] and 127;
          if score[spos] and 128 <> 0 then
        begin
          Inc(spos);
          channelvol[channel] := score[spos];
        end;
        Inc(spos);
        event[i].Data[2] := channelvol[channel];
      end;
      2:
      begin
        event[i].Data[0] := channel or $e0;
        event[i].data[1] := (score[spos] and 1) shr 6;
        event[i].data[2] := (score[spos] div 2) and 127;
        Inc(spos);
      end;
      3:
      begin
        event[i].Data[0] := channel or $b0;
        event[i].Data[1] := XLateMUSControl(score[spos]);
        Inc(spos);
        event[i].Data[2] := 0;
      end;
      4:
      begin
        if boolval(score[spos]) then
        begin
          event[i].Data[0] := channel or $b0;
          event[i].Data[1] := MidiControlers[score[spos]];
          Inc(spos);
          event[i].Data[2] := score[spos];
          Inc(spos);
        end
        else
        begin
          event[i].Data[0] := channel or $c0;
          Inc(spos);
          event[i].Data[1] := score[spos];
          Inc(spos);
          event[i].Data[2] := 64;
        end;
      end;
      else
        finished := True;
    end;
    if finished then
      break;
    Inc(i);
    Dec(count);
    if count < 3 then
      I_Error('I_MusToMidi(): Overflow');
    if delta = -1 then
    begin
      delta := 0;
      while (score[spos] and 128) <> 0 do
      begin
        delta := _SHL(delta, 7);
        delta := delta + score[spos] and 127;
        Inc(spos);
      end;
      delta := delta + score[spos];
      Inc(spos);
    end;
  end;
end;


// MUSIC API.

procedure I_InitMus;
var
  rc: MMRESULT;
  numdev: LongWord;
  i: integer;
begin
  if M_CheckParm('-nomusic') <> 0 then
    exit;

  if hMidiStream <> 0 then
    exit;

  ZeroMemory(midicaps, SizeOf(midicaps));
  MidiDevice := MIDI_MAPPER;

  // First try midi mapper
  rc := midiOutGetDevCaps(MidiDevice, @midicaps, SizeOf(midicaps));
  if rc <> MMSYSERR_NOERROR then
    I_Error('I_InitMusic(): midiOutGetDevCaps failed, return value = %d', [rc]);

  // midiStreamOut not supported (should not happen with MIDI MAPPER...)
  // Try to enumurate all midi devices
  if (midicaps.dwSupport and MIDICAPS_STREAM) = 0 then
  begin
    numdev := midiOutGetNumDevs;
    if numdev = 0 then // fatal
      exit;

    for i := -1 to numdev - 1 do
    begin
      rc := midiOutGetDevCaps(i, @midicaps, SizeOf(midicaps));
      if rc <> MMSYSERR_NOERROR then
        I_Error('I_InitMusic(): midiOutGetDevCaps failed, return value = %d', [rc]);

      if (midicaps.dwSupport and MIDICAPS_STREAM) <> 0 then
      begin
        MidiDevice := i;
        break;
      end;
    end;
  end;

  if MidiDevice = MIDI_MAPPER then
    printf('Using midi mapper' + #13#10)
  else
    printf('Using midi device %d' + #13#10, [MidiDevice]);

  rc := midiStreamOpen(@hMidiStream, @MidiDevice, 1, 0, 0, CALLBACK_NULL);
  if rc <> MMSYSERR_NOERROR then
  begin
    hMidiStream := 0;
    printf('I_InitMusic(): midiStreamOpen failed, result = %d' + #13#10, [rc]);
  end;
  started := False;
end;

procedure I_InitMusic;
begin
  I_InitMus;
end;



// I_StopMusic

procedure I_StopMusicMus(song: Psonginfo_t);
var
  i: integer;
  rc: MMRESULT;
begin
  if not (boolval(song) and boolval(hMidiStream)) then
    exit;

  loopsong := False;
  rc := midiOutReset(HMIDIOUT(hMidiStream));
  if rc <> MMSYSERR_NOERROR then
    printf('I_StopMusic(): midiOutReset failed, result = %d' + #13#10, [rc]);

  started := False;

  for i := 0 to NUMMIDIHEADERS - 1 do
  begin
    if boolval(song.header[i].lpData) then
    begin
      rc := midiOutUnprepareHeader(HMIDIOUT(hMidiStream), @song.header[i],
        SizeOf(midiheader_t));
      if rc <> MMSYSERR_NOERROR then
        printf('I_StopMusic(): midiOutUnprepareHeader failed, result = %d' +
          #13#10, [rc]);

      song.header[i].lpData := nil;
      song.header[i].dwFlags := MHDR_DONE or MHDR_ISSTRM;
    end;
  end;
  song.nextevent := 0;
end;

procedure I_StopMusic(song: Psonginfo_t);
begin
  case m_type of
    m_midi: I_StopMidi;
    m_mus: I_StopMusicMus(song);
  end;
end;

procedure I_StopMus;
var
  rc: MMRESULT;
begin
  if hMidiStream <> 0 then
  begin
    rc := midiStreamStop(hMidiStream);
    if rc <> MMSYSERR_NOERROR then
      printf('I_ShutdownMusic(): midiStreamStop failed, result = %d' + #13#10, [rc]);

    started := False;
    rc := midiStreamClose(hMidiStream);
    if rc <> MMSYSERR_NOERROR then
      printf('I_ShutdownMusic(): midiStreamClose failed, result = %d' + #13#10, [rc]);

    hMidiStream := 0;
  end;
end;


// I_ShutdownMusic

procedure I_ShutdownMusic;
begin
  I_StopMus;
  I_StopMidi;
  fdelete(MidiFileName);
end;


// I_PlaySong

procedure I_PlaySong(handle: integer; looping: boolean);
begin
  if not (boolval(handle) and boolval(hMidiStream)) then
    exit;
  loopsong := looping;
  CurrentSong := Psonginfo_t(handle);
end;


// I_PauseSong

procedure I_PauseSongMus(handle: integer);
var
  rc: MMRESULT;
begin
  if hMidiStream = 0 then
    exit;

  rc := midiStreamPause(hMidiStream);
  if rc <> MMSYSERR_NOERROR then
    I_Error('I_PauseSong(): midiStreamRestart failed, return value = %d', [rc]);
end;

procedure I_PauseSong(handle: integer);
begin
  case m_type of
    m_midi: I_PauseMidi;
    m_mus: I_PauseSongMus(handle);
  end;
end;


// I_ResumeSong

procedure I_ResumeSongMus(handle: integer);
var
  rc: MMRESULT;
begin
  if hMidiStream = 0 then
    exit;

  rc := midiStreamRestart(hMidiStream);
  if rc <> MMSYSERR_NOERROR then
    I_Error('I_ResumeSong(): midiStreamRestart failed, return value = %d', [rc]);
end;

procedure I_ResumeSong(handle: integer);
begin
  case m_type of
    m_midi: I_ResumeMidi;
    m_mus: I_ResumeSongMus(handle);
  end;
end;

// Stops a song over 3 seconds.
procedure I_StopSong(handle: integer);
var
  song: Psonginfo_t;
begin
  if not (boolval(handle) and boolval(hMidiStream)) then
    exit;

  song := Psonginfo_t(handle);

  I_StopMusic(song);

  if song = CurrentSong then
    CurrentSong := nil;
end;

procedure I_UnRegisterSong(handle: integer);
var
  song: Psonginfo_t;
begin
  if not (boolval(handle) and boolval(hMidiStream)) then
    exit;

  I_StopSong(handle);

  song := Psonginfo_t(handle);
  Z_Free(song.midievents);
  Z_Free(song);
end;

function I_RegisterSong(Data: pointer; size: integer): integer;
var
  song: Psonginfo_t;
  i: integer;
  f: file;
begin
  song := Z_Malloc(SizeOf(songinfo_t), PU_STATIC, nil);
  song.numevents := GetSongLength(PByteArray(Data));
  song.nextevent := 0;
  song.midievents := Z_Malloc(song.numevents * SizeOf(MidiEvent_t), PU_STATIC, nil);

  if m_type = m_midi then
    I_StopMidi;

  if I_MusToMidi(PByteArray(Data), song.midievents) then
  begin
    I_InitMus;
    m_type := m_mus;

    if hMidiStream = 0 then
    begin
      printf('I_RegisterSong(): Could not initialize midi stream' + #13#10);
      m_type := m_none;
      Result := 0;
      exit;
    end;

    for i := 0 to NUMMIDIHEADERS - 1 do
    begin
      song.header[i].lpData := nil;
      song.header[i].dwFlags := MHDR_ISSTRM or MHDR_DONE;
    end;
  end
  else
  begin
    if m_type <> m_midi then
    begin
      I_StopMus;
      m_type := m_midi;
    end;

    if M_CheckParmCDROM then
      MidiFileName := 'c:\doomdata\doom32.mid'
    else
      MidiFileName := 'doom32.mid';

    Assign(f, MidiFileName);
    {$I-}
    rewrite(f, 1);
    BlockWrite(f, Data^, size);
    Close(f);
    {$I+}
    if IOResult <> 0 then
    begin
      printf('I_RegisterSong(): Could not initialize MCI' + #13#10);
      m_type := m_none;
      Result := 0;
      exit;
    end;
    I_PlayMidi;
  end;
  Result := integer(song);
end;

// Is the song playing?
function I_QrySongPlaying(handle: integer): boolean;
begin
  result := CurrentSong <> nil;
end;


// I_SetMusicVolume

procedure I_SetMusicVolumeMus(volume: integer);
var
  rc: MMRESULT;
begin
  snd_MusicVolume := volume;
  // Now set volume on output device.
  // Whatever( snd_MusciVolume );
  if boolval(CurrentSong) and (snd_MusicVolume = 0) and started then
    I_StopMusic(CurrentSong);

  if (midicaps.dwSupport and MIDICAPS_VOLUME) <> 0 then
  begin
    rc := midiOutSetVolume(hMidiStream, _SHLW($FFFF * snd_MusicVolume div 16, 16) or
      _SHLW(($FFFF * snd_MusicVolume div 16), 0));
    if rc <> MMSYSERR_NOERROR then
      printf('I_SetMusicVolume(): midiOutSetVolume failed, return value = %d' +
        #13#10, [rc]);
  end
  else
    printf('I_SetMusicVolume(): Midi device does not support volume control' + #13#10);
end;

procedure I_SetMusicVolume(volume: integer);
begin
  case m_type of
    m_midi: ; // unsupported
    m_mus: I_SetMusicVolumeMus(volume);
  end;
end;

procedure I_ProcessMusic;
var
  header: Pmidiheader_t;
  length: integer;
  i: integer;
  rc: MMRESULT;
begin
  if m_type <> m_mus then
    exit;

  if (snd_MusicVolume = 0) or (not boolval(CurrentSong)) then
    exit;

  for i := 0 to NUMMIDIHEADERS - 1 do
  begin
    header := @CurrentSong.header[i];
    if boolval(header.dwFlags and MHDR_DONE) then
    begin
      if boolval(header.lpData) then
      begin
        rc := midiOutUnprepareHeader(HMIDIOUT(hMidiStream), PMidiHdr(header),
          SizeOf(midiheader_t));
        if rc <> MMSYSERR_NOERROR then
          printf('I_ProcessMusic(): midiOutUnprepareHeader failed, result = %d' +
            #13#10, [rc]);
      end;
      header.lpData := @CurrentSong.midievents[CurrentSong.nextevent];
      length := CurrentSong.numevents - CurrentSong.nextevent;
      if length > MAX_MIDI_EVENTS then
      begin
        length := MAX_MIDI_EVENTS;
        CurrentSong.nextevent := CurrentSong.nextevent + MAX_MIDI_EVENTS;
      end
      else
        CurrentSong.nextevent := 0;
      length := length * SizeOf(MidiEvent_t);
      header.dwBufferLength := length;
      header.dwBytesRecorded := length;
      header.dwFlags := MHDR_ISSTRM;
      rc := midiOutPrepareHeader(HMIDIOUT(hMidiStream), PMidiHdr(header),
        SizeOf(midiheader_t));
      if rc <> MMSYSERR_NOERROR then
        I_Error('I_ProcessMusic(): midiOutPrepareHeader failed, return value = %d',
          [rc]);
      if not started then
      begin
        rc := midiStreamRestart(hMidiStream);
        if rc <> MMSYSERR_NOERROR then
          I_Error('I_ProcessMusic(): midiStreamRestart failed, return value = %d', [rc]);
        started := True;
      end;
      rc := midiStreamOut(hMidiStream, PMidiHdr(header), SizeOf(midiheader_t));
      if rc <> MMSYSERR_NOERROR then
        I_Error('I_ProcessMusic(): midiStreamOut failed, return value = %d', [rc]);
    end;
  end;
end;

end.
