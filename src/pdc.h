#pragma once

#include "core/spg200/spg200.h"
#include "core/spg200/spg200_io.h"

class Pdc final : public Spg200Io {
public:
  enum Button : unsigned {
    Up = 1, Down = 2, Left = 4, Right = 8,
    A = 16, B = 32, Pause = 64, L = 128, R = 256
  };
  explicit Pdc(const char* path);
  ~Pdc();
  Pdc(const Pdc&) = delete;
  Pdc& operator=(const Pdc&) = delete;
  bool Ready() const { return ready_; }
  void Reset();
  void RunFrame() { chip_.RunFrame(); }
  void SetButtons(unsigned buttons) { buttons_ = buttons; }
  BufferView<uint8_t> Picture() const { return chip_.GetPicture(); }
  BufferView<uint16_t> Audio() { return chip_.GetAudio(); }
  unsigned Bank() const { return bank_; }
  unsigned BankCount() const { return bank_count_; }
  unsigned BankSwitches() const { return bank_switches_; }
  Spg200& Chip() { return chip_; }

  void RunCycles(int) override {}
  unsigned GetAdc0() override { return 0; }
  unsigned GetAdc1() override { return 0; }
  unsigned GetAdc2() override { return 0; }
  unsigned GetAdc3() override { return 0; }
  Word GetPortA() override;
  Word GetPortB() override;
  Word GetPortC() override { return 0; }
  void SetPortA(Word value, Word mask) override;
  void SetPortB(Word, Word) override {}
  void SetPortC(Word, Word) override {}
  Word ReadRomCsb(Addr addr) override;
  Word ReadCsb1(Addr addr) override { return ReadRomCsb(addr); }
  Word ReadCsb2(Addr addr) override { return ReadRomCsb(addr); }
  Word ReadCsb3(Addr addr) override { return ReadRomCsb(addr); }
  void WriteRomCsb(Addr, Word) override {}
  void WriteCsb1(Addr, Word) override {}
  void WriteCsb2(Addr, Word) override {}
  void WriteCsb3(Addr, Word) override {}
  void TxUart(uint8_t) override {}
  void RxUartDone() override {}

private:
  static constexpr size_t BankBytes = 0x800000;
  void LoadBank(unsigned bank);
  FILE* file_ = nullptr;
  uint16_t* rom_ = nullptr;
  unsigned bank_ = ~0u;
  unsigned bank_count_ = 0;
  unsigned bank_switches_ = 0;
  unsigned buttons_ = 0;
  bool ready_ = false;
  Spg200 chip_;
};
