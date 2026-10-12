#include "pdc.h"

Pdc::Pdc(const char* path) : chip_(VideoTiming::NTSC, *this) {
  file_ = fopen(path, "rb");
  if (!file_ || fseek(file_, 0, SEEK_END) != 0) return;
  const long bytes = ftell(file_);
  // MAME ignores the unused upper half of the PDC100 physical dump.
  if (bytes == 0x8000000 || bytes == 0x4000000) bank_count_ = 8;
  else if (bytes == 0x1000000) bank_count_ = 2;
  else return;
  rom_ = static_cast<uint16_t*>(malloc(BankBytes));
  if (!rom_) return;
  ready_ = true;
  Reset();
}

Pdc::~Pdc() {
  if (file_) fclose(file_);
  free(rom_);
}

void Pdc::LoadBank(unsigned bank) {
  bank &= bank_count_ - 1;
  if (bank == bank_) return;
  if (fseek(file_, static_cast<long>(bank * BankBytes), SEEK_SET) != 0 ||
      fread(rom_, 1, BankBytes, file_) != BankBytes) {
    die("Cannot read PDC ROM bank");
  }
  // MAME swaps these dumps into its big-endian bus: source words are LE.
  auto* bytes = reinterpret_cast<uint8_t*>(rom_);
  for (size_t i = 0; i < BankBytes; i += 2) {
    rom_[i / 2] = static_cast<uint16_t>(bytes[i] | (bytes[i + 1] << 8));
  }
  bank_ = bank;
  ++bank_switches_;
}

void Pdc::Reset() {
  if (!ready_) return;
  buttons_ = 0;
  LoadBank(bank_count_ - 1);
  chip_.Reset();
}

Word Pdc::ReadRomCsb(Addr addr) {
  return rom_[addr & 0x3fffff];
}

void Pdc::SetPortA(Word value, Word) {
  // Matches MAME's PDC workaround: only bank from code in internal RAM,
  // and ignore initialization writes with no high-byte bits set.
  if (ready_ && chip_.GetPc() < 0x2800 && (value & 0xff00)) {
    LoadBank(value & 7);
  }
}

Word Pdc::GetPortA() {
  return ((buttons_ & L) ? 0x0100 : 0) | ((buttons_ & R) ? 0x1000 : 0);
}

Word Pdc::GetPortB() {
  return (buttons_ & (Up | Down | Left | A | B | Pause)) |
         ((buttons_ & Right) ? 0x0080 : 0);
}
