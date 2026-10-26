# sim/Makefile — Icarus Verilog simulation
#
# Each sim_<app> target compiles its firmware automatically before simulating.
# Unit tests (sim_rom, sim_sram, sim_uart, sim_timer) need no firmware.

IVERILOG     := iverilog
VVP          := vvp
FLAGS        := -g2005-sv
FIRMWARE_DIR := ../firmware

SRC  := ../source/design
TB   := ../source/tb
PICO := $(SRC)/picorv32

# -----------------------------------------------------------------------------
# Firmware build helper — called by each system-level sim target
# Usage: $(call build_fw,app_name)
# -----------------------------------------------------------------------------
define build_fw
	@echo ">>> Building firmware APP=$(1)..."
	$(MAKE) -C $(FIRMWARE_DIR) clean
	$(MAKE) -C $(FIRMWARE_DIR) APP=$(1)
endef

.PHONY: all sim_rom sim_sram sim_uart sim_timer \
        sim_soc sim_arithmetic sim_muldiv sim_cfg \
        sim_echo sim_timer_soc sim_i2c clean

all: sim_rom sim_sram sim_uart sim_timer sim_i2c

# -----------------------------------------------------------------------------
# Unit tests (no firmware needed)
# -----------------------------------------------------------------------------
sim_rom: tb_rom.vvp
	$(VVP) $<

tb_rom.vvp: $(SRC)/wb_rom.v $(TB)/tb_wb_rom.v
	$(IVERILOG) $(FLAGS) -o $@ $^

sim_sram: tb_sram.vvp
	$(VVP) $<

tb_sram.vvp: $(SRC)/wb_sram.v $(TB)/tb_wb_sram.v
	$(IVERILOG) $(FLAGS) -o $@ $^

sim_uart: tb_uart.vvp
	$(VVP) $<

tb_uart.vvp: $(SRC)/wb_uart.v $(TB)/tb_wb_uart.v
	$(IVERILOG) $(FLAGS) -o $@ $^

sim_timer: tb_timer.vvp
	$(VVP) $<

tb_timer.vvp: $(SRC)/wb_timer.v $(TB)/tb_wb_timer.v
	$(IVERILOG) $(FLAGS) -o $@ $^

sim_spi: tb_spi.vvp
	$(VVP) $<

tb_spi.vvp: $(SRC)/wb_spi.v $(TB)/tb_wb_spi.v
	$(IVERILOG) $(FLAGS) -o $@ $^

# -----------------------------------------------------------------------------
# Shared RTL sources for all system-level tests
# -----------------------------------------------------------------------------
I2C_CORE := $(SRC)/i2c_core/axis_fifo.v \
			$(SRC)/i2c_core/i2c_master.v \
            $(SRC)/i2c_core/i2c_master_wbs_8.v

SOC_SRCS := $(PICO)/picorv32.v  \
            $(SRC)/wb_rom.v      \
            $(SRC)/wb_sram.v     \
            $(SRC)/wb_gpio.v     \
            $(SRC)/wb_uart.v     \
            $(SRC)/wb_cfg.v      \
            $(SRC)/wb_timer.v    \
			$(SRC)/wb_spi.v      \
			$(I2C_CORE)          \
			$(SRC)/wb_i2c.v      \
            $(SRC)/soc_top.v     \
            $(TB)/uart_monitor.v

# -----------------------------------------------------------------------------
# System-level tests (auto-compile firmware before simulation)
# -----------------------------------------------------------------------------
sim_soc: tb_soc.vvp
	$(call build_fw,default)
	$(VVP) $<

tb_soc.vvp: $(SOC_SRCS) $(TB)/tb_soc_top.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_top.v

sim_arithmetic: tb_arithmetic.vvp
	$(call build_fw,arithmetic)
	$(VVP) $<

tb_arithmetic.vvp: $(SOC_SRCS) $(TB)/tb_soc_arithmetic.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_arithmetic.v

sim_muldiv: tb_muldiv.vvp
	$(call build_fw,muldiv)
	$(VVP) $<

tb_muldiv.vvp: $(SOC_SRCS) $(TB)/tb_soc_muldiv.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_muldiv.v

sim_cfg: tb_cfg.vvp
	$(call build_fw,cfg_demo)
	$(VVP) $<

tb_cfg.vvp: $(SOC_SRCS) $(TB)/tb_soc_cfg.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_cfg.v

sim_echo: tb_echo.vvp
	$(call build_fw,uart_echo)
	$(VVP) $<

tb_echo.vvp: $(SOC_SRCS) $(TB)/tb_soc_echo.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_echo.v

sim_timer_soc: tb_timer_soc.vvp
	$(call build_fw,timer_demo)
	$(VVP) $<

tb_timer_soc.vvp: $(SOC_SRCS) $(TB)/tb_soc_timer.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_timer.v

sim_spi_soc: tb_spi_soc.vvp
	$(call build_fw,spi_demo)
	$(VVP) $<

tb_spi_soc.vvp: $(SOC_SRCS) $(TB)/tb_soc_spi.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_spi.v

sim_i2c: tb_i2c.vvp
	$(VVP) $<

tb_i2c.vvp: $(I2C_CORE) $(SRC)/wb_i2c.v $(TB)/tb_wb_i2c.v
	$(IVERILOG) $(FLAGS) -o $@ $^

sim_i2c_soc: tb_i2c_soc.vvp
	$(call build_fw,i2c_demo)
	$(VVP) $<

tb_i2c_soc.vvp: $(SOC_SRCS) $(TB)/tb_soc_i2c.v
	$(IVERILOG) $(FLAGS) -o $@ $(SOC_SRCS) $(TB)/tb_soc_i2c.v

# -----------------------------------------------------------------------------
clean:
	rm -f *.vvp *.vcd