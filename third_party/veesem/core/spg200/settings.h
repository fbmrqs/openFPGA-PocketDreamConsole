// Adapted for the PDC Pocket port; see ../README.md and ../LICENSE.
#include "core/portable.h"
#pragma once



struct PpuViewSettings {
  FixedArray<bool, 4> show_sprites_in_layer = {true, true, true, true};
  FixedArray<bool, 2> show_bg = {true, true};
  bool show_sprites = true;
};