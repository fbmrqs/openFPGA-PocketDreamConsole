#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <unordered_map>
#include "Vpocket_sdram_tb.h"

int main(int argc,char** argv) {
    unsigned period=argc>2 ? unsigned(std::strtoul(argv[2],nullptr,10)) : 40;
    unsigned advance=period*13/40;
    unsigned access_ticks=argc>=2 ? unsigned(std::strtoul(argv[1],nullptr,10)) : 22;
    Vpocket_sdram_tb dut;
    uint64_t time=0,burst_started=0,maximum_burst=0,maximum_write=0;
    std::array<unsigned,4> row{};
    std::unordered_map<unsigned,uint16_t> memory;
    std::map<uint64_t,uint16_t> read_events;
    unsigned remaining_write=0,write_beat=0,read_commands=0,read_beats=0;
    unsigned expected_address=0,expected_data=0;
    bool writing=false,reading=false,check_refresh=false;
    uint64_t first_refresh=0,last_refresh=0;unsigned refreshes=0;
    auto fail=[&](const char* reason) {std::fprintf(stderr,"Pocket SDRAM: %s at 0.25ns tick %llu\n",reason,time);std::exit(1);};
    auto tick=[&] {
        ++time;
        auto arrived=read_events.find(time);
        if (arrived!=read_events.end()) {dut.chip_data=arrived->second;read_events.erase(arrived);}
        bool controller=(time%period)<period/2,chip=((time+advance)%period)<period/2;
        bool chip_rise=chip && !dut.chip_clk, controller_rise=controller && !dut.controller_clk;
        dut.controller_clk=controller;dut.chip_clk=chip;dut.eval();
        if (!dut.reset_n) return;
        if (controller_rise && dut.burst_valid) {
            if (!reading || dut.burst_data!=memory[expected_address+read_beats]) {std::fprintf(stderr,"beat %u address %x expected %04x actual %04x chip %04x\n",read_beats,expected_address+read_beats,memory[expected_address+read_beats],dut.burst_data,dut.chip_data);fail("invalid burst response");}
            read_beats++;
        }
        if (chip_rise && dut.phy_cke) {
            unsigned command=(dut.phy_ras<<2)|(dut.phy_cas<<1)|dut.phy_we;
            if (command==1 && check_refresh) {
                if(!refreshes)first_refresh=time;
                last_refresh=time;refreshes++;
            }
            if (command==3) row[dut.phy_ba]=dut.phy_a;
            if (command==5) {
                unsigned address=(dut.phy_ba<<23)|(row[dut.phy_ba]<<10)|(dut.phy_a&1023);
                if (!reading || address!=expected_address+read_commands*2) fail("incorrect burst geometry or ordering");
                read_events.emplace(time+3*period+access_ticks,memory[address]);
                read_events.emplace(time+4*period+access_ticks,memory[address+1]);
                read_commands++;
            }
            if (command==4) {
                unsigned address=(dut.phy_ba<<23)|(row[dut.phy_ba]<<10)|(dut.phy_a&1023);
                if (!writing || address!=expected_address*2 || remaining_write) fail("incorrect write address or overlapping write");
                remaining_write=2;write_beat=0;
            }
            if (remaining_write) {
                if (!dut.controller_drive || dut.phy_dqm!=0 || dut.bus_data!=uint16_t(expected_data>>(write_beat*16)))
                    fail("32-bit write beat order, mask or data mismatch");
                memory[expected_address*2+write_beat]=dut.bus_data;
                remaining_write--;write_beat++;
            }
        }
    };
    auto cycle=[&] {do {tick();} while (time%period!=period/2);};
    dut.reset_n=0;for (unsigned n=0;n<10;n++) cycle();dut.reset_n=1;
    for (unsigned n=0;n<33000;n++) cycle();
    check_refresh=true;
    for (unsigned n=0;n<512;n++) {
        expected_address=((n*49157u)^(n<<17))&0xffffffu;
        if (n<4) expected_address=n*0x400000u+0x3fffffu;
        unsigned line_address=expected_address&~7u;
        for(unsigned fill=0;fill<8;fill++) {
        expected_address=line_address+fill;
        expected_data=(n*8+fill)*0x178a392du^0x96ac1234u;
        uint64_t write_started=time;
        writing=true;dut.word_address=expected_address;dut.word_data=expected_data;dut.word_write=1;cycle();dut.word_write=0;
        unsigned timeout=0;while (!dut.word_done && ++timeout<500) cycle();
        if (!dut.word_done || remaining_write || write_beat!=2) fail("write completion failed");
        if (time-write_started>maximum_write) maximum_write=time-write_started;
        writing=false;cycle();
        }
        expected_address=(expected_address*2)&~15u;read_commands=0;read_beats=0;reading=true;
        dut.burst_address=expected_address;dut.burst_read=1;burst_started=time;cycle();dut.burst_read=0;
        unsigned timeout=0;while (!dut.burst_done && ++timeout<500) cycle();
        if (!dut.burst_done || read_commands!=8 || read_beats!=16) fail("cache line did not return exactly sixteen halfwords");
        uint64_t latency=time-burst_started;
        if (latency>maximum_burst) maximum_burst=latency;
        reading=false;cycle();
    }
    if(refreshes<3)fail("refresh activity was not exercised");
    double refresh_ns=double(last_refresh-first_refresh)/4/(refreshes-1);
    if(refresh_ns>7500)fail("refresh interval exceeds conservative 7.5 us bound");
    std::printf("SDRAM refresh average %.2f ns across %u refreshes\n",refresh_ns,refreshes);
    std::printf("Pocket SDRAM: 4096 writes/512 fully populated bursts with delayed CL3 responses, all banks, final addresses, little-endian beats and sixteen-halfword lines passed; worst burst %.2f ns, write %.2f ns\n",double(maximum_burst)/4,double(maximum_write)/4);
}
