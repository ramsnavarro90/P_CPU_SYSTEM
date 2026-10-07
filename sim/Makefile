# sim/Makefile — Icarus Verilog simulation
#
# Targets:
#   make sim_rom   — wb_rom unit test
#   make sim_sram  — wb_sram unit test
#   make sim_soc   — full SoC system test
#   make all       — run all three
#   make clean     — remove build artifacts

IVERILOG := iverilog
VVP      := vvp
FLAGS    := -g2005-sv

SRC  := ../source/design
TB   := ../source/tb
PICO := $(SRC)/picorv32

.PHONY: all sim_rom sim_sram sim_soc clean

all: sim_rom sim_sram sim_soc

# --- ROM unit test ---
sim_rom: tb_rom.vvp
	$(VVP) $<

tb_rom.vvp: $(SRC)/wb_rom.v $(TB)/tb_wb_rom.v
	$(IVERILOG) $(FLAGS) -o $@ $^

# --- SRAM unit test ---
sim_sram: tb_sram.vvp
	$(VVP) $<

tb_sram.vvp: $(SRC)/wb_sram.v $(TB)/tb_wb_sram.v
	$(IVERILOG) $(FLAGS) -o $@ $^

# --- Full SoC system test ---
sim_soc: tb_soc.vvp
	$(VVP) $<

tb_soc.vvp: $(PICO)/picorv32.v   \
            $(SRC)/wb_rom.v       \
            $(SRC)/wb_sram.v      \
            $(SRC)/wb_gpio.v      \
            $(SRC)/soc_top.v      \
            $(TB)/tb_soc_top.v
	$(IVERILOG) $(FLAGS) -o $@ $^

clean:
	rm -f *.vvp *.vcd