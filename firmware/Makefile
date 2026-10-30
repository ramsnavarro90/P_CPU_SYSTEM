# firmware/Makefile
#
# Usage:
#   make               → compiles apps/default/main.c
#   make APP=arithmetic → compiles apps/arithmetic/main.c

CROSS   := riscv64-unknown-elf
CC      := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
OBJDUMP := $(CROSS)-objdump

# Compilation flags - add mul/div hardware support for the arithmetic test app
CFLAGS  := -march=rv32im -mabi=ilp32 \
           -Os -ffreestanding -nostdlib \
           -fno-builtin                 \
           -fno-tree-loop-distribute-patterns \
		   -I include                       \
           -Wall -Wextra

LDFLAGS := -march=rv32im -mabi=ilp32 \
           -nostdlib -T link.ld

APP      ?= default
MAIN_SRC := apps/$(APP)/main.c
TARGET   := firmware

.PHONY: all dump clean

all: $(TARGET).hex
	@echo "Built app: $(APP)"

# --- Compile ---
crt0.o: crt0.S
	$(CC) $(CFLAGS) -c $< -o $@

main.o: $(MAIN_SRC)
	$(CC) $(CFLAGS) -c $< -o $@

# --- Link ---
# Use of -lgcc is required for __mulsi3 and __divsi3 for software multiply/divide
# The use of -lgcc is only required if the firmware app uses software multiply/divide
# (i.e. if the CPU does not have hardware multiply/divide support)
$(TARGET).elf: crt0.o main.o
	$(CC) $(LDFLAGS) $^ -lgcc -o $@

# --- Raw binary ---
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# --- Verilog hex for $readmemh ---
$(TARGET).hex: $(TARGET).bin
	python3 bin2hex.py $< $@
	cp $(TARGET).hex ../sim/firmware.hex
	@echo "Copied to ../sim/firmware.hex"

# --- Disassembly ---
dump: $(TARGET).elf
	$(OBJDUMP) -d -M no-aliases $<

clean:
	rm -f *.o *.elf *.bin *.hex

# -----------------------------------------------------------------------------
# Flash image: application linked to run from SRAM (loaded by the bootloader)
#   make flash APP=<name>   -> flash.hex (bytes + header), copied to ../sim/
# -----------------------------------------------------------------------------
.PHONY: flash

flash_main.o: $(MAIN_SRC)
	$(CC) $(CFLAGS) -c $< -o $@

flash.elf: crt0.o flash_main.o link_sram.ld
	$(CC) -march=rv32im -mabi=ilp32 -nostdlib -T link_sram.ld crt0.o flash_main.o -lgcc -o $@

flash.bin: flash.elf
	$(OBJCOPY) -O binary $< $@

flash.hex: flash.bin
	python3 bin2hex.py $< $@ --flash
	cp $@ ../sim/flash.hex
	@echo "Copied to ../sim/flash.hex"

flash: flash.hex
	@echo "Built flash image for app: $(APP)"