.include "constants.inc"

.segment "ZEROPAGE"
.importzp pad1, pad2

.segment "CODE"

.export read_controller1, read_controller2

; === READ CONTROLLER 1 (arrow keys) ===
.proc read_controller1
  PHP
  PHA
  TXA
  PHA

  LDA #$01
  STA CONTROLLER1
  LDA #$00
  STA CONTROLLER1

  LDA #%00000001
  STA pad1

read_buttons1:
  LDA CONTROLLER1
  LSR A
  ROL pad1
  BCC read_buttons1

  PLA
  TAX
  PLA
  PLP
  RTS
.endproc

; === READ CONTROLLER 2 (WASD keys) ===
.proc read_controller2
  PHP
  PHA
  TXA
  PHA

  LDA #$01
  STA CONTROLLER2
  LDA #$00
  STA CONTROLLER2

  LDA #%00000001
  STA pad2

read_buttons2:
  LDA CONTROLLER2
  LSR A
  ROL pad2
  BCC read_buttons2

  PLA
  TAX
  PLA
  PLP
  RTS
.endproc
