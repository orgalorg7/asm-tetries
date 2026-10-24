NASM ?= nasm
LD   ?= ld

NASMFLAGS := -f elf64 -g -F dwarf
LDFLAGS   := --build-id=none

.PHONY: all clean debug test check demo benchmark versus showcase match magic forecast

all: tetris

tetris: tetris.o
	$(LD) $(LDFLAGS) -o $@ $<

tetris.o: tetris.asm game_state.inc copilot.asm cli.asm dashboard.asm arena.asm arena_view.asm arena_cli.asm multiverse.asm multiverse_view.asm multiverse_cli.asm tests/copilot.asm tests/arena.asm tests/multiverse.asm
	$(NASM) $(NASMFLAGS) $< -o $@

debug: tetris
	gdb ./tetris

test: tetris
	./tetris --test

check: test
	python3 tests/integration.py

demo: tetris
	./tetris --demo

versus: tetris
	./tetris --versus

showcase: tetris
	./tetris --arena-demo

magic: tetris
	./tetris --multiverse $(SEED)

forecast: tetris
	./tetris --forecast $(SEED)

MATCH_SECONDS ?= 180
match: tetris
	./tetris --match $(MATCH_SECONDS) $(SEED)

PIECES ?= 1000
SEED ?= 12648430
benchmark: tetris
	./tetris --benchmark $(PIECES) $(SEED)

clean:
	rm -f tetris tetris.o
