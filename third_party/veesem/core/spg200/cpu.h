// Adapted for the PDC Pocket port; see ../README.md and ../LICENSE.
#include "core/portable.h"
#pragma once





#include "core/common.h"

class BusInterface;

class Cpu {
public:
  Cpu(BusInterface& bus);

  int Step();
  void SetIrq(int irq, bool value);
  void SetFiq(bool value);

  void Reset();

  Word GetDs();
  void SetDs(Word val);
  Addr GetCsPc();

  void PrintRegisterState();

#ifdef PDC_CPU_TRACE
  struct State {
    FixedArray<uint16_t, 8> regs;
    FixedArray<uint8_t, 3> shift;
    unsigned irq_signals;
    bool fiq_signal, irq, fiq, irq_enable, fiq_enable, fir_move;
  };
  class Trace {
  public:
    virtual ~Trace() = default;
    virtual void Begin(const State& state) = 0;
    virtual void Read(Addr address, Word value) = 0;
    virtual void Write(Addr address, Word value) = 0;
    virtual void End(const State& state, int cycles, bool interrupt) = 0;
  };
  void SetTrace(Trace* trace) { trace_ = trace; }
#endif

private:
#ifdef PDC_CPU_TRACE
  State GetState() const;
  int Execute();
  Trace* trace_ = nullptr;
  bool trace_interrupt_ = false;
#endif
  Word ReadBus(Addr address);
  void WriteBus(Addr address, Word value);
  void AluOp(Word& save, Word val1, Word val2, int alu_op, bool update_flags);
  void UpdateNz(uint32_t result);
  void UpdateNzsc(uint32_t result, int32_t result_signed);
  bool CheckBranch(int branchop);
  bool CheckInterrupts();

  Word ReadWordFromPc();
  void PushWord(Word& sp, Word val);
  Word PopWord(Word& sp);

  void SetCsPc(Addr val);

  BusInterface& bus_;

  FixedArray<uint16_t, 8> regs_;
  FixedArray<uint8_t, 3> sb_;  // 0 - normal, 1 - irq, 2 - fiq (fiq ? 2 : irq)

  BitFlags<8> irq_signal_;
  bool fiq_signal_ = false;

  bool irq_, fiq_;
  bool irq_enable_, fiq_enable_;
  bool fir_mov_;
};
