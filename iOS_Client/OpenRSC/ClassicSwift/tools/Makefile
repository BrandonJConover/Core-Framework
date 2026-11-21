# Golden-data dumpers: small C programs that run the real rsc-c code and print
# what it produced, so the Swift port's tests can compare against it.
#
#   make -C iOS_Client/OpenRSC/ClassicSwift/tools golden
#
# Links against the headless engine objects (RSCEngine/tools), built first.

ENGINE := ../../RSCEngine
ENGINE_OBJ = $(filter-out %/headless_main.o,$(wildcard $(ENGINE)/tools/build/obj/*.o))
CFLAGS += -std=gnu99 -fwrapv -O2 -I$(ENGINE)/shim -I$(ENGINE)/include \
          -I$(ENGINE)/rsc-c-src -I$(ENGINE)/rsc-c-src/lib \
          -DSDL2 -DRENDER_SW -DANDROID -w
LDLIBS += -lm -lpthread
CACHE := $(ENGINE)/rsc-cache
GOLDEN := ../Tests/RSCClassicTests/Golden
TOOLS := build/jagdump build/gamedata build/surfacedump

all: $(TOOLS)

engine:
	$(MAKE) -C $(ENGINE)/tools

build/%: %.c engine | build
	$(CC) $(CFLAGS) -o $@ $< $(ENGINE_OBJ) $(LDLIBS)

build:
	mkdir -p $@

golden: $(TOOLS)
	mkdir -p $(GOLDEN)/jag
	for f in $(CACHE)/*.jag $(CACHE)/*.mem; do \
		build/jagdump $$f > $(GOLDEN)/jag/`basename $$f`.txt; done
	build/gamedata $(CACHE)/config85.jag 1 85 > $(GOLDEN)/gamedata-members.txt
	build/gamedata $(CACHE)/config85.jag 0 85 > $(GOLDEN)/gamedata-free.txt
	build/surfacedump $(CACHE) > $(GOLDEN)/surface.txt

.PHONY: all engine golden
