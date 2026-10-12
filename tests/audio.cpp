#include "audio.h"
#include <assert.h>

int main() {
  AudioResampler resampler;
  uint16_t source[750];
  for (size_t i = 0; i < 750; i += 2) {
    source[i] = 32768 + 1000;
    source[i + 1] = 32768 - 2000;
  }
  auto audio = resampler.Convert({source, 750});
  assert(audio.size() == 128);
  for (size_t i = 0; i < audio.size(); i += 2) {
    assert(audio[i] == 1000);
    assert(audio[i + 1] == -2000);
  }
  resampler.Reset();
  size_t samples = 0;
  for (size_t i = 0; i < 750; i += 2) {
    audio = resampler.Convert({source + i, 2});
    samples += audio.size();
    for (size_t j = 0; j < audio.size(); j += 2) {
      assert(audio[j] == 1000);
      assert(audio[j + 1] == -2000);
    }
  }
  assert(samples == 128);
  resampler.Reset();
  for (auto& value : source) value = 32768;
  audio = resampler.Convert({source, 750});
  for (auto value : audio) assert(value == 0);
  printf("Audio: 281250 -> 48000 Hz, stereo, silence, frame-boundary continuity OK\n");
}
