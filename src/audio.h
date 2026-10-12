#pragma once

#include "core/portable.h"

// The SPG audio clock is 281250 Hz. Integrate each 375/64-sample interval
// into one 48 kHz stereo pair, preserving the phase across video frames.
class AudioResampler {
public:
  BufferView<int16_t> Convert(BufferView<uint16_t> input) {
    size_t count = 0;
    for (size_t i = 0; i + 1 < input.size(); i += 2) {
      const int left = static_cast<int>(input[i]) - 32768;
      const int right = static_cast<int>(input[i + 1]) - 32768;
      unsigned remaining = 64;
      while (remaining) {
        const unsigned weight = remaining < 375 - phase_ ? remaining : 375 - phase_;
        left_sum_ += left * static_cast<int>(weight);
        right_sum_ += right * static_cast<int>(weight);
        phase_ += weight;
        remaining -= weight;
        if (phase_ == 375) {
          if (count + 2 > sizeof(output_) / sizeof(output_[0])) abort();
          output_[count++] = static_cast<int16_t>(left_sum_ / 375);
          output_[count++] = static_cast<int16_t>(right_sum_ / 375);
          phase_ = 0;
          left_sum_ = right_sum_ = 0;
        }
      }
    }
    return {output_, count};
  }
  void Reset() { phase_ = 0; left_sum_ = right_sum_ = 0; }
private:
  int16_t output_[4096];
  unsigned phase_ = 0;
  int32_t left_sum_ = 0, right_sum_ = 0;
};
