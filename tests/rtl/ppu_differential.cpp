#include <array>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <unordered_map>
#include "core/portable.h"
#include "core/common.h"
#define private public
#include "core/spg200/ppu.h"
#undef private
#include "core/spg200/cpu.h"
#include "core/spg200/irq.h"
#include "core/spg200/bus_interface.h"
#include "Vpdc_ppu.h"
struct Memory : BusInterface {
    std::unordered_map<uint32_t,uint16_t> words;
    bool zero_default=false;
    Word ReadWord(Addr addr) override {
        addr &= 0x3fffff;
        auto it=words.find(addr);
        return it==words.end() ? (zero_default ? 0 : uint16_t((addr*17389)^(addr>>2))) : it->second;
    }
    void WriteWord(Addr addr,Word word) override {words[addr&0x3fffff]=word;}
};
int main() {
  for(bool use_rom_lines : {false,true}) {
    Vpdc_ppu dut;dut.pixel_ready=1;Memory memory;Cpu cpu(memory);Irq irq(cpu);Ppu reference(VideoTiming::NTSC,memory,irq);
    std::mt19937 random{0x505055};
    bool pending=false;uint32_t address=0;int delay=0;
    unsigned fixture=0, count=0;std::array<uint16_t,320> result{};
    auto tick=[&] {
        dut.clk=0;dut.eval();dut.memory_ack=0;dut.memory_line_valid=0;
        if (dut.memory_request) {
            if (!pending) {pending=true;address=dut.memory_address;delay=random()%4;}
            if (address!=dut.memory_address) std::abort();
            if (delay--==0) {dut.memory_ack=1;dut.memory_data=memory.ReadWord(address);pending=false;
                if(address>=0x4000 && use_rom_lines){
                    dut.memory_line_valid=1;
                    for(unsigned n=0;n<8;n++)dut.memory_line_data[n]=uint32_t(memory.ReadWord((address&~15u)+n*2))|uint32_t(memory.ReadWord((address&~15u)+n*2+1))<<16;
                }}
        } else if (pending) std::abort();
        dut.clk=1;dut.eval();
        if (dut.pixel_valid) {
            if (dut.pixel_x!=count || count>=320) std::abort();
            result[count++]=dut.pixel_data;
        }
    };
    auto write=[&](unsigned addr,uint16_t value) {
        dut.register_write=1;dut.register_address=addr;dut.register_data=value;tick();dut.register_write=0;
        if (addr>=0x2810 && addr<=0x281b) {
            int bg=(addr-0x2810)/6;
            switch ((addr-0x2810)%6) {
                case 0:reference.SetBgXScroll(bg,value);break;
                case 1:reference.SetBgYScroll(bg,value);break;
                case 2:reference.SetBgAttribute(bg,value);break;
                case 3:reference.SetBgControl(bg,value);break;
                case 4:reference.SetBgTileMapPtr(bg,value);break;
                case 5:reference.SetBgAttributeMapPtr(bg,value);break;
            }
        } else if (addr==0x281c) reference.SetVerticalCompressAmount(value);
        else if (addr==0x281d) reference.SetVerticalCompressOffset(value);
        else if (addr==0x2820 || addr==0x2821) reference.SetBgSegmentPtr(addr-0x2820,value);
        else if (addr==0x2822) reference.SetSpriteSegmentPtr(value);
        else if (addr==0x282a) reference.SetBlendLevel(value);
        else if (addr==0x2842) reference.SetSpriteControl(value);
        else if (addr>=0x2900 && addr<0x2a00) reference.SetLineScroll(addr&255,value);
        else if (addr>=0x2b00 && addr<0x2c00) reference.SetPaletteColor(addr&255,value);
        else if (addr>=0x2c00 && addr<0x3000) reference.WriteSpriteMemory(addr&1023,value);
    };
    for (fixture=0;fixture<96;fixture++) {
        reference.Reset();cpu.Reset();irq.Reset();dut.reset=1;pending=false;count=0;tick();dut.reset=0;
        for (int n=0;n<1100 && !dut.ready;n++) tick();
        if (!dut.ready) std::abort();
        memory.words.clear();
        for (int n=0;n<256;n++) {write(0x2b00+n,uint16_t(random()));write(0x2900+n,uint16_t(random()));}
        write(0x281c,fixture%3==0 ? 16 : fixture%3==1 ? 32 : 64);
        write(0x281d,fixture%2 ? 0x1ff0 : 0x10);write(0x282a,fixture&3);write(0x2842,1);write(0x2822,0x600);
        for (int bg=0;bg<2;bg++) {
            unsigned base=0x2810+bg*6;
            write(base,fixture%4==0 ? 511 : uint16_t(random()));write(base+1,uint16_t(random()));
            write(base+2,uint16_t((fixture&3)|((fixture%4)<<4)|(((fixture/4)%4)<<6)|((fixture%16)<<8)|((fixture%4)<<12)|((fixture%4)<<2)));
            uint16_t control=8 | (fixture&1 ? 2 : 0) | (fixture&4 ? 0x10 : 0) | (fixture&8 ? 0x100 : 0) | (fixture&16 ? 0x40 : 0);
            if (fixture>=64) control|=1|(fixture&1 ? 0x80 : 0);
            write(base+3,control);write(base+4,0x2000+bg*0x300);write(base+5,0x1800+bg*0x200);write(0x2820+bg,0x400+bg*0x100);
        }
        for (int sprite=0;sprite<256;sprite++) {
            unsigned base=0x2c00+sprite*4;
            write(base,1+random()%32);write(base+1,uint16_t(int(random()%480)-240));write(base+2,uint16_t(int(random()%300)-150));
            write(base+3,uint16_t(random()));
        }
        for (unsigned y:{0u,1u,63u,127u,239u}) {
            count=0;reference.DrawLine(y);dut.line=y;dut.start_line=1;tick();dut.start_line=0;
            unsigned clocks=0;
            while (!dut.line_done && clocks++<1000000) tick();
            if (!dut.line_done || count!=320) {std::fprintf(stderr,"PPU timeout fixture %u y %u count %u\n",fixture,y,count);return 1;}
            for (unsigned x=0;x<320;x++) if (result[x]!=reference.framebuffer_[y][x].raw) {
                std::fprintf(stderr,"PPU fixture %u pixel (%u,%u) expected %04x actual %04x\n",fixture,x,y,reference.framebuffer_[y][x].raw,result[x]);return 1;
            }
        }
    }
    // Empty sprite passes must not cost eight full scans per visible line.
    reference.Reset();cpu.Reset();irq.Reset();dut.reset=1;pending=false;count=0;tick();dut.reset=0;
    while(!dut.ready)tick();memory.words.clear();write(0x2842,1);
    reference.DrawLine(100);dut.line=100;dut.start_line=1;tick();dut.start_line=0;
    unsigned empty_clocks=0;
    while(!dut.line_done && empty_clocks<4096){tick();empty_clocks++;}
    if(!dut.line_done || count!=320 || empty_clocks>700) {
        std::fprintf(stderr,"Empty sprite line costs %u clocks (budget 700)\n",empty_clocks);return 1;
    }
    for(unsigned x=0;x<320;x++)if(result[x]!=reference.framebuffer_[100][x].raw)return 1;
    std::printf("Empty sprite line: %u clocks (budget 700)\n",empty_clocks);
    // Exercise both ends of the sprite RAM and every layer/blend pass.
    unsigned boundary_lines=0,maximum_sparse_clocks=0;
    for(unsigned slot : {0u,1u,7u,8u,15u,16u,127u,128u,247u,248u,254u,255u})for(unsigned pass=0;pass<8;pass++) {
        reference.Reset();cpu.Reset();irq.Reset();dut.reset=1;pending=false;count=0;tick();dut.reset=0;
        while(!dut.ready)tick();memory.words.clear();memory.zero_default=true;
        for(unsigned n=0;n<256;n++)write(0x2b00+n,0x03e0);
        write(0x2842,1);write(0x2822,0x100);
        unsigned base=0x2c00+slot*4;
        write(base,1);write(base+1,0);write(base+2,0);
        write(base+3,uint16_t(((pass>>1)<<12)|((pass&1)<<14)));
        for(unsigned y : {128u,0u}) {
            count=0;reference.DrawLine(y);dut.line=y;dut.start_line=1;tick();dut.start_line=0;
            unsigned clocks=0;while(!dut.line_done && clocks++<4096)tick();
            if(!dut.line_done || count!=320)return 1;
            for(unsigned x=0;x<320;x++)if(result[x]!=reference.framebuffer_[y][x].raw) {
                std::fprintf(stderr,"Sprite boundary slot %u pass %u pixel (%u,%u) expected %04x actual %04x\n",slot,pass,x,y,reference.framebuffer_[y][x].raw,result[x]);return 1;
            }
            if(y==128 && clocks>maximum_sparse_clocks)maximum_sparse_clocks=clocks;
            if(y==128 && clocks>820) {
                std::fprintf(stderr,"Sparse sprite line costs %u clocks (budget 820), slot %u pass %u\n",clocks,slot,pass);return 1;
            }
            boundary_lines++;
        }
    }
    std::printf("Sparse sprite lines: maximum %u clocks (budget 820)\n",maximum_sparse_clocks);
    // A preceding sprite must not leave its palette active on the next one.
    reference.Reset();cpu.Reset();irq.Reset();dut.reset=1;pending=false;count=0;tick();dut.reset=0;
    while(!dut.ready)tick();memory.words.clear();memory.zero_default=true;
    write(0x2822,0x4000);write(0x2842,1);write(0x2b34,0x0401);
    for(const auto& entry : std::array<std::pair<unsigned,uint16_t>,8>{{
        {0x2c00,0x0fc9},{0x2c01,0x01aa},{0x2c02,0x0050},{0x2c03,0x14a2},
        {0x2c30,0x177f},{0x2c31,0x01a0},{0x2c32,0x0050},{0x2c33,0x1092}}}) write(entry.first,entry.second);
    memory.words[0x219f43]=0x4dbf;
    reference.DrawLine(32);dut.line=32;dut.start_line=1;tick();dut.start_line=0;
    while(!dut.line_done)tick();
    if(reference.framebuffer_[32][66].raw!=0x0401 || result[66]!=0x0401) {
        std::fprintf(stderr,"PPU overlap pixel (66,32) expected 0401 actual %04x\n",result[66]);return 1;
    }
    for(unsigned x=0;x<320;x++)if(result[x]!=reference.framebuffer_[32][x].raw) {
        std::fprintf(stderr,"PPU overlap pixel (%u,32) expected %04x actual %04x\n",x,reference.framebuffer_[32][x].raw,result[x]);return 1;
    }
    std::printf("PPU differential: %u scanlines / %u pixels matched\n",fixture*5+2+boundary_lines,(fixture*5+2+boundary_lines)*320);
}
}
