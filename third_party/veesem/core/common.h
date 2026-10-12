// Adapted for the PDC Pocket port; see ../README.md and ../LICENSE.
#pragma once







#include "portable.h"

[[noreturn]] inline void die(const char* msg,
    const char* file = __builtin_FILE(), int line = __builtin_LINE()) {
  fprintf(stderr, "%s(%d): %s\n", file, line, msg);
  abort();
}

using Word = uint16_t;
using Addr = uint32_t;  // should really be 22-bit

template <size_t Bits>
inline int sext(unsigned value) {
  const unsigned sign = (1 << (Bits - 1));
  return (value ^ sign) - sign;
}

template <size_t Bits>
inline unsigned rotl(unsigned val, unsigned step) {
  const unsigned mask = ((1 << Bits) - 1);
  return ((val << step) | (val >> (Bits - step))) & mask;
}

template <size_t Bits>
inline unsigned rotr(unsigned val, unsigned step) {
  const unsigned mask = ((1 << Bits) - 1);
  return ((val >> step) | (val << (Bits - step))) & mask;
}

class SimpleConfigurableClock {
public:
  SimpleConfigurableClock(int a, int b) : counter_(a), a_(a), b_(b) {}
  inline bool Tick(int cycles) {
    counter_ -= b_ * cycles;
    if (counter_ <= 0) {
      counter_ += a_;
      return true;
    }
    return false;
  }

  inline void Reset() { counter_ = a_; }

protected:
  int counter_;
  const int a_;
  const int b_;
};

template <int A, int B = 1>
class SimpleClock {
public:
  SimpleClock() = default;

  inline bool Tick(int cycles) {
    counter_ -= B * cycles;
    if (counter_ <= 0) {
      counter_ += A;
      return true;
    }
    return false;
  }

  inline void Reset() { counter_ = A; }

protected:
  int counter_ = A;
};

template <int A, int B = 1>
class DivisibleClock : public SimpleClock<A, B> {
public:
  DivisibleClock() = default;

  inline bool Tick(int cycles) {
    auto ret = SimpleClock<A, B>::Tick(cycles);
    if (ret) {
      div_counter_++;
    }
    return ret;
  }

  inline void Reset() {
    SimpleClock<A, B>::Reset();
    ClearDivCounter();
  }

  inline bool GetDividedTick(unsigned div) { return (div_counter_ & ((1 << div) - 1)) == 0; }

  inline void ClearDivCounter() { div_counter_ = 0; }

private:
  int div_counter_ = 0;
};

template <size_t Position, size_t Size>
struct Bitfield {
  static constexpr Word Maximum = (1 << Size) - 1;
  static constexpr Word Mask = Maximum << Position;
  using Type = typename BitfieldType<Size == 1>::Type;
  Word value;

  inline __attribute__((always_inline)) constexpr operator Type() const {
    return static_cast<Type>((value >> Position) & Maximum);
  }

  inline __attribute__((always_inline)) constexpr Bitfield& operator=(const Type v) {
    value = (value & ~Mask) | ((static_cast<Word>(v) & Maximum) << Position);
    return *this;
  }

  inline __attribute__((always_inline)) constexpr Bitfield& operator+=(const Type v) {
    value = (value & ~Mask) | ((static_cast<Word>(*this + v) & Maximum) << Position);
    return *this;
  }

  inline __attribute__((always_inline)) constexpr Bitfield& operator-=(const Type v) {
    value = (value & ~Mask) | ((static_cast<Word>(*this - v) & Maximum) << Position);
    return *this;
  }

  inline __attribute__((always_inline)) constexpr Bitfield& operator++() { return *this += 1; }

  inline __attribute__((always_inline)) constexpr Bitfield& operator--() { return *this -= 1; }

  inline __attribute__((always_inline)) constexpr Bitfield operator++(int) {
    Bitfield tmp(*this);
    operator++();
    return tmp;
  }

  inline __attribute__((always_inline)) constexpr Bitfield operator--(int) {
    Bitfield tmp(*this);
    operator--();
    return tmp;
  }
};