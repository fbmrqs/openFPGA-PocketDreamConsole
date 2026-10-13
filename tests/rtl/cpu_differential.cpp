#include "cpu_fixture.h"

int main() {
    Rig rig;Memory reference_memory;Cpu reference(reference_memory);Recorder recorder;reference.SetTrace(&recorder);
    std::mt19937 random{0x756e7370};
    std::vector<uint16_t> instructions;
    const int operations[]={0,1,2,3,4,6,8,9,10,11,12,13};
    for (int op:operations) for (int mode=0;mode<64;mode++) for (int rd=0;rd<8;rd++) for (int rs=0;rs<8;rs++) {
        if (rd==7 && mode<16) continue;
        if (mode>=16 && mode<24 && op!=9 && op!=13) continue;
        if (op==13 && (mode>=8 && mode<16 || mode==32 || mode==33 || mode==34 || mode>=36 && mode<56)) continue;
        instructions.push_back(uint16_t(op<<12|rd<<9|mode<<3|rs));
    }
    for (int op=0;op<15;op++) for (int mode=0;mode<16;mode++) for (int imm=0;imm<8;imm++) instructions.push_back(uint16_t(op<<12|7<<9|mode<<3|imm));
    for (int op1=0;op1<8;op1++) for (int rd=0;rd<8;rd++) for (int rs=0;rs<8;rs++) {
        if ((op1==0 || op1==4) && rd!=7 && rs!=7) instructions.push_back(uint16_t(0xf000|rd<<9|op1<<6|8|rs));
        if (op1==1 || op1==2 && rd==7) instructions.push_back(uint16_t(0xf000|rd<<9|op1<<6|rs));
        if ((op1==2 || op1==3 || op1==6 || op1==7) && rd!=7 && rs!=7) for (int n=0;n<16;n++) instructions.push_back(uint16_t(0xf000|rd<<9|op1<<6|n<<3|rs));
    }
    for (int imm:{0,1,2,3,4,5,8,9,12,14,32,37,40,48,56}) instructions.push_back(uint16_t(0xf140|imm));
    unsigned cases=0;
    for (uint16_t instruction:instructions) {
        for (int variant=0;variant<4;variant++) {
            rig.memory.words.clear();reference_memory.words.clear();
            reference.Reset();rig.reset();
            for (int n=0;n<8;n++) {
                uint16_t value=variant==0 ? uint16_t(random()) : variant==1 ? uint16_t(n&1 ? 0xffff : 0) : uint16_t(n&1 ? 0x8000 : 0x7fff);
                reference.regs_[n]=value;rig.dut.rootp->unsp_cpu__DOT__r[n]=value;
            }
            // Keep fetch separate from generated operand addresses, including PC aliases.
            reference.regs_[7]=variant==3 ? 0xffff : 0x4100;reference.regs_[6]=(reference.regs_[6]&0xffc0)|0x21;
            rig.dut.rootp->unsp_cpu__DOT__r[7]=reference.regs_[7];rig.dut.rootp->unsp_cpu__DOT__r[6]=reference.regs_[6];
            for (int n=0;n<3;n++) reference.sb_[n]=rig.dut.rootp->unsp_cpu__DOT__sb[n]=uint8_t(random()&15);
            reference.irq_=rig.dut.rootp->unsp_cpu__DOT__in_irq=bool(random()&1);
            reference.fiq_=rig.dut.rootp->unsp_cpu__DOT__in_fiq=bool(random()&1);
            reference.fir_mov_=rig.dut.rootp->unsp_cpu__DOT__fir_move=bool(random()&1);
            reference.irq_enable_=rig.dut.rootp->unsp_cpu__DOT__irq_enable=bool(random()&1);
            reference.fiq_enable_=rig.dut.rootp->unsp_cpu__DOT__fiq_enable=bool(random()&1);
            uint32_t pc=reference.GetCsPc();
            reference_memory.words[pc]=rig.memory.words[pc]=instruction;
            reference_memory.words[(pc+1)&0x3fffff]=rig.memory.words[(pc+1)&0x3fffff]=uint16_t(random());
            rig.dut.eval();reference.Step();rig.step(variant==1,variant==2);rig.compare(recorder,++cases,instruction);
        }
    }
    // Interrupt priority, nesting, and return state are independent of opcode coverage.
    for (unsigned signals=1;signals<512;signals++) {
        reference_memory.words.clear();rig.memory.words.clear();reference.Reset();rig.reset();
        reference.regs_[0]=rig.dut.rootp->unsp_cpu__DOT__r[0]=0x1700;
        reference.irq_enable_=reference.fiq_enable_=true;
        rig.dut.rootp->unsp_cpu__DOT__irq_enable=rig.dut.rootp->unsp_cpu__DOT__fiq_enable=1;
        for (int n=0;n<8;n++) reference.SetIrq(n,signals&(1<<n));
        reference.SetFiq(signals&256);rig.dut.irq=signals&255;rig.dut.fiq=(signals>>8)&1;
        rig.dut.eval();reference.Step();rig.step();rig.compare(recorder,++cases,0);
    }
    for (uint16_t invalid:{uint16_t(0x5000),uint16_t(0xd040),uint16_t(0xf000),uint16_t(0xf146)}) {
        rig.replay=nullptr;rig.memory.words.clear();rig.memory.words[0xfff7]=0x5000;rig.memory.words[0x5000]=invalid;
        rig.reset();rig.dut.run=1;
        for (int n=0;n<1000 && !rig.dut.fault;n++) rig.tick();
        if (!rig.dut.fault || rig.dut.fault_pc!=0x5000 || rig.dut.fault_opcode!=invalid) return 1;
        for (int n=0;n<16;n++) {rig.tick();if (rig.dut.bus_valid || rig.dut.retired) return 1;}
    }
    for(bool interrupt_test : {false,true}) {
        rig.replay=nullptr;rig.random.seed(0x4541524c);
        rig.memory.words.clear();reference_memory.words.clear();
        reference.Reset();reference_memory.words[0xfff7]=rig.memory.words[0xfff7]=0x5000;
        reference.Reset();rig.reset();
        reference.regs_[0]=rig.dut.rootp->unsp_cpu__DOT__r[0]=0x1800;
        reference.irq_enable_=reference.fiq_enable_=true;
        rig.dut.rootp->unsp_cpu__DOT__irq_enable=rig.dut.rootp->unsp_cpu__DOT__fiq_enable=1;
        for(unsigned pc=0x5000;pc<0x5200;pc++)reference_memory.words[pc]=rig.memory.words[pc]=0x0241;
        for(unsigned vector : {0xfff6u,0xfff8u})reference_memory.words[vector]=rig.memory.words[vector]=0x6000;
        reference_memory.words[0x6000]=rig.memory.words[0x6000]=0x9a98;
        rig.dut.prefetch_enable=1;unsigned clocks=0;
        for(unsigned step=0;step<128;step++) {
            bool irq=interrupt_test && step==32,fiq=interrupt_test && step==64;
            reference.SetIrq(0,irq);reference.SetFiq(fiq);rig.dut.irq=irq;rig.dut.fiq=fiq;
            unsigned pc=reference.GetCsPc();reference.Step();rig.dut.run=1;
            unsigned timeout=0;
            do {rig.tick();clocks++;if(++timeout>4000 || rig.dut.fault)return 1;}while(!rig.dut.retired);
            // An interrupt may discard exactly one speculative opcode read.
            if(recorder.interrupt && !rig.accesses.empty() &&
                !std::get<0>(rig.accesses.front()) && std::get<1>(rig.accesses.front())==pc)
                rig.accesses.erase(rig.accesses.begin());
            rig.compare(recorder,++cases,recorder.interrupt ? 0 : 0x0241);
            rig.accesses.clear();rig.dut.run=0;
            if(step!=127)for(unsigned gap=0;gap<2;gap++){rig.tick();clocks++;}
        }
        if(!interrupt_test && clocks>820)std::fprintf(stderr,"Performance note: continuous ALU stream costs %u clocks (target 820)\n",clocks);
        std::printf("Continuous CPU stream: %u clocks, interrupts %s\n",clocks,interrupt_test ? "enabled" : "absent");
        rig.dut.prefetch_enable=0;rig.dut.run=0;
        for(unsigned drain=0;rig.dut.bus_valid && drain<100;drain++)rig.tick();
        if(rig.dut.bus_valid || rig.pending)return 1;
    }
    std::printf("CPU differential: %u cases passed, randomized 0–7 clock bus latency and idle/early instruction prefetch\n",cases);
}
