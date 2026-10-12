// Adapted for the PDC Pocket port; see ../README.md and ../LICENSE.
#include "core/portable.h"
#pragma once

#include "core/common.h"

class Random {
public:
  void Set(Word value);
  Word Get();

private:
  void UpdateSeed();
  Word seed_ = 0;
};