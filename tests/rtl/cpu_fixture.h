#pragma once
#include <array>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <tuple>
#include <vector>
#include <unordered_map>
#include "core/portable.h"
#include "core/common.h"
#define private public
#include "core/spg200/cpu.h"
#undef private
#include "core/spg200/bus_interface.h"
#include "Vunsp_cpu.h"
#include "Vunsp_cpu___024root.h"

using Access = std::tuple<bool,uint32_t,uint16_t>;
struct Memory : BusInterface {
    std::unordered_map<uint32_t,uint16_t> words;
    uint16_t ReadWord(Addr address) override {
        address &= 0x3fffff;
        auto p = words.find(address);
        return p == words.end() ? uint16_t((address * 31337) ^ (address >> 3)) : p->second;
    }
    void WriteWord(Addr address,Word value) override { words[address & 0x3fffff] = value; }
};
struct Recorder : Cpu::Trace {
    std::vector<Access> accesses;
    Cpu::State after{};
    int cycles=0;
    bool interrupt=false;
    void Begin(const Cpu::State&) override { accesses.clear(); }
    void Read(Addr address,Word value) override { accesses.emplace_back(false,address & 0x3fffff,value); }
    void Write(Addr address,Word value) override { accesses.emplace_back(true,address & 0x3fffff,value); }
    void End(const Cpu::State& state,int elapsed,bool entry) override {after=state;cycles=elapsed;interrupt=entry;}
};
struct Rig {
    Vunsp_cpu dut;
    Memory memory;
    std::vector<Access> accesses;
    std::mt19937 random{0x504443};
    const std::vector<Access>* replay=nullptr;
    size_t cursor=0;
    bool pending=false;
    int delay=0;
    Access held;
    void tick() {
        dut.clk=0; dut.eval();
        dut.bus_ack=0;dut.ds_write=0;
        if (dut.bus_valid) {
            Access current{dut.bus_write,dut.bus_addr,dut.bus_wdata};
            if (!pending) {pending=true;held=current;delay=int(random()%8);}
            if (current!=held) {std::fprintf(stderr,"Bus request changed during wait\n");std::exit(1);}
            if (delay--==0) {
                auto [write,address,value]=held;
                if (replay) {
                    if (cursor >= replay->size()) {std::fprintf(stderr,"Extra bus access\n");std::exit(1);}
                    auto [expected_write,expected_address,expected_value]=(*replay)[cursor++];
                    if (write!=expected_write || address!=expected_address || write && value!=expected_value) {
                        std::fprintf(stderr,"Replay bus mismatch %c %06x %04x expected %c %06x %04x\n",write?'w':'r',address,value,expected_write?'w':'r',expected_address,expected_value);std::exit(1);
                    }
                    value=expected_value;
                    if (write && address==0x3d2f) {dut.ds_write=1;dut.ds_value=value&63;}
                } else if (write) memory.WriteWord(address,value);
                else value=memory.ReadWord(address);
                accesses.emplace_back(write,address,value);
                dut.bus_rdata=value;dut.bus_ack=1;pending=false;
            }
        } else if (pending) {std::fprintf(stderr,"Bus request withdrawn during wait\n");std::exit(1);}
        dut.clk=1; dut.eval();
    }
    void reset() {
        pending=false;dut.reset=1;dut.run=0;dut.irq=0;dut.fiq=0;dut.ds_write=0;
        tick();dut.reset=0;
        for (int n=0;n<100 && dut.rootp->unsp_cpu__DOT__state!=(uint64_t{1}<<2);n++) tick();
        if (dut.rootp->unsp_cpu__DOT__state!=(uint64_t{1}<<2)) std::abort();
        accesses.clear();
    }
    void step(bool prefetch=false) {
        accesses.clear(); cursor=0;
        dut.prefetch_enable=prefetch;dut.run=0;
        if (prefetch) {
            unsigned wait=0;
            while (!dut.rootp->unsp_cpu__DOT__prefetch_valid && ++wait<1000) tick();
            if (!dut.rootp->unsp_cpu__DOT__prefetch_valid) {
                std::fprintf(stderr,"Instruction prefetch timeout\n");std::exit(1);
            }
        }
        dut.prefetch_enable=0;dut.run=1;
        for (int n=0;n<4000;n++) {
            tick();
            if (dut.fault) {std::fprintf(stderr,"Unexpected fault pc=%06x opcode=%04x\n",dut.fault_pc,dut.fault_opcode);std::exit(1);}
            if (dut.retired) {dut.run=0;return;}
        }
        std::fprintf(stderr,"Retirement timeout\n");std::exit(1);
    }
    void compare(const Recorder& reference,unsigned case_id,uint16_t instruction) {
        auto* root=dut.rootp;
        for (int n=0;n<8;n++) if (root->unsp_cpu__DOT__r[n]!=reference.after.regs[n]) {
            std::fprintf(stderr,"Case %u opcode %04x register %d expected %04x actual %04x\n",case_id,instruction,n,reference.after.regs[n],root->unsp_cpu__DOT__r[n]);std::exit(1);
        }
        for (int n=0;n<3;n++) if (root->unsp_cpu__DOT__sb[n]!=reference.after.shift[n]) std::abort();
        unsigned modes=(reference.after.fir_move<<4)|(reference.after.fiq_enable<<3)|(reference.after.irq_enable<<2)|(reference.after.fiq<<1)|reference.after.irq;
        if (dut.modes!=modes || dut.cycles!=reference.cycles || dut.interrupt_entry!=reference.interrupt || accesses!=reference.accesses) {
            std::fprintf(stderr,"Case %u opcode %04x modes %u/%u cycles %u/%d accesses %zu/%zu\n",case_id,instruction,dut.modes,modes,dut.cycles,reference.cycles,accesses.size(),reference.accesses.size());
            for (auto [w,a,v]:reference.accesses) std::fprintf(stderr," ref %c %06x %04x\n",w?'w':'r',a,v);
            for (auto [w,a,v]:accesses) std::fprintf(stderr," rtl %c %06x %04x\n",w?'w':'r',a,v);
            std::exit(1);
        }
    }
};

