// Adapted for the PDC Pocket port; see ../README.md and ../LICENSE.
#include "core/portable.h"
#pragma once




class Adpcm {
public:
  Adpcm() = default;
  void Reset();
  int16_t Decode(uint8_t nibble);

private:
  int8_t step_index_ = 0;
  int16_t last_sample_ = 0;
};