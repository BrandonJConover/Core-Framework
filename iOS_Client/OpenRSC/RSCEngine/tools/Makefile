# Builds the headless rsc-c driver used to test the embedded engine and the
# SDL shim on Linux/macOS without a display. Same flags as the iOS target.
#
#   make -C iOS_Client/OpenRSC/RSCEngine/tools
#   ./iOS_Client/OpenRSC/RSCEngine/tools/build/headless ...

ENGINE := ..
SRC := $(wildcard $(ENGINE)/rsc-c-src/*.c $(ENGINE)/rsc-c-src/lib/*.c \
        $(ENGINE)/rsc-c-src/lib/rsa/*.c $(ENGINE)/rsc-c-src/ui/*.c \
        $(ENGINE)/rsc-c-src/custom/*.c) $(ENGINE)/shim/rsc_sdl_shim.c
OBJ := $(patsubst %.c,build/obj/%.o,$(notdir $(SRC)))
VPATH := $(sort $(dir $(SRC)))

# Keep in sync with RSCEngine settings in ../../project.yml
CFLAGS += -std=gnu99 -fwrapv -O2 -g -I$(ENGINE)/shim -I$(ENGINE)/include \
          -DSDL2 -DRENDER_SW -DANDROID \
          -Wno-unused-result -Wno-format-truncation -Wno-stringop-truncation
LDLIBS += -lm -lpthread

build/headless: $(OBJ) build/obj/headless_main.o
	$(CC) -o $@ $^ $(LDLIBS)

# rsc-c's main() becomes rsc_c_main(), which the shim calls on its thread
build/obj/%.o: %.c | build/obj
	$(CC) $(CFLAGS) -Dmain=rsc_c_main -c -o $@ $<

build/obj/headless_main.o: headless.c | build/obj
	$(CC) $(CFLAGS) -c -o $@ $<

build/obj:
	mkdir -p $@

clean:
	rm -rf build

.PHONY: clean
