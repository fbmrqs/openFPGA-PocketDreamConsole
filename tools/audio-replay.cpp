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

static void word(FILE* f,unsigned value,unsigned bytes) {
    while(bytes--){std::fputc(value&255,f);value>>=8;}
}
int main(int argc,char** argv) {
    if(argc!=5)return 2;
    unsigned category=0,position=0;
    if(!std::strcmp(argv[2],"hair-salon"))position=1;
    else if(!std::strcmp(argv[2],"bunny-pinky")){category=Pdc::Right;position=5;}
    else if(!std::strcmp(argv[2],"beeline-2")){category=Pdc::Down;position=1;}
    else if(!std::strcmp(argv[2],"fun-match-2")){category=Pdc::Down;position=2;}
    else return 2;
    Pdc pdc(argv[1]);if(!pdc.Ready())return 2;
    AudioResampler resampler;std::vector<int16_t> audio;
    FILE* trace=std::fopen(argv[4],"w");if(!trace)return 2;
    std::fprintf(trace,"frame,pc,channel,wave,phase,target,accumulator,mode,pitch_control,pan\n");
    for(unsigned frame=0;frame<1600;frame++) {
        unsigned buttons=0;
        if(frame==560 || frame==561)buttons=category;
        if(frame==620 || frame==621 || frame==840 || frame==841 || frame==1000 || frame==1001)buttons=Pdc::A;
        for(unsigned item=0;item<position;item++)if(frame==700+item*20 || frame==701+item*20)buttons=Pdc::Down;
        pdc.SetButtons(buttons);pdc.RunFrame();auto samples=resampler.Convert(pdc.Audio());
        if(frame>=820)for(auto sample:samples)audio.push_back(sample);
        if(frame>=820)for(unsigned voice=0;voice<16;voice++) {
            auto& channel=pdc.Chip().spu_.channel_data_[voice];
            std::fprintf(trace,"%u,%06x,%u,%06x,%u,%u,%u,%04x,%04x,%04x\n",frame,pdc.Chip().GetPc(),voice,
                channel.wave_address,channel.phase,channel.target_phase,channel.phase_acc,
                channel.mode.raw,channel.pitch_bend_control.raw,channel.pan.raw);
        }
    }
    std::fclose(trace);FILE* wav=std::fopen(argv[3],"wb");if(!wav)return 2;
    unsigned bytes=unsigned(audio.size()*2);
    std::fwrite("RIFF",1,4,wav);word(wav,36+bytes,4);std::fwrite("WAVEfmt ",1,8,wav);
    word(wav,16,4);word(wav,1,2);word(wav,2,2);word(wav,48000,4);word(wav,192000,4);word(wav,4,2);word(wav,16,2);
    std::fwrite("data",1,4,wav);word(wav,bytes,4);
    for(auto sample:audio)word(wav,unsigned(uint16_t(sample)),2);
    std::fclose(wav);
    std::printf("Reference replay %s: %.2f seconds captured; menu route awaits scene confirmation\n",argv[2],audio.size()/96000.0);
}
