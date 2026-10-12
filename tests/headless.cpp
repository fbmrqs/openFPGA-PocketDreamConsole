#include "pdc.h"
#include <time.h>

static uint64_t Hash(const uint8_t* data, size_t bytes) {
  uint64_t hash = 14695981039346656037ull;
  for (size_t i = 0; i < bytes; ++i) hash = (hash ^ data[i]) * 1099511628211ull;
  return hash;
}

int main(int argc, char** argv) {
  if (argc < 2 || argc > 3) {
    fprintf(stderr, "Usage: %s ROM [frames]\n", argv[0]);
    return 2;
  }
  const int frames = argc == 3 ? atoi(argv[2]) : 600;
  if (frames <= 0 || frames > 36000) return 2;
  auto* pdc = new Pdc(argv[1]);
  if (!pdc->Ready()) {
    fprintf(stderr, "Cannot load a 16, 64, or 128 MiB PDC ROM: %s\n", argv[1]);
    delete pdc;
    return 1;
  }
  const clock_t start = clock();
  unsigned changed_frames = 0, colored_frames = 0, audio_samples = 0;
  uint64_t previous = 0;
  for (int f = 0; f < frames; ++f) {
    unsigned buttons = 0;
    if (f == 620 || f == 621 || f == 800 || f == 801) buttons |= Pdc::A;
    if (f >= 900 && f < 960) buttons |= Pdc::Right;
    if (f >= 1050 && f < 1110) buttons |= Pdc::A;
    pdc->SetButtons(buttons);
    pdc->RunFrame();
    const auto picture = pdc->Picture();
    const auto hash = Hash(picture.data(), picture.size());
    changed_frames += f > 0 && hash != previous;
    previous = hash;
    const auto* pixels = reinterpret_cast<const uint16_t*>(picture.data());
    bool colored = false;
    for (size_t i = 0; i < picture.size() / 2; ++i) colored |= (pixels[i] & 0x7fff) != 0;
    colored_frames += colored;
    const auto audio = pdc->Audio();
    for (auto sample : audio) audio_samples += sample != 0x8000;
    if (f % 60 == 0 || f == frames - 1) {
      printf("frame=%d bank=%u pc=%06x hash=%016llx colored=%d\n", f,
             pdc->Bank(), pdc->Chip().GetPc(), static_cast<unsigned long long>(hash), colored);
      fflush(stdout);
    }
  }
  printf("frames=%d changed=%u colored=%u nonzero_audio=%u banks_loaded=%u cpu_seconds=%.3f\n",
         frames, changed_frames, colored_frames, audio_samples, pdc->BankSwitches(),
         static_cast<double>(clock() - start) / CLOCKS_PER_SEC);
  delete pdc;
  return colored_frames > 0 && changed_frames > 0 ? 0 : 1;
}
