.include "constants.inc"
.include "header.inc"
.import reset_handler
.import read_controller1
.import read_controller2

.segment "ZEROPAGE"
player1_x:        .res 1
player1_y:        .res 1
player2_x:       .res 1
player2_y:       .res 1
sprite_index:    .res 1
sprite_attributes: .res 1
tile_head:       .res 1 ; indice del tile head tile que se va a dibujar
tile_body:       .res 1 ; indice del body tile
tile_tail:       .res 1 ; indice del tale/shell tile
frame_count:   .res 1   ; counter para los frames
walk_toggle:     .res 1
pad1:            .res 1 ; input del control 1
pad2:            .res 1 ; input del control 2
player1_jump:         .res 1
player1_jump_timer:     .res 1
player2_jump:        .res 1
player2_jump_timer:     .res 1
floor_y:         .res 1 ; esto representa donde sera el "piso" del juego (se cambia el valor depende el background)
temp_x:          .res 1 ; estas temporales son para guardar las posiciones de x y y 
temp_y:          .res 1 ; para acordarse la posicion original cuando se va a cambiar de pokemon
player1_form: .res 1 ; 0 = Pikachu, 1 = Charmander, 2 = Bulbasaur
player2_form: .res 1 

;IMIMPLEMENTACION DE PROYECTILES
poke_proj_active1: .res 1 ; detecta si esta activo o no el proyectil
poke_proj_x1:      .res 1 ; guarda la posocion del proyectil en x para player 1
poke_proj_y1:      .res 1 ; guarda la posicion del proyectil en y para player 1
poke_attack_timer1: .res 1 ; este timer controla cuanto tiempo va a estar activa la animacion del ataque

poke_proj_active2: .res 1; mismas variables de arriba creadas para el player2
poke_proj_x2:      .res 1
poke_proj_y2:      .res 1
poke_attack_timer2: .res 1

pika_phase1: .res 1 ; estas variables son para el proyectil de pikachu especificamente (movimiento en Y) 0 = up, 1 = down
pika_phase2: .res 1
bulba_bounce_timer1: .res 1 ; timer para cuanto tiempo va a estar subiendo/bajando el proyectil de bulbasaur
bulba_bounce_timer2 : .res 1
bulba_bounce_dir1: .res 1 ;alterna entre 0 y 1 para suir/bajar 0 = up, 1 = down
bulba_bounce_dir2: .res 1 ; estas variables son especificamernte para el proyectil de bulbasaur para su movimiento (brinco) en el eje de Y

; Estas variables son la vida de los pokemon cada una se inicializa al final con 3 cada uno
pika1_hp:  .res 1
char1_hp:  .res 1
bulb1_hp: .res 1
pika2_hp:  .res 1
char2_hp:  .res 1
bulb2_hp: .res 1

;Estas variables son flags que ayudan a saber si los players hicieron un hit
hit_p1:    .res 1  ; 1 if Player 1 hit Player 2, 0 otherwise
hit_p2:    .res 1  ; 1 if Player 2 hit Player 1, 0 otherwise

;Este flag es para detectar un hit de la lava
floor_hit_p1: .res 1  
floor_hit_p2: .res 1

;Este flag ayuda a que el switch de pokemones no sea instantaneo 
switch_lock_p1: .res 1
switch_lock_p2: .res 1

.exportzp player1_x, player1_y, player2_x, player2_y, pad1, pad2, floor_y, player1_jump, player1_jump_timer, player2_jump, player2_jump_timer, player1_form, player2_form

.segment "CODE"

.proc irq_handler
  RTI
.endproc

.proc nmi_handler
  INC frame_count
  LDA frame_count
  CMP #15
  BNE skip_toggle
  LDA #0
  STA frame_count
  LDA walk_toggle
  EOR #1
  STA walk_toggle

skip_toggle:

  ; Handle los Switch Locks
  LDA switch_lock_p1
  BEQ skip_lock1
  DEC switch_lock_p1
skip_lock1:

  LDA switch_lock_p2
  BEQ skip_lock2
  DEC switch_lock_p2
skip_lock2:

  ; Lee los controller inputs y hace updates al juego
  JSR read_controller1
  JSR read_controller2
  JSR handle_switch
  JSR update_player1
  JSR update_player2
  JSR check_floor_damage

  ; Controla el timer que el ataque del jugador 1 esta activo
  LDA poke_attack_timer1
  BEQ skip_attack_timer
  DEC poke_attack_timer1
skip_attack_timer:

  ; Resets el index del sprite
  LDA #0
  STA sprite_index

  ; Updates projectiles y verifica si hubo una colision 
  JSR update_projectile1
  JSR update_projectile2
  JSR check_projectile_hits

  ;Draw Player 1
  LDA player1_x
  STA temp_x
  LDA player1_y
  STA temp_y
  JSR set_P1_attributes

  ;Draw Player 2 
  LDA player2_x
  STA player1_x
  LDA player2_y
  STA player1_y
  JSR set_P2_attributes

  ;Restore Player 1 Position 
  LDA temp_x
  STA player1_x
  LDA temp_y
  STA player1_y

  ;Transfer Sprites to OAM
  LDA #0
  STA OAMADDR
  LDA #$02
  STA OAMDMA

  ; Reset Scroll 
  LDA #0
  STA $2005
  STA $2005

  ;Dibuja projectiles que estan activos
  LDA poke_proj_active1
  BEQ skip_proj1
  JSR draw_projectile1
skip_proj1:

  LDA poke_proj_active2
  BEQ skip_proj2
  JSR draw_projectile2
skip_proj2:

  ; Verifica si se cumple las condiciones para determinar un ganador
  JSR check_player1_alive
  JSR check_player2_alive

  ;Dibuja numeros de vida
  JSR draw_hp_numbers

  RTI
.endproc


;Esta rutina se encarga de controlar los switches entre los pokemones para ambos jugadores. 
;Estos switches tienen locks para prevenir que cambien rapido utilizando un debounce logic.
.proc handle_switch
  ;Player 1 Switching con debounce logic
  LDA switch_lock_p1
  BNE check_p2        ; skip if still in cooldown

  LDA poke_proj_active1 ; skip if projectile active (or attack animation)
  ORA poke_attack_timer1
  BNE check_p2

  LDA pad1
  AND #BTN_SELECT
  BEQ check_p2

  LDA #10             ; debounce delay
  STA switch_lock_p1

  LDA player1_form
  CLC
  ADC #1
  CMP #3
  BNE :+
  LDA #0
:
  STA temp_x
  LDX temp_x

find_next_p1:
  CPX #0
  BEQ check_pika1
  CPX #1
  BEQ check_char1
  CPX #2
  BEQ check_bulb1

check_pika1:
  LDA pika1_hp
  BNE select_poke1
  JMP next_index_p1

check_char1:
  LDA char1_hp
  BNE select_poke1
  JMP next_index_p1

check_bulb1:
  LDA bulb1_hp
  BNE select_poke1
  JMP next_index_p1

next_index_p1:
  INX
  CPX #3
  BNE :+
  LDX #0
:
  CPX temp_x
  BEQ no_alive_poke1
  JMP find_next_p1

select_poke1:
  STX player1_form
  JMP check_p2

no_alive_poke1:
  JMP check_p2

;Player 2 Switching con debounce logic
check_p2:
  LDA switch_lock_p2
  BNE done_switch

  LDA poke_proj_active2
  ORA poke_attack_timer2
  BNE done_switch

  LDA pad2
  AND #BTN_SELECT
  BEQ done_switch

  LDA #10
  STA switch_lock_p2

  LDA player2_form
  CLC
  ADC #1
  CMP #3
  BNE :+
  LDA #0
:
  STA temp_x
  LDX temp_x

find_next_p2:
  CPX #0
  BEQ check_pika2
  CPX #1
  BEQ check_char2
  CPX #2
  BEQ check_bulb2

check_pika2:
  LDA pika2_hp
  BNE select_poke2
  JMP next_index_p2

check_char2:
  LDA char2_hp
  BNE select_poke2
  JMP next_index_p2

check_bulb2:
  LDA bulb2_hp
  BNE select_poke2
  JMP next_index_p2

next_index_p2:
  INX
  CPX #3
  BNE :+
  LDX #0
:
  CPX temp_x
  BEQ no_alive_poke2
  JMP find_next_p2

select_poke2:
  STX player2_form
  JMP done_switch

no_alive_poke2:
  JMP done_switch

done_switch:
  RTS
.endproc


.proc update_player1 ; esta funcion esta updating el movimiento del player 1 (lado a lado/brincar) y verificando si se presiono el boton de ataque
  LDA pad1
  AND #BTN_LEFT
  BEQ right
  LDA player1_x
  CMP #$50      
  BEQ right
  DEC player1_x
right:
  LDA pad1
  AND #BTN_RIGHT
  BEQ check_jump
  LDA player1_x
  CMP #$F0       ; limite de la derecha (pantalla)
  BEQ check_jump
  INC player1_x

check_jump:
  LDA player1_jump
  BNE do_jump
  LDA pad1
  AND #BTN_A
  BEQ check_attack
  LDA #20
  STA player1_jump_timer
  LDA #1
  STA player1_jump

do_jump:
  LDA player1_jump
  BEQ ground
  LDA player1_jump_timer
  BEQ fall
  DEC player1_y
  DEC player1_jump_timer
  JMP done

fall:
  LDA player1_y
  CMP floor_y
  BCS landed
  INC player1_y
  JMP done

landed:
  LDA floor_y
  STA player1_y
  LDA #0
  STA player1_jump
  JMP done

ground:
  LDA floor_y
  STA player1_y

check_attack:
  LDA pad1
  AND #BTN_B
  BEQ done

  LDA player1_form
  CMP #0
  BEQ pika_attack
  CMP #1
  BEQ char_attack
  CMP #2
  BEQ bulb_attack
  JMP done

pika_attack:
  LDA poke_proj_active1
  BNE done
  LDA #1
  STA poke_proj_active1
  LDA #10
  STA poke_attack_timer1
  LDA #0
  STA pika_phase1
  LDA player1_x
  STA poke_proj_x1
  LDA player1_y
  STA poke_proj_y1
  JMP done

char_attack:
  LDA poke_proj_active1
  BNE done
  LDA #1
  STA poke_proj_active1
  LDA #10
  STA poke_attack_timer1
  LDA player1_x
  STA poke_proj_x1
  LDA player1_y
  STA poke_proj_y1
  JMP done

bulb_attack:
  LDA poke_proj_active1
  BNE done
  LDA #1
  STA poke_proj_active1
  LDA #10
  STA poke_attack_timer1
  LDA #0
  STA bulba_bounce_dir1
  LDA #4
  STA bulba_bounce_timer1
  LDA player1_x
  STA poke_proj_x1
  LDA player1_y
  STA poke_proj_y1
  JMP done

done:
  RTS
.endproc

.proc update_player2  ; esta funcion esta updating el player 2 (movimiento y ataques)
  LDA pad2
  AND #BTN_LEFT
  BEQ right
  LDA player2_x
  CMP #$08       ; limite de la izquierda (pantalla)
  BEQ right
  DEC player2_x
right:
  LDA pad2
  AND #BTN_RIGHT
  BEQ check_jump
  LDA player2_x
  CMP #$A8
  BEQ check_jump
  INC player2_x

check_jump:
  LDA player2_jump
  BNE do_jump
  LDA pad2
  AND #BTN_A
  BEQ check_attack
  LDA #20
  STA player2_jump_timer
  LDA #1
  STA player2_jump

do_jump:
  LDA player2_jump
  BEQ ground
  LDA player2_jump_timer
  BEQ fall
  DEC player2_y
  DEC player2_jump_timer
  JMP done

fall:
  LDA player2_y
  CMP floor_y
  BCS landed
  INC player2_y
  JMP done

landed:
  LDA floor_y
  STA player2_y
  LDA #0
  STA player2_jump
  JMP done

ground:
  LDA floor_y
  STA player2_y

check_attack:
  LDA pad2
  AND #BTN_B
  BEQ done

  LDA player2_form
  CMP #0
  BEQ pika_attack2
  CMP #1
  BEQ char_attack2
  CMP #2
  BEQ bulb_attack2
  JMP done

pika_attack2:
  LDA poke_proj_active2
  BNE done
  LDA #1
  STA poke_proj_active2
  LDA #10
  STA poke_attack_timer2
  LDA #0
  STA pika_phase2
  LDA player2_x
  STA poke_proj_x2
  LDA player2_y
  STA poke_proj_y2
  JMP done

char_attack2:
  LDA poke_proj_active2
  BNE done
  LDA #1
  STA poke_proj_active2
  LDA #10
  STA poke_attack_timer2
  LDA player2_x
  STA poke_proj_x2
  LDA player2_y
  STA poke_proj_y2
  JMP done

bulb_attack2:
  LDA poke_proj_active2
  BNE done
  LDA #1
  STA poke_proj_active2
  LDA #10
  STA poke_attack_timer2
  LDA #0
  STA bulba_bounce_dir2
  LDA #4
  STA bulba_bounce_timer2
  LDA player2_x
  STA poke_proj_x2
  LDA player2_y
  STA poke_proj_y2
  JMP done

done:
  RTS
.endproc

.proc update_projectile1 ; maneja el movimiento de los proyectiles de cada pokemon 
  LDA poke_proj_active1
  BEQ done

  LDA player1_form
  CMP #0        ; Pikachu
  BEQ pika_logic
  CMP #1        ; Charmander
  BEQ char_logic
  CMP #2        ; Bulbasaur
  BEQ bulb_logic
  JMP done

; === Pikachu Logic ===
pika_logic:
  LDA pika_phase1
  BEQ pika_up
  INC poke_proj_y1
  LDA poke_proj_y1
  CMP #$C0
  BCC done
  LDA #0
  STA poke_proj_active1
  JMP done
pika_up:
  DEC poke_proj_y1
  LDA poke_proj_y1
  CMP #$00
  BNE done
  ; aparece al otro lado el rayo
  LDA #1
  STA pika_phase1
  LDA #$40
  STA poke_proj_y1
  LDA #$FF
  SEC
  SBC poke_proj_x1
  STA poke_proj_x1
  JMP done

; === Charmander Logic ===
char_logic:
  LDA poke_proj_x1
  SEC
  SBC #2
  STA poke_proj_x1
  CMP #$10
  BCS done
  LDA #0
  STA poke_proj_active1
  JMP done

; === Bulbasaur Logic ===
bulb_logic:
  LDA poke_proj_x1
  SEC
  SBC #2
  STA poke_proj_x1
  ; Zigzag bounce
  DEC bulba_bounce_timer1
  BNE skip_toggle
  LDA #8
  STA bulba_bounce_timer1
  LDA bulba_bounce_dir1
  EOR #1
  STA bulba_bounce_dir1
skip_toggle:
  LDA bulba_bounce_dir1
  BEQ bounce_up
  INC poke_proj_y1
  JMP check_offscreen
bounce_up:
  DEC poke_proj_y1
check_offscreen:
  LDA poke_proj_x1
  CMP #$10
  BCS done
  LDA #0
  STA poke_proj_active1
done:
  RTS
.endproc

.proc update_projectile2 ;maneja el movimiento de los proyectiles de cada pokemon 
  ; === Pikachu ===
  LDA player2_form
  CMP #0
  BNE not_pika2
  LDA pika_phase2
  BEQ go_up2
  INC poke_proj_y2
  LDA poke_proj_y2
  CMP #$C0
  BCC check_timer
  LDA #0
  STA poke_proj_active2
  JMP check_timer
go_up2:
  DEC poke_proj_y2
  LDA poke_proj_y2
  CMP #$00
  BNE check_timer
  ;aparece al otro lado el rayo
  LDA #1
  STA pika_phase2
  LDA #$40
  STA poke_proj_y2
  LDA #$FF
  SEC
  SBC poke_proj_x2
  STA poke_proj_x2
  JMP check_timer
not_pika2:
  ; === Bulbasaur ===
  LDA player2_form
  CMP #2
  BNE not_bulb2
  ; Move right
  LDA poke_proj_x2
  CLC
  ADC #2
  STA poke_proj_x2
  ; Zigzag bounce
  DEC bulba_bounce_timer2
  BNE skip_bounce_toggle2
  LDA #8
  STA bulba_bounce_timer2
  LDA bulba_bounce_dir2
  EOR #1
  STA bulba_bounce_dir2
skip_bounce_toggle2:
  LDA bulba_bounce_dir2
  BEQ bounce_up2
  INC poke_proj_y2
  JMP bulb_check_off2
bounce_up2:
  DEC poke_proj_y2
bulb_check_off2:
  LDA poke_proj_x2
  CMP #$F0
  BCC check_timer
  LDA #0
  STA poke_proj_active2
  JMP check_timer
not_bulb2:
  ; === Charmander ===
  LDA player2_form
  CMP #1
  BNE done2

  LDA poke_proj_x2
  CLC
  ADC #2
  STA poke_proj_x2
  CMP #$F0
  BCC check_timer
  LDA #0
  STA poke_proj_active2
check_timer:
  LDA poke_attack_timer2
  BEQ skip_timer
  DEC poke_attack_timer2
skip_timer:
done2:
  RTS
.endproc

.proc draw_projectile1 ; depende que pokemon este activo dibuja el tile del proyectil a memoria player 1
  LDX sprite_index
  LDA poke_proj_y1
  STA $0200, X

  LDA player1_form
  CMP #0        ; Pikachu
  BEQ pika_proj
  CMP #1        ; Charmander
  BEQ char_proj
  CMP #2        ; Bulbasaur
  BEQ bulb_proj

  JMP end_draw

pika_proj:
  LDA #$11
  JMP write_tile

char_proj:
  LDA #$1F
  JMP write_tile

bulb_proj:
  LDA #$29

write_tile:
  STA $0201, X
  LDA #%00000000
  STA $0202, X
  LDA poke_proj_x1
  STA $0203, X
  INX
  INX
  INX
  INX
  STX sprite_index

end_draw:
  RTS
.endproc

.proc draw_projectile2 ; depende que pokemon este activo dibuja el tile del proyectil a memoria player2
  LDX sprite_index
  LDA poke_proj_y2
  STA $0200, X
  LDA player2_form
  CMP #0
  BEQ pika_proj2
  CMP #1
  BEQ char_proj2
  CMP #2
  BEQ bulb_proj2

  JMP end_draw2
pika_proj2:
  LDA #$11
  JMP write_proj2

char_proj2:
  LDA #$1F
  JMP write_proj2
bulb_proj2:
  LDA #$29
write_proj2:
  STA $0201, X
  LDA #%01000000   ; flip horizontally (Player 2)
  STA $0202, X
  LDA poke_proj_x2
  STA $0203, X
  INX
  INX
  INX
  INX
  STX sprite_index
end_draw2:
  RTS
.endproc

.proc set_P1_attributes ; funcion que setea los sprite attributes para el player1 dependiendo que pokemon este activo
  LDA player1_form
  CMP #1
  BEQ set_char_attributes
  CMP #2
  BEQ set_bulb_attributes

  ; Default to Pikachu
  LDA #%00000000  ; Pikachu palette
  STA sprite_attributes
  JSR set_walking_pika
  RTS

set_char_attributes:
  LDA #%00000001  ; Charmander palette
  STA sprite_attributes
  JSR set_walking_char
  RTS

set_bulb_attributes:
  LDA #%00000010  ; Bulbasaur palette
  STA sprite_attributes
  JSR set_walking_bulb
  RTS

.endproc

.proc set_P2_attributes ; funcion que setea los sprite attributes para el player2 dependiendo que pokemon este activo

  LDA player2_form
  CMP #1
  BEQ set_char_attributes
  CMP #2
  BEQ set_bulb_attributes

  ; Default to Pikachu
  LDA #%01000000  ; Pikachu palette + horizontal flip
  STA sprite_attributes
  JSR set_walking_pika2
  RTS

set_char_attributes:
  LDA #%01000001  ; Charmander palette + flip
  STA sprite_attributes
  JSR set_walking_char2
  RTS

set_bulb_attributes:
  LDA #%01000010  ; Bulbasaur palette + flip
  STA sprite_attributes
  JSR set_walking_bulb2
  RTS
.endproc

.proc set_walking_pika ; funcion alterna entre los tiles de tail y body que da la ilusion de que esta animado el pikachu de player 1
  LDA poke_attack_timer1
  BEQ pika_normal_walk
  LDA #$0E         ; attack head
  STA tile_head
  LDA #$0F         ; attack body
  STA tile_body
  LDA #$10         ; attack tail
  STA tile_tail
  JMP draw1

pika_normal_walk:
  LDA #$04
  STA tile_head
  LDA walk_toggle
  BEQ pika_pose1
  LDA #$07
  STA tile_body
  LDA #$08
  STA tile_tail
  JMP draw1

pika_pose1:
  LDA #$05
  STA tile_body
  LDA #$06
  STA tile_tail

draw1:
  JSR draw_tiles
  RTS
.endproc

.proc set_walking_pika2 ; funcion que alterna entre los tiles de tail y body que da la ilusion de que esta animado el pikachu de player 2
  LDA poke_attack_timer2
  BEQ pika_normal_walk2
  LDA #$0E         ; attack head
  STA tile_head
  LDA #$0F         ; attack body
  STA tile_body
  LDA #$10         ; attack tail
  STA tile_tail
  JMP draw2

pika_normal_walk2:
  LDA #$04
  STA tile_head
  LDA walk_toggle
  BEQ pika_pose2
  LDA #$07
  STA tile_body
  LDA #$08
  STA tile_tail
  JMP draw2

pika_pose2:
  LDA #$05
  STA tile_body
  LDA #$06
  STA tile_tail

draw2:
  JSR draw_tiles
  RTS
.endproc

.proc set_walking_char ; funcion que alterna entre los tiles de tail y body que da la ilusion de que esta animado el charmander de player 1
  LDA poke_attack_timer1
  BEQ not_attacking1
  LDA #$1C         ; head (attack)
  STA tile_head
  LDA #$1D         ; body (attack)
  STA tile_body
  LDA #$1E         ; tail (attack)
  STA tile_tail
  JMP draw
not_attacking1:
  LDA #$12
  STA tile_head
  LDA walk_toggle
  BEQ pose1
  LDA #$15
  STA tile_body
  LDA #$16
  STA tile_tail
  JMP draw
pose1:
  LDA #$13
  STA tile_body
  LDA #$14
  STA tile_tail
draw:
  JSR draw_tiles
  RTS
.endproc

.proc set_walking_char2 ; funcion que alterna entre los tiles de tail y body que da la ilusion de que esta animado el charmander de player 2
  LDA poke_attack_timer2
  BEQ not_attacking2
  LDA #$1C         ; head (attack)
  STA tile_head
  LDA #$1D         ; body (attack)
  STA tile_body
  LDA #$1E         ; tail (attack)
  STA tile_tail
  JMP draw

not_attacking2:
  LDA #$12         ; head
  STA tile_head
  LDA walk_toggle
  BEQ pose2
  LDA #$15         ; body A
  STA tile_body
  LDA #$16         ; tail A
  STA tile_tail
  JMP draw

pose2:
  LDA #$13         ; body B
  STA tile_body
  LDA #$14         ; tail B
  STA tile_tail

draw:
  JSR draw_tiles
  RTS
.endproc


.proc set_walking_bulb ; funcion que alterna entre los tiles de tail y body que da la ilusion de que esta animado el bulbasaur de player 1
  LDA poke_attack_timer1
  BEQ bulb_normal_walk
  LDA #$25         ; attack head
  STA tile_head
  LDA #$26         ; attack body
  STA tile_body
  LDA #$27         ; attack tail
  STA tile_tail
  JMP draw

bulb_normal_walk:
  LDA #$20
  STA tile_head
  LDA walk_toggle
  BEQ pose1
  LDA #$24
  STA tile_body
  LDA #$21
  STA tile_tail
  JMP draw

pose1:
  LDA #$22
  STA tile_body
  LDA #$21
  STA tile_tail
draw:
  JSR draw_btiles
  RTS
.endproc


.proc set_walking_bulb2 ; funcion que alterna entre los tiles de tail y body que da la ilusion de que esta animado el bulbasaur de player 2
  LDA poke_attack_timer2
  BEQ bulb_walk2
  LDA #$25         ; attack head
  STA tile_head
  LDA #$26         ; attack body
  STA tile_body
  LDA #$27         ; attack tail
  STA tile_tail
  JMP draw

bulb_walk2:
  LDA #$20
  STA tile_head
  LDA walk_toggle
  BEQ pose2
  LDA #$24
  STA tile_body
  LDA #$21
  STA tile_tail
  JMP draw

pose2:
  LDA #$22
  STA tile_body
  LDA #$21
  STA tile_tail

draw:
  JSR draw_btiles
  RTS
.endproc

.proc draw_tiles ; funcion que dibuja los tiles en la pantalla
  LDX sprite_index

  ; head
  LDA player1_y
  STA $0200, X
  LDA tile_head
  STA $0201, X
  LDA sprite_attributes
  STA $0202, X
  LDA player1_x
  STA $0203, X
  INX
  INX
  INX
  INX

  ; body
  LDA player1_y
  CLC
  ADC #8
  STA $0200, X
  LDA tile_body
  STA $0201, X
  LDA sprite_attributes
  STA $0202, X
  LDA player1_x
  STA $0203, X
  INX
  INX
  INX
  INX

  ; tail
  LDA player1_y
  CLC
  ADC #8
  STA $0200, X
  LDA tile_tail
  STA $0201, X
  LDA sprite_attributes
  STA $0202, X
  LDA sprite_attributes
  AND #%01000000
  BEQ tail_side ; resultado de la comparacion entre los attributes y %01000000 (detecta a si esta flipped)
  LDA player1_x
  SEC
  SBC #8
  STA $0203, X
  JMP tail_done

tail_side: ;si esta flipped, la cola debe estar rendered al otro lado del pokemon
  LDA player1_x
  CLC
  ADC #8
  STA $0203, X
tail_done:
  INX
  INX
  INX
  INX
  STX sprite_index
  RTS
.endproc

.proc draw_btiles
  LDX sprite_index
  ; Head
  LDA player1_y
  STA $0200, X
  LDA tile_head
  STA $0201, X
  LDA sprite_attributes
  STA $0202, X
  LDA player1_x
  STA $0203, X
  INX
  INX
  INX
  INX

  ; Body
  LDA player1_y
  CLC
  ADC #8
  STA $0200, X    
  LDA tile_body
  STA $0201, X
  LDA sprite_attributes
  STA $0202, X
  LDA sprite_attributes
  AND #%01000000
  BEQ body_right
  LDA player1_x
  SEC
  SBC #8
  STA $0203, X
  JMP body_done
body_right:
  LDA player1_x
  CLC
  ADC #8
  STA $0203, X
body_done:
  INX
  INX
  INX
  INX

  ; Tail
  LDA player1_y
  STA $0200, X
  LDA tile_tail
  STA $0201, X
  LDA sprite_attributes
  STA $0202, X
  LDA sprite_attributes
  AND #%01000000
  BEQ tail_right
  ; Flipped tail to the left
  LDA player1_x
  SEC
  SBC #8
  STA $0203, X
  JMP tail_done

tail_right:
  ; tail to the right
  LDA player1_x
  CLC
  ADC #8
  STA $0203, X

tail_done:
  INX
  INX
  INX
  INX

  STX sprite_index
  RTS

.endproc

.proc check_projectile_hits
  ;  P1 projectile hits P2 
  LDA poke_proj_active1
  BEQ skip_p1_check

  LDA player1_form
  CMP #0
  BEQ pika_hit_p1

  ; Charmander / Bulbasaur standard hitbox
  LDA poke_proj_x1
  SEC
  SBC player2_x
  CMP #8
  BCS skip_p1_check

  LDA poke_proj_y1
  SEC
  SBC player2_y
  CMP #16
  BCS skip_p1_check

  JMP do_p1_hit

pika_hit_p1:
  LDA poke_proj_x1
  SEC
  SBC player2_x
  CMP #8
  BCS skip_p1_check

  LDA poke_proj_y1
  SEC
  SBC player2_y
  CMP #24
  BCS skip_p1_check

do_p1_hit:
  LDA #0
  STA poke_proj_active1
  LDA #1
  STA hit_p1
  JSR handle_damage

skip_p1_check:

  ; P2 projectile hits P1 
  LDA poke_proj_active2
  BEQ done

  LDA player2_form
  CMP #0
  BEQ pika_hit_p2

  ; Charmander / Bulbasaur standard hitbox
  LDA poke_proj_x2
  SEC
  SBC player1_x
  CMP #8
  BCS done

  LDA poke_proj_y2
  SEC
  SBC player1_y
  CMP #16
  BCS done

  JMP do_p2_hit

pika_hit_p2:
 
  LDA poke_proj_x2
  SEC
  SBC player1_x
  CMP #8
  BCS done

  LDA poke_proj_y2
  SEC
  SBC player1_y
  CMP #24
  BCS done

do_p2_hit:
  LDA #0
  STA poke_proj_active2
  LDA #1
  STA hit_p2
  JSR handle_damage

done:
  RTS
.endproc

.proc handle_damage

; Player 1 projectile hits Player 2 
check_p1_hit:
  LDA hit_p1
  BEQ check_p2_hit   ; if no hit, skip to P2 check

  ; Decrease HP for Player 2's current Pokémon
  LDA player2_form
  CMP #0
  BEQ dec_pika2
  CMP #1
  BEQ dec_char2
  CMP #2
  BEQ dec_bulb2
  JMP check_p2_hit

dec_pika2:
  DEC pika2_hp
  LDA pika2_hp
  BNE check_p2_hit
  ; if 0, force switch
  LDA #BTN_SELECT
  STA pad2
  JSR handle_switch
  LDA #0
  STA pad2
  JMP check_p2_hit

dec_char2:
  DEC char2_hp
  LDA char2_hp
  BNE check_p2_hit
  ; if 0, force switch
  LDA #BTN_SELECT
  STA pad2
  JSR handle_switch
  LDA #0
  STA pad2
  JMP check_p2_hit

dec_bulb2:
  DEC bulb2_hp
  LDA bulb2_hp
  BNE check_p2_hit
  ; if 0, force switch
  LDA #BTN_SELECT
  STA pad2
  JSR handle_switch
  LDA #0
  STA pad2
  JMP check_p2_hit

; Player 2 projectile hits Player 1 
check_p2_hit:
  LDA hit_p2
  BEQ end_damage   ; if no hit, done

  ; Decrease HP for Player 1's current Pokémon
  LDA player1_form
  CMP #0
  BEQ dec_pika1
  CMP #1
  BEQ dec_char1
  CMP #2
  BEQ dec_bulb1
  JMP end_damage

dec_pika1:
  DEC pika1_hp
  LDA pika1_hp
  BNE end_damage
  ; if 0, force switch
  LDA #BTN_SELECT
  STA pad1
  JSR handle_switch
  LDA #0
  STA pad1
  JMP end_damage

dec_char1:
  DEC char1_hp
  LDA char1_hp
  BNE end_damage
  ; if 0, force switch
  LDA #BTN_SELECT
  STA pad1
  JSR handle_switch
  LDA #0
  STA pad1
  JMP end_damage

dec_bulb1:
  DEC bulb1_hp
  LDA bulb1_hp
  BNE end_damage
  ; if 0, force switch
  LDA #BTN_SELECT
  STA pad1
  JSR handle_switch
  LDA #0
  STA pad1
  JMP end_damage

end_damage:
  ; Clear hit flags at the end
  LDA #0
  STA hit_p1
  STA hit_p2
  RTS

.endproc

;Esta subrutina verifica si el player1 o player 2 esta en lava. Si esta en lava le quita 1hp
;y llama a otra subrutina que "pushes" el jugador a un safe block
.proc check_floor_damage
  ;Check Player 1
  LDA player1_y
  CMP #$B0
  BCC p1_safe_y
  CMP #$C0
  BCS p1_safe_y

  LDA player1_x
  CMP #$50
  BCC p1_safe_x
  CMP #$A8
  BCS p1_safe_x

  ; P1 is in Lava
  LDA floor_hit_p1
  BNE p1_done    ; if already hit this frame, skip

  
  LDA player1_form
  CMP #0
  BEQ hurt_pika1
  CMP #1
  BEQ hurt_char1
  CMP #2
  BEQ hurt_bulb1
  JMP p1_done

hurt_pika1:
  DEC pika1_hp
  JSR push_back_p1
  LDA #1
  STA floor_hit_p1
  JMP p1_done

hurt_char1:
  DEC char1_hp
  JSR push_back_p1
  LDA #1
  STA floor_hit_p1
  JMP p1_done

hurt_bulb1:
  DEC bulb1_hp
  JSR push_back_p1
  LDA #1
  STA floor_hit_p1
  JMP p1_done

p1_safe_x:
p1_safe_y:
  ; If player 1 is NOT touching lava, reset flag
  LDA #0
  STA floor_hit_p1

p1_done:

  ;Check Player 2
  LDA player2_y
  CMP #$B0
  BCC p2_safe_y
  CMP #$C0
  BCS p2_safe_y

  LDA player2_x
  CMP #$50
  BCC p2_safe_x
  CMP #$A8
  BCS p2_safe_x

  ;P2 is in Lava 
  LDA floor_hit_p2
  BNE p2_done    ; if already hit this frame, skip

  ; Not hit yet: Damage and move
  LDA player2_form
  CMP #0
  BEQ hurt_pika2
  CMP #1
  BEQ hurt_char2
  CMP #2
  BEQ hurt_bulb2
  JMP p2_done

hurt_pika2:
  DEC pika2_hp
  JSR push_back_p2
  LDA #1
  STA floor_hit_p2
  JMP p2_done

hurt_char2:
  DEC char2_hp
  JSR push_back_p2
  LDA #1
  STA floor_hit_p2
  JMP p2_done

hurt_bulb2:
  DEC bulb2_hp
  JSR push_back_p2
  LDA #1
  STA floor_hit_p2
  JMP p2_done

p2_safe_x:
p2_safe_y:
  ; If player 2 is NOT touching lava, reset flag
  LDA #0
  STA floor_hit_p2

p2_done:
  RTS
.endproc

.proc push_back_p1
  LDA player1_x
  SEC
  ADC #$08
  STA player1_x

  ; After moving, clear floor hit flag
  LDA #0
  STA floor_hit_p1

  ; Check if current Pokémon is dead
  LDA player1_form
  CMP #0
  BEQ check_pika1
  CMP #1
  BEQ check_char1
  CMP #2
  BEQ check_bulb1
  RTS

check_pika1:
  LDA pika1_hp
  BNE done
  LDA #BTN_SELECT
  STA pad1
  JSR handle_switch
  LDA #0
  STA pad1
  RTS

check_char1:
  LDA char1_hp
  BNE done
  LDA #BTN_SELECT
  STA pad1
  JSR handle_switch
  LDA #0
  STA pad1
  RTS

check_bulb1:
  LDA bulb1_hp
  BNE done
  LDA #BTN_SELECT
  STA pad1
  JSR handle_switch
  LDA #0
  STA pad1
  RTS

done:
  RTS
.endproc
.proc push_back_p2
  LDA player2_x
  CLC
  SBC #$08
  STA player2_x

  ; After moving, clear floor hit flag
  LDA #0
  STA floor_hit_p2

  ; Check if current Pokémon is dead
  LDA player2_form
  CMP #0
  BEQ check_pika2
  CMP #1
  BEQ check_char2
  CMP #2
  BEQ check_bulb2
  RTS

check_pika2:
  LDA pika2_hp
  BNE done
  LDA #BTN_SELECT
  STA pad2
  JSR handle_switch
  LDA #0
  STA pad2
  RTS

check_char2:
  LDA char2_hp
  BNE done
  LDA #BTN_SELECT
  STA pad2
  JSR handle_switch
  LDA #0
  STA pad2
  RTS

check_bulb2:
  LDA bulb2_hp
  BNE done
  LDA #BTN_SELECT
  STA pad2
  JSR handle_switch
  LDA #0
  STA pad2
  RTS

done:
  RTS
.endproc


;Dibuja "P1 wins"
.proc draw_p1_wins
  LDX sprite_index

  ; P 
  LDA #100
  STA $0200, X
  LDA #$2B   ; Tile 'P'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #116
  STA $0203, X
  INX
  INX
  INX
  INX

  ;  1 
  LDA #100
  STA $0200, X
  LDA #$2C   ; Tile '1'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #124
  STA $0203, X
  INX
  INX
  INX
  INX

  ;  W 
  LDA #100
  STA $0200, X
  LDA #$2E   ; Tile 'W'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #140
  STA $0203, X
  INX
  INX
  INX
  INX

  ; I 
  LDA #100
  STA $0200, X
  LDA #$2F   ; Tile 'I'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #148
  STA $0203, X
  INX
  INX
  INX
  INX

  ; N
  LDA #100
  STA $0200, X
  LDA #$30   ; Tile 'N'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #156
  STA $0203, X
  INX
  INX
  INX
  INX

  ; S
  LDA #100
  STA $0200, X
  LDA #$31   ; Tile 'S'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #164
  STA $0203, X
  INX
  INX
  INX
  INX

  STX sprite_index
  RTS
.endproc
.proc draw_p2_wins
  LDX sprite_index

  ;  P 
  LDA #100
  STA $0200, X
  LDA #$2B   ; Tile 'P'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #116
  STA $0203, X
  INX
  INX
  INX
  INX

  ;  2 
  LDA #100
  STA $0200, X
  LDA #$2D   ; Tile '2'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #124
  STA $0203, X
  INX
  INX
  INX
  INX

  ;  W 
  LDA #100
  STA $0200, X
  LDA #$2E   ; Tile 'W'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #140
  STA $0203, X
  INX
  INX
  INX
  INX

  ;  I 
  LDA #100
  STA $0200, X
  LDA #$2F   ; Tile 'I'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #148
  STA $0203, X
  INX
  INX
  INX
  INX

  ;  N 
  LDA #100
  STA $0200, X
  LDA #$30   ; Tile 'N'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #156
  STA $0203, X
  INX
  INX
  INX
  INX

  ;  S 
  LDA #100
  STA $0200, X
  LDA #$31   ; Tile 'S'
  STA $0201, X
  LDA #%00000001
  STA $0202, X
  LDA #164
  STA $0203, X
  INX
  INX
  INX
  INX

  STX sprite_index
  RTS
.endproc


.proc check_player1_alive
  LDA pika1_hp
  BNE alive
  LDA char1_hp
  BNE alive
  LDA bulb1_hp
  BNE alive

  ; No Pokémon left means Player 2 wins
  JSR draw_p1_wins
halt_p1win:
  JMP halt_p1win

alive:
  RTS
.endproc

.proc check_player2_alive
  LDA pika2_hp
  BNE alive
  LDA char2_hp
  BNE alive
  LDA bulb2_hp
  BNE alive

  ; No Pokémon left means Player 1 wins
  JSR draw_p2_wins
halt_p2win:
  JMP halt_p2win

alive:
  RTS
.endproc

.proc draw_hp_numbers
  LDX sprite_index

  ; P1 HP
  ; Pikachu
  LDA #16       ; Y
  STA $0200, X
  JSR get_p2_tile_0 ; Draw HP for P2's Pikachu on left side
  STA $0201, X
  LDA #%00000000
  STA $0202, X
  LDA #80
  STA $0203, X
  INX
  INX
  INX
  INX

  ; Charmander
  LDA #32
  STA $0200, X
  JSR get_p2_tile_1 ; P2's Char HP on left
  STA $0201, X
  LDA #%00000000
  STA $0202, X
  LDA #80
  STA $0203, X
  INX
  INX
  INX
  INX

  ; Bulbasaur
  LDA #48
  STA $0200, X
  JSR get_p2_tile_2 ; P2's Bulb HP on left
  STA $0201, X
  LDA #%00000000
  STA $0202, X
  LDA #80
  STA $0203, X
  INX
  INX
  INX
  INX

  ; P2 HP
  ; Pikachu
  LDA #16
  STA $0200, X
  JSR get_p1_tile_0 ; Draw HP for P1's Pikachu on right side
  STA $0201, X
  LDA #%00000000
  STA $0202, X
  LDA #168
  STA $0203, X
  INX
  INX
  INX
  INX

  ; Charmander
  LDA #32
  STA $0200, X
  JSR get_p1_tile_1
  STA $0201, X
  LDA #%00000000
  STA $0202, X
  LDA #168
  STA $0203, X
  INX
  INX
  INX
  INX

  ; Bulbasaur
  LDA #48
  STA $0200, X
  JSR get_p1_tile_2
  STA $0201, X
  LDA #%00000000
  STA $0202, X
  LDA #168
  STA $0203, X
  INX
  INX
  INX
  INX

  STX sprite_index
  RTS
.endproc

.proc get_p1_tile_0
  LDA pika1_hp
  JMP get_hp_tile
.endproc
.proc get_p1_tile_1
  LDA char1_hp
  JMP get_hp_tile
.endproc
.proc get_p1_tile_2
  LDA bulb1_hp
  JMP get_hp_tile
.endproc
.proc get_p2_tile_0
  LDA pika2_hp
  JMP get_hp_tile
.endproc
.proc get_p2_tile_1
  LDA char2_hp
  JMP get_hp_tile
.endproc
.proc get_p2_tile_2
  LDA bulb2_hp
  JMP get_hp_tile
.endproc

.proc get_hp_tile
  CMP #3
  BEQ load_tile_3
  CMP #2
  BEQ load_tile_2
  CMP #1
  BEQ load_tile_1
  LDA #$00
  RTS
load_tile_3:
  LDA #$32
  RTS
load_tile_2:
  LDA #$2D
  RTS
load_tile_1:
  LDA #$2C
  RTS
.endproc



.export main
.proc main
  ; === Load background palettes to $3F00 ===
  LDA PPUSTATUS          ; reset address latch
  LDA #$3F
  STA PPUADDR
  LDA #$00
  STA PPUADDR
  LDX #$00
load_bg_palettes:
  LDA palettes, X
  STA PPUDATA
  INX
  CPX #$10
  BNE load_bg_palettes

    ; === Load sprite palettes to $3F10 ===
  LDA PPUSTATUS
  LDA #$3F
  STA PPUADDR
  LDA #$10
  STA PPUADDR
  LDX #$10
load_sprite_palettes:
  LDA palettes, X
  STA PPUDATA
  INX
  CPX #$20
  BNE load_sprite_palettes
  
; Write nametable from $2300 to $23BF (6 rows)
  LDA PPUSTATUS ; Reset PPUADDR latch
  LDA #$23
  STA PPUADDR
  LDA #$00  ; Start at $2300
  STA PPUADDR
  
  LDX #$C0  ; 192 bytes (6 rows * 32 tiles per row)
fill_nametable:
  LDA #$02
  STA PPUDATA
  DEX
  BNE fill_nametable
; Set PPUADDR to $230A
LDA PPUSTATUS
LDA #$23
STA PPUADDR
LDA #$0A
STA PPUADDR

LDX #$0C           ; 12 tiles
replace_loop:
  LDA #$03         ; New tile ID
  STA PPUDATA
  DEX
  BNE replace_loop
  
	LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$80  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0D  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$81  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0D  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$82  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0D  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$60  ; Specific position in the nametable
  STA PPUADDR
  LDA #$1E  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$61  ; Specific position in the nametable
  STA PPUADDR
  LDA #$1F  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$40  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0E  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$41  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0F  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$E1  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0B  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$41  ; Specific position in the nametable
  STA PPUADDR
  LDA #$09  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$42  ; Specific position in the nametable
  STA PPUADDR
  LDA #$04  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$43  ; Specific position in the nametable
  STA PPUADDR
  LDA #$05  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$44  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$46  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$48  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$82  ; Specific position in the nametable
  STA PPUADDR
  LDA #$04  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$83  ; Specific position in the nametable
  STA PPUADDR
  LDA #$06  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$84  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$86  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$88  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA
	
	LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$C2  ; Specific position in the nametable
  STA PPUADDR
  LDA #$04  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$C3  ; Specific position in the nametable
  STA PPUADDR
  LDA #$07  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$C4  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$C6  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$C8  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$49  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0A  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$E9  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0C  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$9F  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0D  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$9E  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0D  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$9D  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0D  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$7F  ; Specific position in the nametable
  STA PPUADDR
  LDA #$21  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$7E  ; Specific position in the nametable
  STA PPUADDR
  LDA #$20  ; Tile ID
  STA PPUDATA

	LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$5F  ; Specific position in the nametable
  STA PPUADDR
  LDA #$11  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$21  ; Nametable address
  STA PPUADDR
  LDA #$5E  ; Specific position in the nametable
  STA PPUADDR
  LDA #$10  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$56  ; Specific position in the nametable
  STA PPUADDR
  LDA #$09  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$57  ; Specific position in the nametable
  STA PPUADDR
  LDA #$04  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$58  ; Specific position in the nametable
  STA PPUADDR
  LDA #$05  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$59  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$5B  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$5D  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$5E  ; Specific position in the nametable
  STA PPUADDR
  LDA #$0A  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$97  ; Specific position in the nametable
  STA PPUADDR
  LDA #$04  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$98  ; Specific position in the nametable
  STA PPUADDR
  LDA #$06  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$99  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$9B  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$9D  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$D7  ; Specific position in the nametable
  STA PPUADDR
  LDA #$04  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$D8  ; Specific position in the nametable
  STA PPUADDR
  LDA #$07  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$D9  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$DB  ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$DD ; Specific position in the nametable
  STA PPUADDR
  LDA #$08  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$F6 ; Specific position in the nametable
  STA PPUADDR
  LDA #$0B  ; Tile ID
  STA PPUDATA

  LDA PPUSTATUS
  LDA #$20  ; Nametable address
  STA PPUADDR
  LDA #$FE ; Specific position in the nametable
  STA PPUADDR
  LDA #$0C  ; Tile ID
  STA PPUDATA

  ; Write attribute table
;   LDA PPUSTATUS
;   LDA #$23
;   STA PPUADDR
;   LDA #$C0
;   STA PPUADDR
;   LDA #%01000000
;   STA PPUDATA
  
;   LDA PPUSTATUS
;   LDA #$23
;   STA PPUADDR
;   LDA #$FF
;   STA PPUADDR
;   LDA #%00001100
;   STA PPUDATA

; Fill attribute table with palette 0 (00 00 00 00)


  ; Set initial positions
  LDA #$d0
  STA player1_x
  LDA #$28
  STA player2_x
  LDA #$b0
  STA player1_y
  STA player2_y
  STA floor_y

  LDA #0
  STA sprite_index
  STA frame_count
  STA walk_toggle
  STA player1_jump
  STA player2_jump
  STA player1_jump_timer
  STA player2_jump_timer
  STA player1_form
  STA player2_form


  LDA #3
  ; Health for each Pokémon
  STA pika1_hp
  STA char1_hp
  STA bulb1_hp
  STA pika2_hp
  STA char2_hp
  STA bulb2_hp




vblankwait:
  BIT PPUSTATUS
  BPL vblankwait

  LDA #%10010000
  STA PPUCTRL
  LDA #%00011110
  STA PPUMASK

forever:
  JMP forever
.endproc

.segment "VECTORS"
.addr nmi_handler
.addr reset_handler
.addr irq_handler

.segment "RODATA"

hp_addr_p1:
  .word pika1_hp, char1_hp, bulb1_hp
hp_addr_p2:
  .word pika2_hp, char2_hp, bulb2_hp

p1_hp_x:
  .byte 80
p1_hp_y:
  .byte 16, 32, 48
p2_hp_x:
  .byte 168
p2_hp_y:
  .byte 16, 32, 48

; Player 1 (left side)
p1_heart_addrs:
  .byte $44, $46, $48    ; P1 hearts (Pikachu)
  .byte $84, $86, $88    ; P2 hearts (Charmander)
  .byte $C4, $C6, $C8    ; P3 hearts (Bulbasaur)

; Player 2 (right side)
p2_heart_addrs:
  .byte $59, $5B, $5D    ; P1 hearts (Pikachu)
  .byte $99, $9B, $9D    ; P2 hearts (Charmander)
  .byte $D9, $DB, $DD    ; P3 hearts (Bulbasaur)
palettes:
.byte $21, $2D, $19, $05
.byte $0f, $2b, $3c, $39
.byte $0f, $0c, $21, $32
.byte $0f, $19, $09, $29

.byte $21, $15, $28, $17 ; sprite palette 0: Pikachu
.byte $0f, $05, $16, $27 ; sprite palette 1: Charmander
.byte $0f, $0B, $2c, $30 ;sprite palette 2; bulbasaur
.byte $0f, $0c, $21, $32


.segment "CHR"
.incbin "pokemon.chr"
