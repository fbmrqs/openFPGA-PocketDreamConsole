#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "Vpdc_audio.h"

int main() {
    Vpdc_audio dut;
    uint64_t time=0;
    unsigned audio_phase=0, sample_phase=0, sent=0, received=0, edges=0, bit=0;
    uint16_t left=0,right=0;
    unsigned held=0, rate=48000;
    bool last_mclk=false,last_lr=false, synchronized=false, collecting=false, started=false;
    auto fail=[&](const char* reason) {std::fprintf(stderr,"Pocket audio: %s at pair %u time %llu\n",reason,received,time);std::exit(1);};
    auto tick=[&](bool feed) {
        ++time;
        bool system=(time&1)==0;
        if (system && !dut.system_clk) {
            dut.sample_valid=0;
            if (!dut.reset && feed) {
                sample_phase+=rate;
                if (sample_phase>=200000000) {
                    sample_phase-=200000000;dut.sample_valid=1;
                    dut.sample_left=uint16_t(0x1234+sent*73);dut.sample_right=uint16_t(~dut.sample_left);sent++;
                }
            }
        }
        audio_phase+=24576000;
        if (audio_phase>=400000000) {audio_phase-=400000000;dut.audio_clk=!dut.audio_clk;}
        dut.system_clk=system;dut.eval();
        if (dut.reset) return;
        if (!last_mclk && dut.audio_mclk && ++edges%4==2) {
            if (last_lr!=bool(dut.audio_lrck)) {
                if (!dut.audio_lrck) {
                    if (collecting) {
                        if (!started && left==0x1234 && right==uint16_t(~left)) started=true;
                        if (started) {
                            uint16_t expected=uint16_t(0x1234+received*73);
                            if (right!=uint16_t(~left)) fail("stereo pair corrupted or silence inserted");
                            if (left==expected) received++;
                            else if (dut.underflow && received && left==uint16_t(0x1234+(received-1)*73)) held++;
                            else fail("I2S bit order, channel order or sample sequence mismatch");
                        }
                    }
                    left=right=0;collecting=synchronized;synchronized=true;
                }
                bit=0;last_lr=dut.audio_lrck;
            } else if (bit++<16) {
                auto& channel=dut.audio_lrck ? right : left;
                channel=uint16_t(channel<<1 | dut.audio_dac);
            }
        }
        last_mclk=dut.audio_mclk;
        if (dut.overflow) fail("sample FIFO overflow");
    };
    dut.reset=1;for (unsigned n=0;n<100;n++) tick(false);dut.reset=0;
    while (received<512 && time<20000000) tick(true);
    if (received!=512 || dut.underflow) fail("stream failed to start without underrun");
    // Once the producer stops, the serializer must report that its queue drained.
    while (!dut.underflow && time<40000000) tick(false);
    if (!dut.underflow) fail("missing underrun diagnostic");
    const uint64_t drain_end=time+400000;
    while(time<drain_end)tick(false);
    if(received!=sent || held<32)fail("drained stream did not hold its final sample");
    const unsigned resume_target=received+128, held_before=held;
    rate=32000;
    while(received<resume_target && time<50000000)tick(true);
    if(received!=resume_target || held-held_before<32)fail("slow producer did not recover with repeated samples");
    std::printf("Pocket audio: ordered stereo, prefill, starvation sample hold and 32 kHz producer recovery passed\n");
}
