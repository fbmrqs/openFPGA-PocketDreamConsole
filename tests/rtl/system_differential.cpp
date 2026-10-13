#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include "core/portable.h"
#include "core/common.h"
#define private public
#include "pdc.h"
#undef private
#include "audio.h"
#include "Vpdc_system.h"
#include "Vpdc_system___024root.h"

#ifndef PDC_TEST_CLOCK_KHZ
#define PDC_TEST_CLOCK_KHZ 196608
#endif
#ifdef PDC_POCKET_OUTPUTS
#include "pocket_outputs.h"
#endif
int main(int argc,char** argv) {
    if (argc<3 || argc>5) return 2;
    const bool videojet=argc==5 && std::strcmp(argv[4],"videojet")==0;
    if(argc==5 && !videojet)return 2;
    const bool paced=argc>=4 && std::strcmp(argv[3],"paced")==0;
    const bool native_latency=paced || (argc>=4 && std::strcmp(argv[3],"native-latency")==0);
    const unsigned limit=unsigned(std::strtoul(argv[2],nullptr,10));
    Pdc reference(argv[1],videojet);if (!reference.Ready()) return 2;
    FILE* file=std::fopen(argv[1],"rb");if (!file) return 2;
    const size_t words=size_t(reference.BankCount())*0x400000;
    std::vector<uint16_t> rom(words);if (std::fread(rom.data(),2,words,file)!=words) return 2;std::fclose(file);
    Vpdc_system dut;dut.videojet_controls=videojet;dut.pixel_ready=1;dut.rom_line_valid=native_latency;AudioResampler resampler;
    uint32_t startup_crc=0xffffffff;
    for(size_t n=words-0x400000;n<words;n++)for(unsigned byte=0;byte<2;byte++) {
        startup_crc^=uint8_t(rom[n]>>(byte*8));
        for(unsigned bit=0;bit<8;bit++)startup_crc=(startup_crc>>1)^(startup_crc&1 ? 0xedb88320u : 0u);
    }
    dut.graphics_hash=reference.BankCount()==1 && (startup_crc^0xffffffff)==0xcea549ad;
    #ifdef PDC_POCKET_OUTPUTS
    PocketOutputs outputs;
    #endif
    std::vector<int16_t> expected_audio;size_t audio_position=0;
    std::vector<uint16_t> picture(320*240);
    unsigned frames=0,pixels=0,maximum_backlog=0;uint64_t instructions=0,clocks=0;
    bool pending=false;unsigned delay=0;uint32_t address=0;
    uint32_t line_tag=~0u;uint64_t rom_reads=0,bursts=0,frame_start=0,max_frame_clocks=0;
    auto buttons=[&](unsigned frame) {
        if (frame==620 || frame==621 || frame==800 || frame==801) return unsigned(Pdc::A);
        if (frame>=900 && frame<960) return unsigned(Pdc::Right);
        if (frame>=1050 && frame<1110) return unsigned(Pdc::A);
        return 0u;
    };
    auto tick=[&] {
        dut.clk=0;dut.eval();
        #ifdef PDC_POCKET_OUTPUTS
        outputs.step(dut,false,frames);dut.pixel_ready=outputs.fb.pixel_ready;dut.eval();
        #endif
        dut.rom_ack=0;
        if (dut.rom_request) {
            if (!pending) {pending=true;address=dut.rom_address;delay=address&3;
                rom_reads++;
                if (native_latency) {
                    delay=2;
                    if ((address>>4)!=line_tag) {line_tag=address>>4;delay+=126;bursts++;}
                }}
            if (address!=dut.rom_address) {std::fprintf(stderr,"Unstable ROM bus\n");std::exit(1);}
            if (delay--==0) {
                dut.rom_ack=1;dut.rom_data=rom.at(address);pending=false;
                for (unsigned n=0;n<8;n++) dut.rom_line_data[n]=
                    uint32_t(rom.at((address&~15u)+n*2)) | uint32_t(rom.at((address&~15u)+n*2+1))<<16;
            }
        } else if (pending && !dut.reset) std::abort();
        #ifdef PDC_POCKET_OUTPUTS
        outputs.step(dut,true,frames);
        #endif
        dut.clk=1;dut.eval();clocks++;
        if (paced) {
            const unsigned credit=dut.rootp->pdc_system__DOT__credit;
            const unsigned backlog=credit<(1u<<17) ? credit : 0;
            if (backlog>maximum_backlog) maximum_backlog=backlog;
            if (dut.cycle_overflow) {
#ifdef PDC_POCKET_OUTPUTS
                outputs.report_stall();
#endif
std::fprintf(stderr,"Real-time cycle budget overflow at frame %u\n",frames);std::exit(1);}
        }
        if (dut.cpu_fault) {std::fprintf(stderr,"CPU fault %06x:%04x\n",dut.fault_pc,dut.fault_opcode);std::exit(1);}
        if (dut.retired) {
            const unsigned pc_before=(unsigned(reference.Chip().cpu_.regs_[6]&63)<<16)|reference.Chip().cpu_.regs_[7];
            int cycles=reference.Chip().cpu_.Step();instructions++;
            for (unsigned n=0;n<8;n++) {
                uint16_t value=uint16_t(dut.registers[n/2]>>(16*(n%2)));
                if (value!=reference.Chip().cpu_.regs_[n]) {
                    std::fprintf(stderr,"%s instruction %llu frame %u pc %06x register %u expected %04x actual %04x\n",argv[1],instructions,frames,pc_before,n,reference.Chip().cpu_.regs_[n],value);std::exit(1);
                }
            }
            if (reference.Bank()!=dut.bank) {std::fprintf(stderr,"Bank mismatch\n");std::exit(1);}
            auto& chip=reference.Chip();chip.adc_.RunCycles(cycles);chip.uart_.RunCycles(cycles);
            chip.timer_.RunCycles(cycles);chip.spu_.RunCycles(cycles);chip.ppu_.RunCycles(cycles);
            auto audio=resampler.Convert(chip.GetAudio());
            for (size_t n=0;n<audio.size();n++) expected_audio.push_back(audio[n]);
        }
        if (dut.audio_valid) {
            if (audio_position+2>expected_audio.size()) {std::fprintf(stderr,"Unexpected native audio at frame %u\n",frames);std::exit(1);}
            if (int16_t(dut.audio_left)!=expected_audio[audio_position] || int16_t(dut.audio_right)!=expected_audio[audio_position+1]) {
                std::fprintf(stderr,"Audio mismatch frame %u at sample %zu expected %d,%d actual %d,%d\n",frames,audio_position/2,expected_audio[audio_position],expected_audio[audio_position+1],int16_t(dut.audio_left),int16_t(dut.audio_right));
                for (unsigned ch=0;ch<16;ch++) {
                    auto& r=reference.Chip().spu_.channel_data_[ch];
                    std::fprintf(stderr,"ch%u wave=%06x phase=%05x acc=%05x mode=%04x pan=%04x env=%04x prev=%04x cur=%04x\n",ch,r.wave_address,r.phase,r.phase_acc,r.mode.raw,r.pan.raw,r.envelope_data.raw,r.wave_data_0,r.wave_data);
                }std::exit(1);
            }
            audio_position+=2;
        }
        if (dut.pixel_valid) {
            picture[dut.pixel_y*320+dut.pixel_x]=dut.pixel_data;pixels++;
        }
        if (dut.frame_done) {
            if (pixels!=320*240) {std::fprintf(stderr,"Incomplete frame %u pixels %u\n",frames,pixels);std::exit(1);}
            for (unsigned n=0;n<picture.size();n++) {
                uint16_t expected=reference.Chip().ppu_.framebuffer_[n/320][n%320].raw;
                if (picture[n]!=expected) {std::fprintf(stderr,"Frame %u pixel (%u,%u) expected %04x actual %04x\n",frames,n%320,n/320,expected,picture[n]);std::exit(1);}
            }
            uint64_t frame_clocks=clocks-frame_start;frame_start=clocks;
            if (frames>0 && frame_clocks>max_frame_clocks) max_frame_clocks=frame_clocks;
            frames++;pixels=0;dut.buttons=buttons(frames);reference.SetButtons(buttons(frames));
            if (frames%10==0) {std::printf("%s: %u frames, %llu instructions, %llu FPGA clocks matched\n",argv[1],frames,instructions,clocks);std::fflush(stdout);}
            if (audio_position==expected_audio.size()) {expected_audio.clear();audio_position=0;}
        }
    };
    dut.reset=1;dut.rom_ready=0;dut.final_bank=reference.BankCount()-1;tick();tick();
    dut.reset=0;dut.rom_ready=1;
    while (frames<limit && clocks<100000000000ull) tick();
    if (frames!=limit) return 1;
    std::printf("Memory profile: %llu ROM halfword reads, %llu SDRAM bursts, maximum steady frame %llu clocks (%.3f ms at %.3f MHz)\n",rom_reads,bursts,max_frame_clocks,double(max_frame_clocks)/PDC_TEST_CLOCK_KHZ,PDC_TEST_CLOCK_KHZ/1000.0);
    constexpr uint64_t frame_budget=uint64_t(1716)*262*uint64_t(PDC_TEST_CLOCK_KHZ)*1000/27000000;
    if (native_latency && !paced && limit>=1800 && max_frame_clocks>frame_budget) {
        std::fprintf(stderr,"Native frame deadline exceeded: %llu clocks, budget %llu\n",max_frame_clocks,frame_budget);return 1;
    }
    if (paced) std::printf("Real-time pacing: maximum modeled cycle backlog %u\n",maximum_backlog);
    std::printf("System differential %s: %u frames matched CPU, banking, video and stereo audio\n",argv[1],frames);
}
