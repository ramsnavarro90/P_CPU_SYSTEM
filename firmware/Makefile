# firmware/Makefile — Build RV32I bare-metal firmware
#
# Toolchain : riscv64-unknown-elf  (adjust CROSS if using xPack: riscv-none-elf)
# ISA       : RV32I
# ABI       : ilp32

CROSS   := riscv64-unknown-elf
CC      := $(CROSS)-gcc
OBJCOPY := $(CROSS)-objcopy
OBJDUMP := $(CROSS)-objdump

CFLAGS  := -march=rv32i -mabi=ilp32 \
           -Os -ffreestanding -nostdlib \
           -Wall -Wextra

LDFLAGS := -march=rv32i -mabi=ilp32 \
           -nostdlib -T link.ld

SRCS    := crt0.S main.c
OBJS    := crt0.o main.o
TARGET  := firmware

.PHONY: all dump clean

all: $(TARGET).hex

# --- Compile ---
crt0.o: crt0.S
	$(CC) $(CFLAGS) -c $< -o $@

main.o: main.c
	$(CC) $(CFLAGS) -c $< -o $@

# --- Link ---
$(TARGET).elf: $(OBJS)
	$(CC) $(LDFLAGS) $^ -o $@

# --- Raw binary ---
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# --- Verilog hex for $readmemh ---
$(TARGET).hex: $(TARGET).bin
	python3 bin2hex.py $< $@
	cp $(TARGET).hex ../sim/firmware.hex
	@echo "Copied to ../sim/firmware.hex"

# --- Disassembly (useful to verify _start lands at 0x0) ---
dump: $(TARGET).elf
	$(OBJDUMP) -d -M no-aliases $<

clean:
	rm -f *.o *.elf *.bin *.hex