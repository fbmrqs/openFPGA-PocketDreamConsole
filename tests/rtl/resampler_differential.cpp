#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <deque>
#include <array>
#include "audio.h"
#include "Vpdc_resampler.h"

int main() {
    Vpdc_resampler dut;
    AudioResampler reference;
    uint32_t random = 0x61fcaa19;
    unsigned outputs = 0;
    std::deque<std::array<int16_t,2>> pending;
    auto tick = [&] {
        dut.clk=0; dut.eval(); dut.clk=1; dut.eval();
        if (dut.output_valid) {
            if (pending.empty() || int16_t(dut.output_left)!=pending.front()[0] || int16_t(dut.output_right)!=pending.front()[1]) {
                std::fprintf(stderr,"Pipelined resampler output mismatch at output %u\n",outputs);std::exit(1);
            }
            pending.pop_front();outputs++;
        }
    };
    dut.reset=1; dut.sample_valid=0; tick(); dut.reset=0;
    for (unsigned n=0;n<1000000;n++) {
        uint16_t samples[2];
        for (auto& s:samples) {random^=random<<13;random^=random>>17;random^=random<<5;s=uint16_t(random);}
        if (n<400) samples[0]=samples[1]=n<200 ? 0 : 65535;
        if (n%100003==0) {dut.reset=1;pending.clear();tick();dut.reset=0;reference.Reset();}
        auto expected=reference.Convert({samples,2});
        if (expected.size()!=0) pending.push_back({expected[0],expected[1]});
        dut.sample_valid=1;dut.sample_left=int16_t(samples[0]-32768);dut.sample_right=int16_t(samples[1]-32768);tick();
        if (n%3!=0) {dut.sample_valid=0;tick();}
    }
    dut.sample_valid=0;for (unsigned n=0;n<32;n++) tick();
    if (!pending.empty()) {std::fprintf(stderr,"Resampler output exceeded 32-clock drain budget\n");return 1;}
    std::printf("Resampler: 1000000 inputs and %u stereo outputs matched\n",outputs);
}
