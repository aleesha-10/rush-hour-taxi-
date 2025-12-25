; --------------------------
; Rush Hour Taxi Game(Enhanced)
; --------------------------

.386
.model flat, stdcall
.stack 4096
ExitProcess PROTO, dwExitCode:DWORD

INCLUDE Irvine32.inc
INCLUDE macros.inc

; Constants
SCREEN_WIDTH = 80
SCREEN_HEIGHT = 25
GRID_ROWS = 6
GRID_COLS = 6
CELL_WIDTH = 8
CELL_HEIGHT = 3
MAX_PASSENGERS = 3
MAX_NPC_CARS = 4

.data
SAVE_FILE_NAME BYTE "rushhour_save.dat", 0
LEADERBOARD_FILE BYTE "leaderboard.txt", 0

tempTime DWORD ? ; temporary dword used for save / load of elapsed ms
taxiCharStr BYTE "Taxi", 0; legend text - null terminated

; Game State Variables
gameState BYTE 0; 0 = Menu, 1 = Playing, 2 = Paused, 3 = GameOver, 4 = Leaderboard, 5 = Instructions
currentMode BYTE 0; 0 = Career, 1 = Time, 2 = Endless
difficulty BYTE 1; 1 = Easy, 2 = Medium, 3 = Hard
score DWORD 0
timeLeft DWORD 60; for Time Mode
level DWORD 1
playerName BYTE 16 DUP(' ')
playerNameLen DWORD 0
taxiColor BYTE 1; 0 = Red, 1 = Yellow
hasSavedGame BYTE 0

; Taxi and Player
taxiRow DWORD 2
taxiCol DWORD 2
taxiDirection BYTE 0; 0 = Up, 1 = Right, 2 = Down, 3 = Left
taxiSpeed DWORD 150; milliseconds between moves
playerSpeed DWORD 200; base speed for red taxi

; Passengers
passengerRows DWORD MAX_PASSENGERS DUP(-1)
passengerCols DWORD MAX_PASSENGERS DUP(-1)
destRows DWORD MAX_PASSENGERS DUP(-1)
destCols DWORD MAX_PASSENGERS DUP(-1)
hasPassenger BYTE MAX_PASSENGERS DUP(0)
passengerInTaxi DWORD - 1; which passenger is in taxi(-1 = none)

; NPC Cars
npcRows DWORD MAX_NPC_CARS DUP(0)
npcCols DWORD MAX_NPC_CARS DUP(0)
npcDirections BYTE MAX_NPC_CARS DUP(0); 0 = Horizontal, 1 = Vertical
npcSpeeds DWORD MAX_NPC_CARS DUP(300)
npcActive BYTE MAX_NPC_CARS DUP(0)

; Game Grid
gameGrid BYTE GRID_ROWS* GRID_COLS DUP('0')

; Score Tracking
successfulDrops DWORD 0
crashes DWORD 0
startTime DWORD ?

; Menu Variables
menuSelection BYTE 0
subMenuSelection BYTE 0
menuOptions BYTE "New Game", 0
BYTE "Continue", 0
BYTE "Difficulty", 0
BYTE "Leaderboard", 0
BYTE "Instructions", 0
BYTE "Exit", 0
numMenuOptions = 6

difficultyOptions BYTE "Easy", 0
BYTE "Medium", 0
BYTE "Hard", 0

gameModeOptions BYTE "Career Mode", 0
BYTE "Time Mode", 0
BYTE "Endless Mode", 0

colorOptions BYTE "Red Taxi", 0
BYTE "Yellow Taxi", 0

; UI Strings
titleStr BYTE "RUSH HOUR TAXI GAME", 0
scoreStr BYTE "Score: ", 0
timeStr BYTE "Time: ", 0
levelStr BYTE "Level: ", 0
modeStr BYTE "Mode: ", 0
passengerStr BYTE "Passengers: ", 0
dropsStr BYTE "Drops: ", 0
crashesStr BYTE "Crashes: ", 0
pauseStr BYTE "GAME PAUSED - Press P to Resume", 0
gameOverStr BYTE "GAME OVER", 0
namePrompt BYTE "Enter your name (15 chars max): ", 0
colorPrompt BYTE "Choose taxi color:", 0
modePrompt BYTE "Select game mode:", 0
diffPrompt BYTE "Select difficulty:", 0
instruct1 BYTE "Controls:", 0
instruct2 BYTE "WASD Keys - Move Taxi", 0
instruct3 BYTE "Spacebar - Pickup/Drop Passenger", 0
instruct4 BYTE "P - Pause/Resume", 0
instruct5 BYTE "ESC - Return to Menu", 0
instruct6 BYTE "Objective: Pick up passengers and", 0
instruct7 BYTE "drop them at their destinations.", 0
instruct8 BYTE "Avoid collisions with other cars!", 0
leaderTitle BYTE "TOP 10 SCORES", 0
leaderHeader BYTE "Rank  Name            Score  Mode", 0
noSaveStr BYTE "No saved game found", 0
saveSuccess BYTE "Game saved successfully!", 0

; Character definitions
taxiChars BYTE 'R', 'Y'; Red and Yellow taxi chars
passengerChar BYTE 'P', 0
destChar BYTE 'D', 0
npcChar BYTE 'C', 0
treeChar BYTE 'T', 0
boxChar BYTE 'B', 0
roadChar BYTE '.', 0

; Leaderboard data structure
MAX_LEADER_ENTRIES = 10
leaderNames BYTE MAX_LEADER_ENTRIES * 16 DUP(' ')
leaderScores DWORD MAX_LEADER_ENTRIES DUP(0)
leaderModes BYTE MAX_LEADER_ENTRIES DUP(0)
numLeaderEntries DWORD 0

; Buffer for input
inputBuffer BYTE 16 DUP(0)

.code
main PROC
    call Randomize
    call LoadLeaderboard
    
GameStart:
    mov gameState, 0
    call ShowMainMenu
    
    ; Check what to do after menu
    cmp gameState, 1      ; Playing
    je GameLoop
    cmp gameState, 4      ; Leaderboard
    je ShowLeaderboardScreen
    cmp gameState, 5      ; Instructions
    je ShowInstructions
    cmp gameState, 255    ; Exit
    je ExitGame
    jmp GameStart         ; Shouldn't happen, but just in case

GameLoop:
    call Clrscr
    
    ; Clear any pending key presses
    mov ecx, 10
ClearBuffer:
    call ReadKey
    loop ClearBuffer
    
    ; Handle input
    call CheckInput
    cmp gameState, 2      ; Paused?
    je PauseLoop
    
    ; Update game state
    call UpdateNPCs
    call CheckCollisions
    call UpdateTimer
    
    ; Draw everything
    call DrawGameScreen
    
    ; Game over check
    call CheckGameOver
    cmp gameState, 3
    je GameOverScreen
    
    ; Delay for smooth movement
    mov eax, taxiSpeed
    call Delay
    
    jmp GameLoop

PauseLoop:
    call DrawPauseScreen
    call CheckPauseInput
    jmp GameLoop

GameOverScreen:
    call ShowGameOver
    jmp GameStart

ShowLeaderboardScreen:
    call ShowLeaderboard
    jmp GameStart

ShowInstructions:
    call ShowInstructionScreen
    jmp GameStart

ExitGame:
    ; Save leaderboard before exiting
    call SaveLeaderboard
    INVOKE ExitProcess, 0
main ENDP

; ==================== MENU SYSTEM ====================
ShowMainMenu PROC
    pushad
    
MenuLoop:
    call Clrscr

    ; Draw title
    mov eax, yellow + (blue * 16)
    call SetTextColor
    mov dl, (SCREEN_WIDTH - 20) / 2
    mov dh, 3
    call Gotoxy
    mov edx, OFFSET titleStr
    call WriteString

    ; Draw menu options
    mov eax, white + (black * 16)
    call SetTextColor

    mov esi, OFFSET menuOptions
    mov ecx, numMenuOptions
    mov dh, 8

DrawMenuOptions:
    mov dl, 35
    call Gotoxy

    ; Highlight selected option
    mov al, numMenuOptions
    sub al, cl
    cmp al, menuSelection
    jne NotSelected
    mov eax, white + (red * 16)
    call SetTextColor
NotSelected:
    
    push edx
    mov edx, esi
    call WriteString
    pop edx

    ; Move to next string
    push ecx
FindNull:
    cmp BYTE PTR[esi], 0
    je FoundNull
    inc esi
    jmp FindNull
FoundNull:
    inc esi
    pop ecx

    add dh, 2
    loop DrawMenuOptions

    ; Get input
    call ReadChar

    cmp al, 'w'
    je MoveUp
    cmp al, 's'
    je MoveDown
    cmp al, 13    ; Enter
    je SelectOption
    cmp al, 27    ; ESC
    je ExitMenu
    jmp MenuLoop

MoveUp:
    cmp menuSelection, 0
    je MenuLoop
    dec menuSelection
    jmp MenuLoop

MoveDown:
    mov al, menuSelection
    cmp al, numMenuOptions - 1
    jge MenuLoop
    inc menuSelection
    jmp MenuLoop

SelectOption:
    movzx eax, menuSelection
    cmp eax, 0    ; New Game
    je NewGameSelected
    cmp eax, 1    ; Continue
    je ContinueSelected
    cmp eax, 2    ; Difficulty
    je DifficultySelected
    cmp eax, 3    ; Leaderboard
    je LeaderboardSelected
    cmp eax, 4    ; Instructions
    je InstructionsSelected
    jmp ExitMenu    ; Exit

NewGameSelected:
    call SetupNewGame
    ; After setting up new game, we need to exit the menu
    mov gameState, 1    ; Set to Playing
    jmp MenuDone    ; Exit menu loop

ContinueSelected:
    cmp hasSavedGame, 0
    je MenuLoop
    call LoadGame
    ; LoadGame already sets gameState to 1
    jmp MenuDone

DifficultySelected:
    call ShowDifficultyMenu
    jmp MenuLoop

LeaderboardSelected:
    mov gameState, 4
    jmp MenuDone

InstructionsSelected:
    mov gameState, 5
    jmp MenuDone

ExitMenu:
    mov gameState, 255    ; Signal to exit

MenuDone:
    popad
    ret
ShowMainMenu ENDP

SetupNewGame PROC
    ; Get player name
    call GetPlayerName

    ; Choose taxi color
    call ChooseTaxiColor

    ; Choose game mode
    call ChooseGameMode

    ; Initialize game
    call InitializeGameData

    ; Set game state to playing
    mov gameState, 1

    ret
SetupNewGame ENDP

GetPlayerName PROC
    pushad

    call Clrscr
    mov dl, 30
    mov dh, 10
    call Gotoxy
    mov edx, OFFSET namePrompt
    call WriteString

    mov dl, 30
    mov dh, 12
    call Gotoxy

    ; Get input
    mov edx, OFFSET playerName
    mov ecx, 15
    call ReadString
    mov playerNameLen, eax

    ; If no name entered, use default
    cmp eax, 0
    jne NameEntered
    mov playerName[0], 'P'
    mov playerName[1], 'l'
    mov playerName[2], 'a'
    mov playerName[3], 'y'
    mov playerName[4], 'e'
    mov playerName[5], 'r'
    mov playerName[6], 0
    mov playerNameLen, 6

NameEntered:
    popad
    ret
GetPlayerName ENDP

ChooseTaxiColor PROC
    pushad

ColorMenu:
    call Clrscr

    mov dl, 35
    mov dh, 8
    call Gotoxy
    mov edx, OFFSET colorPrompt
    call WriteString

    ; Show color options
    mov esi, OFFSET colorOptions
    mov ecx, 2
    mov dh, 10

DrawColorOptions:
    mov dl, 38
    call Gotoxy

    ; Highlight selected
    mov al, 2
    sub al, cl
    cmp al, taxiColor
    jne ColorNotSelected
    mov eax, white + (blue * 16)
    call SetTextColor
ColorNotSelected:

    push edx
    mov edx, esi
    call WriteString
    pop edx

    ; Move to next string
ColorFindNull:
    cmp BYTE PTR[esi], 0
    je ColorFoundNull
    inc esi
    jmp ColorFindNull
ColorFoundNull:
    inc esi

    add dh, 2
    loop DrawColorOptions

    ; Get input
    call ReadChar

    cmp al, 'w'
    je ColorUp
    cmp al, 's'
    je ColorDown
    cmp al, 13
    je ColorSelected
    jmp ColorMenu

ColorUp:
    cmp taxiColor, 0
    je ColorMenu
    dec taxiColor
    jmp ColorMenu

ColorDown:
    cmp taxiColor, 1
    je ColorMenu
    inc taxiColor
    jmp ColorMenu

ColorSelected:
    ; Set speed based on color (Yellow is faster)
    cmp taxiColor, 0    ; Red
    jne YellowTaxi
    mov taxiSpeed, 200
    mov playerSpeed, 200
    jmp ColorDone
YellowTaxi:
    mov taxiSpeed, 150
    mov playerSpeed, 150

ColorDone:
    popad
    ret
ChooseTaxiColor ENDP

ChooseGameMode PROC
    pushad

ModeMenu:
    call Clrscr

    mov dl, 35
    mov dh, 8
    call Gotoxy
    mov edx, OFFSET modePrompt
    call WriteString

    ; Show mode options
    mov esi, OFFSET gameModeOptions
    mov ecx, 3
    mov dh, 10

DrawModeOptions:
    mov dl, 36
    call Gotoxy

    ; Highlight selected
    mov al, 3
    sub al, cl
    cmp al, currentMode
    jne ModeNotSelected
    mov eax, white + (green * 16)
    call SetTextColor
ModeNotSelected:

    push edx
    mov edx, esi
    call WriteString
    pop edx

    ; Move to next string
ModeFindNull:
    cmp BYTE PTR[esi], 0
    je ModeFoundNull
    inc esi
    jmp ModeFindNull
ModeFoundNull:
    inc esi

    add dh, 2
    loop DrawModeOptions

    ; Get input
    call ReadChar

    cmp al, 'w'
    je ModeUp
    cmp al, 's'
    je ModeDown
    cmp al, 13
    je ModeSelected
    jmp ModeMenu

ModeUp:
    cmp currentMode, 0
    je ModeMenu
    dec currentMode
    jmp ModeMenu

ModeDown:
    cmp currentMode, 2
    je ModeMenu
    inc currentMode
    jmp ModeMenu

ModeSelected:
    popad
    ret
ChooseGameMode ENDP

ShowDifficultyMenu PROC
    pushad

DiffMenu:
    call Clrscr

    mov dl, 35
    mov dh, 8
    call Gotoxy
    mov edx, OFFSET diffPrompt
    call WriteString

    ; Show difficulty options
    mov esi, OFFSET difficultyOptions
    mov ecx, 3
    mov dh, 10

DrawDiffOptions:
    mov dl, 38
    call Gotoxy

    ; Highlight selected
    mov al, 3
    sub al, cl
    dec al
    cmp al, difficulty
    jne DiffNotSelected
    mov eax, white + (red * 16)
    call SetTextColor
DiffNotSelected:

    push edx
    mov edx, esi
    call WriteString
    pop edx

    ; Move to next string
DiffFindNull:
    cmp BYTE PTR[esi], 0
    je DiffFoundNull
    inc esi
    jmp DiffFindNull
DiffFoundNull:
    inc esi

    add dh, 2
    loop DrawDiffOptions

    ; Get input
    call ReadChar

    cmp al, 'w'
    je DiffUp
    cmp al, 's'
    je DiffDown
    cmp al, 13
    je DiffSelected
    jmp DiffMenu

DiffUp:
    cmp difficulty, 1
    je DiffMenu
    dec difficulty
    jmp DiffMenu

DiffDown:
    cmp difficulty, 3
    je DiffMenu
    inc difficulty
    jmp DiffMenu

DiffSelected:
    popad
    ret
ShowDifficultyMenu ENDP

; ==================== GAME INITIALIZATION ====================
InitializeGameData PROC
    pushad

    ; Reset game variables
    mov score, 0
    mov successfulDrops, 0
    mov crashes, 0
    mov level, 1

    ; Reset taxi position
    mov taxiRow, 2
    mov taxiCol, 2
    mov passengerInTaxi, -1

    ; Clear passenger arrays
    mov ecx, MAX_PASSENGERS
    mov esi, 0
ClearPassengers:
    mov passengerRows[esi * 4], -1
    mov passengerCols[esi * 4], -1
    mov destRows[esi * 4], -1
    mov destCols[esi * 4], -1
    mov hasPassenger[esi], 0
    inc esi
    loop ClearPassengers

    ; Generate initial game grid
    call GenerateGameGrid

    ; Spawn initial passengers
    call SpawnPassengers

    ; Spawn NPC cars
    call SpawnNPCs

    ; Set start time
    call GetTickCount
    mov startTime, eax

    ; Set time for Time Mode
    mov eax, 0
    mov al, difficulty
    imul eax, 30
    add eax, 30
    mov timeLeft, eax

    popad
    ret
InitializeGameData ENDP

GenerateGameGrid PROC
    pushad

    ; Clear grid
    mov ecx, GRID_ROWS* GRID_COLS
    mov esi, 0
ClearGrid:
    mov gameGrid[esi], '0'
    inc esi
    loop ClearGrid

    ; Add trees(R)
    mov ecx, 8
AddTrees:
    call GetRandomEmptyCell
    mov gameGrid[eax], 'R'
    loop AddTrees

    ; Add boxes(B)
    mov ecx, 6
AddBoxes:
    call GetRandomEmptyCell
    mov gameGrid[eax], 'B'
    loop AddBoxes

    ; Add roads(.)
    mov ecx, 12
AddRoads:
    call GetRandomEmptyCell
    mov gameGrid[eax], '.'
    loop AddRoads

    popad
    ret
GenerateGameGrid ENDP

GetRandomEmptyCell PROC
    ; Returns empty cell index in EAX
TryAgain:
    mov eax, GRID_ROWS* GRID_COLS
    call RandomRange

    ; Check if empty
    cmp gameGrid[eax], '0'
    jne TryAgain

    ; Check not taxi position
    push eax
    mov edx, 0
    mov ebx, GRID_COLS
    div ebx    ; eax = row, edx = col
    cmp eax, taxiRow
    jne NotTaxiRow
    cmp edx, taxiCol
    jne NotTaxiRow
    pop eax
    jmp TryAgain

NotTaxiRow:
    pop eax
    ret
GetRandomEmptyCell ENDP

SpawnPassengers PROC
    pushad

    mov ecx, MAX_PASSENGERS
    mov esi, 0

SpawnLoop:
    push ecx

    ; Find empty spot for passenger
    call GetRandomEmptyCell
    push eax

    ; Convert index to row/col
    mov edx, 0
    mov ebx, GRID_COLS
    div ebx    ; eax = row, edx = col

    ; Store passenger position
    mov passengerRows[esi * 4], eax
    mov passengerCols[esi * 4], edx

    ; Find destination (different from pickup)
    pop eax
FindDestination:
    call GetRandomEmptyCell
    push eax
    mov edx, 0
    mov ebx, GRID_COLS
    div ebx

    ; Check if different from passenger position
    cmp eax, passengerRows[esi * 4]
    jne ValidDest
    cmp edx, passengerCols[esi * 4]
    je FindDestination

ValidDest:
    mov destRows[esi * 4], eax
    mov destCols[esi * 4], edx
    pop eax

    inc esi
    pop ecx
    loop SpawnLoop

    popad
    ret
SpawnPassengers ENDP
SpawnNPCs PROC
    pushad

    ; Initialize ALL NPCs to inactive first
    mov ecx, MAX_NPC_CARS
    mov esi, 0
InitNPCs:
    cmp esi, MAX_NPC_CARS
    jge DoneInit
    mov npcActive[esi], 0
    inc esi
    loop InitNPCs
DoneInit:

    ; Now spawn a few active NPCs
    mov esi, 0
    cmp esi, MAX_NPC_CARS
    jge NoSpawn1
    ; NPC 0
    mov npcRows[0], 0
    mov npcCols[0], 2
    mov npcDirections[0], 0
    mov npcSpeeds[0], 300
    mov npcActive[0], 1
    
    mov esi, 1
    cmp esi, MAX_NPC_CARS
    jge NoSpawn2
    ; NPC 1
    mov npcRows[4], 3
    mov npcCols[4], 0
    mov npcDirections[1], 1
    mov npcSpeeds[4], 300
    mov npcActive[1], 1
    
    mov esi, 2
    cmp esi, MAX_NPC_CARS
    jge NoSpawn3
    ; NPC 2
    mov npcRows[8], GRID_ROWS - 1
    mov npcCols[8], 4
    mov npcDirections[2], 0
    mov npcSpeeds[8], 300
    mov npcActive[2], 1

NoSpawn1:
NoSpawn2:
NoSpawn3:
    popad
    ret
SpawnNPCs ENDP
; ==================== INPUT HANDLING ====================
CheckInput PROC
    call ReadKey
    jz NoInput

    ; Check for regular keys first
    cmp al, 'p'
    je TogglePause
    cmp al, 'P'
    je TogglePause
    cmp al, 27    ; ESC
    je ReturnToMenu
    cmp al, ' '
    je SpacePressed

    ; Check for WASD keys (case-insensitive)
    cmp al, 'w'
    je MoveUp
    cmp al, 'W'
    je MoveUp
    cmp al, 's'
    je MoveDown
    cmp al, 'S'
    je MoveDown
    cmp al, 'a'
    je MoveLeft
    cmp al, 'A'
    je MoveLeft
    cmp al, 'd'
    je MoveRight
    cmp al, 'D'
    je MoveRight

    jmp NoInput

TogglePause:
    cmp gameState, 1
    je PauseGame
    cmp gameState, 2
    je ResumeGame
    jmp NoInput

PauseGame:
    mov gameState, 2
    jmp NoInput

ResumeGame:
    mov gameState, 1
    jmp NoInput

ReturnToMenu:
    call SaveGame
    mov gameState, 0
    jmp NoInput

SpacePressed:
    call HandlePickupDrop
    jmp NoInput

MoveUp:
    cmp taxiRow, 0
    je NoInput
    dec taxiRow
    mov taxiDirection, 0
    jmp NoInput

MoveDown:
    cmp taxiRow, GRID_ROWS - 1
    je NoInput
    inc taxiRow
    mov taxiDirection, 2
    jmp NoInput

MoveLeft:
    cmp taxiCol, 0
    je NoInput
    dec taxiCol
    mov taxiDirection, 3
    jmp NoInput

MoveRight:
    cmp taxiCol, GRID_COLS - 1
    je NoInput
    inc taxiCol
    mov taxiDirection, 1

NoInput:
    ret
CheckInput ENDP

HandlePickupDrop PROC
    pushad

    ; If carrying passenger, try to drop
    cmp passengerInTaxi, -1
    jne TryDrop

    ; Try to pickup passenger
    mov ecx, MAX_PASSENGERS
    mov esi, 0

PickupLoop:
    cmp BYTE PTR hasPassenger[esi], 0
    jne NextPassenger

    ; Check if taxi at passenger location
    mov eax, DWORD PTR passengerRows[esi * 4]
    cmp eax, taxiRow
    jne NextPassenger
    mov eax, passengerCols[esi * 4]
    cmp eax, taxiCol
    jne NextPassenger

    ; Pickup passenger
    mov hasPassenger[esi], 1
    mov passengerInTaxi, esi

    ; Clear passenger from grid (visually)
    mov passengerRows[esi * 4], -1
    mov passengerCols[esi * 4], -1

    ; Add points
    add score, 10

    jmp PickupDone

NextPassenger:
    inc esi
    loop PickupLoop
    jmp PickupDone

TryDrop:
    ; Check if at destination
    mov esi, passengerInTaxi
    mov eax, destRows[esi * 4]
    cmp eax, taxiRow
    jne PickupDone
    mov eax, destCols[esi * 4]
    cmp eax, taxiCol
    jne PickupDone

    ; Successful drop!
    mov passengerInTaxi, -1

    ; Add points
    add score, 50
    inc successfulDrops

    ; Increase speed every 2 drops
    mov eax, successfulDrops
    mov edx, 0
    mov ebx, 2
    div ebx
    cmp edx, 0
    jne NoSpeedIncrease

    ; Increase NPC speeds
    mov ecx, MAX_NPC_CARS
    mov esi, 0
SpeedUpNPCs:
    mov eax, npcSpeeds[esi * 4]
    sub eax, 20
    cmp eax, 50
    jge NotTooFast
    mov eax, 50
NotTooFast:
    mov npcSpeeds[esi * 4], eax
    inc esi
    loop SpeedUpNPCs

NoSpeedIncrease:

    ; Level up check
    mov eax, successfulDrops
    mov edx, 0
    mov ebx, 5
    div ebx
    cmp edx, 0
    jne PickupDone
    inc level

    ; Spawn new passenger
    call SpawnSinglePassenger

PickupDone:
    popad
    ret
HandlePickupDrop ENDP

SpawnSinglePassenger PROC
    pushad

    ; Find empty passenger slot
    mov ecx, MAX_PASSENGERS
    mov esi, 0
FindEmptySlot:
    cmp BYTE PTR hasPassenger[esi], 0
    je FoundSlot
    inc esi
    loop FindEmptySlot
    jmp SpawnDone

FoundSlot:
    ; Find position for passenger
    call GetRandomEmptyCell
    push eax
    mov edx, 0
    mov ebx, GRID_COLS
    div ebx

    mov passengerRows[esi * 4], eax
    mov passengerCols[esi * 4], edx

    ; Find destination
    pop eax
FindDest:
    call GetRandomEmptyCell
    push eax
    mov edx, 0
    mov ebx, GRID_COLS
    div ebx

    cmp eax, passengerRows[esi * 4]
    jne ValidDest2
    cmp edx, passengerCols[esi * 4]
    je FindDest

ValidDest2:
    mov destRows[esi * 4], eax
    mov destCols[esi * 4], edx
    pop eax

SpawnDone:
    popad
    ret
SpawnSinglePassenger ENDP

; ==================== NPC UPDATES ====================
UpdateNPCs PROC
    pushad

    mov ecx, MAX_NPC_CARS
    mov esi, 0
    cmp ecx, 0
    je UpdateDone

NPCLoop:
    cmp npcActive[esi], 0
    je NextNPC

    ; Move based on direction
    mov al, npcDirections[esi]
    cmp al, 0
    jne MoveVertical

    ; Horizontal movement
    mov eax, npcCols[esi * 4]
    cmp eax, GRID_COLS - 1
    jge ReverseHoriz
    inc npcCols[esi * 4]
    jmp CheckBounds
ReverseHoriz:
    mov npcCols[esi * 4], 0
    jmp CheckBounds

MoveVertical:
    ; Vertical movement
    mov eax, npcRows[esi * 4]
    cmp eax, GRID_ROWS - 1
    jge ReverseVert
    inc npcRows[esi * 4]
    jmp CheckBounds
ReverseVert:
    mov npcRows[esi * 4], 0

CheckBounds:
    ; Simple bounds check
    mov eax, npcRows[esi * 4]
    cmp eax, GRID_ROWS
    jl RowOK
    mov npcRows[esi * 4], 0
RowOK:
    mov eax, npcCols[esi * 4]
    cmp eax, GRID_COLS
    jl ColOK
    mov npcCols[esi * 4], 0
ColOK:

NextNPC:
    inc esi
    dec ecx
    jnz NPCLoop

UpdateDone:
    popad
    ret
UpdateNPCs ENDP

; ==================== COLLISION DETECTION ====================
CheckCollisions PROC
    pushad

    ; Check collision with NPC cars
    mov ecx, MAX_NPC_CARS
    mov esi, 0

CollisionLoop:
    cmp npcActive[esi], 0
    je SkipNPC

    mov eax, npcRows[esi * 4]
    cmp eax, taxiRow
    jne SkipNPC
    mov eax, npcCols[esi * 4]
    cmp eax, taxiCol
    jne SkipNPC

    ; Collision detected!
    inc crashes
    sub score, 25
    cmp score, 0
    jge ScoreOK
    mov score, 0

ScoreOK:
    ; Reset taxi position
    mov taxiRow, 2
    mov taxiCol, 2

SkipNPC:
    inc esi
    loop CollisionLoop

    popad
    ret
CheckCollisions ENDP

; ==================== DRAWING FUNCTIONS ====================
DrawGameScreen PROC
    pushad

    call Clrscr

    ; Draw game info panel
    call DrawInfoPanel

    ; Draw game grid
    mov dl, 5
    mov dh, 3
    call Gotoxy

    ; Draw grid with contents
    mov ecx, GRID_ROWS
    mov esi, 0

RowLoop:
    push ecx
    mov ecx, GRID_COLS
    mov edi, 0

ColLoop:
    push ecx

    ; Check what to draw
    ; First check if taxi here
    mov eax, esi
    cmp eax, taxiRow
    jne CheckPassengerHere
    mov eax, edi
    cmp eax, taxiCol
    jne CheckPassengerHere

    ; Draw taxi
    mov eax, yellow + (black * 16)
    cmp taxiColor, 0
    jne TaxiColorSet
    mov eax, red + (black * 16)
TaxiColorSet:
    call SetTextColor
    mov al, 'T'
    call WriteChar
    mov eax, white + (black * 16)
    call SetTextColor
    jmp NextCell

CheckPassengerHere:
    ; Check for passenger at this location
    push esi
    push edi
    mov ecx, MAX_PASSENGERS
    mov ebx, 0

CheckPassengerLoop:
    cmp hasPassenger[ebx], 0
    jne PassengerNotHere

    mov eax, passengerRows[ebx * 4]
    cmp eax, esi
    jne PassengerNotHere
    mov eax, passengerCols[ebx * 4]
    cmp eax, edi
    jne PassengerNotHere

    ; Draw passenger
    mov eax, magenta + (black * 16)
    call SetTextColor
    mov al, 'P'
    call WriteChar
    mov eax, white + (black * 16)
    call SetTextColor
    pop edi
    pop esi
    jmp NextCell

PassengerNotHere:
    inc ebx
    loop CheckPassengerLoop

    ; Check for destination
    mov ecx, MAX_PASSENGERS
    mov ebx, 0

CheckDestLoop:
    cmp hasPassenger[ebx], 0
    jne DestNotHere

    mov eax, destRows[ebx * 4]
    cmp eax, esi
    jne DestNotHere
    mov eax, destCols[ebx * 4]
    cmp eax, edi
    jne DestNotHere

    ; Draw destination
    mov eax, green + (black * 16)
    call SetTextColor
    mov al, 'D'
    call WriteChar
    mov eax, white + (black * 16)
    call SetTextColor
    pop edi
    pop esi
    jmp NextCell

DestNotHere:
    inc ebx
    loop CheckDestLoop

    pop edi
    pop esi

    ; Check for NPC car
    push esi
    push edi
    mov ecx, MAX_NPC_CARS
    mov ebx, 0

CheckNPCLoop:
    cmp npcActive[ebx], 0
    je NPCNotHere

    mov eax, npcRows[ebx * 4]
    cmp eax, esi
    jne NPCNotHere
    mov eax, npcCols[ebx * 4]
    cmp eax, edi
    jne NPCNotHere

    ; Draw NPC car
    mov eax, blue + (black * 16)
    call SetTextColor
    mov al, 'C'
    call WriteChar
    mov eax, white + (black * 16)
    call SetTextColor
    pop edi
    pop esi
    jmp NextCell

NPCNotHere:
    inc ebx
    loop CheckNPCLoop

    pop edi
    pop esi

    ; Check grid object
    mov eax, esi
    imul eax, GRID_COLS
    add eax, edi
    mov al, gameGrid[eax]

    cmp al, 'R'    ; Tree
    je DrawTree
    cmp al, 'B'    ; Box
    je DrawBox
    cmp al, '.'    ; Road
    je DrawRoad
    jmp DrawEmpty

DrawTree:
    mov eax, green + (black * 16)
    call SetTextColor
    mov al, 5    ; Tree symbol
    call WriteChar
    jmp ColorReset

DrawBox:
    mov eax, brown + (black * 16)
    call SetTextColor
    mov al, 254    ; Box symbol
    call WriteChar
    jmp ColorReset

DrawRoad:
    mov eax, gray + (black * 16)
    call SetTextColor
    mov al, '.'
    call WriteChar
    jmp ColorReset

DrawEmpty:
    mov al, ' '
    call WriteChar

ColorReset:
    mov eax, white + (black * 16)
    call SetTextColor

NextCell:
    pop ecx
    inc edi
    dec ecx
    jnz ColLoop

    ; New line for next row
    call Crlf
    pop ecx
    inc esi
    dec ecx
    jnz RowLoop

    ; Draw legend
    mov dl, 5
    mov dh, 20
    call Gotoxy

    mov eax, red + (black * 16)
    call SetTextColor
    mov al, 'T'
    call WriteChar
    mov eax, white + (black * 16)
    call SetTextColor
    mov edx, OFFSET taxiCharStr
    call WriteString
    mWrite " = Taxi | "

    mov eax, magenta + (black * 16)
    call SetTextColor
    mov al, 'P'
    call WriteChar
    mov eax, white + (black * 16)
    call SetTextColor
    mWrite " = Passenger | "

    mov eax, green + (black * 16)
    call SetTextColor
    mov al, 'D'
    call WriteChar
    mWrite " = Destination | "

    mov eax, blue + (black * 16)
    call SetTextColor
    mov al, 'C'
    call WriteChar
    mWrite " = NPC Car"

    popad
    ret
DrawGameScreen ENDP

DrawInfoPanel PROC
    pushad
    
    ; Draw score
    mov dl, 50
    mov dh, 3
    call Gotoxy
    mov edx, OFFSET scoreStr
    call WriteString
    mov eax, score
    call WriteDec
    
    ; DEBUG: Show taxi position
    mov dl, 50
    mov dh, 17
    call Gotoxy
    mWrite "Taxi Pos: "
    mov eax, taxiRow
    call WriteDec
    mWrite ","
    mov eax, taxiCol
    call WriteDec
    
    ; Draw level
    mov dl, 50
    mov dh, 5
    call Gotoxy
    mov edx, OFFSET levelStr
    call WriteString
    mov eax, level
    call WriteDec
    
    ; Draw successful drops
    mov dl, 50
    mov dh, 7
    call Gotoxy
    mov edx, OFFSET dropsStr
    call WriteString
    mov eax, successfulDrops
    call WriteDec
    
    ; Draw crashes
    mov dl, 50
    mov dh, 9
    call Gotoxy
    mov edx, OFFSET crashesStr
    call WriteString
    mov eax, crashes
    call WriteDec
    
    ; Draw passenger status
    mov dl, 50
    mov dh, 11
    call Gotoxy
    mov edx, OFFSET passengerStr
    call WriteString
    
    cmp passengerInTaxi, -1
    je NoPassenger
    mWrite "Carrying"
    jmp StatusDone
NoPassenger:
    mWrite "Available"
StatusDone:
    
    ; Draw time for Time Mode
    cmp currentMode, 1
    jne NotTimeMode
    
    mov dl, 50
    mov dh, 13
    call Gotoxy
    mov edx, OFFSET timeStr
    call WriteString
    mov eax, timeLeft
    call WriteDec
    mWrite " sec"
    
NotTimeMode:
    
    ; Draw player name
    mov dl, 50
    mov dh, 15
    call Gotoxy
    mov edx, OFFSET playerName
    call WriteString
    
    popad
    ret
DrawInfoPanel ENDP

DrawPauseScreen PROC
    pushad
    
    call Clrscr
    
    ; Draw pause message
    mov dl, (SCREEN_WIDTH - 30) / 2
    mov dh, SCREEN_HEIGHT / 2
    call Gotoxy
    
    mov eax, yellow + (black * 16)
    call SetTextColor
    mov edx, OFFSET pauseStr
    call WriteString
    
    ; Draw current score
    mov dl, (SCREEN_WIDTH - 10) / 2
    mov dh, (SCREEN_HEIGHT / 2) + 2
    call Gotoxy
    
    mov eax, white + (black * 16)
    call SetTextColor
    mov edx, OFFSET scoreStr
    call WriteString
    mov eax, score
    call WriteDec
    
    popad
    ret
DrawPauseScreen ENDP

CheckPauseInput PROC
    call ReadChar
    cmp al, 'p'
    je Resume
    cmp al, 'P'
    je Resume
    cmp al, 27    ; ESC
    je ReturnToMenu2
    ret
    
Resume:
    mov gameState, 1
    ret
    
ReturnToMenu2:
    call SaveGame
    mov gameState, 0
    ret
CheckPauseInput ENDP

; ==================== TIMER AND UPDATES ====================
UpdateTimer PROC
    cmp currentMode, 1    ; Only for Time Mode
    jne TimerDone
    
    call GetTickCount
    mov ebx, startTime
    sub eax, ebx
    mov ebx, 1000
    mov edx, 0
    div ebx
    
    mov ebx, timeLeft
    sub ebx, eax
    mov timeLeft, ebx
    
    cmp timeLeft, 0
    jg TimerDone
    mov gameState, 3    ; Game Over
    
TimerDone:
    ret
UpdateTimer ENDP

; ==================== GAME OVER ====================
CheckGameOver PROC
    ; For Career Mode: check level completion
    cmp currentMode, 0
    jne CheckTimeMode
    
    ; Career mode: complete when reaching certain level
    cmp level, 10
    jge CareerComplete
    jmp GameNotOver
    
CareerComplete:
    mov gameState, 3
    jmp GameOverDone
    
CheckTimeMode:
    cmp currentMode, 1
    jne CheckEndless
    
    ; Time mode: check time
    cmp timeLeft, 0
    jle TimeUp
    jmp GameNotOver
    
TimeUp:
    mov gameState, 3
    jmp GameOverDone
    
CheckEndless:
    ; Endless mode: never ends (but could add crash limit)
    cmp crashes, 10
    jge TooManyCrashes
    jmp GameNotOver
    
TooManyCrashes:
    mov gameState, 3
    
GameNotOver:
GameOverDone:
    ret
CheckGameOver ENDP

ShowGameOver PROC
    pushad
    
    call Clrscr
    
    ; Draw game over message
    mov dl, (SCREEN_WIDTH - 9) / 2
    mov dh, 8
    call Gotoxy
    
    mov eax, red + (black * 16)
    call SetTextColor
    mov edx, OFFSET gameOverStr
    call WriteString
    
    ; Draw final score
    mov dl, (SCREEN_WIDTH - 15) / 2
    mov dh, 10
    call Gotoxy
    
    mov eax, yellow + (black * 16)
    call SetTextColor
    mWrite "Final Score: "
    mov eax, score
    call WriteDec
    
    ; Update leaderboard
    call UpdateLeaderboard
    
    ; Ask to save score
    mov dl, (SCREEN_WIDTH - 20) / 2
    mov dh, 12
    call Gotoxy
    mWrite "Press any key to continue"
    
    call ReadChar
    
    popad
    ret
ShowGameOver ENDP

; ==================== LEADERBOARD SYSTEM ====================
LoadLeaderboard PROC
    pushad

    ; For now, just initialize with empty leaderboard
    mov numLeaderEntries, 0
    
    popad
    ret
LoadLeaderboard ENDP

SaveLeaderboard PROC
    pushad
    ; Simple implementation - doesn't actually save to file in this version
    popad
    ret
SaveLeaderboard ENDP

UpdateLeaderboard PROC
    pushad
    ; Simple implementation
    popad
    ret
UpdateLeaderboard ENDP

ShowLeaderboard PROC
    pushad

LeaderboardScreen:
    call Clrscr

    ; Draw title
    mov dl, (SCREEN_WIDTH - 13) / 2
    mov dh, 3
    call Gotoxy

    mov eax, cyan + (black * 16)
    call SetTextColor
    mov edx, OFFSET leaderTitle
    call WriteString

    ; Draw header
    mov dl, 20
    mov dh, 6
    call Gotoxy

    mov eax, white + (black * 16)
    call SetTextColor
    mov edx, OFFSET leaderHeader
    call WriteString

    ; Check if we have entries
    cmp numLeaderEntries, 0
    jne HasEntries
    
    ; No entries message
    mov dl, 30
    mov dh, 10
    call Gotoxy
    mWrite "No scores yet!"
    jmp WaitForInput

HasEntries:
    ; Simple display - would need full implementation
    mov dl, 30
    mov dh, 10
    call Gotoxy
    mWrite "Leaderboard placeholder"

WaitForInput:
    mov dl, 30
    mov dh, 22
    call Gotoxy
    mWrite "Press ESC to return to menu"

    call ReadChar
    cmp al, 27
    jne LeaderboardScreen

ReturnFromLeaderboard:
    mov gameState, 0

    popad
    ret
ShowLeaderboard ENDP

; ==================== INSTRUCTIONS ====================
ShowInstructionScreen PROC
    pushad

    call Clrscr

    ; Draw title
    mov dl, (SCREEN_WIDTH - 12) / 2
    mov dh, 3
    call Gotoxy

    mov eax, yellow + (black * 16)
    call SetTextColor
    mWrite "INSTRUCTIONS"

    ; Draw instructions
    mov eax, white + (black * 16)
    call SetTextColor

    mov dl, 20
    mov dh, 6
    call Gotoxy
    mov edx, OFFSET instruct1
    call WriteString

    mov dl, 20
    mov dh, 8
    call Gotoxy
    mov edx, OFFSET instruct2
    call WriteString

    mov dl, 20
    mov dh, 9
    call Gotoxy
    mov edx, OFFSET instruct3
    call WriteString

    mov dl, 20
    mov dh, 10
    call Gotoxy
    mov edx, OFFSET instruct4
    call WriteString

    mov dl, 20
    mov dh, 11
    call Gotoxy
    mov edx, OFFSET instruct5
    call WriteString

    mov dl, 20
    mov dh, 13
    call Gotoxy
    mov edx, OFFSET instruct6
    call WriteString

    mov dl, 20
    mov dh, 14
    call Gotoxy
    mov edx, OFFSET instruct7
    call WriteString

    mov dl, 20
    mov dh, 15
    call Gotoxy
    mov edx, OFFSET instruct8
    call WriteString

    ; Wait for input
    mov dl, 30
    mov dh, 22
    call Gotoxy
    mWrite "Press ESC to return to menu"

    call ReadChar

    popad
    ret
ShowInstructionScreen ENDP

; ==================== SAVE / LOAD GAME ====================
SaveGame PROC
    pushad
    ; Simple save implementation
    mov hasSavedGame, 1
    popad
    ret
SaveGame ENDP

LoadGame PROC
    pushad
    ; Simple load implementation
    ; Just initialize a new game for now
    call InitializeGameData
    mov gameState, 1
    popad
    ret
LoadGame ENDP

END main