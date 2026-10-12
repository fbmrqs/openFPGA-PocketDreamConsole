#include <array>
#include <cstdio>
#include <cstdlib>
#include <random>
#include <vector>
#include "core/portable.h"
#define private public
#define protected public
#include "pdc.h"
#undef private
#undef protected
#include "Vpdc_io.h"
#include "Vpdc_io___024root.h"

int main() {
    Pdc reference("pdc_pink.u2");
    if (!reference.Ready()) return 2;
    Vpdc_io dut;
    std::mt19937 random{0x54494d45};
    bool watchdog_seen=false;
    auto tick=[&] {dut.clk=0;dut.eval();dut.clk=1;dut.eval();watchdog_seen|=dut.watchdog_reset;};
    auto write=[&](unsigned address,uint16_t value) {
        reference.Chip().WriteWord(address,value);
        dut.address=address;dut.write_data=value;dut.access=1;dut.write=1;
        tick();dut.access=0;dut.write=0;
        while (dut.busy) tick();
    };
    reference.Reset();dut.final_bank=1;dut.reset=1;tick();dut.reset=0;
    for(unsigned n=0;n<64;n++) {
        dut.cycles=1;dut.advance=1;tick();dut.advance=0;
        unsigned clocks=0;while(dut.busy && clocks<16){tick();clocks++;}
        if(dut.busy || clocks>1){std::fprintf(stderr,"Quiet IO advance costs %u clocks (budget 1)\n",clocks);return 1;}
    }
    unsigned gpio_snapshots=0;
    for (unsigned internal=0;internal<2;internal++) {
        reference.Reset();dut.final_bank=1;dut.reset=1;tick();dut.reset=0;
        dut.pc=internal ? 0x2000 : 0x4000;
        reference.Chip().cpu_.regs_[6]=0;
        reference.Chip().cpu_.regs_[7]=dut.pc;
        for (unsigned iteration=0;iteration<256;iteration++) {
            unsigned buttons=random()&511;reference.SetButtons(buttons);dut.buttons=buttons;
            unsigned address=0x3d01+random()%15;
            uint16_t value=random();
            write(address,value);
            if (dut.bank!=reference.Bank()) {
                std::fprintf(stderr,"GPIO bank mismatch at %04x internal %u step %u: expected %u actual %u\n",address,internal,iteration,reference.Bank(),unsigned(dut.bank));return 1;
            }
            for (unsigned read_address=0x3d01;read_address<=0x3d0f;read_address++) {
                dut.address=read_address;dut.eval();
                if (dut.read_data!=reference.Chip().ReadWord(read_address)) {
                    std::fprintf(stderr,"GPIO register mismatch at %04x\n",read_address);return 1;
                }
            }
            gpio_snapshots++;
        }
    }
    reference.SetButtons(0);dut.buttons=0;dut.pc=0;
    std::printf("IO GPIO: %u writes, all three ports, input masks and PC-gated banking matched\n",gpio_snapshots);
    constexpr std::array<unsigned,16> controls={5,13,21,29,37,45,53,61,50,51,52,54,0,1,6,7};
    constexpr std::array<unsigned,8> fiqs={0,1,2,3,4,5,6,7};
    unsigned snapshots=0;
    for (unsigned timebase=0;timebase<16;timebase++) for (unsigned control:controls) for (unsigned source=0;source<8;source++) {
        reference.Reset();dut.final_bank=1;dut.reset=1;tick();dut.reset=0;
        write(0x3d10,timebase);write(0x3d13,control);write(0x3d17,source);
        write(0x3d12,0xffff);write(0x3d16,0xfffe);write(0x3d14,1);write(0x3d18,1);
        write(0x3d21,uint16_t(random()));write(0x3d2e,fiqs[source]);
        // Start beside a divider boundary so every rate and overflow is covered.
        unsigned count=(1u<<(random()%15))-1;
        reference.Chip().timer_.timer_clock_.div_counter_=count;
        dut.rootp->pdc_io__DOT__timer_divcounter=count;
        for (unsigned iteration=0;iteration<128;iteration++) {
            if (iteration==64) write(0x3d11,0);
            if (iteration%17==0) write(0x3d22,0xffff);
            unsigned elapsed=1+random()%255;
            reference.Chip().timer_.RunCycles(elapsed);
            dut.cycles=elapsed;dut.advance=1;tick();dut.advance=0;
            unsigned clocks=0;
            while (dut.busy && ++clocks<64) tick();
            if (dut.busy) {std::fprintf(stderr,"IO timer did not finish\n");return 1;}
            for (unsigned address:{0x3d10,0x3d12,0x3d13,0x3d14,0x3d16,0x3d17,0x3d18,0x3d21,0x3d22}) {
                dut.address=address;dut.eval();unsigned expected=reference.Chip().ReadWord(address);
                if (dut.read_data!=expected) {
                    std::fprintf(stderr,"IO timebase %u control %u source %u step %u register %04x expected %04x actual %04x\n",timebase,control,source,iteration,address,expected,dut.read_data);return 1;
                }
            }
            for (unsigned irq=0;irq<8;irq++) if (bool((dut.irq>>irq)&1)!=reference.Chip().cpu_.irq_signal_[irq]) {
                std::fprintf(stderr,"IO IRQ %u mismatch\n",irq);return 1;
            }
            // The reference leaves its cached FIQ signal stale after status clears.
            // Check the selected active source directly from its public registers.
            unsigned active=reference.Chip().ReadWord(0x3d22)&reference.Chip().ReadWord(0x3d21);
            bool expected_fiq=source==2 ? active&0x0800 : source==3 ? active&0x0400 : false;
            if (bool(dut.fiq)!=expected_fiq) {std::fprintf(stderr,"IO FIQ mismatch\n");return 1;}
            snapshots++;
        }
    }
    for (unsigned divider=0;divider<4;divider++) for (unsigned channel=0;channel<4;channel++) for (unsigned enable=0;enable<2;enable++) {
        reference.Reset();dut.reset=1;tick();dut.reset=0;
        write(0x3d21,0xffff);write(0x3d2e,6);
        unsigned control=1|(divider<<2)|(channel<<4)|(enable<<9);
        for (unsigned iteration=0;iteration<128;iteration++) {
            if (iteration%17==0) write(0x3d25,control|0x3000);
            unsigned elapsed=1+random()%16;
            reference.Chip().adc_.RunCycles(elapsed);
            reference.Chip().timer_.RunCycles(elapsed);
            dut.cycles=elapsed;dut.advance=1;tick();dut.advance=0;
            while (dut.busy) tick();
            for (unsigned address:{0x3d25,0x3d27,0x3d22}) {
                dut.address=address;dut.eval();unsigned expected=reference.Chip().ReadWord(address);
                if (dut.read_data!=expected) {
                    std::fprintf(stderr,"IO ADC divider %u channel %u enable %u step %u register %04x expected %04x actual %04x\n",divider,channel,enable,iteration,address,expected,dut.read_data);return 1;
                }
            }
            if (bool((dut.irq>>3)&1)!=reference.Chip().cpu_.irq_signal_[3] || bool(dut.fiq)!=reference.Chip().cpu_.fiq_signal_) {
                std::fprintf(stderr,"IO ADC interrupt mapping mismatch\n");return 1;
            }
            snapshots++;
        }
    }
    unsigned uart_snapshots=0;
    for (unsigned baud:{0u,1u,32768u,65535u}) for (unsigned mode=0;mode<2;mode++) for (unsigned enabled=0;enabled<2;enabled++) {
        reference.Reset();dut.reset=1;tick();dut.reset=0;
        write(0x3d21,0xffff);write(0x3d2e,5);
        write(0x3d33,baud&255);write(0x3d34,baud>>8);
        write(0x3d30,(enabled?0x80:0)|(mode?0x20:0)|2);write(0x3d35,0xa5);
        if (dut.rootp->pdc_io__DOT__tx_clock!=reference.Chip().uart_.tx_counter_) {
            std::fprintf(stderr,"UART duration mismatch for baud %u mode %u\n",baud,mode);return 1;
        }
        unsigned duration=16*(65536-baud)*(mode?11:10);
        for (unsigned elapsed=0;elapsed<=duration+255;elapsed+=255) {
            reference.Chip().uart_.RunCycles(255);reference.Chip().timer_.RunCycles(255);
            dut.cycles=255;dut.advance=1;tick();dut.advance=0;while (dut.busy) tick();
            dut.address=0x3d31;dut.eval();
            if (dut.read_data!=reference.Chip().ReadWord(0x3d31) ||
                dut.rootp->pdc_io__DOT__tx_clock!=reference.Chip().uart_.tx_counter_ ||
                bool((dut.irq>>3)&1)!=reference.Chip().cpu_.irq_signal_[3]) {
                std::fprintf(stderr,"UART countdown/IRQ mismatch baud %u mode %u elapsed %u\n",baud,mode,elapsed);return 1;
            }
            uart_snapshots++;
        }
        write(0x3d30,0);write(0x3d31,3);
        dut.address=0x3d31;dut.eval();
        if (dut.read_data!=reference.Chip().ReadWord(0x3d31)) return 1;
    }
    std::printf("IO UART: %u duration/countdown/status/IRQ snapshots across baud rates and frame lengths matched\n",uart_snapshots);
    unsigned watchdog_snapshots=0;
    for (unsigned enabled=0;enabled<2;enabled++) for (unsigned clear:{0x55aau,0x55abu}) for (unsigned seed:{0u,1u,127u,255u,20250000u}) {
        reference.Reset();dut.reset=1;tick();dut.reset=0;
        write(0x3d20,enabled?0x8000:0);
        reference.Chip().watchdog_.clock_.counter_=seed;
        dut.rootp->pdc_io__DOT__watchdog_clock=seed;
        write(0x3d24,clear);
        for (unsigned n=0;n<128;n++) {
            unsigned elapsed=1+random()%255;
            reference.Chip().cpu_.regs_[1]=0x1234;
            reference.Chip().watchdog_.RunCycles(elapsed);
            bool expected_reset=reference.Chip().cpu_.regs_[1]==0;
            watchdog_seen=false;dut.cycles=elapsed;dut.advance=1;tick();dut.advance=0;while (dut.busy) tick();
            if (watchdog_seen!=expected_reset || int(dut.rootp->pdc_io__DOT__watchdog_clock)!=reference.Chip().watchdog_.clock_.counter_) {
                std::fprintf(stderr,"Watchdog countdown/reset mismatch enabled %u clear %04x seed %u step %u\n",enabled,clear,seed,n);return 1;
            }
            watchdog_snapshots++;
        }
    }
    std::printf("IO watchdog: %u countdown/reset/clear snapshots matched\n",watchdog_snapshots);
    for (unsigned external=0;external<4;external++) {
        reference.Reset();dut.reset=1;tick();dut.reset=0;
        write(0x3d21,0xffff);write(0x3d2e,5);
        reference.Chip().irq_.SetExt1Irq(external&1);
        reference.Chip().irq_.SetExt2Irq(external&2);
        dut.rootp->pdc_io__DOT__irq_status=((external&1)?0x0200:0)|((external&2)?0x1000:0);
        dut.eval();
        if (bool((dut.irq>>5)&1)!=reference.Chip().cpu_.irq_signal_[5] || bool(dut.fiq)!=reference.Chip().cpu_.fiq_signal_) {
            std::fprintf(stderr,"IO external interrupt mapping mismatch\n");return 1;
        }
    }
    std::printf("IO timers: %u register/IRQ snapshots across dividers, timebases, overflow, counter reset, ADC and FIQ selection matched\n",snapshots);
}
