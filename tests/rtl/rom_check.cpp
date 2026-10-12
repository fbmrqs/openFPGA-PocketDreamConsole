#include <cstdint>
#include <initializer_list>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include "Vpdc_rom_check.h"
static uint16_t word(uint32_t address) { return uint16_t(address*31337u ^ (address>>16) ^ 0x1234u); }
int main(int argc,char** argv) {
    Vpdc_rom_check dut;
    auto tick=[&] {dut.clk=0;dut.eval();dut.clk=1;dut.eval();};
    auto fail=[](const char* message) {std::fprintf(stderr,"ROM check: %s\n",message);std::exit(1);};
    if(argc==2) {
        FILE* file=std::fopen(argv[1],"rb");if(!file)return 2;
        std::fseek(file,0,SEEK_END);long size=std::ftell(file);
        unsigned bank=size==0x1000000?1:7;
        std::fseek(file,long(bank)*0x800000,SEEK_SET);
        std::vector<uint16_t> words(0x400000);
        if(std::fread(words.data(),2,words.size(),file)!=words.size())return 2;
        std::fclose(file);
        dut.reset=1;dut.rom_ready=0;dut.rom_ack=0;tick();dut.reset=0;dut.rom_ready=1;dut.final_bank=bank;
        unsigned replies=0,delay=0;uint32_t held=0;bool pending=false;
        uint64_t clocks=0;
        while(!dut.done && clocks++<220000000) {
            dut.clk=0;dut.eval();dut.rom_ack=0;
            if(dut.rom_request) {
                if(!pending){pending=true;held=dut.rom_address;delay=128;}
                if(held!=dut.rom_address)fail("full-bank read address changed");
                if(delay--==0){
                    if(held!=((bank<<22)+16*(replies%0x40000)))fail("full-bank sweep order is wrong");
                    unsigned offset=held&0x3fffff;
                    for(unsigned n=0;n<8;n++)dut.rom_line_data[n]=uint32_t(words[offset+n*2])|(uint32_t(words[offset+n*2+1])<<16);
                    dut.rom_line_valid=1;dut.rom_ack=1;pending=false;replies++;
                }
            }
            dut.clk=1;dut.eval();
        }
        uint32_t expected=bank==1?0x0c1dc0f3:0xccd6c6d3;
        if(!dut.passed || replies!=0x80000 || dut.first_crc!=expected || dut.second_crc!=expected || dut.reset_vector!=words[0xfff7])fail("real ROM bank checksum, vector or sweep length mismatch");
        std::printf("%s: two full 8 MiB sweeps, CRC=%08x, vector=%04x, %llu clocks (%.3f seconds at 98.304 MHz) passed\n",argv[1],expected,dut.reset_vector,(unsigned long long)clocks,double(clocks)/98304000.0);
        return 0;
    }
    for(unsigned bank:{1u,7u}) for(unsigned corruption=0;corruption<4;corruption++) {
        dut.rom_ready=0;dut.reset=1;dut.rom_ack=0;tick();dut.reset=0;tick();
        dut.final_bank=bank;dut.rom_ready=1;
        unsigned replies=0,delay=0;uint32_t held=0;bool pending=false;
        for(unsigned clocks=0;!dut.done && clocks<12000;clocks++) {
            dut.clk=0;dut.eval();dut.rom_ack=0;
            if(dut.rom_request) {
                if(!pending) {pending=true;held=dut.rom_address;delay=(replies%13)+1;}
                if(held!=dut.rom_address)fail("request address changed before acknowledgment");
                if(delay--==0) {
                    if(held!=((bank<<22)+16*(replies%16)))fail("bank scan order is wrong");
                    for(unsigned n=0;n<8;n++)dut.rom_line_data[n]=uint32_t(word(held+n*2))|(uint32_t(word(held+n*2+1))<<16);
                    if(replies==2 && corruption==1 || replies==18 && corruption==2) dut.rom_line_data[0]^=0x20;
                    dut.rom_line_valid=!(replies==2 && corruption==3);
                    dut.rom_ack=1;pending=false;replies++;
                }
            }
            dut.clk=1;dut.eval();
            if(!dut.done && dut.passed)fail("machine released before both checks completed");
        }
        unsigned expected=corruption==0?7:corruption==1?5:corruption==2?3:9;
        if(!dut.done || dut.status!=expected || dut.passed!=(corruption==0))fail("incorrect pass/failure status");
        if(corruption!=3) {
            uint32_t crc=bank==1?0x351d11ad:0x9b5396bc;
            if(replies!=32 || (corruption!=1 && dut.first_crc!=crc) || (corruption!=2 && dut.second_crc!=crc))fail("CRC or sweep length differs from zlib reference");
            if(dut.reset_vector!=word((bank<<22)+0x37))fail("reset-vector sample is wrong");
        }
        for(unsigned n=0;n<20;n++){tick();if(dut.rom_request)fail("extra read after completion");}
        dut.rom_ready=0;tick();if(dut.done || dut.passed || dut.status)fail("reload did not clear verification");
    }
    // Interrupted sweeps must restart rather than reuse partial evidence.
    dut.rom_ready=1;tick();dut.reset=1;tick();
    if(dut.done || dut.passed || dut.rom_request || dut.status)fail("reset did not clear the in-progress check");
    std::puts("ROM check: both banks, two independent sweeps, zlib CRCs, vector capture, first/second-pass corruption, incomplete lines and reset/reload passed");
}
