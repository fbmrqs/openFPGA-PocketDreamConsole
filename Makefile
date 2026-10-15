.DEFAULT_GOAL := help

SDK_ROOT := .deps/openfpga-sdk
SDK_DIR := $(SDK_ROOT)/src/sdk
BUILD_DIR := build/pocket
OBJ_DIR := build/pocket/obj
USE_SDK_CONTAINER ?= 0
CXXFLAGS := -std=c++20 -O3 -flto -D_DEFAULT_SOURCE -fno-strict-aliasing -Wno-unused-parameter -Ithird_party/veesem -Isrc
LDFLAGS := -O3 -flto
SRCS_CXX := src/main.cpp src/pdc.cpp $(wildcard third_party/veesem/core/spg200/*.cpp) $(SDK_DIR)/of_cxxabi.cpp

# Only the retired software target needs the RISC-V SDK.
ifneq ($(filter software package setup,$(MAKECMDGOALS)),)
include $(SDK_DIR)/sdk.mk
endif

ENGINE := src/pdc.cpp $(wildcard third_party/veesem/core/spg200/*.cpp)
HEADERS := $(wildcard src/*.h third_party/veesem/core/*.h third_party/veesem/core/spg200/*.h)

.PHONY: all software headless trace check package setup help check-release
all: fpga
software: $(BUILD_DIR)/app.elf

help:
	@echo 'Native core: make fpga, rtl-test, rtl-pocket-test, rtl-clock-test'
	@echo 'ROM-free host checks: make check-release'
	@echo 'Public packaging: python3 tools/release.py --workspace <qualified-workspace>'
	@echo 'Reference tools: make headless, trace, audio-replay'
	@echo 'Retired software target: make software (requires openfpgaSDK)'

check-release:
	python3 -m unittest discover -s tests -p test_release.py
	python3 -m unittest discover -s tests -p native_validation.py
	python3 tools/check_repository.py

$(APP_CXX_OBJS): $(HEADERS) Makefile

build/pdc-headless: tests/headless.cpp $(ENGINE) $(HEADERS) Makefile
	mkdir -p build
	c++ -std=c++20 -O3 -flto -fno-strict-aliasing -Wall -Wextra -Wno-unused-parameter -Ithird_party/veesem -Isrc tests/headless.cpp $(ENGINE) -o $@

headless: build/pdc-headless

build/pdc-trace: tools/trace.cpp $(ENGINE) $(HEADERS)
	mkdir -p build
	c++ -std=c++20 -O2 -fno-strict-aliasing -DPDC_CPU_TRACE -Wall -Wextra -Wno-unused-parameter -Ithird_party/veesem -Isrc tools/trace.cpp $(ENGINE) -o $@

trace: build/pdc-trace

build/test-audio: tests/audio.cpp src/audio.h third_party/veesem/core/portable.h
	mkdir -p build
	c++ -std=c++20 -O2 -Wall -Wextra -Ithird_party/veesem -Isrc tests/audio.cpp -o $@

check: headless build/test-audio
	python3 tests/package.py
	./build/test-audio
	./build/pdc-headless pdc_pink.u2 1800
	./build/pdc-headless pdc100.bin 1800

package: software
	python3 tools/package.py

setup:
	bash $(SDK_ROOT)/scripts/setup.sh --yes

.PHONY: rtl-test rtl-system-test fpga-template fpga package-native
rtl-test:
	bash tools/fpga/test.sh

rtl-system-test:
	bash tools/fpga/system-test.sh pdc_pink.u2 1800
	bash tools/fpga/system-test.sh pdc100.bin 1800
	bash tools/fpga/system-test.sh pdc_pink.u2 1800 paced
	bash tools/fpga/system-test.sh pdc100.bin 1800 paced

fpga-template:
	bash tools/fpga/quartus.sh template

fpga:
	bash tools/fpga/quartus.sh native

package-native:
	python3 tools/package_native.py

.PHONY: rtl-clock-test rtl-pocket-test
rtl-clock-test:
	bash tools/fpga/slow-clock-test.sh

rtl-pocket-test:
	bash tools/fpga/pocket-system-test.sh pdc_pink.u2 1800
	bash tools/fpga/pocket-system-test.sh pdc100.bin 1800

.PHONY: audio-replay
audio-replay: build/pdc-audio-replay

build/pdc-audio-replay: tools/audio-replay.cpp src/audio.h $(ENGINE)
	mkdir -p build
	c++ -std=c++20 -O3 -fno-strict-aliasing -Ithird_party/veesem -Isrc tools/audio-replay.cpp $(ENGINE) -o $@
