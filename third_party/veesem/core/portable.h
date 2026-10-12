// Adapted for the PDC Pocket port; see ../README.md and ../LICENSE.
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// Header-only storage used by the emulator on the SDK's musl-only runtime.
template <typename T, size_t N> struct FixedArray {
  T items[N];
  T& operator[](size_t i) { return items[i]; }
  const T& operator[](size_t i) const { return items[i]; }
  T* data() { return items; }
  const T* data() const { return items; }
  constexpr size_t size() const { return N; }
  T* begin() { return items; }
  T* end() { return items + N; }
  void fill(const T& value) { for (auto& item : items) item = value; }
};

template <typename T> struct BufferView {
  T* ptr;
  size_t count;
  T* data() const { return ptr; }
  size_t size() const { return count; }
  T* begin() const { return ptr; }
  T* end() const { return ptr + count; }
  T& operator[](size_t i) const { return ptr[i]; }
};

template <size_t N> class BitFlags {
  static_assert(N > 0 && N < 32);
  static constexpr uint32_t mask = (1u << N) - 1;
  uint32_t value_ = 0;
public:
  struct Reference {
    uint32_t& value;
    uint32_t bit;
    operator bool() const { return (value & bit) != 0; }
    Reference& operator=(bool set) {
      value = set ? value | bit : value & ~bit;
      return *this;
    }
  };
  BitFlags() = default;
  BitFlags(uint32_t value) : value_(value & mask) {}
  Reference operator[](size_t i) { return {value_, 1u << i}; }
  bool operator[](size_t i) const { return (value_ & (1u << i)) != 0; }
  bool any() const { return value_ != 0; }
  void reset() { value_ = 0; }
  uint32_t to_ulong() const { return value_; }
  BitFlags& operator=(uint32_t value) { value_ = value & mask; return *this; }
  BitFlags& operator&=(uint32_t value) { value_ &= value; return *this; }
};

template <bool Boolean> struct BitfieldType { using Type = unsigned; };
template <> struct BitfieldType<true> { using Type = bool; };

template <typename T> T Clamp(T value, T lo, T hi) {
  return value < lo ? lo : value > hi ? hi : value;
}
