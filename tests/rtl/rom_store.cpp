#include <cstdint>
#include <initializer_list>
#include <cstdio>
#include <cstdlib>
#include "Vrom_path_tb.h"

static uint32_t word(uint32_t address) {return address*0x75b9u ^ 0xa52cf10du;}
static uint16_t halfword(uint32_t address) {return uint16_t(word(address/2)>>(16*(address&1)));}
static uint32_t crc_word(uint32_t crc,uint32_t data) {
    for(unsigned n=0;n<32;n++) {crc=(crc>>1)^((crc^data)&1 ? 0xedb88320u : 0);data>>=1;}
    return crc;
}
int main() {
    Vrom_path_tb dut;
    uint64_t time=0;
    unsigned write_delay=0, burst_count=0, committed=0, burst_delay=0;
    uint64_t maximum_read_clocks=0;
    uint32_t burst_address=0;
    bool burst_active=false, corrupt_read=false;
    auto fail=[&](const char* reason) {std::fprintf(stderr,"ROM store: %s at time %llu\n",reason,time);std::exit(1);};
    auto tick=[&] {
        ++time;
        bool bridge=(time%6)<3, memory=(time%4)<2, system=(time%2)==0;
        bool memory_rise=memory && !dut.memory_clk;
        if (memory_rise) {
            dut.word_done=0;dut.burst_valid=0;dut.burst_done=0;
            if (write_delay && --write_delay==0) {dut.word_done=1;committed++;}
            if (dut.word_write) {
                if (write_delay || dut.word_address!=committed || dut.word_data!=word(committed)) fail("incorrect or overlapping SDRAM write");
                // The pin-level controller fixture measures twenty clocks.
                // Exercise fifty percent extra latency throughout a full load.
                write_delay=30;
            }
            if (dut.burst_read) {
                if (burst_active) fail("overlapping SDRAM burst");
                burst_active=true;burst_address=dut.burst_address;burst_count=0;burst_delay=25;
            } else if (burst_active && burst_delay) {--burst_delay;
            } else if (burst_active) {
                dut.burst_valid=1;dut.burst_data=halfword(burst_address+burst_count++)^(corrupt_read ? 1 : 0);
                if (burst_count==16) {dut.burst_done=1;burst_active=false;}
            }
        }
        dut.bridge_clk=bridge;dut.memory_clk=memory;dut.system_clk=system;dut.eval();
    };
    auto bridge_tick=[&] {do {tick();} while (!(time%6==3));};
    auto settle=[&](unsigned cycles) {while (cycles--) tick();};
    dut.check_enable=0;dut.reset=1;settle(30);dut.reset=0;settle(30);
    for (unsigned size : {0x800000u,0x1000000u,0x4000000u}) {
    committed=0;dut.slot_complete=0;
    dut.slot_id=1;dut.slot_size=size;dut.slot_write=1;bridge_tick();bridge_tick();dut.slot_write=0;
    settle(60);
    const unsigned count=size/4;
    uint32_t expected_crc=0xffffffff;
    for (unsigned n=0;n<count;n++) {
        if(n>=count-0x200000)expected_crc=crc_word(expected_crc,word(n));
        dut.bridge_address=0x10000000+n*4;dut.bridge_data=word(n);dut.bridge_write=1;
        bridge_tick();dut.bridge_write=0;
        // About 9 MB/s: above the documented few MB/s APF throughput.
        for (unsigned k=0;k<27;k++) bridge_tick();
        if (dut.rom_ready || dut.load_fault) fail("ROM started before complete load, or legal load failed");
    }
    dut.slot_complete=1;bridge_tick();dut.slot_complete=0;
    unsigned timeout=0;while (!dut.rom_ready && timeout++<10000) tick();
    if (!dut.rom_ready || dut.final_bank!=(size==0x800000 ? 0 : size==0x1000000 ? 1 : 7) || committed!=count) fail("complete ROM did not start with its final bank");
    if(~expected_crc!=(size==0x800000 ? 0x8940c2c6u : size==0x1000000 ? 0x319a7c17u : 0x546062feu))fail("software CRC disagrees with independent zlib fixture");
    if(dut.load_crc!=~expected_crc || dut.write_crc!=~expected_crc)fail("startup-bank loading CRC mismatch");
    std::printf("%u MiB loading taps: L=%08x W=%08x passed\n",size>>20,dut.load_crc,dut.write_crc);
    for (unsigned n=0;n<512;n++) {
        dut.rom_address=(n==0 ? size/2-1 : n*7919u)&(size/2-1);dut.rom_request=1;
        uint64_t read_started=time;
        timeout=0;while (!dut.rom_ack && timeout++<10000) tick();
        if (!dut.rom_ack || dut.rom_data!=halfword(dut.rom_address)) fail("ROM read or byte order mismatch");
        uint64_t read_clocks=(time-read_started+1)/2;
        if (read_clocks>maximum_read_clocks) maximum_read_clocks=read_clocks;
        dut.rom_request=0;settle(12);
    }
    for(unsigned bad=0;bad<2;bad++) {
        corrupt_read=bad;dut.check_enable=1;
        unsigned timeout=0;while(!dut.check_done && timeout++<100000)tick();
        if(!dut.check_done || dut.check_status!=(bad ? 1 : 7))fail("integrated readback verdict is wrong");
        uint32_t golden=size==0x800000 ? 0xcf964c64u : size==0x1000000 ? 0x95c56ca2u : 0xeb971541u;
        if(!bad && (dut.first_crc!=golden || dut.second_crc!=golden))fail("integrated CRC differs from zlib fixture");
        std::printf("ROM path: %u MiB bank, injected corruption %u, M=%u A=%08x B=%08x passed\n",size>>20,bad,dut.check_status,dut.first_crc,dut.second_crc);
        dut.check_enable=0;settle(100);
    }
    corrupt_read=false;
    }
    dut.slot_size=0x1000000;dut.slot_write=1;bridge_tick();bridge_tick();dut.slot_write=0;settle(60);
    dut.slot_complete=1;bridge_tick();dut.slot_complete=0;settle(60);
    if (dut.rom_ready || !dut.load_fault) fail("incomplete ROM length was accepted");
    dut.slot_size=0x1234;dut.slot_write=1;bridge_tick();bridge_tick();dut.slot_write=0;settle(60);
    if (dut.rom_ready || !dut.load_fault || dut.slot_ok) fail("invalid ROM length was accepted");
    std::printf("ROM adapter worst miss: %llu system clocks with a 42-memory-clock SDRAM response\n",maximum_read_clocks);
    std::printf("ROM store: complete 8/16/64 MiB loads, 1536 delayed burst reads, byte order, bank reset, reload and invalid/incomplete lengths passed\n");
}
