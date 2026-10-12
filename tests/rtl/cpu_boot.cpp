#include <fstream>
#include "cpu_fixture.h"
int main(int argc,char** argv) {
    if (argc!=2) return 2;
    std::ifstream input(argv[1]);if (!input) return 2;
    Rig rig;Recorder expected;unsigned count=0, opcode;
    while (input>>opcode) {
        unsigned interrupt,irq,fiq,value,mode,size;
        Cpu::State before{};
        input>>expected.cycles>>interrupt>>irq>>fiq;
        expected.interrupt=interrupt;
        for (auto& reg:before.regs) {input>>value;reg=value;}
        for (auto& shift:before.shift) {input>>value;shift=value;}
        input>>mode;
        for (auto& reg:expected.after.regs) {input>>value;reg=value;}
        for (auto& shift:expected.after.shift) {input>>value;shift=value;}
        unsigned after_mode;input>>after_mode>>size;
        expected.after.irq=after_mode&1;expected.after.fiq=after_mode&2;
        expected.after.irq_enable=after_mode&4;expected.after.fiq_enable=after_mode&8;
        expected.after.fir_move=after_mode&16;
        expected.accesses.clear();
        for (unsigned n=0;n<size;n++) {unsigned w,a,v;input>>w>>a>>v;expected.accesses.emplace_back(w,a,v);}
        if (!input) return 2;
        if (count==0) {rig.memory.words[0xfff7]=before.regs[7];rig.reset();}
        for (int n=0;n<8;n++) if (rig.dut.rootp->unsp_cpu__DOT__r[n]!=before.regs[n]) std::abort();
        rig.dut.irq=irq;rig.dut.fiq=fiq;rig.dut.eval();
        rig.replay=&expected.accesses;rig.step();rig.compare(expected,++count,opcode);
    }
    if (count!=4096) return 2;
    std::printf("%s: %u contiguous boot retirements matched\n",argv[1],count);
}
