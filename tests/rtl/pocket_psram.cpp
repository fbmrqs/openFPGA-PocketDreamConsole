#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <unordered_map>
#include "Vpocket_psram_tb.h"
int main() {
    Vpocket_psram_tb dut;
    std::unordered_map<uint32_t,uint16_t> memory;
    uint64_t time=0,phase=0,selected_at=0,data_at=0,adv_at=0,write_at=0,adv_end_at=0,write_end_at=0;
    uint32_t latched_address=0;
    uint16_t last_data=0;
    bool armed=false;
    unsigned maximum_read=0,maximum_write=0;
    auto fail=[&](const char* reason) {std::fprintf(stderr,"Pocket PSRAM: %s at %.2f ns\n",reason,time/4.0);std::exit(1);};
    auto tick=[&] {
        ++time;
        phase+=266481580;
        bool clock=dut.clk;
        if (phase>=4000000000ull) {phase-=4000000000ull;clock=!clock;}
        bool old_adv=dut.adv_n,old_we=dut.we_n;
        bool selected=!dut.ce0_n || !dut.ce1_n;
        // Delay the device's 70 ns access by the full 6 ns budget in each
        // direction. Until then return poison instead of early valid data.
        dut.chip_data=time>=adv_at+328 ? memory[latched_address] : 0xbad;
        bool old_drive=dut.controller_drive;
        dut.clk=clock;dut.eval();
        bool now_selected=!dut.ce0_n || !dut.ce1_n;
        if (!armed) return;
        if (now_selected && !selected) selected_at=time;
        if (!dut.adv_n && old_adv) adv_at=time;
        if (!dut.we_n && old_we) write_at=time;
        if (dut.adv_n && !old_adv) {
            if (!dut.controller_drive || time-selected_at<60 || time-adv_at<44) fail("address latch or CE/ADV interval with 6 ns pin skew");
            adv_end_at=time;
            latched_address=(uint32_t(!dut.ce1_n)<<22)|(uint32_t(dut.physical_address)<<16)|dut.bus_data;
        }
        if (!dut.controller_drive && old_drive && !dut.we_n && time-adv_end_at<32)
            fail("address hold interval with 6 ns pin skew");
        if (!dut.controller_drive && old_drive && dut.we_n && write_end_at && time-write_end_at<32)
            fail("write data hold interval with 6 ns pin skew");
        if (dut.controller_drive && dut.bus_data!=last_data) {last_data=dut.bus_data;data_at=time;}
        if (dut.we_n && !old_we) {
            if (!dut.controller_drive || time-write_at<204 || time-data_at<104 || time-adv_at<304) fail("write pulse or data setup with 6 ns pin skew");
            write_end_at=time;
            memory[latched_address]=dut.bus_data;
        }
        if (dut.read_avail && time-adv_at<328) fail("read access interval too short");
    };
    auto cycle=[&] {do {tick();} while (!dut.clk);do {tick();} while (dut.clk);};
    for (unsigned n=0;n<10;n++) cycle();
    armed=true;
    for (unsigned n=0;n<512;n++) {
        dut.bank=n&1;dut.address=(n*73117u)^0x2a731fu;dut.address&=0x3fffff;
        dut.write_data=uint16_t(n*17477u^0xb973u);dut.write_en=1;cycle();dut.write_en=0;
        unsigned cycles=1;while (dut.busy && ++cycles<100) cycle();
        if (dut.busy) fail("write timeout");
        if (cycles>maximum_write) maximum_write=cycles;
        cycle();dut.read_en=1;cycle();dut.read_en=0;
        cycles=1;while (!dut.read_avail && ++cycles<100) cycle();
        if (!dut.read_avail || dut.read_data!=dut.write_data) fail("read value or completion");
        if (cycles>maximum_read) maximum_read=cycles;
        cycle();
    }
    std::printf("Pocket PSRAM: 512 pin-level reads/writes, both dies and latch/setup/pulse timing passed; read %u clocks, write %u clocks\n",maximum_read,maximum_write);
}
