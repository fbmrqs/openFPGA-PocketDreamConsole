#include "pdc.h"

#include <errno.h>
#include <string>
#include <vector>

class Recorder final : public Cpu::Trace {
public:
  Recorder(Pdc& board, FILE* output) : board_(board), output_(output) {
    bus_.reserve(64);
  }

  void Begin(const Cpu::State& state) override {
    before_ = state;
    bank_before_ = board_.Bank();
    bus_.clear();
  }
  void Read(Addr address, Word value) override {
    bus_.push_back({false, board_.Bank(), address, value});
  }
  void Write(Addr address, Word value) override {
    bus_.push_back({true, board_.Bank(), address, value});
    if (address >= 0x2800 && address < 0x4000) ++mmio_writes_[address - 0x2800];
  }

  void End(const Cpu::State& state, int cycles, bool interrupt) override {
    const Word opcode = interrupt ? 0 : bus_.at(0).value;
    const bool new_opcode = !interrupt && opcode_counts_[opcode]++ == 0;
    const bool bank_change = bank_before_ != board_.Bank();
    const bool retain = steps_ < 4096 || new_opcode || bank_change ||
                        (interrupt && interrupts_ < 16);
    cycles_ += cycles;
    if (interrupt) ++interrupts_;
    else ++instructions_;
    if (retain) {
      fprintf(output_, "{\"step\":%llu,\"kind\":\"%s\",\"bank_before\":%u,\"bank_after\":%u,\"opcode\":%u,\"cycles\":%d,\"before\":",
              steps_, interrupt ? "interrupt" : "instruction", bank_before_,
              board_.Bank(), opcode, cycles);
      WriteState(before_);
      fprintf(output_, ",\"after\":");
      WriteState(state);
      fprintf(output_, ",\"bus\":[");
      for (size_t i = 0; i < bus_.size(); ++i) {
        const auto& event = bus_[i];
        fprintf(output_, "%s[\"%c\",%u,%u,%u]", i ? "," : "",
                event.write ? 'w' : 'r', event.bank, event.address, event.value);
      }
      fprintf(output_, "]}\n");
      ++retained_;
    }
    ++steps_;
  }

  void Summary(FILE* output, int frames) {
    fprintf(output, "{\"schema\":1,\"frames\":%d,\"steps\":%llu,\"instructions\":%llu,\"interrupt_entries\":%llu,\"model_cycles\":%llu,\"retained_records\":%llu,\"final_bank\":%u,\"banks_loaded\":%u,\"selection\":\"first 4096 CPU steps; first occurrence of each opcode; all bank changes; first 16 interrupt entries\",\"register_order\":[\"SP\",\"R1\",\"R2\",\"R3\",\"R4\",\"BP\",\"SR\",\"PC\"],\"bus_event_order\":[\"read_or_write\",\"active_bank\",\"word_address\",\"word_value\"],\"limitations\":[\"software model execution, not physical PDC or FPGA execution\",\"modeled cycle counts are not measured hardware timing\",\"CPU-issued bus requests only; DMA and video/audio memory requests are excluded\",\"retained trace is contiguous for the first 4096 steps and sampled afterward\",\"opcode coverage does not establish all operand, flag, or instruction-version cases\"],\"opcode_counts\":{",
            frames, steps_, instructions_, interrupts_, cycles_, retained_,
            board_.Bank(), board_.BankSwitches());
    bool comma = false;
    for (unsigned i = 0; i < 65536; ++i) {
      if (!opcode_counts_[i]) continue;
      fprintf(output, "%s\"%04x\":%llu", comma ? "," : "", i, opcode_counts_[i]);
      comma = true;
    }
    fprintf(output, "},\"mmio_write_counts\":{");
    comma = false;
    for (unsigned i = 0; i < 0x1800; ++i) {
      if (!mmio_writes_[i]) continue;
      fprintf(output, "%s\"%04x\":%llu", comma ? "," : "", i + 0x2800, mmio_writes_[i]);
      comma = true;
    }
    fprintf(output, "}}\n");
    printf("frames=%d instructions=%llu interrupts=%llu records=%llu banks_loaded=%u\n",
           frames, instructions_, interrupts_, retained_, board_.BankSwitches());
  }

private:
  struct Event { bool write; unsigned bank; Addr address; Word value; };
  void WriteState(const Cpu::State& state) {
    fprintf(output_, "{\"regs\":[");
    for (unsigned i = 0; i < 8; ++i) fprintf(output_, "%s%u", i ? "," : "", state.regs[i]);
    fprintf(output_, "],\"shift\":[%u,%u,%u],\"irq_signals\":%u,\"fiq_signal\":%u,\"irq\":%u,\"fiq\":%u,\"irq_enable\":%u,\"fiq_enable\":%u,\"fir_move\":%u}",
            state.shift[0], state.shift[1], state.shift[2], state.irq_signals,
            state.fiq_signal, state.irq, state.fiq, state.irq_enable,
            state.fiq_enable, state.fir_move);
  }
  Pdc& board_;
  FILE* output_;
  Cpu::State before_{};
  unsigned bank_before_ = 0;
  std::vector<Event> bus_;
  unsigned long long steps_ = 0, instructions_ = 0, interrupts_ = 0;
  unsigned long long cycles_ = 0, retained_ = 0;
  unsigned long long opcode_counts_[65536]{};
  unsigned long long mmio_writes_[0x1800]{};
};

int main(int argc, char** argv) {
  if (argc != 4) {
    fprintf(stderr, "Usage: %s ROM frames output-prefix\n", argv[0]);
    return 2;
  }
  errno = 0;
  char* end;
  const long frames = strtol(argv[2], &end, 10);
  if (errno || *end || frames < 1 || frames > 36000) return 2;
  auto board = new Pdc(argv[1]);
  if (!board->Ready()) {
    fprintf(stderr, "Cannot load PDC ROM\n");
    delete board;
    return 1;
  }
  const std::string prefix = argv[3];
  FILE* trace = fopen((prefix + ".jsonl").c_str(), "wx");
  if (!trace) { perror("trace output"); delete board; return 1; }
  FILE* summary = fopen((prefix + ".json").c_str(), "wx");
  if (!summary) { perror("summary output"); fclose(trace); delete board; return 1; }
  auto recorder = new Recorder(*board, trace);
  board->Chip().SetCpuTrace(recorder);
  for (int frame = 0; frame < frames; ++frame) {
    unsigned buttons = 0;
    if (frame == 620 || frame == 621 || frame == 800 || frame == 801) buttons |= Pdc::A;
    if (frame >= 900 && frame < 960) buttons |= Pdc::Right;
    if (frame >= 1050 && frame < 1110) buttons |= Pdc::A;
    board->SetButtons(buttons);
    board->RunFrame();
    board->Audio();
  }
  board->Chip().SetCpuTrace(nullptr);
  recorder->Summary(summary, static_cast<int>(frames));
  const bool write_error = ferror(trace) || ferror(summary);
  const int trace_close = fclose(trace), summary_close = fclose(summary);
  delete recorder;
  delete board;
  return write_error || trace_close || summary_close ? 1 : 0;
}
