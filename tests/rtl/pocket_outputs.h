#include <array>
#include "Vpdc_framebuffer.h"
#include "Vpdc_framebuffer___024root.h"
#include "Vpdc_audio.h"

// Exercise the production framebuffer and its clock crossings. The responder
// uses the same conservative PSRAM transaction times as pocket_framebuffer.cpp.
struct PocketOutputs {
    Vpdc_framebuffer fb;
    Vpdc_audio audio;
    struct Transfer {unsigned remaining=0,address=0,data=0;bool write=false;};
    std::array<Transfer,2> pending{};
    std::array<std::array<uint16_t,115200>,2> ram{};
    uint64_t memory_phase=0,video_phase=0,audio_phase=0;
    static constexpr uint64_t system_edges=uint64_t(PDC_TEST_CLOCK_KHZ)*2000;
    uint64_t blocked=0;
    void report_stall() const {
        const auto& state=*fb.rootp;
        std::fprintf(stderr,"Display backlog: blocked=%llu writer=%u queued=%u pixels=%u scanout=%u beam=%u,%u memory_busy=%u\n",
            blocked,state.pdc_framebuffer__DOT__writer,state.pdc_framebuffer__DOT__queued_frames,
            state.pdc_framebuffer__DOT__pixel_level,state.pdc_framebuffer__DOT__scan_level,
            state.pdc_framebuffer__DOT__x_count,state.pdc_framebuffer__DOT__y_count,fb.memory_busy);
    }
    void step(Vpdc_system& system,bool high,unsigned frame) {
        const bool reset=system.reset || !system.ready || !system.rom_ready;
        audio.reset=reset;audio.sample_valid=system.audio_valid;
        audio.sample_left=system.audio_left;audio.sample_right=system.audio_right;
        audio.system_clk=high;audio.eval();
        audio_phase+=24576000;
        if(audio_phase>=system_edges){audio_phase-=system_edges;audio.audio_clk=!audio.audio_clk;audio.eval();}
        if(!reset && (audio.underflow || audio.overflow)) {
            std::fprintf(stderr,"Pocket audio starvation/overflow at frame %u: underflow=%u overflow=%u\n",frame,audio.underflow,audio.overflow);std::exit(1);
        }
        fb.reset=reset;fb.pixel_valid=system.pixel_valid;
        fb.pixel_x=system.pixel_x;fb.pixel_y=system.pixel_y;fb.pixel_data=system.pixel_data;
        fb.system_clk=high;fb.eval();
        memory_phase+=266481580;
        while(memory_phase>=system_edges) {
            memory_phase-=system_edges;
            bool rising=!fb.memory_clk;
            if(rising) {
                fb.memory_valid=0;
                for(unsigned chip=0;chip<2;chip++) {
                    auto& t=pending[chip];bool busy=t.remaining!=0;
                    if(busy && --t.remaining==0) {
                        if(t.write)ram[chip][t.address]=uint16_t(t.data);
                        else {fb.memory_valid|=1u<<chip;
                            fb.memory_q=(fb.memory_q&~(0xffffu<<(chip*16)))|(uint32_t(ram[chip][t.address])<<(chip*16));}
                    }
                    if((fb.memory_read|fb.memory_write)&(1u<<chip)) {
                        if((fb.memory_read&fb.memory_write)&(1u<<chip)){std::fprintf(stderr,"Simultaneous PSRAM read/write\n");std::exit(1);}
                        if(busy){std::fprintf(stderr,"Display request while PSRAM busy\n");std::exit(1);}
                        t.address=unsigned((fb.memory_address>>(chip*22))&0x3fffff);
                        if(t.address>=115200)std::abort();
                        t.write=fb.memory_write&(1u<<chip);t.data=(fb.memory_data>>(chip*16))&0xffff;
                        t.remaining=t.write ? 14+(t.address%3) : 15;
                    }
                }
                fb.memory_busy=(pending[0].remaining ? 1 : 0)|(pending[1].remaining ? 2 : 0);
            }
            fb.memory_clk=!fb.memory_clk;fb.eval();
        }
        video_phase+=24598300;
        if(video_phase>=system_edges){video_phase-=system_edges;fb.video_clk=!fb.video_clk;fb.eval();}
        if(high && !fb.pixel_ready)blocked++;
        if(!reset && (fb.underflow || fb.write_fault)) {
            std::fprintf(stderr,"Display fault: underflow=%u write_fault=%u\n",fb.underflow,fb.write_fault);std::exit(1);
        }
    }
};
