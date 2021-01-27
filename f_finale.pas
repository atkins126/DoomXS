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

unit f_finale;

interface

uses
  doomtype,
  d_event;

function F_Responder(ev: Pevent_t): boolean;

{ Called by main loop. }
procedure F_Ticker;

{ Called by main loop. }
procedure F_Drawer;

procedure F_StartFinale;

implementation

uses
  d_delphi,
  am_map,
  d_player,
  d_main,
  g_game,
  info_h,
  info,
  p_pspr,
  r_data,
  r_defs,
  r_things,
// Functions.
  i_system,
  z_memory,
  v_video,
  w_wad,
  s_sound,
// Data.
  dstrings,
  d_englsh,
  sounds,
  doomdef,
  doomstat,
  hu_stuff;

var
// Stage of animation:
//  0 = text, 1 = art screen, 2 = character cast
  finalestage: integer;

  finalecount: integer;

const
  TEXTSPEED = 3;
  TEXTWAIT = 250;

var
  finaletext: string;
  finaleflat: string;

procedure F_StartCast; forward;

procedure F_CastTicker; forward;

function F_CastResponder(ev: Pevent_t): boolean; forward;

procedure F_CastDrawer; forward;

procedure F_StartFinale;
begin
  gameaction := ga_nothing;
  gamestate := GS_FINALE;
  viewactive := false;
  automapactive := false;

  // Okay - IWAD dependend stuff.
  // This has been changed severly, and
  //  some stuff might have changed in the process.
  case gamemode of
    // DOOM 1 - E1, E3 or E4, but each nine missions
    shareware,
    registered,
    retail:
      begin
        S_ChangeMusic(Ord(mus_victor), true);
        case gameepisode of
          1:
            begin
              finaleflat := 'FLOOR4_8';
              finaletext := E1TEXT;
            end;
          2:
            begin
              finaleflat := 'SFLR6_1';
              finaletext := E2TEXT;
            end;
          3:
            begin
              finaleflat := 'MFLR8_4';
              finaletext := E3TEXT;
            end;
          4:
            begin
              finaleflat := 'MFLR8_3';
              finaletext := E4TEXT;
            end;
        else
          // Ouch.
        end;
      end;
    // DOOM II and missions packs with E1, M34
    commercial:
      begin
        S_ChangeMusic(Ord(mus_read_m), true);
        case gamemap of
          6:
            begin
              finaleflat := 'SLIME16';
              finaletext := C1TEXT;
            end;
         11:
            begin
              finaleflat := 'RROCK14';
              finaletext := c2text;
            end;
         20:
            begin
              finaleflat := 'RROCK07';
              finaletext := C3TEXT;
            end;
         30:
            begin
              finaleflat := 'RROCK17';
              finaletext := C4TEXT;
            end;
         15:
            begin
              finaleflat := 'RROCK13';
              finaletext := C5TEXT;
            end;
         31:
            begin
              finaleflat := 'RROCK19';
              finaletext := C6TEXT;
            end;
        else
        // Ouch.
        end;
      end;
  else
    begin
      S_ChangeMusic(Ord(mus_read_m), true);
      finaleflat := 'F_SKY1'; // Not used anywhere else.
      finaletext := C1TEXT;   // FIXME - other text, music?
    end;
  end;
  finalestage := 0;
  finalecount := 0;
end;

function F_Responder(ev: Pevent_t): boolean;
begin
  result := false;
  if finalestage = 2 then
    result := F_CastResponder(ev);
end;

//
// F_Ticker
//
procedure F_Ticker;
var
  i: integer;
begin
  // check for skipping
  if (gamemode = commercial) and (finalecount > 50) then
  begin
    // go on to the next level
    i := 0;
    while i < MAXPLAYERS do
    begin
      if players[i].cmd.buttons <> 0 then
        break;
      inc(i);
    end;
    if i < MAXPLAYERS then
    begin
      if gamemap = 30 then
        F_StartCast
      else
        gameaction := ga_worlddone;
    end;
  end;

  // advance animation
  inc(finalecount);

  if finalestage = 2 then
  begin
    F_CastTicker;
    exit;
  end;

  if gamemode = commercial then
    exit;

  if (finalestage = 0) and (finalecount > Length(finaletext) * TEXTSPEED + TEXTWAIT) then
  begin
    finalecount := 0;
    finalestage := 1;
    wipegamestate := -1;    // force a wipe
    if gameepisode = 3 then
      S_StartMusic(Ord(mus_bunny));
  end;
end;

procedure F_TextWrite;
var
  src: PByteArray;
  dest: integer;
  x, y, w: integer;
  count: integer;
  ch: string;
  c: char;
  c1: integer;
  i: integer;
  len: integer;
  cx: integer;
  cy: integer;
  dstscr: integer;
begin
  // erase the entire screen to a tiled background
  src := W_CacheLumpName(finaleflat, PU_CACHE);
  dest := 0;
  dstscr := SCN_SCRF;

  for y := 0 to 200 - 1 do
  begin
    for x := 0 to (320 div 64) - 1 do
    begin
      memcpy(@screens[dstscr, dest], @src[_SHL(y and 63, 6)], 64);
      dest := dest + 64;
    end;

    if (320 and 63) <> 0 then
    begin
      memcpy(@screens[dstscr, dest], @src[_SHL(y and 63, 6)], 320 and 63);
      dest := dest + (320 and 63);
    end;
  end;

  // draw some of the text onto the screen
  cx := 10;
  cy := 10;
  ch := finaletext;
  len := Length(ch);

  count := (finalecount - 10) div TEXTSPEED;
  if count < 0 then
    count := 0;

  i := 1;
  while count > 0 do
  begin

    if i > len then
      break;

    c := ch[i];
    inc(i);
    if c = #13 then
    begin
      cy := cy + 11;
      continue;
    end;
    if c = #10 then
    begin
      cx := 10;
      continue;
    end;

    c1 := Ord(toupper(c)) - Ord(HU_FONTSTART);
    if (c1 < 0) or (c1 > HU_FONTSIZE) then
    begin
      cx := cx + 4;
      continue;
    end;

    w := hu_font[c1].width;
    if cx + w > 320 then
      break;
    V_DrawPatch(cx, cy, dstscr, hu_font[c1], false);
    cx := cx + w;
    dec(count);
  end;
  V_CopyRect(0, 0, SCN_SCRF, 320, 200, 0, 0, SCN_FG, true);
end;

//
// Final DOOM 2 animation
// Casting by id Software.
//   in order of appearance
//
type
  castinfo_t = record
    name: string;
    _type: mobjtype_t;
  end;
  Pcastinfo_t = ^castinfo_t;

const
  NUM_CASTS = 18;

var
  castorder: array[0..NUM_CASTS - 1] of castinfo_t;

  castnum: integer;
  casttics: integer;
  caststate: Pstate_t;
  castdeath: boolean;
  castframes: integer;
  castonmelee: integer;
  castattacking: boolean;

//
// F_StartCast
//
procedure F_StartCast;
begin
  wipegamestate := -1;    // force a screen wipe
  castnum := 0;
  caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].seestate];
  casttics := caststate.tics;
  castdeath := false;
  finalestage := 2;
  castframes := 0;
  castonmelee := 0;
  castattacking := false;
  S_ChangeMusic(Ord(mus_evil), true);
end;

//
// F_CastTicker
//
procedure F_CastTicker;
var
  st: integer;
  sfx: integer;
begin
  dec(casttics);
  if casttics > 0 then
    exit; // not time to change state yet

  if (caststate.tics = -1) or (caststate.nextstate = S_NULL) then
  begin
    // switch from deathstate to next monster
    inc(castnum);
    castdeath := false;
    if castorder[castnum].name = '' then
      castnum := 0;
    if mobjinfo[Ord(castorder[castnum]._type)].seesound <> 0 then
      S_StartSound(nil, mobjinfo[Ord(castorder[castnum]._type)].seesound);
    caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].seestate];
    castframes := 0;
  end
  else
  begin
  // just advance to next state in animation
    if caststate = @states[Ord(S_PLAY_ATK1)] then
    begin
      castattacking := false;
      castframes := 0;
      caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].seestate];
      casttics := caststate.tics;
      if casttics = -1 then
        casttics := 15;
      exit;
    end;
    st := Ord(caststate.nextstate);
    caststate := @states[st];
    inc(castframes);

    // sound hacks....
    case statenum_t(st) of
      S_PLAY_ATK1: sfx := Ord(sfx_dshtgn);
      S_POSS_ATK2: sfx := Ord(sfx_pistol);
      S_SPOS_ATK2: sfx := Ord(sfx_shotgn);
      S_VILE_ATK2: sfx := Ord(sfx_vilatk);
      S_SKEL_FIST2: sfx := Ord(sfx_skeswg);
      S_SKEL_FIST4: sfx := Ord(sfx_skepch);
      S_SKEL_MISS2: sfx := Ord(sfx_skeatk);
      S_FATT_ATK8,
      S_FATT_ATK5,
      S_FATT_ATK2: sfx := Ord(sfx_firsht);
      S_CPOS_ATK2,
      S_CPOS_ATK3,
      S_CPOS_ATK4: sfx := Ord(sfx_shotgn);
      S_TROO_ATK3: sfx := Ord(sfx_claw);
      S_SARG_ATK2: sfx := Ord(sfx_sgtatk);
      S_BOSS_ATK2,
      S_BOS2_ATK2,
      S_HEAD_ATK2: sfx := Ord(sfx_firsht);
      S_SKULL_ATK2: sfx := Ord(sfx_sklatk);
      S_SPID_ATK2,
      S_SPID_ATK3: sfx := Ord(sfx_shotgn);
      S_BSPI_ATK2: sfx := Ord(sfx_plasma);
      S_CYBER_ATK2,
      S_CYBER_ATK4,
      S_CYBER_ATK6: sfx := Ord(sfx_rlaunc);
      S_PAIN_ATK3: sfx := Ord(sfx_sklatk);
    else
      sfx := 0;
    end;
    if sfx <> 0 then
      S_StartSound(nil, sfx);
  end;

  if castframes = 12 then
  begin
    // go into attack frame
    castattacking := true;
    if castonmelee <> 0 then
      caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].meleestate]
    else
      caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].missilestate];
    castonmelee := castonmelee xor 1;
    if caststate = @states[Ord(S_NULL)] then
    begin
      if castonmelee <> 0 then
        caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].meleestate]
      else
        caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].missilestate];
    end;
  end;

  if castattacking then
  begin
    if (castframes = 24) or
       (caststate = @states[mobjinfo[Ord(castorder[castnum]._type)].seestate]) then
    begin
      castattacking := false;
      castframes := 0;
      caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].seestate];
    end;
  end;

  casttics := caststate.tics;
  if casttics = -1 then
    casttics := 15;
end;

//
// F_CastResponder
//
function F_CastResponder(ev: Pevent_t): boolean;
begin
  if ev._type <> ev_keydown then
  begin
    result := false;
    exit;
  end;

  if castdeath then
  begin
    result := true; // already in dying frames
    exit;
  end;

  // go into death frame
  castdeath := true;
  caststate := @states[mobjinfo[Ord(castorder[castnum]._type)].deathstate];
  casttics := caststate.tics;
  castframes := 0;
  castattacking := false;
  if mobjinfo[Ord(castorder[castnum]._type)].deathsound <> 0 then
    S_StartSound(nil, mobjinfo[Ord(castorder[castnum]._type)].deathsound);

  result := true;
end;

procedure F_CastPrint(text: string);
var
  ch: string;
  i: integer;
  c: char;
  c1: integer;
  len: integer;
  cx: integer;
  w: integer;
  width: integer;
begin
  // find width
  ch := text;
  width := 0;

  len := Length(ch);
  for i := 1 to len do
  begin
    c := ch[i];
    if c = #0 then
      break;
    c1 := Ord(toupper(c)) - Ord(HU_FONTSTART);
    if (c1 < 0) or (c1 > HU_FONTSIZE) then
      width := width + 4
    else
    begin
      w := hu_font[c1].width;
      width := width + w;
    end;
  end;

  // draw it
  cx := (320 - width) div 2;
  for i := 1 to len do
  begin
    c := ch[i];
    if c = #0 then
      break;
    c1 := Ord(toupper(c)) - Ord(HU_FONTSTART);
    if (c1 < 0) or (c1 > HU_FONTSIZE) then
      cx := cx + 4
    else
    begin
      w := hu_font[c1].width;
      V_DrawPatch(cx, 180, 0, hu_font[c1], true);
      cx := cx + w;
    end;
  end;
end;

//
// F_CastDrawer
//
procedure F_CastDrawer;
var
  sprdef: Pspritedef_t;
  sprframe: Pspriteframe_t;
  lump: integer;
  flip: boolean;
  patch: Ppatch_t;
begin
  // erase the entire screen to a background
  V_DrawPatch(0, 0, 0, W_CacheLumpName('BOSSBACK', PU_CACHE), true);

  F_CastPrint(castorder[castnum].name);

  // draw the current frame in the middle of the screen
  sprdef := @sprites[Ord(caststate.sprite)];
  sprframe := @sprdef.spriteframes[caststate.frame and FF_FRAMEMASK];
  lump := sprframe.lump[0];
  flip := boolean(sprframe.flip[0]);

  patch := W_CacheLumpNum(lump + firstspritelump, PU_CACHE);
  if flip then
    V_DrawPatchFlipped(160, 170, 0, patch, true)
  else
    V_DrawPatch(160, 170, 0, patch, true);
end;

//
// F_DrawPatchCol
//
procedure F_DrawPatchCol(scr: integer; x: integer; patch: Ppatch_t; col: integer);
var
  column: Pcolumn_t;
  source: PByte;
  dest: PByte;
  desttop: PByte;
  count: integer;
begin
  column := Pcolumn_t(integer(patch) + patch.columnofs[col]);
  desttop := PByte(integer(screens[scr]) + x);

  // step through the posts in a column
  while column.topdelta <> $ff do
  begin
    source := PByte(integer(column) + 3);
    dest := PByte(integer(desttop) + column.topdelta * 320);
    count := column.length;

    while count > 0 do
    begin
      dest^ := source^;
      inc(source);
      inc(dest, 320);
      dec(count);
    end;
    column := Pcolumn_t(integer(column) + column.length + 4);
  end;
end;

//
// F_BunnyScroll
//
var
  laststage: integer = 0;

procedure F_BunnyScroll;
var
  scrolled: integer;
  x: integer;
  p1: Ppatch_t;
  p2: Ppatch_t;
  name: string;
  stage: integer;
  dstscr: integer;
begin
  p1 := W_CacheLumpName('PFUB2', PU_LEVEL);
  p2 := W_CacheLumpName('PFUB1', PU_LEVEL);

  dstscr := SCN_SCRF;

  scrolled := 320 - (finalecount - 230) div 2;
  if scrolled > 320 then
    scrolled := 320
  else if scrolled < 0 then
    scrolled := 0;

  for x := 0 to 320 - 1 do
  begin
    if x + scrolled < 320 then
      F_DrawPatchCol(dstscr, x, p1, x + scrolled)
    else
      F_DrawPatchCol(dstscr, x, p2, x + scrolled - 320);
  end;

  if finalecount >= 1130 then
  begin
    if finalecount < 1180 then
    begin
      V_DrawPatch((320 - 13 * 8) div 2,
                  (200 - 8 * 8) div 2,
                   dstscr, W_CacheLumpName('END0', PU_CACHE), false);
      laststage := 0;
    end
    else
    begin
      stage := (finalecount - 1180) div 5;
      if stage > 6 then
        stage := 6;
      if stage > laststage then
      begin
        S_StartSound(nil, Ord(sfx_pistol));
        laststage := stage;
      end;

      sprintf(name,'END%d', [stage]);
      V_DrawPatch((320 - 13 * 8) div 2,
                  (200 - 8 * 8) div 2,
                   dstscr, W_CacheLumpName(name, PU_CACHE), false);
    end;
  end;

  V_CopyRect(0, 0, SCN_SCRF, 320, 200, 0, 0, SCN_FG, true);
end;

//
// F_Drawer
//
procedure F_Drawer;
begin
  if finalestage = 2 then
  begin
    F_CastDrawer;
    exit;
  end;

  if finalestage = 0 then
    F_TextWrite
  else
  begin
    case gameepisode of
      1:
        begin
          if gamemode = retail then
            V_DrawPatch(0, 0, 0,
              W_CacheLumpName('CREDIT', PU_CACHE), true)
          else
            V_DrawPatch(0, 0, 0,
              W_CacheLumpName('HELP2', PU_CACHE), true);
        end;
      2:
        begin
          V_DrawPatch(0, 0, 0,
            W_CacheLumpName('VICTORY2', PU_CACHE), true);
        end;
      3:
        begin
          F_BunnyScroll;
        end;
      4:
        begin
          V_DrawPatch(0, 0, 0,
            W_CacheLumpName('ENDPIC', PU_CACHE), true);
        end;
    end;
  end;
end;

initialization
  castorder[0].name := CC_ZOMBIE;
  castorder[0]._type := MT_POSSESSED;

  castorder[1].name := CC_SHOTGUN;
  castorder[1]._type := MT_SHOTGUY;

  castorder[2].name := CC_HEAVY;
  castorder[2]._type := MT_CHAINGUY;

  castorder[3].name := CC_IMP;
  castorder[3]._type := MT_TROOP;

  castorder[4].name := CC_DEMON;
  castorder[4]._type := MT_SERGEANT;

  castorder[5].name := CC_LOST;
  castorder[5]._type := MT_SKULL;

  castorder[6].name := CC_CACO;
  castorder[6]._type := MT_HEAD;

  castorder[7].name := CC_HELL;
  castorder[7]._type := MT_KNIGHT;

  castorder[8].name := CC_BARON;
  castorder[8]._type := MT_BRUISER;

  castorder[9].name := CC_ARACH;
  castorder[9]._type := MT_BABY;

  castorder[10].name := CC_PAIN;
  castorder[10]._type := MT_PAIN;

  castorder[11].name := CC_REVEN;
  castorder[11]._type := MT_UNDEAD;

  castorder[12].name := CC_MANCU;
  castorder[12]._type := MT_FATSO;

  castorder[13].name := CC_ARCH;
  castorder[13]._type := MT_VILE;

  castorder[14].name := CC_SPIDER;
  castorder[14]._type := MT_SPIDER;

  castorder[15].name := CC_CYBER;
  castorder[15]._type := MT_CYBORG;

  castorder[16].name := CC_HERO;
  castorder[16]._type := MT_PLAYER;

  castorder[17].name := '';
  castorder[17]._type := mobjtype_t(0);

end.

