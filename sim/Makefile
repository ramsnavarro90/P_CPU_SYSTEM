# sim/Makefile — Icarus Verilog simulation
#
# Targets:
#   make sim_rom   — compile and run wb_rom testbench
#   make sim_sram  — compile and run wb_sram testbench
#   make all       — run both
#   make clean     — remove build artifacts

IVERILOG := iverilog
VVP      := vvp

SRC  := ../source/design
TB   := ../source/tb

.PHONY: all sim_rom sim_sram clean

all: sim_rom sim_sram

# --- ROM ---
sim_rom: tb_rom.vvp
	$(VVP) $<

tb_rom.vvp: $(SRC)/wb_rom.v $(TB)/tb_wb_rom.v
	$(IVERILOG) -g2005-sv -o $@ $^

# --- SRAM ---
sim_sram: tb_sram.vvp
	$(VVP) $<

tb_sram.vvp: $(SRC)/wb_sram.v $(TB)/tb_wb_sram.v
	$(IVERILOG) -g2005-sv -o $@ $^

clean:
	rm -f *.vvp *.vcd