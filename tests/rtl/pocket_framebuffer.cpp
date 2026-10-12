#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "Vpdc_framebuffer.h"

static uint16_t pixel(unsigned frame, unsigned address) {
    return uint16_t((address*73u + frame*997u + 0x1234u) & 0x7fff);
}
static uint32_t rgb(uint16_t value) {
    auto expand=[](unsigned v) {return (v<<3)|(v>>2);};
    return expand(value>>10)<<16 | expand((value>>5)&31)<<8 | expand(value&31);
}
int main(int argc,char** argv) {
    const uint64_t producer_delay=argc>1 ? std::strtoull(argv[1],nullptr,10) : 0;
    const bool burst=argc>2;
    bool backpressured=false;
    Vpdc_framebuffer dut;
    std::array<std::array<uint16_t,115200>,2> ram{};
    struct Transaction {unsigned remaining=0,address=0,data=0;bool write=false;};
    std::array<Transaction,2> transaction{};
    uint64_t time=0;
    unsigned memory_phase=0,video_phase=0,model_phase=0,model_cycle=0;
    unsigned source_frame=0,source_address=0,display_frame=0,display_address=0;
    bool producing=false;
    auto fail=[&](const char* reason) {
        std::fprintf(stderr,"Pocket framebuffer: %s at frame %u pixel %u time %llu\n",reason,display_frame,display_address,time);
        std::exit(1);
    };
    auto tick=[&] {
        ++time;
        bool system=(time&1)==0, memory=dut.memory_clk, video=dut.video_clk;
        memory_phase+=266481580;
        if (memory_phase>=400000000) {memory_phase-=400000000;memory=!memory;}
        video_phase+=24598300;
        if (video_phase>=400000000) {video_phase-=400000000;video=!video;}
        bool video_rise=video && !dut.video_clk;
        if (system && !dut.system_clk) {
            dut.pixel_valid=0;
            if (!dut.reset && time>=1000+producer_delay) {
                if (burst) producing=source_frame<4;
                else {
                model_phase+=27000000;
                if (model_phase>=200000000) {
                    model_phase-=200000000;
                    if (model_cycle%1716==0 && model_cycle/1716<240) {
                        if (producing) fail("producer failed to finish the previous scanline");
                        producing=true;
                    }
                    if (++model_cycle==1716*262) {model_cycle=0;source_frame++;}
                }
                }
                if (producing && !dut.pixel_ready) backpressured=true;
                if (producing && dut.pixel_ready) {
                    dut.pixel_valid=1;dut.pixel_x=source_address%320;dut.pixel_y=source_address/320;
                    dut.pixel_data=pixel(source_frame,source_address);
                    source_address++;
                    if (source_address%320==0) producing=false;
                    if (source_address==76800) {source_address=0;if (burst) source_frame++;}
                }
            }
        }
        if (memory && !dut.memory_clk) {
            dut.memory_valid=0;
            for (unsigned chip=0;chip<2;chip++) {
                auto& item=transaction[chip];
                bool busy=item.remaining!=0;
                if (busy && --item.remaining==0) {
                    if (item.write) ram[chip][item.address]=uint16_t(item.data);
                    else {
                        dut.memory_valid|=1u<<chip;
                        uint32_t mask=0xffffu<<(chip*16);
                        dut.memory_q=(dut.memory_q&~mask)|(uint32_t(ram[chip][item.address])<<(chip*16));
                    }
                }
                if ((dut.memory_read|dut.memory_write)&(1u<<chip)) {
                    if (busy) fail("PSRAM request while busy");
                    if ((dut.memory_read&dut.memory_write)&(1u<<chip)) fail("simultaneous read and write on one die");
                    item.address=unsigned((dut.memory_address>>(chip*22))&0x3fffff);
                    if (item.address>=115200) fail("PSRAM address exceeds framebuffer");
                    item.write=dut.memory_write&(1u<<chip);
                    item.data=(dut.memory_data>>(chip*16))&0xffff;
                    item.remaining=item.write ? 14+(item.address%3) : 15;
                }
            }
            dut.memory_busy=(transaction[0].remaining ? 1 : 0)|(transaction[1].remaining ? 2 : 0);
        }
        dut.system_clk=system;dut.memory_clk=memory;dut.video_clk=video;dut.eval();
        if (dut.reset) return;
        if (dut.underflow) fail("scanout FIFO underflow");
        if (dut.write_fault) fail("invalid producer sequence");
        if (dut.dropped_frames) fail("dropped frame");
        if (video_rise && dut.video_de) {
            if (dut.video_rgb!=rgb(pixel(display_frame,display_address))) fail("RGB555 conversion, frame sequence or pixel order mismatch");
            if (++display_address==76800) {display_address=0;display_frame++;}
        }
    };
    dut.reset=1;for (unsigned n=0;n<1000;n++) tick();dut.reset=0;
    while (display_frame<4 && time<40000000) tick();
    if (display_frame!=4) fail("display did not produce four complete frames");
    if (burst && !backpressured) fail("burst producer never exercised backpressure");
    std::printf("Pocket framebuffer: four complete 320x240 frames, independent clocks, PSRAM latency, RGB555 and ordered triple buffering passed\n");
}
