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

unit p_plats;

interface

uses
  i_system,
  z_memory,
  m_rnd,
  doomdef,
  p_spec,
  p_local,
  r_defs,
  s_sound,
  // State.
  doomstat,
  // Data.
  sounds;

var
  activeplats: array[0..MAXPLATS - 1] of Pplat_t;

procedure T_PlatRaise(plat: Pplat_t);

function EV_DoPlat(line: Pline_t; _type: plattype_e; amount: integer): integer;

procedure P_ActivateInStasis(tag: integer);

procedure EV_StopPlat(line: Pline_t);

procedure P_AddActivePlat(plat: Pplat_t);

procedure P_RemoveActivePlat(plat: Pplat_t);

implementation

uses
  d_delphi,
  m_fixed,
  p_mobj_h,
  p_tick,
  p_setup,
  p_floor;

procedure T_PlatRaise(plat: Pplat_t);
var
  res: result_e;
begin
  case plat.status of
    up:
    begin
      res := T_MovePlane(plat.sector, plat.speed, plat.high, plat.crush, 0, 1);

      if (plat._type = raiseAndChange) or (plat._type = raiseToNearestAndChange) then
      begin
          if leveltime and 7 = 0 then
          S_StartSound(Pmobj_t(@plat.sector.soundorg), Ord(sfx_stnmov));
      end;

      if (res = crushed) and (not plat.crush) then
      begin
        plat.count := plat.wait;
        plat.status := down;
        S_StartSound(Pmobj_t(@plat.sector.soundorg), Ord(sfx_pstart));
      end
      else
      begin
        if res = pastdest then
        begin
          plat.count := plat.wait;
          plat.status := waiting;
          S_StartSound(Pmobj_t(@plat.sector.soundorg), Ord(sfx_pstop));

          case plat._type of
            blazeDWUS,
            downWaitUpStay:
              P_RemoveActivePlat(plat);
            raiseAndChange,
            raiseToNearestAndChange:
              P_RemoveActivePlat(plat);
          end;
        end;
      end;
    end;

    down:
    begin
      res := T_MovePlane(plat.sector, plat.speed, plat.low, False, 0, -1);

      if res = pastdest then
      begin
        plat.count := plat.wait;
        plat.status := waiting;
        S_StartSound(Pmobj_t(@plat.sector.soundorg), Ord(sfx_pstop));
      end;
    end;
    waiting:
    begin
      plat.count := plat.count - 1;
        if plat.count = 0 then
      begin
        if plat.sector.floorheight = plat.low then
          plat.status := up
        else
          plat.status := down;
        S_StartSound(Pmobj_t(@plat.sector.soundorg), Ord(sfx_pstart));
      end;
    end;
  end;
end;


// Do Platforms
//  "amount" is only used for SOME platforms.

function EV_DoPlat(line: Pline_t; _type: plattype_e; amount: integer): integer;
var
  plat: Pplat_t;
  secnum: integer;
  sec: Psector_t;
begin
  Result := 0;

  //  Activate all <type> plats that are in_stasis
  if _type = perpetualRaise then
    P_ActivateInStasis(line.tag);

  secnum := P_FindSectorFromLineTag(line, -1);
  while secnum >= 0 do
  begin
    sec := @sectors[secnum];
    secnum := P_FindSectorFromLineTag(line, secnum);

    if sec.specialdata <> nil then
      continue;

    // Find lowest & highest floors around sector
    Result := 1;
    plat := Z_Malloc(SizeOf(plat_t), PU_LEVSPEC, nil);
    P_AddThinker(@plat.thinker);

    plat._type := _type;
    plat.sector := sec;
    plat.sector.specialdata := plat;
    plat.thinker._function.acp1 := @T_PlatRaise;
    plat.crush := False;
    plat.tag := line.tag;

    case _type of
      raiseToNearestAndChange:
      begin
        plat.speed := PLATSPEED div 2;
        sec.floorpic := sides[line.sidenum[0]].sector.floorpic;
        plat.high := P_FindNextHighestFloor(sec, sec.floorheight);
        plat.wait := 0;
        plat.status := up;
        // NO MORE DAMAGE, IF APPLICABLE
        sec.special := 0;
        S_StartSound(Pmobj_t(@sec.soundorg), Ord(sfx_stnmov));
      end;

      raiseAndChange:
      begin
        plat.speed := PLATSPEED div 2;
        sec.floorpic := sides[line.sidenum[0]].sector.floorpic;
        plat.high := sec.floorheight + amount * FRACUNIT;
        plat.wait := 0;
        plat.status := up;
        S_StartSound(Pmobj_t(@sec.soundorg), Ord(sfx_stnmov));
      end;
      downWaitUpStay:
      begin
        plat.speed := PLATSPEED * 4;
        plat.low := P_FindLowestFloorSurrounding(sec);
        if plat.low > sec.floorheight then
          plat.low := sec.floorheight;
        plat.high := sec.floorheight;
        plat.wait := TICRATE * PLATWAIT;
        plat.status := down;
        S_StartSound(Pmobj_t(@sec.soundorg), Ord(sfx_pstart));
      end;
      blazeDWUS:
      begin
        plat.speed := PLATSPEED * 8;
        plat.low := P_FindLowestFloorSurrounding(sec);
        if plat.low > sec.floorheight then
          plat.low := sec.floorheight;
        plat.high := sec.floorheight;
        plat.wait := TICRATE * PLATWAIT;
        plat.status := down;
        S_StartSound(Pmobj_t(@sec.soundorg), Ord(sfx_pstart));
      end;
      perpetualRaise:
      begin
        plat.speed := PLATSPEED;
        plat.low := P_FindLowestFloorSurrounding(sec);
        if plat.low > sec.floorheight then
          plat.low := sec.floorheight;
        plat.high := P_FindHighestFloorSurrounding(sec);
        if plat.high < sec.floorheight then
          plat.high := sec.floorheight;
        plat.wait := TICRATE * PLATWAIT;
        plat.status := plat_e(P_Random and 1);
        S_StartSound(Pmobj_t(@sec.soundorg), Ord(sfx_pstart));
      end;
    end;
    P_AddActivePlat(plat);
  end;
end;

procedure P_ActivateInStasis(tag: integer);
var
  i: integer;
begin
  for i := 0 to MAXPLATS - 1 do
    if (activeplats[i] <> nil) and (activeplats[i].tag = tag) and
      (activeplats[i].status = in_stasis) then
    begin
      activeplats[i].status := activeplats[i].oldstatus;
      activeplats[i].thinker._function.acp1 := @T_PlatRaise;
    end;
end;


procedure EV_StopPlat(line: Pline_t);
var
  i: integer;
begin
  for i := 0 to MAXPLATS - 1 do
    if (activeplats[i] <> nil) and (activeplats[i].status <> in_stasis) and


      (activeplats[i].tag = line.tag) then
    begin
      activeplats[i].oldstatus := activeplats[i].status;
      activeplats[i].status := in_stasis;
      activeplats[i].thinker._function.acv := nil;
    end;
end;

procedure P_AddActivePlat(plat: Pplat_t);
var
  i: integer;
begin
  for i := 0 to MAXPLATS - 1 do
    if activeplats[i] = nil then
    begin
      activeplats[i] := plat;
      exit;
    end;

  I_Error('P_AddActivePlat(): no more plats!');
end;

procedure P_RemoveActivePlat(plat: Pplat_t);
var
  i: integer;
begin
  for i := 0 to MAXPLATS - 1 do
    if plat = activeplats[i] then
    begin
      activeplats[i].sector.specialdata := nil;
      P_RemoveThinker(@activeplats[i].thinker);
      activeplats[i] := nil;
      exit;
    end;

  I_Error('P_RemoveActivePlat(): can''t find plat!');
end;

end.
