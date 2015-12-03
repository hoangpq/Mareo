open Sprite
open Actors

let friction = 0.8
let gravity = 0.1
let player_speed = 3.
let dampen_jump = 2.
let invuln = 20

type xy = {
  mutable x: float;
  mutable y: float;
}


type aabb = {
  center: xy;
  half: xy;
}

type obj_params = {
  has_gravity: bool;
  speed: float;
}

let id_counter = ref min_int

type obj = {
  params: obj_params;
  pos: xy;
  vel: xy;
  id: int;
  mutable jumping: bool;
  mutable grounded: bool;
  mutable dir: Actors.dir_1d;
  mutable invuln: int;
  mutable kill: bool;
}

type collidable =
  | Player of sprite * obj
  | Enemy of enemy_typ * sprite * obj
  | Item of item_typ * sprite * obj
  | Block of block_typ * sprite * obj

type noncollidable =
  (*| Dead of dead_type * sprite*)
  | Scenery of sprite * obj

let setup_obj ?anim:(anim=true) ?g:(has_gravity=true) ?spd:(speed=1.) () =
  {
    has_gravity;
    speed;
  }

(* Sets an object's x velocity to the speed specified in its params based on
 * its direction *)
let set_vel_to_speed obj =
  let speed = obj.params.speed in
  match obj.dir with
  | Left -> obj.vel.x <- ~-.speed
  | Right -> obj.vel.x <- speed

let make_player () = setup_obj ~spd:player_speed ()

let make_item = function
  | Mushroom -> setup_obj ()
  | FireFlower -> setup_obj ()
  | Star -> setup_obj ()
  | Coin -> setup_obj ~g:false ()

let make_enemy = function
  | Goomba -> setup_obj ()
  | GKoopa -> setup_obj ()
  | RKoopa -> setup_obj ()
  | GKoopaShell -> setup_obj ~spd:5. ()
  | RKoopaShell -> setup_obj ~spd:5. ()

let make_block = function
  | QBlock i -> setup_obj ~g:false ()
  | QBlockUsed -> setup_obj ~g:false ()
  | Brick -> setup_obj ~g:false ()
  | UnBBlock -> setup_obj ~g:false ()

let make_type = function
  | SPlayer t -> make_player ()
  | SEnemy t -> make_enemy t
  | SItem t -> make_item t
  | SBlock t -> make_block t

let new_id () =
  id_counter := !id_counter + 1;
  !id_counter

let make ?id:(id=None) ?dir:(dir=Left) spawnable context (posx, posy) =
  let spr = Sprite.make spawnable dir context in
  let params = make_type spawnable in
  let id = match id with
    | None -> new_id ()
    | Some n -> n
  in
  let obj = {
    params;
    pos = {x=posx; y=posy};
    vel = {x=0.0;y=0.0};
    id;
    jumping = false;
    grounded = false;
    dir;
    invuln = 0;
    kill = false;
  } in
  (spr,obj)

let spawn spawnable context (posx, posy) =
  let (spr,obj) = make spawnable context (posx, posy) in
  match spawnable with
  | SPlayer t -> Player(spr,obj)
  | SEnemy t ->
      set_vel_to_speed obj;
      Enemy(t,spr,obj)
  | SItem t -> Item(t,spr,obj)
  | SBlock t -> Block(t,spr,obj)


let get_sprite = function
  | Player (s,_) | Enemy (_,s, _) | Item (_,s, _) | Block (_,s, _)  -> s

let get_obj = function
  | Player (_,o) | Enemy (_,_,o) | Item (_,_,o) | Block (_,_,o) -> o

let is_player = function
  | Player(_,_) -> true
  | _ -> false

let is_enemy = function
  | Enemy(_,_,_) -> true
  | _ -> false

let equals col1 col2 = (get_obj col1).id = (get_obj col2).id

let update_player_keys (player : obj) (controls : controls) : unit =
  match controls with
  | CLeft ->
    if player.vel.x > ~-.(player.params.speed)
    then player.vel.x <- player.vel.x;
    player.dir <- Left
  | CRight ->
    if player.vel.x < player.params.speed
    then player.vel.x <- player.vel.x;
    player.dir <- Right
  | CUp ->
    if (not player.jumping && player.grounded) then begin
      player.jumping <- true;
      player.grounded <- false;
      player.vel.y <- player.vel.y -.(player.params.speed)
    end
  | CDown ->
    if (not player.jumping) then print_endline "crouch"

let update_player player keys context =
  let prev_jumping = player.jumping in
  let prev_dir = player.dir in
  List.iter (update_player_keys player) keys;
  let v = player.vel.x *. friction in
  let vel_damped = if abs_float v < 0.1 then 0. else v in
  let () = player.vel.x <- vel_damped in
  if not prev_jumping && player.jumping
  then Some (Sprite.make (SPlayer Jumping) player.dir context)
  else if prev_dir <> player.dir && not player.jumping
  then Some (Sprite.make (SPlayer Running) player.dir context)
  else if prev_dir <> player.dir && player.jumping && prev_jumping
  then Some (Sprite.make (SPlayer Jumping) player.dir context)
  else if player.vel.y = 0. && player.vel.x = 0.
  then Some (Sprite.make (SPlayer Standing) player.dir context)
  else None

let update_vel obj =
  if obj.grounded then obj.vel.y <- 0.
  else if obj.params.has_gravity then obj.vel.y <- (obj.vel.y +. gravity)

let update_pos obj =
  obj.pos.x <- (obj.vel.x +. obj.pos.x);
  if obj.params.has_gravity then obj.pos.y <- (obj.vel.y +. obj.pos.y)

let process_obj obj =
  update_vel obj;
  update_pos obj
  (*todo kill if out of bounds *)
  (*match col with
  | Player(t,s,o) ->

  | Enemy(t,s,o) ->
  | Item(t,s,o) ->
  | Block(t,s,o) ->
*)

(* Converts an origin based on the bottom left of the bounding box to the top
 * right of the sprite, to make it easier to place objects flush with the ground.*)
let normalize_origin pos (spr:Sprite.sprite) =
  let p = spr.params in
  let (box,boy) = p.bbox_offset and (_,bh) = p.bbox_size in
  pos.x <- pos.x -. box;
  pos.y <- pos.y -. (boy +. bh)

let normalize_pos pos (oldspr:Sprite.sprite) (newspr:Sprite.sprite) =
    let p1 = oldspr.params and p2 = newspr.params in
    let (box1,boy1) = p1.bbox_offset and (box2,boy2) = p2.bbox_offset in
    let (bw1,bh1) = p1.bbox_size and (bw2,bh2) = p2.bbox_size in
    Printf.printf " %f %f " pos.x pos.y;
    pos.x <- pos.x -. (bw2 +. box2) +. (bw1 +. box1) -.1.;
    pos.y <- pos.y -. (bh2 +. boy2) +. (bh1 +. boy1) -.1.;
    Printf.printf " %f %f \n" pos.x pos.y

let collide_block ?check_x:(check_x=true) dir obj =
  match dir with
  | North -> obj.vel.y <- 0.
  | South ->
      obj.vel.y <- 0.;
      obj.grounded <- true;
      obj.jumping <- false;
  | East | West -> if check_x then obj.vel.x <- 0.

let reverse_left_right obj =
  obj.vel.x <- ~-.(obj.vel.x);
  obj.dir <-
    match obj.dir with
    | Left -> Right
    | Right -> Left

let evolve_enemy player_dir typ spr obj context =
  match typ with
  | GKoopa ->
      let (new_spr,new_obj) = make ~dir:obj.dir (SEnemy GKoopaShell) context (obj.pos.x,obj.pos.y) in
      normalize_pos new_obj.pos spr new_spr;
      Some(Enemy(GKoopaShell,new_spr,new_obj))
  | RKoopa ->
      let (new_spr,new_obj) = make ~dir:obj.dir (SEnemy RKoopaShell) context (obj.pos.x,obj.pos.y) in
      normalize_pos new_obj.pos spr new_spr;
      Some(Enemy(RKoopaShell,new_spr,new_obj))
  | GKoopaShell |RKoopaShell ->
      obj.dir <- player_dir;
      if obj.vel.x <> 0. then obj.vel.x <- 0. else set_vel_to_speed obj;
      None
  | _ -> obj.kill <- true; None

let process_collision dir c1 c2 context =
  match (c1, c2, dir) with
  | (Player(s1,o1), Enemy(typ,s2,o2), South)
  | (Enemy(typ,s2,o2),Player(s1,o1), North) ->
      o1.invuln <- invuln;
      o1.jumping <- false; 
      o2.kill <- true;
      o1.grounded <- true;
      o1.vel.y <- ~-. dampen_jump;
      (None,(evolve_enemy o1.dir typ s2 o2 context))
  | (Player(s1,o1), Enemy(t2,s2,o2), _)
  | (Enemy(t2,s2,o2), Player(s1,o1), _) ->
      o1.invuln <- invuln;
      begin match t2 with
      | GKoopaShell |RKoopaShell ->
          let r2 = if o2.vel.x = 0. then evolve_enemy o1.dir t2 s2 o2 context
                  else (o1.kill <- true; None) in
          (None,r2)
      | _ -> o1.kill <- true; (None, None)
      end
  | (Player(s1,o1), Item(t2,s2,o2), _)
  | (Item(t2,s2,o2), Player(s1,o1), _) ->
      o2.kill <- true; (None,None)(*& stuff happens to player*)
  | (Enemy(t1,s1,o1), Enemy(t2,s2,o2), dir) ->
      begin match dir with
      | West | East ->
          reverse_left_right o1;
          reverse_left_right o2;
          Sprite.transform_enemy t1 s1 o1.dir;
          Sprite.transform_enemy t2 s2 o2.dir;
          (None,None)
      | _ -> (None,None)
      end
  | (Enemy(t,s1,o1), Block(typ2,s2,o2), East)
  | (Enemy(t,s1,o1), Block(typ2,s2,o2), West)->
      reverse_left_right o1;
      Sprite.transform_enemy t s1 o1.dir;
      (None,None)
  | (Item(_,s1,o1), Block(typ2,s2,o2), East)
  | (Item(_,s1,o1), Block(typ2,s2,o2), West) ->
      reverse_left_right o1;
      (None, None)
  | (Enemy(_,s1,o1), Block(typ2,s2,o2), _)
  | (Player(s1,o1), Block(typ2,s2,o2), _)
  | (Item(_,s1,o1), Block(typ2,s2,o2), _) ->
      collide_block dir o1;
      (None, None)
  | (_, _, _) -> (None,None)

let get_aabb obj  =
  let spr = ((get_sprite obj).params)  in
  let obj = get_obj obj in
  let (offx, offy) = spr.bbox_offset in
  let (box,boy) = (obj.pos.x+.offx,obj.pos.y+.offy) in
  let (sx,sy) = spr.bbox_size in
  {
    center = {x=(box+.sx/.2.);y=(boy+.sy/.2.)};
    half = {x=sx/.2.;y=sy/.2.};
  }

let check_collision o1 o2 =
  let b1 = get_aabb o1 and b2 = get_aabb o2 in
  let o1 = get_obj o1 in
  let vx = (b1.center.x) -. (b2.center.x) in
  let vy = (b1.center.y) -. (b2.center.y) in
  let hwidths = (b1.half.x) +. (b2.half.x) in
  let hheights = (b1.half.y) +. (b2.half.y) in
  if abs_float vx < hwidths && abs_float vy < hheights then begin
    let ox = hwidths -. abs_float vx in
    let oy = hheights -. abs_float vy in
    if ox >= oy then begin
      if vy > 0. then (o1.pos.y <- (o1.pos.y+.oy);  Some North)
      else (o1.pos.y <- (o1.pos.y -. oy);  Some South)
    end else begin
      if vx > 0. then (o1.pos.x <- o1.pos.x +.ox; Some West)
      else (o1.pos.x <- o1.pos.x -. ox;  Some East)
    end
  end else None

let kill = function
  | _ -> []
