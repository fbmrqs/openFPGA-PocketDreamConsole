#include "of.h"
#include "pdc.h"
#include "audio.h"
#include <string.h>
#include <time.h>

int main(int argc, char** argv) {
  of_video_init();
  const of_video_mode_t mode = {320, 240, 640, OF_VIDEO_MODE_RGB555, 0};
  if (of_video_set_mode(&mode) != 0) {
    fprintf(stderr, "Pocket Dream Console requires RGB555 video.\n");
    return 1;
  }
  of_audio_init();
  const char* rom = argc > 1 ? argv[1] : "pdc30.rom";
  of_file_slot_register(4, rom);
  auto* pdc = new Pdc(rom);
  if (!pdc->Ready()) {
    fprintf(stderr, "Cannot read PDC ROM: %s\n", rom);
    delete pdc;
    return 1;
  }
  printf("Pocket Dream Console: %s, %u ROM banks\n", rom, pdc->BankCount());
  AudioResampler resampler;
  for (;;) {
    of_input_poll_p0();
    if (of_btn(OF_BTN_SELECT) && of_btn_pressed(OF_BTN_START)) {
      pdc->Reset();
      of_audio_init();
      resampler.Reset();
    }
    unsigned buttons = 0;
    if (of_btn(OF_BTN_UP)) buttons |= Pdc::Up;
    if (of_btn(OF_BTN_DOWN)) buttons |= Pdc::Down;
    if (of_btn(OF_BTN_LEFT)) buttons |= Pdc::Left;
    if (of_btn(OF_BTN_RIGHT)) buttons |= Pdc::Right;
    if (of_btn(OF_BTN_A)) buttons |= Pdc::A;
    if (of_btn(OF_BTN_B)) buttons |= Pdc::B;
    if (of_btn(OF_BTN_START)) buttons |= Pdc::Pause;
    if (of_btn(OF_BTN_L1)) buttons |= Pdc::L;
    if (of_btn(OF_BTN_R1)) buttons |= Pdc::R;
    pdc->SetButtons(buttons);
    pdc->RunFrame();
    const auto picture = pdc->Picture();
    memcpy(of_video_surface(), picture.data(), picture.size());
    of_video_flip();
    auto audio = resampler.Convert(pdc->Audio());
    size_t sent = 0;
    while (sent < audio.size() / 2) {
      const int count = of_audio_write(
          audio.data() + sent * 2,
          static_cast<int>(audio.size() / 2 - sent));
      if (count > 0) sent += static_cast<size_t>(count);
      else if (count < 0) {
        fprintf(stderr, "Pocket audio stream failed: %d\n", count);
        delete pdc;
        return 1;
      } else {
        const timespec delay = {0, 1000000};
        nanosleep(&delay, nullptr);
      }
    }
    of_video_wait_flip();
  }
}
