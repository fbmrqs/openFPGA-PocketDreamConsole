#include <array>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>
#include "core/portable.h"
#include "core/common.h"
#define private public
#include "pdc.h"
#undef private
#include "Vpdc_spu.h"
int main() {
    Pdc reference("pdc_pink.u2");if (!reference.Ready()) return 2;
    Vpdc_spu dut;std::mt19937 random{0x535055};
    bool pending=false;uint32_t address=0;int delay=0;
    std::vector<uint16_t> actual;
    auto tick=[&] {
        dut.clk=0;dut.eval();dut.memory_ack=0;
        if (dut.memory_request) {
            if (!pending) {pending=true;address=dut.memory_address;delay=random()%4;}
            if (address!=dut.memory_address) std::abort();
            if (delay--==0) {dut.memory_ack=1;dut.memory_data=reference.Chip().ReadWord(address);pending=false;}
        } else if (pending) std::abort();
        dut.clk=1;dut.eval();
        if (dut.sample_valid) {actual.push_back(uint16_t(dut.sample_left)^0x8000);actual.push_back(uint16_t(dut.sample_right)^0x8000);}
    };
    auto write=[&](unsigned addr,uint16_t value) {
        reference.Chip().WriteWord(addr,value);dut.register_address=addr;dut.register_data=value;
        dut.register_write=1;tick();dut.register_write=0;
    };
    reference.Reset();dut.reset=1;tick();dut.reset=0;tick();actual.clear();
    reference.Chip().spu_.RunCycles(96);auto silent=reference.Chip().GetAudio();
    dut.advance=1;dut.cycles=96;tick();dut.advance=0;
    unsigned silent_clocks=0;while(dut.busy && silent_clocks<100){tick();silent_clocks++;}
    if(dut.busy || silent_clocks>12){std::fprintf(stderr,"Silent sound update costs %u clocks (budget 12)\n",silent_clocks);return 1;}
    if(actual.size()!=silent.size())return 1;
    for(size_t n=0;n<actual.size();n++)if(actual[n]!=silent[n])return 1;
    std::printf("Silent sound update: %u clocks (budget 12)\n",silent_clocks);
    // A dense sustained chord exercises mixing without ROM-fetch latency.
    reference.Reset();dut.reset=1;tick();dut.reset=0;tick();actual.clear();
    for (unsigned voice=0;voice<16;voice++) {
        write(0x3003+voice*16,0x407f);write(0x3005+voice*16,127);
        write(0x3200+voice*16,0);write(0x3204+voice*16,0);
    }
    write(0x3415,0xffff);write(0x3400,0xffff);write(0x3401,127);
    for (unsigned voice=0;voice<16;voice++) {
        write(0x3009+voice*16,0x8800);write(0x300b+voice*16,0x8800);
    }
    reference.Chip().spu_.RunCycles(96);auto chord=reference.Chip().GetAudio();
    dut.advance=1;dut.cycles=96;tick();dut.advance=0;
    unsigned chord_clocks=0;while(dut.busy && chord_clocks<200){tick();chord_clocks++;}
    if(actual.size()!=chord.size())return 1;
    for(size_t n=0;n<actual.size();n++)if(actual[n]!=chord[n])return 1;
    if(dut.busy || chord_clocks>125){std::fprintf(stderr,"Dense sound update costs %u clocks (budget 125)\n",chord_clocks);return 1;}
    std::printf("Dense sound update: %u clocks (budget 125)\n",chord_clocks);
    unsigned compared=0;
    for (unsigned fixture=0;fixture<72;fixture++) {
        reference.Reset();pending=false;dut.reset=1;tick();dut.reset=0;
        for (int n=0;n<16;n++) {
            unsigned base=0x3000+n*16;
            write(base,0x8000+random()%0x4000);write(base+2,0x9000+random()%0x4000);
            write(base+1,uint16_t(((fixture%3)+1)<<12 | (fixture&1 ? 0x8000 : 0) | (fixture&2 ? 0x4000 : 0)));
            write(base+3,uint16_t(random()));
            write(base+4,uint16_t(random()));write(base+5,uint16_t(random()));
            write(base+6,uint16_t(random()));write(base+7,uint16_t(random()&0xffc0));write(base+8,0xa000+random()%0x4000);
            write(base+9,uint16_t(random()));write(base+10,uint16_t(random()));write(base+11,uint16_t(random()));
            base=0x3200+n*16;
            write(base,random()%8);write(base+4,uint16_t(random()));
            write(base+1,random()%8);write(base+5,uint16_t(random()));
            write(base+2,random()%8);write(base+6,uint16_t(random()));
            write(base+3,fixture%4);write(base+7,uint16_t(random()));
        }
        if (fixture>=64) {
            // Envelope equality, overshoot, shutdown and bounds with sparse voices.
            constexpr std::array<uint8_t,8> source={8,8,8,8,8,127,0,9};
            constexpr std::array<uint8_t,8> target={16,16,0,0,4,127,127,9};
            constexpr std::array<uint8_t,8> step={2,8,2,16,8,127,127,0};
            unsigned envelope=fixture-64;
            for (unsigned voice=0;voice<16;voice++) {
                unsigned base=0x3000+voice*16;
                write(base+4,uint16_t(target[envelope]<<8 | (envelope>=2 && envelope<=4 ? 0x80 : 0) | step[envelope]));
                write(base+5,source[envelope]);write(base+6,0xff01);
                write(0x3200+voice*16,0);write(0x3204+voice*16,0);
            }
        }
        write(0x3415,fixture&4 ? 0xffff : 0);write(0x3418,fixture&8 ? 0xffff : 0);
        if (fixture>=64) {write(0x3415,0);write(0x3418,0);}
        write(0x3400,fixture>=64 ? 0x8001 : fixture<48 ? 0xffff : std::array<uint16_t,4>{0,0x8001,0x5555,0x0240}[fixture%4]);write(0x3401,127);write(0x3402,uint16_t(random()));
        write(0x340d,uint16_t(random()));write(0x3404,2);write(0x3405,0x8004);
        for (unsigned addr=0x3406;addr<=0x3409;addr++) write(addr,0x0123);
        if (fixture<64 && fixture&16) write(0x340a,0xffff);
        for (unsigned iteration=0;iteration<4000;iteration++) {
            unsigned elapsed=2+random()%165;
            actual.clear();reference.Chip().spu_.RunCycles(elapsed);
            auto expected=reference.Chip().GetAudio();
            dut.advance=1;dut.cycles=elapsed;tick();dut.advance=0;
            unsigned clocks=0;while (dut.busy && clocks++<10000) tick();
            if (dut.busy || actual.size()!=expected.size()) {std::fprintf(stderr,"SPU timing fixture %u step %u %zu/%zu\n",fixture,iteration,actual.size(),expected.size());return 1;}
            for (size_t n=0;n<actual.size();n++) if (actual[n]!=expected[n]) {
                std::fprintf(stderr,"SPU fixture %u step %u sample %zu expected %04x actual %04x\n",fixture,iteration,n,expected[n],actual[n]);return 1;
            }
            for (unsigned addr=0x3000;addr<=0x3418;addr++) {
                if (addr>=0x3100 && addr<0x3200 || addr>=0x3300 && addr<0x3400) continue;
                dut.register_address=addr;tick();uint16_t value=reference.Chip().ReadWord(addr);
                if (value!=dut.register_read_data) {
                    std::fprintf(stderr,"SPU fixture %u step %u register %04x expected %04x actual %04x\n",fixture,iteration,addr,value,dut.register_read_data);return 1;
                }
            }
            bool beat=reference.Chip().cpu_.irq_signal_[4];
            bool channel=reference.Chip().cpu_.irq_signal_[1];
            if (bool(dut.beat_irq)!=beat || bool(dut.channel_irq)!=channel) {std::fprintf(stderr,"SPU IRQ fixture %u step %u\n",fixture,iteration);return 1;}
            compared+=actual.size()/2;
        }
    }
    std::printf("SPU differential: %u stereo samples and 288000 register/IRQ snapshots matched\n",compared);
}
